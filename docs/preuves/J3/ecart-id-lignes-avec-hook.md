# Écart entre `count(*)` et `max(id)` avec le hook `CHECKPOINT` (23/11/2026)

Troisième observation du phénomène décrit dans `docs/preuves/J2/ecart-id-lignes.md` (deux observations sans
hook le 17/11 : 18 puis 32 ids sans ligne). Celle-ci vient de la démonstration J3
(`docs/preuves/J3/demo-sinistre.txt`) : sauvegarde planifiée `app-15min-20261123091533` avec le hook
`CHECKPOINT` (`HooksAttempted: 1`, `HooksFailed: 0`), restauration sur cluster-b. Ce document ne contient que
ce que les requêtes ont montré.

## Observations
| Mesure | Résultat |
|--------|----------|
| Contrôle de cohérence avant la reprise de l'écrivain (écrivain à 0 réplique) | 374 lignes, `max(id)` = 374 (écart 0), aucun doublon, `ts` croissant, aucun écart de plus de 5 s, `max(ts)` 09:15:36 UTC |
| Journal PostgreSQL sur cluster-b | `last known up at 2026-11-23 09:15:33 UTC`, puis `not properly shut down; automatic recovery in progress` |
| Heure de début de la sauvegarde | 10:15:33 CET, soit 09:15:33 UTC |
| Après la reprise de l'écrivain (09:18:22 UTC) | 397 lignes, `max(id)` = 427, `max(id) - count(*)` = **30** |
| ids sans ligne | 375 à 404 (30 ids) |
| `events_id_seq.last_value` | 427 |
| Lignes autour du trou | id 374 à 09:15:36, puis des ids supérieurs à 404 après la reprise |

## Comparaison avec les observations sans hook
| | 17/11 obs. 1 | 17/11 obs. 2 | 23/11 avec hook |
|---|---|---|---|
| ids sans ligne sur cluster-b après la reprise | 18 | 32 | 30 |
| Écart nul avant la reprise de l'écrivain | oui | oui | oui |
| Récupération automatique au démarrage | oui | oui | oui |
| Contrôle de cohérence (`ts`, doublons, écarts) | non défini | non défini | réussi |

## Ce que cette observation établit
1. Avec le hook `CHECKPOINT`, l'écart d'ids après restauration **existe toujours** (30). Le hook ne le supprime pas.
2. Les trois écarts observés (18, 32, 30) sont inférieurs ou égaux à 32.
3. La valeur `last known up at` (09:15:33 UTC) est l'heure de début de la sauvegarde, c'est-à-dire du hook
   `CHECKPOINT`. Cela concorde avec l'hypothèse 1 de `docs/preuves/J2/ecart-id-lignes.md` (heure du dernier checkpoint
   enregistrée dans les fichiers copiés).
4. La continuité des données restaurées se juge sur `ts` : le contrôle de cohérence de
   `docs/architecture.md` (section 6) est réussi, un trou d'ids n'est pas une anomalie.

## Ce qui n'est pas établi
- La cause de l'avance de la séquence (non testée). Les hypothèses du 17/11 (checkpoint, pré-journalisation de
  32 valeurs de la séquence) restent des hypothèses : trois observations ne les démontrent pas.
- Si l'écart suit une règle : trois valeurs (18, 32, 30) ne suffisent pas.

## Quatrième observation (25/11/2026) : séquence lue avant la reprise de l'écrivain
Démonstration `demo-sinistre-2.txt`, sauvegarde `app-15min-20261125093021` (09:30:21 à 09:30:27 UTC,
`hooksAttempted: 1`). Cette fois `last_value` est lue par `scripts/restore.sh` juste après la restauration,
l'écrivain étant à 0 réplique. Les heures sont en UTC.

### Journaux PostgreSQL
Sur cluster-a (copié avant sa destruction), checkpoint déclenché par le hook :
```
09:30:22.532  checkpoint starting: immediate force wait
09:30:22.551  checkpoint complete: ... lsn=0/19CD948, redo lsn=0/19CD8F0
```
Sur cluster-b, au démarrage après restauration :
```
09:30:58  database system was interrupted; last known up at 2026-11-25 09:30:22 UTC
09:30:59  database system was not properly shut down; automatic recovery in progress
09:30:59  redo starts at 0/19CD8F0
```

### Lignes et séquence
| Mesure sur cluster-b | Résultat |
|----------------------|----------|
| Avant la reprise de l'écrivain : `count(*)`, `max(id)` | 731, 731 (aucun id manquant) |
| Avant la reprise de l'écrivain : `last_value`, `is_called` | **762**, `t` |
| Après la reprise : ids sans ligne | 732 à 762 (**31**) |
| Après la reprise : lignes autour du trou | id 731 à 09:30:23.914, puis id 763 à 09:31:10.852 |

| id | `ts` | Position |
|----|------|----------|
| 729 | 09:30:21.914 | avant le checkpoint du hook |
| 730 | 09:30:22.914 | **première ligne après le checkpoint** |
| 731 | 09:30:23.914 | dernière ligne restaurée |

### Ce que cette observation établit
1. L'avance de la séquence est **déjà présente avant la reprise de l'écrivain** : elle vient de la base restaurée, pas
   de l'écrivain. Les ids sans ligne sont exactement ceux compris entre `max(id)` restauré et `last_value`.
2. La récupération sur cluster-b repart de la position du checkpoint du hook (`redo lsn=0/19CD8F0`, même valeur dans
   les deux journaux), et `last known up at` est l'heure de ce checkpoint. L'hypothèse 1 du 17/11 concorde ici avec les
   journaux des deux clusters.
3. `last_value` = 762 = **730 + 32**, où 730 est le premier id attribué après ce checkpoint. C'est ce que prévoit la
   pré-journalisation de la séquence (hypothèse 2 du 17/11) : au premier `nextval` qui suit un checkpoint, PostgreSQL
   écrit dans le WAL une valeur en avance de 32, et la récupération restaure cette valeur. L'écart vaut alors
   32 moins le nombre de lignes récupérées après la première, ici 32 - 1 = 31.

### Limites
- La concordance chiffrée porte sur **une** observation. Ce n'est pas une expérience dédiée (par exemple en faisant
  varier le délai entre le checkpoint et la copie), et le code source de PostgreSQL n'a pas été relu pour ce document.
- Les trois observations précédentes (18, 32, 30) sont compatibles (inférieures ou égales à 32) mais leurs données ne
  permettent pas le même recoupement.
- Sans effet sur le contrôle de cohérence : la continuité se juge sur `ts`.
