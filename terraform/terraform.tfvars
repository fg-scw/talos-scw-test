# =============================================================================
# Scaleway Talos Kubernetes Cluster Configuration
# =============================================================================

# Scaleway
region = "fr-par"
zone   = "fr-par-2"

# Cluster
cluster_name  = "talos-k8s"
environment   = "production"
talos_version = "v1.12.1"

# Network
private_network_cidr = "10.0.0.0/22"

# Control Plane (3 nodes for HA)
control_plane_count         = 3
control_plane_instance_type = "PRO2-S"
control_plane_disk_size     = 50

# GPU Workers (H100)
gpu_worker_count         = 1
gpu_worker_instance_type = "H100-1-80G"
gpu_worker_disk_size     = 100

# CPU Workers
cpu_worker_count         = 3
cpu_worker_instance_type = "PRO2-XXS"
cpu_worker_disk_size     = 50

# GPU MIG Configuration
# Set enable_gpu_mig=true to install MIG Manager
# gpu_mig_profile options:
#   - all-disabled: Full 80GB GPU (default)
#   - all-1g.10gb:  7x 10GB slices
#   - all-2g.20gb:  3x 20GB slices
#   - all-3g.40gb:  2x 40GB slices
#   - mixed-40-20:  1x 40GB + 2x 20GB
enable_gpu_mig  = false
gpu_mig_profile = "all-disabled"

# Load Balancer
load_balancer_type      = "LB-S"
expose_k8s_api_publicly = false
expose_talos_api        = true

# Public Gateway
public_gateway_type    = "VPC-GW-S"
enable_gateway_bastion = true
gateway_bastion_port   = 61000

# Bootstrap Bastion
enable_bootstrap_bastion = true
bastion_instance_type    = "DEV1-S"

# Tags
additional_tags = [
  "team=platform",
  "project=kubernetes",
]
