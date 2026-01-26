# =============================================================================
# Network Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = scaleway_vpc.kubernetes.id
}

output "private_network_id" {
  description = "Private Network ID"
  value       = scaleway_vpc_private_network.kubernetes.id
}

output "private_network_cidr" {
  description = "Private Network CIDR"
  value       = var.private_network_cidr
}

output "public_gateway_ip" {
  description = "Public Gateway IP"
  value       = scaleway_vpc_public_gateway_ip.kubernetes.address
}

# =============================================================================
# Node Outputs
# =============================================================================

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

# =============================================================================
# Bastion Outputs
# =============================================================================

output "bastion_ip" {
  description = "Bastion public IP"
  value       = var.enable_bootstrap_bastion ? scaleway_instance_ip.bastion[0].address : null
}

output "bastion_private_ip" {
  description = "Bastion private IP"
  value       = var.enable_bootstrap_bastion ? data.scaleway_ipam_ip.bastion[0].address : null
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = var.enable_bootstrap_bastion ? "ssh -J bastion@${scaleway_vpc_public_gateway_ip.kubernetes.address}:${var.gateway_bastion_port} root@${data.scaleway_ipam_ip.bastion[0].address}" : null
}

# =============================================================================
# API Endpoints
# =============================================================================

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${local.k8s_api_endpoint}:6443"
}

output "talos_api_endpoint" {
  description = "Talos API endpoint"
  value       = "https://${local.k8s_api_endpoint}:50000"
}

# =============================================================================
# Image Info
# =============================================================================

output "talos_image_minimal_id" {
  description = "Talos minimal image ID"
  value       = data.scaleway_instance_image.talos_minimal.id
}

output "talos_image_gpu_id" {
  description = "Talos GPU image ID"
  value       = var.gpu_worker_count > 0 ? data.scaleway_instance_image.talos_gpu[0].id : null
}

# =============================================================================
# Next Steps
# =============================================================================

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT

╔═══════════════════════════════════════════════════════════════╗
║     Infrastructure deployed with AUTOMATIC BOOTSTRAP!         ║
╚═══════════════════════════════════════════════════════════════╝

🚀 Bootstrap is running automatically on the bastion.

📊 Follow progress:
   make status

🔑 SSH to bastion:
   make ssh

⏱️  Expected time: 8-10 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Once bootstrap is complete:

1️⃣  Download configurations:
   make download

2️⃣  Use the cluster:
   export KUBECONFIG=~/.kube/${var.cluster_name}-config
   kubectl get nodes
   kubectl get pods -A

3️⃣  (Optional) Destroy bastion:
   make cleanup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Cluster Info:
   Name: ${var.cluster_name}
   API: https://${local.k8s_api_endpoint}:6443
   Control Planes: ${join(", ", local.control_plane_ips)}
   GPU Workers: ${length(local.gpu_worker_ips) > 0 ? join(", ", local.gpu_worker_ips) : "none"}
   CPU Workers: ${length(local.cpu_worker_ips) > 0 ? join(", ", local.cpu_worker_ips) : "none"}

EOT
}
