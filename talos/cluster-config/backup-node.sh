#!/bin/bash

backup_machine_config() {
    local node_name=$1
    
    if [ -z "$node_name" ]; then
        echo "Usage: $0 <node_name>"
        return 1
    fi

    # Resolve script directory to ensure relative paths work correctly
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    local backup_dir="${script_dir}/backup/history"
    local lastconfig_dir="${script_dir}/backup"
    local base_filename="machineconfig-${node_name}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"
    mkdir -p "$lastconfig_dir"

    # Fetch Talos version
    local talos_version
    if ! talos_version=$(talosctl get version -n "$node_name" -o json 2>/dev/null | jq -r .spec.version); then
        talos_version="unknown"
    fi
    # Handle empty or null version
    if [ -z "$talos_version" ] || [ "$talos_version" == "null" ]; then
        talos_version="unknown"
    fi

    local backup_file="${backup_dir}/${base_filename}-${timestamp}-${talos_version}.yaml"
    local lastconfig_file="${lastconfig_dir}/${node_name}.yaml"

    echo "Creating a machineconfig backup for node $node_name at $backup_file"
    local stderr_file
    stderr_file=$(mktemp)

    # Enable pipefail to ensure we catch talosctl errors
    set -o pipefail

    # Run talosctl, capture stderr to file, pipe stdout to jq, write jq output to backup file
    if talosctl -n "$node_name" get machineconfig -o json 2>"$stderr_file" | jq -s -r '.[-1].spec' > "$backup_file"; then
        # Check if the result is "null" (jq's output for missing data) or empty
        if [ ! -s "$backup_file" ] || grep -q "^null$" "$backup_file"; then
            echo "Error: Backup content is empty or invalid."
            if [ -s "$stderr_file" ]; then
                echo "talosctl output:"
                cat "$stderr_file"
            fi
            rm -f "$backup_file"
            rm -f "$stderr_file"
            set +o pipefail
            return 1
        fi

        echo "Backup complete: $backup_file"
        cp "$backup_file" "$lastconfig_file"
        echo "Updated last config: $lastconfig_file"
        
        # Show warnings if any
        if [ -s "$stderr_file" ]; then
            echo "talosctl warnings:"
            cat "$stderr_file"
        fi
        
        rm -f "$stderr_file"
        set +o pipefail
        return 0
    else
        # talosctl or jq failed
        echo "Error: Failed to create backup for node $node_name"
        if [ -s "$stderr_file" ]; then
            cat "$stderr_file"
        fi
        rm -f "$backup_file"
        rm -f "$stderr_file"
        set +o pipefail
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    backup_machine_config "$@" || exit 1
fi
