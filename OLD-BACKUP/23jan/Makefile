# =============================================================================
# Talos Kubernetes on Scaleway - GPU Ready
# =============================================================================

.PHONY: help init build-minimal build-gpu build-all deploy destroy clean status logs download cleanup validate ssh plan gpu-status mig-status

# Configuration
ZONE ?= fr-par-2
TALOS_VERSION ?= v1.12.2
CLUSTER_NAME ?= talos-k8s
GATEWAY_IP ?= $(shell cd terraform && terraform output -raw public_gateway_ip 2>/dev/null)
BASTION_PRIVATE_IP ?= $(shell cd terraform && terraform output -raw bastion_private_ip 2>/dev/null)

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
CYAN := \033[0;36m
NC := \033[0m

help:
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════════╗"
	@echo "║       Talos Kubernetes on Scaleway - GPU + MIG Ready              ║"
	@echo "╚═══════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "$(CYAN)🔧 Setup:$(NC)"
	@echo "  make init               - Initialize Packer and Terraform"
	@echo ""
	@echo "$(CYAN)🏗️  Build Images:$(NC)"
	@echo "  make build-minimal      - Build Talos image for CP & CPU workers"
	@echo "  make build-gpu          - Build Talos image for GPU workers (NVIDIA)"
	@echo "  make build-all          - Build both images"
	@echo ""
	@echo "$(CYAN)🚀 Deploy:$(NC)"
	@echo "  make plan               - Terraform plan"
	@echo "  make deploy             - Deploy infrastructure"
	@echo "  make all                - Build all + Deploy"
	@echo ""
	@echo "$(CYAN)📊 Operations:$(NC)"
	@echo "  make status             - Show bootstrap progress"
	@echo "  make logs               - Show full bootstrap logs"
	@echo "  make ssh                - SSH to bastion"
	@echo "  make download           - Download kubeconfig"
	@echo ""
	@echo "$(CYAN)🎮 GPU Operations:$(NC)"
	@echo "  make gpu-status         - Show GPU node status"
	@echo "  make mig-status         - Show MIG configuration"
	@echo "  make validate           - Validate GPU with test pod"
	@echo ""
	@echo "$(CYAN)🧹 Cleanup:$(NC)"
	@echo "  make cleanup            - Destroy bastion only"
	@echo "  make destroy            - Destroy all infrastructure"
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
	@echo "$(GREEN)🏗️  Building Talos $(TALOS_VERSION) GPU image...$(NC)"
	cd packer && packer build \
		-var "zone=$(ZONE)" \
		-var "talos_version=$(TALOS_VERSION)" \
		-var "schematic_file=provision/schematic-gpu.yaml" \
		-var "image_suffix=-gpu" \
		-force \
		talos-scaleway.pkr.hcl
	@echo "$(GREEN)✅ GPU image built$(NC)"

build-all: build-minimal build-gpu
	@echo "$(GREEN)✅ All images built$(NC)"

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
	@echo "╔═══════════════════════════════════════════════════════════════════╗"
	@echo "║              🎉 Deployment Started! 🎉                            ║"
	@echo "╚═══════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📊 Follow bootstrap progress:"
	@echo "   make status"
	@echo ""
	@echo "⏱️  Expected time: ~15-20 minutes (with MIG configuration)"
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
	@echo "To use:"
	@echo "  export KUBECONFIG=~/.kube/$(CLUSTER_NAME)-config"
	@echo "  kubectl get nodes"

# =============================================================================
# GPU Operations
# =============================================================================

validate:
	@echo "$(GREEN)🔍 Validating GPU...$(NC)"
	@ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		'kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"'

gpu-status:
	@echo "$(GREEN)🎮 GPU Node Status:$(NC)"
	@ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		'echo "=== Nodes ===" && kubectl get nodes -o wide && echo "" && \
		 echo "=== GPU Resources ===" && kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu" && echo "" && \
		 echo "=== GPU Stack Pods ===" && kubectl -n nvidia-gpu-stack get pods'

mig-status:
	@echo "$(GREEN)🎮 MIG Configuration Status:$(NC)"
	@ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		'echo "=== MIG Config ===" && kubectl -n nvidia-gpu-stack get configmap mig-config -o jsonpath="{.data}" && echo "" && \
		 echo "" && echo "=== MIG Configurator Logs ===" && kubectl -n nvidia-gpu-stack logs -l app=mig-configurator -c configure-mig --tail=30 2>/dev/null || echo "No logs yet"'

gpu-test:
	@echo "$(GREEN)🧪 Running GPU test...$(NC)"
	@ssh -o StrictHostKeyChecking=no -J bastion@$(GATEWAY_IP):61000 root@$(BASTION_PRIVATE_IP) \
		'kubectl run gpu-test-$$$$ --rm -it --restart=Never \
			--image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
			--overrides='"'"'{"spec":{"runtimeClassName":"nvidia","tolerations":[{"key":"nvidia.com/gpu","operator":"Exists"}],"containers":[{"name":"cuda","image":"nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04","command":["nvidia-smi","-L"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}'"'"' 2>/dev/null || true'

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
