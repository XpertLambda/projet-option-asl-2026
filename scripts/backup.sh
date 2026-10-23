#!/usr/bin/env bash
# Sauvegarde ponctuelle du namespace app sur cluster-a, vers MinIO, et attend la fin.
# Usage : ./scripts/backup.sh [nom]      (nom par défaut : manuel-AAAAMMJJ-HHMMSS)
# Affiche une ligne "BACKUP name=... phase=... duree_s=..." exploitable par d'autres scripts.
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

NAME="${1:-manuel-$(date +%Y%m%d-%H%M%S)}"
V=(velero --kubeconfig "$(kubeconfig cluster-a)")
log "Sauvegarde $NAME du namespace app (cluster-a)"
t0=$(date +%s)
"${V[@]}" backup create "$NAME" --include-namespaces app --wait >/dev/null
dur=$(( $(date +%s) - t0 ))
phase="$(kubectl --kubeconfig "$(kubeconfig cluster-a)" -n velero get backup "$NAME" -o jsonpath='{.status.phase}')"
"${V[@]}" backup get "$NAME" | sed 's/^/   /'
echo "BACKUP name=$NAME phase=$phase duree_s=$dur"
[[ "$phase" == Completed ]] || { "${V[@]}" backup logs "$NAME" | tail -20; die "sauvegarde $NAME en phase $phase"; }
