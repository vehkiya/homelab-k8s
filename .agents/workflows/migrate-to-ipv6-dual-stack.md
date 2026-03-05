---
description:
---

# Comprehensive Multi-Phase Migration Plan: IPv6 Dual-Stack

This document outlines the strategic, multi-phase approach to migrate the `homelab-k8s` cluster to an IPv6 Dual-Stack configuration. Given the heavy reliance on hardcoded IPv4 addresses for storage (NFS), external services (Synology, UPS), and internal security (`NetworkPolicies`), a gradual Dual-Stack approach is mandatory to prevent widespread outages.

## Phase 1: Planning and Upstream Configuration

Before touching the Kubernetes cluster, the foundational network must be prepared to route and handle IPv6 traffic.

1. **IPAM Planning:**
   - **Node Subnet:** Decide on the IPv6 subnet for the physical nodes (VLAN 1 / VLAN 2).
   - **Pod CIDR:** Allocate a `/48` or `/56` Unique Local Address (ULA) or Global Unicast Address (GUA) range for Pods (e.g., `fd00:10:244::/48`).
   - **Service CIDR:** Allocate an IPv6 range for Kubernetes Services (e.g., `fd00:11::/112`).
   - **LoadBalancer IPs:** Allocate a small slice of routable IPv6 addresses for external exposure via Cilium IPAM (e.g., `fd00:10:1::/120`).

2. **Upstream Router Configuration (UDM Pro / OPNsense / FRR):**
   - Enable IPv6 on the primary LAN network.
   - Configure Router Advertisements (RA) or DHCPv6.
   - Update BGP peering configuration on the router to accept the new IPv6 Pod and Service CIDRs from the Cilium nodes. If peering over IPv6, configure the IPv6 neighbor addresses.

## Phase 2: Talos Node Configuration Updates

The foundational nodes must be aware of the new Dual-Stack architecture before the CNI can provision it.

1. **Update Machine Configurations:**
   Modify the Talos machine configs (`talos/cluster-config/`) to enable IPv6.
   - **Cluster Network:** Uncomment or add the IPv6 ranges to `podSubnets` and `serviceSubnets`.
     ```yaml
     cluster:
       network:
         podSubnets:
           - 10.244.0.0/16
           - fd00:10:244::/48
         serviceSubnets:
           - 10.96.0.0/12
           - fd00:11::/112
     ```
   - **Node Interfaces:** Ensure `bond0` or the primary interface has an IPv6 address assigned (statically or via DHCPv6/SLAAC). Your configs already show partial readiness (e.g., `fd00:10:244::101/64` on `lab-1`).
2. **Apply Configuration:** Roll out the machine config updates to all Control Plane and Worker nodes using `talosctl apply-config`.

## Phase 3: Cilium & Core Networking Migration

Update the CNI to provision IPv6 addresses and manage routing.

1. **Update Cilium Values (`apps/cluster-core/cilium/values/values.yaml`):**
   - Enable IPv6: `ipv6: enabled: true`
   - Define IPv6 Pod CIDRs in IPAM:
     ```yaml
     ipam:
       operator:
         clusterPoolIPv6PodCIDRList:
           - "fd00:10:244::/48"
         clusterPoolIPv6MaskSize: 64
     ```
   - Enable K8s IPv6 requirement: `k8s: requireIPv6PodCIDR: true`
   - (Optional) Disable IPv6 Masquerade to gain full SNAT-avoidance benefits: `enableIPv6Masquerade: false`
2. **Update Cilium IP Pools (`apps/cluster-core/cilium/ip-pools.yaml`):**
   - Add the allocated IPv6 LoadBalancer blocks alongside the existing IPv4 ranges to ensure dual-stack services get both IPs.
3. **Update Cilium BGP Peering (`apps/cluster-core/cilium/bgp.yaml`):**
   - If utilizing IPv6 peering, add the IPv6 neighbor configurations and ensure IPv6 prefixes are advertised.

## Phase 4: Application & Security Policy Remediation

This is the most critical phase to prevent application failures.

1. **Update NetworkPolicies:**
   Audit and update all `NetworkPolicy` manifests across the `apps/` directory. Wherever an IPv4 node IP or the `10.10.1.0/24` subnet is whitelisted, add the corresponding IPv6 subnet or node IPs.
   _Target Applications:_ Postgres, ArgoCD, External Secrets Operator, Authelia, monitoring stack, etc.

   ```yaml
   # Example addition
   - ipBlock:
       cidr: "fd00:10::/64" # Your node IPv6 subnet
   ```

2. **Update Hardcoded Configurations:**
   - **Home Assistant:** Update `config.yaml` to include the IPv6 LoadBalancer/Node subnets in the `trusted_proxies` list.
   - **CoreDNS:** Add `AAAA` records for static DNS entries like `fortress`, `kube`, and `proxy` in `apps/cluster-core/coredns/values/values.yaml`.

3. **Storage (NFS):**
   - The Synology CSI and NFS PersistentVolumes currently rely on `10.10.1.218`. They can remain on IPv4 (Dual-Stack allows this), but if you intend to move storage to IPv6, update the `server` IP in all `*-pv-pvc.yaml` files and the Synology CSI `NetworkPolicy`.

## Phase 5: Validation and Rollout

1. **Incremental Rollout:** Apply changes via ArgoCD incrementally. Start with core networking (Cilium) and monitor node/pod health.
2. **Validation:**
   - Verify Pods receive both IPv4 and IPv6 addresses (`kubectl get pods -o wide`).
   - Verify Services have Dual-Stack configurations (`ipFamilies: [IPv6, IPv4]`).
   - Test external connectivity to ensure BGP is routing the IPv6 prefixes correctly.
   - Verify internal application communication (e.g., ensure Authelia and Postgres still function).
3. **Clean Up:** Once stabilized, monitor for any lingering IPv4-only dependencies that could be upgraded to support Dual-Stack natively.
