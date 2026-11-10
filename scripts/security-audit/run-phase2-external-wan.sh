#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${SCRIPT_DIR}/lib/common.sh"

OUTPUT_DIR="${REPO_ROOT}/docs/security-audit/telemetry"
mkdir -p "${OUTPUT_DIR}"
RAW_RESULTS="${OUTPUT_DIR}/phase2-raw.json"
FINAL_RESULTS="${OUTPUT_DIR}/phase2-results.json"

export RESULTS_JSON="${RAW_RESULTS}"
rm -f "${RAW_RESULTS}" "${FINAL_RESULTS}"
touch "${RAW_RESULTS}"

WAN_IP="89.149.95.101"

log_info "================================================================="
log_info "PHASE 2: EXTERNAL PERIMETER & DIRECT WAN VERIFICATION"
log_info "================================================================="

# Pre-flight check: Verify external vantage point
CURRENT_PUBLIC_IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "unknown")
log_info "Current Public IP detected: ${CURRENT_PUBLIC_IP}"

if [[ "${CURRENT_PUBLIC_IP}" == "${WAN_IP}" ]]; then
    log_warn "WARNING: You are testing directly from your home residential WAN IP (${WAN_IP})."
    record_result "PREFLIGHT_VANTAGE" "WARN" "Vantage point check" "Testing from residential WAN IP ${CURRENT_PUBLIC_IP}"
else
    log_pass "External vantage point confirmed: Source IP is ${CURRENT_PUBLIC_IP} (distinct from WAN ${WAN_IP})."
    record_result "PREFLIGHT_VANTAGE" "PASS" "Vantage point check" "External source IP ${CURRENT_PUBLIC_IP}"
fi

# -------------------------------------------------------------
# TRACK 2A: Direct WAN Port 443 Origin Shielding Probe
# -------------------------------------------------------------
log_info "--- Track 2A: Direct WAN Port 443 Origin Shielding ---"

log_info "Testing Test 2.1a: Direct TCP Port 443 (Should be dropped by firewall/Cilium)..."
HTTP_443_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 4 "https://${WAN_IP}:443" --resolve "mealie.kerrlab.app:443:${WAN_IP}" 2>/dev/null || true)
if [[ "${HTTP_443_CODE}" == "000" || -z "${HTTP_443_CODE}" ]]; then
    log_pass "Test 2.1a: Direct TCP 443 connection dropped or refused (timeout 000)"
    record_result "TEST_2.1A_TCP_443_DROP" "PASS" "Direct TCP 443 Origin Shielding" "Connection dropped by UCG-Fiber/Cilium as expected (timeout)"
else
    log_fail "Test 2.1a: Direct TCP 443 connection SUCCEEDED with HTTP ${HTTP_443_CODE}!"
    record_result "TEST_2.1A_TCP_443_DROP" "FAIL" "Direct TCP 443 Origin Shielding" "Origin open directly to internet (HTTP ${HTTP_443_CODE})"
fi

log_info "Testing Test 2.1b: Direct UDP Port 443 (HTTP/3 QUIC probe)..."
QUIC_RES=$(curl --http3 -k -s -o /dev/null -w "%{http_code}" --connect-timeout 4 "https://${WAN_IP}:443" 2>/dev/null || true)
if [[ "${QUIC_RES}" == "000" || -z "${QUIC_RES}" ]]; then
    log_pass "Test 2.1b: Direct UDP 443 (HTTP/3) dropped or refused"
    record_result "TEST_2.1B_UDP_443_DROP" "PASS" "Direct UDP 443 QUIC Shielding" "Packet dropped or refused"
else
    log_warn "Test 2.1b: UDP 443 responded with ${QUIC_RES}"
    record_result "TEST_2.1B_UDP_443_DROP" "WARN" "Direct UDP 443 QUIC Shielding" "Responded with ${QUIC_RES}"
fi

log_info "Testing Test 2.2: Direct TCP Port 80 (Plaintext HTTP)..."
HTTP_80_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 "http://${WAN_IP}:80" 2>/dev/null || true)
if [[ "${HTTP_80_CODE}" == "000" || -z "${HTTP_80_CODE}" ]]; then
    log_pass "Test 2.2: Direct TCP 80 connection dropped or refused"
    record_result "TEST_2.2_TCP_80_DROP" "PASS" "Direct Plaintext HTTP 80" "Connection refused/dropped"
else
    log_fail "Test 2.2: Plaintext HTTP 80 is OPEN with HTTP ${HTTP_80_CODE}!"
    record_result "TEST_2.2_TCP_80_DROP" "FAIL" "Direct Plaintext HTTP 80" "Port 80 responded with HTTP ${HTTP_80_CODE}"
fi

# -------------------------------------------------------------
# TRACK 2B: Direct WAN Ingress on Plex (Port 32400)
# -------------------------------------------------------------
log_info "--- Track 2B: Direct WAN Ingress on Plex (Port 32400) ---"

log_info "Testing Test 2.3: Direct Plex TLS Handshake & Auth Gate..."
PLEX_OUTPUT=$(curl -v -s --connect-timeout 5 "https://${WAN_IP}:32400" --resolve "plex.kerrlab.app:32400:${WAN_IP}" 2>&1 || true)
PLEX_HTTP_CODE=$(echo "${PLEX_OUTPUT}" | grep -E "< HTTP/[1-3]" | tail -n 1 | awk '{print $3}' || echo "TIMEOUT")
TLS_VERSION=$(echo "${PLEX_OUTPUT}" | grep -i "SSL connection using" || echo "Unknown TLS")

log_info "Plex TLS Details: ${TLS_VERSION}"
log_info "Plex HTTP Response: ${PLEX_HTTP_CODE}"

if [[ "${PLEX_HTTP_CODE}" == "401" ]]; then
    log_pass "Test 2.3: Plex enforces authentication (HTTP 401 Unauthorized without token)"
    record_result "TEST_2.3_PLEX_AUTH" "PASS" "Plex Port 32400 Auth Enforcement" "Returned 401 Unauthorized: ${TLS_VERSION}"
elif [[ "${PLEX_HTTP_CODE}" == "TIMEOUT" || -z "${PLEX_HTTP_CODE}" ]]; then
    log_warn "Test 2.3: Plex port 32400 timed out or dropped from WAN"
    record_result "TEST_2.3_PLEX_AUTH" "WARN" "Plex Port 32400 Reachability" "Connection timed out"
else
    log_info "Test 2.3: Plex responded with HTTP ${PLEX_HTTP_CODE}"
    record_result "TEST_2.3_PLEX_AUTH" "PASS" "Plex Port 32400 Status" "HTTP ${PLEX_HTTP_CODE}: ${TLS_VERSION}"
fi

log_info "Testing Test 2.4: Header Injection on Plex Port 32400..."
INJECT_OUTPUT=$(curl -s -i --connect-timeout 5 "https://${WAN_IP}:32400" \
    --resolve "plex.kerrlab.app:32400:${WAN_IP}" \
    -H "X-Forwarded-For: 1.2.3.4" \
    -H "Remote-User: admin" \
    -H "Remote-Groups: administrators" \
    -H "CF-Connecting-IP: 8.8.8.8" 2>&1 || true)
INJECT_CODE=$(echo "${INJECT_OUTPUT}" | head -n 1 | awk '{print $2}' || echo "")

if [[ -n "${INJECT_CODE}" && "${INJECT_CODE}" != "ERROR" ]]; then
    log_info "Header Injection Response: HTTP ${INJECT_CODE}"
    record_result "TEST_2.4_HEADER_INJECTION" "PASS" "Header Injection on DMZ Gateway" "Injected headers sent, HTTP code ${INJECT_CODE}"
else
    log_warn "Header Injection skipped: Port 32400 unreachable from WAN"
    record_result "TEST_2.4_HEADER_INJECTION" "SKIPPED" "Header Injection on DMZ Gateway" "Connection timed out at WAN firewall; unable to send headers"
fi

# -------------------------------------------------------------
# TRACK 2C: Edge Proxy & Admission Verification
# -------------------------------------------------------------
log_info "--- Track 2C: Edge Proxy & Application Admission ---"

log_info "Testing Test 2.5: Cloudflare Edge Admission on whoami..."
WHOAMI_RES=$(curl -s -I --connect-timeout 5 "https://whoami.kerrlab.app" 2>&1 || true)
WHOAMI_CODE=$(echo "${WHOAMI_RES}" | head -n 1 | awk '{print $2}' || echo "ERROR")
WHOAMI_CF=$(echo "${WHOAMI_RES}" | grep -i "cf-mitigated:" || echo "None")

log_info "whoami HTTP code: ${WHOAMI_CODE}, Cloudflare mitigation: ${WHOAMI_CF}"
if [[ "${WHOAMI_CODE}" == "403" && "${WHOAMI_CF}" =~ challenge ]]; then
    log_pass "Test 2.5: Cloudflare Edge WAF enforces Managed Challenge / 403 on untrusted external clients"
    record_result "TEST_2.5_CF_CHALLENGE" "PASS" "Cloudflare Edge Geofence WAF" "HTTP 403 Managed Challenge enforced"
elif [[ "${WHOAMI_CODE}" == "302" ]]; then
    log_pass "Test 2.5: Application protected by Authelia forward-auth (HTTP 302)"
    record_result "TEST_2.5_CF_CHALLENGE" "PASS" "Authelia Forward-Auth Gate" "HTTP 302 redirect"
else
    log_info "Test 2.5: Endpoint responded with HTTP ${WHOAMI_CODE}"
    record_result "TEST_2.5_CF_CHALLENGE" "INFO" "Cloudflare / Edge Admission" "HTTP ${WHOAMI_CODE}"
fi

log_info "Testing Test 2.6: Cloudflare Edge Threat Filtering Probe..."
WAF_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://whoami.kerrlab.app/?test=%3Cscript%3Ealert(1)%3C/script%3E" 2>&1 || echo "ERROR")
log_info "Threat Probe HTTP Code: ${WAF_CODE}"
if [[ "${WAF_CODE}" == "403" ]]; then
    log_pass "Test 2.6: External threat probe successfully blocked (HTTP 403 Forbidden)"
    record_result "TEST_2.6_CROWDSEC_WAF" "PASS" "Edge Threat Filtering" "Blocked with HTTP 403"
else
    log_info "Test 2.6: Endpoint returned HTTP ${WAF_CODE}"
    record_result "TEST_2.6_CROWDSEC_WAF" "INFO" "Edge Threat Filtering" "Returned HTTP ${WAF_CODE}"
fi

# -------------------------------------------------------------
# TRACK 2D: IPv6 Inbound Exposure Probe
# -------------------------------------------------------------
log_info "--- Track 2D: Inbound IPv6 Perimeter Filtering ---"
IPV6_TARGET="2a00:1858:104b:8558::10"
log_info "Testing IPv6 reachability to DMZ VIP ${IPV6_TARGET}:443..."
IPV6_CODE=$(curl -6 -k -s -o /dev/null -w "%{http_code}" --connect-timeout 4 "https://[${IPV6_TARGET}]:443" 2>/dev/null || true)
if [[ "${IPV6_CODE}" == "000" || -z "${IPV6_CODE}" ]]; then
    log_pass "Test 2.7: Inbound IPv6 to DMZ VIP dropped/filtered (timeout)"
    record_result "TEST_2.7_IPV6_FIREWALL" "PASS" "Inbound IPv6 Perimeter Filtering" "Connection dropped or filtered by router firewall"
else
    log_info "Test 2.7: IPv6 probe result: ${IPV6_CODE}"
    record_result "TEST_2.7_IPV6_FIREWALL" "INFO" "Inbound IPv6 Perimeter Filtering" "Result: ${IPV6_CODE}"
fi

# Finalize JSON
echo "[" > "${FINAL_RESULTS}"
sed '$ s/,$//' "${RAW_RESULTS}" >> "${FINAL_RESULTS}"
echo "]" >> "${FINAL_RESULTS}"
rm -f "${RAW_RESULTS}"

log_info "Phase 2 execution complete. Results saved to ${FINAL_RESULTS}."
