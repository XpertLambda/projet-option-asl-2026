# Registre des risques

Échelle : Probabilité et Impact de 1 (faible) à 3 (fort). Criticité = P x I.

| ID | Risque | P | I | Crit. | Mitigation | Plan B | Responsable |
|----|--------|---|---|-------|------------|--------|-------------|
| R1 | Virtualisation (VT-x/AMD-V) désactivée ou absente sur l'hôte | 1 | 3 | 3 | Vérifier le BIOS et `kvm-ok` dès l'installation | Autre machine de la salle | Ahmad |
| R2 | RAM de l'hôte insuffisante pour 3 VM + mesures | 2 | 2 | 4 | Dimensionnement serré (10 Go au total), Ubuntu Server si 16 Go | Réduire `backup` à 1 Go ou MinIO sur l'hôte | Ahmad |
| R3 | MinIO CE non maintenu, binaire ou image indisponible | 2 | 2 | 4 | Figer et archiver le dernier binaire officiel dès J2 | Garage ou SeaweedFS (compatibles S3) | Amer |
| R4 | Restauration Velero incomplète (PVC, ordre des ressources, StorageClass) | 2 | 3 | 6 | Test de restauration dès J2 sur une appli simple, même StorageClass sur A et B | `pg_dump` + manifestes Git | Amer |
| R5 | Base PostgreSQL incohérente après restauration | 2 | 3 | 6 | Hook Velero (`pg_backup_start/stop`), vérification par requêtes | Sauvegarde logique `pg_dump` | Ali |
| R6 | Destruction accidentelle des sauvegardes (mauvais bucket, B en écriture) | 1 | 3 | 3 | BSL du cluster B en lecture seule, versionnage du bucket | Sauvegarde du disque de la VM `backup` | Amer |
| R7 | Secret (clés MinIO, kubeconfig) poussé sur GitHub (dépôt public) | 2 | 3 | 6 | `.gitignore`, secrets générés au déploiement, relecture avant push | Révoquer et régénérer les clés, réécrire l'historique | Tous |
| R8 | Reconstruction impossible par un tiers (J5) | 2 | 3 | 6 | README tenu à jour à chaque jalon, Ali ne touche pas aux scripts d'infra | Répétition à blanc mi-janvier | Ali |
| R9 | Retard sur J3 (MVP) à cause des vacances et du calendrier irrégulier | 2 | 3 | 6 | MVP minimal visé dès fin novembre, travail hors créneaux | Journées de rattrapage du 16 au 18/12 | Tous |
| R10 | Panne ou réinstallation de l'hôte en cours de semestre | 1 | 3 | 3 | Tout est reconstructible depuis Git, sauvegarde avant les vacances (18/12) | Reconstruction sur une autre machine | Ahmad |
| R11 | Mesures RTO/RPO peu fiables (bruit, une seule mesure) | 2 | 2 | 4 | Protocole écrit avant J4, 3 répétitions minimum, scripts horodatés | Augmenter le nombre de répétitions | Ali |
