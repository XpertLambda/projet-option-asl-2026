#!/usr/bin/env bash
# Sinistre : détruit la VM cluster-a (et seulement elle ; la VM backup et les sauvegardes restent).
# Juste avant, lit en lecture seule la dernière écriture connue (max(ts) de events sur cluster-a), puis
# relève t0 immédiatement avant la commande de destruction (docs/architecture.md, section 6).
# L'état est écrit dans ~/.cache/projet/last-disaster.env (hors dépôt), lu par restore.sh.
# Usage : CONFIRM_DISASTER=yes ./scripts/disaster.sh [--dry-run]
#   --dry-run : relève t0 et la dernière écriture sans rien détruire (essai de restauration à blanc)
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

DRY=no; [[ "${1:-}" == --dry-run ]] && DRY=yes
[[ "$DRY" == yes || "${CONFIRM_DISASTER:-}" == yes ]] \
  || die "destruction de cluster-a : relancer avec CONFIRM_DISASTER=yes (make disaster CONFIRM_DISASTER=yes)"
KA="$(kubeconfig cluster-a)"; [[ -f "$KA" ]] || die "kubeconfig absent : $KA"

log "Dernière écriture connue sur cluster-a (lecture seule)"
row="$(kubectl --kubeconfig "$KA" -n app exec -i postgres-0 -c postgres -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -At -F "|"' <<<"SELECT to_char(max(ts) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'), extract(epoch from max(ts)), count(*) FROM events")" \
  || die "cluster-a injoignable : rien à détruire ou PostgreSQL à l'arrêt"
IFS='|' read -r LAST_TS LAST_EPOCH ROWS_A <<<"$row"
[[ -n "$LAST_TS" ]] || die "table events vide sur cluster-a"
info "max(ts) = $LAST_TS ($ROWS_A lignes)"

# Date de création de cette instance de cluster-a : restore.sh refuse toute sauvegarde antérieure (le bucket
# garde les sauvegardes des instances précédentes de cluster-a)
A_CREATED="$(kubectl --kubeconfig "$KA" get node cluster-a -o jsonpath='{.metadata.creationTimestamp}')"
A_CREATED_EPOCH="$(date -d "$A_CREATED" +%s)"

mkdir -p "$CACHE_DIR"; STATE="$CACHE_DIR/last-disaster.env"
T0_EPOCH="$(date +%s.%N)"; T0_ISO="$(date -u -d "@${T0_EPOCH%.*}" +%FT%TZ)"
if [[ "$DRY" == yes ]]; then
  log "Essai à blanc : cluster-a n'est pas détruit"
else
  log "Destruction de cluster-a (t0 = $T0_ISO)"
  "$(dirname "$0")/../infra/destroy-vm.sh" cluster-a
fi
cat > "$STATE" <<STATE
T0_EPOCH=$T0_EPOCH
T0_ISO=$T0_ISO
LAST_TS=$LAST_TS
LAST_EPOCH=$LAST_EPOCH
ROWS_A=$ROWS_A
A_CREATED_EPOCH=$A_CREATED_EPOCH
DESTROYED=$([[ "$DRY" == yes ]] && echo no || echo yes)
STATE
echo "DISASTER t0=$T0_EPOCH t0_iso=$T0_ISO last_ts=$LAST_TS rows_a=$ROWS_A destroyed=$([[ "$DRY" == yes ]] && echo no || echo yes)"
