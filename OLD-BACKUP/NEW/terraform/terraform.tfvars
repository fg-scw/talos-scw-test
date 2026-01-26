# =============================================================================
# Scaleway Talos Kubernetes - Configuration
# =============================================================================

region = "fr-par"
zone   = "fr-par-2"

cluster_name  = "talos-k8s"
talos_version = "v1.12.1"

# Network
private_network_cidr = "10.0.0.0/22"

# =============================================================================
# Control Plane (3 nodes for HA)
# =============================================================================
control_plane_count         = 3
control_plane_instance_type = "PRO2-S"

# =============================================================================
# GPU Workers
# =============================================================================
gpu_worker_count         = 1
gpu_worker_instance_type = "H100-1-80G"

# =============================================================================
# MIG Configuration
# =============================================================================
# Profiles:
#   all-disabled  - 1x 80GB (no MIG)
#   all-1g.10gb   - 7x 10GB
#   all-2g.20gb   - 3x 20GB (recommended)
#   all-3g.40gb   - 2x 40GB
#   mixed-40-20   - 1x 40GB + 2x 20GB
# =============================================================================
enable_gpu_mig  = true
gpu_mig_profile = "all-2g.20gb"

# =============================================================================
# CPU Workers
# =============================================================================
cpu_worker_count         = 3
cpu_worker_instance_type = "PRO2-XXS"

# =============================================================================
# Infrastructure
# =============================================================================
enable_bootstrap_bastion = true
bastion_instance_type    = "PRO2-S"
public_gateway_type      = "VPC-GW-S"
enable_gateway_bastion   = true
gateway_bastion_port     = 61000
load_balancer_type       = "LB-S"
