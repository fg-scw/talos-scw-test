# =============================================================================
# Terraform Configuration
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.49"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "scaleway" {
  region = var.region
  zone   = var.zone
}

# =============================================================================
# Locals
# =============================================================================

locals {
  common_tags = [
    "cluster=${var.cluster_name}",
    "environment=${var.environment}",
    "talos-version=${var.talos_version}",
    "managed-by=terraform",
  ]

  # K8s API endpoint (first control plane private IP)
  k8s_api_endpoint = length(local.control_plane_ips) > 0 ? local.control_plane_ips[0] : "127.0.0.1"

  # Collect IPs after creation
  control_plane_ips = [for ip in data.scaleway_ipam_ip.control_plane : ip.address]
  gpu_worker_ips    = [for ip in data.scaleway_ipam_ip.gpu_workers : ip.address]
  cpu_worker_ips    = [for ip in data.scaleway_ipam_ip.cpu_workers : ip.address]
}
