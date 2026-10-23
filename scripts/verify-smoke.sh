#!/usr/bin/env bash
# Test de fumée J2 : une sauvegarde faite sur A est visible depuis B (même MinIO), et le
# volume de PostgreSQL a bien été copié par Kopia.
# Usage : ./scripts/verify-smoke.sh
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

NAME="smoke-$(date +%Y%m%d-%H%M%S)"
"$(dirname "$0")/backup.sh" "$NAME"

log "Contenu de la sauvegarde (volumes copiés par Kopia)"
KA="$(kubeconfig cluster-a)"
velero --kubeconfig "$KA" backup describe "$NAME" --details | sed -n '/Pod Volume Backups/,$p' | sed 's/^/   /'
[[ "$(kubectl --kubeconfig "$KA" -n velero get podvolumebackup -l velero.io/backup-name="$NAME" --no-headers | grep -c Completed)" -ge 1 ]] \
  || die "aucune copie de volume (PodVolumeBackup) terminée"

log "Visibilité depuis cluster-b (synchronisation de l'emplacement toutes les minutes)"
VB=(velero --kubeconfig "$(kubeconfig cluster-b)")
for i in $(seq 1 60); do
  if "${VB[@]}" backup get "$NAME" >/dev/null 2>&1; then
    "${VB[@]}" backup get | sed 's/^/   /'
    echo "SMOKE ok : $NAME visible depuis cluster-b après $((i*3)) s au plus"; exit 0
  fi
  sleep 3
done
die "$NAME toujours invisible depuis cluster-b après 3 minutes"
