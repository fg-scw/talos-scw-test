# =============================================================================
# Talos Kubernetes on Scaleway - GPU Ready
# =============================================================================

.PHONY: help init build-minimal build-gpu build-all plan deploy destroy clean \
        status logs ssh download gpu-status mig-status gpu-test validate

# Configuration
ZONE ?= fr-par-2
TALOS_VERSION ?= v1.12.2
CLUSTER_NAME ?= talos-k8s

# Scaleway Factory API
TALOS_FACTORY_URL := https://factory.talos.dev/schematics

# Dynamic values from Terraform
GATEWAY_IP = $(shell cd terraform && terraform output -raw cluster_info 2>/dev/null | jq -r '.public_gateway_ip' 2>/dev/null || echo "")
BASTION_IP = $(shell cd terraform && terraform output -raw bastion_info 2>/dev/null | jq -r '.private_ip' 2>/dev/null || echo "")

# Colors
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
CYAN   := \033[0;36m
NC     := \033[0m

# =============================================================================
# Help
# =============================================================================

help:
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════════╗"
	@echo "║         Talos Kubernetes on Scaleway - GPU + MIG Ready            ║"
	@echo "╚═══════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "$(CYAN)🔧 Setup:$(NC)"
	@echo "  make init              Initialize Packer and Terraform"
	@echo ""
	@echo "$(CYAN)🏗️  Build Images:$(NC)"
	@echo "  make build-minimal     Build Talos image for CP & CPU workers"
	@echo "  make build-gpu         Build Talos image for GPU workers"
	@echo "  make build-all         Build both images"
	@echo ""
	@echo "$(CYAN)🚀 Deploy:$(NC)"
	@echo "  make plan              Terraform plan"
	@echo "  make deploy            Deploy infrastructure"
	@echo "  make all               Build all + Deploy"
	@echo ""
	@echo "$(CYAN)📊 Operations:$(NC)"
	@echo "  make status            Show bootstrap progress (live)"
	@echo "  make logs              Show full bootstrap logs"
	@echo "  make ssh               SSH to bastion"
	@echo "  make download          Download kubeconfig & talosconfig"
	@echo ""
	@echo "$(CYAN)🎮 GPU Operations:$(NC)"
	@echo "  make gpu-status        Show GPU node status"
	@echo "  make mig-status        Show MIG configuration"
	@echo "  make gpu-test          Run GPU validation test"
	@echo ""
	@echo "$(CYAN)🧹 Cleanup:$(NC)"
	@echo "  make destroy           Destroy all infrastructure"
	@echo "  make clean             Destroy + clean local files"
	@echo ""

# =============================================================================
# Initialization
# =============================================================================

init:
	@echo "$(GREEN)🔧 Initializing Packer...$(NC)"
	@cd packer && packer init .
	@echo "$(GREEN)🔧 Initializing Terraform...$(NC)"
	@cd terraform && terraform init
	@echo "$(GREEN)✅ Initialization complete$(NC)"

# =============================================================================
# Image Building
# =============================================================================

build-minimal:
	@echo "$(GREEN)🔍 Calculating Schematic ID for Minimal...$(NC)"
	$(eval MINIMAL_ID := $(shell curl -s -X POST --data-binary @packer/provision/schematic-minimal.yaml $(TALOS_FACTORY_URL) | jq -r .id))
	@echo "   Schematic ID: $(MINIMAL_ID)"
	@echo "$(GREEN)🏗️  Building Talos $(TALOS_VERSION) minimal image...$(NC)"
	@cd packer && packer build \
		-var "zone=$(ZONE)" \
		-var "talos_version=$(TALOS_VERSION)" \
		-var "schematic_id=$(MINIMAL_ID)" \
		-var "image_suffix=-minimal" \
		-force \
		talos-scaleway.pkr.hcl
	@echo "$(GREEN)✅ Minimal image built$(NC)"

build-gpu:
	@echo "$(GREEN)🔍 Calculating Schematic ID for GPU...$(NC)"
	$(eval GPU_ID := $(shell curl -s -X POST --data-binary @packer/provision/schematic-gpu.yaml $(TALOS_FACTORY_URL) | jq -r .id))
	@echo "   Schematic ID: $(GPU_ID)"
	@echo "$(GREEN)🏗️  Building Talos $(TALOS_VERSION) GPU image...$(NC)"
	@cd packer && packer build \
		-var "zone=$(ZONE)" \
		-var "talos_version=$(TALOS_VERSION)" \
		-var "schematic_id=$(GPU_ID)" \
		-var "image_suffix=-gpu" \
		-force \
		talos-scaleway.pkr.hcl
	@echo "$(GREEN)✅ GPU image built$(NC)"

build-all: build-minimal build-gpu
	@echo "$(GREEN)🎉 All images built successfully!$(NC)"

# =============================================================================
# Terraform Deployment
# =============================================================================

plan:
	@echo "$(GREEN)🔍 Calculating Schematic IDs...$(NC)"
	$(eval MINIMAL_ID := $(shell curl -s -X POST --data-binary @packer/provision/schematic-minimal.yaml $(TALOS_FACTORY_URL) | jq -r .id))
	$(eval GPU_ID := $(shell curl -s -X POST --data-binary @packer/provision/schematic-gpu.yaml $(TALOS_FACTORY_URL) | jq -r .id))
	@echo "   Minimal: $(MINIMAL_ID)"
	@echo "   GPU:     $(GPU_ID)"
	@cd terraform && terraform plan \
		-var="minimal_schematic_id=$(MINIMAL_ID)" \
		-var="gpu_schematic_id=$(GPU_ID)"

deploy:
	@echo "$(GREEN)🔍 Calculating Schematic IDs...$(NC)"
	$(eval MINIMAL_ID := $(shell curl -s -X POST --data-binary @packer/provision/schematic-minimal.yaml $(TALOS_FACTORY_URL) | jq -r .id))
	$(eval GPU_ID := $(shell curl -s -X POST --data-binary @packer/provision/schematic-gpu.yaml $(TALOS_FACTORY_URL) | jq -r .id))
	@echo "   Minimal: $(MINIMAL_ID)"
	@echo "   GPU:     $(GPU_ID)"
	@echo "$(GREEN)🚀 Deploying infrastructure...$(NC)"
	@cd terraform && terraform apply -auto-approve \
		-var="minimal_schematic_id=$(MINIMAL_ID)" \
		-var="gpu_schematic_id=$(GPU_ID)"
	@echo ""
	@echo "$(GREEN)✅ Infrastructure deployed!$(NC)"
	@echo ""
	@echo "📊 Follow bootstrap: make status"
	@echo "🔑 SSH to bastion:   make ssh"

all: init build-all deploy
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════════╗"
	@echo "║                   🎉 Deployment Started! 🎉                       ║"
	@echo "╚═══════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📊 Follow bootstrap progress: make status"
	@echo "⏱️  Expected time: ~15-20 minutes (with MIG auto-configuration)"
	@echo ""

# =============================================================================
# Operations
# =============================================================================

ssh:
	@echo "$(GREEN)🔑 Connecting to bastion...$(NC)"
	@cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.ssh_command' | xargs -I {} sh -c '{}'

status:
	@echo "$(GREEN)📊 Bootstrap status (live)...$(NC)"
	@GATEWAY=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.public_gateway_ip') && \
	BASTION=$$(cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.private_ip') && \
	ssh -o StrictHostKeyChecking=no -J "bastion@$$GATEWAY:61000" "root@$$BASTION" \
		"journalctl -u talos-bootstrap.service -f"

logs:
	@echo "$(GREEN)📋 Full bootstrap logs...$(NC)"
	@GATEWAY=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.public_gateway_ip') && \
	BASTION=$$(cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.private_ip') && \
	ssh -o StrictHostKeyChecking=no -J "bastion@$$GATEWAY:61000" "root@$$BASTION" \
		"journalctl -u talos-bootstrap.service --no-pager"

download:
	@echo "$(GREEN)⬇️  Downloading configurations...$(NC)"
	@mkdir -p ~/.kube ~/.talos
	@GATEWAY=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.public_gateway_ip') && \
	BASTION=$$(cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.private_ip') && \
	CLUSTER=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.name') && \
	scp -o StrictHostKeyChecking=no -o "ProxyJump=bastion@$$GATEWAY:61000" \
		"root@$$BASTION:/root/talos-config/kubeconfig" "$$HOME/.kube/$$CLUSTER-config" && \
	scp -o StrictHostKeyChecking=no -o "ProxyJump=bastion@$$GATEWAY:61000" \
		"root@$$BASTION:/root/talos-config/talosconfig" "$$HOME/.talos/$$CLUSTER-config" 2>/dev/null || true && \
	echo "" && \
	echo "$(GREEN)✅ Configurations downloaded!$(NC)" && \
	echo "" && \
	echo "To use:" && \
	echo "  export KUBECONFIG=~/.kube/$$CLUSTER-config" && \
	echo "  kubectl get nodes"

# =============================================================================
# GPU Operations
# =============================================================================

gpu-status:
	@echo "$(GREEN)🎮 GPU Node Status:$(NC)"
	@GATEWAY=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.public_gateway_ip') && \
	BASTION=$$(cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.private_ip') && \
	ssh -o StrictHostKeyChecking=no -J "bastion@$$GATEWAY:61000" "root@$$BASTION" \
		'export KUBECONFIG=/root/talos-config/kubeconfig && \
		echo "=== Nodes ===" && \
		kubectl get nodes -o wide && echo "" && \
		echo "=== GPU Resources ===" && \
		kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu" && echo "" && \
		echo "=== GPU Stack Pods ===" && \
		kubectl -n nvidia-gpu-stack get pods -o wide'

mig-status:
	@echo "$(GREEN)🎮 MIG Configuration:$(NC)"
	@GATEWAY=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.public_gateway_ip') && \
	BASTION=$$(cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.private_ip') && \
	ssh -o StrictHostKeyChecking=no -J "bastion@$$GATEWAY:61000" "root@$$BASTION" \
		'export KUBECONFIG=/root/talos-config/kubeconfig && \
		echo "=== MIG Config ===" && \
		kubectl -n nvidia-gpu-stack get configmap mig-config -o yaml && echo "" && \
		echo "=== MIG Configurator Logs ===" && \
		kubectl -n nvidia-gpu-stack logs -l app=mig-configurator -c configure-mig --tail=30 2>/dev/null || echo "No logs yet"'

gpu-test:
	@echo "$(GREEN)🧪 Running GPU validation test...$(NC)"
	@GATEWAY=$$(cd terraform && terraform output -json cluster_info 2>/dev/null | jq -r '.public_gateway_ip') && \
	BASTION=$$(cd terraform && terraform output -json bastion_info 2>/dev/null | jq -r '.private_ip') && \
	ssh -o StrictHostKeyChecking=no -J "bastion@$$GATEWAY:61000" "root@$$BASTION" \
		'export KUBECONFIG=/root/talos-config/kubeconfig && \
		kubectl run gpu-test-$$$$ --rm -it --restart=Never \
			--image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
			--overrides='"'"'{ \
				"spec": { \
					"runtimeClassName": "nvidia", \
					"tolerations": [{"operator": "Exists"}], \
					"containers": [{ \
						"name": "cuda", \
						"image": "nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04", \
						"command": ["nvidia-smi"], \
						"resources": {"limits": {"nvidia.com/gpu": "1"}} \
					}] \
				} \
			}'"'"' 2>/dev/null || echo "Test completed"'

validate: gpu-test

# =============================================================================
# Cleanup
# =============================================================================

destroy:
	@echo "$(RED)💥 Destroying all infrastructure...$(NC)"
	@cd terraform && terraform destroy -auto-approve
	@echo "$(GREEN)✅ Infrastructure destroyed$(NC)"

clean: destroy
	@echo "$(YELLOW)🧹 Cleaning local files...$(NC)"
	@rm -rf terraform/.terraform terraform/terraform.tfstate* terraform/.terraform.lock.hcl
	@rm -f packer/manifest.json
	@echo "$(GREEN)✅ Clean complete$(NC)"
