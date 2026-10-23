# Checklist J2 : socle en place (23/10/2026)

Critère du jalon : `make up` construit les 3 VM, les 2 clusters, MinIO, l'application et Velero
depuis zéro ; `make destroy` les retire. Preuves : fichiers de ce dossier (sorties datées).

| Critère | Statut | Preuve |
|---------|--------|--------|
| Versions figées dans `versions.yaml`, lues par les scripts | Fait | `versions.txt` |
| Réseau `dr-net` avec réservations DHCP (.10 A, .20 B, .30 backup) | Fait | `reseau.txt` |
| 3 VM créées par script (image Ubuntu + cloud-init), dimensionnement conforme | Fait | `vm-ressources.txt`, `etat-plateforme.txt` |
| k3s figé sur A et B, kubeconfig hors dépôt | Fait | `etat-plateforme.txt` |
| MinIO figé en service systemd, disque de données séparé, bucket `velero` versionné, utilisateur limité au bucket | Fait | `minio.txt`, `make-up-from-scratch.txt` |
| PostgreSQL + écrivain (1 ligne par seconde) sur A | Fait | `application.txt` |
| Velero + Kopia sur A (lecture/écriture) et B (lecture seule) | Fait | `velero-a.txt`, `velero-b.txt`, `kopia-b-lecture.txt` |
| Test de fumée : sauvegarde sur A, visible depuis B, volume copié par Kopia | Fait | `test-de-fumee.txt` |
| `make up` idempotent (relance sans effet de bord) | Fait : 26 s | `make-up-idempotent.txt` |
| `make destroy` puis `make up` depuis zéro (A et B) | Fait : 5 min 31 s (la VM `backup` est conservée) | `make-destroy.txt`, `make-up-from-scratch.txt` |
| Destruction complète y compris `backup` puis reconstruction | À faire sur décision explicite du groupe (`make destroy-all CONFIRM_DESTROY_BACKUP=yes`) | - |
| README « de A à Z » | Fait | `README.md` |
| Essai préliminaire de restauration sur B (hors protocole J3) | Fait : 19 s, données lisibles | `essai-restauration-b.txt` |

## Mesures et observations
- Reconstruction de A et B + réinstallation de l'application et de Velero : **331 s** (5 min 31 s).
- RAM de l'hôte pendant la reconstruction : 10 Go utilisés, 5,5 Go disponibles ; swap de 0,5 Go
  occupé par des applications du bureau (navigateur, session), sans activité de swap (`si`/`so` à 0).
  Repli prévu (cluster-b à 3 Go, backup à 1,5 Go) non déclenché ; à surveiller pendant les mesures du J4.
- Le résolveur DNS amont a échoué une fois (« Could not resolve host ») pendant l'installation de
  k3s : l'installateur est désormais relancé automatiquement (risque R14).
