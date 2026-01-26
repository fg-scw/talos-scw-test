#!/bin/bash
# =============================================================================
# GPU Stack Management Script for Talos Kubernetes
# =============================================================================
# Usage:
#   ./gpu-stack.sh install [MIG_PROFILE]    - Install GPU stack
#   ./gpu-stack.sh uninstall                - Remove GPU stack
#   ./gpu-stack.sh status                   - Show GPU status
#   ./gpu-stack.sh enable-mig               - Enable MIG mode (requires reboot)
#   ./gpu-stack.sh set-profile <PROFILE>    - Change MIG profile
#   ./gpu-stack.sh validate                 - Run validation tests
#   ./gpu-stack.sh logs                     - Show component logs
#
# MIG Profiles: all-1g.10gb, all-2g.20gb, all-3g.40gb, disabled
# =============================================================================

set -euo pipefail

NAMESPACE="nvidia-gpu-stack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*"; }
header() { echo -e "\n${CYAN}=== $* ===${NC}\n"; }

# =============================================================================
# Helper Functions
# =============================================================================

get_gpu_nodes() {
  kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""
}

get_gpu_node_ip() {
  kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.addresses[0].address}' 2>/dev/null || echo ""
}

wait_for_pods() {
  local label=$1
  local timeout=${2:-120}
  
  log "Waiting for pods with label $label..."
  kubectl -n "$NAMESPACE" wait --for=condition=Ready pod -l "$label" --timeout="${timeout}s" 2>/dev/null || true
}

# =============================================================================
# Install
# =============================================================================
cmd_install() {
  local profile="${1:-all-1g.10gb}"
  
  header "Installing GPU Stack"
  log "MIG Profile: $profile"
  
  # Cleanup existing GPU Operator if present
  if kubectl get namespace gpu-operator &>/dev/null; then
    warn "Found existing gpu-operator namespace, cleaning up..."
    helm uninstall gpu-operator -n gpu-operator 2>/dev/null || true
    kubectl delete namespace gpu-operator --wait=true 2>/dev/null || true
    sleep 5
  fi
  
  # Set MIG config based on profile
  case "$profile" in
    "disabled"|"all-disabled")
      MIG_ENABLED="false"
      MIG_PROFILE_ID="0"
      MIG_INSTANCE_COUNT="1"
      ;;
    "all-1g.10gb"|"1g.10gb")
      MIG_ENABLED="true"
      MIG_PROFILE_ID="19"
      MIG_INSTANCE_COUNT="7"
      ;;
    "all-2g.20gb"|"2g.20gb")
      MIG_ENABLED="true"
      MIG_PROFILE_ID="14"
      MIG_INSTANCE_COUNT="3"
      ;;
    "all-3g.40gb"|"3g.40gb")
      MIG_ENABLED="true"
      MIG_PROFILE_ID="9"
      MIG_INSTANCE_COUNT="2"
      ;;
    *)
      fail "Unknown profile: $profile"
      echo "Available profiles: disabled, all-1g.10gb, all-2g.20gb, all-3g.40gb"
      exit 1
      ;;
  esac
  
  # Apply the stack
  log "Applying GPU stack manifests..."
  kubectl apply -f "$SCRIPT_DIR/gpu-stack-standalone.yaml"
  
  # Update MIG config
  log "Configuring MIG profile..."
  kubectl -n "$NAMESPACE" patch configmap mig-config --type merge -p "{
    \"data\": {
      \"MIG_ENABLED\": \"$MIG_ENABLED\",
      \"MIG_PROFILE\": \"$profile\",
      \"MIG_PROFILE_ID\": \"$MIG_PROFILE_ID\",
      \"MIG_INSTANCE_COUNT\": \"$MIG_INSTANCE_COUNT\"
    }
  }" 2>/dev/null || true
  
  # Wait for components
  log "Waiting for NFD..."
  kubectl -n "$NAMESPACE" rollout status deployment/nfd-master --timeout=120s 2>/dev/null || true
  kubectl -n "$NAMESPACE" rollout status daemonset/nfd-worker --timeout=120s 2>/dev/null || true
  
  log "Waiting for GPU Labeler..."
  kubectl -n "$NAMESPACE" rollout status deployment/gpu-labeler --timeout=60s 2>/dev/null || true
  
  # Wait for GPU nodes to be labeled
  log "Waiting for GPU node detection (30s)..."
  sleep 30
  
  GPU_NODES=$(get_gpu_nodes)
  if [ -n "$GPU_NODES" ]; then
    ok "GPU nodes detected: $GPU_NODES"
    
    log "Waiting for MIG Configurator..."
    kubectl -n "$NAMESPACE" rollout status daemonset/mig-configurator --timeout=120s 2>/dev/null || true
    
    log "Waiting for Device Plugin..."
    kubectl -n "$NAMESPACE" rollout status daemonset/nvidia-device-plugin --timeout=120s 2>/dev/null || true
  else
    warn "No GPU nodes detected yet. They will be configured automatically when available."
  fi
  
  echo ""
  header "Installation Complete"
  cmd_status
  
  echo ""
  log "If MIG mode is not enabled, run: $0 enable-mig"
}

# =============================================================================
# Uninstall
# =============================================================================
cmd_uninstall() {
  header "Uninstalling GPU Stack"
  
  kubectl delete -f "$SCRIPT_DIR/gpu-stack-standalone.yaml" --ignore-not-found=true
  kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
  
  # Remove GPU labels from nodes
  for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
    kubectl label node "$node" nvidia.com/gpu.present- 2>/dev/null || true
  done
  
  ok "GPU Stack removed"
}

# =============================================================================
# Status
# =============================================================================
cmd_status() {
  header "GPU Stack Status"
  
  echo -e "${CYAN}Nodes:${NC}"
  kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,GPU:.status.allocatable.nvidia\.com/gpu,MIG-CAPABLE:.metadata.labels.nvidia\.com/mig\.capable'
  
  echo ""
  echo -e "${CYAN}GPU Resources per Node:${NC}"
  kubectl get nodes -l nvidia.com/gpu.present=true -o custom-columns='NODE:.metadata.name,GPUs:.status.allocatable.nvidia\.com/gpu' 2>/dev/null || echo "No GPU nodes found"
  
  echo ""
  echo -e "${CYAN}Pods in $NAMESPACE:${NC}"
  kubectl -n "$NAMESPACE" get pods -o wide 2>/dev/null || echo "Namespace not found"
  
  echo ""
  echo -e "${CYAN}MIG Configuration:${NC}"
  kubectl -n "$NAMESPACE" get configmap mig-config -o jsonpath='{.data}' 2>/dev/null | tr ',' '\n' || echo "ConfigMap not found"
  
  # Check MIG status on GPU node
  GPU_NODE=$(get_gpu_nodes | awk '{print $1}')
  if [ -n "$GPU_NODE" ]; then
    echo ""
    echo -e "${CYAN}MIG Status on $GPU_NODE:${NC}"
    kubectl -n "$NAMESPACE" logs -l app=mig-configurator -c configure-mig --tail=20 2>/dev/null | tail -10 || echo "No logs available"
  fi
}

# =============================================================================
# Enable MIG
# =============================================================================
cmd_enable_mig() {
  header "Enable MIG Mode"
  
  GPU_IP=$(get_gpu_node_ip)
  
  if [ -z "$GPU_IP" ]; then
    fail "No GPU node found"
    exit 1
  fi
  
  log "GPU node IP: $GPU_IP"
  
  # Create admin pod
  log "Creating admin pod..."
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: mig-admin
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  nodeSelector:
    nvidia.com/gpu.present: "true"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  containers:
    - name: cuda
      image: nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["sleep", "infinity"]
      securityContext:
        privileged: true
      resources:
        limits:
          nvidia.com/gpu: 1
EOF
  
  log "Waiting for admin pod..."
  kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/mig-admin --timeout=120s
  
  # Check current MIG status
  log "Current MIG status:"
  kubectl -n "$NAMESPACE" exec mig-admin -- nvidia-smi -i 0 --query-gpu=mig.mode.current,mig.mode.pending --format=csv
  
  # Enable MIG
  log "Enabling MIG mode..."
  kubectl -n "$NAMESPACE" exec mig-admin -- nvidia-smi -mig 1 || true
  
  echo ""
  ok "MIG mode enabled (pending)"
  echo ""
  warn "A reboot is required to activate MIG mode!"
  echo ""
  echo "Run the following commands:"
  echo "  1. Delete admin pod: kubectl -n $NAMESPACE delete pod mig-admin"
  echo "  2. Reboot GPU node:  talosctl -n $GPU_IP reboot"
  echo ""
  echo "After reboot, MIG instances will be created automatically."
  echo "Then restart device plugin: kubectl -n $NAMESPACE delete pod -l app=nvidia-device-plugin"
}

# =============================================================================
# Set Profile
# =============================================================================
cmd_set_profile() {
  local profile="$1"
  
  if [ -z "$profile" ]; then
    fail "Usage: $0 set-profile <PROFILE>"
    echo "Available profiles: disabled, all-1g.10gb, all-2g.20gb, all-3g.40gb"
    exit 1
  fi
  
  header "Setting MIG Profile: $profile"
  
  case "$profile" in
    "disabled"|"all-disabled")
      MIG_ENABLED="false"
      MIG_PROFILE_ID="0"
      MIG_INSTANCE_COUNT="1"
      ;;
    "all-1g.10gb"|"1g.10gb")
      MIG_ENABLED="true"
      MIG_PROFILE_ID="19"
      MIG_INSTANCE_COUNT="7"
      ;;
    "all-2g.20gb"|"2g.20gb")
      MIG_ENABLED="true"
      MIG_PROFILE_ID="14"
      MIG_INSTANCE_COUNT="3"
      ;;
    "all-3g.40gb"|"3g.40gb")
      MIG_ENABLED="true"
      MIG_PROFILE_ID="9"
      MIG_INSTANCE_COUNT="2"
      ;;
    *)
      fail "Unknown profile: $profile"
      exit 1
      ;;
  esac
  
  kubectl -n "$NAMESPACE" patch configmap mig-config --type merge -p "{
    \"data\": {
      \"MIG_ENABLED\": \"$MIG_ENABLED\",
      \"MIG_PROFILE\": \"$profile\",
      \"MIG_PROFILE_ID\": \"$MIG_PROFILE_ID\",
      \"MIG_INSTANCE_COUNT\": \"$MIG_INSTANCE_COUNT\"
    }
  }"
  
  ok "Profile updated to $profile"
  echo ""
  warn "To apply changes:"
  echo "  1. Delete MIG instances: kubectl -n $NAMESPACE exec mig-admin -- sh -c 'nvidia-smi mig -dci; nvidia-smi mig -dgi'"
  echo "  2. Restart MIG configurator: kubectl -n $NAMESPACE delete pod -l app=mig-configurator"
  echo "  3. Restart device plugin: kubectl -n $NAMESPACE delete pod -l app=nvidia-device-plugin"
}

# =============================================================================
# Validate
# =============================================================================
cmd_validate() {
  header "GPU Validation"
  
  GPU_COUNT=$(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
  
  if [ "$GPU_COUNT" = "0" ] || [ -z "$GPU_COUNT" ]; then
    fail "No GPU resources available"
    exit 1
  fi
  
  ok "Found $GPU_COUNT GPU(s)"
  
  log "Running GPU test pod..."
  
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-$$
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  nodeSelector:
    nvidia.com/gpu.present: "true"
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  containers:
    - name: cuda
      image: nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04
      command: ["/bin/bash", "-c"]
      args:
        - |
          echo "=== GPU Test ==="
          nvidia-smi -L
          echo ""
          nvidia-smi
          echo ""
          echo "=== Test Complete ==="
      resources:
        limits:
          nvidia.com/gpu: 1
EOF
  
  log "Waiting for test pod..."
  kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/gpu-test-$$" --timeout=120s 2>/dev/null || true
  
  sleep 5
  
  echo ""
  echo -e "${CYAN}Test Results:${NC}"
  kubectl -n "$NAMESPACE" logs "gpu-test-$$" 2>/dev/null || echo "Waiting for logs..."
  
  kubectl -n "$NAMESPACE" delete pod "gpu-test-$$" --ignore-not-found=true &>/dev/null
  
  ok "Validation complete"
}

# =============================================================================
# Logs
# =============================================================================
cmd_logs() {
  local component="${1:-all}"
  
  header "GPU Stack Logs"
  
  case "$component" in
    "mig"|"mig-configurator")
      echo -e "${CYAN}MIG Configurator:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=mig-configurator -c configure-mig --tail=50
      ;;
    "device-plugin"|"dp")
      echo -e "${CYAN}Device Plugin:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=nvidia-device-plugin --tail=50
      ;;
    "nfd")
      echo -e "${CYAN}NFD Master:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=nfd-master --tail=30
      echo ""
      echo -e "${CYAN}NFD Worker:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=nfd-worker --tail=30
      ;;
    "labeler")
      echo -e "${CYAN}GPU Labeler:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=gpu-labeler --tail=50
      ;;
    "all"|*)
      echo -e "${CYAN}MIG Configurator (init):${NC}"
      kubectl -n "$NAMESPACE" logs -l app=mig-configurator -c configure-mig --tail=20 2>/dev/null || echo "No logs"
      echo ""
      echo -e "${CYAN}Device Plugin:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=nvidia-device-plugin -c nvidia-device-plugin --tail=20 2>/dev/null || echo "No logs"
      echo ""
      echo -e "${CYAN}GPU Labeler:${NC}"
      kubectl -n "$NAMESPACE" logs -l app=gpu-labeler --tail=10 2>/dev/null || echo "No logs"
      ;;
  esac
}

# =============================================================================
# Main
# =============================================================================
case "${1:-help}" in
  install)
    cmd_install "${2:-all-1g.10gb}"
    ;;
  uninstall)
    cmd_uninstall
    ;;
  status)
    cmd_status
    ;;
  enable-mig)
    cmd_enable_mig
    ;;
  set-profile)
    cmd_set_profile "${2:-}"
    ;;
  validate)
    cmd_validate
    ;;
  logs)
    cmd_logs "${2:-all}"
    ;;
  help|--help|-h|*)
    echo "GPU Stack Management for Talos Kubernetes"
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  install [PROFILE]     Install GPU stack (default: all-1g.10gb)"
    echo "  uninstall             Remove GPU stack"
    echo "  status                Show GPU status"
    echo "  enable-mig            Enable MIG mode (requires reboot)"
    echo "  set-profile <PROFILE> Change MIG profile"
    echo "  validate              Run validation tests"
    echo "  logs [COMPONENT]      Show logs (all|mig|device-plugin|nfd|labeler)"
    echo ""
    echo "MIG Profiles:"
    echo "  disabled      - Full GPU, no MIG (1x 80GB)"
    echo "  all-1g.10gb   - 7x 10GB instances"
    echo "  all-2g.20gb   - 3x 20GB instances"
    echo "  all-3g.40gb   - 2x 40GB instances"
    ;;
esac
