#!/usr/bin/env bash
# Installe k3s (version figée) sur une VM et récupère le kubeconfig dans ~/.kube/<vm>.yaml
# (adresse du serveur réécrite, hors du dépôt). Idempotent.
# Usage : ./infra/install-k3s.sh <cluster-a|cluster-b>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $# -eq 1 ]] || die "usage : $0 <cluster-a|cluster-b>"
VM="$1"; IP="$(vm_ip "$VM")"; K3S="$(ver k3s_version)"
[[ -n "$IP" ]] || die "VM inconnue : $VM"

IMPORT_TAINT=projet/import-images
IMAGE_LIST="${IMAGE_CACHE_FILE%.tar}.txt"
taint_arg=""
log "k3s $K3S sur $VM ($IP)"
if vm_ssh "$VM" "k3s --version 2>/dev/null | grep -q '$K3S'"; then
  info "k3s $K3S déjà installé"
else
  # Images fournies à k3s avant son démarrage, s'il existe un cache sur l'hôte (infra/cache-images.sh).
  # k3s les importe en parallèle du démarrage : le nœud porte une marque (taint) qui empêche tout pod,
  # retirée plus bas quand toutes les images sont là. Sinon les pods les téléchargent quand même.
  if [[ "$IMAGE_CACHE" == yes && -f "$IMAGE_CACHE_FILE" && -f "$IMAGE_LIST" ]]; then
    taint_arg="--node-taint $IMPORT_TAINT=true:NoSchedule"
    info "copie du cache local des images ($(du -h "$IMAGE_CACHE_FILE" | cut -f1))"
    vm_ssh "$VM" 'sudo mkdir -p /var/lib/rancher/k3s/agent/images && sudo tee /var/lib/rancher/k3s/agent/images/k3s-images.tar >/dev/null' \
      < "$IMAGE_CACHE_FILE"
  else
    info "pas de cache local des images : téléchargement depuis Docker Hub"
  fi
  # traefik et servicelb inutiles ici (économie de RAM/CPU) ; local-path et metrics-server conservés
  # Le script d'installation est téléchargé d'abord (avec reprises) : un téléchargement raté
  # ne doit pas passer pour une installation réussie.
  vm_ssh "$VM" "curl -fsSL --retry 10 --retry-all-errors --retry-delay 5 --max-time 30 -o /tmp/k3s-install.sh https://get.k3s.io" \
    || die "téléchargement du script d'installation k3s impossible depuis $VM"
  # Le résolveur DNS amont est parfois instable : l'installateur (idempotent) est relancé jusqu'à 3 fois
  for try in 1 2 3; do
    out="$(vm_ssh "$VM" "sudo INSTALL_K3S_VERSION='$K3S' sh /tmp/k3s-install.sh server \
      --disable traefik --disable servicelb --write-kubeconfig-mode 600 \
      --tls-san $IP --node-name $VM $taint_arg" 2>&1)" && break
    info "essai $try en échec : $(printf '%s' "$out" | tail -1)"
    [[ $try -lt 3 ]] || { printf '%s\n' "$out" | tail -15 | sed 's/^/   /'; die "installation de k3s en échec sur $VM"; }
    sleep 10
  done
  info "k3s installé"
fi

KC="$(kubeconfig "$VM")"; mkdir -p "$KUBE_DIR"; chmod 700 "$KUBE_DIR"
k3s_yaml_present() { vm_ssh "$VM" 'sudo test -s /etc/rancher/k3s/k3s.yaml'; }
wait_for "k3s.yaml absent sur $VM" k3s_yaml_present
vm_ssh "$VM" 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed -e "s|https://127.0.0.1:6443|https://$IP:6443|" -e "s/: default$/: $VM/" -e "s/name: default$/name: $VM/" \
        -e "s/cluster: default$/cluster: $VM/" -e "s/user: default$/user: $VM/" > "$KC"
chmod 600 "$KC"
info "kubeconfig : $KC"

node_ready() { [[ "$(kubectl --kubeconfig "$KC" get nodes --no-headers 2>/dev/null | awk '{print $2}')" == Ready ]]; }
wait_for "le nœud $VM n'est pas Ready" node_ready
# Marque posée à l'installation avec le cache (aussi après une exécution interrompue)
if [[ " $(kubectl --kubeconfig "$KC" get node "$VM" -o jsonpath='{.spec.taints[*].key}') " == *" $IMPORT_TAINT "* ]]; then
  images_imported() {
    local present; present="$(vm_ssh "$VM" 'sudo k3s ctr -n k8s.io images ls -q')"
    ! grep -qvxF -f <(printf '%s\n' "$present") "$IMAGE_LIST"
  }
  start=$SECONDS
  wait_for "images du cache non importées sur $VM (journalctl -u k3s)" images_imported
  info "$(wc -l < "$IMAGE_LIST") images du cache importées ($((SECONDS - start)) s d'attente)"
  kubectl --kubeconfig "$KC" taint node "$VM" "$IMPORT_TAINT-" >/dev/null
fi
# Attente des composants système (coredns, local-path-provisioner, metrics-server)
system_deploys_present() { [[ "$(kubectl --kubeconfig "$KC" -n kube-system get deploy --no-headers 2>/dev/null | wc -l)" -ge 3 ]]; }
wait_for "composants système de $VM absents (coredns, local-path-provisioner, metrics-server)" system_deploys_present
kubectl --kubeconfig "$KC" -n kube-system wait --for=condition=Available deploy --all --timeout="$WAIT_TIMEOUT" >/dev/null \
  || die "composants système de $VM non prêts (kubectl -n kube-system get pods)"
kubectl --kubeconfig "$KC" get nodes -o wide | sed 's/^/   /'
