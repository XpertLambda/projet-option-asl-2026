#!/usr/bin/env bash
# Détruit une VM et tous ses disques (système, données, graine cloud-init). Idempotent.
# Usage : ./infra/destroy-vm.sh <nom>
# Protection : la VM 'backup' contient les sauvegardes, elle n'est détruite que si
# CONFIRM_DESTROY_BACKUP=yes est positionné explicitement.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $# -eq 1 ]] || die "usage : $0 <nom>"
NAME="$1"
case "$NAME" in cluster-a|cluster-b|backup) ;; *) die "VM inconnue : $NAME (cluster-a, cluster-b ou backup)";; esac
if [[ "$NAME" == backup && "${CONFIRM_DESTROY_BACKUP:-}" != yes ]]; then
  die "la VM backup contient les sauvegardes : relancer avec CONFIRM_DESTROY_BACKUP=yes si c'est voulu"
fi

log "Destruction de la VM $NAME"
if virsh dominfo "$NAME" >/dev/null 2>&1; then
  [[ "$(virsh domstate "$NAME")" != running ]] || virsh destroy "$NAME" >/dev/null
  virsh undefine "$NAME" --remove-all-storage >/dev/null
  info "VM supprimée avec ses disques"
else
  info "VM absente"
fi
# Volumes éventuellement restés dans le pool (VM jamais définie jusqu'au bout)
for v in "$NAME.qcow2" "$NAME-data.qcow2" "$NAME-seed.iso"; do
  virsh vol-info --pool "$POOL_VMS" "$v" >/dev/null 2>&1 && { virsh vol-delete --pool "$POOL_VMS" "$v" >/dev/null; info "volume $v supprimé"; } || true
done
rm -f "$(kubeconfig "$NAME")"
