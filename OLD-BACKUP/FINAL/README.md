# Talos Kubernetes on Scaleway - GPU Ready

Deploy a production-ready Talos Kubernetes cluster on Scaleway with NVIDIA H100 GPU support and automatic MIG (Multi-Instance GPU) configuration.

## Features

- **Automated Bootstrap**: Single `make all` command deploys entire cluster
- **GPU Support**: NVIDIA H100 with pre-loaded drivers via Talos system extensions
- **MIG Configuration**: Automatic MIG partitioning (7x 10GB, 3x 20GB, etc.)
- **Dynamic Scaling**: Add/remove GPU nodes without manual intervention
- **Persistence**: MIG configuration survives node reboots
- **Production Ready**: HA control plane, Cilium CNI, private networking

## Architecture

```
                                    Internet
                                        │
                    ┌───────────────────┼───────────────────┐
                    │          Public Gateway               │
                    │          (Bastion SSH)                │
                    └───────────────────┼───────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    │            Load Balancer              │
                    │         (K8s API :6443)               │
                    └───────────────────┼───────────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        │                        Private Network                         │
        │                         10.0.0.0/24                            │
        │                                                                │
        │   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐        │
        │   │   CP-1      │   │   CP-2      │   │   CP-3      │        │
        │   │  PRO2-S     │   │  PRO2-S     │   │  PRO2-S     │        │
        │   │  Talos      │   │  Talos      │   │  Talos      │        │
        │   └─────────────┘   └─────────────┘   └─────────────┘        │
        │                                                                │
        │   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐        │
        │   │  CPU-1      │   │  CPU-2      │   │  CPU-3      │        │
        │   │  PRO2-M     │   │  PRO2-M     │   │  PRO2-M     │        │
        │   │  Talos      │   │  Talos      │   │  Talos      │        │
        │   └─────────────┘   └─────────────┘   └─────────────┘        │
        │                                                                │
        │   ┌─────────────────────────────────────────────────┐        │
        │   │              GPU Worker                          │        │
        │   │              H100-1-80G                          │        │
        │   │              Talos + NVIDIA Extensions           │        │
        │   │              MIG: 7x 1g.10gb                      │        │
        │   └─────────────────────────────────────────────────┘        │
        │                                                                │
        └────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Scaleway account with API credentials
- Packer >= 1.9
- Terraform >= 1.6
- SSH key configured in Scaleway

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repo-url>
cd talos-scaleway-gpu

# Configure Scaleway credentials
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"

# Create terraform.tfvars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars as needed
```

### 2. Deploy

```bash
# Initialize, build images, and deploy
make all

# Follow bootstrap progress
make status
```

### 3. Access Cluster

```bash
# Download kubeconfig
make download

# Use the cluster
export KUBECONFIG=~/.kube/talos-k8s-config
kubectl get nodes

# Verify GPU resources
make validate
```

## MIG Configuration

### Available Profiles

| Profile | Memory | Instances | Use Case |
|---------|--------|-----------|----------|
| `disabled` | 80 GB | 1 | Full GPU |
| `all-1g.10gb` | 10 GB | 7 | Inference (Whisper, small models) |
| `all-2g.20gb` | 20 GB | 3 | Medium models |
| `all-3g.40gb` | 40 GB | 2 | Larger models |

### Configure MIG in terraform.tfvars

```hcl
enable_gpu_mig  = true
gpu_mig_profile = "all-1g.10gb"  # 7x 10GB instances
```

### Verify MIG Status

```bash
# Check MIG configuration
make mig-status

# Check GPU resources
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

## Project Structure

```
talos-scaleway-gpu/
├── Makefile                 # Main commands
├── terraform/
│   ├── main.tf             # Infrastructure definition
│   ├── variables.tf        # Variable definitions
│   ├── terraform.tfvars    # Your configuration
│   └── templates/
│       └── bootstrap-cloud-init.yaml  # Bootstrap script
├── packer/
│   ├── talos-scaleway.pkr.hcl        # Packer template
│   └── provision/
│       ├── schematic-minimal.yaml    # CP & CPU workers
│       └── schematic-gpu.yaml        # GPU workers (NVIDIA)
├── manifests/
│   └── gpu-stack-standalone.yaml     # GPU stack manifest
├── scripts/
│   └── gpu-stack.sh                  # GPU management script
└── docs/
    └── GPU-MIG-OPERATIONS.md         # GPU operations guide
```

## Commands Reference

### Deployment

| Command | Description |
|---------|-------------|
| `make init` | Initialize Packer and Terraform |
| `make build-all` | Build Talos images |
| `make deploy` | Deploy infrastructure |
| `make all` | Build + Deploy (full deployment) |

### Operations

| Command | Description |
|---------|-------------|
| `make status` | Follow bootstrap progress |
| `make logs` | View full bootstrap logs |
| `make ssh` | SSH to bastion |
| `make download` | Download kubeconfig |

### GPU

| Command | Description |
|---------|-------------|
| `make validate` | Show GPU resources |
| `make gpu-status` | Full GPU status |
| `make mig-status` | MIG configuration details |
| `make gpu-test` | Run GPU test pod |

### Cleanup

| Command | Description |
|---------|-------------|
| `make cleanup` | Remove bastion only |
| `make destroy` | Destroy all infrastructure |

## Dynamic GPU Scaling

The GPU stack supports adding/removing GPU nodes dynamically:

### Adding a GPU Node

1. Increase `gpu_worker_count` in terraform.tfvars
2. Run `terraform apply`
3. New node automatically joins and gets MIG configured

### How It Works

```
New GPU Node Joins
        ↓
NFD detects GPU (PCI 10de) → Labels node
        ↓
MIG Configurator DaemonSet → Creates MIG instances
        ↓
Device Plugin DaemonSet → Exposes GPU to K8s
        ↓
Node ready for GPU workloads
```

## Troubleshooting

### GPU Not Detected

```bash
# SSH to bastion and check extensions
make ssh
talosctl -n <GPU_IP> get extensions | grep nvidia
```

### MIG Instances Not Created

```bash
# Check MIG configurator logs
kubectl -n nvidia-gpu-stack logs -l app=mig-configurator -c configure-mig
```

### Pods Pending GPU

```bash
# Check available resources
kubectl describe node <GPU_NODE> | grep -A5 "Allocatable:"

# Restart device plugin
kubectl -n nvidia-gpu-stack delete pod -l app=nvidia-device-plugin
```

## Cost Estimation (Scaleway fr-par-2)

| Component | Type | Monthly Cost |
|-----------|------|--------------|
| 3x Control Plane | PRO2-S | ~€90 |
| 3x CPU Workers | PRO2-M | ~€180 |
| 1x GPU Worker | H100-1-80G | ~€2,500 |
| Load Balancer | LB-S | ~€10 |
| Public Gateway | VPC-GW-S | ~€20 |
| **Total** | | **~€2,800/month** |

## License

MIT
