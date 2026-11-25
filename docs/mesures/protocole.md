# Protocole de mesure du J4

Arrêté par le groupe le 25/11/2026, **avant toute mesure**. Toute modification est datée et justifiée en fin de
document. Les chiffres de calibration viennent de `calibration-2026-11-25.txt` : ce ne sont pas des mesures.

## 1. Questions
1. Quels RTO et RPO obtient-on avec S1, S2 et S3 pour la même base ?
2. Comment le RPO dépend-il du moment du sinistre par rapport à la dernière sauvegarde ?

## 2. Stratégies
| Série | Stratégie | Sauvegarde utilisée dans l'essai |
|-------|-----------|----------------------------------|
| S1-15 | Velero planifié, période de 15 min | `velero backup create --from-schedule app-15min` |
| S1-60 | Velero planifié, période d'une heure | idem |
| S2 | `pg_dump` en CronJob vers MinIO (période de 15 min) | `kubectl create job --from=cronjob/...` |
| S3 | Archivage continu des WAL avec WAL-G (ADR 0006), `archive_timeout = 60s` | sauvegarde de base en début d'essai |

La sauvegarde est **déclenchée par nous à un instant connu T_b**, planification en pause
(`velero schedule pause`). La période ne sert donc qu'à borner le décalage testé.

## 3. Décalage du sinistre
Décalage `d = t0 - T_b`, mesuré depuis le début de la sauvegarde.

| Série | Décalages | Essais |
|-------|-----------|--------|
| S1-15 | 1 min 30, 7 min 30, 13 min 30 | 3 par décalage, plus 1 chauffe |
| S1-60 | 30 min (milieu de la période) | 3 |
| S2 | 1 min 30, 13 min 30 | 3 par décalage, plus 1 chauffe |
| S3 | pas de décalage : sinistre 10, 30 et 50 s après la dernière bascule de segment | 1 par instant, plus 1 chauffe |

Les décalages d'une série sont entrelacés (par exemple 1,5 ; 7,5 ; 13,5 ; puis de nouveau) pour que la dérive de
l'hôte ne se confonde pas avec le décalage. La chauffe est enregistrée et écartée de l'analyse.

Le plus petit décalage (90 s) laisse environ 20 s de marge : en calibration, la sauvegarde était visible depuis
cluster-b 70 s après T_b. Les lignes écrites pendant la copie du volume sont restaurées, le RPO attendu de S1
est donc `d` moins quelques secondes (7 s en calibration).

## 4. Données
**1 000 000 de lignes**, les mêmes pour S1, S2 et S3 : `make prefill ROWS=1000000`.

| Observé en calibration | Valeur |
|------------------------|--------|
| Durée du pré-remplissage | 41 s |
| Table et index ; base ; WAL | 85 Mo ; 93 Mo ; 208 Mo |
| Volume copié par Kopia | 339 Mo |
| Durée de la sauvegarde Velero | 11 s |
| CPU de cluster-a pendant la sauvegarde | moyenne 12 % (10 % avant), maximum 52 % |

## 5. Indicateurs
| Indicateur | Définition |
|------------|------------|
| RTO | t1 - t0 (`docs/architecture.md`, section 6) |
| Première écriture | première nouvelle ligne lue sur cluster-b - t0 (en plus du RTO) |
| RPO | dernier `ts` lu sur cluster-a avant t0 - `max(ts)` restauré |
| Sauvegarde | durée et taille de chaque sauvegarde |
| Charge | CPU de cluster-a pendant la sauvegarde (`vmstat -n 1`, de 5 s avant à 55 s après T_b) |
| Cohérence | `ok` ou `incoherent` (section 7) |
| Ids | `last_value` après restauration, à titre d'information |

## 6. Déroulement d'un essai
1. cluster-a détruit puis reconstruit (`make up`, avec le cache d'images : 124 s observées).
2. `make prefill ROWS=1000000`, puis `./scripts/verify.sh cluster-a` : `status=ok` exigé.
3. Planification en pause : `velero schedule pause app-15min` (S1).
4. Velero et node-agent de cluster-b redémarrés, pour vider le cache Kopia :
   `kubectl -n velero rollout restart deploy/velero ds/node-agent`, puis attente de `rollout status`.
5. T_b relevé, sauvegarde déclenchée, mesure de la charge.
6. Attente de la visibilité depuis cluster-b, puis de l'instant `T_b + d`.
7. `make disaster CONFIRM_DISASTER=yes`.
8. `./scripts/restore.sh <nom_de_la_sauvegarde>` (la sauvegarde est donnée explicitement).
9. Résultat ajouté à `results/runs.csv`.

Cette procédure (étapes 2 à 6 et 8) a été répétée à blanc le 25/11, cluster-a conservé.

## 7. Contrôle de cohérence
Critère **strict**, celui de `docs/architecture.md` section 6 (`scripts/verify.sh`) : au moins une ligne, aucun
`id` en double, `ts` croissant avec l'`id`, aucun écart de plus de 5 s, `max(ts)` <= t0. Un trou d'ids sans
ligne n'est pas une anomalie. cluster-a est reconstruit avant chaque essai, la table n'a donc pas d'historique.

## 8. Conditions
- Aucune autre charge sur l'hôte ; pas de swap en cours (`free -h`) ; `./infra/check-host.sh` sans `[KO]`
  (dont la synchronisation NTP).
- Même commit pour toute une série ; versions de `versions.yaml`.
- cluster-b et `backup` ne sont pas reconstruits pendant une série ; les images sont présentes sur cluster-b
  (aucun événement `Pulling`).
- L'hôte n'est ni redémarré ni mis en veille pendant une session.

## 9. Validité et analyse
- **Essai invalide** (refait, et noté avec sa raison) : condition de la section 8 non respectée, sauvegarde non
  visible depuis cluster-b avant t0, planification non mise en pause, contrôle de cohérence de cluster-a en échec
  avant la sauvegarde, écriture sur cluster-b avant la fin du contrôle.
- **Essai incohérent** : compté comme échec, conservé, exclu de la médiane du RTO.
- Aucun autre essai n'est retiré.
- Par série et par décalage : médiane, minimum et maximum de chaque indicateur (`scripts/analyse.py`, à écrire
  au J4), et comparaison du RPO mesuré avec le décalage.

## 10. Durée estimée
Part fixe d'un essai : environ 4 min (reconstruction 124 s, pré-remplissage 41 s, redémarrage de Velero sur B
et restauration environ 1 min 15), plus le décalage.

| Série | Durée estimée |
|-------|---------------|
| S1-15 (9 essais et 1 chauffe) | 1 h 50 |
| S1-60 (3 essais) | 1 h 40 |
| S2 (6 essais et 1 chauffe) | 1 h 15 (restauration `pg_restore` non calibrée) |
| S3 (3 essais et 1 chauffe) | 30 min (non calibrée) |
| **Total** | **environ 5 h 15**, avec 20 % de marge environ 6 h 20 : deux à trois sessions |

## 11. Responsables
Selon `docs/plan.md` : stratégies S1, S2, S3 : Amer EL JIBBAWE ; scripts de mesure et d'analyse : Ali TERRO ;
hôte et reconstruction : Ahmad SAAD.

## 12. Reste à faire au J4 avant la première mesure
- S2 (CronJob et restauration) et S3 (archivage et restauration), puis leur calibration.
- `scripts/measure.sh` (enchaîne les étapes de la section 6) et `scripts/analyse.py`.
- Colonnes à ajouter à `results/runs.csv` : série, décalage, chauffe, validité et raison.

## Modifications
Aucune depuis l'arrêt du protocole.
