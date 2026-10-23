#!/usr/bin/env bash
# Crée une VM à partir de l'image cloud Ubuntu (disque qcow2 en surcouche) et cloud-init.
# Idempotent : si la VM existe, elle est seulement démarrée si besoin.
# Usage : ./infra/create-vm.sh <nom> <vcpu> <ram_mb> <disk_gb> [data_disk_gb]
#   ex. : ./infra/create-vm.sh backup 1 2048 20 100
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $# -ge 4 ]] || die "usage : $0 <nom> <vcpu> <ram_mb> <disk_gb> [data_disk_gb]"
NAME="$1"; VCPU="$2"; RAM="$3"; DISK="$4"; DATA="${5:-}"
MAC="$(vm_mac "$NAME")"; IP="$(vm_ip "$NAME")"
[[ -n "$MAC" && -n "$IP" ]] || die "VM '$NAME' absente de infra/network.xml"
[[ "$(virsh net-info "$NET_NAME" 2>/dev/null)" =~ Active:\ +yes ]] || die "réseau $NET_NAME inactif : lancer ./infra/create-network.sh"
[[ "$(virsh pool-info "$POOL_VMS" 2>/dev/null)" =~ State:\ +running ]] || die "pool $POOL_VMS inactif : lancer ./infra/create-storage.sh"

log "VM $NAME ($IP, ${VCPU} vCPU, ${RAM} Mo, disque ${DISK} Go${DATA:+ + données ${DATA} Go})"
ensure_ssh_key

if virsh dominfo "$NAME" >/dev/null 2>&1; then
  [[ "$(virsh domstate "$NAME")" == running ]] || { virsh start "$NAME" >/dev/null; info "VM redémarrée"; }
else
  vol() {  # nom taille [backing]
    if virsh vol-info --pool "$POOL_VMS" "$1" >/dev/null 2>&1; then info "volume $1 déjà présent"; return; fi
    if [[ -n "${3:-}" ]]; then
      virsh vol-create-as "$POOL_VMS" "$1" "${2}G" --format qcow2 \
        --backing-vol "/var/lib/libvirt/images/base/$BASE_IMAGE" --backing-vol-format qcow2 >/dev/null
    else
      virsh vol-create-as "$POOL_VMS" "$1" "${2}G" --format qcow2 >/dev/null
    fi
    info "volume $1 créé"
  }
  vol "$NAME.qcow2" "$DISK" backing
  [[ -z "$DATA" ]] || vol "$NAME-data.qcow2" "$DATA"

  # Graine cloud-init (ISO) rendue depuis les modèles, envoyée comme volume libvirt
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  pub="$(cat "$SSH_KEY.pub")"
  for f in user-data meta-data; do
    sed -e "s|@HOSTNAME@|$NAME|g" -e "s|@SSH_PUBKEY@|$pub|g" "$REPO_DIR/infra/cloud-init/$f.tpl" > "$tmp/$f"
  done
  cloud-localds "$tmp/seed.iso" "$tmp/user-data" "$tmp/meta-data"
  virsh vol-info --pool "$POOL_VMS" "$NAME-seed.iso" >/dev/null 2>&1 && virsh vol-delete --pool "$POOL_VMS" "$NAME-seed.iso" >/dev/null
  virsh vol-create-as "$POOL_VMS" "$NAME-seed.iso" "$(stat -c %s "$tmp/seed.iso")" --format raw >/dev/null
  virsh vol-upload --pool "$POOL_VMS" "$NAME-seed.iso" "$tmp/seed.iso"

  args=(--name "$NAME" --vcpus "$VCPU" --memory "$RAM" --cpu host-model
        --osinfo ubuntu24.04 --import --noautoconsole --graphics none
        --network "network=$NET_NAME,mac=$MAC,model=virtio"
        --disk "vol=$POOL_VMS/$NAME.qcow2,bus=virtio"
        --disk "vol=$POOL_VMS/$NAME-seed.iso,device=cdrom"
        --autostart)
  [[ -z "$DATA" ]] || args+=(--disk "vol=$POOL_VMS/$NAME-data.qcow2,bus=virtio")
  virt-install "${args[@]}" >/dev/null
  info "VM définie et démarrée"
fi

# Attente de SSH puis de la fin de cloud-init
for i in $(seq 1 90); do
  if ssh "${SSH_OPTS[@]}" "ubuntu@$IP" true 2>/dev/null; then break; fi
  [[ $i -lt 90 ]] || die "SSH ne répond pas sur $IP après 3 minutes (voir : virsh console $NAME)"
  sleep 2
done
vm_ssh "$NAME" 'sudo cloud-init status --wait >/dev/null; test -f /var/lib/cloud/instance/dr-ready' \
  || die "cloud-init n'a pas terminé correctement sur $NAME (voir /var/log/cloud-init-output.log)"
info "$NAME prêt : ssh -i $SSH_KEY ubuntu@$IP"
