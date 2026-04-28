#!/usr/bin/env bash

# upgrade-cluster.sh
# Orchestrates a Talos Linux cluster upgrade according to the LifecycleService plan.

# --- Configuration ---
SINGLE_NODE_UPGRADE_SCRIPT="./upgrade-node.sh"
DOMAIN=".kube.kerrlab.app"
# --- End Configuration ---

# Check for required dependencies
for cmd in talosctl kubectl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "🛑 Error: Required command '$cmd' is not installed or not in PATH."
        exit 1
    fi
done

# Argument Parsing
STAGE_FLAG=""
VERSION=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --stage)
            STAGE_FLAG="--stage"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--stage] <version>"
            exit 0
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            else
                echo "🛑 Error: Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "🛑 Error: No version specified."
    echo "Usage: $0 [--stage] <version>"
    exit 1
fi

echo "🚀 Starting Talos cluster upgrade to version: $VERSION"
if [ -n "$STAGE_FLAG" ]; then
    echo "⚠️  STAGING MODE ENABLED: Nodes will download and load new boot assets, but WILL NOT REBOOT."
fi
echo "----------------------------------------------------"

# Helper function to check version and ask to skip
should_skip_node() {
    local NODE=$1
    local TARGET_VERSION=$2
    local K8S_NODE="${NODE%%.*}"
    
    local OS_IMAGE=$(kubectl get node "$K8S_NODE" -o jsonpath='{.status.nodeInfo.osImage}' 2>/dev/null)
    local CURRENT_VERSION=$(echo "$OS_IMAGE" | grep -oP 'v\d+\.\d+\.\d+' 2>/dev/null)
    
    if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
        echo "⚠️  Node $NODE is already running version $CURRENT_VERSION."
        read -r -p "Do you want to skip upgrading this node? [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY]) 
                return 0 # return 0 for success/true (yes, skip)
                ;;
            *)
                return 1 # return 1 for false (no, don't skip)
                ;;
        esac
    fi
    return 1 # don't skip
}

echo "=== Phase 1: Node Discovery ==="
echo "Discovering nodes via kubectl..."
# We use Kubernetes labels to dynamically identify node roles
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane= -o jsonpath='{.items[*].metadata.name}')
WORKER_NODES=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}')

if [ -z "$CP_NODES" ]; then
    echo "⚠️  Error: Failed to discover any control-plane nodes. Are the kubectl labels correct?"
    exit 1
fi

read -ra CP_ARRAY_SHORT <<< "$CP_NODES"
read -ra WORKER_ARRAY_SHORT <<< "$WORKER_NODES"

# Append FQDN
CP_ARRAY=()
for n in "${CP_ARRAY_SHORT[@]}"; do
    CP_ARRAY+=("${n}${DOMAIN}")
done

WORKER_ARRAY=()
for n in "${WORKER_ARRAY_SHORT[@]}"; do
    WORKER_ARRAY+=("${n}${DOMAIN}")
done

echo "Detected Control-Plane Nodes (${#CP_ARRAY[@]}): ${CP_ARRAY[*]}"
echo "Detected Worker Nodes (${#WORKER_ARRAY[@]}): ${WORKER_ARRAY[*]}"

echo "=== Phase 2: Pre-flight Check ==="
echo "Verifying cluster health before starting..."
if ! talosctl --endpoints "${CP_ARRAY[0]}" --nodes "${CP_ARRAY[0]}" health --wait-timeout 30s; then
    echo "⚠️  Error: Cluster is not healthy. Aborting upgrade to ensure safety."
    exit 1
fi
echo "✅ Cluster is healthy."

printf "\nPress enter to begin the cluster upgrade..."
read -r ans

echo "=== Phase 3: Quorum Protection (Control Plane) ==="
for NODE in "${CP_ARRAY[@]}"; do
    echo "⬆️  Upgrading control-plane node: $NODE..."
    
    if should_skip_node "$NODE" "$VERSION"; then
        echo "⏭️  Skipping node $NODE."
        echo "----------------------------------------------------"
        continue
    fi
    
    # Execute the single-node upgrade script
    if "$SINGLE_NODE_UPGRADE_SCRIPT" $STAGE_FLAG "$NODE" "$VERSION"; then
        echo "✅ Successfully processed $NODE."
        
        # In full upgrade mode, wait for the cluster to regain health (etcd quorum & endpoints)
        if [ -z "$STAGE_FLAG" ]; then
            echo "Waiting for cluster health (etcd sync) to stabilize before proceeding to the next node..."
            # Wait up to 10 minutes for etcd and cluster health to return to normal
            if ! talosctl --endpoints "$NODE" --nodes "$NODE" health --wait-timeout 10m; then
                echo "🛑 Error: Cluster health check failed after upgrading $NODE. Halting entire cluster upgrade."
                exit 1
            fi
            echo "✅ Cluster health restored."
        fi
        echo "----------------------------------------------------"
    else
        echo "🛑 Error processing control-plane node $NODE. Halting entire cluster upgrade."
        exit 1
    fi
done

echo "=== Phase 4: Batching (Worker Nodes) ==="
for NODE in "${WORKER_ARRAY[@]}"; do
    echo "⬆️  Upgrading worker node: $NODE..."
    
    if should_skip_node "$NODE" "$VERSION"; then
        echo "⏭️  Skipping node $NODE."
        echo "----------------------------------------------------"
        continue
    fi
    
    # We upgrade workers one-by-one here, but this loop could be modified to background tasks 
    # for concurrent batching if desired in the future.
    if "$SINGLE_NODE_UPGRADE_SCRIPT" $STAGE_FLAG "$NODE" "$VERSION"; then
        echo "✅ Successfully processed worker $NODE."
        echo "----------------------------------------------------"
    else
        echo "🛑 Error processing worker node $NODE. Halting entire cluster upgrade."
        exit 1
    fi
done

echo "🎉 All nodes successfully processed for version $VERSION!"
if [ -n "$STAGE_FLAG" ]; then
    echo "⚠️  Staging complete. You must reboot the nodes manually or re-run without --stage to finalize the upgrade."
fi
exit 0
