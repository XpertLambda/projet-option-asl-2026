#!/usr/bin/env bash
# Données de départ des mesures (docs/mesures/protocole.md) : remplit la table events de cluster-a avec
# N lignes sans casser le contrôle de cohérence (ids croissants, une ligne par seconde, aucun écart).
#   1. écrivain arrêté, table vidée, séquence positionnée à N ;
#   2. écrivain relancé : ses lignes commencent à l'id N+1 ;
#   3. lignes 1 à N insérées avec des ts antidatés qui finissent 1 s avant sa première ligne.
# La table est vidée : à utiliser sur un cluster-a reconstruit pour un essai.
# Usage : ./scripts/prefill.sh [N]     (N = 1000000 par défaut)
#         CONFIRM_PREFILL=yes pour vider une table qui contient déjà plus d'une heure d'écritures
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

N="${1:-1000000}"
[[ "$N" =~ ^[1-9][0-9]*$ ]] || die "usage : $0 [nombre de lignes]"
KA="$(kubeconfig cluster-a)"; [[ -f "$KA" ]] || die "kubeconfig absent : $KA"
K=(kubectl --kubeconfig "$KA" -n app)
# shellcheck disable=SC2016  # variables développées dans le pod
q() { "${K[@]}" exec -i postgres-0 -c postgres -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -At -v ON_ERROR_STOP=1'; }

before="$(q <<<"SELECT count(*) FROM events")"
(( before <= 3600 )) || [[ "${CONFIRM_PREFILL:-}" == yes ]] \
  || die "la table events de cluster-a contient $before lignes : elle serait vidée, relancer avec CONFIRM_PREFILL=yes"

log "Pré-remplissage de events sur cluster-a : $N lignes (les $before lignes présentes sont effacées)"
start=$SECONDS
"${K[@]}" scale deployment/writer --replicas=0 >/dev/null
"${K[@]}" wait --for=delete pod -l app=writer --timeout="$WAIT_TIMEOUT" >/dev/null
q <<<"TRUNCATE events; SELECT setval('events_id_seq', $N);" >/dev/null
"${K[@]}" scale deployment/writer --replicas=1 >/dev/null
first_row() { [[ "$(q <<<"SELECT EXISTS (SELECT 1 FROM events WHERE id > $N)")" == t ]]; }
wait_for "l'écrivain n'a rien écrit après le vidage" first_row

q <<<"INSERT INTO events (id, ts)
      SELECT g, f.ts - ($N + 1 - g) * interval '1 second'
      FROM (SELECT ts FROM events ORDER BY id LIMIT 1) f, generate_series(1, $N) g;" >/dev/null
# Deux checkpoints : les segments de WAL du remplissage sont recyclés avant la sauvegarde
q <<<"VACUUM ANALYZE events;" >/dev/null
q <<<"CHECKPOINT;" >/dev/null
q <<<"CHECKPOINT;" >/dev/null

info "lignes : $(q <<<"SELECT count(*) FROM events")"
info "table et index : $(q <<<"SELECT pg_size_pretty(pg_total_relation_size('events'))")"
info "base : $(q <<<"SELECT pg_size_pretty(pg_database_size(current_database()))"), dont WAL : $(q <<<"SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir()")"
info "durée du pré-remplissage : $((SECONDS - start)) s"
