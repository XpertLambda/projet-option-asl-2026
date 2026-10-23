#cloud-config
# Modèle rendu par infra/create-vm.sh (variables @NOM@). Aucun secret : seule la clé publique est injectée.
hostname: @HOSTNAME@
manage_etc_hosts: true
timezone: Europe/Paris
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - @SSH_PUBKEY@
ssh_pwauth: false
package_update: true
packages:
  - qemu-guest-agent
  - chrony
  - curl
  - ca-certificates
  - jq
runcmd:
  - systemctl enable --now qemu-guest-agent chrony
  - touch /var/lib/cloud/instance/dr-ready
