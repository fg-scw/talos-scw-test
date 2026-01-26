# =============================================================================
# Configuration
# =============================================================================

cluster_name  = "talos-k8s"
region        = "fr-par"
zone          = "fr-par-2"
talos_version = "v1.12.2"

# Control Plane (3 for HA)
control_plane_count         = 3
control_plane_instance_type = "PRO2-S"

# CPU Workers
cpu_worker_count         = 2
cpu_worker_instance_type = "PRO2-M"

# GPU Workers
gpu_worker_count         = 1
gpu_worker_instance_type = "H100-1-80G"

# MIG: all-1g.10gb = 7x 10GB instances (ideal for Whisper)
enable_gpu_mig  = true
gpu_mig_profile = "all-1g.10gb"

# Network
private_network_cidr = "10.0.0.0/24"
public_gateway_type  = "VPC-GW-S"
load_balancer_type   = "LB-S"

# Bootstrap
enable_bootstrap_bastion = true
