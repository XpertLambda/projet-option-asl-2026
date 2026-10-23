#!/usr/bin/env bash
# Déclare les pools de stockage libvirt du projet (sans sudo : c'est libvirtd qui écrit
# les disques). dr-base = image Ubuntu de l'hôte, dr-vms = disques des VM. Idempotent.
# Usage : ./infra/create-storage.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Pools de stockage libvirt"
base_dir=/var/lib/libvirt/images/base
vms_dir=/var/lib/libvirt/images/dr
[[ -f "$base_dir/$BASE_IMAGE" ]] || die "image de base absente : $base_dir/$BASE_IMAGE (voir SETUP-MACHINE : infra/setup-host.sh)"
sum="$(sha256sum "$base_dir/$BASE_IMAGE" | cut -d' ' -f1)"
[[ "$sum" == "$(ver ubuntu_image_sha256)" ]] || die "empreinte de $BASE_IMAGE différente de versions.yaml ($sum)"

ensure_pool() {  # nom chemin
  virsh pool-info "$1" >/dev/null 2>&1 || { virsh pool-define-as "$1" dir --target "$2" >/dev/null; info "pool $1 défini"; }
  [[ "$1" == "$POOL_VMS" ]] && virsh pool-build "$1" >/dev/null 2>&1 || true
  [[ "$(virsh pool-info "$1")" =~ State:\ +running ]] || { virsh pool-start "$1" >/dev/null; info "pool $1 démarré"; }
  virsh pool-autostart "$1" >/dev/null
}
ensure_pool "$POOL_BASE" "$base_dir"
ensure_pool "$POOL_VMS" "$vms_dir"
virsh pool-list | sed 's/^/   /'
