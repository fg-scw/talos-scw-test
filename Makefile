.PHONY: help packer-init packer-build terraform-init terraform-plan terraform-apply terraform-destroy clean \
        bootstrap-status bootstrap-logs bootstrap-download-configs bootstrap-cleanup deploy-all

ZONE ?= fr-par-2
TALOS_VERSION ?= v1.12.1
CLUSTER_NAME ?= talos-k8s

help:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║         Talos on Scaleway - Makefile Commands                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🏗️  Build & Deploy:"
	@echo "  make deploy-all          - Complete deployment (Packer + Terraform)"
	@echo "  make packer-init         - Initialize Packer plugins"
	@echo "  make packer-build        - Build Talos image with Packer"
	@echo "  make terraform-init      - Initialize Terraform"
	@echo "  make terraform-plan      - Plan Terraform changes"
	@echo "  make terraform-apply     - Apply Terraform configuration"
	@echo ""
	@echo "🚀 Bootstrap (Automatic via Bastion):"
	@echo "  make bootstrap-status    - Watch bootstrap progress in real-time"
	@echo "  make bootstrap-logs      - View bootstrap logs"
	@echo "  make bootstrap-download  - Download kubeconfig & talosconfig from bastion"
	@echo "  make bootstrap-cleanup   - Destroy bastion after successful bootstrap"
	@echo ""
	@echo "🧹 Cleanup:"
	@echo "  make terraform-destroy   - Destroy entire infrastructure"
	@echo "  make clean               - Clean temporary files"
	@echo ""
	@echo "📋 Variables:"
	@echo "  ZONE=$(ZONE)"
	@echo "  TALOS_VERSION=$(TALOS_VERSION)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo ""

# ============================================================================
# Packer - Image Building
# ============================================================================

packer-init:
	@echo "🔧 Initializing Packer..."
	cd packer && packer init .

packer-build: packer-init
	@echo "🏗️  Building Talos $(TALOS_VERSION) image for $(ZONE)..."
	cd packer && packer build \
		-var "zone=$(ZONE)" \
		-var "talos_version=$(TALOS_VERSION)" \
		talos-scaleway.pkr.hcl
	@echo "✅ Talos image built successfully!"

# ============================================================================
# Terraform - Infrastructure
# ============================================================================

terraform-init:
	@echo "🔧 Initializing Terraform..."
	cd terraform && terraform init

terraform-plan: terraform-init
	@echo "📋 Planning Terraform changes..."
	cd terraform && terraform plan

terraform-apply: terraform-init
	@echo "🚀 Deploying infrastructure..."
	cd terraform && terraform apply
	@echo ""
	@echo "✅ Infrastructure deployed!"
	@echo ""
	@echo "📊 To follow bootstrap progress:"
	@echo "   make bootstrap-status"
	@echo ""
	@echo "📝 To view bootstrap logs:"
	@echo "   make bootstrap-logs"
	@echo ""

terraform-destroy:
	@echo "🗑️  Destroying infrastructure..."
	cd terraform && terraform destroy

# ============================================================================
# Bootstrap Management
# ============================================================================

bootstrap-status:
	@echo "📊 Following bootstrap status (Ctrl+C to exit)..."
	@BASTION_IP=$$(cd terraform && terraform output -raw bastion_ip 2>/dev/null); \
	if [ -z "$$BASTION_IP" ] || [ "$$BASTION_IP" = "null" ]; then \
		echo "❌ Bastion not found. Is bastion_enabled=true?"; \
		exit 1; \
	fi; \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		root@$$BASTION_IP 'journalctl -u talos-bootstrap -f'

bootstrap-logs:
	@echo "📝 Viewing bootstrap logs..."
	@BASTION_IP=$$(cd terraform && terraform output -raw bastion_ip 2>/dev/null); \
	if [ -z "$$BASTION_IP" ] || [ "$$BASTION_IP" = "null" ]; then \
		echo "❌ Bastion not found. Is bastion_enabled=true?"; \
		exit 1; \
	fi; \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		root@$$BASTION_IP 'tail -f /var/log/talos-bootstrap.log'

bootstrap-download:
	@echo "📥 Downloading Kubernetes configs from bastion..."
	@BASTION_IP=$$(cd terraform && terraform output -raw bastion_ip 2>/dev/null); \
	if [ -z "$$BASTION_IP" ] || [ "$$BASTION_IP" = "null" ]; then \
		echo "❌ Bastion not found. Is bastion_enabled=true?"; \
		exit 1; \
	fi; \
	mkdir -p _out ~/.kube ~/.talos; \
	echo "📥 Downloading kubeconfig..."; \
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		root@$$BASTION_IP:/root/talos-config/kubeconfig _out/kubeconfig; \
	cp _out/kubeconfig ~/.kube/$(CLUSTER_NAME)-config; \
	echo "📥 Downloading talosconfig..."; \
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		root@$$BASTION_IP:/root/talos-config/talosconfig _out/talosconfig; \
	cp _out/talosconfig ~/.talos/$(CLUSTER_NAME)-config; \
	echo ""; \
	echo "✅ Configs downloaded!"; \
	echo ""; \
	echo "📋 To use your cluster:"; \
	echo "   export KUBECONFIG=~/.kube/$(CLUSTER_NAME)-config"; \
	echo "   kubectl get nodes"; \
	echo ""

bootstrap-cleanup:
	@echo "🧹 Destroying bastion (keeping cluster running)..."
	cd terraform && terraform destroy -target=scaleway_instance_server.bastion[0] -target=scaleway_instance_ip.bastion[0]
	@echo "✅ Bastion destroyed. Cluster is still running."

# ============================================================================
# Complete Deployment
# ============================================================================

deploy-all: packer-build terraform-apply
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║          🎉 Complete Deployment Successful! 🎉                 ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 Bootstrap is running automatically on the bastion!"
	@echo ""
	@echo "📊 Follow progress:"
	@echo "   make bootstrap-status"
	@echo ""
	@echo "⏱️  Expected time: 8-10 minutes"
	@echo ""
	@echo "📥 Once complete, download configs:"
	@echo "   make bootstrap-download"
	@echo ""
	@echo "🧹 Clean up bastion:"
	@echo "   make bootstrap-cleanup"
	@echo ""

# ============================================================================
# Cleanup
# ============================================================================

clean:
	@echo "🧹 Cleaning temporary files..."
	rm -rf packer/packer_cache
	rm -f packer/manifest.json
	rm -f packer/packer.log
	rm -rf terraform/.terraform
	rm -f terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate*
	rm -rf _out
	@echo "✅ Cleaned!"
