# =============================================================================
# Talos Kubernetes on Scaleway - Example Configuration
# =============================================================================
# Copy this file to terraform.tfvars and adjust values as needed
# =============================================================================

# Cluster name (used for resource naming)
cluster_name = "talos-k8s"

# Scaleway region and zone
region = "fr-par"
zone   = "fr-par-2"  # GPU instances available in fr-par-2

# Talos version
talos_version = "v1.12.2"

# -----------------------------------------------------------------------------
# Control Plane Configuration
# -----------------------------------------------------------------------------

control_plane_count         = 3        # Recommended: 3 for HA
control_plane_instance_type = "PRO2-S" # 2 vCPU, 8GB RAM
control_plane_disk_size     = 50       # GB

# -----------------------------------------------------------------------------
# CPU Workers
# -----------------------------------------------------------------------------

cpu_worker_count         = 3         # Number of CPU-only workers
cpu_worker_instance_type = "PRO2-S"  # 4 vCPU, 16GB RAM
cpu_worker_disk_size     = 100       # GB

# -----------------------------------------------------------------------------
# GPU Workers
# -----------------------------------------------------------------------------

gpu_worker_count         = 1           # Number of GPU workers
gpu_worker_instance_type = "H100-1-80G" # NVIDIA H100 80GB
gpu_worker_disk_size     = 100         # GB

# -----------------------------------------------------------------------------
# GPU / MIG Configuration
# -----------------------------------------------------------------------------

# Enable MIG for multi-tenant GPU workloads
enable_gpu_mig = true

# MIG profile options:
# - "disabled"    : Full GPU, no partitioning (1x 80GB)
# - "all-1g.10gb" : 7 instances x 10GB each (best for inference)
# - "all-2g.20gb" : 3 instances x 20GB each
# - "all-3g.40gb" : 2 instances x 40GB each
gpu_mig_profile = "all-1g.10gb"

# Talos Factory schematic ID for GPU image
# This ID includes: qemu-guest-agent, util-linux-tools, nvidia drivers, container toolkit
gpu_schematic_id = "3d501d8855ab62b6742bc43f82da2967ea6e8f759797bc47d03fb84c6edf91d3"

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

private_network_cidr   = "10.0.0.0/24"
public_gateway_type    = "VPC-GW-S"
load_balancer_type     = "LB-S"
enable_gateway_bastion = true
gateway_bastion_port   = 61000
expose_talos_api       = false

# -----------------------------------------------------------------------------
# Bootstrap Bastion
# -----------------------------------------------------------------------------

enable_bootstrap_bastion = true
bastion_instance_type    = "PRO2-S"  # Small instance for bootstrap only
