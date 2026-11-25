# Checklist J2 : socle en place

Établie le 23/10/2026, **revérifiée le 15/11/2026** contre l'état réel de la plateforme
(`controle-15-11.txt` et `reconstruction-15-11.txt`), puis **reconstruction refaite le 17/11/2026**
(`reconstruction-avec-correctif.txt`) et **le 18/11/2026** avec des attentes sur un état partout
(`reconstruction-attentes-sur-etat.txt`). Les fichiers datés du 23/10 restent la preuve de cette date ;
ceux du 15/11 et du 17/11 confirment ou corrigent.

Critère du jalon : `make up` construit les 3 VM, les 2 clusters, MinIO, l'application et Velero
depuis zéro ; `make destroy` les retire. Échéance : vendredi 20/11/2026 18:00 (la rencontre avec l'enseignant, prévue l'après-midi du 20/11, est reportée à la semaine suivante ; pas d'oral le matin).

## Critères

| Critère | Statut (dernière vérification) | Preuve |
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
| `make destroy` puis `make up` depuis zéro (A et B) | **Fait.** 23/10 : du premier coup en 5 min 31 s. 15/11 : 3 exécutions et environ 20 min, deux échecs sur `velero install --wait` (réseau lent), d'où la correction (`7540c49`, `1965aab`, `50859b9`). **17/11 : du premier coup, `make destroy` 2 s, `make up` 252 s, `make smoke` 62 s, avec la correction.** Conditions du 17/11 : réseau rapide, commit `af3f9a7`, attentes sur un état (`rollout status`, `kubectl wait`) avec un plafond de 900 s (`WAIT_TIMEOUT`). **18/11 : du premier coup aussi, `make destroy` 1 s, `make up` 262 s, `make smoke` 59 s, commit `ee359d0`, après remplacement des attentes à durée fixe (voir ligne suivante).** Le comportement sur réseau lent n'a été rejoué ni le 17/11 ni le 18/11 ; **rejoué le 25/11** avec un débit bridé : réussi du premier coup en 840 s (`reconstruction-reseau-lent-25-11.txt`) | `make-destroy.txt`, `make-up-from-scratch.txt`, `reconstruction-15-11.txt`, [`reconstruction-avec-correctif.txt`](reconstruction-avec-correctif.txt), [`reconstruction-attentes-sur-etat.txt`](reconstruction-attentes-sur-etat.txt) |
| Aucune attente à durée fixe courte : toutes les attentes portent sur un état, avec un plafond large | **Fait le 18/11.** Fonction `wait_for` (`infra/lib.sh`, plafond `WAIT_TIMEOUT`, 900 s par défaut) pour `k3s.yaml`, nœud `Ready`, composants système, emplacement de sauvegarde `Available`, SSH des VM, visibilité de la sauvegarde depuis B ; les déploiements utilisent `rollout status` / `kubectl wait` avec le même plafond ; santé de MinIO portée de 30 s à 5 min. Reste fixe : la pause de 10 s entre deux essais de l'installateur k3s (relance, pas une attente d'état) | `infra/lib.sh`, `infra/install-k3s.sh`, `infra/create-vm.sh`, `k8s/velero/install-velero.sh`, `scripts/verify-smoke.sh` |
| La VM `backup` est protégée contre une destruction involontaire | Fait : `destroy-vm.sh backup` refuse sans `CONFIRM_DESTROY_BACKUP=yes` (code 1), la VM reste en marche | `controle-15-11.txt` |
| Destruction complète y compris `backup` puis reconstruction | **Fait le 25/11**, sur décision du groupe : `make destroy-all` 2 s, `make up` 281 s (sans cache d'images), `make smoke` 60 s, du premier coup ; les sauvegardes d'avant sont perdues | [`destroy-all-25-11.txt`](destroy-all-25-11.txt) |
| README « de A à Z » | Fait ; durée annoncée corrigée le 15/11 (« 10 minutes » remplacé par 5 à 20 minutes selon le réseau) et `WAIT_TIMEOUT` documenté | `README.md` |
| Essai préliminaire de restauration sur B (hors protocole J3) | Fait le 23/10 (19 s, données lisibles) ; non refait le 15/11 | `essai-restauration-b.txt` |

## Ce qui reste ouvert
| Point | Pourquoi | Échéance |
|-------|----------|----------|
| Test de `make destroy-all` puis `make up` | Réseau, pools et MinIO reconstruits aussi (`destroy-all-25-11.txt`) | Fait le 25/11 |
| Préparation de la rencontre avec l'enseignant | Chaque membre doit pouvoir expliquer chaque script | Vendredi 27/11 (reportée du 20/11) |
| Accès SSH des trois membres à l'hôte | Géré hors du dépôt : les membres peuvent se connecter à la machine (déclaré par le groupe le 25/11 ; le 15/11, `~/.ssh/authorized_keys` était vide) | Fait |
| Cache local des images (plan B du risque R12) | Retenu : `make images`, ADR 0005 ; 0 téléchargement à la reconstruction | Fait le 25/11 |
| Écart entre `count(*)` et `max(id)` après restauration | Rejoué au J3 avec le hook : l'écart persiste et vérifie la pré-journalisation de 32 valeurs de la séquence (`../J3/ecart-id-lignes-avec-hook.md`) ; la continuité se juge sur `ts` | Fait (23 et 25/11) |
| Tag `J2` | Posé le 18/11/2026 avec les réserves de ce tableau | Fait |

## Mesures et observations
- 23/10 : reconstruction de A et B + réinstallation de l'application et de Velero en **331 s** (5 min 31 s).
- 15/11 : même opération en 3 exécutions de `make up`, environ **20 min** au total (21:49 à 22:09).
  Les plus grosses images Docker Hub ont pris de 1,5 à 3,5 minutes chacune (environ 0,8 Mo/s).
- 17/11 : `make destroy` (2 s), `make up` (**252 s**) et `make smoke` (62 s) en une seule exécution,
  sans échec, réseau rapide, commit `af3f9a7`.
- 18/11 : `make destroy` (1 s), `make up` (**262 s**) et `make smoke` (59 s) en une seule exécution,
  sans échec, réseau rapide, commit `ee359d0` (attentes sur un état). Sauvegarde visible depuis B en 47 s.
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
| R12 (Docker Hub) | Les images (PostgreSQL 161 Mo, Velero) sont téléchargées depuis Docker Hub à chaque reconstruction. Débit mesuré d'environ 0,8 Mo/s : 2 à 3,5 minutes par image. | Attentes des déploiements portées à 15 minutes (`WAIT_TIMEOUT`, `infra/lib.sh`) et `velero install --wait` supprimé. Cache local des images ajouté le 25/11 (ADR 0005). |
| R14 (réseau amont) | Reconstruction en 3 essais et 20 minutes au lieu de 5 min 31 s le 23/10 ; deux essais ont échoué sur le délai de `velero install --wait`. | Même correction. Reconstruction du premier coup confirmée les 17/11 (252 s) et 18/11 (262 s) sur un réseau rapide, et le 25/11 sur un réseau lent simulé (débit des VM A et B bridé à 800 Ko/s : 840 s). |

Conséquence pour une démonstration : la durée d'une reconstruction depuis zéro n'est garantie ni
par le dépôt ni par l'hôte, elle dépend du réseau du moment.
