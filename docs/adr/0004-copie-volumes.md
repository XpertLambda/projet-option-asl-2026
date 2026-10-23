# ADR 0004 : Méthode de copie des volumes persistants

- Statut : accepté
- Date : 2026-10-23
- Décideurs : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO

## Contexte
Velero sait sauvegarder les données des volumes de deux façons : par **snapshots
CSI** (instantané pris par le pilote de stockage) ou par **File System Backup**
(le `node-agent` lit les fichiers du volume et les envoie vers S3 avec Kopia).
k3s fournit par défaut `local-path-provisioner`, qui ne gère pas les snapshots CSI.
La base PostgreSQL écrit en continu : une copie de fichiers « à chaud » peut être
incohérente.

## Options étudiées

| Option | Fonctionne avec local-path | Cohérence | Complexité |
|--------|----------------------------|-----------|------------|
| Snapshots CSI | Non (il faudrait Longhorn ou un autre pilote CSI) | Instantané | Élevée |
| **File System Backup (Kopia)** | Oui | Copie à chaud, à rendre cohérente par un hook | Faible |
| File System Backup (Restic) | Oui | Idem | Faible, mais moteur déprécié par Velero |

## Décision
**Velero File System Backup avec Kopia** (`--use-node-agent`,
`--default-volumes-to-fs-backup`).

Pour la cohérence de PostgreSQL, un **hook Velero** est ajouté sur le pod de base :
- `pre` : `CHECKPOINT` puis `pg_backup_start()` (ou `fsfreeze` du volume) ;
- `post` : `pg_backup_stop()`.
Sans hook, la copie reste restaurable (PostgreSQL rejoue ses WAL au démarrage, comme
après une coupure de courant), mais le hook rend la cohérence explicite.

## Alternatives rejetées
- **Snapshots CSI** : demande d'installer Longhorn, ce qui ajoute un composant lourd
  sans rapport direct avec le sujet. Envisageable en extension J4 pour comparer.
- **Restic** : remplacé par Kopia dans les versions récentes de Velero.

## Plan B
Si le File System Backup échoue sur PostgreSQL : sauvegarde logique (`pg_dump`)
vers MinIO en complément de Velero, restaurée par `pg_restore` (voir ADR 0001).

## Conséquences
- Le `node-agent` (DaemonSet) doit tourner sur les deux clusters.
- Les sauvegardes sont incrémentales côté Kopia : on mesurera au J4 la taille et la
  durée des sauvegardes successives.
