# =============================================================================
# Talos Kubernetes on Scaleway - Main Configuration
# =============================================================================
# GPU-Ready cluster with automatic MIG configuration
# =============================================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.49"
    }
  }
}

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
    "managed-by=terraform",
  ]

  # Collect IPs after creation via IPAM
  control_plane_ips = [for ip in data.scaleway_ipam_ip.control_plane : ip.address]
  gpu_worker_ips    = [for ip in data.scaleway_ipam_ip.gpu_worker : ip.address]
  cpu_worker_ips    = [for ip in data.scaleway_ipam_ip.cpu_worker : ip.address]

  # MIG profile mappings
  mig_profile_map = {
    "disabled"     = { id = "0", count = "1" }
    "all-disabled" = { id = "0", count = "1" }
    "all-1g.10gb"  = { id = "19", count = "7" }
    "all-2g.20gb"  = { id = "14", count = "3" }
    "all-3g.40gb"  = { id = "9", count = "2" }
    "mixed-40-20"  = { id = "9", count = "3" }
  }

  mig_profile_id       = lookup(local.mig_profile_map, var.gpu_mig_profile, { id = "0", count = "1" }).id
  mig_instance_count   = lookup(local.mig_profile_map, var.gpu_mig_profile, { id = "0", count = "1" }).count
  mig_enabled          = var.enable_gpu_mig && var.gpu_mig_profile != "disabled" && var.gpu_mig_profile != "all-disabled"
}

# =============================================================================
# Data Sources - Talos Images
# =============================================================================

data "scaleway_instance_image" "talos_minimal" {
  name         = "talos-scaleway-${var.talos_version}-minimal"
  architecture = "x86_64"
  zone         = var.zone
  latest       = true
}

data "scaleway_instance_image" "talos_gpu" {
  count = var.gpu_worker_count > 0 ? 1 : 0

  name         = "talos-scaleway-${var.talos_version}-gpu"
  architecture = "x86_64"
  zone         = var.zone
  latest       = true
}

# =============================================================================
# VPC & Network
# =============================================================================

resource "scaleway_vpc" "main" {
  name   = "${var.cluster_name}-vpc"
  region = var.region
  tags   = local.common_tags
}

resource "scaleway_vpc_private_network" "main" {
  name   = "${var.cluster_name}-pn"
  vpc_id = scaleway_vpc.main.id
  region = var.region

  ipv4_subnet {
    subnet = var.private_network_cidr
  }

  tags = local.common_tags
}

# =============================================================================
# Public Gateway
# =============================================================================

resource "scaleway_vpc_public_gateway_ip" "main" {
  zone = var.zone
  tags = local.common_tags
}

resource "scaleway_vpc_public_gateway" "main" {
  name            = "${var.cluster_name}-gw"
  type            = var.public_gateway_type
  zone            = var.zone
  ip_id           = scaleway_vpc_public_gateway_ip.main.id
  bastion_enabled = var.enable_gateway_bastion
  bastion_port    = var.gateway_bastion_port
  tags            = local.common_tags
}

resource "scaleway_vpc_gateway_network" "main" {
  gateway_id         = scaleway_vpc_public_gateway.main.id
  private_network_id = scaleway_vpc_private_network.main.id
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }

  depends_on = [scaleway_vpc_private_network.main]
}

# =============================================================================
# Load Balancer
# =============================================================================

resource "scaleway_lb_ip" "main" {
  zone = var.zone
}

resource "scaleway_lb" "main" {
  name   = "${var.cluster_name}-lb"
  ip_ids = [scaleway_lb_ip.main.id]
  zone   = var.zone
  type   = var.load_balancer_type
  tags   = local.common_tags

  private_network {
    private_network_id = scaleway_vpc_private_network.main.id
  }

  depends_on = [scaleway_vpc_gateway_network.main]
}

resource "scaleway_lb_backend" "k8s_api" {
  lb_id            = scaleway_lb.main.id
  name             = "k8s-api"
  forward_protocol = "tcp"
  forward_port     = 6443
  proxy_protocol   = "none"

  health_check_tcp {}
  health_check_timeout     = "5s"
  health_check_delay       = "10s"
  health_check_max_retries = 3

  server_ips = local.control_plane_ips
}

resource "scaleway_lb_frontend" "k8s_api" {
  lb_id        = scaleway_lb.main.id
  name         = "k8s-api"
  backend_id   = scaleway_lb_backend.k8s_api.id
  inbound_port = 6443
}

resource "scaleway_lb_backend" "talos_api" {
  count = var.expose_talos_api ? 1 : 0

  lb_id            = scaleway_lb.main.id
  name             = "talos-api"
  forward_protocol = "tcp"
  forward_port     = 50000
  proxy_protocol   = "none"

  health_check_tcp {}
  health_check_timeout     = "5s"
  health_check_delay       = "10s"
  health_check_max_retries = 3

  server_ips = local.control_plane_ips
}

resource "scaleway_lb_frontend" "talos_api" {
  count = var.expose_talos_api ? 1 : 0

  lb_id        = scaleway_lb.main.id
  name         = "talos-api"
  backend_id   = scaleway_lb_backend.talos_api[0].id
  inbound_port = 50000
}

# =============================================================================
# Control Plane Nodes
# =============================================================================

resource "scaleway_instance_server" "control_plane" {
  count = var.control_plane_count

  name  = "${var.cluster_name}-cp-${count.index + 1}"
  type  = var.control_plane_instance_type
  image = data.scaleway_instance_image.talos_minimal.id
  zone  = var.zone

  root_volume {
    size_in_gb            = var.control_plane_disk_size
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.main.id
  }

  tags = concat(local.common_tags, ["role=control-plane"])

  depends_on = [scaleway_vpc_gateway_network.main]
}

# =============================================================================
# GPU Workers
# =============================================================================

resource "scaleway_instance_server" "gpu_worker" {
  count = var.gpu_worker_count

  name  = "${var.cluster_name}-gpu-worker-${count.index + 1}"
  type  = var.gpu_worker_instance_type
  image = data.scaleway_instance_image.talos_gpu[0].id
  zone  = var.zone

  root_volume {
    size_in_gb            = var.gpu_worker_disk_size
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.main.id
  }

  tags = concat(local.common_tags, ["role=gpu-worker", "gpu=nvidia-h100"])

  depends_on = [scaleway_vpc_gateway_network.main]
}

# =============================================================================
# CPU Workers
# =============================================================================

resource "scaleway_instance_server" "cpu_worker" {
  count = var.cpu_worker_count

  name  = "${var.cluster_name}-cpu-worker-${count.index + 1}"
  type  = var.cpu_worker_instance_type
  image = data.scaleway_instance_image.talos_minimal.id
  zone  = var.zone

  root_volume {
    size_in_gb            = var.cpu_worker_disk_size
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.main.id
  }

  tags = concat(local.common_tags, ["role=cpu-worker"])

  depends_on = [scaleway_vpc_gateway_network.main]
}

# =============================================================================
# IPAM - Get Private IPs via MAC address
# =============================================================================

data "scaleway_ipam_ip" "control_plane" {
  count = var.control_plane_count

  mac_address = scaleway_instance_server.control_plane[count.index].private_network[0].mac_address
  type        = "ipv4"
}

data "scaleway_ipam_ip" "gpu_worker" {
  count = var.gpu_worker_count

  mac_address = scaleway_instance_server.gpu_worker[count.index].private_network[0].mac_address
  type        = "ipv4"
}

data "scaleway_ipam_ip" "cpu_worker" {
  count = var.cpu_worker_count

  mac_address = scaleway_instance_server.cpu_worker[count.index].private_network[0].mac_address
  type        = "ipv4"
}

# =============================================================================
# Bootstrap Bastion
# =============================================================================

data "scaleway_instance_image" "ubuntu" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  name         = "Ubuntu 22.04 Jammy Jellyfish"
  architecture = "x86_64"
  zone         = var.zone
  latest       = true
}

resource "scaleway_instance_server" "bastion" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  name  = "${var.cluster_name}-bastion"
  type  = var.bastion_instance_type
  image = data.scaleway_instance_image.ubuntu[0].id
  zone  = var.zone

  root_volume {
    size_in_gb            = 20
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.main.id
  }

  user_data = {
    cloud-init = templatefile("${path.module}/templates/bootstrap-cloud-init.yaml", {
      cluster_name           = var.cluster_name
      talos_version          = var.talos_version
      k8s_api_endpoint       = scaleway_lb_ip.main.ip_address
      control_plane_ips      = join(" ", local.control_plane_ips)
      gpu_worker_ips         = join(" ", local.gpu_worker_ips)
      cpu_worker_ips         = join(" ", local.cpu_worker_ips)
      control_plane_count    = var.control_plane_count
      gpu_worker_count       = var.gpu_worker_count
      cpu_worker_count       = var.cpu_worker_count
      enable_gpu_mig         = local.mig_enabled ? "true" : "false"
      gpu_mig_profile        = var.gpu_mig_profile
      gpu_mig_profile_id     = local.mig_profile_id
      gpu_mig_instance_count = local.mig_instance_count
      gpu_schematic_id       = var.gpu_schematic_id
    })
  }

  tags = concat(local.common_tags, ["role=bastion", "temporary=true"])

  depends_on = [
    scaleway_vpc_gateway_network.main,
    scaleway_instance_server.control_plane,
    scaleway_instance_server.gpu_worker,
    scaleway_instance_server.cpu_worker,
  ]
}

data "scaleway_ipam_ip" "bastion" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  mac_address = scaleway_instance_server.bastion[0].private_network[0].mac_address
  type        = "ipv4"
}

# =============================================================================
# Outputs
# =============================================================================

output "public_gateway_ip" {
  description = "Public Gateway IP"
  value       = scaleway_vpc_public_gateway_ip.main.address
}

output "load_balancer_ip" {
  description = "Load Balancer IP"
  value       = scaleway_lb_ip.main.ip_address
}

output "bastion_private_ip" {
  description = "Bastion private IP"
  value       = var.enable_bootstrap_bastion ? data.scaleway_ipam_ip.bastion[0].address : null
}

output "control_plane_ips" {
  description = "Control plane private IPs"
  value       = local.control_plane_ips
}

output "gpu_worker_ips" {
  description = "GPU worker private IPs"
  value       = local.gpu_worker_ips
}

output "cpu_worker_ips" {
  description = "CPU worker private IPs"
  value       = local.cpu_worker_ips
}

output "ssh_command" {
  description = "SSH command to bastion"
  value       = var.enable_bootstrap_bastion ? "ssh -J bastion@${scaleway_vpc_public_gateway_ip.main.address}:${var.gateway_bastion_port} root@${data.scaleway_ipam_ip.bastion[0].address}" : null
}

output "mig_config" {
  description = "MIG configuration"
  value = {
    enabled        = local.mig_enabled
    profile        = var.gpu_mig_profile
    profile_id     = local.mig_profile_id
    instance_count = local.mig_instance_count
    expected_gpus  = local.mig_enabled ? local.mig_instance_count : "1"
  }
}

output "kubectl_config_command" {
  description = "Command to get kubeconfig"
  value       = var.enable_bootstrap_bastion ? "scp -o ProxyJump=bastion@${scaleway_vpc_public_gateway_ip.main.address}:${var.gateway_bastion_port} root@${data.scaleway_ipam_ip.bastion[0].address}:/root/talos-config/kubeconfig ~/.kube/${var.cluster_name}-config" : null
}
