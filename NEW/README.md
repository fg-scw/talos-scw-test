# Talos Kubernetes on Scaleway - NVIDIA H100 GPU + MIG

Production-ready Kubernetes cluster on Scaleway with Talos Linux, NVIDIA H100 GPU, and automated MIG configuration.

## Features

- Talos Linux v1.12.1 with NVIDIA drivers
- H100 PCIe 80GB with MIG support  
- Automated cluster bootstrap
- Cilium CNI
- NVIDIA Device Plugin (privileged, MIG_STRATEGY=single)

## Quick Start

```bash
# 1. Configure
cp .envrc.example .envrc
# Edit .envrc with Scaleway credentials
source .envrc

# 2. Initialize and build images (~10 min first time)
make init
make build-all

# 3. Configure MIG in terraform/terraform.tfvars
# enable_gpu_mig  = true
# gpu_mig_profile = "all-2g.20gb"

# 4. Deploy (~12 min)
make deploy
make status   # Follow bootstrap

# 5. Get kubeconfig
make download
export KUBECONFIG=~/.kube/talos-k8s-config
kubectl get nodes
```

## MIG Profiles (H100 PCIe)

| Profile | IDs | GPUs | VRAM |
|---------|-----|------|------|
| `all-disabled` | - | 1 | 80GB |
| `all-1g.10gb` | 19x7 | 7 | 10GB |
| `all-2g.20gb` | 14x3 | 3 | 20GB |
| `all-3g.40gb` | 9x2 | 2 | 40GB |
| `mixed-40-20` | 9,14,14 | 3 | Mixed |

## Verify GPU

```bash
# Check resources
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

# Test GPU
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","nodeSelector":{"nvidia.com/gpu.present":"true"},"resources":{"limits":{"nvidia.com/gpu":"1"}}}}' \
  -- nvidia-smi
```

## Manual MIG Reconfiguration

```bash
# Create privileged pod
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: mig-setup
  namespace: nvidia-device-plugin
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  nodeSelector:
    nvidia.com/gpu.present: "true"
  containers:
    - name: mig-setup
      image: nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
      resources:
        limits:
          nvidia.com/gpu: 1
EOF

# Wait for Running
kubectl -n nvidia-device-plugin get pod mig-setup -w

# Check/enable MIG
kubectl -n nvidia-device-plugin exec mig-setup -- nvidia-smi
kubectl -n nvidia-device-plugin exec mig-setup -- nvidia-smi -i 0 -mig 1
# If enabling MIG: talosctl -n <GPU_IP> reboot

# Delete existing and create new instances
kubectl -n nvidia-device-plugin exec mig-setup -- nvidia-smi mig -dgi
kubectl -n nvidia-device-plugin exec mig-setup -- nvidia-smi mig -cgi 14,14,14 -C

# Cleanup and restart
kubectl delete pod -n nvidia-device-plugin mig-setup
kubectl -n nvidia-device-plugin delete pod -l name=nvidia-device-plugin-ds

# Verify
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

## Commands

| Command | Description |
|---------|-------------|
| `make init` | Initialize Packer/Terraform |
| `make build-all` | Build Talos images |
| `make deploy` | Deploy infrastructure |
| `make status` | Bootstrap logs (follow) |
| `make logs` | Bootstrap logs (all) |
| `make ssh` | SSH to bastion |
| `make download` | Get kubeconfig |
| `make validate` | Check GPU resources |
| `make cleanup` | Destroy bastion only |
| `make destroy` | Destroy everything |

## Troubleshooting

### Bootstrap issues
```bash
make ssh
journalctl -u talos-bootstrap.service --no-pager
```

### 0 GPUs detected
```bash
kubectl -n nvidia-device-plugin logs -l name=nvidia-device-plugin-ds
# Device plugin must have privileged: true
```

### GPU node issues
```bash
talosctl -n <GPU_IP> get extensions | grep nvidia
talosctl -n <GPU_IP> read /proc/modules | grep nvidia
```

## Architecture

```
[Load Balancer :6443]
        |
   [CP-1,2,3] ── [GPU Worker] ── [CPU Workers]
                  H100 80GB
                  MIG 3x20GB
```
