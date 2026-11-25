# Projet d'option ASL-IA 2026-2027 : Sauvegarde et reprise après sinistre

Groupe : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO
Sujet : **Sujet 8, Sauvegarde et reprise après sinistre** (attribué le 22/10/2026)
Encadrant : A. ADELL, INSA Centre Val de Loire, option ASL-IA

## Objectif
Protéger une application à état (PostgreSQL) déployée sur un cluster Kubernetes,
puis démontrer qu'après la destruction totale de ce cluster, l'application et ses
données sont restaurées sur un second cluster. Les temps de reprise (RTO) et les
pertes de données (RPO) sont mesurés selon plusieurs stratégies.

Ce dépôt contient tout le nécessaire pour reconstruire la plateforme de A à Z par script.

## Vue d'ensemble
- Hôte : Ubuntu 24.04 LTS + KVM/libvirt
- VM `cluster-a` : k3s, application PostgreSQL, Velero (cluster de production)
- VM `cluster-b` : k3s, Velero (cluster de reprise)
- VM `backup` : MinIO, cible des sauvegardes, hors des deux clusters

Détails : [docs/architecture.md](docs/architecture.md)

## Arborescence
- `docs/architecture.md` : document d'architecture (J1)
- `docs/adr/` : décisions d'architecture (ADR)
- `docs/plan.md` : plan de travail, rôles, calendrier
- `docs/risques.md` : registre des risques
- `docs/journal/` : journal de séance (AAAA-MM-JJ.md)
- `infra/` : préparation de l'hôte, création des VM (libvirt, cloud-init) et installation de k3s
- `k8s/` : manifestes Kubernetes (application, Velero)
- `scripts/` : sinistre, restauration, mesures RTO/RPO

## Jalons
| Jalon | Échéance | Tag Git |
|-------|----------|---------|
| J1 Cadrage | 06/11/2026 | `J1` |
| J2 Socle en place | 20/11/2026 | `J2` |
| J3 MVP | 15/12/2026 | `J3` |
| J4 Extensions et mesures | 22/01/2027 | `J4` |
| J5 Reproductibilité | 05/02/2027 | `J5` |
| Rendu final | 12/02/2027 | `final` |

## Reconstruction de A à Z

### 0. Étapes manuelles (une seule fois, sur la machine physique)
| Étape | Détail |
|-------|--------|
| BIOS | Activer VT-x / AMD-V |
| Système | Installer Ubuntu 24.04 LTS, compte `projet`, IP fixe ou réservation DHCP |
| Accès | `ssh-copy-id projet@<IP_MACHINE>` depuis le PC de chaque membre |
| Cloner | `mkdir -p ~/projet_option && cd ~/projet_option && git clone <url du dépôt> src` |

### 1. Préparer l'hôte (sudo requis, une seule fois)
```bash
cd ~/projet_option/src
sudo ./infra/setup-host.sh projet     # KVM/libvirt, kubectl, helm, velero, image Ubuntu...
# se déconnecter puis se reconnecter (groupes libvirt et kvm), puis :
./infra/check-host.sh                 # toutes les lignes doivent être [OK]
```

### 2. Construire la plateforme
```bash
make up        # 5 à 20 minutes depuis zéro selon le débit du réseau (5 min 31 s le 23/10, environ 20 min le 15/11), environ 30 s si tout existe
make status    # VM, nœuds, emplacements de sauvegarde, pods, MinIO
make smoke     # test de fumée : sauvegarde sur A, visible depuis B
```
`make up` enchaîne, chaque étape est idempotente et peut être relancée seule :

| Cible | Script | Effet |
|-------|--------|-------|
| `check` | `infra/check-host.sh` | L'hôte est prêt (lecture seule) |
| `network` | `infra/create-storage.sh`, `infra/create-network.sh` | Pools libvirt et réseau `dr-net` (192.168.100.0/24, réservations DHCP) |
| `vms` | `infra/create-vm.sh` | VM `backup`, `cluster-a`, `cluster-b` (image Ubuntu + cloud-init) |
| `minio` | `infra/install-minio.sh` | MinIO figé sur `backup`, bucket `velero` versionné, utilisateur limité au bucket |
| `k3s` | `infra/install-k3s.sh` | k3s figé sur A et B, kubeconfig dans `~/.kube/` |
| `app` | `k8s/app/deploy.sh` | PostgreSQL + écrivain (1 ligne par seconde) sur A |
| `velero` | `k8s/velero/install-velero.sh` | Velero + Kopia sur A (lecture/écriture) et B (lecture seule) |
| (fin de `make up`) | `k8s/velero/schedule.sh` | Sauvegarde planifiée de A toutes les 15 min, conservée 72 h (`make schedule` pour l'attendre) |

### 3. Détruire
```bash
make destroy                                   # cluster-a et cluster-b ; la VM backup (les sauvegardes) reste
make destroy-all CONFIRM_DESTROY_BACKUP=yes    # tout, y compris backup et le réseau (action volontaire)
```

## Où sont les secrets (jamais dans Git)
| Fichier | Contenu |
|---------|---------|
| `~/.config/projet/minio.env` | Identifiants administrateur MinIO |
| `~/.config/projet/velero-minio.env` | Identifiants de l'utilisateur Velero (limité au bucket `velero`) |
| `~/.config/projet/velero-repo.env` | Mot de passe du dépôt Kopia, identique sur A et B |
| `~/.config/projet/postgres.env` | Mot de passe PostgreSQL |
| `~/.config/projet/ssh/id_ed25519` | Clé SSH des VM (utilisateur `ubuntu`) |
| `~/.kube/cluster-a.yaml`, `cluster-b.yaml` | Kubeconfig des clusters |
| `~/.cache/projet/` | Binaires MinIO et mc archivés (leur source amont a disparu) |

Ces fichiers sont générés au premier `make up`. Perdre `~/.config/projet/` après une
sauvegarde rend celle-ci illisible : le copier hors de l'hôte avec les sauvegardes.

## Versions
Toutes les versions sont figées dans [versions.yaml](versions.yaml) : image Ubuntu (empreinte),
k3s, Velero et plugin AWS, MinIO et mc (empreintes), PostgreSQL.

## Points manuels et pièges connus
- Le mot de passe `sudo` n'est demandé que pour `infra/setup-host.sh` (installation des paquets).
- Si un `make` échoue, le relancer : chaque étape reprend là où elle s'est arrêtée.
- Les images sont téléchargées depuis Docker Hub : avec un réseau lent (environ 1 Mo/s), chaque image
  prend plusieurs minutes. Les scripts attendent un état (déploiement prêt, nœud `Ready`, emplacement de
  sauvegarde `Available`, SSH, sauvegarde visible depuis B), sans durée fixe : le plafond de 15 minutes
  par attente (`WAIT_TIMEOUT`, en secondes avec le suffixe `s`, par exemple `WAIT_TIMEOUT=1800s make up`)
  n'est qu'une borne contre une attente infinie.
- Docker Hub limite les téléchargements anonymes (100 par 6 h et par IP) : une dizaine d'images
  par reconstruction, donc ne pas enchaîner plus de quelques reconstructions complètes d'affilée.
- MinIO : `dl.min.io` ne sert plus de binaire, la source est la release GitHub (voir ADR 0002).

## Sinistre et reprise (jalon J3)
```bash
make schedule                        # sauvegarde planifiée de A (déjà lancée par make up) ; attend la première sauvegarde
make disaster CONFIRM_DISASTER=yes   # détruit cluster-a SEULEMENT, relève max(ts) puis t0 juste avant
make restore                         # restaure la dernière sauvegarde planifiée sur cluster-b, écrivain à 0,
                                     # contrôle de cohérence, t1, RTO et RPO ajoutés à results/runs.csv
make demo CONFIRM_DISASTER=yes       # tout le scénario, avec sortie commentée
make up                              # reconstruit cluster-a après la démonstration
```
- Avant la démonstration, `cluster-a` ne doit pas avoir connu d'interruption (redémarrage de l'hôte, VM arrêtées) :
  le contrôle porte sur toute la table `events` et jugerait la restauration incohérente. Dans ce cas,
  `make destroy && make up` d'abord (la VM `backup` et les sauvegardes restent).
- `make demo` attend jusqu'à 15 minutes la première sauvegarde planifiée de l'instance actuelle de `cluster-a`
  (le bucket garde les sauvegardes des instances précédentes, `restore.sh` les refuse).
- Le contrôle de cohérence est défini dans `docs/architecture.md` (section 6) ; si le contrôle échoue, t1 n'est pas posé et
  l'essai est noté `incoherent` dans `results/runs.csv`.
- Preuves : `docs/preuves/J3/`.

## Preuves
`docs/preuves/<jalon>/` : sorties de commandes et durées de chaque jalon.
