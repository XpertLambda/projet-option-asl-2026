#!/usr/bin/env bash
# Préparation de l'hôte Ubuntu 24.04 (Desktop ou Server) pour le projet.
# Idempotent : peut être relancé sans risque.
# Usage : sudo ./infra/setup-host.sh [compte]   (par défaut : le compte qui lance sudo)
# Le projet utilise un seul compte partagé, `projet`, avec la clé SSH de chaque membre.
set -euo pipefail

VELERO_VERSION="${VELERO_VERSION:-v1.18.1}"
IMAGES_DIR="/var/lib/libvirt/images"
UBUNTU_IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

if [[ $EUID -ne 0 ]]; then echo "Lancer avec sudo." >&2; exit 1; fi
ACCOUNT="${1:-${SUDO_USER:-}}"
if [[ -z "$ACCOUNT" ]] || ! id "$ACCOUNT" >/dev/null 2>&1; then
  echo "Compte '$ACCOUNT' introuvable. Usage : sudo $0 projet" >&2; exit 1
fi

echo "== 1. Mise à jour et paquets de base"
apt-get update
apt-get -y upgrade
apt-get -y install openssh-server git make curl wget jq tmux htop tree \
  python3 python3-venv python3-pip ca-certificates gnupg chrony

echo "== 2. Virtualisation (KVM/libvirt, cloud-init)"
apt-get -y install cpu-checker qemu-kvm libvirt-daemon-system libvirt-clients \
  virtinst virt-manager cloud-image-utils genisoimage
kvm-ok
systemctl enable --now libvirtd

echo "== 3. Compte $ACCOUNT dans les groupes libvirt et kvm"
usermod -aG libvirt,kvm "$ACCOUNT"

echo "== 4. SSH"
systemctl enable --now ssh

echo "== 5. Pas de mise en veille (sinon les VM s'arrêtent)"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "== 6. Heure synchronisée (nécessaire aux mesures RTO/RPO)"
systemctl enable --now chrony
timedatectl set-ntp true || true

echo "== 7. Pare-feu : SSH autorisé"
if command -v ufw >/dev/null; then ufw allow OpenSSH; ufw --force enable; fi

echo "== 8. Outils Kubernetes et sauvegarde (CLI)"
snap install kubectl --classic || true
snap install helm --classic || true
if ! command -v velero >/dev/null || ! velero version --client-only 2>/dev/null | grep -q "$VELERO_VERSION"; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/velero.tgz" \
    "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz"
  tar -xzf "$tmp/velero.tgz" -C "$tmp"
  install -m 0755 "$tmp/velero-${VELERO_VERSION}-linux-amd64/velero" /usr/local/bin/velero
  rm -rf "$tmp"
fi

echo "== 9. Image cloud Ubuntu 24.04 pour les VM"
mkdir -p "$IMAGES_DIR/base"
if [[ ! -f "$IMAGES_DIR/base/noble.img" ]]; then
  wget -O "$IMAGES_DIR/base/noble.img" "$UBUNTU_IMG_URL"
fi

echo "== Terminé. Déconnectez-vous puis reconnectez-vous pour appliquer les groupes."
echo "   Vérification : ./infra/check-host.sh"
