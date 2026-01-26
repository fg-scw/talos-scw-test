# =============================================================================
# Talos Images (Minimal for CP/CPU, GPU for GPU workers)
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
# Control Plane Nodes
# =============================================================================

resource "scaleway_instance_server" "control_plane" {
  count = var.control_plane_count

  name              = "${var.cluster_name}-cp-${count.index + 1}"
  type              = var.control_plane_instance_type
  image             = data.scaleway_instance_image.talos_minimal.id
  zone              = var.zone
  security_group_id = scaleway_instance_security_group.talos.id

  root_volume {
    size_in_gb            = var.control_plane_disk_size
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.kubernetes.id
  }

  tags = concat(local.common_tags, var.additional_tags, [
    "role=control-plane",
    "node-index=${count.index + 1}",
  ])

  depends_on = [scaleway_vpc_gateway_network.kubernetes]
}

# =============================================================================
# GPU Worker Nodes
# =============================================================================

resource "scaleway_instance_server" "gpu_workers" {
  count = var.gpu_worker_count

  name              = "${var.cluster_name}-gpu-worker-${count.index + 1}"
  type              = var.gpu_worker_instance_type
  image             = data.scaleway_instance_image.talos_gpu[0].id
  zone              = var.zone
  security_group_id = scaleway_instance_security_group.talos.id

  root_volume {
    size_in_gb            = var.gpu_worker_disk_size
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.kubernetes.id
  }

  tags = concat(local.common_tags, var.additional_tags, [
    "role=gpu-worker",
    "node-index=${count.index + 1}",
    "gpu=nvidia-h100",
  ])

  depends_on = [scaleway_vpc_gateway_network.kubernetes]
}

# =============================================================================
# CPU Worker Nodes
# =============================================================================

resource "scaleway_instance_server" "cpu_workers" {
  count = var.cpu_worker_count

  name              = "${var.cluster_name}-cpu-worker-${count.index + 1}"
  type              = var.cpu_worker_instance_type
  image             = data.scaleway_instance_image.talos_minimal.id
  zone              = var.zone
  security_group_id = scaleway_instance_security_group.talos.id

  root_volume {
    size_in_gb            = var.cpu_worker_disk_size
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  private_network {
    pn_id = scaleway_vpc_private_network.kubernetes.id
  }

  tags = concat(local.common_tags, var.additional_tags, [
    "role=cpu-worker",
    "node-index=${count.index + 1}",
  ])

  depends_on = [scaleway_vpc_gateway_network.kubernetes]
}

# =============================================================================
# IPAM - Get Private IPs
# =============================================================================

data "scaleway_ipam_ip" "control_plane" {
  count = var.control_plane_count

  mac_address = scaleway_instance_server.control_plane[count.index].private_network[0].mac_address
  type        = "ipv4"
}

data "scaleway_ipam_ip" "gpu_workers" {
  count = var.gpu_worker_count

  mac_address = scaleway_instance_server.gpu_workers[count.index].private_network[0].mac_address
  type        = "ipv4"
}

data "scaleway_ipam_ip" "cpu_workers" {
  count = var.cpu_worker_count

  mac_address = scaleway_instance_server.cpu_workers[count.index].private_network[0].mac_address
  type        = "ipv4"
}
