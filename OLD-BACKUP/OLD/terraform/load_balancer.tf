# =============================================================================
# Load Balancer for Kubernetes API
# =============================================================================

resource "scaleway_lb_ip" "kubernetes" {
  zone = var.zone
}

resource "scaleway_lb" "kubernetes" {
  name    = "${var.cluster_name}-lb"
  ip_ids  = [scaleway_lb_ip.kubernetes.id]
  zone    = var.zone
  type    = var.load_balancer_type

  private_network {
    private_network_id = scaleway_vpc_private_network.kubernetes.id
  }

  tags = local.common_tags

  depends_on = [scaleway_vpc_gateway_network.kubernetes]
}

# =============================================================================
# Kubernetes API Backend
# =============================================================================

resource "scaleway_lb_backend" "k8s_api" {
  lb_id            = scaleway_lb.kubernetes.id
  name             = "k8s-api"
  forward_protocol = "tcp"
  forward_port     = 6443
  proxy_protocol   = "none"

  health_check_tcp {}
  health_check_timeout  = "5s"
  health_check_delay    = "10s"
  health_check_max_retries = 3

  server_ips = local.control_plane_ips
}

resource "scaleway_lb_frontend" "k8s_api" {
  lb_id        = scaleway_lb.kubernetes.id
  backend_id   = scaleway_lb_backend.k8s_api.id
  name         = "k8s-api"
  inbound_port = 6443
}

# =============================================================================
# Talos API Backend (Optional)
# =============================================================================

resource "scaleway_lb_backend" "talos_api" {
  count = var.expose_talos_api ? 1 : 0

  lb_id            = scaleway_lb.kubernetes.id
  name             = "talos-api"
  forward_protocol = "tcp"
  forward_port     = 50000
  proxy_protocol   = "none"

  health_check_tcp {}
  health_check_timeout  = "5s"
  health_check_delay    = "10s"
  health_check_max_retries = 3

  server_ips = local.control_plane_ips
}

resource "scaleway_lb_frontend" "talos_api" {
  count = var.expose_talos_api ? 1 : 0

  lb_id        = scaleway_lb.kubernetes.id
  backend_id   = scaleway_lb_backend.talos_api[0].id
  name         = "talos-api"
  inbound_port = 50000
}
