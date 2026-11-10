# Homelab Cluster & LAN Security Posture Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Orchestrate an end-to-end security verification exercise simulating an attacker with repository OSINT knowledge to validate the external perimeter (WAN to UCG-Fiber router to DMZ) and internal zero-trust containment (assumed-breach lateral movement to LAN, NAS, and Talos control plane).

**Architecture:** The exercise is structured into decoupled, sequential phases to preserve cluster control-plane connectivity on the workstation: first, in-cluster assumed-breach lateral movement testing via ephemeral non-root pods matching exposed workload profiles (`n8n` and `plex`); second, external blackbox probing from ProtonVPN directly targeting the public WAN IP (`89.149.95.101`); third, automated log harvesting via `cilium monitor` and Envoy DMZ access logs, ban cleanup in CrowdSec LAPI, and synthesis of a comprehensive security findings report.

**Tech Stack:** Bash, `kubectl`, Cilium CNI eBPF (`cilium-agent` drop monitor), Envoy Gateway access logs, CrowdSec LAPI (`cscli`), `curl`, `nmap`/`nc`, `curlimages/curl:8.11.1`, `nicolaka/netshoot:v0.13`, ProtonVPN CLI.

**Spec:** [`docs/superpowers/specs/2026-11-10-security-posture-verification-exercise-design.md`](file:///home/vehkiya/projects/homelab-k8s/docs/superpowers/specs/2026-11-10-security-posture-verification-exercise-design.md)

## Global Constraints

* **WAN Target IP:** `89.149.95.101` (Direct WAN origin and Plex ingress).
* **Control Plane VIP:** `10.10.1.250` (Kubernetes API on port `6443`, Talos API on port `50000`).
* **Storage Target:** Synology / SeaweedFS NAS at `10.10.1.218` (Postgres allowed for n8n on `15432`; NFS `2049`, SMB `445`, S3 `9000` strictly blocked).
* **Private Subnets:** `10.10.1.0/24` (Internal LAN / Talos bare metal), `192.168.1.0/24` (Management/Clients), `192.168.4.0/24`, `192.168.11.0/24`, `192.168.29.0/24`.
* **Zero Credential Leakage:** No plaintext tokens, passwords, or private keys in scripts, output logs, or git commits.
* **Mandatory Pod Limits:** Every ephemeral pod container must specify explicit CPU and memory requests and limits (`requests.cpu: 10m`, `limits.cpu: 100m`, `requests.memory: 32Mi`, `limits.memory: 64Mi`).
* **Image Tag Pinning:** Pinned semantic tags only (`curlimages/curl:8.11.1`, `nicolaka/netshoot:v0.13`).
* **Non-Destructive Operations:** Read-only network probes (`curl`, `nc -zv`); zero database mutations or service disruption.
* **Cilium Drop Telemetry:** Use `kubectl exec -n kube-system ds/cilium -c cilium-agent -- cilium monitor --type drop` (Hubble is disabled in production).
* **CrowdSec Clearance Buffer:** Any ProtonVPN IP banned during WAF checks must be cleared via `cscli decisions delete --ip <VPN_IP>` with a 60-second synchronization window for `cs-unifi-bouncer`.

## Review Focus

1. **Phase 2 Origin Drop vs Ingress Conflict:** Ensure direct WAN probes on port 443 are asserted to timeout/drop, while Plex on port 32400 is asserted to negotiate TLS and enforce token auth.
2. **Workstation Routing Preservation:** Ensure ProtonVPN is never connected during Phase 1 or Phase 3, guaranteeing uninhibited workstation access to the Talos Kubernetes API.
3. **Residential IP Protection:** Ensure malicious/WAF test payloads in Track 2C are never sent from the local network, preventing an accidental ban of the home's residential IP on the UCG-Fiber router.
4. **Workload Identity Accuracy:** Ensure ephemeral pods inherit the real namespace and label selectors of `automation/n8n` and `media/plex` so that Cilium eBPF evaluates real workload policies.
5. **Clean Teardown:** Ensure test pods in `automation` and `media` namespaces are unconditionally deleted even if individual assertion steps fail.

---

### Task 1: Reusable Test Fixtures & Probe Pod Manifests

**Files:**
- Create: `scripts/security-audit/fixtures/automation-probe.yaml`
- Create: `scripts/security-audit/fixtures/media-probe.yaml`
- Create: `scripts/security-audit/lib/common.sh`

**Interfaces:**
- Produces: `automation-probe.yaml` (manifest for pod simulating n8n in `automation` namespace with `networking/expose-dmz: "true"` and `app.kubernetes.io/name: n8n`).
- Produces: `media-probe.yaml` (manifest for pod simulating Plex in `media` namespace with `app.kubernetes.io/name: plex`).
- Produces: `scripts/security-audit/lib/common.sh` (utility functions: `log_info`, `log_pass`, `log_fail`, `assert_connection_drop`, `assert_connection_allow`).

- [ ] **Step 1: Write `scripts/security-audit/fixtures/automation-probe.yaml`**
  Declare ephemeral probe pod in `automation` namespace with:
  - Labels: `app.kubernetes.io/name: n8n`, `networking/expose-dmz: "true"`
  - Image: `nicolaka/netshoot:v0.13`
  - Explicit resources: `requests: {cpu: "10m", memory: "32Mi"}`, `limits: {cpu: "100m", memory: "64Mi"}`
  - Security context: `runAsNonRoot: true`, `runAsUser: 1000`, `allowPrivilegeEscalation: false`, `capabilities: {drop: ["ALL"]}`
  - Command: `["sleep", "3600"]`

- [ ] **Step 2: Write `scripts/security-audit/fixtures/media-probe.yaml`**
  Declare ephemeral probe pod in `media` namespace with:
  - Labels: `app.kubernetes.io/name: plex`
  - Image: `nicolaka/netshoot:v0.13`
  - Explicit resources: `requests: {cpu: "10m", memory: "32Mi"}`, `limits: {cpu: "100m", memory: "64Mi"}`
  - Security context: `runAsNonRoot: true`, `runAsUser: 1000`, `allowPrivilegeEscalation: false`, `capabilities: {drop: ["ALL"]}`
  - Command: `["sleep", "3600"]`

- [ ] **Step 3: Write `scripts/security-audit/lib/common.sh`**
  Implement common logging and assertion helper functions with ANSI colors and timestamping.

- [ ] **Step 4: Lint manifests using `kubeconform`**
  Run: `kubeconform -summary -ignore-missing-schemas -strict scripts/security-audit/fixtures/*.yaml`
  Expected: All resources valid.

---

### Task 2: Phase 1 — In-Cluster Assumed-Breach Lateral Movement Verification

**Files:**
- Create: `scripts/security-audit/run-phase1-assumed-breach.sh`

**Interfaces:**
- Consumes: `automation-probe.yaml`, `media-probe.yaml`, `scripts/security-audit/lib/common.sh`.
- Produces: `docs/security-audit/telemetry/phase1-results.json` (machine-readable test results for Phase 1).

- [ ] **Step 1: Write Phase 1 deployment and teardown trap in `run-phase1-assumed-breach.sh`**
  Deploy `automation-probe` into `automation` namespace and `media-probe` into `media` namespace; ensure `trap cleanup EXIT` reliably deletes both pods on script completion or interrupt.

- [ ] **Step 2: Implement n8n Legitimate Egress Assertions (Test 1.1a)**
  Execute probes from `automation-probe`:
  - `nc -z -w 3 10.10.1.218 15432` -> Assert connection SUCCESS (Postgres on NAS).
  - `nc -z -w 3 home-assistant.iot.svc.cluster.local 8123` -> Assert connection SUCCESS.
  - `nc -z -w 3 1.1.1.1 443` -> Assert connection SUCCESS (outbound internet).

- [ ] **Step 3: Implement n8n Unauthorized Lateral Egress Assertions (Test 1.1b)**
  Execute probes from `automation-probe`:
  - `nc -z -w 3 10.10.1.218 2049` (NFS) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.10.1.218 445` (SMB) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.10.1.250 6443` (K8s API VIP) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.10.1.250 50000` (Talos API VIP) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.96.0.1 443` (Kubernetes Service VIP) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.10.1.1 80` (Gateway / Router LAN) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 192.168.1.1 80` (Management LAN Gateway) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 openbao.security.svc.cluster.local 8200` -> Assert connection DROPPED / TIMEOUT.

- [ ] **Step 4: Implement Plex Lateral Egress Assertions (Test 1.2)**
  Execute probes from `media-probe`:
  - `nc -z -w 3 1.1.1.1 443` -> Assert connection SUCCESS (outbound internet).
  - `nc -z -w 3 10.10.1.250 6443` (K8s Control Plane) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.10.1.218 2049` (NAS Storage) -> Assert connection DROPPED / TIMEOUT.
  - `nc -z -w 3 10.10.1.1 80` (LAN Gateway) -> Assert connection DROPPED / TIMEOUT.

- [ ] **Step 5: Implement L2 Multicast / Broadcast Assertions (Test 1.3)**
  Execute probes from `media-probe`:
  - Send UDP datagram to `239.255.255.250:1900` (SSDP) and `224.0.0.251:5353` (mDNS).
  - Verify that no broadcast/multicast packets escape the container veth interface.

- [ ] **Step 6: Capture eBPF Drop Telemetry from Cilium Agent**
  Run `kubectl exec -n kube-system ds/cilium -c cilium-agent -- cilium monitor --type drop --hex -c 20` during probe execution and record observed drops.

- [ ] **Step 7: Run Phase 1 script directly from workstation**
  Execute: `bash scripts/security-audit/run-phase1-assumed-breach.sh`
  Expected: All legitimate egress passes; all lateral movement probes drop; ephemeral pods cleaned up.

---

### Task 3: Phase 2 — External Perimeter & Direct WAN Origin Probing (via ProtonVPN)

**Files:**
- Create: `scripts/security-audit/run-phase2-external-wan.sh`

**Interfaces:**
- Consumes: Public WAN IP `89.149.95.101`, ProtonVPN CLI.
- Produces: `docs/security-audit/telemetry/phase2-results.json` (machine-readable external test results).

- [ ] **Step 1: Write ProtonVPN Pre-Flight Check in `run-phase2-external-wan.sh`**
  Verify that ProtonVPN is connected (`protonvpn status` returns active, public IP is different from residential WAN IP `89.149.95.101`). If not connected, prompt with exact `protonvpn c` command and exit.

- [ ] **Step 2: Implement Track 2A: Direct WAN Port 443 Origin Shielding Probe (Test 2.1a, 2.1b, 2.2)**
  - Test 2.1a (TCP 443): `curl -k -v --connect-timeout 5 https://89.149.95.101:443 --resolve mealie.kerrlab.app:443:89.149.95.101`
    Assert: TIMEOUT / Connection Drop (Confirms non-Cloudflare traffic is blocked).
  - Test 2.1b (UDP 443 / QUIC): `curl --http3 -k -v --connect-timeout 5 https://89.149.95.101:443`
    Assert: TIMEOUT / UDP Drop.
  - Test 2.2 (TCP 80): `curl -v --connect-timeout 5 http://89.149.95.101:80`
    Assert: Connection refused or dropped.

- [ ] **Step 3: Implement Track 2B: Direct WAN Ingress on Plex (Port 32400) (Test 2.3, 2.4)**
  - Test 2.3 (TLS Handshake & Certificate Verification):
    `curl -v --connect-timeout 5 https://89.149.95.101:32400 --resolve plex.kerrlab.app:32400:89.149.95.101`
    Assert: TLS 1.3 negotiated, valid wildcard certificate, HTTP 401 Unauthorized response (Plex token enforcement).
  - Test 2.4 (Header Sanitization & Spoofing Attempt):
    Send request to port 32400 injecting:
    `-H "X-Forwarded-For: 1.2.3.4" -H "Remote-User: admin" -H "Remote-Groups: administrators" -H "CF-Connecting-IP: 8.8.8.8"`
    Assert: Envoy Gateway accepts request without accepting spoofed identity (asserted in Phase 3 log audit).

- [ ] **Step 4: Implement Track 2C: Edge Proxy & Admission Verification (Test 2.5, 2.6)**
  - Test 2.5 (Authelia Forward-Auth Check):
    `curl -I -s https://mealie.kerrlab.app`
    Assert: HTTP 302 Found redirecting to `https://auth.kerrlab.app` (or 401/403).
  - Test 2.6 (CrowdSec AppSec WAF Probe):
    `curl -s -o /dev/null -w "%{http_code}" "https://whoami.kerrlab.app/?test=<script>alert(1)</script>"`
    Assert: HTTP 403 Forbidden (Blocked by CrowdSec bouncer).

- [ ] **Step 5: Implement Track 2D: IPv6 Inbound Exposure Probe (Test 2.7)**
  If IPv6 connectivity is active, probe router VIP / prefixes on ports 443 and 32400.
  Assert: Filtered / dropped by UCG-Fiber stateful firewall.

- [ ] **Step 6: Run Phase 2 script via ProtonVPN**
  Execute: `bash scripts/security-audit/run-phase2-external-wan.sh`
  Expected: Track 2A drops, Track 2B validates TLS & 401, Track 2C validates Authelia redirect & CrowdSec 403.

---

### Task 4: Phase 3 — Teardown, Log Harvesting & CrowdSec Clearance

**Files:**
- Create: `scripts/security-audit/run-phase3-harvest-and-teardown.sh`

**Interfaces:**
- Consumes: `docs/security-audit/telemetry/phase1-results.json`, `docs/security-audit/telemetry/phase2-results.json`.
- Produces: `docs/security-audit/telemetry/harvested-logs.json`.

- [ ] **Step 1: Write Post-VPN Safety Verification in `run-phase3-harvest-and-teardown.sh`**
  Verify ProtonVPN is disconnected (`protonvpn disconnect`); confirm local route to `10.10.1.250:6443` is fully restored.

- [ ] **Step 2: Clear Temporary CrowdSec LAPI Decisions**
  Execute `kubectl exec -n security deploy/crowdsec-lapi -c crowdsec -- cscli decisions delete --ip <VPN_IP>` to remove any ban against the test IP.
  Wait 60 seconds for `cs-unifi-bouncer` to synchronize state with the UCG-Fiber router.

- [ ] **Step 3: Harvest Envoy DMZ Access Logs**
  Query recent access logs from `envoy-gateway-system/envoy-dmz`:
  `kubectl logs -n envoy-gateway-system ds/envoy-dmz -c envoy --tail=100`
  Verify that injected `Remote-User` and `Remote-Groups` headers were dropped, and `downstream_remote_address` correctly recorded the external test client IP.

- [ ] **Step 4: Verify Zero Residual Artifacts**
  Verify that no pods remain with `security-verification` labels in `automation`, `media`, or other namespaces.

- [ ] **Step 5: Run Phase 3 script directly from workstation**
  Execute: `bash scripts/security-audit/run-phase3-harvest-and-teardown.sh`
  Expected: Bans cleared, logs collected, cluster state clean.

---

### Task 5: Security Posture Assessment Report & Findings Matrix

**Files:**
- Create: `docs/security-audit/2026-11-10-security-posture-assessment-report.md`

**Interfaces:**
- Consumes: Telemetry and harvested logs from Tasks 2, 3, and 4.
- Produces: Final Comprehensive Security Posture Report.

- [ ] **Step 1: Compile Executive Summary**
  Synthesize the overall security posture of the homelab cluster across the WAN perimeter, edge proxy, and in-cluster zero-trust eBPF boundaries.

- [ ] **Step 2: Populate the Test Verification Matrix**
  Document every tested boundary with:
  - Boundary description
  - Expected posture
  - Observed telemetry / result
  - Status: PASS / FAIL / WARN

- [ ] **Step 3: Detail Security Findings & Hardening Recommendations**
  Provide clear, prioritized remediation advice for any identified gaps or policy enhancements (e.g. IPv6 firewall tightening, header drop assertions, rate-limiting adjustments).

- [ ] **Step 4: Audit Git Changes for Credential Leaks**
  Run `git diff --cached` and verify that no credentials, tokens, or private keys are staged, per `AGENTS.md` Rule 1.
