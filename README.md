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
# Generate your Schematic ID with Packer via the Factory or via Packer
https://factory.talos.dev/
```

```bash
#Modify your parameter in the script

# Configuration
TALOS_VERSION="v1.12.2"
ZONE="fr-par-2"

# Schematic IDs
GPU_SCHEMATIC_ID="a7b13477c902b8d7b270c56251fbd924f8061ca0bc4b17d88090c8c4ca3901ff"
MINIMAL_SCHEMATIC_ID="ed0bd5f7a3cb1e30abd6330389ad748adc104f24c74336b0c786881e55372dea"

```


```bash
# Build the Image CPU & GPU
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

```bash
root@talos-k8s-bastion:~# journalctl -u cloud-final.service -f
Jan 26 17:00:04 talos-k8s-bastion cloud-init[1825]: No user sessions are running outdated binaries.
Jan 26 17:00:04 talos-k8s-bastion cloud-init[1825]: No VM guests are running outdated hypervisor (qemu) binaries on this host.
Jan 26 17:00:05 talos-k8s-bastion cloud-init[1825]: [17:00:05] Installing tools...
Jan 26 17:00:14 talos-k8s-bastion cloud-init[1825]: [17:00:14] Waiting for Talos nodes...
Jan 26 17:00:14 talos-k8s-bastion cloud-init[1825]: [17:00:14] Generating Talos config...
Jan 26 17:00:14 talos-k8s-bastion cloud-init[1825]: generating PKI and tokens
Jan 26 17:00:15 talos-k8s-bastion cloud-init[1825]: Created /root/talos-config/controlplane.yaml
Jan 26 17:00:15 talos-k8s-bastion cloud-init[1825]: Created /root/talos-config/worker.yaml
Jan 26 17:00:15 talos-k8s-bastion cloud-init[1825]: Created /root/talos-config/talosconfig
Jan 26 17:00:15 talos-k8s-bastion cloud-init[1825]: [17:00:15] Applying configs...
Jan 26 17:02:16 talos-k8s-bastion cloud-init[1825]: [17:02:16] Bootstrapping etcd...
Jan 26 17:03:46 talos-k8s-bastion cloud-init[1825]: [17:03:46] Installing Cilium...
Jan 26 17:03:48 talos-k8s-bastion cloud-init[1825]: [17:03:48] Waiting for 6 nodes...
Jan 26 17:06:06 talos-k8s-bastion cloud-init[1825]: [17:06:06] Nodes ready: 6/6
Jan 26 17:06:06 talos-k8s-bastion cloud-init[1825]: [17:06:06] Deploying GPU stack...
Jan 26 17:07:07 talos-k8s-bastion cloud-init[1825]: [17:07:07] Configuring MIG...
Jan 26 17:07:27 talos-k8s-bastion cloud-init[1825]: [17:07:27] Enabling MIG on talos-k8s-gpu-1...
Jan 26 17:07:48 talos-k8s-bastion cloud-init[1825]: [17:07:48] Rebooting talos-k8s-gpu-1...
Jan 26 17:15:32 talos-k8s-bastion cloud-init[1825]: [17:15:32] Creating MIG instances on talos-k8s-gpu-1...
Jan 26 17:16:02 talos-k8s-bastion cloud-init[1825]: [17:16:02] Deploying device plugin...
Jan 26 17:16:32 talos-k8s-bastion cloud-init[1825]: [17:16:32] Bootstrap complete - GPU resources: 1
Jan 26 17:16:32 talos-k8s-bastion cloud-init[1825]: [17:16:32] KUBECONFIG: /root/talos-config/kubeconfig
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3318]: #############################################################
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3319]: -----BEGIN SSH HOST KEY FINGERPRINTS-----
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3321]: 256 SHA256:Bd8osS6B4iZa0E9XYgOb89Fx/Wy4GM6t6NlZbJqJKfk root@talos-k8s-bastion (ECDSA)
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3323]: 256 SHA256:ZofTN32FwCJWjhseq9HUq93ck692DsdRTx9qWwMil44 root@talos-k8s-bastion (ED25519)
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3325]: 3072 SHA256:CyuxVHPIgMtCfanumGBqv8Bda0TFgjP8BL5BmFjuCNc root@talos-k8s-bastion (RSA)
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3326]: -----END SSH HOST KEY FINGERPRINTS-----
Jan 26 17:16:33 talos-k8s-bastion cloud-init[3327]: #############################################################
Jan 26 17:16:33 talos-k8s-bastion cloud-init[1825]: Cloud-init v. 25.2-0ubuntu1~22.04.1 finished at Mon, 26 Jan 2026 17:16:33 +0000. Datasource DataSourceNoCloud [seed=/dev/sr0].  Up 1059.47 seconds
Jan 26 17:16:33 talos-k8s-bastion systemd[1]: Finished Cloud-init: Final Stage.
```

### 4. Verify

```bash
export KUBECONFIG=/root/talos-config/kubeconfig

# Check nodes
kubectl get nodes

# Check GPU resources (should show 1 if using H100-1-80G)
kubectl get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"

NAME              GPU
talos-k8s-cp-1    <none>
talos-k8s-cp-2    <none>
talos-k8s-cp-3    <none>
talos-k8s-cpu-1   <none>
talos-k8s-cpu-2   <none>
talos-k8s-gpu-1   1


# Test GPU
kubectl run gpu-test -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}],"containers":[{"name":"test","image":"nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04","command":["nvidia-smi","-L"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}'

GPU 0: NVIDIA H100 PCIe (UUID: GPU-e284f2f0-b7db-deb5-4d10-143420128721)

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

```bash
# 5. SHOW MIG PARTITION in namespace
kubectl run mig-config -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}],"containers":[{"name":"config","image":"nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04","command":["bash","-c","nvidia-smi mig -cgi 19,19,19,19,19,19,19 -C && nvidia-smi mig -lgi"],"securityContext":{"privileged":true}}]}}'

Successfully created GPU instance ID  9 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID  9 using profile MIG 1g.10gb (ID  0)
Successfully created GPU instance ID  7 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID  7 using profile MIG 1g.10gb (ID  0)
Successfully created GPU instance ID  8 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID  8 using profile MIG 1g.10gb (ID  0)
Successfully created GPU instance ID 11 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID 11 using profile MIG 1g.10gb (ID  0)
Successfully created GPU instance ID 12 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID 12 using profile MIG 1g.10gb (ID  0)
Successfully created GPU instance ID 13 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID 13 using profile MIG 1g.10gb (ID  0)
Successfully created GPU instance ID 14 on GPU  0 using profile MIG 1g.10gb (ID 19)
Successfully created compute instance ID  0 on GPU  0 GPU instance ID 14 using profile MIG 1g.10gb (ID  0)

+---------------------------------------------------------+
| GPU instances:                                          |
| GPU   Name               Profile  Instance   Placement  |
|                            ID       ID       Start:Size |
|=========================================================|
|   0  MIG 1g.10gb           19        7          4:1     |
+---------------------------------------------------------+
|   0  MIG 1g.10gb           19        8          5:1     |
+---------------------------------------------------------+
|   0  MIG 1g.10gb           19        9          6:1     |
+---------------------------------------------------------+
|   0  MIG 1g.10gb           19       11          0:1     |
+---------------------------------------------------------+
|   0  MIG 1g.10gb           19       12          1:1     |
+---------------------------------------------------------+
|   0  MIG 1g.10gb           19       13          2:1     |
+---------------------------------------------------------+
|   0  MIG 1g.10gb           19       14          3:1     |
+---------------------------------------------------------+

```

## Troubleshooting

```bash
# Device plugin logs
kubectl -n nvidia-gpu-stack logs -l app=nvidia-device-plugin

  "sharing": {
    "timeSlicing": {}
  }
}
I0126 17:16:11.599694       1 main.go:256] Retreiving plugins.
I0126 17:16:11.600274       1 factory.go:107] Detected NVML platform: found NVML library
I0126 17:16:11.600306       1 factory.go:107] Detected non-Tegra platform: /sys/devices/soc0/family file not found
I0126 17:16:11.785945       1 server.go:165] Starting GRPC server for 'nvidia.com/gpu'
I0126 17:16:11.786430       1 server.go:117] Starting to serve 'nvidia.com/gpu' on /var/lib/kubelet/device-plugins/nvidia-gpu.sock
I0126 17:16:11.787925       1 server.go:125] Registered device plugin for 'nvidia.com/gpu' with Kubelet
```

```bash
# Check MIG status
kubectl run mig-check -n nvidia-gpu-stack --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"operator":"Exists"}]}}' \
  -- nvidia-smi -L

GPU 0: NVIDIA H100 PCIe (UUID: GPU-e284f2f0-b7db-deb5-4d10-143420128721)
  MIG 1g.10gb     Device  0: (UUID: MIG-5068167e-8438-5874-bcde-57279823597e)
  MIG 1g.10gb     Device  1: (UUID: MIG-678fc2a6-04b2-5b9d-9757-d70ae2c5d8bc)
  MIG 1g.10gb     Device  2: (UUID: MIG-4874c758-673a-541a-847f-37122c4de0d8)
  MIG 1g.10gb     Device  3: (UUID: MIG-f6748545-64d3-5a5f-a580-ccb2e961d2fe)
  MIG 1g.10gb     Device  4: (UUID: MIG-1873c508-9fba-50ab-a0d5-0f16288a475e)
  MIG 1g.10gb     Device  5: (UUID: MIG-9d233510-f52e-54ed-8845-76859538753d)
  MIG 1g.10gb     Device  6: (UUID: MIG-dcb09d15-9f20-5d0c-8332-3f942ea44933)

```

## Cleanup

```bash
cd terraform
terraform destroy
```
