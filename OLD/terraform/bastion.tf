# =============================================================================
# Bootstrap Bastion Instance
# =============================================================================

data "scaleway_instance_image" "ubuntu" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  name         = "Ubuntu 22.04 Jammy Jellyfish"
  architecture = "x86_64"
  zone         = var.zone
  latest       = true
}

resource "scaleway_instance_ip" "bastion" {
  count = var.enable_bootstrap_bastion ? 1 : 0
  zone  = var.zone
  tags  = local.common_tags
}

resource "scaleway_instance_server" "bastion" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  name              = "${var.cluster_name}-bastion"
  type              = var.bastion_instance_type
  image             = data.scaleway_instance_image.ubuntu[0].id
  zone              = var.zone
  security_group_id = scaleway_instance_security_group.bastion[0].id
  ip_id             = scaleway_instance_ip.bastion[0].id

  root_volume {
    size_in_gb            = 20
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.kubernetes.id
  }

  user_data = {
    cloud-init = templatefile("${path.module}/templates/bootstrap-cloud-init.yaml", {
      cluster_name        = var.cluster_name
      talos_version       = var.talos_version
      k8s_api_endpoint    = local.k8s_api_endpoint
      control_plane_ips   = join(" ", local.control_plane_ips)
      gpu_worker_ips      = join(" ", local.gpu_worker_ips)
      cpu_worker_ips      = join(" ", local.cpu_worker_ips)
      control_plane_count = var.control_plane_count
      gpu_worker_count    = var.gpu_worker_count
      cpu_worker_count    = var.cpu_worker_count
      enable_gpu_mig      = var.enable_gpu_mig
      gpu_mig_profile     = var.gpu_mig_profile
    })
  }

  tags = concat(local.common_tags, [
    "role=bootstrap-bastion",
    "temporary=true",
  ])

  depends_on = [
    scaleway_vpc_gateway_network.kubernetes,
    scaleway_instance_server.control_plane,
    scaleway_instance_server.gpu_workers,
    scaleway_instance_server.cpu_workers,
  ]
}

# =============================================================================
# IPAM - Bastion Private IP
# =============================================================================

data "scaleway_ipam_ip" "bastion" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  mac_address = scaleway_instance_server.bastion[0].private_network[0].mac_address
  type        = "ipv4"
}
