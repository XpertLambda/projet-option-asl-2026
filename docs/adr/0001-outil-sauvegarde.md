# ADR 0001 : Outil de sauvegarde du cluster

- Statut : accepté
- Date : 2026-10-23
- Décideurs : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO

## Contexte
Il faut sauvegarder une application à état sur Kubernetes (manifestes, secrets,
volumes persistants PostgreSQL), puis la restaurer intégralement sur **un autre
cluster** après destruction du premier. L'outil doit être libre, scriptable, et
fonctionner avec un stockage objet S3 auto-hébergé.

## Options étudiées

| Critère | Velero | Kasten K10 | `pg_dump` en CronJob | Snapshot etcd k3s |
|---------|--------|------------|----------------------|-------------------|
| Licence | Apache 2.0, CNCF | Propriétaire (gratuit limité) | Libre | Libre |
| Ressources K8s | Oui | Oui | Non | Oui |
| Données des volumes | Oui (Kopia ou CSI) | Oui | Base seulement | Non |
| Restauration sur autre cluster | Oui, natif | Oui | Manuelle | Même cluster seulement |
| Planification | `Schedule` intégré | Oui | CronJob | Oui |
| Cible S3 (MinIO) | Oui | Oui | Via script | Oui |
| Pilotable en CLI / scripts | Oui | Surtout via interface web | Oui | Oui |

## Décision
Nous retenons **Velero**.

Raisons :
- seul outil libre qui couvre à la fois les ressources Kubernetes et les volumes ;
- restauration sur un autre cluster prévue nativement (même `BackupStorageLocation`) ;
- entièrement pilotable par la CLI `velero`, donc scriptable dans le Makefile ;
- outil de référence de la CNCF, bien documenté.

## Alternatives rejetées
- **Kasten K10** : fonctionnellement complet, mais propriétaire et orienté interface
  web, ce qui va contre la reconstruction par script.
- **`pg_dump` seul** : ne sauvegarde pas les ressources Kubernetes ; la reprise
  demanderait de redéployer à la main. Il reste utile comme **stratégie comparée
  au J4** (S2).
- **Snapshot etcd** : sauvegarde l'état du cluster, pas les données des volumes, et
  se restaure sur le même cluster.

## Plan B
Si Velero ne parvient pas à restaurer correctement les volumes : manifestes
versionnés dans Git (redéploiement par `kubectl apply`) + `pg_dump` en CronJob vers
MinIO, restauré par `pg_restore` sur le cluster B.

## Conséquences
- Velero doit être installé sur les deux clusters, avec la même version.
- Il faut choisir comment Velero copie les volumes : voir ADR 0004.
- Il faut un stockage S3 hors cluster : voir ADR 0002.
