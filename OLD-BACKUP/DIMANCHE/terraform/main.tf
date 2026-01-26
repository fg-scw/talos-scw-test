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

  # ==========================================================================
  # MIG Profile Mappings for H100 80GB
  # ==========================================================================
  # Profile ID Reference:
  #   0  = 7g.80gb (full GPU in MIG mode)
  #   5  = 4g.40gb
  #   9  = 3g.40gb
  #   14 = 2g.20gb
  #   19 = 1g.10gb
  # ==========================================================================
  mig_profile_map = {
    "disabled" = {
      enabled        = false
      profile_config = ""
      instance_count = 1
      description    = "Full GPU, no MIG partitioning"
    }
    "all-1g.10gb" = {
      enabled        = true
      profile_config = "19,19,19,19,19,19,19"
      instance_count = 7
      description    = "7x 10GB instances (Whisper inference)"
    }
    "all-2g.20gb" = {
      enabled        = true
      profile_config = "14,14,14"
      instance_count = 3
      description    = "3x 20GB instances"
    }
    "all-3g.40gb" = {
      enabled        = true
      profile_config = "9,9"
      instance_count = 2
      description    = "2x 40GB instances"
    }
    "all-7g.80gb" = {
      enabled        = true
      profile_config = "0"
      instance_count = 1
      description    = "1x 80GB instance (MIG single)"
    }
    "mixed-4g-3g" = {
      enabled        = true
      profile_config = "5,9"
      instance_count = 2
      description    = "1x 4g.40gb + 1x 3g.40gb"
    }
  }

  mig_config       = local.mig_profile_map[var.gpu_mig_profile]
  mig_enabled      = var.enable_gpu_mig && local.mig_config.enabled
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

# Kubernetes API Backend
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

# Talos API Backend (optional)
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

  name  = "${var.cluster_name}-gpu-${count.index + 1}"
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

  name  = "${var.cluster_name}-cpu-${count.index + 1}"
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
# IPAM - Get Private IPs
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
      cluster_name        = var.cluster_name
      talos_version       = var.talos_version
      k8s_api_endpoint    = scaleway_lb_ip.main.ip_address
      control_plane_ips   = join(" ", local.control_plane_ips)
      gpu_worker_ips      = join(" ", local.gpu_worker_ips)
      cpu_worker_ips      = join(" ", local.cpu_worker_ips)
      control_plane_count = var.control_plane_count
      gpu_worker_count    = var.gpu_worker_count
      cpu_worker_count    = var.cpu_worker_count
      total_nodes         = var.control_plane_count + var.gpu_worker_count + var.cpu_worker_count
      mig_enabled         = local.mig_enabled ? "true" : "false"
      mig_profile         = var.gpu_mig_profile
      mig_profile_config  = local.mig_config.profile_config
      mig_instance_count  = local.mig_config.instance_count
    })
  }

  tags = concat(local.common_tags, ["role=bastion"])

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

output "cluster_info" {
  description = "Cluster information"
  value = {
    name              = var.cluster_name
    talos_version     = var.talos_version
    load_balancer_ip  = scaleway_lb_ip.main.ip_address
    public_gateway_ip = scaleway_vpc_public_gateway_ip.main.address
  }
}

output "node_ips" {
  description = "Node private IPs"
  value = {
    control_plane = local.control_plane_ips
    gpu_workers   = local.gpu_worker_ips
    cpu_workers   = local.cpu_worker_ips
  }
}

output "mig_config" {
  description = "MIG configuration"
  value = {
    enabled        = local.mig_enabled
    profile        = var.gpu_mig_profile
    description    = local.mig_config.description
    instance_count = local.mig_config.instance_count
  }
}

output "bastion_info" {
  description = "Bastion connection info"
  value = var.enable_bootstrap_bastion ? {
    private_ip  = data.scaleway_ipam_ip.bastion[0].address
    ssh_command = "ssh -J bastion@${scaleway_vpc_public_gateway_ip.main.address}:${var.gateway_bastion_port} root@${data.scaleway_ipam_ip.bastion[0].address}"
  } : null
}

output "kubeconfig_command" {
  description = "Command to download kubeconfig"
  value = var.enable_bootstrap_bastion ? "scp -o ProxyJump=bastion@${scaleway_vpc_public_gateway_ip.main.address}:${var.gateway_bastion_port} root@${data.scaleway_ipam_ip.bastion[0].address}:/root/talos-config/kubeconfig ~/.kube/${var.cluster_name}-config" : null
}
