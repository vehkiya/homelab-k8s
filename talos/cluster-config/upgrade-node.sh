source ./backup-node.sh

NODE="$1"
VERSION=$2
FACTORY_PARAMS="image-factory-parameters.yaml"
if [ $# -lt 2 ]; then
    echo 1>&2 "$0: not enough arguments. Required arguments are NODE and VERSION"
    exit 2
elif [ $# -gt 2 ]; then
  echo 1>&2 "$0: too many arguments"
  exit 2
fi

backup_machine_config "$NODE" || exit 1 # Exit if backup fails

echo "Preparing node upgrade for $NODE to version $VERSION using factory parameters $FACTORY_PARAMS"

ID=$(curl -s -X POST --data-binary @$FACTORY_PARAMS https://factory.talos.dev/schematics | jq -r '.id')
echo "Image ID is $ID"

printf "%s " "Press enter to proceed with upgrade"
read ans

echo "Starting upgrade now"
if talosctl upgrade --image "factory.talos.dev/installer/$ID:$VERSION" -n "$NODE"; then
    echo "Upgrade completed successfully for node $NODE to version $VERSION"
else
    echo "Error: Upgrade failed for node $NODE"
    exit 1
fi

exit 0
