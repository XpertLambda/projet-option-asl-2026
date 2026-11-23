#!/usr/bin/env bash
# Contrôle de cohérence de l'application sur un cluster (docs/architecture.md, section 6, étape 4).
# Sur la table témoin events, vérifie :
#   - les pods sont Ready et PostgreSQL répond ;
#   - count(*) > 0 ;
#   - aucun id en double ;
#   - ts croissant avec l'id ;
#   - aucun écart de plus de 5 s entre deux lignes consécutives ;
#   - si --t0 est donné : max(ts) inférieur ou égal à t0.
# Un trou d'ids sans ligne n'est PAS une anomalie (docs/preuves/J2/ecart-id-lignes.md) : la
# continuité se juge sur ts.
# Dernière ligne : "VERIFY cluster=... count=... max_id=... max_ts=... gaps_gt5s=... dup_ids=...
# ts_not_increasing=... t0_check=ok|ko|na status=ok|incoherent". Code de sortie 1 si incohérent.
# Usage : ./scripts/verify.sh <cluster-a|cluster-b> [--t0 <secondes depuis l'epoch>]
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

CL=""; T0=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --t0) [[ $# -ge 2 ]] || die "--t0 demande une valeur"; T0="$2"; shift 2;;
    cluster-a|cluster-b) CL="$1"; shift;;
    *) die "usage : $0 <cluster-a|cluster-b> [--t0 <secondes depuis l'epoch>]";;
  esac
done
[[ -n "$CL" ]] || die "usage : $0 <cluster-a|cluster-b> [--t0 <secondes depuis l'epoch>]"
[[ -z "$T0" || "$T0" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--t0 doit être un nombre de secondes (epoch), reçu '$T0'"

K=(kubectl --kubeconfig "$(kubeconfig "$CL")")
log "Contrôle de cohérence sur $CL"
"${K[@]}" -n app get pods --no-headers | sed 's/^/   /'
"${K[@]}" -n app wait --for=condition=Ready pod --all --timeout=10s >/dev/null || die "pods de l'application non Ready"

SQL="SELECT count(*), coalesce(max(id), 0),
  coalesce(to_char(max(ts) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'), ''),
  coalesce(extract(epoch from max(ts)), 0),
  count(*) - count(DISTINCT id),
  (SELECT count(*) FROM (SELECT ts, lag(ts) OVER (ORDER BY id) AS p FROM events) a WHERE ts < p),
  (SELECT count(*) FROM (SELECT ts - lag(ts) OVER (ORDER BY id) AS d FROM events) b WHERE d > interval '5 seconds')
FROM events"
row="$("${K[@]}" -n app exec -i postgres-0 -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -At -F "|"' <<<"$SQL")" \
  || die "PostgreSQL ne répond pas sur $CL"
IFS='|' read -r count maxid maxts maxepoch dups unordered gaps <<<"$row"
info "lignes : $count, dernier id : $maxid, dernier ts : $maxts"
info "ids en double : $dups ; ts non croissant avec l'id : $unordered ; écarts de plus de 5 s : $gaps"

reasons=()
(( count > 0 ))      || reasons+=("aucune ligne restaurée")
(( dups == 0 ))      || reasons+=("$dups id en double")
(( unordered == 0 )) || reasons+=("$unordered ligne(s) avec ts décroissant")
(( gaps == 0 ))      || reasons+=("$gaps écart(s) de plus de 5 s")
t0check=na
if [[ -n "$T0" ]]; then
  if awk -v a="$maxepoch" -v b="$T0" 'BEGIN { exit !(a <= b) }'; then t0check=ok; else t0check=ko; reasons+=("max(ts) postérieur à t0"); fi
  info "max(ts) <= t0 : $t0check"
fi

status=ok; (( ${#reasons[@]} == 0 )) || status=incoherent
echo "VERIFY cluster=$CL count=$count max_id=$maxid max_ts=$maxts max_epoch=$maxepoch gaps_gt5s=$gaps dup_ids=$dups ts_not_increasing=$unordered t0_check=$t0check status=$status"
if [[ "$status" != ok ]]; then
  printf 'INCOHÉRENT : %s\n' "$(IFS=';'; echo "${reasons[*]}")" >&2
  exit 1
fi
