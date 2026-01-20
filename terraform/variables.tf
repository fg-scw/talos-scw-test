# =============================================================================
# Scaleway Configuration
# =============================================================================

variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway availability zone"
  type        = string
  default     = "fr-par-2"
}

# =============================================================================
# Cluster Configuration
# =============================================================================

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "talos-k8s"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.cluster_name)) && length(var.cluster_name) <= 24
    error_message = "Cluster name must be lowercase alphanumeric with hyphens, max 24 chars."
  }
}

variable "environment" {
  description = "Environment (production, staging, dev)"
  type        = string
  default     = "production"
}

variable "talos_version" {
  description = "Talos Linux version"
  type        = string
  default     = "v1.12.1"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "private_network_cidr" {
  description = "CIDR for the Private Network"
  type        = string
  default     = "10.0.0.0/22"
}

# =============================================================================
# Control Plane Configuration
# =============================================================================

variable "control_plane_count" {
  description = "Number of control plane nodes (1, 3, or 5)"
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 3, 5], var.control_plane_count)
    error_message = "Control plane count must be 1, 3, or 5."
  }
}

variable "control_plane_instance_type" {
  description = "Instance type for control plane"
  type        = string
  default     = "PRO2-S"
}

variable "control_plane_disk_size" {
  description = "Root disk size (GB)"
  type        = number
  default     = 50
}

# =============================================================================
# GPU Worker Configuration
# =============================================================================

variable "gpu_worker_count" {
  description = "Number of GPU workers"
  type        = number
  default     = 1
}

variable "gpu_worker_instance_type" {
  description = "GPU instance type (H100-1-80G, H100-2-160G)"
  type        = string
  default     = "H100-1-80G"
}

variable "gpu_worker_disk_size" {
  description = "Root disk size (GB)"
  type        = number
  default     = 100
}

# =============================================================================
# CPU Worker Configuration
# =============================================================================

variable "cpu_worker_count" {
  description = "Number of CPU workers"
  type        = number
  default     = 3
}

variable "cpu_worker_instance_type" {
  description = "CPU worker instance type"
  type        = string
  default     = "PRO2-XXS"
}

variable "cpu_worker_disk_size" {
  description = "Root disk size (GB)"
  type        = number
  default     = 50
}

# =============================================================================
# GPU MIG Configuration
# =============================================================================

variable "enable_gpu_mig" {
  description = "Enable MIG (Multi-Instance GPU) Manager"
  type        = bool
  default     = false
}

variable "gpu_mig_profile" {
  description = "Initial MIG profile: all-disabled, all-1g.10gb, all-2g.20gb, all-3g.40gb, mixed-40-20"
  type        = string
  default     = "all-disabled"

  validation {
    condition     = contains(["all-disabled", "all-1g.10gb", "all-2g.20gb", "all-3g.40gb", "mixed-40-20"], var.gpu_mig_profile)
    error_message = "Invalid MIG profile."
  }
}

# =============================================================================
# Load Balancer Configuration
# =============================================================================

variable "load_balancer_type" {
  description = "Load Balancer type"
  type        = string
  default     = "LB-S"
}

variable "expose_k8s_api_publicly" {
  description = "Expose K8s API publicly"
  type        = bool
  default     = false
}

variable "expose_talos_api" {
  description = "Expose Talos API via LB"
  type        = bool
  default     = true
}

# =============================================================================
# Gateway Configuration
# =============================================================================

variable "public_gateway_type" {
  description = "Public Gateway type"
  type        = string
  default     = "VPC-GW-S"
}

variable "enable_gateway_bastion" {
  description = "Enable SSH bastion on Gateway"
  type        = bool
  default     = true
}

variable "gateway_bastion_port" {
  description = "SSH port for bastion"
  type        = number
  default     = 61000
}

# =============================================================================
# Bootstrap Bastion Configuration
# =============================================================================

variable "enable_bootstrap_bastion" {
  description = "Create bootstrap bastion instance"
  type        = bool
  default     = true
}

variable "bastion_instance_type" {
  description = "Bastion instance type"
  type        = string
  default     = "DEV1-S"
}

# =============================================================================
# Additional Tags
# =============================================================================

variable "additional_tags" {
  description = "Additional tags"
  type        = list(string)
  default     = []
}
