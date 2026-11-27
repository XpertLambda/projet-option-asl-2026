# 1. Contexte

## Sujet
Sujet 8, « Sauvegarde et reprise après sinistre », attribué le 22/10/2026 (encadrant : A. ADELL). Prérequis
du sujet : deux environnements installés par le groupe et un stockage objet MinIO.

## Problème
Une application à état perd ses données si son cluster disparaît et que les sauvegardes disparaissent avec
lui. Le projet vise à montrer qu'après la destruction totale d'un cluster, l'application et ses données
reviennent sur un second cluster, et à chiffrer ce que cela coûte :

- **RTO** : temps entre le sinistre et le retour du service ;
- **RPO** : écritures perdues, exprimées en temps.

## Jalons
| Jalon | Échéance | Attendu | État au 25/11 |
|-------|----------|---------|---------------|
| J1 Cadrage | 06/11/2026 | Architecture, ADR, risques, plan | Validé en retard (tag `J1` du 15/11) |
| J2 Socle | 20/11/2026 | Plateforme reconstructible par script | Validé (tag `J2` du 18/11) |
| J3 MVP | 15/12/2026 | Sauvegarde, sinistre, restauration, preuves | En cours de test (non validé ; tag `J3` du 25/11 retiré le 27/11) |
| J4 Mesures | 22/01/2027 | RTO et RPO de plusieurs stratégies, plan de reprise | Non commencé |

## Contraintes
- Une seule machine physique : 4 threads CPU, 15 Go de RAM, 428 Go de disque.
- Pas de cloud externe.
- Tout doit se reconstruire par script depuis le dépôt (reconstruction par un membre au J5).
- Mesures selon un protocole écrit à l'avance, au moins 3 répétitions.
