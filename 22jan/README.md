# Talos Kubernetes on Scaleway with GPU + MIG

Déploiement automatisé d'un cluster Talos sur Scaleway avec support GPU (H100) et MIG.

## Quick Start

```bash
# 1. Configuration
cp .envrc.example .envrc
# Éditer .envrc avec vos credentials Scaleway
source .envrc

cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Éditer terraform.tfvars selon vos besoins

# 2. Build images
make build-all

# 3. Deploy
make deploy

# 4. Follow bootstrap
make status

# 5. Get kubeconfig
make download
export KUBECONFIG=~/.kube/talos-k8s-config
```

## Commands

```bash
make help           # Toutes les commandes

# Build
make build-minimal  # Image pour CP + CPU workers
make build-gpu      # Image avec drivers NVIDIA
make build-all      # Les deux images

# Deploy
make deploy         # Déployer le cluster
make destroy        # Supprimer le cluster
make status         # Suivre les logs bootstrap

# Operations
make ssh            # SSH vers le bastion
make nodes          # Lister les nodes
make download       # Récupérer kubeconfig
make validate       # Vérifier les GPUs
```

## Configuration

### terraform.tfvars

```hcl
cluster_name      = "my-cluster"
gpu_worker_count  = 1
cpu_worker_count  = 0

# MIG (optionnel - peut être configuré après bootstrap)
enable_gpu_mig    = false
gpu_mig_profile   = "all-disabled"
```

### Variables GPU importantes

| Variable | Description | Default |
|----------|-------------|---------|
| `gpu_worker_count` | Nombre de workers GPU | 1 |
| `gpu_worker_instance_type` | Type instance | H100-1-80G |
| `enable_gpu_mig` | Activer MIG au bootstrap | false |
| `gpu_mig_profile` | Profil MIG | all-disabled |

## Configuration MIG

Voir le guide complet : **[docs/MIG-CONFIGURATION.md](docs/MIG-CONFIGURATION.md)**

### Profils MIG disponibles (H100 80GB)

| Profil | Instances | Mémoire | Use Case |
|--------|-----------|---------|----------|
| `all-disabled` | 1 | 80GB | GPU complet |
| `all-1g.10gb` | 7 | 10GB | Inférence légère |
| `all-2g.20gb` | 3 | 20GB | Inférence moyenne |
| `all-3g.40gb` | 2 | 40GB | Training petit modèle |

### Configuration MIG post-bootstrap (résumé)

```bash
# 1. SSH au bastion
make ssh

# 2. Créer pod privilegié
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: mig-config
  namespace: nvidia-device-plugin
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  nodeSelector:
    nvidia.com/gpu.present: "true"
  containers:
    - name: mig
      image: nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["sleep", "infinity"]
      securityContext:
        privileged: true
EOF

# 3. Activer MIG
kubectl -n nvidia-device-plugin exec -it mig-config -- nvidia-smi -mig 1

# 4. Rebooter le node GPU
GPU_IP=$(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.addresses[0].address}')
kubectl -n nvidia-device-plugin delete pod mig-config
talosctl -n $GPU_IP reboot

# 5. Après reboot, recréer le pod et créer les instances MIG
# Exemple: 3x 2g.20gb
kubectl -n nvidia-device-plugin exec -it mig-config -- nvidia-smi mig -cgi 14,14,14 -C

# 6. Redémarrer le device plugin
kubectl -n nvidia-device-plugin delete pod -l name=nvidia-device-plugin-ds
```

## Vérification GPU

```bash
# Vérifier les resources GPU
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

# Test nvidia-smi
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","resources":{"limits":{"nvidia.com/gpu":"1"}}}}' \
  -- nvidia-smi
```

## Structure

```
.
├── .envrc.example              # Template credentials
├── Makefile                    # Commandes Make
├── README.md
├── docs/
│   └── MIG-CONFIGURATION.md    # Guide MIG complet
├── packer/
│   ├── talos-scaleway.pkr.hcl
│   └── provision/
│       ├── schematic-minimal.yaml
│       └── schematic-gpu.yaml
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── terraform.tfvars.example
    └── templates/
        └── bootstrap-cloud-init.yaml
```

## Troubleshooting

### GPU non détecté

```bash
# Vérifier les extensions Talos
talosctl -n <GPU_IP> get extensions | grep nvidia

# Si vide, upgrade le node avec le bon schematic
SCHEMATIC_ID="22db031c3ec95035687f35472b6f75858473fc7856b40eb44697562db5d0f350"
talosctl -n <GPU_IP> upgrade --image "factory.talos.dev/installer/$SCHEMATIC_ID:v1.12.1" --preserve
```

### Pods GPU en Pending

```bash
# Vérifier les events
kubectl describe pod <pod-name>

# Vérifier le device plugin
kubectl -n nvidia-device-plugin logs -l name=nvidia-device-plugin-ds
```

### MIG non fonctionnel

Voir : [docs/MIG-CONFIGURATION.md#troubleshooting](docs/MIG-CONFIGURATION.md#troubleshooting)
