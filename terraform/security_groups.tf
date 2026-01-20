# =============================================================================
# Security Group for Talos Nodes
# =============================================================================

resource "scaleway_instance_security_group" "talos" {
  name                    = "${var.cluster_name}-talos-sg"
  zone                    = var.zone
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  stateful                = true

  # Talos API
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 50000
    ip_range = var.private_network_cidr
  }

  # Talos Trustd
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 50001
    ip_range = var.private_network_cidr
  }

  # Kubernetes API
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 6443
    ip_range = var.private_network_cidr
  }

  # etcd
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 2379
    ip_range = var.private_network_cidr
  }

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 2380
    ip_range = var.private_network_cidr
  }

  # Kubelet
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 10250
    ip_range = var.private_network_cidr
  }

  # Cilium
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 4240
    ip_range = var.private_network_cidr
  }

  inbound_rule {
    action   = "accept"
    protocol = "UDP"
    port     = 8472
    ip_range = var.private_network_cidr
  }

  # ICMP
  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = var.private_network_cidr
  }

  tags = local.common_tags
}

# =============================================================================
# Security Group for Bastion
# =============================================================================

resource "scaleway_instance_security_group" "bastion" {
  count = var.enable_bootstrap_bastion ? 1 : 0

  name                    = "${var.cluster_name}-bastion-sg"
  zone                    = var.zone
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  stateful                = true

  # SSH
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
    ip_range = var.private_network_cidr
  }

  # ICMP
  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = var.private_network_cidr
  }

  tags = local.common_tags
}
