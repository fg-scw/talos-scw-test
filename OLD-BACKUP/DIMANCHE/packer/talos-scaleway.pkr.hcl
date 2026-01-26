# =============================================================================
# Talos Image Builder for Scaleway - With Integrity Check
# =============================================================================
# Usage:
#   packer build -var "schematic_id=xxx" -var "image_suffix=-minimal" .
#   packer build -var "schematic_id=xxx" -var "image_suffix=-gpu" .
# =============================================================================

packer {
  required_plugins {
    scaleway = {
      source  = "github.com/scaleway/scaleway"
      version = "~> 1.3"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

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
  type    = string
  default = env("SCW_DEFAULT_PROJECT_ID")
}

variable "zone" {
  type    = string
  default = "fr-par-2"
}

variable "talos_version" {
  type    = string
  default = "v1.12.2"
}

variable "schematic_id" {
  type        = string
  description = "Talos Factory schematic ID (generated from schematic YAML)"
}

variable "image_suffix" {
  type        = string
  description = "Image name suffix: -minimal or -gpu"
  default     = "-minimal"
}

locals {
  image_name    = "talos-scaleway-${var.talos_version}${var.image_suffix}"
  snapshot_name = "talos-snapshot-${var.talos_version}${var.image_suffix}"
}

# =============================================================================
# Source Builder
# =============================================================================

source "scaleway" "talos" {
  access_key      = var.scw_access_key
  secret_key      = var.scw_secret_key
  project_id      = var.scw_project_id
  zone            = var.zone

  # Temporary build instance
  # Using PRO2-XXS (4 vCPU, 16GB RAM) with local SSD for reliable image creation
  image           = "ubuntu_jammy"
  commercial_type = "PRO2-XXS"

  image_name    = local.image_name
  snapshot_name = local.snapshot_name
  ssh_username  = "root"

  root_volume {
    size_in_gb  = 50
    volume_type = "l_ssd"  # Local SSD storage
  }

  tags = ["talos", "packer", var.talos_version, var.image_suffix]
}

# =============================================================================
# Build
# =============================================================================

build {
  source "scaleway.talos" {}

  # Wait for instance to be ready
  provisioner "shell" {
    inline = ["cloud-init status --wait || true"]
  }

  # Download, verify, and write Talos image
  provisioner "shell" {
    environment_vars = [
      "TALOS_VERSION=${var.talos_version}",
      "SCHEMATIC_ID=${var.schematic_id}",
    ]
    expect_disconnect = true
    skip_clean        = true

    inline = [
      "set -e",

      "echo '=== [1/6] Installing required tools ==='",
      "apt-get update -qq && apt-get install -y -qq curl zstd ca-certificates",

      "echo '=== [2/6] Detecting target disk ==='",
      "TARGET_DISK=/dev/$(lsblk -dn -o NAME,TYPE | awk '$2==\"disk\"{print $1; exit}')",
      "echo \"Target disk: $TARGET_DISK\"",

      "echo '=== [3/6] Downloading Talos image ==='",
      "echo \"Version: $TALOS_VERSION\"",
      "echo \"Schematic: $SCHEMATIC_ID\"",
      "DOWNLOAD_URL=\"https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/scaleway-amd64.raw.zst\"",
      "echo \"URL: $DOWNLOAD_URL\"",
      "",
      "# Download to temporary file with retry",
      "for i in 1 2 3; do",
      "  echo \"Download attempt $i...\"",
      "  curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 \"$DOWNLOAD_URL\" -o /tmp/talos.raw.zst && break",
      "  echo \"Attempt $i failed, retrying...\"",
      "  sleep 10",
      "done",
      "",
      "if [ ! -f /tmp/talos.raw.zst ]; then",
      "  echo 'ERROR: Failed to download image'",
      "  exit 1",
      "fi",
      "",
      "echo \"Downloaded size: $(ls -lh /tmp/talos.raw.zst | awk '{print $5}')\"",

      "echo '=== [4/6] Verifying image integrity ==='",
      "if ! zstd -t /tmp/talos.raw.zst; then",
      "  echo 'ERROR: Image integrity check failed - file is corrupt'",
      "  rm -f /tmp/talos.raw.zst",
      "  exit 1",
      "fi",
      "echo 'Integrity check PASSED'",

      "echo '=== [5/6] Decompressing image ==='",
      "zstd -d /tmp/talos.raw.zst -o /tmp/talos.raw --rm",
      "echo \"Decompressed size: $(ls -lh /tmp/talos.raw | awk '{print $5}')\"",

      "echo '=== [6/6] Writing image to disk ==='",
      "# oflag=direct bypasses kernel cache - writes go directly to disk",
      "# This ensures data is on persistent storage when dd completes",
      "dd if=/tmp/talos.raw of=$TARGET_DISK bs=4M status=progress oflag=direct",
      
      "echo '=== Image installation complete ==='"
    ]
    
    # Accept exit codes 0 (success) and 126 (command not found after disk overwrite)
    valid_exit_codes = [0, 126]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
