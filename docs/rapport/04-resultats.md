# 4. Résultats au J3

## Ce qui fonctionne
| Capacité | Preuve (`../preuves/`) |
|----------|------------------------|
| Reconstruction de toute la plateforme depuis zéro, y compris la VM des sauvegardes : `make up` 281 s | `J2/destroy-all-25-11.txt` |
| Sauvegarde planifiée toutes les 15 min, hook `CHECKPOINT` | `J3/planification-velero.txt`, `J3/hooks-postgresql.txt` |
| Destruction de cluster-a et restauration sur cluster-b, avec contrôle de cohérence | `J3/demo-sinistre.txt`, `J3/demo-sinistre-2.txt`, `J3/demo-sinistre-3.txt` |
| Reconstruction depuis un clone neuf du dépôt, et sur un réseau lent simulé | `J3/reconstruction-clone-neuf.txt`, `J2/reconstruction-reseau-lent-25-11.txt` |
| Refus des manoeuvres dangereuses (sans confirmation, VM `backup`, sauvegarde d'une autre instance) | `J3/garde-fous.txt` |

## Démonstrations
| Essai (`results/runs.csv`) | 23/11 | 25/11, essai 2 | 25/11, essai 3 |
|----------------------------|-------|----------------|----------------|
| Lignes restaurées | 374 | 731 | 69 |
| RTO | 28,3 s | 19,4 s | 18,3 s |
| Première nouvelle écriture, après t0 | non relevée | environ 29 s | 19,7 s |
| RPO | 113 s | 17 s | 32 s |
| Contrôle de cohérence | réussi | réussi | réussi |

**Ces trois essais ne sont pas des mesures** : base presque vide, moment du sinistre non maîtrisé, aucune
répétition à conditions égales. Ils montrent que le scénario fonctionne. Le RPO suit surtout l'âge de la
dernière sauvegarde au moment du sinistre.

## Observations
- **Écart d'ids après restauration.** Les lignes restaurées sont continues, mais les nouvelles écritures
  sautent jusqu'à 32 identifiants. PostgreSQL journalise la séquence 32 valeurs à l'avance au premier
  `nextval` qui suit un checkpoint ; la récupération restaure cette valeur. La formule s'est vérifiée exactement
  sur deux observations (`J3/ecart-id-lignes-avec-hook.md`). Ce n'est pas une perte de données : la continuité
  se juge sur `ts`.
- **Reprise des écritures.** Elle suit t1 de 1,5 à 10 s selon l'essai ; elle est désormais relevée à chaque fois.
- **Images.** Sans cache, une reconstruction de A et B fait 15 téléchargements d'images ; avec le cache, aucun (ADR 0005).

## Limites
- Un seul hôte : il reste un point unique de défaillance, sauvegardes comprises.
- Le contrôle porte sur toute la table : une base qui a connu une interruption est jugée incohérente.
- `pg_backup_start` et `pg_backup_stop` ne sont pas utilisés ; la cohérence repose sur la récupération
  de PostgreSQL au démarrage.
- Sur un réseau lent, la reconstruction réussit mais dure environ 14 min au lieu de 4 à 5 (840 s à 800 Ko/s,
  `J2/reconstruction-reseau-lent-25-11.txt`).
- MinIO Community n'est plus maintenu ; une vulnérabilité connue n'est pas corrigée dans le binaire utilisé.

## Suite (J4)
Protocole arrêté avant toute mesure : [`../mesures/protocole.md`](../mesures/protocole.md). Trois stratégies
(Velero planifié à deux périodes, `pg_dump`, archivage des WAL), 1 000 000 de lignes, au moins 3 répétitions,
médiane et dispersion. Restent à écrire : S2, S3, les scripts de mesure et d'analyse, le plan de reprise.
