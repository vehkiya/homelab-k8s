#!/usr/bin/env bash
# Upgrade one Talos node without the shutdown hanging on NFS.
#
# Talos' UnmountPodMounts runs open()+syncfs() on every leftover pod mount
# before its unmount timeouts start. On a hard NFS mount whose server is gone
# (e.g. a Longhorn share-manager stopped earlier in the same shutdown) that
# blocks forever and the node needs a power cycle. So: drain the node ourselves,
# NFS clients first, and refuse to upgrade until /proc/mounts has no NFS left.
#
# Usage: upgrade-node.sh <node-name> [installer-image]
#   installer-image defaults to `tofu output -raw installer_image`.
set -euo pipefail

NODE="${1:?usage: $0 <node-name> [installer-image]}"
IMAGE="${2:-$(tofu -chdir="$(dirname "$0")" output -raw installer_image)}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-10m}"
NFS_WAIT_SECONDS="${NFS_WAIT_SECONDS:-300}"

IP="$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
ROLE=worker
kubectl get node -l node-role.kubernetes.io/control-plane -o name | grep -x "node/$NODE" >/dev/null && ROLE=controlplane

log() { printf '\n[%s] %s\n' "$(date +%T)" "$*"; }
die() { log "ABORT: $*"; log "node $NODE is left cordoned; run 'kubectl uncordon $NODE' to back out"; exit 1; }

server_version() { talosctl -n "$IP" version | awk '/^Server:/ {s=1} s && /Tag:/ {print $2}'; }
nfs_mounts() { talosctl -n "$IP" read /proc/mounts | awk '$3 ~ /^nfs/ {print $1, $2}'; }

log "node=$NODE ($ROLE) ip=$IP running=$(server_version) image=$IMAGE"

log "preflight: all nodes Ready, none cordoned"
kubectl get nodes --no-headers | awk '$2 != "Ready" {bad=1; print} END {exit bad}' \
  || { echo "some node is not Ready (or already cordoned)"; exit 1; }

log "cordon"
kubectl cordon "$NODE"

log "drain 1/2: everything except Longhorn share/instance managers"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout="$DRAIN_TIMEOUT" \
  --pod-selector='longhorn.io/component notin (share-manager,instance-manager)' \
  || die "first drain did not finish"

log "waiting up to ${NFS_WAIT_SECONDS}s for all NFS mounts to go away"
deadline=$((SECONDS + NFS_WAIT_SECONDS))
while :; do
  left="$(nfs_mounts)"
  [ -z "$left" ] && break
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "$left"
    die "NFS mounts still present (orphaned pod dirs? see longhorn-csi-plugin logs for 'directory not empty')"
  fi
  sleep 10
done
echo "no NFS mounts"

log "drain 2/2: remaining pods (Longhorn PDBs release once volumes detach)"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout="$DRAIN_TIMEOUT" \
  || die "second drain did not finish"

va="$(kubectl get volumeattachments -o jsonpath="{range .items[?(@.spec.nodeName==\"$NODE\")]}{.spec.source.persistentVolumeName}{\"\n\"}{end}")"
[ -n "$va" ] && { echo "$va"; die "VolumeAttachments still on $NODE"; }
[ -n "$(nfs_mounts)" ] && die "NFS mount reappeared"

log "talosctl upgrade"
talosctl -n "$IP" upgrade --image "$IMAGE" --wait --timeout 30m

log "waiting for $NODE Ready"
kubectl wait --for=condition=Ready "node/$NODE" --timeout=15m
log "running $(server_version)"

log "uncordon"
kubectl uncordon "$NODE"

if [ "$ROLE" = controlplane ]; then
  log "etcd members"
  talosctl -n "$IP" etcd status
fi

log "Cilium check (LAB-19): every non-host endpoint on $NODE realizes namespaced rules"
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --field-selector "spec.nodeName=$NODE" --timeout=5m
CILIUM_POD="$(kubectl -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$NODE" -o name)"
sleep 30
kubectl -n kube-system exec "$CILIUM_POD" -c cilium-agent -- cilium-dbg endpoint list -o json | jq '
  [.[] | select((.status.identity.labels//[]) | any(test("^reserved:(host|health)")) | not)
       | ([.status.policy.realized.l4.ingress[]?, .status.policy.realized.l4.egress[]?
           | .["derived-from-rules"][]?[]?] | map(select(test("derived-from=(Cilium)?NetworkPolicy"))) | length > 0)]
  | {total: length, ok: ([.[] | select(.)] | length)}'

log "done: compare total vs ok above; if ok < total run the LAB-19 CNP re-import runbook"
