# Domain: Networking & Edge

Scope: the CNI and DNS in `apps/bootstrap/`, and every controller in `apps/system/networking/`
(ApplicationSet `apps/gitops/app-of-apps/system-networking.yaml`, namespace = directory name
unless the `kustomization.yaml` overrides it). Blueprints: flows/ingress-and-auth.md,
flows/cilium-network-policies.md.

## Apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| cilium | `apps/bootstrap/cilium` | kube-system | - | Helm, CCNP | CNI in eBPF native-routing mode (no tunnel, no kube-proxy), dual-stack IPv4/IPv6, LoadBalancer IPAM, BGP + L2 announcements. Its own Gateway API and ingress controller are disabled. Day-0 install by OpenTofu, then Argo. Settings: `values/values.yaml` |
| coredns | `apps/bootstrap/coredns` | kube-system | - | Helm, CNP | Cluster DNS plus an in-cluster zone for the lab domain; upstream forwarders in `values`. Its `network-policy.yaml` must list every upstream resolver |
| gateway-api | `apps/system/networking/gateway-api` | cluster-scoped | - | - | Gateway API CRDs (remote resource). CRD provider for every `HTTPRoute`/`Gateway` |
| envoy-gateway | `apps/system/networking/envoy-gateway` | envoy-gateway-system | - | Helm, CNP, SvcMon, PodMon | Controller + Envoy CRDs (`SecurityPolicy`, `BackendTrafficPolicy`, `ClientTrafficPolicy`, `EnvoyProxy`). `proxy-network-policy.yaml` is the proxy fleets' own allow-list: backends not covered by the global `web-ui`/`http-api` policies must be added there |
| edge | `apps/system/networking/edge` | edge | - | HTTPRoute, Gateway, SecPol, BTP | `GatewayClass` `envoy`, Gateways `internal-gateway` and `external-gateway` (`gateways.yaml`), wildcard + apex certs (`certificates.yaml`), CrowdSec on the DMZ gateway, gateway defaults, admission policy. Needs cert-manager, envoy-gateway, crowdsec |
| policies | `apps/system/networking/policies` | per overlay | - | SecPol | Per-namespace `authelia-forward-auth` `SecurityPolicy` overlays + `ReferenceGrant` into `security`. See flows/ingress-and-auth.md |
| traefik | `apps/system/networking/traefik` | traefik | 1 | Helm, HTTPRoute, Gateway, CNP, ExtSecret, SvcMon | Legacy edge: GatewayClass `traefik`, its own `internal-gateway`/`external-gateway`/`plex-gateway`, Traefik CRDs (`Middleware`). Routes named `*-eg` have replaced it; do not add new Traefik routes |
| cert-manager | `apps/system/networking/cert-manager` | cert-manager | - | Helm, CNP, ExtSecret | `ClusterIssuer`s with Cloudflare DNS-01 (`zerossl-issuer-cf-solver.yaml`, `acme-issuer-cf-solver.yaml`). Secrets from OpenBao `platform/cloudflare`, `platform/zerossl` |
| keda | `apps/system/networking/keda` | networking | - | Helm, CNP | KEDA + HTTP add-on. Scale-to-zero apps route to Service `keda-add-ons-http-interceptor-proxy` in `networking`; `reference-grant.yaml` permits it |
| multus | `apps/system/networking/multus` | kube-system | - | - | Secondary pod networks (remote manifest + patches); the only `NetworkAttachmentDefinition` is `apps/workloads/iot/home-assistant/nad.yaml`, attached by home-assistant, go2rtc, matter-server, otbr |
| tailscale | `apps/system/networking/tailscale` | tailscale | - | Helm | Excluded from the ApplicationSet: not deployed |

No tunnel is deployed: Tailscale is parked, and public traffic arrives through the DMZ gateway.

## Cilium datapath pointers

| Concern | File | Contract |
|---|---|---|
| LoadBalancer IPAM pools | `apps/bootstrap/cilium/ip-pools.yaml` | A Service picks a pool with the label `pool: <name>`; unlabeled Services fall into `internal-lb-pool`. Dedicated single-IP pools exist for each proxy fleet (`edge-internal-pool`, `edge-dmz-pool`, and the Traefik pair); `dmz-lb-pool` serves other DMZ Services |
| BGP | `apps/bootstrap/cilium/bgp.yaml` | Peers with the UniFi gateway over IPv4 and IPv6 and advertises LoadBalancer IPs |
| L2 announcements | `apps/bootstrap/cilium/l2-announcements.yaml` | ARP for LoadBalancer IPs on the node bond interface, so same-subnet hosts reach them |
| Network policy baseline | `apps/bootstrap/cilium/global-network-policies.yaml` | Default-deny plus label-driven allows; see security.md |

## CRDs exposed to the cluster

| Provider | CRDs other apps use |
|---|---|
| cilium | `CiliumNetworkPolicy`, `CiliumClusterwideNetworkPolicy`, `CiliumLoadBalancerIPPool`, BGP and L2 announcement kinds |
| gateway-api | `Gateway`, `GatewayClass`, `HTTPRoute`, `ReferenceGrant` |
| envoy-gateway | `SecurityPolicy`, `BackendTrafficPolicy`, `ClientTrafficPolicy`, `EnvoyProxy`, `HTTPRouteFilter` |
| cert-manager | `Certificate`, `ClusterIssuer` |
| keda | `HTTPScaledObject` (HTTP add-on), `ScaledObject` |
| multus | `NetworkAttachmentDefinition` |
| traefik (legacy) | `Middleware` |

## Gateway listeners exposed

Envoy gateways live in namespace `edge` (`apps/system/networking/edge/gateways.yaml`).

| Gateway | `sectionName` | Serves | Routes may attach from |
|---|---|---|---|
| `internal-gateway` | `websecure` | wildcard hosts, LAN | any namespace |
| `internal-gateway` | `websecure-apex` | apex domain | `tools` |
| `internal-gateway` | `plex` | plex host on its own port | `media` |
| `external-gateway` | `dmz` | wildcard hosts, public | any namespace |
| `external-gateway` | `plex` | plex host on its own port | `media` |

The legacy Traefik gateways (`internal-gateway`, `external-gateway`, `plex-gateway` in
namespace `traefik`) are defined in `apps/system/networking/traefik/gateways.yaml`.

## Dependency order

`cilium` -> `coredns` (Day-0) -> `gateway-api` (CRDs) -> `envoy-gateway` (controller + Envoy CRDs) and `cert-manager`
(certificates) -> `edge` (GatewayClass, Gateways, gateway-level policies) -> `policies`
(per-namespace forward-auth) -> app `HTTPRoute`s. Sync-waves do not enforce this order.

## Where to change what

| Change | File |
|---|---|
| Gateway listener, hostname, allowed namespaces | `apps/system/networking/edge/gateways.yaml` |
| Certificate or new SAN | `apps/system/networking/edge/certificates.yaml` |
| Issuer / DNS-01 solver | `apps/system/networking/cert-manager/zerossl-issuer-cf-solver.yaml`, `apps/system/networking/cert-manager/acme-issuer-cf-solver.yaml` |
| Proxy fleet shape, LB pool binding | `apps/system/networking/edge/envoyproxies.yaml` |
| What the proxy fleets may reach or accept | `apps/system/networking/envoy-gateway/proxy-network-policy.yaml` |
| Gateway timeouts, error pages | `apps/system/networking/edge/backend-traffic-policy.yaml`, `apps/system/networking/edge/error-pages` |
| CrowdSec on the DMZ gateway | `apps/system/networking/edge/crowdsec-security-policy.yaml` |
| Forward-auth for a namespace | `apps/system/networking/policies/forward-auth` |
| Scale-to-zero interceptor | `apps/system/networking/keda/kustomization.yaml`, `apps/system/networking/keda/reference-grant.yaml` |
| CoreDNS zones and forwarders | `apps/bootstrap/coredns/values` |
| Legacy Traefik values and gateways | `apps/system/networking/traefik/values`, `apps/system/networking/traefik/gateways.yaml` |

Step-by-step blueprints: flows/ingress-and-auth.md and flows/cilium-network-policies.md.
