#!/usr/bin/env bash
# Supprime le réseau dr-net et les pools de stockage du projet (les VM doivent être détruites
# avant). Idempotent. Usage : ./infra/destroy-network.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Suppression du réseau $NET_NAME et des pools $POOL_VMS / $POOL_BASE"
for vm in cluster-a cluster-b backup; do
  ! virsh dominfo "$vm" >/dev/null 2>&1 || die "la VM $vm existe encore : la détruire d'abord"
done
if virsh net-info "$NET_NAME" >/dev/null 2>&1; then
  [[ "$(virsh net-info "$NET_NAME")" =~ Active:\ +yes ]] && virsh net-destroy "$NET_NAME" >/dev/null
  virsh net-undefine "$NET_NAME" >/dev/null; info "réseau supprimé"
fi
for p in "$POOL_VMS" "$POOL_BASE"; do
  if virsh pool-info "$p" >/dev/null 2>&1; then
    [[ "$(virsh pool-info "$p")" =~ State:\ +running ]] && virsh pool-destroy "$p" >/dev/null
    virsh pool-undefine "$p" >/dev/null; info "pool $p retiré (les fichiers de l'image de base restent sur l'hôte)"
  fi
done
