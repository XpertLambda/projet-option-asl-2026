#!/usr/bin/env bash
# Vérifie que l'hôte est prêt pour le projet. Ne modifie rien.
ok(){ printf "  [OK]   %s\n" "$1"; }
ko(){ printf "  [KO]   %s\n" "$1"; FAIL=1; }
FAIL=0
echo "Vérification de l'hôte"

kvm-ok >/dev/null 2>&1 && ok "Virtualisation matérielle (kvm-ok)" || ko "Virtualisation : activer VT-x/AMD-V dans le BIOS"
virsh -c qemu:///system list >/dev/null 2>&1 && ok "libvirt accessible sans sudo" || ko "libvirt : groupe libvirt manquant ou session à rouvrir"
systemctl is-active --quiet ssh && ok "Serveur SSH actif" || ko "SSH inactif"
[[ "$(systemctl is-enabled suspend.target 2>/dev/null)" == "masked" ]] && ok "Mise en veille désactivée" || ko "Mise en veille encore active"
[[ "$(timedatectl show -p NTPSynchronized --value)" == "yes" ]] && ok "Heure synchronisée (NTP)" || ko "Heure non synchronisée"
for c in git make kubectl helm velero virt-install cloud-localds; do
  command -v "$c" >/dev/null && ok "Commande $c" || ko "Commande $c absente"
done
[[ -f /var/lib/libvirt/images/base/noble.img ]] && ok "Image cloud Ubuntu 24.04 présente" || ko "Image cloud absente"

ram=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
disk=$(df -BG --output=avail /var/lib/libvirt/images | tail -1 | tr -dc '0-9')
cpu=$(nproc)
(( ram >= 14 )) && ok "RAM : ${ram} Go" || ko "RAM : ${ram} Go (14 Go minimum : 10 Go pour les VM + hôte)"
(( disk >= 180 )) && ok "Disque libre : ${disk} Go" || ko "Disque libre : ${disk} Go (180 Go nécessaires)"
(( cpu >= 4 )) && ok "CPU : ${cpu} threads" || ko "CPU : ${cpu} threads (4 minimum)"

echo
[[ $FAIL -eq 0 ]] && echo "Hôte prêt." || echo "Hôte pas encore prêt : corriger les lignes [KO]."
exit $FAIL
