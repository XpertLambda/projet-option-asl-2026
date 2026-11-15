# Checklist J1 : cadrage

- **Échéance du jalon : vendredi 06/11/2026 à 18:00.**
- **Cette checklist a été rédigée le 15/11/2026**, soit 9 jours après l'échéance. Le jalon est donc
  validé en retard. Les statuts ci-dessous décrivent l'état réel du dépôt le 15/11, vérifié fichier
  par fichier ce jour-là.
- Ce que le dépôt prouve par ses dates : tous les documents du cadrage ont été commités les 22 et
  23/10/2026 (historique `git log`), et le reflog local indique un push le 05/11/2026 à 23:02, avant
  l'échéance. Ce qui manquait à l'échéance : le tag `J1`, cette checklist et un journal de séance
  après le 23/10.

## Exigences du jalon

| # | Exigence | Statut | Preuve dans le dépôt | Remarques |
|---|----------|--------|----------------------|-----------|
| 1 | Dépôt Git dédié, arborescence structurée | Fait | `README.md` (section Arborescence), dossiers `docs/`, `infra/`, `k8s/`, `scripts/` ; remote `origin` = `projet-option-asl-2026` | Premier commit le 22/10/2026 (`0cdf2cc`) |
| 2 | Document d'architecture de 2 à 3 pages | Fait, longueur à contrôler | `docs/architecture.md` (10 sections, 1305 mots) | Environ 3 pages de texte, davantage une fois les tableaux rendus : à vérifier à l'export PDF |
| 3 | Diagramme d'architecture | Fait | `docs/architecture.md` section 2 (diagramme Mermaid : hôte, réseau `dr-net`, 3 VM, flux de sauvegarde et de restauration) | Section 4 : tableau d'adressage |
| 4 | Les deux environnements planifiés dès le départ | Fait | `docs/architecture.md` sections 2, 4 et 5 (`cluster-a`, `cluster-b`, plus la VM `backup`, adresses et dimensionnement) ; `docs/plan.md` | Cluster A protégé, cluster B de reprise en lecture seule sur les sauvegardes |
| 5 | ADR sur l'outil de sauvegarde, avec alternative et plan B | Fait | `docs/adr/0001-outil-sauvegarde.md` | Options comparées (Velero, Kasten K10, `pg_dump`, snapshot etcd), alternatives rejetées expliquées, plan B (manifestes Git + `pg_dump`) |
| 6 | ADR sur la stratégie de stockage des sauvegardes, avec alternative et plan B | Fait | `docs/adr/0002-stockage-sauvegardes.md` | Cinq options comparées (MinIO dans A, dans B, sur VM dédiée, NFS, cloud), plan B Garage ou SeaweedFS. Complété le 23/10 par la vérification des binaires MinIO |
| 7 | Au moins 2 ADR (ici 4) avec alternative et plan B | Fait | `docs/adr/0003-os-virtualisation.md`, `docs/adr/0004-copie-volumes.md`, modèle `docs/adr/0000-modele.md` | Les 4 ADR ont une section d'options et un plan B. L'ADR 0003 n'a pas de section « Alternatives rejetées » séparée : ses alternatives sont dans les tableaux d'options |
| 8 | Registre des risques | Fait | `docs/risques.md` : 14 risques (R1 à R14) avec probabilité, impact, criticité, mitigation, plan B et responsable | R12 à R14 ajoutés le 23/10 (commit `d1431de`) |
| 9 | Plan de travail et rôles | Fait | `docs/plan.md` : rôles principaux et secondaires de chaque membre, calendrier par période, définition de « terminé » d'un jalon | Règle J5 : Ali ne lance pas les scripts d'infrastructure avant la reconstruction à l'aveugle |
| 10 | Journal de séance pour chaque séance | Partiel | `docs/journal/2026-10-22.md`, `docs/journal/2026-10-23.md`, `docs/journal/2026-11-15.md` | Aucune entrée entre le 23/10 et le 15/11 : aucune séance n'a été consignée sur cette période |
| 11 | Relecture du cadrage par les trois membres | Fait, selon la déclaration du groupe | Ahmad SAAD, Amer EL JIBBAWE et Ali TERRO déclarent avoir relu ensemble les documents du J1, en salle, le 23/10/2026. Seules traces écrites : le commit `d1431de` (« Revue du cadrage J1 : source des binaires MinIO, hook PostgreSQL, nouveaux risques », attribué à Amer EL JIBBAWE) et la liste des présents du journal du 23/10 (les trois membres), où la relecture figure sous « Prévu » | Aucune autre preuve : la relecture elle-même n'a pas laissé de compte rendu écrit |
| 12 | Tag Git `J1` sur le commit de validation | À poser | Le tag annoté `J1` est créé le 15/11/2026 sur le commit qui contient cette checklist | Validation tardive, tag non antidaté : sa date est celle du 15/11/2026 |

## Écarts et réserves
- **Retard** : le jalon est validé 9 jours après l'échéance du 06/11 (tag et checklist du 15/11).
- **Relecture** : établie par la déclaration du groupe et par deux traces écrites indirectes
  (ligne 11) ; il n'existe pas de compte rendu de la relecture.
- **Longueur** de l'architecture à contrôler (ligne 2).
- **Push** : la date du push du 05/11 vient du reflog local ; elle n'a pas pu être confirmée auprès de
  GitHub lors de cette vérification.
- **Évolutions depuis l'échéance** : aucun document du cadrage n'a été modifié après le 23/10.
  Les seuls changements du 15/11 concernent des scripts du jalon J2 (délais d'attente) et les preuves J2.
