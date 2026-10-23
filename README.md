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

## Reconstruction
Procédure complète à partir du jalon J2 (`make up`, `make backup`, `make disaster`,
`make restore`, `make demo`).
