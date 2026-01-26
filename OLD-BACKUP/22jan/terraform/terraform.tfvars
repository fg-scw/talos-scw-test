# =============================================================================
# Talos Kubernetes on Scaleway - Configuration
# =============================================================================

# Cluster
cluster_name  = "talos-k8s"
region        = "fr-par"
zone          = "fr-par-2"
talos_version = "v1.12.1"

# Network
private_network_cidr   = "10.0.0.0/24"
public_gateway_type    = "VPC-GW-S"
enable_gateway_bastion = true
gateway_bastion_port   = 61000
load_balancer_type     = "LB-S"
expose_talos_api       = false

# Control Plane
control_plane_count         = 3
control_plane_instance_type = "PRO2-S"
control_plane_disk_size     = 20

# CPU Workers (optional)
cpu_worker_count         = 3
cpu_worker_instance_type = "PRO2-XS"
cpu_worker_disk_size     = 100

# GPU Workers
gpu_worker_count         = 1
gpu_worker_instance_type = "H100-1-80G"
gpu_worker_disk_size     = 100

# GPU MIG Configuration
# Set enable_gpu_mig = true to enable MIG during bootstrap
# Profiles: all-disabled, all-1g.10gb, all-2g.20gb, all-3g.40gb, mixed-40-20
#enable_gpu_mig  = false
#gpu_mig_profile = "all-disabled"

enable_gpu_mig  = true
gpu_mig_profile = "all-1g.10gb"

# GPU schematic ID (for auto-upgrade if extensions missing)
# This is the schematic with nvidia-open-gpu-kernel-modules-production
gpu_schematic_id = "22db031c3ec95035687f35472b6f75858473fc7856b40eb44697562db5d0f350"

# Bootstrap Bastion
enable_bootstrap_bastion = true
bastion_instance_type    = "DEV1-S"
