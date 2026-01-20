packer {
  required_plugins {
    scaleway = {
      source  = "github.com/scaleway/scaleway"
      version = "~> 1.3"
    }
  }
}

# =========================
# Variables
# =========================

variable "scw_access_key" {
  type      = string
  sensitive = true
  default   = env("SCW_ACCESS_KEY")
}

variable "scw_secret_key" {
  type      = string
  sensitive = true
  default   = env("SCW_SECRET_KEY")
}

variable "scw_project_id" {
  type      = string
  sensitive = true
  default   = env("SCW_DEFAULT_PROJECT_ID")
}

variable "zone" {
  type        = string
  description = "Scaleway zone where the image will be created"
  default     = "fr-par-2"
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version to build"
  default     = "v1.12.1"
}

variable "base_image" {
  type        = string
  description = "Base Scaleway image for the build process"
  default     = "ubuntu_jammy"
}

variable "commercial_type" {
  type        = string
  description = "Instance type used during build"
  default     = "PRO2-XXS"
}

variable "volume_size" {
  type        = number
  description = "Root volume size in GB for the build instance"
  default     = 10
}

# =========================
# Locals
# =========================

locals {
  timestamp       = regex_replace(timestamp(), "[- TZ:]", "")
  image_full_name = "talos-scaleway-${var.talos_version}-${local.timestamp}"
  stable_image_name = "talos-scaleway-${var.talos_version}"
}

# =========================
# Source
# =========================

source "scaleway" "talos" {
  access_key = var.scw_access_key
  secret_key = var.scw_secret_key
  project_id = var.scw_project_id
  zone       = var.zone

  image           = var.base_image
  commercial_type = var.commercial_type

  image_name    = local.image_full_name
  snapshot_name = "talos-snapshot-${var.talos_version}-${local.timestamp}"

  communicator = "ssh"
  ssh_username = "root"

  root_volume {
    size_in_gb = var.volume_size
    type       = "sbs_volume"
  }

  tags = [
    "talos",
    "packer",
    var.talos_version,
  ]
}

# =========================
# Build
# =========================

build {
  name = "talos-scaleway-image"

  source "scaleway.talos" {
    name = "talos"
  }

  provisioner "shell" {
    inline = [
      "echo '==> Waiting for cloud-init...'",
      "cloud-init status --wait || echo 'cloud-init status returned non-zero (ignore)'",
    ]
  }

  provisioner "file" {
    source      = "provision/build-image.sh"
    destination = "/tmp/build-image.sh"
  }

  provisioner "file" {
    source      = "provision/schematic.yaml"
    destination = "/tmp/schematic.yaml"
  }

  provisioner "shell" {
    environment_vars = [
      "TALOS_VERSION=${var.talos_version}",
      "WORK_DIR=/tmp/talos-build",
      "SCHEMATIC_FILE=/tmp/schematic.yaml",
    ]

    expect_disconnect = true
    skip_clean        = true

    inline = [
      "set -e",
      "echo '==> Installing dependencies'",
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update",
      "apt-get install -y curl wget jq zstd",
      "",
      "echo '==> Executing build script'",
      "chmod +x /tmp/build-image.sh",
      "bash /tmp/build-image.sh",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
