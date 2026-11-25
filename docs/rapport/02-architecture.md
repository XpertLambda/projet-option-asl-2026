# 2. Architecture

Le détail et le schéma sont dans [`../architecture.md`](../architecture.md) ; cette section en donne la synthèse.

## Plateforme
Un hôte Ubuntu 24.04 avec KVM/libvirt porte trois VM sur le réseau `dr-net` (192.168.100.0/24) :

| VM | Adresse | Rôle | Ressources |
|----|---------|------|------------|
| `cluster-a` | .10 | k3s, PostgreSQL, écrivain, Velero en lecture et écriture | 2 vCPU, 4 Go |
| `cluster-b` | .20 | k3s, Velero en lecture seule : cluster de reprise | 2 vCPU, 4 Go |
| `backup` | .30 | MinIO, bucket `velero` versionné | 1 vCPU, 2 Go, disque de données de 100 Go |

Principe : la cible de sauvegarde ne partage rien avec le cluster protégé.

## Application témoin
PostgreSQL (StatefulSet, volume `local-path`) et un écrivain qui insère une ligne par seconde dans
`events(id, ts)`. La dernière valeur de `ts` restaurée donne directement le point de reprise.

## Sauvegarde et reprise
- Velero sur cluster-a sauvegarde le namespace `app` toutes les 15 minutes (conservation 72 h). Les volumes
  sont copiés par Kopia, après un `CHECKPOINT` déclenché par un hook sur le pod PostgreSQL.
- Sinistre (`make disaster`) : la dernière écriture est lue sur A, t0 est relevé, la VM est détruite avec son disque.
- Reprise (`make restore`) : restauration sur B avec l'écrivain à 0 réplique, contrôle de cohérence, t1, puis
  écrivain remis en route.
- `make demo` enchaîne l'ensemble.

## Contrôle de cohérence
Avant la première nouvelle écriture : pods prêts, au moins une ligne, aucun `id` en double, `ts` croissant avec
l'`id`, aucun écart de plus de 5 s, aucune ligne postérieure à t0. Un essai qui échoue est noté `incoherent`.

## Reconstruction
`make up` construit les VM, k3s, MinIO, l'application, Velero et la planification. `make destroy` retire A et B
et garde les sauvegardes ; `make destroy-all` retire tout. Les versions sont figées dans `versions.yaml`, les
secrets sont générés sur l'hôte, hors du dépôt.
