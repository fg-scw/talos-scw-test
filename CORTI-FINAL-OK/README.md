# Talos Kubernetes on Scaleway with NVIDIA H100 MIG

Production-ready Talos Kubernetes cluster with NVIDIA H100 GPU and MIG support.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Scaleway VPC (fr-par-2)                    │
│  ┌────────────┐                                                 │
│  │ Public GW  │◄── SSH Bastion (:61000)                         │
│  └─────┬──────┘                                                 │
│        │          ┌─────────────────────────────────────────┐   │
│  ┌─────┴──────┐   │       Private Network 10.0.0.0/24       │   │
│  │     LB     │   │  ┌─────┐ ┌─────┐ ┌─────┐  Control Plane │   │
│  │ :6443/:50k │   │  │ CP1 │ │ CP2 │ │ CP3 │                │   │
│  └─────┬──────┘   │  └─────┘ └─────┘ └─────┘                │   │
│        └──────────┤  ┌─────┐ ┌─────┐          CPU Workers   │   │
│                   │  │CPU1 │ │CPU2 │                        │   │
│                   │  └─────┘ └─────┘                        │   │
│                   │  ┌─────────────┐          GPU Worker    │   │
│                   │  │ GPU1 (H100) │  7x MIG 1g.10gb        │   │
│                   │  └─────────────┘                        │   │
│                   └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Critical Fixes (vs upstream)

| Issue | Broken | Fixed |
|-------|--------|-------|
| Device Plugin | v0.17.0 | **v0.14.5** |
| Strategy | cdi-annotations | **envvar** |
| Privileged pods | default namespace | **nvidia-gpu-stack** |
| Deployment order | device plugin with MIG | **device plugin AFTER MIG instances** |

> ⚠️ **DO NOT use device plugin v0.17.0** - it has Talos CDI/glibc compatibility issues

> ⚠️ **CRITICAL**: Device plugin must be deployed AFTER MIG instances are created, not before!

## Deployment Order (MIG)

```
1. Deploy gpu-stack.yaml     → namespace, NFD, labeler (NO device plugin)
2. Label GPU node            → nvidia.com/gpu.present=true
3. Enable MIG mode           → nvidia-smi -mig 1
4. Reboot GPU node           → required for MIG activation
5. Create MIG instances      → nvidia-smi mig -cgi 19,19,19,19,19,19,19 -C
6. Deploy device-plugin.yaml → NOW device plugin can start
```

The bootstrap script handles this automatically.

## Quick Start

### 1. Build Talos Images

```bash
chmod +x build-images.sh
./build-images.sh
```

### 2. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

### 3. Monitor Bootstrap (~15-20 min)

```bash
# Get SSH command
terraform output bastion_ssh

# Follow logs
ssh -J bastion@<GW_IP>:61000 root@<BASTION_IP>
journalctl -u talos-bootstrap.service -f
```

### 4. Verify

```bash
export KUBECONFIG=/root/talos-config/kubeconfig

# Check nodes
kubectl get nodes

# Check GPU resources (should show 7)
kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"

# Test GPU
kubectl run gpu-test -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}],"containers":[{"name":"test","image":"nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04","command":["nvidia-smi","-L"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}'
```

## MIG Profiles

| Profile | Instances | Memory | Use Case |
|---------|-----------|--------|----------|
| `disabled` | 1 | 80GB | Large models |
| `all-1g.10gb` | 7 | 10GB | Whisper, small inference |
| `all-2g.20gb` | 3 | 20GB | Medium models |
| `all-3g.40gb` | 2 | 40GB | Large inference |

Configure in `terraform.tfvars`:
```hcl
enable_gpu_mig  = true
gpu_mig_profile = "all-1g.10gb"
```

## Manual MIG Configuration

If MIG wasn't configured during bootstrap:

```bash
# 1. Enable MIG (requires reboot)
kubectl run mig-enable -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}],"containers":[{"name":"enable","image":"nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04","command":["bash","-c","nvidia-smi -pm 1 && nvidia-smi -mig 1"],"securityContext":{"privileged":true}}]}}'

# 2. Reboot GPU node
talosctl reboot -n <GPU_NODE_IP> -e <GPU_NODE_IP>

# 3. Wait ~3 min, then create MIG instances
kubectl run mig-config -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}],"containers":[{"name":"config","image":"nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04","command":["bash","-c","nvidia-smi mig -cgi 19,19,19,19,19,19,19 -C && nvidia-smi mig -lgi"],"securityContext":{"privileged":true}}]}}'

# 4. Restart device plugin
kubectl label node <GPU_NODE> nvidia.com/gpu.present=true --overwrite
kubectl -n nvidia-gpu-stack delete pod -l app=nvidia-device-plugin
```

## Troubleshooting

```bash
# Device plugin logs
kubectl -n nvidia-gpu-stack logs -l app=nvidia-device-plugin

# Check MIG status
kubectl run mig-check -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}]}}' \
  -- nvidia-smi -L
```

## Cleanup

```bash
cd terraform
terraform destroy
```
