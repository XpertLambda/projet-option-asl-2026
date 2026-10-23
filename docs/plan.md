# Plan de travail et répartition des rôles

## Rôles

| Membre | Rôle principal | Rôle secondaire |
|--------|----------------|-----------------|
| Ahmad SAAD | Infrastructure : hôte, réseau libvirt, création des VM (cloud-init), k3s, Makefile | Revue des scripts de sauvegarde |
| Amer EL JIBBAWE | Sauvegarde : MinIO, Velero (A et B), planification, stratégies S1/S2/S3 | Soutien sur l'infrastructure |
| Ali TERRO | Application et mesures : PostgreSQL, écrivain, hooks, scripts RTO/RPO, documentation | **Reconstruction à l'aveugle au J5** |

Règle pour le J5 : Ali ne lance pas lui-même les scripts d'infrastructure avant le J5,
afin que la reconstruction soit un vrai test du README.

Chacun tient son carnet de bord individuel ; le journal de séance
(`docs/journal/AAAA-MM-JJ.md`) est rédigé à chaque créneau.

## Calendrier

| Période | Objectif | Livrables | Pilote |
|---------|----------|-----------|--------|
| 23/10 au 30/10 | Hôte prêt | Ubuntu installé, SSH pour les 3 membres, KVM/libvirt opérationnel (`kvm-ok`) | Ahmad |
| jusqu'au 06/11 | **J1 Cadrage** | Architecture, 4 ADR, registre des risques, ce plan. Tag `J1` | Tous |
| 06/11 au 13/11 | Scripts VM | `make vms` crée les 3 VM, `make destroy` les supprime | Ahmad |
| 06/11 au 20/11 | Briques | k3s sur A et B ; MinIO sur `backup` ; PostgreSQL + écrivain sur A ; Velero sur A et B | Ahmad, Amer, Ali |
| **20/11** | **J2 Socle en place** | `make up` reconstruit tout. Oral J1 + J2 le matin. Tag `J2` | Tous |
| 20/11 au 15/12 | Sinistre et reprise | `Schedule` Velero, `make disaster`, `make restore`, validation des données, premier `make demo` | Amer, Ali |
| **15/12** | **J3 MVP** | Démonstration de bout en bout avec preuves. Tag `J3` | Tous |
| 18/12 | Rédaction | Sections du rapport J1 à J3, sauvegarde de la plateforme avant les vacances | Ali |
| 04/01 au 22/01 | **J4 Extensions et mesures** | Protocole écrit, stratégies S1/S2/S3, 3 répétitions, médiane et dispersion, plan de reprise documenté. Tag `J4` | Amer, Ali |
| 29/01 | Gel | Plus aucune nouvelle fonctionnalité | Tous |
| **05/02** | **J5 Reproductibilité** | Ali détruit et reconstruit tout, chronométré et filmé. Tag `J5` | Ali |
| **12/02** | **Rendu final** | Rapport, dépôt final, `make demo`. Tag `final` | Tous |

## Définition de « terminé » pour chaque jalon
Un jalon est validé quand : le tag Git est posé, la checklist du jalon est cochée
avec ses preuves (captures, sorties de commandes, journaux) dans `docs/`, et le
journal de séance est à jour.
