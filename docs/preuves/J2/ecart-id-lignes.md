# Écart entre `count(*)` et `max(id)` de la table `events` (17/11/2026)

Observation faite le 17/11/2026 sur la plateforme reconstruite le jour même
(`reconstruction-avec-correctif.txt`), avec des requêtes en lecture seule sur `events`, puis deux
restaurations successives sur cluster-b (observation 1 : sections 1 à 4 ; observation 2 : section 5).
Ce document ne contient que ce que les requêtes ont montré.

## Contexte
- `events(id serial, ts timestamptz default now())`, une ligne par seconde par l'écrivain.
- Sauvegarde utilisée : `smoke-20261117-172720`, démarrée à 17:27:20 CET, terminée à 17:27:31 CET
  (soit 16:27:20 à 16:27:31 UTC), `Hooks: <none>` (aucun hook PostgreSQL à ce stade), volume
  `app/postgres-0` copié par Kopia pendant que PostgreSQL tournait.
- Restauration sur cluster-b : `velero restore create restore-ecart-20261117-173119 --from-backup
  smoke-20261117-172720 --wait`, lancée à 17:31:19 CET, terminée en 19 s (`Completed`).
- Les heures ci-dessous sont en UTC (colonne `ts`), sauf mention contraire.

## 1. cluster-a (jamais interrompu depuis la reconstruction)
Requêtes à 16:31:04 puis instantané unique plus tard :

| Mesure | Résultat |
|--------|----------|
| `count(*)`, `min(id)`, `max(id)` | 267, 1, 267 (écart 0) |
| ids manquants entre `min(id)` et `max(id)` | 0 |
| ids en double | 0 |
| interruptions de plus de 5 s | 0 |
| démarrage de PostgreSQL | 16:26:30, aucun redémarrage depuis |
| instantané unique (comptage, `max(id)` et séquence dans la même requête) | 342, 342, 342 |

La première requête séparée de la séquence avait donné `last_value = 268` pour `max(id) = 267` : les
trois valeurs ont été lues dans trois requêtes successives, l'écrivain insérant une ligne par seconde.
Dans une seule requête, elles sont égales. Sur A, **aucun écart**.

## 2. cluster-b juste après la restauration
PostgreSQL a démarré à 16:31:38. Ses journaux indiquent :
`database system was interrupted; last known up at 16:26:30`, puis
`database system was not properly shut down; automatic recovery in progress`, `redo starts at
0/1917A18`, `redo done at 0/198EBF0`, `database system is ready to accept connections`.

Première lecture (16:31:43, avant la première insertion de l'écrivain sur B) :

| Mesure | Résultat |
|--------|----------|
| `count(*)`, `min(id)`, `max(id)` | 48, 1, 48 (écart 0) |
| `max(ts)` | 16:27:24.508 |
| ids manquants, ids en double | 0, 0 |
| `events_id_seq.last_value` (`is_called = t`) | **66** |

Les données restaurées sont donc continues (ids 1 à 48) et la séquence est en avance : 66 pour un
`max(id)` de 48.

## 3. cluster-b après la reprise de l'écrivain
Lecture de 16:32:16, puis lecture de contrôle un peu plus tard :

| Mesure | 16:32:16 | plus tard |
|--------|----------|-----------|
| `count(*)` | 77 | 94 |
| `max(id)` | 95 | 112 |
| `max(id) - count(*)` | **18** | **18** |
| ids manquants dans l'intervalle | 18 (ids 49 à 66) | - |
| ids en double | 0 | - |
| interruptions de plus de 5 s | 1 | - |

- Lignes autour du trou : id 48 à 16:27:24.508, puis **id 67 à 16:31:47.979**. Les ids 49 à 66 n'existent
  pas sur B.
- Après le trou, les ids sont consécutifs (67, 68, 69, ...), à une ligne par seconde.
- L'écart de 18 reste constant (il ne grandit pas), l'unique interruption de plus de 5 s est le trou
  entre 16:27:24 (dernière ligne sauvegardée) et 16:31:47 (première ligne écrite sur B).

## 4. Comparaison avec les mêmes ids sur cluster-a
Sur A, les ids manquants sur B existent et sont continus :

| id | `ts` sur A |
|----|-----------|
| 1 | 16:26:37.508 |
| 48 | 16:27:24.508 |
| 49 | 16:27:25.508 |
| 57 | 16:27:33.509 |
| 66 | 16:27:42.508 |
| 67 | 16:27:43.508 |

- Les ids 49 à 66 correspondent à des lignes écrites sur A de 16:27:25 à 16:27:42.
- La sauvegarde s'est terminée à 16:27:31 : les lignes 49 à 66 ne sont donc pas toutes postérieures à la
  fin de la sauvegarde (la ligne 49 date de 16:27:25, pendant la sauvegarde).
- Sur B, le dernier id présent (48, 16:27:24) précède de 1 s le début des ids absents.

## 5. Seconde observation : nouvelle sauvegarde, namespace `app` de B supprimé, restauration
Même méthode, même jour. Namespace `app` de cluster-b supprimé (`kubectl delete namespace app`), puis :

| Étape | Valeur |
|-------|--------|
| État de A juste avant la sauvegarde (16:36:24 UTC) | `count(*)` = `max(id)` = `last_value` = 587 |
| Sauvegarde | `essai2-20261117-173624`, 17:36:24 à 17:36:30 CET (6 s), `Completed`, `Hooks: <none>`, 1 volume Kopia |
| État de A juste après (16:36:30 UTC) | 594, 594, 594 |
| Visible sur B | environ 30 s |
| Restauration | `restore-essai2-173721`, `Completed` en 13 s |
| Démarrage de PostgreSQL sur B | 16:37:33 |

Journaux de PostgreSQL sur B : `database system was interrupted; last known up at 16:31:40`, puis
`database system was not properly shut down; automatic recovery in progress`, `redo starts at 0/19A6100`,
`redo done at 0/19BF800`, `database system is ready to accept connections`.

Première lecture (16:37:35, avant la première insertion de l'écrivain sur B) :

| Mesure | Résultat |
|--------|----------|
| `count(*)`, `min(id)`, `max(id)` | 591, 1, 591 (écart 0) |
| `max(ts)` | 16:36:27.508 |
| ids manquants, ids en double | 0, 0 |
| `events_id_seq.last_value` (`is_called = t`) | **623** |

Lecture de 16:38:10, après la reprise de l'écrivain :

| Mesure | Résultat |
|--------|----------|
| `count(*)` | 621 |
| `max(id)` | 653 |
| `max(id) - count(*)` | **32** |
| ids manquants dans l'intervalle | 32 (ids 592 à 623) |
| ids en double | 0 |
| interruptions de plus de 5 s | 1 |

- Lignes autour du trou : id 591 à 16:36:27.508, puis **id 624 à 16:37:40.904**.
- Sur A, les ids 592 à 623 existent (592 à 16:36:28, 623 à 16:36:59) ; la sauvegarde s'est terminée à
  16:36:30, la ligne 591 (16:36:27) est donc dans la fenêtre de la sauvegarde (16:36:24 à 16:36:30).

### Comparaison des deux observations
| | Observation 1 | Observation 2 |
|---|---|---|
| Dernier id restauré sur B | 48 | 591 |
| `last_value` de la séquence sur B après restauration | 66 | 623 |
| Avance de la séquence sur `max(id)` | 18 | 32 |
| ids sans ligne sur B | 49 à 66 (18) | 592 à 623 (32) |
| `max(id) - count(*)` après reprise de l'écrivain | 18 | 32 |
| Données restaurées continues, sans doublon | oui | oui |
| Récupération automatique au démarrage | oui | oui |

**L'écart n'est pas identique** (18 puis 32). Il est dans les deux cas strictement positif, les données
restaurées sont continues et sans doublon, et la séquence est en avance sur `max(id)`.

## Ce que les requêtes établissent
1. Sur A, sans interruption : `count(*) = max(id)`, pas de trou.
2. Après restauration sur B, les lignes restaurées sont continues, sans doublon.
3. Sur B, la séquence restaurée (`last_value = 66`) est en avance de 18 sur `max(id)` (48) : les ids 49 à
   66 n'ont été attribués à aucune ligne sur B, d'où `max(id) - count(*) = 18` ensuite.
4. Les journaux de PostgreSQL sur B signalent une récupération automatique au démarrage
   (`not properly shut down`).
5. Ces constats se répètent sur une seconde restauration, avec une avance de séquence différente
   (18 puis 32, section 5).

## Hypothèses (non démontrées)
Lecture seule des journaux de PostgreSQL sur cluster-a (`kubectl logs postgres-0`), lignes `checkpoint` :

| Heure (UTC) | Ligne du journal de A |
|-------------|-----------------------|
| 16:26:29.874 | `checkpoint complete: wrote 925 buffers` (précédé de `checkpoint starting: shutdown immediate`) |
| 16:27:20 à 16:27:31 | **sauvegarde 1** |
| 16:31:30.116 | `checkpoint starting: time` |
| 16:31:40.407 | `checkpoint complete: wrote 105 buffers ... total=10.291 s` |
| 16:36:24 à 16:36:30 | **sauvegarde 2** |
| 16:36:30.492 | `checkpoint starting: time` |
| 16:36:31.918 | `checkpoint complete: wrote 15 buffers ... total=1.426 s` |

Un checkpoint a donc eu lieu entre la première et la seconde sauvegarde (16:31:30 à 16:31:40), et le
suivant a commencé 0,5 s après la fin de la seconde sauvegarde (16:36:30).

**Hypothèse 1 : valeur de `last known up at`.** La valeur affichée par PostgreSQL sur B au démarrage
vaut 16:26:30 pour l'observation 1 et 16:31:40 pour l'observation 2. Ces heures correspondent à la fin du
dernier checkpoint terminé sur A avant chaque copie (16:26:29.874 et 16:31:40.407). Les heures
concordent ; le lien entre les deux (heure de checkpoint enregistrée dans les fichiers copiés) n'a pas
été vérifié, par exemple en lisant `pg_controldata` sur une copie.

**Hypothèse 2 : taille de l'écart.** Les deux écarts observés (18 et 32) sont inférieurs ou égaux à 32.
Cela est compatible avec une pré-journalisation de 32 valeurs de la séquence par PostgreSQL (valeurs
réservées à l'avance, qui ne sont pas attribuées à une ligne après une récupération). Ce n'est pas
démontré : deux observations seulement, et aucune mesure de la séquence dans la copie elle-même.

## Ce que ces requêtes ne montrent pas
- La cause de l'avance de la séquence (non testée ici). Il faudrait, par exemple, comparer la valeur de la
  séquence et le contenu de la table dans la copie Kopia elle-même, ou répéter l'essai avec les hooks
  PostgreSQL prévus au jalon J3 (`CHECKPOINT`, `pg_backup_start`, `pg_backup_stop`) et vérifier si
  l'avance disparaît.
- Si l'écart suit une règle : deux observations (18 et 32) ne suffisent pas à le dire.
- Aucun RPO n'est calculé ici : cette note porte sur les ids, pas sur la perte de données.

## État de cluster-b
Après les observations, le namespace `app` de cluster-b a été supprimé (`kubectl delete namespace app`) :
B est de nouveau sans application, comme exigé avant un essai de restauration du jalon J3.

## Requêtes utilisées
Toutes en lecture seule, via `kubectl exec postgres-0 ... psql` :
- `SELECT count(*), min(id), max(id), max(id)-count(*), min(ts), max(ts), now() FROM events`
- ids manquants : `generate_series(min(id), max(id)) LEFT JOIN events USING (id) WHERE e.id IS NULL`
- ids en double : `GROUP BY id HAVING count(*) > 1`
- `SELECT last_value, is_called FROM events_id_seq`
- trous : `lead(id) OVER (ORDER BY id)` quand `nxt > id + 1`
- interruptions : `ts - lag(ts) OVER (ORDER BY id) > interval '5 seconds'`
- `SELECT pg_postmaster_start_time()`
