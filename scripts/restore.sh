#!/usr/bin/env bash
# Reprise sur cluster-b après un sinistre (docs/architecture.md, section 6) :
#   1. choisit la dernière sauvegarde planifiée terminée (ou celle donnée en argument) ;
#   2. restaure le namespace app sur cluster-b, l'écrivain restant à 0 réplique ;
#   3. attend PostgreSQL, puis lance le contrôle de cohérence (scripts/verify.sh) sur les lignes restaurées ;
#   4. si le contrôle réussit : t1 est relevé, l'écrivain est remis à 1 réplique ;
#      sinon : t1 n'est pas posé, l'écrivain reste à 0, l'essai est noté "incoherent".
# RTO = t1 - t0 ; RPO = (max(ts) lu sur cluster-a avant t0) - max(ts) restauré.
# t0 et la dernière écriture viennent de scripts/disaster.sh (~/.cache/projet/last-disaster.env).
# Les essais réels (sinistre non à blanc) sont ajoutés à results/runs.csv.
# Usage : ./scripts/restore.sh [nom_de_sauvegarde]
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"

STATE="$CACHE_DIR/last-disaster.env"
[[ -f "$STATE" ]] || die "aucun sinistre enregistré : lancer d'abord make disaster"
source "$STATE"
KB="$(kubeconfig cluster-b)"; [[ -f "$KB" ]] || die "kubeconfig absent : $KB"
K=(kubectl --kubeconfig "$KB"); V=(velero --kubeconfig "$KB")
CSV="$REPO_DIR/results/runs.csv"
SCHED=app-15min
RESTORE_START=$(date +%s.%N)
awk_calc() { awk "BEGIN { printf \"%.3f\", $1 }"; }

# 1. Sauvegarde à restaurer
BACKUP="${1:-}"
if [[ -z "$BACKUP" ]]; then
  BACKUP="$("${K[@]}" -n velero get backup -l "velero.io/schedule-name=$SCHED" --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{range .items[?(@.status.phase=="Completed")]}{.metadata.name}{"\n"}{end}' | tail -1)"
fi
[[ -n "$BACKUP" ]] || die "aucune sauvegarde planifiée terminée visible depuis cluster-b (make schedule sur cluster-a, patienter une minute)"
b_start="$("${K[@]}" -n velero get backup "$BACKUP" -o jsonpath='{.status.startTimestamp}')"
b_end="$("${K[@]}" -n velero get backup "$BACKUP" -o jsonpath='{.status.completionTimestamp}')"
# Le bucket garde les sauvegardes des instances précédentes de cluster-a : n'accepter que celles faites par
# l'instance détruite (terminées après sa création)
if [[ -n "${A_CREATED_EPOCH:-}" && -n "$b_end" ]] && (( $(date -d "$b_end" +%s) < A_CREATED_EPOCH )); then
  die "la sauvegarde $BACKUP date d'avant la création de cluster-a ($(date -d "@$A_CREATED_EPOCH" +%FT%T%z)) : attendre une sauvegarde de l'instance détruite"
fi
log "Restauration de $BACKUP sur cluster-b"

# 2. Namespace app propre sur cluster-b, puis restauration avec l'écrivain à 0 réplique
if "${K[@]}" get namespace app >/dev/null 2>&1; then
  info "namespace app déjà présent sur cluster-b (reste d'un essai précédent) : suppression"
  "${K[@]}" delete namespace app --wait=true --timeout="$WAIT_TIMEOUT" >/dev/null
fi
"${K[@]}" apply -f "$REPO_DIR/k8s/velero/restore-modifier.yaml" >/dev/null
RESTORE="restore-${BACKUP:0:36}-$(date +%H%M%S)"
"${V[@]}" restore create "$RESTORE" --from-backup "$BACKUP" --resource-modifier-configmap restore-writer-zero --wait \
  | tail -1 | sed 's/^/   /'
phase="$("${K[@]}" -n velero get restore "$RESTORE" -o jsonpath='{.status.phase}')"
[[ "$phase" == Completed ]] || die "restauration $RESTORE en phase $phase (velero restore logs $RESTORE)"

# 3. PostgreSQL prêt, écrivain à 0 réplique
pg_pod_present() { "${K[@]}" -n app get pod postgres-0; }
wait_for "postgres-0 absent sur cluster-b après la restauration" pg_pod_present
"${K[@]}" -n app wait --for=condition=Ready pod/postgres-0 --timeout="$WAIT_TIMEOUT" >/dev/null \
  || die "postgres-0 non Ready sur cluster-b"
replicas="$("${K[@]}" -n app get deployment writer -o jsonpath='{.spec.replicas}')"
[[ "$replicas" == 0 ]] || { "${K[@]}" -n app scale deployment/writer --replicas=0 >/dev/null; die "l'écrivain n'était pas à 0 réplique ($replicas) : essai invalide, écrivain remis à 0"; }
info "écrivain à 0 réplique pendant le contrôle"
# Lecture seule de la séquence des ids juste après la restauration, avant la remise de l'écrivain à 1
# (observation de l'écart d'ids, docs/preuves/J3/ecart-id-lignes-avec-hook.md) ; sans effet sur le statut du contrôle
if seq="$("${K[@]}" -n app exec -i postgres-0 -c postgres -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -At -F "|"' \
    <<<"SELECT last_value, is_called FROM events_id_seq" 2>/dev/null)" && [[ -n "$seq" ]]; then
  info "events_id_seq après restauration : last_value=${seq%%|*} is_called=${seq##*|}"
else
  info "events_id_seq après restauration : lecture impossible"
fi

# 4. Contrôle de cohérence ; t1 seulement s'il réussit
set +e
out="$("$(dirname "$0")/verify.sh" cluster-b --t0 "$T0_EPOCH" 2>&1)"; vrc=$?
set -e
printf '%s\n' "$out" | sed 's/^/   /'
vline="$(printf '%s\n' "$out" | grep '^VERIFY ' | tail -1 || true)"
field() { sed -n "s/.* $1=\([^ ]*\).*/\1/p" <<<"$vline"; }
ROWS_B="$(field count)"; MAX_TS_B="$(field max_ts)"; MAX_EPOCH_B="$(field max_epoch)"
RPO="" ; [[ -n "$MAX_EPOCH_B" ]] && RPO="$(awk_calc "$LAST_EPOCH - $MAX_EPOCH_B")"

# Garde-fou : aucune ligne ne peut être postérieure à la fin de la sauvegarde, sinon l'écrivain a écrit
# sur cluster-b avant la fin du contrôle (essai invalide).
POST_WRITE=no
if [[ -n "$MAX_EPOCH_B" && -n "$b_end" ]] && awk -v a="$MAX_EPOCH_B" -v b="$(date -d "$b_end" +%s)" 'BEGIN { exit !(a > b + 1) }'; then
  POST_WRITE=yes; info "ligne postérieure à la fin de la sauvegarde : l'écrivain a écrit avant la fin du contrôle"
fi

T1_EPOCH=""; RTO=""; STATUS=incoherent
if (( vrc == 0 )) && [[ "$(field status)" == ok && "$POST_WRITE" == no ]]; then
  T1_EPOCH="$(date +%s.%N)"; RTO="$(awk_calc "$T1_EPOCH - $T0_EPOCH")"; STATUS=ok
  "${K[@]}" -n app scale deployment/writer --replicas=1 >/dev/null
  "${K[@]}" -n app rollout status deployment/writer --timeout="$WAIT_TIMEOUT" >/dev/null
  info "contrôle réussi : t1 posé, écrivain remis à 1 réplique"
else
  info "contrôle échoué : t1 non posé, écrivain laissé à 0 réplique, essai noté incohérent"
fi

# Durée de la sauvegarde restaurée et taille copiée (visibles sur cluster-b)
B_DUR=""; [[ -n "$b_start" && -n "$b_end" ]] && B_DUR="$(( $(date -d "$b_end" +%s) - $(date -d "$b_start" +%s) ))"
B_SIZE="$("${K[@]}" -n velero get podvolumebackup -l "velero.io/backup-name=$BACKUP" -o jsonpath='{.items[*].status.progress.totalBytes}' 2>/dev/null | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; if (NF) print s}')"

# Enregistrement (essais réels seulement)
if [[ "$DESTROYED" == yes ]]; then
  mkdir -p "$(dirname "$CSV")"
  [[ -f "$CSV" ]] || echo "run,date,strategy,backup,t0,t1,rto_s,last_ts_a,max_ts_restored,rpo_s,rows_restored,backup_duration_s,backup_size_bytes,status" > "$CSV"
  RUN=$(( $(wc -l < "$CSV") ))
  echo "$RUN,$(date +%F),S1,$BACKUP,$T0_EPOCH,$T1_EPOCH,$RTO,$LAST_TS,$MAX_TS_B,$RPO,$ROWS_B,$B_DUR,$B_SIZE,$STATUS" >> "$CSV"
  info "essai $RUN ajouté à results/runs.csv (statut : $STATUS)"
else
  info "essai à blanc (cluster-a non détruit) : non enregistré dans results/runs.csv"
fi
echo "RESTORE backup=$BACKUP t0=$T0_EPOCH t1=${T1_EPOCH:-non_pose} rto_s=${RTO:-} rpo_s=${RPO:-} rows_restored=${ROWS_B:-} status=$STATUS"
[[ "$STATUS" == ok ]]
