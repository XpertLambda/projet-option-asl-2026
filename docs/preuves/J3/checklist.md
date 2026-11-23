# Checklist J3 : MVP (sauvegarde planifiée, sinistre, restauration)

Établie le 23/11/2026. Échéance du jalon : mardi 15/12/2026 18:00. Le tag `J3` n'est pas posé : décision du groupe.

Critère du jalon : sauvegarde planifiée, destruction totale de `cluster-a`, restauration complète sur `cluster-b`, données
vérifiées, avec preuves.

## Critères
| Critère | Statut | Preuve |
|---------|--------|--------|
| Sauvegarde planifiée du namespace `app` sur A (toutes les 15 min, conservée 72 h), incluse dans `make up` | Fait | `planification-velero.txt`, `reconstruction-avant-demo-2.txt` (planification créée par `make up`) |
| Hook PostgreSQL de sauvegarde (`CHECKPOINT` avant la copie du volume) | Fait ; `pg_backup_start` / `pg_backup_stop` non retenus (voir réserves) | `hooks-postgresql.txt` (`HooksAttempted: 1`, `HooksFailed: 0`) |
| `scripts/verify.sh` : pods Ready, `count(*)` > 0, aucun `id` en double, `ts` croissant avec l'`id`, aucun écart de plus de 5 s, `max(ts)` <= t0 | Fait | `demo-sinistre.txt` (VERIFY, `status=ok`) |
| Contrôle de cohérence avant la première nouvelle écriture : écrivain restauré à 0 réplique puis remis à 1 une fois le contrôle réussi | Fait (règle de restauration `k8s/velero/restore-modifier.yaml`) | `demo-sinistre.txt` |
| `scripts/disaster.sh` : `max(ts)` lu sur A en lecture seule, t0 relevé juste avant la destruction, détruit `cluster-a` seulement, refuse sans `CONFIRM_DISASTER=yes` | Fait | `demo-sinistre.txt` |
| `scripts/restore.sh` : dernière sauvegarde planifiée de l'instance détruite, restauration sur B, contrôle, t1, RTO et RPO | Fait | `demo-sinistre.txt` |
| Contrôle échoué : t1 non posé, écrivain laissé à 0, essai noté « incoherent » | Fait, exercé deux fois : essai à blanc, puis essai réel invalide | `demo-essai-invalide-1.txt` |
| `results/runs.csv` | Fait : 1 essai valide | `results/runs.csv` |
| `make backup`, `make schedule`, `make disaster`, `make restore`, `make demo` | Fait | `make help`, `demo-sinistre.txt` |
| Données restaurées vérifiées : pas de corruption, lignes continues jusqu'au point de restauration | Fait : 374 lignes, `ts` continu ; l'écart d'ids est documenté | `demo-sinistre.txt`, `ecart-id-lignes-avec-hook.md` |

## Résultat de la démonstration du 23/11/2026
| Mesure | Valeur |
|--------|--------|
| Sauvegarde restaurée | `app-15min-20261123091533` (6 s, volume de 48 Mo copié par Kopia) |
| t0 (juste avant la destruction de `cluster-a`) | 09:17:30 UTC |
| Dernière écriture connue sur A | 09:17:29.720 UTC (487 lignes) |
| Dernière écriture restaurée | 09:15:36.720 UTC (374 lignes) |
| **RTO** (t1 - t0) | **28,3 s** |
| **RPO** (écriture perdue) | **113 s** |

Un seul essai, réseau rapide : ce n'est pas une mesure au sens du protocole du J4 (au moins 3 répétitions, médiane et dispersion).
Le RPO dépend de l'âge de la dernière sauvegarde planifiée : de 0 à 15 minutes avec cette planification.

## Réserves et limites connues
- **Un seul essai valide.** Le premier essai de démonstration est invalide (`demo-essai-invalide-1.txt`) : le script acceptait des
  sauvegardes planifiées de l'instance précédente de `cluster-a`, restées dans le bucket ; corrigé (le script n'accepte plus que les
  sauvegardes terminées après la création du `cluster-a` détruit). La ligne correspondante a été retirée de `results/runs.csv`.
- **Le contrôle porte sur toute la table `events`.** Une base qui a connu une interruption de plus de 5 s ou un recul d'horloge
  (le 23/11, la table de A avant reconstruction avait 5 interruptions et 1 recul de 0,18 s) est jugée « incohérente » à la restauration
  (essai à blanc du 23/11). La démonstration est faite sur un cluster-a reconstruit juste avant. Pour le J4, il faudra décider
  si le contrôle compare à l'état de A avant le sinistre.
- **Écart d'ids après restauration** : observé trois fois (18, 32, 30 ids sans ligne), y compris avec le hook `CHECKPOINT`
  (`ecart-id-lignes-avec-hook.md`). Cause non testée ; la continuité se juge sur `ts`.
- **Hook** : seul `CHECKPOINT` est utilisé (ADR 0004). `pg_backup_start` et `pg_backup_stop` supposent la même connexion
  pour le début et la fin ; les deux hooks de Velero s'exécutent dans deux commandes distinctes. Non testé.
- **Durée de la démonstration** : jusqu'à 15 minutes d'attente de la première sauvegarde planifiée de la nouvelle instance de
  `cluster-a`, puis environ une minute (504 s le 23/11).
- **Après la démonstration**, `cluster-a` est détruit ; `make up` le reconstruit. `cluster-b` conserve l'application restaurée
  jusqu'à la prochaine restauration (le script supprime alors l'ancien namespace `app`).
- Tests faits sur un réseau rapide ; accès SSH des trois membres et cache local des images restent ouverts (checklist J2).
