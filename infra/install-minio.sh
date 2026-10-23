#!/usr/bin/env bash
# Installe MinIO (binaire figé) en service systemd sur la VM backup, avec le disque de
# données, le bucket 'velero' (versionnage actif) et un utilisateur limité à ce bucket.
# Les identifiants sont générés dans ~/.config/projet/ (hors Git). Idempotent.
# Usage : ./infra/install-minio.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

MINIO_REL="$(ver minio_release)"; MC_REL="$(ver mc_release)"
URL_BASE="https://github.com/minio"
ensure_dir_private "$CONF_DIR"; ensure_dir_private "$CACHE_DIR"

log "Identifiants MinIO (hors Git)"
if [[ ! -f "$CONF_DIR/minio.env" ]]; then
  umask 077
  printf 'MINIO_ROOT_USER=root-%s\nMINIO_ROOT_PASSWORD=%s\n' "$(rand 6)" "$(rand 32)" > "$CONF_DIR/minio.env"
  printf 'VELERO_ACCESS_KEY=velero\nVELERO_SECRET_KEY=%s\n' "$(rand 32)" > "$CONF_DIR/velero-minio.env"
  info "identifiants générés dans $CONF_DIR"
else
  info "identifiants déjà présents"
fi
chmod 600 "$CONF_DIR"/*.env
# shellcheck disable=SC1091
source "$CONF_DIR/minio.env"; source "$CONF_DIR/velero-minio.env"

log "Binaires MinIO et mc (téléchargement vérifié, copie archivée dans $CACHE_DIR)"
fetch() {  # fichier_local url sha256
  if [[ -f "$CACHE_DIR/$1" ]] && [[ "$(sha256sum "$CACHE_DIR/$1" | cut -d' ' -f1)" == "$3" ]]; then
    info "$1 déjà en cache (empreinte OK)"; return
  fi
  curl -fsSL --retry 3 -o "$CACHE_DIR/$1.part" "$2"
  [[ "$(sha256sum "$CACHE_DIR/$1.part" | cut -d' ' -f1)" == "$3" ]] || { rm -f "$CACHE_DIR/$1.part"; die "empreinte invalide pour $1"; }
  mv "$CACHE_DIR/$1.part" "$CACHE_DIR/$1"; info "$1 téléchargé (empreinte OK)"
}
fetch "minio.$MINIO_REL" "$URL_BASE/minio/releases/download/$MINIO_REL/minio.linux-amd64.$MINIO_REL" "$(ver minio_sha256)"
fetch "mc.$MC_REL" "$URL_BASE/mc/releases/download/$MC_REL/mc.linux-amd64.$MC_REL" "$(ver mc_sha256)"

log "Installation sur la VM backup"
vm_scp backup "$CACHE_DIR/minio.$MINIO_REL" "$CACHE_DIR/mc.$MC_REL" /tmp/
POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::velero","arn:aws:s3:::velero/*"]}]}'
{
  printf 'export MINIO_REL=%q MC_REL=%q ROOT_USER=%q ROOT_PASS=%q VELERO_USER=%q VELERO_PASS=%q POLICY=%q\n' \
    "$MINIO_REL" "$MC_REL" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" "$VELERO_ACCESS_KEY" "$VELERO_SECRET_KEY" "$POLICY"
  cat <<'REMOTE'
set -euo pipefail
install -m 0755 "/tmp/minio.$MINIO_REL" /usr/local/bin/minio
install -m 0755 "/tmp/mc.$MC_REL" /usr/local/bin/mc
rm -f "/tmp/minio.$MINIO_REL" "/tmp/mc.$MC_REL"

# Disque de données : formaté une seule fois, monté par étiquette
if ! blkid /dev/vdb >/dev/null 2>&1; then mkfs.ext4 -q -L minio-data /dev/vdb; echo "disque de données formaté"; fi
mkdir -p /srv/minio
grep -q 'LABEL=minio-data' /etc/fstab || echo 'LABEL=minio-data /srv/minio ext4 defaults,nofail 0 2' >> /etc/fstab
mountpoint -q /srv/minio || mount /srv/minio
id minio-user >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin minio-user
mkdir -p /srv/minio/data; chown -R minio-user:minio-user /srv/minio/data

# Configuration et service
umask 077
printf 'MINIO_ROOT_USER=%s\nMINIO_ROOT_PASSWORD=%s\nMINIO_VOLUMES=/srv/minio/data\nMINIO_OPTS=--address :9000 --console-address :9001\n' \
  "$ROOT_USER" "$ROOT_PASS" > /etc/default/minio
chmod 600 /etc/default/minio
cat > /etc/systemd/system/minio.service <<'UNIT'
[Unit]
Description=MinIO (stockage objet des sauvegardes)
After=network-online.target srv-minio.mount
Wants=network-online.target
RequiresMountsFor=/srv/minio

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable minio >/dev/null 2>&1
systemctl restart minio
for i in $(seq 1 30); do curl -sf http://127.0.0.1:9000/minio/health/live && break; sleep 1; done
curl -sf http://127.0.0.1:9000/minio/health/live || { echo "MinIO ne démarre pas"; journalctl -u minio -n 20 --no-pager; exit 1; }

# Bucket, versionnage, utilisateur et politique limités au bucket velero
export MC_HOST_local="http://$ROOT_USER:$ROOT_PASS@127.0.0.1:9000"
mc --quiet mb --ignore-existing local/velero
mc --quiet version enable local/velero
printf '%s' "$POLICY" > /tmp/velero-policy.json
mc --quiet admin policy create local velero-bucket /tmp/velero-policy.json
rm -f /tmp/velero-policy.json
mc --quiet admin user add local "$VELERO_USER" "$VELERO_PASS"
mc --quiet admin policy attach local velero-bucket --user "$VELERO_USER" 2>&1 | grep -v 'already' || true
echo "MinIO prêt ; versionnage : $(mc version info local/velero)"
REMOTE
} | vm_ssh backup 'sudo bash -s'

log "Contrôle depuis l'hôte avec l'utilisateur Velero (bucket accessible, hors bucket refusé)"
sleep 1
curl -sf "http://$(vm_ip backup):9000/minio/health/live" >/dev/null && info "API S3 joignable sur http://$(vm_ip backup):9000"
{
  printf 'export MC_HOST_v=%q\n' "http://$VELERO_ACCESS_KEY:$VELERO_SECRET_KEY@127.0.0.1:9000"
  cat <<'CHECK'
mc --quiet ls v/velero >/dev/null && echo '   utilisateur velero : accès au bucket velero OK'
if mc --quiet mb v/autre-bucket >/dev/null 2>&1; then echo '   ERREUR : velero peut créer d autres buckets'; exit 1
else echo '   utilisateur velero : création d un autre bucket refusée (OK)'; fi
CHECK
} | vm_ssh backup 'bash -s'
