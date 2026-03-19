# =============================================================================
# Homelab Makefile — Convenience Targets
# =============================================================================
#
# Usage:
#   make tf-init             — Initialise Terraform (download providers)
#   make tf-plan             — Preview VM changes without applying
#   make tf-apply            — Provision the Proxmox VM with Terraform
#   make tf-destroy          — Destroy the Proxmox VM (DESTRUCTIVE)
#   make tf-output           — Show Terraform outputs (IP, SSH command, etc.)
#
#   make bootstrap          — Install K3s and Helm on the VM
#   make argocd REPO=<url>  — Install ArgoCD and configure App of Apps
#   make status             — Show cluster, pod, and ArgoCD app status
#   make dashboard          — Port-forward Grafana and ArgoCD, print URLs
#   make teardown           — Completely uninstall K3s (with confirmation)
#
# Run "make help" to see all available targets.
# =============================================================================

# Default target: show help
.DEFAULT_GOAL := help

# Use bash for all shell commands (safer than sh for complex commands)
SHELL := /bin/bash

# Color codes for output
BLUE  := \033[0;34m
GREEN := \033[0;32m
YELLOW:= \033[1;33m
RED   := \033[0;31m
NC    := \033[0m

# =============================================================================
# HELP — auto-generated from ## comments
# =============================================================================

# Directory containing Terraform configuration
TERRAFORM_DIR := terraform

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "  Homelab — Kubernetes on Proxmox"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# TERRAFORM — Proxmox VM Provisioning
# =============================================================================

.PHONY: tf-init
tf-init: ## Initialise Terraform and download the bpg/proxmox provider
	@echo -e "$(BLUE)[INFO]$(NC) Initialising Terraform..."
	@if [ ! -f "$(TERRAFORM_DIR)/terraform.tfvars" ]; then \
		echo -e "$(YELLOW)[WARN]$(NC) terraform.tfvars not found."; \
		echo -e "$(YELLOW)[WARN]$(NC) Copy the example and fill in your values:"; \
		echo -e "  cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars"; \
		echo -e "  nano $(TERRAFORM_DIR)/terraform.tfvars"; \
	fi
	@cd $(TERRAFORM_DIR) && terraform init

.PHONY: tf-plan
tf-plan: ## Preview what Terraform will create/change (no changes applied)
	@echo -e "$(BLUE)[INFO]$(NC) Running Terraform plan..."
	@cd $(TERRAFORM_DIR) && terraform plan

.PHONY: tf-apply
tf-apply: ## Provision the Proxmox VM (will prompt for confirmation)
	@echo -e "$(BLUE)[INFO]$(NC) Applying Terraform configuration..."
	@cd $(TERRAFORM_DIR) && terraform apply

.PHONY: tf-apply-auto
tf-apply-auto: ## Provision the VM without confirmation prompt (use with care)
	@echo -e "$(YELLOW)[WARN]$(NC) Applying without confirmation..."
	@cd $(TERRAFORM_DIR) && terraform apply -auto-approve

.PHONY: tf-destroy
tf-destroy: ## DESTROY the Proxmox VM — all data will be lost (prompts for confirmation)
	@echo -e "$(RED)WARNING: This will DELETE the VM and ALL its data from Proxmox!$(NC)"
	@read -p "Type 'yes' to confirm destruction: " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Destruction cancelled."; \
		exit 0; \
	fi
	@cd $(TERRAFORM_DIR) && terraform destroy

.PHONY: tf-output
tf-output: ## Show Terraform outputs (VM IP, SSH command, next steps)
	@cd $(TERRAFORM_DIR) && terraform output

.PHONY: tf-state
tf-state: ## List all resources tracked in Terraform state
	@cd $(TERRAFORM_DIR) && terraform state list

.PHONY: tf-validate
tf-validate: ## Validate Terraform configuration syntax
	@cd $(TERRAFORM_DIR) && terraform validate && echo -e "$(GREEN)Configuration is valid$(NC)"

.PHONY: tf-fmt
tf-fmt: ## Format Terraform files to canonical style
	@cd $(TERRAFORM_DIR) && terraform fmt -recursive

# =============================================================================
# BOOTSTRAP — Install K3s and prerequisites on the VM
# =============================================================================

.PHONY: bootstrap
bootstrap: ## Install K3s, Helm, and prerequisites on this machine
	@echo -e "$(BLUE)[INFO]$(NC) Running bootstrap script..."
	@bash scripts/bootstrap.sh

# =============================================================================
# ARGOCD — Install ArgoCD and configure App of Apps
# =============================================================================

.PHONY: argocd
argocd: ## Install ArgoCD and point it at your repo (usage: make argocd REPO=https://github.com/you/homelab.git)
	@if [ -z "$(REPO)" ]; then \
		echo -e "$(RED)[ERROR]$(NC) REPO is required. Usage: make argocd REPO=https://github.com/you/homelab.git"; \
		exit 1; \
	fi
	@echo -e "$(BLUE)[INFO]$(NC) Installing ArgoCD and configuring App of Apps..."
	@bash scripts/install-argocd.sh $(REPO)

# =============================================================================
# GITHUB — Initialize git and push to GitHub
# =============================================================================

.PHONY: github
github: ## Create GitHub repo and push (requires gh CLI authenticated)
	@echo -e "$(BLUE)[INFO]$(NC) Setting up GitHub repository..."
	@bash scripts/setup-github-repo.sh

# =============================================================================
# STATUS — Show cluster and application status
# =============================================================================

.PHONY: status
status: ## Show node status, running pods, and ArgoCD app sync status
	@echo ""
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@echo -e "$(BLUE) Node Status$(NC)"
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@kubectl get nodes -o wide 2>/dev/null || echo "  Cannot connect to cluster"

	@echo ""
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@echo -e "$(BLUE) Pod Status (all namespaces)$(NC)"
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@kubectl get pods -A --sort-by='.metadata.namespace' 2>/dev/null || echo "  Cannot connect to cluster"

	@echo ""
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@echo -e "$(BLUE) ArgoCD Applications$(NC)"
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@kubectl get applications -n argocd 2>/dev/null || echo "  ArgoCD not installed yet"

	@echo ""
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@echo -e "$(BLUE) PersistentVolumeClaims$(NC)"
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@kubectl get pvc -A 2>/dev/null || echo "  Cannot connect to cluster"

	@echo ""
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@echo -e "$(BLUE) Ingress Resources$(NC)"
	@echo -e "$(BLUE)══════════════════════════════════════$(NC)"
	@kubectl get ingress -A 2>/dev/null || echo "  No ingress resources found"

# =============================================================================
# DASHBOARD — Port-forward Grafana and ArgoCD for local access
# =============================================================================

.PHONY: dashboard
dashboard: ## Port-forward Grafana (3000) and ArgoCD (8080), print URLs and credentials
	@echo ""
	@echo -e "$(GREEN)Starting port forwards...$(NC)"
	@echo -e "  Grafana  → http://localhost:3000"
	@echo -e "  ArgoCD   → http://localhost:8080"
	@echo ""
	@echo -e "$(YELLOW)Credentials:$(NC)"
	@echo -n "  ArgoCD  admin password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null && echo || echo "(not found)"
	@echo -e "  Grafana admin password: homelab-grafana (set in system/monitoring/values.yaml)"
	@echo ""
	@echo -e "$(YELLOW)Press Ctrl+C to stop port forwarding$(NC)"
	@echo ""
	# Port-forward both services in the background, then wait
	@kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
	@kubectl port-forward -n argocd svc/argocd-server 8080:80 &
	@wait

# =============================================================================
# LOGS — Tail logs for a specific app
# =============================================================================

.PHONY: logs
logs: ## Tail logs for an app (usage: make logs APP=argocd-server NS=argocd)
	@if [ -z "$(APP)" ]; then \
		echo -e "$(RED)[ERROR]$(NC) APP is required. Usage: make logs APP=argocd-server NS=argocd"; \
		exit 1; \
	fi
	@NS_ARG=$${NS:+-n $(NS)}; \
	kubectl logs -l app.kubernetes.io/name=$(APP) $$NS_ARG --follow --tail=100

# =============================================================================
# SYNC — Force ArgoCD to sync all apps
# =============================================================================

.PHONY: sync
sync: ## Force sync all ArgoCD applications
	@echo -e "$(BLUE)[INFO]$(NC) Triggering sync for all ArgoCD applications..."
	@for app in $$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}'); do \
		echo -e "  Syncing: $$app"; \
		kubectl patch application $$app -n argocd \
			--type merge \
			-p '{"operation": {"initiatedBy": {"username": "make-sync"}, "sync": {"revision": "HEAD"}}}' \
			2>/dev/null || true; \
	done
	@echo -e "$(GREEN)Sync triggered for all apps$(NC)"

# =============================================================================
# TEARDOWN — Completely remove K3s
# =============================================================================

.PHONY: teardown
teardown: ## Completely uninstall K3s from this machine (DESTRUCTIVE — requires confirmation)
	@echo -e "$(RED)WARNING: This will completely remove K3s and ALL data from this machine!$(NC)"
	@echo -e "$(RED)This includes all pods, services, PersistentVolumes, and cluster data.$(NC)"
	@echo ""
	@read -p "Type 'yes' to confirm teardown: " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "Teardown cancelled."; \
		exit 0; \
	fi
	@echo -e "$(YELLOW)[INFO]$(NC) Running K3s uninstall script..."
	@if [ -f /usr/local/bin/k3s-uninstall.sh ]; then \
		sudo /usr/local/bin/k3s-uninstall.sh; \
		echo -e "$(GREEN)K3s uninstalled successfully$(NC)"; \
	else \
		echo -e "$(RED)K3s uninstall script not found. Is K3s installed?$(NC)"; \
	fi
	@echo ""
	@echo "Cleaning up kubeconfig..."
	@rm -f ~/.kube/config
	@echo -e "$(GREEN)Teardown complete.$(NC)"

# =============================================================================
# KUBECONFIG — Print kubeconfig path
# =============================================================================

.PHONY: kubeconfig
kubeconfig: ## Print the kubeconfig file path and export instructions
	@echo "Kubeconfig location: ~/.kube/config"
	@echo ""
	@echo "To use kubectl from another machine, copy this file:"
	@echo "  scp ubuntu@YOUR_VM_IP:~/.kube/config ~/.kube/homelab.yaml"
	@echo "  export KUBECONFIG=~/.kube/homelab.yaml"
	@echo ""
	@echo "NOTE: Update the server address in the file:"
	@echo "  Current: https://127.0.0.1:6443"
	@echo "  Change to: https://YOUR_VM_IP:6443"
