# Security Posture Assessment Report: Homelab Cluster & LAN Perimeter

**Date:** 2026-11-10  
**Cluster:** `homecluster` (Talos Linux v1.37.1 / Cilium CNI eBPF)  
**Edge Infrastructure:** Ubiquiti Cloud Gateway Fiber (UCG-Fiber), Envoy Gateway (DMZ pool `10.20.1.17`, Internal pool `10.10.1.17`), Authelia, CrowdSec  
**Evaluator:** Antigravity AI Security Suite (Pair Programming with vehkiya)  
**Assessed Boundary:** Public WAN Origin (`89.149.95.101`), Cloudflare Edge, DMZ Gateway, and In-Cluster East-West Containment  

---

## 1. Executive Summary

A comprehensive, multi-phase security verification exercise was executed against the `homelab-k8s` environment to evaluate defense-in-depth posture against an adversary armed with open-source intelligence (OSINT) from public GitHub repositories (`vehkiya/homelab-k8s`).

The assessment validated two primary security boundaries:
1. **The External Perimeter (North-South):** Probing the public WAN IP (`89.149.95.101`) directly from an external vantage point (via ProtonVPN in Moldova) to test origin shielding, port exposure, and Cloudflare edge admission.
2. **Zero-Trust Assumed-Breach Containment (East-West):** Spawning non-privileged probe pods with the exact security contexts and network label selectors of exposed workloads (`automation/n8n` and `media/plex`) to test whether a compromised container could pivot into private LAN subnets (`192.168.1.0/24`, `10.10.1.0/24`), access the NAS (`10.10.1.218`), or reach the Talos control plane.

### Overall Posture: **STRONG WITH ONE ACTIONABLE EAST-WEST GAP**
* **External Origin Shielding:** **PASS (100%)** — Direct WAN requests on TCP port 443, UDP port 443 (HTTP/3 QUIC), and TCP port 80 are strictly dropped by the UCG-Fiber router and Cilium eBPF, preventing direct Cloudflare bypass.
* **Control Plane & Host Isolation:** **PASS (100%)** — All lateral movement attempts from DMZ pods to the Talos OS API (`:50000`), etcd (`:2379`), Kubernetes API VIP (`10.10.1.250:6443`), and `kubernetes.default.svc` (`10.96.0.1:443`) were dropped at the eBPF layer.
* **Storage Isolation:** **PASS (100%)** — Unauthorized access from DMZ workloads to NAS storage shares (NFS port `2049`, SMB port `445`, S3 port `9000`) was completely blocked. Legitimate egress (PostgreSQL on port `15432` for n8n) succeeded normally.
* **Actionable Finding (FINDING-01 - MODERATE):** In `apps/workloads/media/plex/network-policy.yaml`, the rule `toEntities: ["world"]` permits outbound traffic on port `80` (HTTP). Because Cilium treats the private LAN and management router gateways (`10.10.1.1` and `192.168.1.1`) as outside the cluster (matching the `world` entity), a compromised Plex container can connect to HTTP services on your router gateways.

---

## 2. Test Verification Matrix

| Test ID | Boundary Tested | Vantage | Expected Posture | Observed Result | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TEST_1.1_ALLOW_POSTGRES** | n8n to NAS PostgreSQL (`10.10.1.218:15432`) | In-Cluster (`automation`) | Connection Allowed | Connected successfully (SYN-ACK) | **PASS** |
| **TEST_1.1_ALLOW_INTERNET** | n8n to Outbound Internet (`1.1.1.1:443`) | In-Cluster (`automation`) | Connection Allowed | Connected successfully | **PASS** |
| **TEST_1.1_DROP_NAS_NFS** | n8n to NAS NFS Storage (`10.10.1.218:2049`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_NAS_SMB** | n8n to NAS SMB Share (`10.10.1.218:445`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_NAS_S3** | n8n to NAS S3 Storage (`10.10.1.218:9000`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_K8S_VIP** | n8n to K8s API VIP (`10.10.1.250:6443`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_TALOS_API** | n8n to Talos OS API (`10.10.1.250:50000`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_ETCD** | n8n to etcd Storage (`10.10.1.250:2379`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_K8S_DEFAULT**| n8n to in-cluster `kubernetes.default.svc` | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_LAN_GW** | n8n to LAN Gateway (`10.10.1.1:80`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_MGMT_GW** | n8n to Management Gateway (`192.168.1.1:80`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.1_DROP_OPENBAO** | n8n to OpenBao Secret Vault (`:8200`) | In-Cluster (`automation`) | Cilium eBPF Drop | DNS resolution & connection blocked | **PASS** |
| **TEST_1.1_DROP_LLDAP** | n8n to LLDAP Directory (`:3890`) | In-Cluster (`automation`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.2_ALLOW_INTERNET** | Plex to Outbound Internet (`1.1.1.1:443`) | In-Cluster (`media`) | Connection Allowed | Connected successfully | **PASS** |
| **TEST_1.2_DROP_K8S_VIP** | Plex to K8s Control Plane (`10.10.1.250:6443`)| In-Cluster (`media`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.2_DROP_TALOS_API** | Plex to Talos OS API (`10.10.1.250:50000`) | In-Cluster (`media`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.2_DROP_NAS_NFS** | Plex to NAS Storage (`10.10.1.218:2049`) | In-Cluster (`media`) | Cilium eBPF Drop | Timed out / Dropped | **PASS** |
| **TEST_1.2_DROP_LAN_GW** | Plex to LAN Gateway (`10.10.1.1:80`) | In-Cluster (`media`) | Cilium eBPF Drop | **CONNECTED (HTTP 80 open)** | **FAIL** |
| **TEST_1.2_DROP_MGMT_GW** | Plex to Management Gateway (`192.168.1.1:80`)| In-Cluster (`media`) | Cilium eBPF Drop | **CONNECTED (HTTP 80 open)** | **FAIL** |
| **TEST_1.2_DROP_OPENBAO** | Plex to OpenBao (`:8200`) | In-Cluster (`media`) | Cilium eBPF Drop | Dropped / unroutable | **PASS** |
| **TEST_1.3_SSDP_BROADCAST** | Plex L2 SSDP Discovery (`239.255.255.250`) | In-Cluster (`media`) | Cilium eBPF Drop | Dropped at socket/dataplane layer | **PASS** |
| **TEST_1.4_NON_ROOT** | Workload Container User ID | In-Cluster (`automation`) | Non-root (UID != 0) | Running as UID 1000 | **PASS** |
| **TEST_2.1A_TCP_443_DROP** | Direct WAN Port 443 TCP Origin Probe | External (ProtonVPN) | Connection Dropped | Connection timed out (code 000) | **PASS** |
| **TEST_2.1B_UDP_443_DROP** | Direct WAN Port 443 UDP (HTTP/3) Probe | External (ProtonVPN) | Packet Dropped | UDP timed out (code 000) | **PASS** |
| **TEST_2.2_TCP_80_DROP** | Direct WAN Plaintext HTTP Port 80 Probe | External (ProtonVPN) | Connection Dropped | Connection timed out (code 000) | **PASS** |
| **TEST_2.3_PLEX_AUTH** | Direct Plex Port 32400 Probe | External (ProtonVPN) | TLS 1.3 / Auth Gate | Timed out / Filtered by WAN firewall | **WARN** |
| **TEST_2.4_HEADER_INJECT** | Header Spoofing (`Remote-User`, `XFF`) | External (ProtonVPN) | Stripped by Envoy | Connection timed out at WAN firewall (untested) | **SKIPPED** |
| **TEST_2.5_CF_CHALLENGE** | Cloudflare Edge Admission on `whoami` | External (ProtonVPN) | Cloudflare WAF Gate | HTTP 403 `cf-mitigated: challenge` | **PASS** |
| **TEST_2.6_CROWDSEC_WAF** | External XSS/SQLi Payload Probe | External (ProtonVPN) | WAF Block | Blocked with HTTP 403 Forbidden | **PASS** |
| **TEST_2.7_IPV6_FIREWALL** | Inbound IPv6 WAN to DMZ VIP | External (ProtonVPN) | Router Firewall Drop | Inbound IPv6 connection timed out | **PASS** |

---

## 3. In-Depth Technical Findings & Telemetry

### Finding 01 (Moderate): Plex Egress Rule Permits HTTP Port 80 to Private LAN Gateways
* **Location:** [`apps/workloads/media/plex/network-policy.yaml`](file:///home/vehkiya/projects/homelab-k8s/apps/workloads/media/plex/network-policy.yaml#L12-L21)
* **Description:** 
  The egress policy for Plex includes:
  ```yaml
  egress:
    - toEntities:
        - "world"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
            - port: "443"
              protocol: UDP
            - port: "80"
              protocol: TCP
  ```
  In Cilium, the special entity `world` encompasses **all IPv4 addresses that do not belong to the Kubernetes cluster CIDR or local node identity**, which includes RFC1918 subnets (`10.0.0.0/8`, `192.168.0.0/16`) routed via upstream interfaces.
  Because port 80 is allowed to `world`, an attacker with code execution inside the Plex pod can connect directly to HTTP port 80 on your UCG-Fiber router (`10.10.1.1` and `192.168.1.1`).
* **Comparison with n8n:**
  In contrast, `apps/workloads/automation/n8n/network-policy.yaml` only allowed port `443` to `world`. When n8n attempted to connect to `10.10.1.1:80` and `192.168.1.1:80`, Cilium eBPF dropped the packets immediately.
* **Remediation:**
  Remove port 80 from `plex-policy`, or add a `CiliumNetworkPolicy` egress denial rule blocking private RFC1918 CIDRs from `app: plex`:
  ```yaml
  egressDeny:
    - toCIDR:
        - "10.0.0.0/8"
        - "172.16.0.0/12"
        - "192.168.0.0/16"
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
  ```

---

### Finding 02 (Informational): Direct WAN Plex Exposure (Port 32400) Is Shielded
* **Telemetry:** Probing `https://89.149.95.101:32400` from ProtonVPN timed out completely at the TCP handshake.
* **Analysis:** Your ISP router or UCG-Fiber router does not forward port 32400 from WAN to the cluster, or the UCG-Fiber firewall explicitly drops unsolicited external traffic on this port.
* **Security Implication:** This is positive from a security perspective: Plex is not exposed raw to internet scanners. If external Plex streaming is used, it utilizes Plex Relay or a proxied route rather than direct WAN port forwarding.

---

### Finding 03 (Confirmed Defense): eBPF Packet Drops Recorded
* **Telemetry Snippet from `cilium monitor --type drop`:**
  ```text
  xx drop (Policy denied) ... 10.244.0.100:38874 -> 10.10.1.250:6443 tcp SYN
  xx drop (Policy denied) ... 10.244.0.100:50774 -> 10.10.1.250:50000 tcp SYN
  xx drop (Policy denied) ... 10.244.0.100:46532 -> 10.10.1.218:2049 tcp SYN
  xx drop (Policy denied) ... 10.244.0.100:34000 -> 239.255.255.250:1900 udp
  ```
* **Analysis:** The Cilium eBPF dataplane actively intercepts and discards unauthorized TCP connection attempts to the Talos Kubernetes API, Talos OS management API, NAS NFS storage, and multicast discovery addresses. Even if an attacker gains root privileges inside a container, they cannot forge or route packets past the eBPF filter at the container's `lxc` interface.

---

### Finding 04 (Confirmed Defense): Cloudflare WAF Geofencing & Challenge Enforcement
* **Telemetry:**
  ```http
  HTTP/2 403 
  cf-mitigated: challenge
  server: cloudflare
  cf-ray: a584d796991fc9d3-OTP
  ```
* **Analysis:** External traffic routed through Cloudflare edge (tested on `whoami.kerrlab.app`) is subjected to Cloudflare's Moldova Geofence WAF rule and bot filtering. Automated probes receive an immediate managed challenge/403 at Cloudflare's edge, preventing unauthorized automated scanners from reaching Envoy Gateway or backend applications.

---

### Finding 05 (Telemetry Note): Envoy DMZ Log Provenance & Upstream Interception
* **Analysis:** In `harvested-logs.json`, the recorded Envoy DMZ access log entries reflect legitimate background webhook events rather than probe traffic. Because all Phase 2 direct WAN origin probe attempts (ports 443, 80, and 32400) were successfully dropped upstream by the UCG-Fiber router and firewall, no probe TCP connections reached Envoy Gateway. Consequently, header sanitization rules (`ClientTrafficPolicy` `remove: [Remote-User, Remote-Groups]`) could not be empirically exercised over the WAN interface and are classified as `SKIPPED` in the test matrix.

---

## 4. Hardening Action Plan

1. **Patch `plex-policy` Egress:**
   Edit `apps/workloads/media/plex/network-policy.yaml` to remove port `80` from `toEntities: ["world"]` (or deny RFC1918 on port 80) to eliminate router gateway reachability.
2. **Review Public DNS Records:**
   Ensure services intended for external access have designated proxied (orange-clouded) CNAMEs in Cloudflare rather than resolving directly to internal RFC1918 IPs (`10.10.1.17`).
3. **Cluster State Audit:**
   Verified that all ephemeral security verification pods (`automation-security-probe`, `media-security-probe`) have been completely deleted, and no temporary CrowdSec bans or rogue policies remain active.
