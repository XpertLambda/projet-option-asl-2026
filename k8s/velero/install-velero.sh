#!/usr/bin/env bash
# Installe Velero (version figée) + plugin AWS sur un cluster, avec Kopia (File System
# Backup par défaut pour tous les volumes) et le BackupStorageLocation vers MinIO.
# Sur cluster-b : emplacement en lecture seule (ReadOnly). Idempotent.
# Usage : ./k8s/velero/install-velero.sh <cluster-a|cluster-b> <rw|ro>
set -euo pipefail
source "$(dirname "$0")/../../infra/lib.sh"

[[ $# -eq 2 && ( "$2" == rw || "$2" == ro ) ]] || die "usage : $0 <cluster-a|cluster-b> <rw|ro>"
CL="$1"; MODE="$2"; KC="$(kubeconfig "$CL")"
[[ -f "$KC" ]] || die "kubeconfig absent : $KC (make k3s)"
[[ -f "$CONF_DIR/velero-minio.env" ]] || die "identifiants MinIO absents (make minio)"
K=(kubectl --kubeconfig "$KC"); V=(velero --kubeconfig "$KC")
VEL="$(ver velero_version)"; PLUGIN="$(ver velero_plugin_aws_version)"
[[ "$(velero version --client-only 2>/dev/null | awk '/Version:/{print $2}')" == "$VEL" ]] \
  || die "CLI velero différent de $VEL (versions.yaml) : relancer sudo ./infra/setup-host.sh avec VELERO_VERSION=$VEL"
source "$CONF_DIR/velero-minio.env"
S3URL="http://$(vm_ip backup):9000"

log "Velero $VEL sur $CL (emplacement de sauvegarde : $MODE)"
# Mot de passe du dépôt Kopia : identique sur A et B, sinon B ne peut pas lire les sauvegardes de A
if [[ ! -f "$CONF_DIR/velero-repo.env" ]]; then
  ( umask 077; printf 'VELERO_REPO_PASSWORD=%s\n' "$(rand 32)" > "$CONF_DIR/velero-repo.env" )
  info "mot de passe du dépôt Kopia généré dans $CONF_DIR/velero-repo.env"
fi
source "$CONF_DIR/velero-repo.env"
"${K[@]}" create namespace velero --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
"${K[@]}" -n velero create secret generic velero-repo-credentials \
  --from-literal=repository-password="$VELERO_REPO_PASSWORD" --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null

if "${K[@]}" -n velero get deployment velero >/dev/null 2>&1; then
  info "Velero déjà installé"
else
  cred="$(mktemp)"; trap 'rm -f "$cred"' EXIT
  printf '[default]\naws_access_key_id=%s\naws_secret_access_key=%s\n' "$VELERO_ACCESS_KEY" "$VELERO_SECRET_KEY" > "$cred"
  "${V[@]}" install --provider aws \
    --image "velero/velero:$VEL" --plugins "velero/velero-plugin-for-aws:$PLUGIN" \
    --bucket velero --secret-file "$cred" \
    --backup-location-config "region=minio,s3ForcePathStyle=true,s3Url=$S3URL" \
    --use-volume-snapshots=false --use-node-agent --uploader-type kopia --default-volumes-to-fs-backup \
    --velero-pod-cpu-request 100m --velero-pod-mem-request 128Mi \
    --node-agent-pod-cpu-request 100m --node-agent-pod-mem-request 256Mi --node-agent-pod-mem-limit 1Gi \
    --wait 2>&1 | grep -E 'Velero is installed|error|Error' | sed 's/^/   /'
fi

# Mode d'accès de l'emplacement de sauvegarde
access=ReadWrite; [[ "$MODE" == ro ]] && access=ReadOnly
"${K[@]}" -n velero patch backupstoragelocation default --type merge -p "{\"spec\":{\"accessMode\":\"$access\"}}" >/dev/null
"${K[@]}" -n velero rollout status deployment/velero --timeout=180s >/dev/null
"${K[@]}" -n velero rollout status daemonset/node-agent --timeout=180s >/dev/null

# Attente de la validation de l'emplacement (phase Available)
for i in $(seq 1 60); do
  phase="$("${K[@]}" -n velero get backupstoragelocation default -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == Available ]] && break
  [[ $i -lt 60 ]] || die "emplacement de sauvegarde non disponible (phase : ${phase:-inconnue}) : velero --kubeconfig $KC backup-location get"
  sleep 2
done
"${V[@]}" backup-location get | sed 's/^/   /'
"${K[@]}" -n velero get pods | sed 's/^/   /'
