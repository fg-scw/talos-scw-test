packer {
  required_plugins {
    scaleway = {
      source  = "github.com/scaleway/scaleway"
      version = "~> 1.3"
    }
  }
}

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

variable "schematic_file" {
  type    = string
  default = "provision/schematic-minimal.yaml"
}

variable "image_suffix" {
  type    = string
  default = "-minimal"
}

locals {
  image_name    = "talos-scaleway-${var.talos_version}${var.image_suffix}"
  snapshot_name = "talos-snapshot-${var.talos_version}${var.image_suffix}"
}

source "scaleway" "talos" {
  access_key      = var.scw_access_key
  secret_key      = var.scw_secret_key
  project_id      = var.scw_project_id
  zone            = var.zone
  image           = "ubuntu_jammy"
  commercial_type = "PRO2-XXS"
  image_name      = local.image_name
  snapshot_name   = local.snapshot_name
  ssh_username    = "root"

  root_volume {
    size_in_gb = 10
    type       = "sbs_volume"
  }

  tags = ["talos", "packer", var.talos_version]
}

build {
  source "scaleway.talos" {}

  provisioner "shell" {
    inline = ["cloud-init status --wait || true"]
  }

  provisioner "file" {
    source      = var.schematic_file
    destination = "/tmp/schematic.yaml"
  }

  provisioner "shell" {
    environment_vars = [
      "TALOS_VERSION=${var.talos_version}",
    ]
    expect_disconnect = true
    skip_clean        = true

    inline = [
      "set -e",
      "apt-get update -qq && apt-get install -y -qq curl wget jq zstd > /dev/null",
      "SCHEMATIC_ID=$(curl -fsSL -X POST --data-binary @/tmp/schematic.yaml https://factory.talos.dev/schematics | jq -r '.id')",
      "echo \"Schematic ID: $SCHEMATIC_ID\"",
      "wget -q -O /tmp/talos.raw.zst https://factory.talos.dev/image/$SCHEMATIC_ID/$TALOS_VERSION/scaleway-amd64.raw.zst",
      "zstd -d -f --rm /tmp/talos.raw.zst -o /tmp/talos.raw",
      "TARGET_DISK=/dev/$(lsblk -dn -o NAME,TYPE | awk '$2==\"disk\"{print $1; exit}')",
      "dd if=/tmp/talos.raw of=$TARGET_DISK bs=4M status=progress conv=fsync",
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
