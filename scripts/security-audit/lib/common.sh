#!/usr/bin/env bash
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RESULTS_JSON="${RESULTS_JSON:-/dev/null}"

log_info() {
    echo -e "${BLUE}[INFO] $(date '+%Y-%m-%dT%H:%M:%S') - $1${NC}"
}

log_pass() {
    echo -e "${GREEN}[PASS] $(date '+%Y-%m-%dT%H:%M:%S') - $1${NC}"
}

log_fail() {
    echo -e "${RED}[FAIL] $(date '+%Y-%m-%dT%H:%M:%S') - $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%dT%H:%M:%S') - $1${NC}"
}

record_result() {
    local test_id="$1"
    local status="$2"
    local desc="$3"
    local details="$4"

    if [[ "$RESULTS_JSON" != "/dev/null" ]]; then
        cat <<EOF >> "$RESULTS_JSON"
{
  "test_id": "$test_id",
  "status": "$status",
  "description": "$desc",
  "details": $(printf '%s' "$details" | jq -R -s .),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
},
EOF
    fi
}

assert_tcp_allow() {
    local pod="$1"
    local ns="$2"
    local host="$3"
    local port="$4"
    local desc="$5"
    local test_id="$6"

    log_info "Testing ALLOW: $desc ($host:$port from $ns/$pod)..."
    if kubectl exec -n "$ns" "$pod" -- nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
        log_pass "$desc: Connection allowed as expected"
        record_result "$test_id" "PASS" "$desc" "Connected successfully to $host:$port"
        return 0
    else
        log_fail "$desc: Expected ALLOW, but connection failed or timed out"
        record_result "$test_id" "FAIL" "$desc" "Failed to connect to $host:$port"
        return 1
    fi
}

assert_tcp_drop() {
    local pod="$1"
    local ns="$2"
    local host="$3"
    local port="$4"
    local desc="$5"
    local test_id="$6"

    log_info "Testing DROP: $desc ($host:$port from $ns/$pod)..."
    local output
    if output=$(kubectl exec -n "$ns" "$pod" -- nc -z -w 2 "$host" "$port" 2>&1); then
        log_fail "$desc: Expected DROP, but connection SUCCEEDED!"
        record_result "$test_id" "FAIL" "$desc" "Unexpectedly connected to $host:$port"
        return 1
    else
        log_pass "$desc: Connection blocked/dropped as expected"
        record_result "$test_id" "PASS" "$desc" "Connection to $host:$port timed out or dropped: $output"
        return 0
    fi
}
