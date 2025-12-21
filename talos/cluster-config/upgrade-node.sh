#!/usr/bin/env bash
source ./backup-node.sh

FORCE_FLAG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)
            FORCE_FLAG="--force"
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
    exit 2
fi

FACTORY_PARAMS="image-factory-parameters.yaml"

backup_machine_config "$NODE" || exit 1 # Exit if backup fails

echo "Preparing node upgrade for $NODE to version $VERSION using factory parameters $FACTORY_PARAMS"

ID=$(curl -s -X POST --data-binary @$FACTORY_PARAMS https://factory.talos.dev/schematics | jq -r '.id')
echo "Image ID is $ID"

printf "%s " "Press enter to proceed with upgrade"
read ans

echo "Starting upgrade now"
if talosctl upgrade --image "factory.talos.dev/installer/$ID:$VERSION" -n "$NODE" $FORCE_FLAG; then
    echo "Upgrade completed successfully for node $NODE to version $VERSION"
else
    echo "Error: Upgrade failed for node $NODE"
    exit 1
fi

exit 0
