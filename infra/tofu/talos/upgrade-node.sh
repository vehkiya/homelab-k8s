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
# Fails (instead of printing nothing) when talosctl can't read the node, so an
# API hiccup is never mistaken for "no NFS mounts".
nfs_mounts() {
  local mounts
  mounts="$(talosctl -n "$IP" read /proc/mounts)" || return 1
  awk '$3 ~ /^nfs/ {print $1, $2}' <<<"$mounts"
}
node_attachments() {
  kubectl get volumeattachments -o jsonpath="{range .items[?(@.spec.nodeName==\"$NODE\")]}{.spec.source.persistentVolumeName}{\"\n\"}{end}"
}

log "node=$NODE ($ROLE) ip=$IP running=$(server_version) image=$IMAGE"

log "preflight: all nodes Ready, none cordoned"
kubectl get nodes --no-headers | awk '$2 != "Ready" {bad=1; print} END {exit bad}' \
  || { echo "some node is not Ready (or already cordoned)"; exit 1; }

log "preflight: talosctl health (etcd quorum and members, control plane, nodes)"
talosctl -n "$IP" health --wait-timeout 3m || { echo "cluster not healthy, not touching $NODE"; exit 1; }

log "cordon"
kubectl cordon "$NODE"

# Longhorn share/instance managers stay: Talos stops them itself once nothing
# uses their volumes, and evicting instance-managers can block on their PDBs.
log "drain: everything except Longhorn share/instance managers"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout="$DRAIN_TIMEOUT" \
  --pod-selector='longhorn.io/component notin (share-manager,instance-manager)' \
  || die "drain did not finish"

log "waiting up to ${NFS_WAIT_SECONDS}s for NFS mounts and VolumeAttachments to go away"
deadline=$((SECONDS + NFS_WAIT_SECONDS))
while :; do
  nfs="$(nfs_mounts)" || die "could not read /proc/mounts on $NODE"
  va="$(node_attachments)"
  [ -z "$nfs" ] && [ -z "$va" ] && break
  if [ "$SECONDS" -ge "$deadline" ]; then
    printf 'NFS mounts:\n%s\nVolumeAttachments:\n%s\n' "$nfs" "$va"
    die "still mounted/attached (orphaned pod dirs? see longhorn-csi-plugin logs for 'directory not empty')"
  fi
  sleep 10
done
echo "no NFS mounts, no VolumeAttachments"

log "talosctl upgrade"
talosctl -n "$IP" upgrade --image "$IMAGE" --wait --timeout 30m

log "waiting for $NODE Ready"
kubectl wait --for=condition=Ready "node/$NODE" --timeout=15m
log "running $(server_version)"

# Before uncordon: only DaemonSet pods are on the node, so a LAB-19 policy
# failure can't break workloads yet.
log "Cilium check (LAB-19): every non-host endpoint on $NODE realizes namespaced rules"
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --field-selector "spec.nodeName=$NODE" --timeout=5m
CILIUM_POD="$(kubectl -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=$NODE" -o name)"
sleep 30
read -r total ok < <(kubectl -n kube-system exec "$CILIUM_POD" -c cilium-agent -- cilium-dbg endpoint list -o json | jq -r '
  [.[] | select((.status.identity.labels//[]) | any(test("^reserved:(host|health)")) | not)
       | ([.status.policy.realized.l4.ingress[]?, .status.policy.realized.l4.egress[]?
           | .["derived-from-rules"][]?[]?] | map(select(test("derived-from=(Cilium)?NetworkPolicy"))) | length > 0)]
  | "\(length) \([.[] | select(.)] | length)"') || true
[ -n "${ok:-}" ] || die "could not read Cilium endpoints from $CILIUM_POD"
echo "endpoints with namespaced rules: $ok/$total"
[ "$total" -gt 0 ] || echo "WARNING: no pod endpoints on $NODE yet, policy check inconclusive"
[ "$ok" -eq "$total" ] || die "endpoints missing namespaced rules: run the LAB-19 CNP re-import runbook, then uncordon"

log "uncordon"
kubectl uncordon "$NODE"

log "postflight: talosctl health"
talosctl -n "$IP" health --wait-timeout 10m

log "done"
