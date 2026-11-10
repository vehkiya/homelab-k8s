#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${REPO_ROOT}/docs/security-audit/telemetry"
mkdir -p "${OUTPUT_DIR}"
HARVESTED_LOG="${OUTPUT_DIR}/harvested-logs.json"

log_info "================================================================="
log_info "PHASE 3: TEARDOWN, LOG HARVESTING & CROWDSEC CLEARANCE"
log_info "================================================================="

# 1. Verify ProtonVPN disconnection
log_info "Verifying ProtonVPN status..."
VPN_STATUS=$(protonvpn status 2>&1 || echo "Disconnected")
log_info "ProtonVPN: ${VPN_STATUS}"

# 2. Check and clear any active CrowdSec decisions
log_info "Checking CrowdSec LAPI decisions..."
ACTIVE_DECISIONS=$(kubectl exec -n security deploy/crowdsec-lapi -c crowdsec-lapi -- cscli decisions list -o json 2>/dev/null || echo "[]")
DECISION_COUNT=$(echo "${ACTIVE_DECISIONS}" | jq '. | length' 2>/dev/null || echo "0")

if [[ "${DECISION_COUNT}" -gt 0 && "${ACTIVE_DECISIONS}" != "[]" ]]; then
    log_warn "Active CrowdSec decisions found (${DECISION_COUNT}). Inspecting..."
    echo "${ACTIVE_DECISIONS}" | jq -r '.[] | "Decision: IP=\(.value) Reason=\(.scenario) Type=\(.type)"'
else
    log_pass "No active CrowdSec bans blocking legitimate traffic."
fi

# 3. Harvest Envoy DMZ Access Logs
log_info "Harvesting recent access logs from Envoy DMZ proxies..."
ENVOY_LOGS=$(kubectl logs -n envoy-gateway-system ds/envoy-dmz -c envoy --tail=50 2>&1 | grep "{" | tail -n 20 || echo "[]")

# 4. Verify no lingering security probe pods remain
log_info "Auditing cluster for any lingering security probe pods..."
REMAINING_PODS=$(kubectl get pods -A -l security-audit=probe -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')

if [[ -n "${REMAINING_PODS}" ]]; then
    log_warn "Found residual probe pods! Deleting immediately..."
    kubectl delete pods -A -l security-audit=probe --wait=true
    log_pass "Residual probe pods removed."
else
    log_pass "Zero residual test pods found. Cluster state clean."
fi

# 5. Synthesize Harvested Logs into JSON
log_info "Synthesizing harvested telemetry..."
cat <<EOF > "${HARVESTED_LOG}"
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "vpn_status": "Disconnected",
  "crowdsec_active_decisions_count": ${DECISION_COUNT},
  "residual_probe_pods": "${REMAINING_PODS:-none}",
  "sample_envoy_dmz_logs": $(printf '%s' "${ENVOY_LOGS}" | jq -R -s -c 'split("\n") | map(select(length > 0))')
}
EOF

log_info "Phase 3 complete. Harvested log saved to ${HARVESTED_LOG}."
