#!/usr/bin/env bash
# Planifie la sauvegarde du namespace app sur cluster-a (toutes les 15 minutes, conservation 72 h,
# voir k8s/velero/schedule.yaml), puis attend la première sauvegarde planifiée terminée. Velero ne
# sauvegarde pas à la création du Schedule : la première sauvegarde part au prochain multiple de
# 15 minutes (constaté le 20/11 : Schedule créé à 16:01, première sauvegarde à 16:15), donc l'attente
# peut durer jusqu'à 15 minutes. Idempotent. Uniquement cluster-a : l'emplacement de sauvegarde de
# cluster-b est en lecture seule.
# Usage : ./k8s/velero/schedule.sh
set -euo pipefail
source "$(dirname "$0")/../../infra/lib.sh"

CL=cluster-a; KC="$(kubeconfig "$CL")"
[[ -f "$KC" ]] || die "kubeconfig absent : $KC (make k3s)"
K=(kubectl --kubeconfig "$KC"); V=(velero --kubeconfig "$KC")
SCHED=app-15min

"${K[@]}" -n velero get backupstoragelocation default >/dev/null 2>&1 \
  || die "Velero absent sur $CL (make velero)"

log "Planification des sauvegardes sur $CL ($SCHED)"
"${K[@]}" apply -f "$(dirname "$0")/schedule.yaml" | sed 's/^/   /'

WAIT_SECONDS=$((WAIT_SECONDS + 900))   # plafond commun + une période de planification
log "Attente de la première sauvegarde planifiée terminée (prochain multiple de 15 min, plafond $WAIT_SECONDS s)"
backup_done() {
  [[ -n "$("${K[@]}" -n velero get backup -l "velero.io/schedule-name=$SCHED" \
    -o jsonpath='{range .items[?(@.status.phase=="Completed")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)" ]]
}
wait_for "aucune sauvegarde planifiée terminée sur $CL (voir : velero --kubeconfig $KC backup get)" backup_done

"${V[@]}" schedule get | sed 's/^/   /'
"${V[@]}" backup get -l "velero.io/schedule-name=$SCHED" | sed 's/^/   /'
