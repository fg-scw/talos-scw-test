# ============================================================================
# Outputs essentiels
# ============================================================================

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint (Load Balancer)"
  value       = "https://${local.k8s_api_endpoint}:6443"
}

output "kubernetes_api_ip" {
  description = "Load Balancer IP for Kubernetes API"
  value       = local.k8s_api_endpoint
}

output "talos_api_endpoint" {
  description = "Talos API endpoint (Load Balancer)"
  value       = var.expose_talos_api ? "https://${local.k8s_api_endpoint}:50000" : "N/A - Talos API not exposed"
}

# ============================================================================
# Node IPs
# ============================================================================

output "control_plane_ips" {
  description = "Private IPs of control plane nodes"
  value       = local.control_plane_ips
}

output "worker_ips" {
  description = "Private IPs of worker nodes"
  value       = local.worker_ips
}

# ============================================================================
# Network
# ============================================================================

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
  value       = scaleway_vpc_private_network.kubernetes.ipv4_subnet[0].subnet
}

output "public_gateway_ip" {
  description = "Public Gateway IP (NAT)"
  value       = scaleway_vpc_public_gateway_ip.main.address
}

# ============================================================================
# Bastion (Bootstrap)
# ============================================================================

output "bastion_ip" {
  description = "IP publique du bastion de bootstrap"
  value       = var.enable_bootstrap_bastion ? scaleway_instance_ip.bastion[0].address : null
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bootstrap bastion"
  value       = var.enable_bootstrap_bastion ? "ssh root@${scaleway_instance_ip.bastion[0].address}" : "Bootstrap bastion not enabled"
}

# ============================================================================
# Gateway Bastion
# ============================================================================

output "gateway_bastion_command" {
  description = "SSH command to connect via gateway bastion"
  value = var.enable_bastion_on_gateway ? (
    "ssh -J bastion@${scaleway_vpc_public_gateway_ip.main.address}:${var.bastion_ssh_port} root@<CONTROL_PLANE_IP>"
  ) : "Gateway bastion not enabled"
}

# ============================================================================
# Next Steps
# ============================================================================

output "next_steps" {
  description = "Next steps to deploy/manage Talos"
  value       = <<-EOT
  %{if var.enable_bootstrap_bastion~}
  
  ╔═══════════════════════════════════════════════════════════════╗
  ║     Infrastructure deployed with AUTOMATIC BOOTSTRAP!         ║
  ╚═══════════════════════════════════════════════════════════════╝
  
  🚀 Bootstrap automatique en cours sur le bastion!
  
  📊 Suivi du bootstrap:
  
     ${scaleway_instance_ip.bastion[0].address != null ? "ssh root@${scaleway_instance_ip.bastion[0].address} 'journalctl -u talos-bootstrap -f'" : "Bastion IP not available"}
  
  📝 Voir les logs:
  
     ${scaleway_instance_ip.bastion[0].address != null ? "ssh root@${scaleway_instance_ip.bastion[0].address} 'tail -f /var/log/talos-bootstrap.log'" : "Bastion IP not available"}
  
  ⏱️  Temps estimé: 8-10 minutes
  
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  
  Une fois le bootstrap terminé:
  
  1️⃣  Télécharger les configurations:
  
     # Kubeconfig
     scp root@${scaleway_instance_ip.bastion[0].address}:/root/talos-config/kubeconfig ~/.kube/${var.cluster_name}-config
     
     # Talosconfig
     scp root@${scaleway_instance_ip.bastion[0].address}:/root/talos-config/talosconfig ~/.talos/${var.cluster_name}-config
  
  2️⃣  Utiliser le cluster:
  
     export KUBECONFIG=~/.kube/${var.cluster_name}-config
     kubectl get nodes
     kubectl get pods -A
  
  3️⃣  (Optionnel) Détruire le bastion après bootstrap:
  
     cd terraform && terraform destroy -target=scaleway_instance_server.bastion[0]
  
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  
  📋 Cluster Info:
     Nom: ${var.cluster_name}
     API: https://${local.k8s_api_endpoint}:6443
     Control Planes: ${join(", ", local.control_plane_ips)}
     Workers: ${join(", ", local.worker_ips)}
  
  📚 Documentation: https://www.talos.dev/
  
  %{else~}
  
  ╔═════════════════════════════════════════════════════════╗
  ║        Infrastructure deployed successfully!            ║
  ╚═════════════════════════════════════════════════════════╝
  
  📋 Next steps:
  
  1️⃣  Generate Talos configurations:
     
     talosctl gen config ${var.cluster_name} https://${local.k8s_api_endpoint}:6443 \
       --output-dir _out \
       --with-docs=false \
       --with-examples=false
  
  2️⃣  Apply Cilium patch (disable kube-proxy):
     
     talosctl --talosconfig _out/talosconfig machineconfig patch \
       _out/controlplane.yaml \
       --patch @../cilium-patch.yaml \
       -o _out/controlplane-patched.yaml
  
  3️⃣  Apply configurations to control planes:
     
     %{for ip in local.control_plane_ips~}
     talosctl apply-config --insecure --nodes ${ip} --file _out/controlplane-patched.yaml
     %{endfor~}
  
  4️⃣  Apply configurations to workers:
     
     %{for ip in local.worker_ips~}
     talosctl apply-config --insecure --nodes ${ip} --file _out/worker.yaml
     %{endfor~}
  
  5️⃣  Bootstrap etcd (first control plane only):
     
     talosctl --talosconfig _out/talosconfig bootstrap --nodes ${length(local.control_plane_ips) > 0 ? local.control_plane_ips[0] : ""}
  
  6️⃣  Get kubeconfig:
     
     talosctl --talosconfig _out/talosconfig kubeconfig _out/kubeconfig \
       --nodes ${local.k8s_api_endpoint}
     
     export KUBECONFIG=$(pwd)/_out/kubeconfig
     kubectl get nodes
  
  7️⃣  Install Cilium:
     
     helm repo add cilium https://helm.cilium.io/
     helm repo update
     
     helm install cilium cilium/cilium \
       --namespace kube-system \
       --set ipam.mode=kubernetes \
       --set kubeProxyReplacement=true \
       --set k8sServiceHost=${local.k8s_api_endpoint} \
       --set k8sServicePort=6443
  
  8️⃣  Verify cluster:
     
     kubectl get nodes
     kubectl -n kube-system get pods
     cilium status --wait
  
  📚 Documentation: https://www.talos.dev/
  
  %{endif~}
  EOT
}

# ============================================================================
# Debug Info
# ============================================================================

output "debug_info" {
  description = "Debug information"
  value = {
    zone                   = var.zone
    cluster_name           = var.cluster_name
    control_plane_count    = var.control_plane_count
    worker_count           = var.worker_count
    lb_type                = var.load_balancer_type
    lb_is_public           = var.expose_k8s_api_publicly
    gateway_type           = var.public_gateway_type
    gateway_bastion        = var.enable_bastion_on_gateway
    bootstrap_bastion      = var.enable_bootstrap_bastion
  }
}

# ============================================================================
# JSON exports for scripts
# ============================================================================

output "control_plane_ips_json" {
  description = "Control plane IPs in JSON format"
  value       = jsonencode(local.control_plane_ips)
}

output "worker_ips_json" {
  description = "Worker IPs in JSON format"
  value       = jsonencode(local.worker_ips)
}
