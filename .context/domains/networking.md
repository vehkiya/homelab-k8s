# Domain: Networking & Edge

Scope: `apps/system/networking/`. The CNI itself (Cilium: BGP, LB IP pools, L2, global
policies) is a bootstrap app at `apps/bootstrap/cilium`, indexed in core-and-gitops.md.
All apps here come from `apps/gitops/app-of-apps/system-networking.yaml`; the destination
namespace is the directory name unless the app's `kustomization.yaml` overrides it.

## Apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| gateway-api | `apps/system/networking/gateway-api` | cluster-scoped | - | - | Gateway API CRDs (remote resource). CRD provider for every `HTTPRoute`/`Gateway` |
| envoy-gateway | `apps/system/networking/envoy-gateway` | envoy-gateway-system | - | Helm, CNP, SvcMon, PodMon | Controller + Envoy CRDs (`SecurityPolicy`, `BackendTrafficPolicy`, `ClientTrafficPolicy`, `EnvoyProxy`). `proxy-network-policy.yaml` is the proxy fleets' own allow-list: backends not covered by the global `web-ui`/`http-api` policies must be added there |
| edge | `apps/system/networking/edge` | edge | - | HTTPRoute, Gateway, SecPol, BTP | `GatewayClass` `envoy`, Gateways `internal-gateway` and `external-gateway` (`gateways.yaml`), wildcard + apex certs (`certificates.yaml`), CrowdSec on the DMZ gateway, gateway defaults, admission policy. Needs cert-manager, envoy-gateway, crowdsec |
| policies | `apps/system/networking/policies` | per overlay | - | SecPol | Per-namespace `authelia-forward-auth` `SecurityPolicy` overlays + `ReferenceGrant` into `security`. See flows/ingress-and-auth.md |
| traefik | `apps/system/networking/traefik` | traefik | 1 | Helm, HTTPRoute, Gateway, CNP, ExtSecret, SvcMon | Legacy edge: GatewayClass `traefik`, its own `internal-gateway`/`external-gateway`/`plex-gateway`, Traefik CRDs (`Middleware`). Routes named `*-eg` have replaced it; do not add new Traefik routes |
| cert-manager | `apps/system/networking/cert-manager` | cert-manager | - | Helm, CNP, ExtSecret | `ClusterIssuer`s with Cloudflare DNS-01 (`zerossl-issuer-cf-solver.yaml`, `acme-issuer-cf-solver.yaml`). Secrets from OpenBao `platform/cloudflare`, `platform/zerossl` |
| keda | `apps/system/networking/keda` | networking | - | Helm, CNP | KEDA + HTTP add-on. Scale-to-zero apps route to Service `keda-add-ons-http-interceptor-proxy` in `networking`; `reference-grant.yaml` permits it |
| multus | `apps/system/networking/multus` | kube-system | - | - | Secondary pod networks (remote manifest + patches); the only `NetworkAttachmentDefinition` is `apps/workloads/iot/home-assistant/nad.yaml`, attached by home-assistant, go2rtc, matter-server, otbr |
| tailscale | `apps/system/networking/tailscale` | tailscale | - | Helm | Excluded from the ApplicationSet: not deployed |

## Dependency order

`gateway-api` (CRDs) -> `envoy-gateway` (controller + Envoy CRDs) and `cert-manager`
(certificates) -> `edge` (GatewayClass, Gateways, gateway-level policies) -> `policies`
(per-namespace forward-auth) -> app `HTTPRoute`s. Sync-waves do not enforce this order.

## Where to change what

| Change | File |
|---|---|
| Gateway listener, hostname, allowed namespaces | `apps/system/networking/edge/gateways.yaml` |
| Certificate or new SAN | `apps/system/networking/edge/certificates.yaml` |
| Issuer / DNS-01 solver | `apps/system/networking/cert-manager/zerossl-issuer-cf-solver.yaml`, `apps/system/networking/cert-manager/acme-issuer-cf-solver.yaml` |
| Proxy fleet shape, LB pool binding | `apps/system/networking/edge/envoyproxies.yaml` |
| LB IP pools, BGP peers, L2 announcements | `apps/bootstrap/cilium/ip-pools.yaml`, `apps/bootstrap/cilium/bgp.yaml`, `apps/bootstrap/cilium/l2-announcements.yaml` |
| What the proxy fleets may reach or accept | `apps/system/networking/envoy-gateway/proxy-network-policy.yaml` |
| Cluster-wide default-deny and label-driven allows | `apps/bootstrap/cilium/global-network-policies.yaml` |
| Gateway timeouts, error pages | `apps/system/networking/edge/backend-traffic-policy.yaml`, `apps/system/networking/edge/error-pages` |
| CrowdSec on the DMZ gateway | `apps/system/networking/edge/crowdsec-security-policy.yaml` |
| Forward-auth for a namespace | `apps/system/networking/policies/forward-auth` |
| Scale-to-zero interceptor | `apps/system/networking/keda/kustomization.yaml`, `apps/system/networking/keda/reference-grant.yaml` |
| Legacy Traefik values and gateways | `apps/system/networking/traefik/values`, `apps/system/networking/traefik/gateways.yaml` |

Step-by-step blueprints: flows/ingress-and-auth.md and flows/cilium-network-policies.md.
