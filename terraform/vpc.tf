# =============================================================================
# VPC and Private Network
# =============================================================================

resource "scaleway_vpc" "kubernetes" {
  name   = "${var.cluster_name}-vpc"
  region = var.region
  tags   = local.common_tags
}

resource "scaleway_vpc_private_network" "kubernetes" {
  name   = "${var.cluster_name}-pn"
  vpc_id = scaleway_vpc.kubernetes.id
  region = var.region

  ipv4_subnet {
    subnet = var.private_network_cidr
  }

  tags = local.common_tags
}

# =============================================================================
# Public Gateway (NAT + Bastion)
# =============================================================================

resource "scaleway_vpc_public_gateway_ip" "kubernetes" {
  zone = var.zone
  tags = local.common_tags
}

resource "scaleway_vpc_public_gateway" "kubernetes" {
  name            = "${var.cluster_name}-gw"
  type            = var.public_gateway_type
  zone            = var.zone
  ip_id           = scaleway_vpc_public_gateway_ip.kubernetes.id
  bastion_enabled = var.enable_gateway_bastion
  bastion_port    = var.gateway_bastion_port

  tags = local.common_tags
}

resource "scaleway_vpc_gateway_network" "kubernetes" {
  gateway_id         = scaleway_vpc_public_gateway.kubernetes.id
  private_network_id = scaleway_vpc_private_network.kubernetes.id
  enable_masquerade  = true

  ipam_config {
    push_default_route = true
  }

  depends_on = [scaleway_vpc_private_network.kubernetes]
}
