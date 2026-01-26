# =============================================================================
# Variables
# =============================================================================

variable "cluster_name" {
  type    = string
  default = "talos-k8s"
}

variable "region" {
  type    = string
  default = "fr-par"
}

variable "zone" {
  type    = string
  default = "fr-par-2"
}

variable "talos_version" {
  type    = string
  default = "v1.12.2"
}

variable "private_network_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

variable "public_gateway_type" {
  type    = string
  default = "VPC-GW-S"
}

variable "load_balancer_type" {
  type    = string
  default = "LB-S"
}

variable "control_plane_count" {
  type    = number
  default = 3
}

variable "control_plane_instance_type" {
  type    = string
  default = "PRO2-S"
}

variable "cpu_worker_count" {
  type    = number
  default = 2
}

variable "cpu_worker_instance_type" {
  type    = string
  default = "PRO2-M"
}

variable "gpu_worker_count" {
  type    = number
  default = 1
}

variable "gpu_worker_instance_type" {
  type    = string
  default = "H100-1-80G"
}

variable "enable_gpu_mig" {
  type    = bool
  default = true
}

variable "gpu_mig_profile" {
  description = "MIG profile: disabled, all-1g.10gb, all-2g.20gb, all-3g.40gb, all-7g.80gb"
  type        = string
  default     = "all-1g.10gb"

  validation {
    condition     = contains(["disabled", "all-1g.10gb", "all-2g.20gb", "all-3g.40gb", "all-7g.80gb"], var.gpu_mig_profile)
    error_message = "Invalid MIG profile."
  }
}

variable "enable_bootstrap_bastion" {
  type    = bool
  default = true
}
