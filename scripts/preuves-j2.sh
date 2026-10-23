#!/usr/bin/env bash
# Rassemble les preuves du jalon J2 dans docs/preuves/J2/ (sorties de commandes datées).
# Ne détruit rien. Usage : ./scripts/preuves-j2.sh
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

OUT="$REPO_DIR/docs/preuves/J2"; mkdir -p "$OUT"
stamp() { printf '# %s\n# commande : %s\n\n' "$(date '+%F %T')" "$1"; }
run() {  # fichier "commande" : enregistre la commande et sa sortie
  { stamp "$2"; bash -c "$2" 2>&1 || true; } > "$OUT/$1"
  info "$1"
}
log "Preuves J2 dans $OUT"
run versions.txt "cat '$REPO_DIR/versions.yaml'; echo; velero version --client-only; kubectl version --client | head -1"
run etat-plateforme.txt "make -C '$REPO_DIR' --no-print-directory status"
run vm-ressources.txt "virsh list --all; for v in cluster-a cluster-b backup; do virsh dominfo \$v | grep -E 'Name|CPU\\(s\\)|Max memory'; done; echo; free -h; echo; vmstat 1 3; echo; echo 'swap utilisé :'; swapon --show; grep -E 'SwapTotal|SwapFree' /proc/meminfo"
run reseau.txt "virsh net-dumpxml dr-net; virsh net-dhcp-leases dr-net"
run minio.txt "source '$CONF_DIR/velero-minio.env'; ssh -i '$SSH_KEY' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@$(vm_ip backup) \"sudo systemctl is-active minio; df -h /srv/minio | tail -1; export MC_HOST_v=http://\$VELERO_ACCESS_KEY:\$VELERO_SECRET_KEY@127.0.0.1:9000; mc version info v/velero; mc ls v/velero; mc ls v/velero/backups\""
run application.txt "'$REPO_DIR/scripts/verify.sh' cluster-a"
run velero-a.txt "velero --kubeconfig '$(kubeconfig cluster-a)' backup-location get; kubectl --kubeconfig '$(kubeconfig cluster-a)' -n velero get pods; velero --kubeconfig '$(kubeconfig cluster-a)' backup get"
run velero-b.txt "velero --kubeconfig '$(kubeconfig cluster-b)' backup-location get; kubectl --kubeconfig '$(kubeconfig cluster-b)' -n velero get pods; velero --kubeconfig '$(kubeconfig cluster-b)' backup get"
run test-de-fumee.txt "'$REPO_DIR/scripts/verify-smoke.sh'"
run kopia-b-lecture.txt "kubectl --kubeconfig '$(kubeconfig cluster-b)' -n velero get backupstoragelocation default -o jsonpath='{.spec.accessMode}{\"\\n\"}'"
info "terminé"
