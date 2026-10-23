#!/usr/bin/env bash
# Fonctions communes des scripts du projet. À charger avec : source "$(dirname "$0")/lib.sh"
# Aucun secret ici : les secrets générés vivent dans $CONF_DIR, hors du dépôt.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_DIR="${PROJET_CONF_DIR:-$HOME/.config/projet}"     # secrets générés (hors Git)
CACHE_DIR="${PROJET_CACHE_DIR:-$HOME/.cache/projet}"    # binaires téléchargés (archive)
KUBE_DIR="$HOME/.kube"
export LIBVIRT_DEFAULT_URI="qemu:///system"

NET_NAME="dr-net"
POOL_BASE="dr-base"      # image de base (lecture seule)
POOL_VMS="dr-vms"        # disques des VM
BASE_IMAGE="noble.img"
SSH_KEY="$CONF_DIR/ssh/id_ed25519"
SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no
          -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

log()  { if [[ -t 1 ]]; then printf '\033[1m== %s\033[0m\n' "$*"; else printf '== [%s] %s\n' "$(date +%T)" "$*"; fi; }
info() { printf '   %s\n' "$*"; }
die()  { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

# ver <cle> : valeur de la clé dans versions.yaml
ver() {
  local v
  v="$(awk -F': *' -v k="$1" '$1==k {gsub(/^"|"$/, "", $2); print $2; exit}' "$REPO_DIR/versions.yaml")"
  [[ -n "$v" ]] || die "clé '$1' absente de versions.yaml"
  printf '%s' "$v"
}

# vm_ip <nom> / vm_mac <nom> : lus dans la définition du réseau (source unique : infra/network.xml)
vm_ip()  { sed -n "s/.*name='$1'.*ip='\([0-9.]*\)'.*/\1/p;s/.*ip='\([0-9.]*\)'.*name='$1'.*/\1/p" "$REPO_DIR/infra/network.xml" | head -1; }
vm_mac() { sed -n "s/.*mac='\([0-9a-f:]*\)'.*name='$1'.*/\1/p;s/.*name='$1'.*mac='\([0-9a-f:]*\)'.*/\1/p" "$REPO_DIR/infra/network.xml" | head -1; }

# vm_ssh <nom> <commande...> : exécute une commande sur la VM
vm_ssh() { local vm="$1"; shift; ssh "${SSH_OPTS[@]}" "ubuntu@$(vm_ip "$vm")" "$@"; }
vm_scp() { local vm="$1"; shift; scp "${SSH_OPTS[@]}" -q "${@:1:$#-1}" "ubuntu@$(vm_ip "$vm"):${!#}"; }

kubeconfig() { printf '%s/cluster-%s.yaml' "$KUBE_DIR" "${1#cluster-}"; }

# gen_secret <fichier> <nom=valeur_ou_@random>... : écrit un fichier KEY=VALUE (0600) s'il n'existe pas
ensure_dir_private() { mkdir -p "$1"; chmod 700 "$1"; }
rand() { head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "${1:-24}"; }

# ensure_ssh_key : clé SSH dédiée aux VM (hors Git), créée une seule fois
ensure_ssh_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    ensure_dir_private "$(dirname "$SSH_KEY")"
    ssh-keygen -q -t ed25519 -N '' -C "projet-vm" -f "$SSH_KEY"
    info "clé SSH des VM créée : $SSH_KEY"
  fi
}
