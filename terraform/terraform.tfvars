# ============================================================================
# Example Terraform Variables Configuration
# Copy this file to terraform.tfvars and adjust values
# ============================================================================

# Scaleway Configuration
region = "fr-par"
zone   = "fr-par-2"

# Cluster Configuration
cluster_name   = "talos-k8s"
environment    = "production"
talos_version  = "v1.12.1"
talos_image_name = ""  # Leave empty to auto-detect: talos-scaleway-v1.12.1

# Network
private_network_cidr = "10.0.0.0/22"

# Control Plane
control_plane_count         = 3
control_plane_instance_type = "PRO2-S"   # 2 vCPU, 8 GB RAM
control_plane_disk_size     = 50

# Workers
worker_count         = 3
worker_instance_type = "H100-1-80G"   # 4 vCPU, 16 GB RAM
worker_disk_size     = 100

# Load Balancer
load_balancer_type       = "LB-S"
expose_k8s_api_publicly  = false  # Set to true only if needed
expose_talos_api         = true

# Public Gateway
public_gateway_type      = "VPC-GW-S"
enable_bastion_on_gateway = true
bastion_ssh_port         = 61000
bastion_allowed_cidr     = ""  # Leave empty for 0.0.0.0/0

# Additional tags
additional_tags = [
  "team=platform",
  "project=kubernetes"
]

# Bootstrap Bastion (automatique)
bastion_enabled       = true   # Active le bootstrap automatique via bastion
bastion_instance_type = "DEV1-S"  # Suffisant pour le bootstrap
