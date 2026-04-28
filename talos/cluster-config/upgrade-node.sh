#!/usr/bin/env bash
source ./backup-node.sh

FORCE_FLAG=""
STAGE_FLAG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)
            FORCE_FLAG="--force"
            shift
            ;;
        --stage)
            STAGE_FLAG="--stage"
            shift
            ;;
        *)
            if [ -z "$NODE" ]; then
                NODE="$1"
            elif [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo 1>&2 "Unknown argument: $1"
                exit 2
            fi
            shift
            ;;
    esac
done

if [ -z "$NODE" ] || [ -z "$VERSION" ]; then
    echo 1>&2 "$0: not enough arguments. Required arguments are NODE and VERSION"
    echo 1>&2 "Usage: $0 [--force] [--stage] <node> <version>"
    exit 2
fi

FACTORY_PARAMS="image-factory-parameters.yaml"

echo "=== Phase 1: Pre-Check ==="
echo "Checking connectivity to node $NODE..."
if ! CURRENT_VERSION=$(talosctl get version -n "$NODE" -o json 2>/dev/null | jq -r .spec.version); then
    echo "Error: Node $NODE is unreachable or talosctl is misconfigured."
    exit 1
fi

if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" == "null" ]; then
    echo "Error: Could not retrieve current version for node $NODE."
    exit 1
fi
echo "Node $NODE is currently running Talos version $CURRENT_VERSION"

echo "=== Phase 2: Backup ==="
backup_machine_config "$NODE" || exit 1 # Exit if backup fails

# Backup: etcd snapshot if controlplane
# The machine config was just backed up, we can read its type from the YAML using yq
# We filter out 'null' because the YAML may contain multiple documents
NODE_TYPE=$(yq -r '.machine.type' "backup/${NODE}.yaml" 2>/dev/null | grep -v null | head -n 1)
if [ "$NODE_TYPE" = "controlplane" ] || [ "$NODE_TYPE" = "init" ]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    SNAPSHOT_FILE="backup/history/etcd-${NODE}-${TIMESTAMP}.snapshot"
    echo "Node $NODE is a control-plane node. Taking etcd snapshot to $SNAPSHOT_FILE..."
    if ! talosctl -n "$NODE" etcd snapshot "$SNAPSHOT_FILE"; then
        echo "Warning: Failed to take etcd snapshot. Proceeding carefully..."
    else
        echo "etcd snapshot saved to $SNAPSHOT_FILE"
    fi
else
    echo "Node $NODE is a worker node. Skipping etcd snapshot."
fi

echo "=== Phase 3: Generate Image ==="
echo "Preparing node upgrade for $NODE to version $VERSION using factory parameters $FACTORY_PARAMS"

ID=$(curl -s -X POST --data-binary @$FACTORY_PARAMS https://factory.talos.dev/schematics | jq -r '.id')
if [ -z "$ID" ] || [ "$ID" == "null" ]; then
    echo "Error: Failed to get image ID from factory.talos.dev"
    exit 1
fi
echo "Image ID is $ID"

printf "%s " "Press enter to proceed with upgrade"
read ans

echo "=== Phase 4: Upgrade ==="
UPGRADE_CMD="talosctl upgrade --image \"factory.talos.dev/installer/$ID:$VERSION\" -n \"$NODE\" --wait --preserve --reboot-mode=default $FORCE_FLAG"

if [ -n "$STAGE_FLAG" ]; then
    echo "Staging mode selected. New boot assets will be loaded into memory, but reboot will be deferred."
    UPGRADE_CMD="talosctl upgrade --image \"factory.talos.dev/installer/$ID:$VERSION\" -n \"$NODE\" --stage $FORCE_FLAG"
fi

echo "Running: $UPGRADE_CMD"
if eval "$UPGRADE_CMD"; then
    echo "Upgrade command completed successfully for node $NODE."
else
    echo "Error: Upgrade failed for node $NODE"
    exit 1
fi

echo "=== Phase 5: Verify ==="
# Verify (skip if staging)
if [ -z "$STAGE_FLAG" ]; then
    echo "Waiting for node $NODE to return to Ready status in Kubernetes..."
    
    # Give it a moment to disconnect if it just rebooted
    sleep 15
    
    RETRY_COUNT=0
    MAX_RETRIES=24 # 24 * 10s = 4 minutes
    READY=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Extract the short hostname for kubectl, as Kubernetes node names often don't include the domain
        K8S_NODE="${NODE%%.*}"
        STATUS=$(kubectl get node "$K8S_NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$STATUS" = "True" ]; then
            echo "Node $NODE is Ready!"
            READY=true
            break
        fi
        echo "Waiting... (Current status: ${STATUS:-Unknown})"
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT+1))
    done
    
    if [ "$READY" = "false" ]; then
        echo "Error: Node $NODE did not reach Ready state within the expected time."
        exit 1
    fi
fi

echo "=== Upgrade Process Complete ==="
exit 0
