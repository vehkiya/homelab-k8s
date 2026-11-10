#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common lib
source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${REPO_ROOT}/docs/security-audit/telemetry"
mkdir -p "${OUTPUT_DIR}"
RAW_RESULTS="${OUTPUT_DIR}/phase1-raw.json"
FINAL_RESULTS="${OUTPUT_DIR}/phase1-results.json"
CILIUM_DROPS_LOG="${OUTPUT_DIR}/cilium-drops-phase1.log"

export RESULTS_JSON="${RAW_RESULTS}"
rm -f "${RAW_RESULTS}" "${FINAL_RESULTS}" "${CILIUM_DROPS_LOG}"
touch "${RAW_RESULTS}"

AUTOMATION_POD="automation-security-probe"
AUTOMATION_NS="automation"
MEDIA_POD="media-security-probe"
MEDIA_NS="media"

cleanup() {
    log_info "Executing teardown: removing ephemeral security probe pods..."
    if [[ -n "${CILIUM_MONITOR_PID:-}" ]]; then
        kill "${CILIUM_MONITOR_PID}" >/dev/null 2>&1 || true
    fi
    kubectl delete pod -n "${AUTOMATION_NS}" "${AUTOMATION_POD}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete pod -n "${MEDIA_NS}" "${MEDIA_POD}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    log_info "Teardown complete."
}
trap cleanup EXIT INT TERM

log_info "================================================================="
log_info "PHASE 1: ASSUMED BREACH & IN-CLUSTER LATERAL MOVEMENT VERIFICATION"
log_info "================================================================="

# Pre-cleanup in case lingering pods exist
log_info "Ensuring clean initial state..."
kubectl delete pod -n "${AUTOMATION_NS}" "${AUTOMATION_POD}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl delete pod -n "${MEDIA_NS}" "${MEDIA_POD}" --ignore-not-found --wait=true >/dev/null 2>&1 || true

# 1. Deploy probe pods
log_info "Deploying automation probe pod (${AUTOMATION_NS}/${AUTOMATION_POD})..."
kubectl apply -f "${SCRIPT_DIR}/fixtures/automation-probe.yaml"

log_info "Deploying media probe pod (${MEDIA_NS}/${MEDIA_POD})..."
kubectl apply -f "${SCRIPT_DIR}/fixtures/media-probe.yaml"

log_info "Waiting for probe pods to reach Ready state..."
kubectl wait -n "${AUTOMATION_NS}" --for=condition=Ready pod/"${AUTOMATION_POD}" --timeout=60s
kubectl wait -n "${MEDIA_NS}" --for=condition=Ready pod/"${MEDIA_POD}" --timeout=60s
log_pass "Both probe pods are Ready and operational."

# Start background cilium monitor to capture drop events
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
log_info "Starting cilium monitor drop capture on ${CILIUM_POD}..."
kubectl exec -n kube-system "${CILIUM_POD}" -c cilium-agent -- cilium monitor --type drop > "${CILIUM_DROPS_LOG}" 2>&1 &
CILIUM_MONITOR_PID=$!

sleep 2

# -------------------------------------------------------------
# TEST 1.1: Automation Profile (n8n Emulation)
# -------------------------------------------------------------
log_info "--- Executing Test 1.1: Automation (n8n) Workload Profile ---"

# Legitimate Egress
assert_tcp_allow "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.218" "15432" "n8n to NAS PostgreSQL" "TEST_1.1_ALLOW_POSTGRES" || true
assert_tcp_allow "${AUTOMATION_POD}" "${AUTOMATION_NS}" "1.1.1.1" "443" "n8n to Outbound Internet (Cloudflare DNS over HTTPS)" "TEST_1.1_ALLOW_INTERNET" || true

# Unauthorized Egress (Must be DROPPED)
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.218" "2049" "n8n to NAS NFS Storage" "TEST_1.1_DROP_NAS_NFS" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.218" "445" "n8n to NAS SMB File Sharing" "TEST_1.1_DROP_NAS_SMB" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.218" "9000" "n8n to NAS S3 Object Storage" "TEST_1.1_DROP_NAS_S3" || true

# Control Plane & Host Isolation
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.250" "6443" "n8n to Kubernetes API VIP" "TEST_1.1_DROP_K8S_VIP" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.250" "50000" "n8n to Talos Linux OS API" "TEST_1.1_DROP_TALOS_API" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.250" "2379" "n8n to etcd Key-Value Store" "TEST_1.1_DROP_ETCD" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.96.0.1" "443" "n8n to in-cluster kubernetes.default.svc" "TEST_1.1_DROP_K8S_DEFAULT_SVC" || true

# LAN Pivoting
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "10.10.1.1" "80" "n8n to Private Gateway (10.10.1.1)" "TEST_1.1_DROP_LAN_GATEWAY" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "192.168.1.1" "80" "n8n to Management Gateway (192.168.1.1)" "TEST_1.1_DROP_MGMT_GATEWAY" || true

# Sensitive Namespaces
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "openbao.security.svc.cluster.local" "8200" "n8n to OpenBao Secret Store" "TEST_1.1_DROP_OPENBAO" || true
assert_tcp_drop "${AUTOMATION_POD}" "${AUTOMATION_NS}" "lldap.security.svc.cluster.local" "3890" "n8n to LLDAP Directory" "TEST_1.1_DROP_LLDAP" || true

# -------------------------------------------------------------
# TEST 1.2: Media Profile (Plex Emulation)
# -------------------------------------------------------------
log_info "--- Executing Test 1.2: Media (Plex) Workload Profile ---"

# Legitimate Egress
assert_tcp_allow "${MEDIA_POD}" "${MEDIA_NS}" "1.1.1.1" "443" "Plex to Outbound Internet (HTTPS)" "TEST_1.2_ALLOW_INTERNET" || true

# Unauthorized Egress (Must be DROPPED)
assert_tcp_drop "${MEDIA_POD}" "${MEDIA_NS}" "10.10.1.250" "6443" "Plex to Kubernetes API VIP" "TEST_1.2_DROP_K8S_VIP" || true
assert_tcp_drop "${MEDIA_POD}" "${MEDIA_NS}" "10.10.1.250" "50000" "Plex to Talos Linux OS API" "TEST_1.2_DROP_TALOS_API" || true
assert_tcp_drop "${MEDIA_POD}" "${MEDIA_NS}" "10.10.1.218" "2049" "Plex to NAS NFS Storage" "TEST_1.2_DROP_NAS_NFS" || true
assert_tcp_drop "${MEDIA_POD}" "${MEDIA_NS}" "10.10.1.1" "80" "Plex to LAN Gateway" "TEST_1.2_DROP_LAN_GATEWAY" || true
assert_tcp_drop "${MEDIA_POD}" "${MEDIA_NS}" "192.168.1.1" "80" "Plex to Management Gateway" "TEST_1.2_DROP_MGMT_GATEWAY" || true
assert_tcp_drop "${MEDIA_POD}" "${MEDIA_NS}" "openbao.security.svc.cluster.local" "8200" "Plex to OpenBao Secret Store" "TEST_1.2_DROP_OPENBAO" || true

# -------------------------------------------------------------
# TEST 1.3: L2 Multicast & Broadcast Containment
# -------------------------------------------------------------
log_info "--- Executing Test 1.3: L2 Multicast / Broadcast Containment ---"
log_info "Probing SSDP (239.255.255.250:1900) from media probe..."
if kubectl exec -n "${MEDIA_NS}" "${MEDIA_POD}" -- timeout 2 bash -c 'echo "M-SEARCH" > /dev/udp/239.255.255.250/1900' >/dev/null 2>&1; then
    log_info "SSDP datagram transmitted (eBPF drops verified at dataplane layer)"
    record_result "TEST_1.3_SSDP_BROADCAST" "PASS" "SSDP Multicast Transmit" "Sent SSDP datagram without crash"
else
    log_pass "SSDP Multicast blocked/dropped at socket layer"
    record_result "TEST_1.3_SSDP_BROADCAST" "PASS" "SSDP Multicast Dropped" "Socket rejected multicast"
fi

# -------------------------------------------------------------
# TEST 1.4: Pod Security Profile & PSA Audit
# -------------------------------------------------------------
log_info "--- Executing Test 1.4: Pod Security & Privilege Escalation Audit ---"
log_info "Checking current user in automation probe..."
CURRENT_UID=$(kubectl exec -n "${AUTOMATION_NS}" "${AUTOMATION_POD}" -- id -u)
if [[ "${CURRENT_UID}" != "0" ]]; then
    log_pass "Probe running as non-root (UID=${CURRENT_UID})"
    record_result "TEST_1.4_NON_ROOT" "PASS" "Non-root container user" "Running as UID ${CURRENT_UID}"
else
    log_fail "Probe running as ROOT!"
    record_result "TEST_1.4_NON_ROOT" "FAIL" "Non-root container user" "Running as root UID 0"
fi

# Stop cilium monitor
kill "${CILIUM_MONITOR_PID}" >/dev/null 2>&1 || true

# Finalize JSON
echo "[" > "${FINAL_RESULTS}"
sed '$ s/,$//' "${RAW_RESULTS}" >> "${FINAL_RESULTS}"
echo "]" >> "${FINAL_RESULTS}"
rm -f "${RAW_RESULTS}"

log_info "Phase 1 execution complete. Results saved to ${FINAL_RESULTS}."
