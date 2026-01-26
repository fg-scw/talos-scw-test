#!/bin/bash
# =============================================================================
# Talos Image Builder for Scaleway - VERSION FINALE CORRIGÉE (SBS & Block API)
# =============================================================================
# Utilise un disque secondaire SBS créé inline pour éviter les bugs de la CLI
# et l'API Block pour la gestion des snapshots.
# =============================================================================
set -euo pipefail

# Configuration
TALOS_VERSION="v1.12.2"
ZONE="fr-par-2"

# Schematic IDs
GPU_SCHEMATIC_ID="a7b13477c902b8d7b270c56251fbd924f8061ca0bc4b17d88090c8c4ca3901ff"
MINIMAL_SCHEMATIC_ID="ed0bd5f7a3cb1e30abd6330389ad748adc104f24c74336b0c786881e55372dea"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

# Build single image
build_image() {
    local schematic_id=$1
    local suffix=$2
    local image_name="talos-scaleway-${TALOS_VERSION}${suffix}"
    local instance_id=""
    local volume_id=""
    
    log "=============================================="
    log "Building: $image_name"
    log "=============================================="
    
    # Download
    log "Downloading Talos image..."
    curl -fL --progress-bar \
        "https://factory.talos.dev/image/$schematic_id/$TALOS_VERSION/scaleway-amd64.raw.xz" \
        -o "/tmp/talos${suffix}.raw.xz"
    
    # Decompress
    log "Decompressing..."
    xz -d -f "/tmp/talos${suffix}.raw.xz"
    ls -lh "/tmp/talos${suffix}.raw"
    
    # Calculate checksum
    log "Calculating checksum..."
    ORIG_SHA=$(shasum -a 256 "/tmp/talos${suffix}.raw" | awk '{print $1}')
    ORIG_SIZE=$(stat -f%z "/tmp/talos${suffix}.raw" 2>/dev/null || stat -c%s "/tmp/talos${suffix}.raw")
    log "SHA256: $ORIG_SHA"
    log "Size: $ORIG_SIZE bytes"
    
    # Delete old image if exists
    log "Checking for existing image..."
    OLD_IMAGE=$(scw instance image list zone=$ZONE -o json 2>/dev/null | \
        jq -r ".[] | select(.name==\"$image_name\") | .id" | head -1) || true
    if [ -n "$OLD_IMAGE" ] && [ "$OLD_IMAGE" != "null" ]; then
        log "Deleting old image: $OLD_IMAGE"
        scw instance image delete $OLD_IMAGE zone=$ZONE with-snapshots=true 2>/dev/null || true
        sleep 5
    fi
    
    # Delete old snapshots (Check both Instance and Block APIs for safety)
    log "Checking for old snapshots..."
    OLD_BLOCK_SNAPS=$(scw block snapshot list zone=$ZONE -o json 2>/dev/null | \
        jq -r ".[] | select(.name | contains(\"talos-snapshot-${TALOS_VERSION}${suffix}\")) | .id") || true
    for snap in $OLD_BLOCK_SNAPS; do
        if [ -n "$snap" ] && [ "$snap" != "null" ]; then
            log "Deleting old block snapshot: $snap"
            scw block snapshot delete $snap zone=$ZONE 2>/dev/null || true
        fi
    done
    
    # Create temporary build instance (SBS logic)
    log "Creating temporary build instance with secondary SBS volume (50G)..."
    INSTANCE_JSON=$(scw instance server create \
        type=PLAY2-MICRO \
        image=ubuntu_jammy \
        name="talos-builder${suffix}-$$" \
        zone=$ZONE \
        ip=new \
        root-volume=sbs:20G \
        additional-volumes.0=sbs:50G \
        -o json)
    
    instance_id=$(echo "$INSTANCE_JSON" | jq -r '.id')
    # Récupération de l'ID du volume SBS secondaire (index 1)
    volume_id=$(echo "$INSTANCE_JSON" | jq -r '.volumes."1".id')

    if [ -z "$instance_id" ] || [ "$instance_id" = "null" ] || [ -z "$volume_id" ] || [ "$volume_id" = "null" ]; then
        echo "$INSTANCE_JSON"
        error "Failed to create instance or secondary volume"
    fi
    log "Instance ID: $instance_id | Target Volume ID: $volume_id"
    
    # Wait for instance to be running
    log "Waiting for instance to start..."
    scw instance server wait $instance_id zone=$ZONE timeout=5m
    
    # Get public IP
    IP=$(scw instance server get $instance_id zone=$ZONE -o json | jq -r '.public_ip.address // .public_ips[0].address')
    if [ -z "$IP" ] || [ "$IP" = "null" ]; then
        error "Could not get public IP"
    fi
    log "Instance IP: $IP"
    
    # Wait for SSH
    log "Waiting for SSH..."
    for i in {1..24}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@$IP "echo SSH_OK" 2>/dev/null; then
            log "SSH connected!"
            break
        fi
        [ $i -eq 24 ] && error "SSH connection timeout"
        sleep 5
    done
    
    # Transfer and Write
    log "Copying image to instance..."
    scp -o StrictHostKeyChecking=no "/tmp/talos${suffix}.raw" root@$IP:/tmp/talos.raw
    
    log "Writing to secondary disk and verifying..."
    ssh -o StrictHostKeyChecking=no -T root@$IP << ENDSSH
set -e
# Detection du disque cible (50G)
TARGET_DISK=""
for disk in sdb vdb nvme1n1 sdc vdc; do
    if [ -b "/dev/\$disk" ]; then
        SIZE=\$(lsblk -bdn -o SIZE /dev/\$disk)
        if [ "\$SIZE" -gt 40000000000 ]; then
            TARGET_DISK="/dev/\$disk"
            break
        fi
    fi
done
[ -z "\$TARGET_DISK" ] && (echo "Target disk not found"; lsblk; exit 1)

echo "Writing to \$TARGET_DISK..."
dd if=/tmp/talos.raw of=\$TARGET_DISK bs=4M status=progress oflag=direct
sync && sleep 2

echo "Verifying checksum on disk..."
DISK_SHA=\$(head -c $ORIG_SIZE \$TARGET_DISK | sha256sum | awk '{print \$1}')
if [ "\$DISK_SHA" != "$ORIG_SHA" ]; then
    echo "Verification FAILED (Got: \$DISK_SHA, Expected: $ORIG_SHA)"
    exit 1
fi
echo "Verification PASSED"
rm -f /tmp/talos.raw
ENDSSH

    if [ $? -ne 0 ]; then
        scw instance server delete $instance_id zone=$ZONE with-ip=true with-block=true 2>/dev/null || true
        error "Image write/verification failed"
    fi
    
    # Stop instance
    log "Stopping instance..."
    scw instance server stop $instance_id zone=$ZONE
    scw instance server wait $instance_id zone=$ZONE
    
    # Note: Volume remains attached - Scaleway allows snapshots of volumes attached to stopped instances
    log "Creating snapshot from volume (still attached to stopped instance)..."
    SNAPSHOT_JSON=$(scw block snapshot create \
        name="talos-snapshot-${TALOS_VERSION}${suffix}" \
        volume-id=$volume_id \
        zone=$ZONE \
        -o json)
    
    SNAPSHOT_ID=$(echo "$SNAPSHOT_JSON" | jq -r '.id')
    if [ -z "$SNAPSHOT_ID" ] || [ "$SNAPSHOT_ID" = "null" ]; then
        echo "$SNAPSHOT_JSON"
        error "Failed to create block snapshot"
    fi
    
    log "Waiting for snapshot $SNAPSHOT_ID..."
    scw block snapshot wait $SNAPSHOT_ID zone=$ZONE timeout=30m
    
    # Create image (Instance API is compatible with Block Snapshots)
    log "Creating final instance image..."
    IMAGE_JSON=$(scw instance image create \
        name="$image_name" \
        snapshot-id=$SNAPSHOT_ID \
        arch=x86_64 \
        zone=$ZONE \
        -o json)
    
    IMAGE_ID=$(echo "$IMAGE_JSON" | jq -r '.image.id // .id')
    if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
        echo "$IMAGE_JSON"
        error "Failed to create image"
    fi
    
    # Cleanup - volume inline will be automatically deleted with the instance
    log "Cleaning up resources..."
    scw instance server delete $instance_id zone=$ZONE with-ip=true with-block=true 2>/dev/null || true
    scw instance server wait $instance_id zone=$ZONE timeout=5m 2>/dev/null || true
    rm -f "/tmp/talos${suffix}.raw"
    
    log "=============================================="
    log "SUCCESS: $image_name = $IMAGE_ID"
    log "=============================================="
    
    echo "$IMAGE_ID"
}

# Main
main() {
    echo "=============================================="
    echo "Talos Image Builder for Scaleway (SBS Edition)"
    echo "=============================================="
    
    # Check dependencies
    command -v scw >/dev/null || error "scw not found"
    command -v jq >/dev/null || error "jq not found"
    command -v xz >/dev/null || error "xz not found"
    
    # Build images
    log "########## GPU IMAGE ##########"
    GPU_IMAGE_ID=$(build_image "$GPU_SCHEMATIC_ID" "-gpu")
    
    log "########## MINIMAL IMAGE ##########"
    MINIMAL_IMAGE_ID=$(build_image "$MINIMAL_SCHEMATIC_ID" "-minimal")
    
    # Summary
    echo ""
    echo "=============================================="
    echo "BUILD COMPLETE"
    echo "=============================================="
    echo "GPU Image:     $GPU_IMAGE_ID"
    echo "Minimal Image: $MINIMAL_IMAGE_ID"
    echo "=============================================="
}

main "$@"