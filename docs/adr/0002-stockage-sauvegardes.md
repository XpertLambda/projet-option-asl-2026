# ADR 0002 : Stratégie de stockage des sauvegardes

- Statut : accepté
- Date : 2026-10-23
- Décideurs : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO

## Contexte
Les sauvegardes doivent survivre à la destruction totale du cluster A et être
lisibles par le cluster B. Velero écrit dans un stockage objet compatible S3. Le
sujet impose MinIO comme stockage objet.

Point d'attention : MinIO Community Edition n'est plus maintenu en amont. Les images
Docker et binaires publics ne sont plus publiés depuis octobre 2025, le projet est
passé en mode maintenance en décembre 2025, puis le dépôt a été archivé en 2026.

## Options étudiées

| Option | Survit à la perte de A | Isolation | Complexité |
|--------|------------------------|-----------|------------|
| MinIO dans le cluster A | **Non** (perdu avec A) | Aucune | Faible |
| MinIO dans le cluster B | Oui | Partielle (B est aussi la cible de reprise) | Faible |
| **MinIO sur une VM dédiée** | Oui | Totale | Moyenne |
| Partage NFS | Oui | Totale | Moyenne, non S3 (incompatible avec Velero sans passerelle) |
| Stockage cloud public | Oui | Totale | Exclu : pas de cloud externe |

## Décision
**MinIO sur une VM dédiée (`backup`)**, hors des deux clusters, avec un disque de
données séparé.

Règles associées :
- un bucket `velero`, avec versionnage activé ;
- un utilisateur MinIO dédié à Velero, dont la politique est limitée à ce bucket ;
- cluster A : `BackupStorageLocation` en lecture/écriture ;
- cluster B : même emplacement, en **lecture seule** (`accessMode: ReadOnly`), pour
  ne jamais modifier les sauvegardes pendant une reprise ;
- rétention : TTL Velero de 72 h pendant les tests, ajusté au J4 ;
- version de MinIO figée (dernier binaire officiel publié), notée dans `versions.yaml`.

## Alternatives rejetées
- **MinIO dans A** : contredit l'objectif ; détruire A détruit les sauvegardes.
- **MinIO dans B** : B serait à la fois cible de reprise et coffre des sauvegardes ;
  un incident sur B ferait tout perdre.
- **NFS** : Velero attend un stockage objet.

## Plan B
Si le binaire MinIO figé pose problème (indisponible, incompatible) : **Garage** ou
**SeaweedFS**, deux stockages objet libres compatibles S3, sur la même VM. Velero ne
voit pas la différence (plugin AWS, même configuration S3). Le changement serait
documenté dans un nouvel ADR.

## Conséquences
- Une troisième VM à dimensionner et à scripter.
- L'hôte reste un point unique de défaillance (limite documentée) ; extension
  possible : placer `backup` sur une seconde machine physique.
- Extension possible au J4 : verrouillage des objets (immuabilité) contre la
  suppression des sauvegardes.
