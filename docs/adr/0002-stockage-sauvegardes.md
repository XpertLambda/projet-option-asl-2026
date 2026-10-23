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
- version de MinIO figée sur le dernier binaire officiel publié, notée dans
  `versions.yaml` avec son empreinte SHA-256 (voir « Vérification » ci-dessous).

## Vérification du 23/10/2026
- `dl.min.io` répond désormais « 410 Gone » pour le serveur et pour `mc` : plus aucun
  binaire n'est servi par ce site.
- Le dernier binaire officiel est celui de la release GitHub
  `RELEASE.2025-09-07T16-13-09Z` (`minio.linux-amd64.RELEASE.2025-09-07T16-13-09Z`,
  avec fichier `.sha256sum`). La release suivante (`RELEASE.2025-10-15T17-29-55Z`) ne
  contient que le code source.
- Ce binaire ne contient pas le correctif de la CVE GHSA-jjjj-jwhf-8rgr (élévation de
  privilèges via les politiques de session des comptes de service et STS, corrigée
  seulement dans le code source de la release du 15/10). Atténuation : réseau `dr-net`
  isolé derrière le NAT de l'hôte, aucun usage de STS ni de comptes de service, un seul
  utilisateur applicatif pour Velero. Risque accepté pour un banc d'essai, à mentionner
  dans le rapport.
- Le client `mc` (nécessaire pour créer le bucket, l'utilisateur et la politique) est
  dans le même cas : binaire `mc.RELEASE.2025-08-13T08-35-41Z` sur GitHub.
- Le binaire et son empreinte sont archivés dans `~/.cache/projet/` sur l'hôte, car la
  source amont peut disparaître (risque R3).

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
