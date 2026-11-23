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
