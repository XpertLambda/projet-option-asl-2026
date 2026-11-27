# Checklist J3 : MVP (sauvegarde planifiée, sinistre, restauration)

Établie le 23/11/2026, mise à jour les 25 et 27/11/2026. Échéance du jalon : mardi 15/12/2026 18:00.

**Statut au 27/11/2026 : J3 en cours de test, non validé.** Un tag `J3` posé le 25/11 sur `6381e2a` a été retiré le 27/11
à la demande du groupe ; il sera posé de nouveau quand le groupe validera le jalon. « Fait » ci-dessous veut dire
réalisé et essayé, pas validé.

Critère du jalon : sauvegarde planifiée, destruction totale de `cluster-a`, restauration complète sur `cluster-b`, données
vérifiées, avec preuves.

## Critères
| Critère | Statut | Preuve |
|---------|--------|--------|
| Sauvegarde planifiée du namespace `app` sur A (toutes les 15 min, conservée 72 h), incluse dans `make up` | Fait | `planification-velero.txt`, `reconstruction-avant-demo-2.txt` (planification créée par `make up`) |
| Hook PostgreSQL de sauvegarde (`CHECKPOINT` avant la copie du volume) | Fait ; `pg_backup_start` / `pg_backup_stop` non retenus (voir réserves) | `hooks-postgresql.txt` (`HooksAttempted: 1`, `HooksFailed: 0`) |
| `scripts/verify.sh` : pods Ready, `count(*)` > 0, aucun `id` en double, `ts` croissant avec l'`id`, aucun écart de plus de 5 s, `max(ts)` <= t0 | Fait | `demo-sinistre.txt`, `demo-sinistre-2.txt` (VERIFY, `status=ok`) |
| Contrôle de cohérence avant la première nouvelle écriture : écrivain restauré à 0 réplique puis remis à 1 une fois le contrôle réussi | Fait (règle de restauration `k8s/velero/restore-modifier.yaml`) | `demo-sinistre.txt` |
| `scripts/disaster.sh` : `max(ts)` lu sur A en lecture seule, t0 relevé juste avant la destruction, détruit `cluster-a` seulement, refuse sans `CONFIRM_DISASTER=yes` | Fait | `demo-sinistre.txt` |
| `scripts/restore.sh` : dernière sauvegarde planifiée de l'instance détruite, restauration sur B, contrôle, t1, RTO et RPO | Fait | `demo-sinistre.txt` |
| Contrôle échoué : t1 non posé, écrivain laissé à 0, essai noté « incoherent » | Fait, exercé deux fois : essai à blanc, puis essai réel invalide | `demo-essai-invalide-1.txt` |
| Garde-fous : sinistre et démonstration refusés sans confirmation, VM `backup` protégée, sauvegarde d'une instance précédente de A refusée | Fait (25/11) | `garde-fous.txt` |
| Ajout du 27/11 : la démonstration s'arrête sans rien détruire si cluster-a échoue déjà au contrôle ; un sinistre n'est enregistré qu'une fois dans `results/runs.csv` | Fait (27/11), testé en réel | `garde-fous-27-11.txt` |
| `results/runs.csv` | Fait : 4 essais valides | `results/runs.csv` |
| `make backup`, `make schedule`, `make disaster`, `make restore`, `make demo` | Fait | `make help`, `demo-sinistre.txt` |
| Données restaurées vérifiées : pas de corruption, lignes continues jusqu'au point de restauration | Fait : 374, 731, 69 puis 731 lignes, `ts` continu ; l'écart d'ids est documenté | `demo-sinistre.txt`, `demo-sinistre-2.txt`, `demo-sinistre-3.txt`, `demo-sinistre-4.txt`, `ecart-id-lignes-avec-hook.md` |
| Reconstruction depuis zéro avant la démonstration, puis de `cluster-a` après | Fait (25/11) : `make destroy` 1 s, `make up` 228 s, `make smoke` 59 s | `reconstruction-demo-2.txt`, `apres-demo-2.txt` |
| Ajouts : reconstruction depuis un clone neuf du dépôt ; sur réseau lent simulé ; de `cluster-a` après un redémarrage de l'hôte | Fait : 223 s (25/11), 840 s (25/11), 141 s (27/11) | `reconstruction-clone-neuf.txt`, `../J2/reconstruction-reseau-lent-25-11.txt`, `reconstruction-27-11.txt` |

## Résultats des démonstrations
| Mesure | 23/11 | 25/11, matin | 25/11, midi | 27/11 |
|--------|-------|----------------|----------------------|----------------------|
| Sauvegarde restaurée | `app-15min-20261123091533` | `app-15min-20261125093021` | `app-15min-20261125103041` | `app-15min-20261127100007` |
| Durée de la sauvegarde, volume copié par Kopia | 6 s, 48 Mo | 6 s, 48 Mo | 6 s, 48 Mo | 7 s, 48 Mo |
| t0 (juste avant la destruction de `cluster-a`, UTC) | 09:17:30 | 09:30:41 | 10:31:15 | 10:00:33 |
| Dernière écriture connue sur A (lignes) | 09:17:29.720 (487) | 09:30:40.914 (748) | 10:31:15.376 (101) | 10:00:32.482 (752) |
| Dernière écriture restaurée (lignes) | 09:15:36.720 (374) | 09:30:23.914 (731) | 10:30:43.376 (69) | 10:00:11.482 (731) |
| **RTO** (t1 - t0) | **28,3 s** | **19,4 s** | **18,3 s** | **24,0 s** |
| Première nouvelle écriture sur B, après t0 | non relevée | environ 29 s | 19,7 s | 35,2 s |
| **RPO** (écriture perdue) | **113 s** | **17 s** | **32 s** | **21 s** |
| Durée totale de `make demo` | 504 s | 670 s | 21 s (sauvegarde déjà là) | 722 s |

Quatre essais, réseau rapide : ce ne sont pas des mesures au sens du protocole du J4 (au moins 3 répétitions, médiane et
dispersion). Le RPO dépend de l'âge de la dernière sauvegarde planifiée : de 0 à 15 minutes avec cette planification.
`make demo` détruit A dès que la sauvegarde est visible depuis B : les 25 et 27/11 le RPO est donc proche du meilleur cas.

## Réserves et limites connues
- **Quatre essais valides seulement.** Le tout premier essai de démonstration est invalide (`demo-essai-invalide-1.txt`) : le script acceptait des
  sauvegardes planifiées de l'instance précédente de `cluster-a`, restées dans le bucket ; corrigé (le script n'accepte plus que les
  sauvegardes terminées après la création du `cluster-a` détruit). La ligne correspondante a été retirée de `results/runs.csv`.
- **Le contrôle porte sur toute la table `events`.** Une base qui a connu une interruption de plus de 5 s ou un recul d'horloge
  (le 23/11, la table de A avant reconstruction avait 5 interruptions et 1 recul de 0,18 s) est jugée « incohérente » à la restauration
  (essai à blanc du 23/11). La démonstration est faite sur un cluster-a reconstruit juste avant. Pour le J4, décision du groupe
  du 23/11 : le contrôle reste strict et cluster-a est reconstruit avant chaque essai.
- **Écart d'ids après restauration** : observé à chaque restauration (au plus 32 ids sans ligne), y compris avec le
  hook `CHECKPOINT`. Les valeurs vérifient exactement la pré-journalisation de 32 valeurs de la séquence sur deux
  observations avec l'heure du checkpoint (`ecart-id-lignes-avec-hook.md`). La continuité se juge sur `ts`.
- **Le RTO ne compte pas la reprise des écritures.** t1 est posé quand la base répond et que le contrôle a réussi ;
  l'écrivain est ensuite remis à 1. La première ligne sur B est arrivée environ 10 s après t1 au premier essai du
  25/11, 1,5 s après au second et 11 s après le 27/11 (cause de l'écart non recherchée). Décision : t1 inchangé, et la première écriture
  est relevée en plus par `restore.sh` (depuis le 25/11 à midi).
- **Hook** : seul `CHECKPOINT` est utilisé (ADR 0004). `pg_backup_start` et `pg_backup_stop` supposent la même connexion
  pour le début et la fin ; les deux hooks de Velero s'exécutent dans deux commandes distinctes. Non testé.
- **Durée de la démonstration** : jusqu'à 15 minutes d'attente de la première sauvegarde planifiée de la nouvelle instance de
  `cluster-a`, puis environ une minute (504 s le 23/11, 670 s le 25/11, 722 s le 27/11).
- **Une base interrompue ne permet pas la démonstration** (redémarrage de l'hôte, VM arrêtées) : `make demo` s'arrête
  sans rien détruire (depuis le 27/11), il faut reconstruire A (`./infra/destroy-vm.sh cluster-a && make up`).
  `make disaster` seul ne fait pas ce contrôle.
- **Après la démonstration**, `cluster-a` est détruit ; `make up` le reconstruit. `cluster-b` conserve l'application restaurée
  jusqu'à la prochaine restauration (le script supprime alors l'ancien namespace `app`).
- Tests faits sur un réseau rapide. Ajoutés depuis le 25/11 à midi : cache local des images (ADR 0005), `make destroy-all` testé
  (`../J2/destroy-all-25-11.txt`), protocole du J4 écrit (`../../mesures/protocole.md`).
