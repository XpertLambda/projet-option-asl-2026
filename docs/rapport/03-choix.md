# 3. Choix

## Décisions
| ADR | Sujet | Décision | Raison principale | Alternative écartée |
|-----|-------|----------|-------------------|---------------------|
| [0001](../adr/0001-outil-sauvegarde.md) | Outil de sauvegarde | Velero | Libre, ressources et volumes, restauration sur un autre cluster | Kasten K10, `pg_dump` seul, snapshot etcd |
| [0002](../adr/0002-stockage-sauvegardes.md) | Stockage | MinIO sur une VM dédiée | Les sauvegardes survivent à la perte de A | MinIO dans un cluster, NFS |
| [0003](../adr/0003-os-virtualisation.md) | Socle | Ubuntu 24.04, KVM/libvirt, k3s | Scriptable et léger | OpenStack, Proxmox, kubeadm, kind |
| [0004](../adr/0004-copie-volumes.md) | Copie des volumes | File System Backup (Kopia) et hook `CHECKPOINT` | `local-path` n'a pas de snapshots CSI | Snapshots CSI, Restic |
| [0005](../adr/0005-cache-images.md) | Images | Cache local sur l'hôte | Ne plus dépendre de Docker Hub | Registre miroir, compte Docker Hub |
| [0006](../adr/0006-archivage-wal.md) | Archivage des WAL (S3) | WAL-G | Un binaire ajouté à l'image officielle | pgBackRest, Barman |

## Ce qui a changé par rapport au cadrage
- **Hook PostgreSQL.** Le cadrage prévoyait `CHECKPOINT`, `pg_backup_start` et `pg_backup_stop`. Seul
  `CHECKPOINT` est utilisé : les hooks `pre` et `post` de Velero sont deux commandes sans session commune
  (ADR 0004, précisé le 23/11). La variante à session maintenue n'a pas été testée.
- **Attentes à durée fixe.** La reconstruction échouait sur un réseau lent (15/11). Toutes les attentes portent
  désormais sur un état, avec un plafond de 15 minutes.
- **MinIO.** `dl.min.io` ne sert plus de binaire : la dernière version officielle est prise sur GitHub, avec son
  empreinte ; une vulnérabilité connue n'est pas corrigée dans ce binaire (ADR 0002).
- **Sauvegardes d'une instance précédente.** Le bucket les conserve après la destruction de A. La reprise refuse
  désormais toute sauvegarde antérieure à l'instance détruite.
