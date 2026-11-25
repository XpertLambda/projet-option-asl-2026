# ADR 0006 : Outil d'archivage continu des WAL (stratégie S3)

- Statut : accepté (choix fait avant le J4, mise en oeuvre au J4)
- Date : 2026-11-25
- Décideurs : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO

## Contexte
La stratégie S3 (`docs/architecture.md`, section 7) archive en continu les journaux de transactions
(WAL) de PostgreSQL vers MinIO, puis restaure sur cluster-b une sauvegarde de base suivie du rejeu des
WAL. Il faut un outil qui écrive vers un stockage S3, qui s'ajoute à l'image `postgres` officielle sans
la remplacer, et qui reste léger (hôte à 4 threads).

## Options étudiées
| Outil | Stockage S3 | Ajout à l'image `postgres` | Remarques |
|-------|-------------|----------------------------|-----------|
| **WAL-G** | Oui | Un seul binaire, configuré par variables d'environnement | Binaires publiés par version et par distribution, avec empreinte |
| pgBackRest | Oui | Paquet à installer (image à construire), fichier de configuration et « stanza » | Très complet ; maintenance interrompue en avril 2026 puis reprise en mai 2026 avec des financeurs (sources consultées le 25/11/2026) |
| Barman | Oui (`barman-cloud`) | Paquet Python et dépendances | Pensé d'abord pour un serveur de sauvegarde dédié |

## Décision
**WAL-G**, version **3.0.10** (publiée le 17/11/2026), binaire `wal-g-pg-22.04-amd64`, avec son empreinte
SHA-256 figée dans `versions.yaml` au moment de la mise en oeuvre.

Règles associées :
- `archive_mode = on`, `archive_command` avec `wal-g wal-push`, **`archive_timeout = 60s`** : à une ligne
  par seconde, un segment de 16 Mo ne se remplit pas assez vite, c'est ce délai qui borne le RPO ;
- une sauvegarde de base (`wal-g backup-push`) au début de chaque essai ;
- bucket séparé de celui de Velero, avec son propre utilisateur MinIO limité à ce bucket ;
- identifiants générés au déploiement, hors Git.

## Vérification du 25/11/2026
- Archive `wal-g-pg-22.04-amd64.tar.gz` de la version 3.0.10 : empreinte SHA-256 calculée identique à celle
  publiée, `5dac31ca337fda10a0e22cf722ee751cd64d4b972fb99fe3cedac1f73f5a2fa4`.
- Le binaire s'exécute dans l'image `postgres:17.11` (Debian 13) : `wal-g --version` répond `v3.0.10`.
- Non testé : l'écriture vers MinIO, l'archivage et la restauration (J4).

## Alternative étudiée
pgBackRest : écarté pour ce projet parce qu'il demande une image PostgreSQL construite par le groupe et
une configuration plus lourde pour un seul serveur.

## Plan B
Si WAL-G ne fonctionne pas avec l'image `postgres` 17 ou avec MinIO : pgBackRest dans une image construite
à partir de l'image officielle, documenté dans un nouvel ADR. Si les deux échouent : `pg_receivewal` vers
un volume copié dans MinIO.

## Conséquences
- Un composant de plus sur cluster-a, et un script de restauration propre à S3 sur cluster-b.
- RPO attendu : au plus 60 s environ (`archive_timeout`), à mesurer.
- Non fait à ce stade : aucun archivage n'est configuré sur la plateforme.
