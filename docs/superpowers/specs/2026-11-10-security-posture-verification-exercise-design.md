# Design Document: Homelab Cluster & LAN Security Posture Verification Exercise

**Date:** 2026-11-10  
**Status:** Approved by Reviewer & Ready for Implementation Planning  
**Author:** Antigravity (Pair Programming with vehkiya)  
**Reviewer:** Principal Security Architect  
**Scope:** `homelab-k8s` cluster, UCG-Fiber router, DMZ workloads, and LAN segmentation

---

## 1. Intent & Context

The user maintains a bare-metal Kubernetes homelab (`homelab-k8s`) running on Talos Linux, orchestrated with ArgoCD, Cilium CNI (default-deny), Envoy Gateway (Gateway API), Authelia (OIDC & Forward-Auth), and CrowdSec. Publicly exposed services (Plex, n8n webhooks, media automation) traverse an upstream ISP router performing port forwarding to a **Ubiquiti Cloud Gateway Fiber (UCG-Fiber)** router, which routes traffic to the cluster's DMZ Envoy Gateway pool (`10.20.1.17` on VLAN 2).

Because the `vehkiya/homelab-k8s` repository is public on GitHub, an external attacker has full open-source intelligence (OSINT): internal IP allocations, DNS domain names, routing policies, port assignments, and authentication configurations.

This exercise verifies the real-world security posture of the external perimeter (WAN to UCG-Fiber to DMZ) and the internal network boundaries (DMZ to LAN / Control Plane) against an adversary armed with this repository knowledge.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
* **Validate External Perimeter Controls (WAN to DMZ):**
  1. **Direct Origin Shielding:** Verify that direct TCP and UDP (QUIC/HTTP3) connections to WAN port 443 are dropped by UCG-Fiber or Cilium `cnp-envoy-dmz` (ensuring no origin bypass).
  2. **Direct Ingress (Plex Port 32400):** Verify TLS 1.3 handshake, certificate presentation, header stripping, and token authentication enforcement.
  3. **Header Sanitization:** Verify that injected client identity or proxy headers (`CF-Connecting-IP`, `X-Forwarded-For`, `Remote-User`, `Remote-Groups`) are stripped by Envoy Gateway.
  4. **IPv6 Perimeter Integrity:** Confirm that unsolicited inbound IPv6 WAN traffic to DMZ or node prefixes is dropped by the UCG-Fiber firewall.
* **Verify Assumed-Breach Containment (Realistic Workload Profiles):**
  1. `automation/n8n`: Verify that legitimate database egress (Postgres on NAS at `10.10.1.218:15432`) and required webhooks work, but unauthorized lateral movement to private LAN subnets (`10.10.1.0/24`, `192.168.x.x`), NAS storage protocols (NFS `2049`, SMB `445`, S3 `9000`), and cluster APIs is strictly dropped by Cilium eBPF.
  2. `media/plex`: Verify that streaming and media notify egress work, but unauthorized pivot attempts toward LAN subnets, adjacent workloads, and Kubernetes/Talos APIs are dropped.
* **Verify Control Plane & Host Isolation:** Confirm that compromised DMZ containers cannot access the Talos API (`50000`), etcd (`2379`), Kubernetes VIP (`10.10.1.250:6443`), local host node IP, or the in-cluster service VIP (`10.96.0.1:443`).
* **Deliver Actionable Reporting & Remediation:** Produce a clear matrix of tested boundaries, pass/fail evidence from packet drops (`cilium monitor --type drop`) and Envoy access logs, with concrete remediations for any gaps.

### Non-Goals
* **Volumetric Denial-of-Service (DoS/DDoS) Testing:** No flood testing against ISP uplinks, UCG-Fiber state tables, or Envoy Gateway proxies.
* **Developing Custom Exploits Against Upstream Software:** We do not need to discover or write live exploit code against Plex or n8n binaries. Instead, **Phase 1 explicitly assumes an attacker has already leveraged a 0-day or N-day vulnerability to achieve full remote code execution inside that pod**, and tests whether your infrastructure containment stops the breach from spreading to your LAN, NAS, or control plane.
* **Testing Unrelated Third Parties:** No probing of external networks or Cloudflare infrastructure beyond the designated WAN endpoints.

### Anti-Goals
* **No Lingering Test Artifacts:** All test pods, test network policies, and debug scripts must be automatically destroyed upon completion.
* **Zero Production Downtime:** Probes must be read-only and non-destructive to persistent volumes or cluster availability.
* **Zero Disruption to Residential Connectivity:** Never execute intrusive WAF probes directly without ProtonVPN; prevent accidental bans of the home's primary residential WAN IP on the UCG-Fiber router via `cs-unifi-bouncer`.
* **Zero Credential Exposure:** Maintain strict compliance with the Zero-Credential Leakage Policy in `AGENTS.md`.

---

## 3. Constraints & Operating Environment

* **Target Destination:** External tests will target the public WAN IP directly (`89.149.95.101`) over ProtonVPN, passing specific SNI/Host headers (`--resolve <hostname>:443:<WAN_IP>`).
* **Sequential Phase Execution:** To avoid severing the local workstation's network route to the Talos Kubernetes API (`10.10.1.250:6443` via local gateway `192.168.1.1`), the execution must be sequential:
  - **Phase 1 (Internal Cluster Tests):** Executed first from the workstation using `kubectl` (in-cluster assumed-breach simulation, Cilium policy audits, and baseline telemetry).
  - **Phase 2 (External WAN Tests):** Executed second with ProtonVPN active (probing the public WAN IP directly).
  - **Phase 3 (Analysis & Log Correlation):** Executed after disconnecting ProtonVPN, harvesting `cilium monitor` drop events and Envoy access logs.
* **Cilium Observability Method:** Because `hubble` is disabled in production values to reduce overhead, eBPF drop events must be observed safely using `cilium monitor --type drop` inside the running `cilium-agent` pod rather than modifying Helm values.
* **CrowdSec LAPI & UniFi Bouncer Management:** WAF tests are executed strictly through ProtonVPN. Triggered bans are recorded as test PASS, cleared via `kubectl exec -n security deploy/crowdsec-lapi -c crowdsec -- cscli decisions delete --ip <VPN_IP>`, and given a 60-second buffer for `cs-unifi-bouncer` to synchronize state with the UCG-Fiber router.
* **Workload Resource Isolation:** All ephemeral test pods must comply with `AGENTS.md` (explicit CPU/memory requests and limits, pinned image tags).

---

## 4. Approaches Considered

### Approach 1: External Perimeter Audit Only
* **Scope:** Blackbox testing against the WAN IP only.
* **Trade-off:** Fast, but fails to test lateral movement or the zero-trust promise of Cilium default-deny if an application like Plex or n8n is compromised.

### Approach 2: Full-Spectrum Perimeter + Assumed-Breach Simulation (Selected)
* **Scope:** Full external WAN probing combined with in-cluster assumed-breach lateral movement tests using real workload profiles (`n8n` and `plex`).
* **Trade-off:** Highest verification value; confirms both the external router/firewall perimeter and internal zero-trust containment.

### Approach 3: Declarative Configuration Audit Only
* **Scope:** Offline manifest and policy review.
* **Trade-off:** Zero disruption, but cannot verify live router state, ISP port-forwarding behavior, or live eBPF dataplane drops.

---

## 5. Execution Test Matrix

```
===================================================================================
PHASE 1: ASSUMED BREACH & IN-CLUSTER LATERAL MOVEMENT (Workstation Direct)
===================================================================================
Vantage: Ephemeral test pods matching workload security contexts & labels
Images: curlimages/curl:8.11.1, nicolaka/netshoot:v0.13 (pinned)

[Test 1.1] Automation Profile (n8n Emulation in 'automation' namespace)
  * Legitimate Egress Assertions:
    - TCP 10.10.1.218:15432 (Postgres on NAS)         -> ALLOW (SYN-ACK)
    - TCP home-assistant.iot.svc:8123                 -> ALLOW (HTTP 200/401)
    - TCP sonarr.media.svc:8989 / radarr:7878         -> ALLOW (HTTP 200/401)
    - TCP qbittorrent.media.svc:8080                  -> ALLOW (HTTP 200/401)
    - TCP ntfy.automation.svc:80                      -> ALLOW (HTTP 200)
    - TCP world:443 (e.g. 1.1.1.1:443)                -> ALLOW (TLS Handshake)
  * Unauthorized Lateral Egress Assertions (Must be Cilium eBPF DROPPED):
    - NAS Storage: TCP 10.10.1.218:2049 (NFS), :445 (SMB), :9000 (S3) -> DROP
    - Control Plane: TCP 10.10.1.250:6443 (VIP), Local Node:6443       -> DROP
    - Talos API: TCP 10.10.1.250:50000, Local Node:50000               -> DROP
    - K8s Service VIP: TCP 10.96.0.1:443 (kubernetes.default.svc)      -> DROP
    - Gateway / LAN: TCP 10.10.1.1:80/443, 192.168.1.0/24 (LAN subnets)-> DROP
    - Core Services: Probe OpenBao (security), LLDAP (security)        -> DROP

[Test 1.2] Media Profile (Plex Emulation in 'media' namespace)
  * Legitimate Egress Assertions:
    - TCP/UDP world:443, TCP world:80                                  -> ALLOW
    - TCP media-webhook-notifier.automation.svc:8080                  -> ALLOW
  * Unauthorized Lateral Egress Assertions (Must be Cilium eBPF DROPPED):
    - Control Plane & Talos API (10.10.1.250:6443, :50000, 10.96.0.1)  -> DROP
    - Internal LAN & Gateway (10.10.1.1, 192.168.1.0/24, 10.10.1.218)  -> DROP
    - Adjacent Namespaces: Probe automation, security, kube-system     -> DROP

[Test 1.3] L2 Multicast & Reconnaissance Containment
  * Probe SSDP (UDP 239.255.255.250:1900) & mDNS (UDP 224.0.0.251:5353)-> DROP
  * Query CoreDNS for cluster internal hostnames                       -> Verify L3/L4 drops

[Test 1.4] Workload Security Profile & Admission Audit
  * Verify PSA enforcement adherence against cluster 'enforce: baseline'
  * Audit Plex & n8n manifests against privilege escalation and host namespace leaks

===================================================================================
PHASE 2: EXTERNAL PERIMETER & DIRECT WAN VERIFICATION (via ProtonVPN)
===================================================================================
Vantage: External public IP via ProtonVPN

TRACK 2A: Direct WAN Origin Shielding (Port 443 / HTTPS & HTTP/3)
[Test 2.1a] Direct TCP Port 443 Probing:
  - Command: curl -k -v --connect-timeout 5 https://89.149.95.101:443 --resolve mealie.kerrlab.app:443:89.149.95.101
  - Expected: TIMEOUT / Connection Dropped (by UCG-Fiber or Cilium cnp-envoy-dmz)
[Test 2.1b] Direct UDP Port 443 (QUIC / HTTP/3) Probing:
  - Command: curl --http3 -k -v --connect-timeout 5 https://89.149.95.101:443
  - Expected: No response / UDP packet dropped
[Test 2.2] Direct TCP Port 80 (Plaintext HTTP):
  - Command: curl -v --connect-timeout 5 http://89.149.95.101:80
  - Expected: Connection refused or dropped (no plaintext exposure)

TRACK 2B: Direct WAN Ingress on Legitimate Exposed Service (Port 32400 / Plex)
[Test 2.3] Direct Plex Handshake & Cipher Suite Verification:
  - Command: curl -v https://89.149.95.101:32400 --resolve plex.kerrlab.app:32400:89.149.95.101
  - Expected: TLS 1.3 negotiated, valid *.kerrlab.app cert, HTTP 401 Unauthorized
[Test 2.4] Header Sanitization on Port 32400:
  - Command: Inject headers:
      -H "X-Forwarded-For: 1.2.3.4"
      -H "Remote-User: admin"
      -H "Remote-Groups: administrators"
      -H "CF-Connecting-IP: 8.8.8.8"
  - Expected: Envoy Gateway strips/sanitizes headers before proxying

TRACK 2C: Application-Layer & Edge Proxy Admission (via Cloudflare Hostnames)
[Test 2.5] Unauthenticated Admission Check:
  - Probe https://mealie.kerrlab.app and https://romm.kerrlab.app via public Cloudflare routing
  - Expected: HTTP 302 Redirect to https://auth.kerrlab.app or 401/403
[Test 2.6] Malicious Payload / WAF Verification (CrowdSec AppSec):
  - Probe endpoint with test SQLi/path traversal payload (e.g. /?id=1%27%20OR%201=1)
  - Expected: HTTP 403 Forbidden from crowdsec-envoy-bouncer

TRACK 2D: IPv6 Perimeter Exposure Check
[Test 2.7] Inbound WAN IPv6 Probing:
  - If routable IPv6 is present on WAN, probe 2a00:1858:104b:8558::10 and node IPv6 on ports 443, 32400, 50000, 6443
  - Expected: Filtered / dropped by UCG-Fiber stateful firewall

===================================================================================
PHASE 3: TEARDOWN, LOG HARVESTING & REPORTING (Workstation Direct)
===================================================================================
- Disconnect ProtonVPN immediately upon Track 2 completion
- Delete all ephemeral test pods from 'automation' and 'media' namespaces
- Clear temporary CrowdSec LAPI bans:
  `kubectl exec -n security deploy/crowdsec-lapi -c crowdsec -- cscli decisions delete --ip <PROTONVPN_IP>`
  (allow 60-second window for cs-unifi-bouncer synchronization to UCG-Fiber)
- Harvest Evidence:
  1. eBPF Drop Verification via `kubectl exec -n kube-system ds/cilium -c cilium-agent -- cilium monitor --type drop`
  2. Envoy Access Logs from 'envoy-gateway-system/envoy-dmz' confirming header drops and client IP extraction
  3. CrowdSec alerts log (`cscli alerts list`)
- Compile Final Report with pass/fail telemetry and remediation steps
```

---

## 6. What's Left to the Builder

* Generation of the exact, pinned Kubernetes ephemeral pod specs (using `curlimages/curl:8.11.1` or `nicolaka/netshoot:v0.13`).
* Exact sequence of CLI test execution commands.
* Synthesis of the final security posture audit report.
