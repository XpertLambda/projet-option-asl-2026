#!/usr/bin/env bash
# Crée (ou met à jour) le réseau libvirt dr-net. Idempotent.
# Usage : ./infra/create-network.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "Réseau $NET_NAME (192.168.100.0/24)"
if virsh net-info "$NET_NAME" >/dev/null 2>&1; then
  # Le XML du dépôt est la référence : on compare les réservations DHCP
  if diff -q <(virsh net-dumpxml "$NET_NAME" | grep -o "host mac='[^']*' name='[^']*' ip='[^']*'" | sort) \
             <(grep -o "host mac='[^']*' name='[^']*' ip='[^']*'" "$REPO_DIR/infra/network.xml" | sort) >/dev/null; then
    info "réseau déjà défini avec les bonnes réservations"
  else
    die "le réseau $NET_NAME existe avec d'autres réservations : le supprimer avec 'make destroy-all' puis relancer"
  fi
else
  virsh net-define "$REPO_DIR/infra/network.xml" >/dev/null
  info "réseau défini"
fi
virsh net-autostart "$NET_NAME" >/dev/null
[[ "$(virsh net-info "$NET_NAME")" =~ Active:\ +yes ]] || { virsh net-start "$NET_NAME" >/dev/null; info "réseau démarré"; }
virsh net-info "$NET_NAME" | sed 's/^/   /'
