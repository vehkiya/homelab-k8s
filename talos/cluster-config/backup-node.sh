backup_machine_config() {
    local node_name=$1
    local backup_dir="backup/history"
    local lastconfig_dir="backup"
    local base_filename="machineconfig-${node_name}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local talos_version=$(talosctl get version -n "$node_name" -o json | jq -r .spec.version)
    local backup_file="${backup_dir}/${base_filename}-${timestamp}-${talos_version}.yaml"
    local lastconfig_file="${lastconfig_dir}/${node_name}.yaml"

    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"
    mkdir -p "$lastconfig_dir"

    echo "Creating a machineconfig backup for node $node_name at $backup_file"
    local stderr_file
    stderr_file=$(mktemp)
    if talosctl -n "$node_name" get machineconfig -o json | jq -s -r '.[-1].spec' > "$backup_file" 2>"$stderr_file"; then
        echo "Backup complete: $backup_file"
        cp "$backup_file" "$lastconfig_file"
        echo "Updated last config: $lastconfig_file"
        if [ -s "$stderr_file" ]; then
            echo "talosctl output:"
            cat "$stderr_file"
        fi
        rm -f "$stderr_file"
        return 0 # Indicate success
    else
        # talosctl command failed. Check if it's a real error or just a warning.
        if grep -q -i "error" "$stderr_file"; then
            echo "Error: Failed to create backup for node $node_name"
            cat "$stderr_file"
            rm -f "$backup_file"
            rm -f "$stderr_file"
            return 1 # Indicate failure
        else
            echo "Backup complete (with warnings): $backup_file"
            cp "$backup_file" "$lastconfig_file"
            echo "Updated last config: $lastconfig_file"
            echo "talosctl output:"
            cat "$stderr_file"
            rm -f "$stderr_file"
            return 0 # Indicate success
        fi
    fi
}

backup_machine_config $1 || exit 1;
