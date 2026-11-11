# Flow: Ingress, TLS & Auth

Two edge stacks exist side by side. **Envoy Gateway is the target**; Traefik is the legacy
stack kept until its routes are removed. Every routed app currently carries both a Traefik
route (`http-route.yaml`, `external-http-route.yaml`) and an Envoy copy (`*-eg.yaml`).
New work goes on the Envoy side only.

## Traffic path (Envoy Gateway)

```
LAN client ----> LB IP (pool edge-internal-pool) -> Envoy fleet "internal" -> HTTPRoute -> Service -> pod
Cloudflare ----> LB IP (pool edge-dmz-pool) ------> Envoy fleet "dmz" -----> HTTPRoute -> Service -> pod
                                                     \-> CrowdSec ext-auth (every DMZ request)
route labeled forward-auth --> SecurityPolicy ext-auth --> Authelia --> allow / redirect to auth.kerrlab.app
```

## Shared resources

| Resource | File |
|---|---|
| `GatewayClass` `envoy` | `apps/system/networking/edge/gatewayclass.yaml` |
| Gateways `internal-gateway`, `external-gateway` and their listeners | `apps/system/networking/edge/gateways.yaml` |
| Proxy fleets (`EnvoyProxy` `internal`, `dmz`), LB pool binding | `apps/system/networking/edge/envoyproxies.yaml` |
| LB IP pools | `apps/bootstrap/cilium/ip-pools.yaml` |
| TLS certificates (wildcard + apex, issued by cert-manager) | `apps/system/networking/edge/certificates.yaml` |
| Issuers (DNS-01 via Cloudflare) | `apps/system/networking/cert-manager/zerossl-issuer-cf-solver.yaml` |
| HTTP -> HTTPS redirect | `apps/system/networking/edge/http-redirect.yaml` |
| Gateway defaults: timeouts, error pages | `apps/system/networking/edge/backend-traffic-policy.yaml`, `apps/system/networking/edge/error-pages` |
| Client TLS / headers / real-IP per listener | `apps/system/networking/edge/client-traffic-policies.yaml` |
| CrowdSec on the DMZ gateway | `apps/system/networking/edge/crowdsec-security-policy.yaml` |
| Guard: route-level policies must merge, not replace | `apps/system/networking/edge/admission-policy.yaml` |
| Forward-auth `SecurityPolicy` (base + per-namespace overlays) | `apps/system/networking/policies/forward-auth` |
| Authelia rules and OIDC clients | `apps/system/security/authelia/templates/configuration.yaml` |
| Legacy Traefik gateways / Middleware | `apps/system/networking/traefik/gateways.yaml`, `apps/common/forward-auth` |

## Listeners (`parentRefs` targets, namespace `edge`)

| Gateway | `sectionName` | Hostname | Who may attach |
|---|---|---|---|
| `internal-gateway` | `websecure` | `*.kerrlab.app` | any namespace |
| `internal-gateway` | `websecure-apex` | apex domain | namespace `tools` only |
| `internal-gateway` | `plex` | plex host, dedicated port | namespace `media` only |
| `external-gateway` | `dmz` | `*.kerrlab.app` | any namespace |
| `external-gateway` | `plex` | plex host, dedicated port | namespace `media` only |

TLS terminates at the gateway; routes never reference certificates. A new hostname under the
wildcard needs no certificate work.

## Writing a route

| Need | Do |
|---|---|
| Internal route | `HTTPRoute` with `parentRefs: internal-gateway / edge / websecure`, backend = the app's Service. Example: `apps/workloads/media/prowlarr/http-route-eg.yaml` |
| Public (DMZ) route | Second `HTTPRoute` on `external-gateway / dmz` (`external-http-route-eg.yaml`), pod label `networking/expose-dmz`. Example: `apps/workloads/home/mealie/external-http-route-eg.yaml` |
| Rate limit on a public route | `BackendTrafficPolicy` targeting the route with `mergeType: StrategicMerge`. Example: `apps/workloads/home/mealie/rate-limit-eg.yaml` |
| Large uploads through the DMZ | Named route rule + `SecurityPolicy` on that `sectionName` without body inspection. Example: `apps/workloads/home/mealie/upload-exceptions-eg.yaml` |
| Scale-to-zero | Backend = `keda-add-ons-http-interceptor-proxy` in `networking` + an `HTTPScaledObject`. Example: `apps/workloads/tools/it-tools/http-route-eg.yaml` |

## Authentication options

| Mode | How | Example |
|---|---|---|
| Forward-auth | Label the `HTTPRoute` with `edge.kerrlab.app/forward-auth: authelia`. The namespace must have the `authelia-forward-auth` `SecurityPolicy` overlay (today: iot, longhorn-system, media, tools). Access tier is decided by `access_control.rules` in the Authelia config | `apps/workloads/media/prowlarr/http-route-eg.yaml` |
| Forward-auth in a new namespace | Add an overlay directory under `apps/system/networking/policies/forward-auth`, list it in that `kustomization.yaml`, and add the namespace to `reference-grant.yaml` there | `apps/system/networking/policies/forward-auth/media` |
| Native OIDC | Register a client in the Authelia config, secret via `apps/system/security/authelia/oidc-secrets.yaml`, pod label `networking/oidc-client: "true"`. Procedure: AGENTS.md section 9 | `apps/workloads/home/mealie` |
| None / app-native | Plain route, no label | `apps/workloads/home/miniflux` |

## Pitfalls

- A `SecurityPolicy` holds a single `extAuth`. The forward-auth policy **replaces** the
  gateway's CrowdSec policy on DMZ routes that carry the label; that is intended.
- Any other route-level Envoy policy must set `mergeType`, or the admission policy rejects it.
- A forward-auth label in a namespace without the overlay is not enforced; an alert in
  `apps/system/observability/prometheus/envoy-gateway-alerts.yaml` catches it.
- No `IngressRoute` objects exist in this repo (the `ingress-route*.yaml` files in
  `apps/bootstrap/argocd` contain `HTTPRoute`s). Do not introduce Traefik CRDs.
