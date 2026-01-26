# =============================================================================
# Talos Kubernetes on Scaleway - Configuration
# =============================================================================

# Cluster identification
cluster_name = "talos-k8s"

# Scaleway location (fr-par-2 required for GPU instances)
region = "fr-par"
zone   = "fr-par-2"

# Talos version
talos_version = "v1.12.2"

talos_gpu_image_id     = "5c0a7022-4db1-4b7b-8295-c656a63a5524"
talos_minimal_image_id = "1a18665b-1142-47f8-8ed4-671bd640e56c"

# -----------------------------------------------------------------------------
# Control Plane (3 nodes recommended for HA)
# -----------------------------------------------------------------------------
control_plane_count         = 3
control_plane_instance_type = "PRO2-S"  # 2 vCPU, 8GB RAM
control_plane_disk_size     = 50

# -----------------------------------------------------------------------------
# CPU Workers
# -----------------------------------------------------------------------------
cpu_worker_count         = 2
cpu_worker_instance_type = "PRO2-M"  # 4 vCPU, 16GB RAM
cpu_worker_disk_size     = 100

# -----------------------------------------------------------------------------
# GPU Workers (NVIDIA H100)
# -----------------------------------------------------------------------------
gpu_worker_count         = 1
gpu_worker_instance_type = "H100-1-80G"
gpu_worker_disk_size     = 100

# -----------------------------------------------------------------------------
# MIG Configuration
# -----------------------------------------------------------------------------
# Enable MIG for multi-tenant GPU workloads
enable_gpu_mig = true

# MIG Profile Options:
#   disabled     - Full GPU, no partitioning (1x 80GB)
#   all-1g.10gb  - 7x 10GB instances (best for Whisper)
#   all-2g.20gb  - 3x 20GB instances
#   all-3g.40gb  - 2x 40GB instances
#   all-7g.80gb  - 1x 80GB MIG instance
#   mixed-4g-3g  - 1x 40GB + 1x 40GB (different compute)
gpu_mig_profile = "all-1g.10gb"

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------
private_network_cidr   = "10.0.0.0/24"
public_gateway_type    = "VPC-GW-S"
load_balancer_type     = "LB-S"
enable_gateway_bastion = true
gateway_bastion_port   = 61000

# Expose Talos API for remote management
expose_talos_api = true

# -----------------------------------------------------------------------------
# Bootstrap Bastion
# -----------------------------------------------------------------------------
enable_bootstrap_bastion = true
bastion_instance_type    = "PRO2-XS"