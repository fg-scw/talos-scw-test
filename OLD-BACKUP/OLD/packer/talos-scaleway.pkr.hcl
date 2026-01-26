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
  type      = string
  sensitive = true
  default   = env("SCW_DEFAULT_PROJECT_ID")
}

variable "zone" {
  type        = string
  description = "Scaleway zone"
  default     = "fr-par-2"
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version"
  default     = "v1.12.1"
}

variable "base_image" {
  type        = string
  description = "Base Scaleway image for build"
  default     = "ubuntu_jammy"
}

variable "commercial_type" {
  type        = string
  description = "Instance type for build"
  default     = "PRO2-XXS"
}

variable "volume_size" {
  type        = number
  description = "Root volume size in GB"
  default     = 10
}

variable "schematic_file" {
  type        = string
  description = "Schematic file path"
  default     = "provision/schematic-minimal.yaml"
}

variable "image_suffix" {
  type        = string
  description = "Image name suffix (-minimal, -gpu)"
  default     = "-minimal"
}

# =============================================================================
# Locals
# =============================================================================

locals {
  image_name    = "talos-scaleway-${var.talos_version}${var.image_suffix}"
  snapshot_name = "talos-snapshot-${var.talos_version}${var.image_suffix}"
}

# =============================================================================
# Source
# =============================================================================

source "scaleway" "talos" {
  access_key = var.scw_access_key
  secret_key = var.scw_secret_key
  project_id = var.scw_project_id
  zone       = var.zone

  image           = var.base_image
  commercial_type = var.commercial_type

  image_name    = local.image_name
  snapshot_name = local.snapshot_name

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
    trimprefix(var.image_suffix, "-"),
  ]
}

# =============================================================================
# Build
# =============================================================================

build {
  name = "talos-scaleway"

  source "scaleway.talos" {
    name = "talos"
  }

  # Wait for cloud-init
  provisioner "shell" {
    inline = [
      "echo '==> Waiting for cloud-init...'",
      "cloud-init status --wait || true",
    ]
  }

  # Upload schematic
  provisioner "file" {
    source      = var.schematic_file
    destination = "/tmp/schematic.yaml"
  }

  # Build Talos image
  provisioner "shell" {
    environment_vars = [
      "TALOS_VERSION=${var.talos_version}",
      "IMAGE_SUFFIX=${var.image_suffix}",
    ]

    expect_disconnect = true
    skip_clean        = true

    inline = [
      "set -e",
      "export DEBIAN_FRONTEND=noninteractive",
      
      "echo ''",
      "echo '╔═══════════════════════════════════════════════════════════════╗'",
      "echo '║     Building Talos Image: ${var.talos_version}${var.image_suffix}'",
      "echo '╚═══════════════════════════════════════════════════════════════╝'",
      "echo ''",
      
      "echo '==> Installing dependencies'",
      "apt-get update -qq",
      "apt-get install -y -qq curl wget jq zstd > /dev/null",
      
      "echo ''",
      "echo '==> Schematic content:'",
      "echo '---'",
      "cat /tmp/schematic.yaml",
      "echo '---'",
      "echo ''",
      
      "echo '==> Getting schematic ID from Talos Image Factory...'",
      "SCHEMATIC_RESPONSE=$(curl -fsSL -X POST --data-binary @/tmp/schematic.yaml https://factory.talos.dev/schematics)",
      "echo \"Factory response: $SCHEMATIC_RESPONSE\"",
      "SCHEMATIC_ID=$(echo \"$SCHEMATIC_RESPONSE\" | jq -r '.id')",
      
      "if [ -z \"$SCHEMATIC_ID\" ] || [ \"$SCHEMATIC_ID\" = \"null\" ]; then",
      "  echo 'ERROR: Failed to get schematic ID'",
      "  exit 1",
      "fi",
      
      "echo ''",
      "echo '╔═══════════════════════════════════════════════════════════════╗'",
      "echo \"║  Schematic ID: $SCHEMATIC_ID\"",
      "echo '╚═══════════════════════════════════════════════════════════════╝'",
      "echo ''",
      
      "echo '==> Downloading Talos image...'",
      "IMAGE_URL=\"https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/scaleway-amd64.raw.zst\"",
      "echo \"URL: $IMAGE_URL\"",
      "wget --progress=bar:force -O /tmp/talos.raw.zst \"$IMAGE_URL\"",
      
      "echo ''",
      "echo '==> Decompressing image...'",
      "zstd -d -f --rm /tmp/talos.raw.zst -o /tmp/talos.raw",
      "ls -lh /tmp/talos.raw",
      
      "echo ''",
      "echo '==> Detecting target disk...'",
      "TARGET_DISK=\"/dev/$(lsblk -dn -o NAME,TYPE | awk '$2==\"disk\"{print $1; exit}')\"",
      "echo \"Target: $TARGET_DISK\"",
      
      "echo ''",
      "echo '==> Writing Talos image to disk...'",
      "dd if=/dev/zero of=$TARGET_DISK bs=1M count=4 conv=fsync 2>/dev/null || true",
      "dd if=/tmp/talos.raw of=$TARGET_DISK bs=4M status=progress conv=fsync",
      
      "echo ''",
      "echo '╔═══════════════════════════════════════════════════════════════╗'",
      "echo '║  ✓ Talos image written successfully!'",
      "echo '║'",
      "echo \"║  Image: talos-scaleway-$TALOS_VERSION$IMAGE_SUFFIX\"",
      "echo \"║  Schematic: $SCHEMATIC_ID\"",
      "echo '╚═══════════════════════════════════════════════════════════════╝'",
      "echo ''",
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
