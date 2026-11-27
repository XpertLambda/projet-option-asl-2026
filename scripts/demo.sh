#!/usr/bin/env bash
# Démonstration complète du jalon J3 : sauvegarde planifiée -> destruction de cluster-a -> restauration
# sur cluster-b -> contrôle de cohérence -> RTO et RPO. Détruit cluster-a (jamais backup).
# Usage : CONFIRM_DISASTER=yes ./scripts/demo.sh        (ou : make demo CONFIRM_DISASTER=yes)
# Après la démonstration, make up reconstruit cluster-a.
set -euo pipefail
source "$(dirname "$0")/../infra/lib.sh"
D="$(dirname "$0")"

[[ "${CONFIRM_DISASTER:-}" == yes ]] || die "la démonstration détruit cluster-a : relancer avec CONFIRM_DISASTER=yes"
KB="$(kubeconfig cluster-b)"; KA="$(kubeconfig cluster-a)"
start=$SECONDS

# Le contrôle porte sur toute la table : si cluster-a échoue déjà (redémarrage de l'hôte, VM arrêtées), la
# restauration serait jugée incohérente. Dans ce cas, rien n'est détruit.
check_a() {
  "$D/verify.sh" cluster-a \
    || die "cluster-a échoue au contrôle de cohérence, rien n'est détruit : le reconstruire (./infra/destroy-vm.sh cluster-a && make up), puis relancer la démonstration"
}
log "1/4 État avant le sinistre : cluster-a (le contrôle doit réussir)"
check_a

log "2/4 Une sauvegarde planifiée de CETTE instance de cluster-a est-elle visible depuis cluster-b ?"
# Le bucket garde les sauvegardes des instances précédentes de cluster-a : seules celles terminées après la
# création du nœud actuel comptent.
A_CREATED="$(kubectl --kubeconfig "$KA" get node cluster-a -o jsonpath='{.metadata.creationTimestamp}')"
info "cluster-a créé le $A_CREATED ; attente de la première sauvegarde planifiée qui suit (prochain multiple de 15 min)"
WAIT_SECONDS=$((WAIT_SECONDS + 900))
backup_visible() {
  kubectl --kubeconfig "$KB" -n velero get backup -l velero.io/schedule-name=app-15min \
    -o jsonpath='{range .items[?(@.status.phase=="Completed")]}{.status.completionTimestamp}{"\n"}{end}' 2>/dev/null \
    | awk -v a="$A_CREATED" '$1 >= a { found=1 } END { exit !found }'
}
wait_for "aucune sauvegarde planifiée de cette instance de cluster-a visible depuis cluster-b" backup_visible
kubectl --kubeconfig "$KB" -n velero get backup -l velero.io/schedule-name=app-15min --sort-by=.metadata.creationTimestamp | tail -3 | sed 's/^/   /'

log "3/4 Sinistre : destruction de cluster-a"
check_a   # de nouveau : l'attente peut durer 15 minutes
"$D/disaster.sh"

log "4/4 Reprise sur cluster-b"
"$D/restore.sh"

log "Résultat"
head -1 "$REPO_DIR/results/runs.csv" | sed 's/^/   /'; tail -1 "$REPO_DIR/results/runs.csv" | sed 's/^/   /'
info "durée de la démonstration : $((SECONDS - start)) s. cluster-a est détruit : make up le reconstruit."
