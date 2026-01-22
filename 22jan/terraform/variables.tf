# =============================================================================
# Talos Kubernetes on Scaleway - Variables
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-k8s"
}

variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
  default     = "fr-par-2"
}

variable "talos_version" {
  description = "Talos version"
  type        = string
  default     = "v1.12.1"
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "private_network_cidr" {
  description = "CIDR block for the private network"
  type        = string
  default     = "10.0.0.0/24"
}

variable "public_gateway_type" {
  description = "Public Gateway type"
  type        = string
  default     = "VPC-GW-S"
}

variable "enable_gateway_bastion" {
  description = "Enable bastion on public gateway"
  type        = bool
  default     = true
}

variable "gateway_bastion_port" {
  description = "Bastion SSH port"
  type        = number
  default     = 61000
}

variable "load_balancer_type" {
  description = "Load Balancer type"
  type        = string
  default     = "LB-S"
}

variable "expose_talos_api" {
  description = "Expose Talos API via load balancer"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Control Plane
# -----------------------------------------------------------------------------

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "control_plane_instance_type" {
  description = "Instance type for control plane"
  type        = string
  default     = "PRO2-S"
}

variable "control_plane_disk_size" {
  description = "Disk size for control plane (GB)"
  type        = number
  default     = 50
}

# -----------------------------------------------------------------------------
# CPU Workers
# -----------------------------------------------------------------------------

variable "cpu_worker_count" {
  description = "Number of CPU worker nodes"
  type        = number
  default     = 0
}

variable "cpu_worker_instance_type" {
  description = "Instance type for CPU workers"
  type        = string
  default     = "PRO2-M"
}

variable "cpu_worker_disk_size" {
  description = "Disk size for CPU workers (GB)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# GPU Workers
# -----------------------------------------------------------------------------

variable "gpu_worker_count" {
  description = "Number of GPU worker nodes"
  type        = number
  default     = 1
}

variable "gpu_worker_instance_type" {
  description = "Instance type for GPU workers"
  type        = string
  default     = "H100-1-80G"
}

variable "gpu_worker_disk_size" {
  description = "Disk size for GPU workers (GB)"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# GPU Configuration
# -----------------------------------------------------------------------------

variable "enable_gpu_mig" {
  description = "Enable MIG on GPU workers"
  type        = bool
  default     = false
}

variable "gpu_mig_profile" {
  description = "MIG profile: all-disabled, all-1g.10gb, all-2g.20gb, all-3g.40gb, mixed-40-20"
  type        = string
  default     = "all-disabled"
}

variable "gpu_schematic_id" {
  description = "Talos Factory schematic ID for GPU image (for auto-upgrade if extensions missing)"
  type        = string
  default     = "22db031c3ec95035687f35472b6f75858473fc7856b40eb44697562db5d0f350"
}

# -----------------------------------------------------------------------------
# Bootstrap Bastion
# -----------------------------------------------------------------------------

variable "enable_bootstrap_bastion" {
  description = "Create bootstrap bastion VM"
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Instance type for bastion"
  type        = string
  default     = "DEV1-S"
}
