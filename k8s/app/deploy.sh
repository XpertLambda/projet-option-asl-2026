#!/usr/bin/env bash
# Déploie l'application (PostgreSQL + écrivain) sur un cluster. Idempotent.
# Le mot de passe PostgreSQL est généré une fois dans ~/.config/projet/ (hors Git) et
# injecté dans un Secret Kubernetes au déploiement.
# Usage : ./k8s/app/deploy.sh <cluster-a|cluster-b>
set -euo pipefail
source "$(dirname "$0")/../../infra/lib.sh"

[[ $# -eq 1 ]] || die "usage : $0 <cluster-a|cluster-b>"
KC="$(kubeconfig "$1")"; [[ -f "$KC" ]] || die "kubeconfig absent : $KC (make k3s)"
K=(kubectl --kubeconfig "$KC")
PG="$(ver postgres_version)"
ensure_dir_private "$CONF_DIR"

log "Application sur $1 (PostgreSQL $PG)"
if [[ ! -f "$CONF_DIR/postgres.env" ]]; then
  ( umask 077; printf 'POSTGRES_PASSWORD=%s\n' "$(rand 32)" > "$CONF_DIR/postgres.env" )
  info "mot de passe PostgreSQL généré dans $CONF_DIR/postgres.env"
fi
source "$CONF_DIR/postgres.env"

"${K[@]}" apply -f "$REPO_DIR/k8s/app/namespace.yaml" >/dev/null
"${K[@]}" -n app create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=app --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB=app --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
for f in postgres writer; do
  sed "s|@POSTGRES_VERSION@|$PG|g" "$REPO_DIR/k8s/app/$f.yaml" | "${K[@]}" apply -f - >/dev/null
done
"${K[@]}" -n app rollout status statefulset/postgres --timeout=300s | sed 's/^/   /'
"${K[@]}" -n app rollout status deployment/writer --timeout=180s | sed 's/^/   /'
"${K[@]}" -n app get pods,pvc | sed 's/^/   /'
