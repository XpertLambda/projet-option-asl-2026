# Plateforme de sauvegarde et reprise après sinistre : tout se pilote d'ici.
# Les scripts lisent les versions dans versions.yaml. Voir README.md.
SHELL := /bin/bash
I := ./infra
K := ./k8s

.DEFAULT_GOAL := help
.PHONY: help check network vms k3s minio app velero up status backup smoke destroy destroy-all

help:
	@echo "Construction  : make up  (= check network vms minio k3s app velero)"
	@echo "  étapes      : check network vms k3s minio app velero"
	@echo "État          : make status"
	@echo "Test de fumée : make backup | make smoke"
	@echo "Destruction   : make destroy      (cluster-a et cluster-b seulement, les sauvegardes restent)"
	@echo "                make destroy-all CONFIRM_DESTROY_BACKUP=yes   (tout, y compris la VM backup)"
	@echo "À venir (J3)  : disaster, restore, demo"

check:
	@$(I)/check-host.sh

network:
	@$(I)/create-storage.sh
	@$(I)/create-network.sh

# Dimensionnement : voir docs/architecture.md section 5
vms: network
	@$(I)/create-vm.sh backup 1 2048 20 100
	@$(I)/create-vm.sh cluster-a 2 4096 30
	@$(I)/create-vm.sh cluster-b 2 4096 30

k3s:
	@$(I)/install-k3s.sh cluster-a
	@$(I)/install-k3s.sh cluster-b

minio:
	@$(I)/install-minio.sh

app:
	@$(K)/app/deploy.sh cluster-a

velero:
	@$(K)/velero/install-velero.sh cluster-a rw
	@$(K)/velero/install-velero.sh cluster-b ro

up: check
	@start=$$(date +%s); \
	$(MAKE) --no-print-directory vms minio k3s app velero && \
	echo "== make up terminé en $$(( $$(date +%s) - start )) s"

status:
	@echo "== VM"; virsh list --all
	@echo "== Adresses"; virsh net-dhcp-leases dr-net 2>/dev/null | awk 'NR>2 && NF {print $$6, $$5}' || true
	@for c in cluster-a cluster-b; do \
	  echo "== $$c"; kubectl --kubeconfig ~/.kube/$$c.yaml get nodes 2>&1 | sed 's/^/   /'; \
	  kubectl --kubeconfig ~/.kube/$$c.yaml -n velero get backupstoragelocation 2>&1 | sed 's/^/   /'; \
	done
	@echo "== Application (cluster-a)"; kubectl --kubeconfig ~/.kube/cluster-a.yaml -n app get pods 2>&1 | sed 's/^/   /'
	@echo "== MinIO"; curl -s -o /dev/null -w "   health: %{http_code}\n" http://192.168.100.30:9000/minio/health/live || true

backup:
	@./scripts/backup.sh

smoke:
	@./scripts/verify-smoke.sh

destroy:
	@$(I)/destroy-vm.sh cluster-a
	@$(I)/destroy-vm.sh cluster-b

destroy-all: destroy
	@$(I)/destroy-vm.sh backup
	@$(I)/destroy-network.sh
