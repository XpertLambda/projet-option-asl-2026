#!/usr/bin/env bash
# Vérifie l'application d'un cluster : pods Ready, nombre de lignes et dernier horodatage
# de la table témoin events. Sortie lisible puis une ligne "VERIFY count=... max_ts=...".
# Usage : ./scripts/verify.sh <cluster-a|cluster-b>
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

[[ $# -eq 1 ]] || die "usage : $0 <cluster-a|cluster-b>"
K=(kubectl --kubeconfig "$(kubeconfig "$1")")
log "Vérification de l'application sur $1"
"${K[@]}" -n app get pods --no-headers | sed 's/^/   /'
"${K[@]}" -n app wait --for=condition=Ready pod --all --timeout=10s >/dev/null || die "pods de l'application non Ready"
row="$("${K[@]}" -n app exec postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -F "|" -c "SELECT count(*), max(id), to_char(max(ts) AT TIME ZONE '"'"'UTC'"'"', '"'"'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'"'"'), extract(epoch from now() - max(ts)) FROM events"')"
IFS='|' read -r count maxid maxts lag <<<"$row"
info "lignes : $count, dernier id : $maxid"
info "dernier ts : $maxts (il y a ${lag}s)"
# Continuité : id et ts doivent être strictement croissants (pas de trou d'id inattendu hors rollback)
gaps="$("${K[@]}" -n app exec postgres-0 -- sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -c "SELECT count(*) FROM (SELECT ts - lag(ts) OVER (ORDER BY id) AS d FROM events) t WHERE d > interval '"'"'5 seconds'"'"'"')"
info "écarts de plus de 5 s entre deux lignes consécutives : $gaps"
echo "VERIFY cluster=$1 count=$count max_id=$maxid max_ts=$maxts gaps_gt5s=$gaps"
