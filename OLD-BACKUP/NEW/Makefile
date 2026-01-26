# =============================================================================
# Talos Kubernetes on Scaleway - Makefile
# =============================================================================

.PHONY: help init build-minimal build-gpu build-all deploy destroy clean status logs download cleanup validate ssh plan

# Configuration
ZONE ?= fr-par-2
TALOS_VERSION ?= v1.12.1
CLUSTER_NAME ?= talos-k8s
GATEWAY_IP ?= $(shell cd terraform && terraform output -raw public_gateway_ip 2>/dev/null)
BASTION_PRIVATE_IP ?= $(shell cd terraform && terraform output -raw bastion_private_ip 2>/dev/null)

# Couleurs
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

help:
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║     Talos Kubernetes on Scaleway - GPU + MIG Ready            ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔧 Setup:"
	@echo "  make init               - Initialize Packer and Terraform"
	@echo ""
	@echo "🏗️  Build Images:"
	@echo "  make build-minimal      - Build Talos image for control plane & CPU workers"
	@echo "  make build-gpu          - Build Talos image for GPU workers (with NVIDIA)"
	@echo "  make build-all          - Build both images (required before deploy)"
	@echo ""
	@echo "🚀 Deploy:"
	@echo "  make plan               - Terraform plan"
	@echo "  make deploy             - Deploy infrastructure with Terraform"
	@echo "  make all                - Build all images + Deploy infrastructure"
	@echo ""
	@echo "📊 Operations:"
	@echo "  make status             - Show bootstrap progress"
	@echo "  make logs               - Show full bootstrap logs"
	@echo "  make ssh                - SSH to bastion"
	@echo "  make download           - Download kubeconfig and talosconfig"
	@echo "  make validate           - Validate GPU node"
	@echo ""
	@echo "🧹 Cleanup:"
	@echo "  make cleanup            - Destroy bastion only (keep cluster)"
	@echo "  make destroy            - Destroy all infrastructure"
	@echo ""
	@echo "Note: Create .envrc from .envrc.example and run 'source .envrc'"
	@echo ""

# =============================================================================
# Initialization
# =============================================================================

init:
	@echo "$(GREEN)🔧 Initializing Packer...$(NC)"
	cd packer && packer init .
	@echo "$(GREEN)🔧 Initializing Terraform...$(NC)"
	cd terraform && terraform init
	@echo "$(GREEN)✅ Initialization complete$(NC)"

# =============================================================================
# Image Building
# =============================================================================

build-minimal: 
	@echo "$(GREEN)🏗️  Building Talos $(TALOS_VERSION) minimal image...$(NC)"
	cd packer && packer build \
		-var "zone=$(ZONE)" \
		-var "talos_version=$(TALOS_VERSION)" \
		-var "schematic_file=provision/schematic-minimal.yaml" \
		-var "image_suffix=-minimal" \
		-force \
		talos-scaleway.pkr.hcl
	@echo "$(GREEN)✅ Minimal image built$(NC)"

build-gpu:
	@echo "$(GREEN)🏗️  Building Talos $(TALOS_VERSION) GPU image (with NVIDIA extensions)...$(NC)"
	cd packer && packer build \
		-var "zone=$(ZONE)" \
		-var "talos_version=$(TALOS_VERSION)" \
		-var "schematic_file=provision/schematic-gpu.yaml" \
		-var "image_suffix=-gpu" \
		-force \
		talos-scaleway.pkr.hcl
	@echo "$(GREEN)✅ GPU image built$(NC)"

build-all: build-minimal build-gpu
	@echo "$(GREEN)✅ All Talos images built successfully$(NC)"

# =============================================================================
# Terraform Deployment
# =============================================================================

plan:
	cd terraform && terraform plan

deploy: init
	@echo "$(GREEN)🚀 Deploying infrastructure...$(NC)"
	cd terraform && terraform apply -auto-approve
	@echo ""
	@echo "$(GREEN)✅ Infrastructure deployed!$(NC)"
	@echo ""
	@echo "📊 Follow bootstrap: make status"
	@echo "🔑 SSH to bastion:   make ssh"

# =============================================================================
# Full Deployment
# =============================================================================

all: build-all deploy
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║          🎉 Complete Deployment Successful! 🎉                ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📊 Follow bootstrap progress:"
	@echo "   make status"
	@echo ""

# =============================================================================
# Operations
# =============================================================================

ssh:
	@echo "$(GREEN)🔑 Connecting to bastion...$(NC)"
	ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP)

status:
	@echo "$(GREEN)📊 Checking bootstrap status...$(NC)"
	ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		"journalctl -u talos-bootstrap.service -f"

logs:
	@echo "$(GREEN)📋 Fetching bootstrap logs...$(NC)"
	ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		"journalctl -u talos-bootstrap.service --no-pager"

download:
	@echo "$(GREEN)⬇️  Downloading configurations...$(NC)"
	@mkdir -p ~/.kube ~/.talos
	scp -o StrictHostKeyChecking=no -o ProxyJump=bastion@$(GATEWAY_IP):61000 \
		root@$(BASTION_PRIVATE_IP):/root/talos-config/kubeconfig ~/.kube/$(CLUSTER_NAME)-config
	scp -o StrictHostKeyChecking=no -o ProxyJump=bastion@$(GATEWAY_IP):61000 \
		root@$(BASTION_PRIVATE_IP):/root/talos-config/talosconfig ~/.talos/$(CLUSTER_NAME)-config 2>/dev/null || true
	@echo ""
	@echo "$(GREEN)✅ Configurations downloaded!$(NC)"
	@echo ""
	@echo "To use the cluster:"
	@echo "  export KUBECONFIG=~/.kube/$(CLUSTER_NAME)-config"
	@echo "  kubectl get nodes"

validate:
	@echo "$(GREEN)🔍 Validating GPU node...$(NC)"
	@ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		'kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"'

# =============================================================================
# Cleanup
# =============================================================================

cleanup:
	@echo "$(YELLOW)🧹 Destroying bastion only...$(NC)"
	cd terraform && terraform destroy -target=scaleway_instance_server.bastion -auto-approve
	@echo "$(GREEN)✅ Bastion destroyed. Cluster is still running.$(NC)"

destroy:
	@echo "$(RED)💥 Destroying all infrastructure...$(NC)"
	cd terraform && terraform destroy -auto-approve
	@echo "$(GREEN)✅ All infrastructure destroyed$(NC)"

clean: destroy
	@echo "$(YELLOW)🧹 Cleaning local files...$(NC)"
	rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl
	rm -f packer/manifest.json
	@echo "$(GREEN)✅ Clean complete$(NC)"
