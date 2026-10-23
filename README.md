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
make up        # environ 10 minutes depuis zéro, quelques dizaines de secondes si tout existe
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
- Docker Hub limite les téléchargements anonymes (100 par 6 h et par IP) : une dizaine d'images
  par reconstruction, donc ne pas enchaîner plus de quelques reconstructions complètes d'affilée.
- MinIO : `dl.min.io` ne sert plus de binaire, la source est la release GitHub (voir ADR 0002).
- Les cibles `disaster`, `restore` et `demo` arrivent au jalon J3.

## Preuves
`docs/preuves/<jalon>/` : sorties de commandes et durées de chaque jalon.
