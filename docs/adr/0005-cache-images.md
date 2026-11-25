# ADR 0005 : Cache local des images sur l'hôte

- Statut : accepté
- Date : 2026-11-25
- Décideurs : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO

## Contexte
Chaque reconstruction télécharge les images depuis Docker Hub : le 25/11, 9 téléchargements sur cluster-a et
6 sur cluster-b. Deux risques du registre sont concernés : R12 (limite de 100 téléchargements anonymes par
6 h) et R14 (réseau amont instable : le 15/11, une reconstruction a pris environ 20 min au lieu de 5). Au J4,
cluster-a est reconstruit avant chaque essai.

## Options étudiées
| Option | Composant ajouté | Remarques |
|--------|------------------|-----------|
| Ne rien faire | Aucun | Dépend du débit et de la limite de Docker Hub |
| **Archive d'images sur l'hôte, importée par k3s** | Aucun (un script) | À refaire quand une version change ; import à chaque reconstruction |
| Registre miroir sur la VM `backup` | Un service de plus sur une VM de 2 Go | Évite l'import complet, mais un composant à installer et maintenir |
| Compte Docker Hub | Un secret de plus | Relève la limite, ne règle pas le débit |

## Décision
**Archive d'images sur l'hôte** (`make images`, `infra/cache-images.sh`) :
- les images étiquetées de cluster-a sont exportées dans `~/.cache/projet/images/` (hors Git, 339 Mo, 8 images) ;
- `infra/install-k3s.sh` la dépose dans `/var/lib/rancher/k3s/agent/images/` avant d'installer k3s ;
- le nœud démarre avec une marque (taint) qui empêche tout pod tant que les images ne sont pas importées ;
- `IMAGE_CACHE=no make up` reconstruit sans le cache ; sans archive, rien ne change.

## Vérification du 25/11 (`docs/preuves/J3/cache-images.txt`)
| Reconstruction de A et B | Téléchargements (A, B) | `make up` |
|--------------------------|------------------------|-----------|
| Sans cache, après `make destroy-all` | 9, 6 | 281 s |
| Première version (références `@sha256` exportées, sans marque) | 6, 6 | 364 s |
| **Version retenue** | **0, 0** | 429 s (attente de l'import : 105 s sur A, 50 s sur B) |

Reconstruction de **cluster-a seul** (cas des essais du J4) : 124 s avec le cache et aucun téléchargement
(`docs/preuves/J3/reconstruction-a-avec-cache.txt`), contre 179 s sans cache le même jour
(`docs/preuves/J3/apres-demo-2.txt`).

La première version ne fonctionnait pas : k3s ne sait pas réétiqueter les références `@sha256` et importe les
images en parallèle du démarrage des pods.

## Alternative étudiée
Registre miroir sur la VM `backup` : non retenu, un composant de plus pour un besoin ponctuel.

## Plan B
Si l'import devient un problème (durée, version de k3s) : `IMAGE_CACHE=no` (comportement précédent), puis
registre miroir sur la VM `backup`.

## Conséquences
- La reconstruction ne dépend plus de Docker Hub. Les binaires (k3s, paquets des VM) viennent toujours
  d'Internet.
- Sur un réseau rapide : reconstruction de A et B ensemble **plus lente** avec le cache (429 s contre 281 s),
  reconstruction de cluster-a seul plus rapide (124 s contre 179 s). Pour tout reconstruire quand le réseau est
  bon : `IMAGE_CACHE=no`.
- La reconstruction « à froid » du J5 se fait sur une machine ou un compte sans archive, ou avec
  `IMAGE_CACHE=no`.
