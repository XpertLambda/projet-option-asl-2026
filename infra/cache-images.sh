#!/usr/bin/env bash
# Cache local des images (docs/adr/0005-cache-images.md) : exporte les images présentes sur cluster-a
# dans une archive gardée sur l'hôte (hors Git). install-k3s.sh la dépose sur chaque nouvelle VM, k3s
# l'importe à son démarrage : les reconstructions ne téléchargent plus les images depuis Docker Hub.
# À relancer après un changement de version dans versions.yaml.
# L'archive passe directement par SSH, aucun fichier temporaire n'est créé sur la VM.
# Usage : ./infra/cache-images.sh      (cluster-a doit être construit : make up)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ensure_dir_private "$CACHE_DIR"; mkdir -p "$(dirname "$IMAGE_CACHE_FILE")"
log "Images présentes sur cluster-a"
mapfile -t refs < <(vm_ssh cluster-a 'sudo k3s ctr -n k8s.io images ls -q' | grep -E '^docker\.io/[^@]+:[^@:/]+$' | sort -u)
(( ${#refs[@]} > 0 )) || die "aucune image trouvée sur cluster-a"
printf '   %s\n' "${refs[@]}"
for needed in "library/postgres:$(ver postgres_version)" "velero/velero:$(ver velero_version)" \
              "velero/velero-plugin-for-aws:$(ver velero_plugin_aws_version)"; do
  printf '%s\n' "${refs[@]}" | grep -q "$needed\$" || die "image $needed absente de cluster-a (make up complet d'abord)"
done

log "Export vers $IMAGE_CACHE_FILE"
# La liste est développée côté hôte (références sans espace)
vm_ssh cluster-a "sudo k3s ctr -n k8s.io images export --platform linux/amd64 - ${refs[*]}" > "$IMAGE_CACHE_FILE.part"
tar -tf "$IMAGE_CACHE_FILE.part" >/dev/null || die "archive illisible"
mv "$IMAGE_CACHE_FILE.part" "$IMAGE_CACHE_FILE"
printf '%s\n' "${refs[@]}" > "${IMAGE_CACHE_FILE%.tar}.txt"
info "${#refs[@]} images, $(du -h "$IMAGE_CACHE_FILE" | cut -f1)"
