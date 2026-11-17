# Checklist J2 : socle en place

Établie le 23/10/2026, **revérifiée le 15/11/2026** contre l'état réel de la plateforme
(`controle-15-11.txt` et `reconstruction-15-11.txt`), puis **reconstruction refaite le 17/11/2026**
(`reconstruction-avec-correctif.txt`). Les fichiers datés du 23/10 restent la preuve de cette date ;
ceux du 15/11 et du 17/11 confirment ou corrigent.

Critère du jalon : `make up` construit les 3 VM, les 2 clusters, MinIO, l'application et Velero
depuis zéro ; `make destroy` les retire. Échéance : vendredi 20/11/2026 18:00 (rencontre avec l'enseignant l'après-midi, pas d'oral le matin).

## Critères

| Critère | Statut au 15/11 | Preuve |
|---------|-----------------|--------|
| Versions figées dans `versions.yaml`, lues par les scripts | Fait, confirmé | `versions.txt`, `controle-15-11.txt` |
| Réseau `dr-net` avec réservations DHCP (.10 A, .20 B, .30 backup) | Fait, confirmé | `reseau.txt`, `controle-15-11.txt` |
| 3 VM créées par script (image Ubuntu + cloud-init), dimensionnement conforme (2+2+1 vCPU, 4+4+2 Go) | Fait, confirmé ; VM A et B recréées le 15/11 | `vm-ressources.txt`, `controle-15-11.txt`, `reconstruction-15-11.txt` |
| k3s figé sur A et B, kubeconfig hors dépôt (droits 600) | Fait, confirmé | `etat-plateforme.txt`, `controle-15-11.txt` |
| MinIO figé en service systemd, disque de données séparé, bucket `velero` versionné, utilisateur limité au bucket | Fait, confirmé : service actif et activé au démarrage, versionnage actif, la création d'un autre bucket est refusée à l'utilisateur Velero | `minio.txt`, `controle-15-11.txt` |
| PostgreSQL + écrivain (1 ligne par seconde) sur A | Fait, confirmé : écriture continue, aucun écart de plus de 5 s depuis le redéploiement du 15/11 | `application.txt`, `controle-15-11.txt` |
| Velero + Kopia sur A (lecture/écriture) et B (lecture seule) ; même mot de passe de dépôt Kopia sur A et B | Fait, confirmé (empreintes du mot de passe identiques) | `velero-a.txt`, `velero-b.txt`, `kopia-b-lecture.txt`, `controle-15-11.txt` |
| Test de fumée : sauvegarde sur A, visible depuis B, volume copié par Kopia | Fait ; refait le 15/11 (`smoke-20261115-220852`, visible depuis B en 30 s) | `test-de-fumee.txt`, `reconstruction-15-11.txt` |
| `make up` idempotent (relance sans effet de bord) | Fait : 26 s (23/10), 30 s (15/11) | `make-up-idempotent.txt`, `reconstruction-15-11.txt` |
| `make destroy` puis `make up` depuis zéro (A et B) | **Fait.** 23/10 : du premier coup en 5 min 31 s. 15/11 : 3 exécutions et environ 20 min, deux échecs sur `velero install --wait` (réseau lent), d'où la correction (`7540c49`, `1965aab`, `50859b9`). **17/11 : du premier coup, `make destroy` 2 s, `make up` 252 s, `make smoke` 62 s, avec la correction.** Conditions du 17/11 : réseau rapide, commit `af3f9a7`, attentes sur un état (`rollout status`, `kubectl wait`) avec un plafond de 900 s (`WAIT_TIMEOUT`). Le comportement sur réseau lent n'a pas été rejoué le 17/11 | `make-destroy.txt`, `make-up-from-scratch.txt`, `reconstruction-15-11.txt`, [`reconstruction-avec-correctif.txt`](reconstruction-avec-correctif.txt) |
| La VM `backup` est protégée contre une destruction involontaire | Fait : `destroy-vm.sh backup` refuse sans `CONFIRM_DESTROY_BACKUP=yes` (code 1), la VM reste en marche | `controle-15-11.txt` |
| Destruction complète y compris `backup` puis reconstruction | **À faire**, sur décision explicite du groupe (`make destroy-all CONFIRM_DESTROY_BACKUP=yes`) | - |
| README « de A à Z » | Fait ; durée annoncée corrigée le 15/11 (« 10 minutes » remplacé par 5 à 20 minutes selon le réseau) et `WAIT_TIMEOUT` documenté | `README.md` |
| Essai préliminaire de restauration sur B (hors protocole J3) | Fait le 23/10 (19 s, données lisibles) ; non refait le 15/11 | `essai-restauration-b.txt` |

## Ce qui reste ouvert
| Point | Pourquoi | Échéance |
|-------|----------|----------|
| Test de `make destroy-all` puis `make up` | Prouve que réseau, pools et MinIO se reconstruisent aussi ; détruit la VM `backup` | À décider par le groupe |
| Préparation de la rencontre avec l'enseignant | Chaque membre doit pouvoir expliquer chaque script | 20/11 après-midi |
| Accès SSH des trois membres à l'hôte | `~/.ssh/authorized_keys` est vide le 15/11 (prévu du 23 au 30/10 dans `docs/plan.md`) | Dès que possible |
| Cache local des images (plan B du risque R12) | Rendrait la reconstruction indépendante du débit vers Docker Hub | À décider (ADR si retenu) |
| Tag `J2` | Pas posé | Sur décision du groupe, après lecture de cette checklist |

## Mesures et observations
- 23/10 : reconstruction de A et B + réinstallation de l'application et de Velero en **331 s** (5 min 31 s).
- 15/11 : même opération en 3 exécutions de `make up`, environ **20 min** au total (21:49 à 22:09).
  Les plus grosses images Docker Hub ont pris de 1,5 à 3,5 minutes chacune (environ 0,8 Mo/s).
- 17/11 : `make destroy` (2 s), `make up` (**252 s**) et `make smoke` (62 s) en une seule exécution,
  sans échec, réseau rapide, commit `af3f9a7`.
- RAM de l'hôte le 23/10 pendant la reconstruction : 10 Go utilisés, 5,5 Go disponibles ; swap de
  0,5 Go occupé par des applications du bureau, sans activité de swap. Le 15/11 en fonctionnement :
  9,6 Go utilisés, 5,9 Go disponibles, swap à 2 Mo. Repli prévu (cluster-b à 3 Go, backup à 1,5 Go)
  non déclenché ; à surveiller pendant les mesures du J4.
- Le résolveur DNS amont a échoué une fois le 23/10 (« Could not resolve host ») pendant
  l'installation de k3s : l'installateur est relancé automatiquement (risque R14).

## Réserves connues (ajouté le 15/11)
Le contrôle du 15/11 (`reconstruction-15-11.txt`) a montré que la reconstruction dépend du débit du
réseau, ce qui concrétise deux risques du registre (`docs/risques.md`) :

| Risque | Constat du 15/11 | Traitement |
|--------|------------------|------------|
| R12 (Docker Hub) | Les images (PostgreSQL 161 Mo, Velero) sont téléchargées depuis Docker Hub à chaque reconstruction. Débit mesuré d'environ 0,8 Mo/s : 2 à 3,5 minutes par image. | Attentes des déploiements portées à 15 minutes (`WAIT_TIMEOUT`, `infra/lib.sh`) et `velero install --wait` supprimé. Pas encore de cache local des images : plan B du risque, à décider. |
| R14 (réseau amont) | Reconstruction en 3 essais et 20 minutes au lieu de 5 min 31 s le 23/10 ; deux essais ont échoué sur le délai de `velero install --wait`. | Même correction. Reconstruction du premier coup confirmée le 17/11 sur un réseau rapide (252 s) ; non rejouée sur réseau lent. |

Conséquence pour une démonstration : la durée d'une reconstruction depuis zéro n'est garantie ni
par le dépôt ni par l'hôte, elle dépend du réseau du moment.
