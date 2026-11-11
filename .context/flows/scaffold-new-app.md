# Flow: Scaffold a New App

Mandatory rules (resource limits, image pinning, ExternalSecrets only, validation pipeline)
are in AGENTS.md sections 2-5. This is the file-level checklist.

## 1. Registration with ArgoCD

| Situation | What to do |
|---|---|
| New app in an existing group (`automation`, `comms`, `home`, `iot`, `media`, `tools`, any `apps/system/*` group, `apps/data-services`) | Create the app directory under the group (workloads: `apps/workloads/<group>/<app>/`) with a `kustomization.yaml`. The group's ApplicationSet git generator picks it up; **no ArgoCD file changes**. Application name = directory name |
| New app in `games` | Add a list element to `apps/gitops/app-of-apps/workloads-games-auto.yaml` (automated) or `apps/gitops/app-of-apps/workloads-games.yaml` (manual sync) |
| New group / namespace | Add the Namespace (with its Pod Security labels) to `apps/bootstrap/namespaces/namespaces.yaml`, copy an ApplicationSet such as `apps/gitops/app-of-apps/workloads-home.yaml`, and have a human `kubectl apply -f` it |
| Park an app without deleting it | `exclude: true` entry in the group's ApplicationSet (see kestra in `apps/gitops/app-of-apps/workloads-automation.yaml`) |

## 2. Files in the app directory

| File | Required content |
|---|---|
| `kustomization.yaml` | `resources:` list; `labels:` pair `app.kubernetes.io/name`; every image under `images:` as `newTag: <tag>@<digest>` so Renovate can update it (values elsewhere need a `# renovate:` comment) |
| `deployment.yaml` | Pod label `app: <app>`; container port named `web-ui` (or `http-api`); pod label `networking/expose-web-ui: "true"`; CPU and memory requests **and** limits on every container |
| `service.yaml` | `targetPort: web-ui` |
| `http-route-eg.yaml` | `HTTPRoute` on `internal-gateway` in namespace `edge`, `sectionName: websecure` |
| `network-policy.yaml` | `CiliumNetworkPolicy` selecting `app: <app>`; only what the global label contracts do not cover |
| `secret.yaml` | `ExternalSecret` against `ClusterSecretStore` `openbao-store` (when the app has secrets) |
| `persistence/` | Own `kustomization.yaml` with the `Prune=false,Delete=false` annotation + the PVC (and PV for NFS) |

Optional, by feature: `external-http-route-eg.yaml` + `rate-limit-eg.yaml` (public),
`httpscaledobject.yaml` (scale-to-zero), `valkey.yaml` + its own policy (cache),
`servicemonitor.yaml` (metrics). Blueprints: the three sibling flow files.

## 3. Files outside the app directory

| When the app... | Also edit |
|---|---|
| uses forward-auth | `access_control.rules` in `apps/system/security/authelia/templates/configuration.yaml` if it needs anything other than the catch-all `users` tier; the namespace overlay in `apps/system/networking/policies/forward-auth` if the namespace has none |
| uses native OIDC | Authelia config (client + policy), `apps/system/security/authelia/oidc-secrets.yaml`; OpenBao entry created by a human |
| calls another in-cluster app | Ingress rule in the callee's `network-policy.yaml` (commonly ntfy, meilisearch, sonarr/radarr, home-assistant) |
| exposes metrics | `apps/system/observability/prometheus/network-policies.yaml` |
| is public but cannot carry `networking/expose-dmz` (Helm, multi-port) | `apps/system/networking/envoy-gateway/proxy-network-policy.yaml` |
| needs special Renovate handling (grouping, schedule, automerge) | `renovate.json` |
| always | The matching table in `.context/domains` |

## 4. Golden templates

| Template | Path | Copy | Leave behind |
|---|---|---|---|
| Simple stateless | `apps/workloads/tools/it-tools` | `kustomization.yaml`, `deployment.yaml`, `service.yaml`, `http-route-eg.yaml`, `network-policy.yaml`, `httpscaledobject.yaml` (drop it and point the route at the Service if scale-to-zero is not wanted) | `http-route.yaml` (Traefik) |
| Full stateful | `apps/workloads/home/mealie` | Everything else: ExternalSecrets, `persistence` (NFS PV/PVC), label-driven network policy, internal + DMZ routes, rate limit, OIDC labels | `http-route.yaml`, `external-http-route.yaml`, `rate-limit.yaml` (Traefik) |

Variants of the stateful template:

| Variant | Take from |
|---|---|
| Forward-auth instead of OIDC | Route label in `apps/workloads/media/prowlarr/http-route-eg.yaml` |
| Longhorn volume instead of NFS | `apps/workloads/media/prowlarr/persistence` |
| Longhorn volume with S3 backup labels | `apps/workloads/media/plex/persistence/longhorn-config-pvc.yaml` |
| Database only, no volume | `apps/workloads/home/miniflux` |
| App + Valkey sidecar, HPA, PDB | `apps/workloads/tools/kaneo` |
| Helm chart through kustomize `helmCharts` | `apps/workloads/tools/penpot` |
| Several instances from one base | `apps/workloads/games/minecraft/base` + `apps/workloads/games/minecraft/overlays/vanilla` |

## 5. Legacy and outlier patterns: do NOT copy

| Pattern | Seen in | Use instead |
|---|---|---|
| Traefik routes: `parentRefs` namespace `traefik`, `ExtensionRef` to a `traefik.io` `Middleware`, `rate-limit.yaml` Middlewares | `http-route.yaml` / `external-http-route.yaml` of almost every app | Envoy route on namespace `edge` + route label / `BackendTrafficPolicy` |
| Traefik forward-auth Component | `apps/common/forward-auth`, `apps/workloads/media/common` | `edge.kerrlab.app/forward-auth: authelia` route label |
| `toServices` egress rules | older media and IoT policies, e.g. `apps/workloads/media/prowlarr/network-policy.yaml` | `toEndpoints` with labels |
| Explicit proxy ingress rules inside an app policy | `apps/data-services/meilisearch/network-policy.yaml` | `networking/expose-*` pod labels + named ports |
| Plain manifests without a `kustomization.yaml` | `apps/bootstrap/runtime` | Always a kustomization |
| `.yml` extension, vendored upstream manifests | `apps/system/storage/synology-csi` | `.yaml`, remote resource or Helm |
| Misleading file names (`ingress-route*.yaml` holding `HTTPRoute`) | `apps/bootstrap/argocd` | `http-route-eg.yaml` |
| Excluded, unmaintained apps | `apps/workloads/automation/kestra`, `apps/system/observability/uptime`, `apps/system/networking/tailscale` | Not a template for anything |
| `synology-iscsi*` StorageClasses | `apps/system/observability/uptime` | `longhorn-retain` or `synostorage-nfs` |

## 6. Before pushing

1. Validation pipeline from AGENTS.md section 3 on the new directory.
2. `git diff --cached` credential audit (AGENTS.md section 1).
3. `go run .context/sync-inventory.go --check` must print `OK`.
