#!/usr/bin/env bash
# Installe k3s (version figée) sur une VM et récupère le kubeconfig dans ~/.kube/<vm>.yaml
# (adresse du serveur réécrite, hors du dépôt). Idempotent.
# Usage : ./infra/install-k3s.sh <cluster-a|cluster-b>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $# -eq 1 ]] || die "usage : $0 <cluster-a|cluster-b>"
VM="$1"; IP="$(vm_ip "$VM")"; K3S="$(ver k3s_version)"
[[ -n "$IP" ]] || die "VM inconnue : $VM"

log "k3s $K3S sur $VM ($IP)"
if vm_ssh "$VM" "k3s --version 2>/dev/null | grep -q '$K3S'"; then
  info "k3s $K3S déjà installé"
else
  # traefik et servicelb inutiles ici (économie de RAM/CPU) ; local-path et metrics-server conservés
  # Le script d'installation est téléchargé d'abord (avec reprises) : un téléchargement raté
  # ne doit pas passer pour une installation réussie.
  vm_ssh "$VM" "curl -fsSL --retry 10 --retry-all-errors --retry-delay 5 --max-time 30 -o /tmp/k3s-install.sh https://get.k3s.io" \
    || die "téléchargement du script d'installation k3s impossible depuis $VM"
  # Le résolveur DNS amont est parfois instable : l'installateur (idempotent) est relancé jusqu'à 3 fois
  for try in 1 2 3; do
    out="$(vm_ssh "$VM" "sudo INSTALL_K3S_VERSION='$K3S' sh /tmp/k3s-install.sh server \
      --disable traefik --disable servicelb --write-kubeconfig-mode 600 \
      --tls-san $IP --node-name $VM" 2>&1)" && break
    info "essai $try en échec : $(printf '%s' "$out" | tail -1)"
    [[ $try -lt 3 ]] || { printf '%s\n' "$out" | tail -15 | sed 's/^/   /'; die "installation de k3s en échec sur $VM"; }
    sleep 10
  done
  info "k3s installé"
fi

KC="$(kubeconfig "$VM")"; mkdir -p "$KUBE_DIR"; chmod 700 "$KUBE_DIR"
for i in $(seq 1 60); do vm_ssh "$VM" 'sudo test -s /etc/rancher/k3s/k3s.yaml' && break; [[ $i -lt 60 ]] || die "k3s.yaml absent sur $VM après 2 minutes"; sleep 2; done
vm_ssh "$VM" 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed -e "s|https://127.0.0.1:6443|https://$IP:6443|" -e "s/: default$/: $VM/" -e "s/name: default$/name: $VM/" \
        -e "s/cluster: default$/cluster: $VM/" -e "s/user: default$/user: $VM/" > "$KC"
chmod 600 "$KC"
info "kubeconfig : $KC"

for i in $(seq 1 60); do
  [[ "$(kubectl --kubeconfig "$KC" get nodes --no-headers 2>/dev/null | awk '{print $2}')" == Ready ]] && break
  [[ $i -lt 60 ]] || die "le nœud $VM n'est pas Ready après 2 minutes"
  sleep 2
done
# Attente des composants système (coredns, local-path-provisioner, metrics-server)
for i in $(seq 1 60); do
  [[ "$(kubectl --kubeconfig "$KC" -n kube-system get deploy --no-headers 2>/dev/null | wc -l)" -ge 3 ]] && break
  sleep 2
done
kubectl --kubeconfig "$KC" -n kube-system wait --for=condition=Available deploy --all --timeout=240s >/dev/null \
  || die "composants système de $VM non prêts (kubectl -n kube-system get pods)"
kubectl --kubeconfig "$KC" get nodes -o wide | sed 's/^/   /'
