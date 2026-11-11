# Flow: Cilium Network Policies

Rules of the road (selector choice, `toFQDNs` limits, webhook ports, validity checks) are in
AGENTS.md section 6. This file maps where policies live and which selectors each flow uses.

## Structure

| Layer | Kind | Where | Purpose |
|---|---|---|---|
| Cluster baseline | `CiliumClusterwideNetworkPolicy` | `apps/bootstrap/cilium/global-network-policies.yaml` | Default-deny for every endpoint, plus the label-driven allows below |
| Per app | `CiliumNetworkPolicy` | `network-policy.yaml` in the app directory (extra files such as `redis-network-policy.yaml`, `dragonfly-network-policy.yaml` for sidecar services) | Everything the baseline does not cover: egress, app-to-app ingress, metrics |
| Proxy fleets | `CiliumNetworkPolicy` | `apps/system/networking/envoy-gateway/proxy-network-policy.yaml` | What the internal and DMZ Envoy fleets accept and may reach |

A CNP is namespaced: `endpointSelector` only selects pods in its own namespace, and a peer
selector without `k8s:io.kubernetes.pod.namespace` only matches that same namespace.
Pods are selected by the `app:` label (most apps) or `app.kubernetes.io/name`.

## Label contracts (no per-app policy needed)

Set these on the **pod template**; the global CCNPs do the rest.

| Pod label | Requires | Effect |
|---|---|---|
| `networking/expose-web-ui: "true"` | container port named `web-ui` | Ingress from Traefik and the internal Envoy fleet |
| `networking/expose-http-api: "true"` | container port named `http-api` | Same, for API ports |
| `networking/expose-dmz: "true"` | one of the two labels above | Additionally ingress from the DMZ Envoy fleet (`external-gateway`) |
| `networking/oidc-client: "true"` | - | Egress to the internal proxies for `auth.kerrlab.app` (OIDC discovery/token hairpin) |
| (none) | - | DNS to CoreDNS and kubelet probes are allowed for every pod |

## Standard flows

| Flow | Direction / selector | Ports |
|---|---|---|
| Ingress proxy -> pod | Global CCNP via labels above. Internal fleet identity: `k8s:io.kubernetes.pod.namespace: envoy-gateway-system` + `gateway.envoyproxy.io/owning-gateway-namespace: edge` + `gateway.envoyproxy.io/owning-gateway-name: internal-gateway` (DMZ: `external-gateway`). Traefik: namespace `traefik` + `app.kubernetes.io/name: traefik` | named `web-ui` / `http-api` |
| Scale-to-zero app | App CNP ingress from `k8s:io.kubernetes.pod.namespace: networking` + `app.kubernetes.io/component: interceptor` (the proxy never talks to the pod directly) | the app's container port |
| Pod -> CoreDNS | Global: `k8s:io.kubernetes.pod.namespace: kube-system` + `k8s-app: coredns` | 53 UDP/TCP |
| Pod -> Authelia (OIDC) | Global via `networking/oidc-client`; targets the internal proxies and their LoadBalancer IPs, not the Authelia pod | 443 (10443/8443/9443 on the proxy pods) |
| Proxy -> Authelia (forward-auth) | Nothing per app: Authelia carries `expose-web-ui` and `expose-dmz` | `web-ui` |
| Pod -> NAS PostgreSQL | App CNP egress `toCIDR: 10.10.1.218/32` | 15432 TCP |
| Pod -> NAS MariaDB / S3 | Same `toCIDR` | 3306 / 8333 TCP |
| Pod -> in-cluster sidecar (Redis, Valkey, Dragonfly) | App CNP egress `toEndpoints` on the sidecar's `app:` label, and a second CNP selecting the sidecar with matching ingress | 6379 TCP |
| Pod -> shared in-cluster service | Egress in the caller's CNP **and** ingress in the callee's CNP with the caller's namespace + label (callee side for meilisearch: `apps/data-services/meilisearch/network-policy.yaml`; for ntfy: `apps/workloads/automation/ntfy/network-policy.yaml`) | service port |
| Pod -> internet | `toEntities: world` | 443 TCP (+ 80 where needed) |
| Pod -> LAN device | `toCIDR` with the device IP or VLAN subnet | device port |
| Pod -> kube-apiserver | `toEntities: kube-apiserver` | 6443 TCP |
| Prometheus -> pod | App CNP ingress from `k8s:io.kubernetes.pod.namespace: observability` + `app.kubernetes.io/name: prometheus`, plus egress in `apps/system/observability/prometheus/network-policies.yaml` | metrics port |

## DMZ exposure checklist

The DMZ fleet has an explicit egress allow-list. A backend routed on `external-gateway` needs:

1. `networking/expose-dmz: "true"` and a named `web-ui`/`http-api` port on the pod, or
2. for Helm-rendered or multi-port backends that cannot carry the label, an explicit rule in
   `apps/system/networking/envoy-gateway/proxy-network-policy.yaml` (`cnp-envoy-dmz`).

Scale-to-zero DMZ routes go through the KEDA interceptor, which is already allowed.

## Reference policies

| File | Shows |
|---|---|
| `apps/workloads/home/mealie/network-policy.yaml` | Minimal app policy: ingress fully delegated to pod labels, egress to NAS Postgres + world |
| `apps/system/security/authelia/network-policy.yaml` | Prometheus scrape ingress, `toEndpoints` to an in-namespace sidecar and a peer app, `toCIDR` to the NAS |

Do not copy the `toServices` rules still present in older media and IoT policies (for example
`apps/workloads/media/prowlarr/network-policy.yaml`); write `toEndpoints` with labels instead.

## After changing a policy

`kubectl get cnp,ccnp -A` and look for `Valid=False`. Alerts for rejected policies are defined in
`apps/system/observability/prometheus/cilium-alerts.yaml`.
