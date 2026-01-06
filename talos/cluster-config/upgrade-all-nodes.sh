#!/bin/bash

# Script to upgrade all Talos nodes sequentially

# --- Configuration ---
# List your Talos node hostnames or IP addresses here
NODES=("lab-1.kube.kerrlab.app" "lab-2.kube.kerrlab.app" "lab-3.kube.kerrlab.app", "worker-1.kube.kerrlab.app")

# Name of your script that upgrades a single node
# This script should accept two arguments: <node_host> <version>
SINGLE_NODE_UPGRADE_SCRIPT="./upgrade-node.sh"
# --- End Configuration ---

# Check if version argument is provided
if [ -z "$1" ]; then
  echo "🛑 Error: No version specified."
  echo "Usage: $0 <version>"
  exit 1
fi

VERSION="$1"

echo "🚀 Starting Talos cluster upgrade to version: $VERSION"
echo "----------------------------------------------------"

# Loop through each node and upgrade it
for NODE in "${NODES[@]}"; do
  echo "⬆️ Upgrading node: $NODE to version $VERSION..."
  if "$SINGLE_NODE_UPGRADE_SCRIPT" "$NODE" "$VERSION"; then
    echo "✅ Successfully upgraded $NODE."
    echo "----------------------------------------------------"
  else
    echo "⚠️ Error upgrading $NODE. Halting further upgrades."
    exit 1
  fi
done

echo "🎉 All nodes successfully upgraded to version $VERSION!"