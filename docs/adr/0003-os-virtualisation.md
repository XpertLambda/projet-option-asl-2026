# ADR 0003 : Système hôte, virtualisation et distribution Kubernetes

- Statut : accepté
- Date : 2026-10-23
- Décideurs : Ahmad SAAD, Amer EL JIBBAWE, Ali TERRO

## Contexte
Le sujet demande deux environnements indépendants. Nous disposons d'une machine
vierge. Le mail de cadrage autorise un OpenStack all-in-one ou des VM KVM/libvirt,
puis un Kubernetes léger. Tout doit être reconstructible par script.

## Options étudiées

### Socle de virtualisation
| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **KVM/libvirt + cloud-init** | Léger, entièrement scriptable (`virt-install`, `virsh`), destruction d'une VM triviale | Pas d'interface web (virt-manager en option) |
| OpenStack all-in-one (Kolla-Ansible) | Proche d'un vrai cloud | Lourd (RAM), long à installer, hors sujet ici, déjà source de blocage |
| Proxmox VE | Interface web pratique | Système dédié, pousse aux actions manuelles, scripts via API plus lourds |

### Système hôte
| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **Ubuntu 24.04 LTS** | Support jusqu'en 2029, KVM et cloud-init natifs, documentation k3s/Velero testée dessus | - |
| Debian 12/13 | Stable, léger | Moins de documentation ciblée |
| Rocky Linux | Orienté entreprise | SELinux ajoute des frictions sans bénéfice ici |

### Kubernetes
| Option | Avantages | Inconvénients |
|--------|-----------|---------------|
| **k3s** | Installation en une commande, faible empreinte, stockage local et ingress fournis | Moins proche d'un cluster kubeadm standard |
| kubeadm | Standard | Plus long à installer et à automatiser |
| kind / k3d | Très rapide | Clusters dans des conteneurs : la destruction d'un « cluster » est moins réaliste |

## Décision
- Hôte : **Ubuntu 24.04 LTS** (Desktop ou Server ; avec 15 Go de RAM, Server laisse
  environ 1,5 Go de plus aux VM).
- Virtualisation : **KVM/libvirt**, VM créées à partir de l'image cloud Ubuntu 24.04
  et configurées par **cloud-init**.
- Kubernetes : **k3s**, un nœud par cluster.

## Plan B
- Si cloud-init pose problème : Vagrant avec le fournisseur libvirt.
- Si k3s pose problème : kubeadm sur les mêmes VM.
- Si l'hôte manque de RAM : `backup` réduite à 1 Go, ou MinIO directement sur l'hôte
  (isolation moindre, documentée).

## Conséquences
- Le sinistre se simule proprement par destruction de la VM et de son disque.
- Les scripts `infra/` dépendent de `virt-install`, `cloud-localds` et `virsh`.
