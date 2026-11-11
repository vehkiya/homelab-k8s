# Domain: GitOps & Lifecycle

Scope: `apps/gitops/`, ArgoCD and namespaces in `apps/bootstrap/`, dependency automation.
Nodes, Talos and hardware drivers: nodes-and-hardware.md. Cilium and CoreDNS: networking.md.
External Secrets: security.md. Versions and chart pins live in each `kustomization.yaml`.

## Bootstrap ordering contract (Day-0, OpenTofu)

`infra/tofu/bootstrap/apps.tf` applies, in order: cilium -> coredns -> namespaces ->
external-secrets -> argocd -> `apps/gitops/app-of-apps/bootstrap.yaml`. After that ArgoCD owns
everything. The other ApplicationSets in `apps/gitops/app-of-apps` are applied with `kubectl apply -f`
(see AGENTS.md section 7). Sync-waves are not used for ordering, except inside Traefik and Fluxer.

## App-of-Apps hierarchy

```
OpenTofu (infra/tofu/bootstrap) --applies--> ApplicationSet "bootstrap" --generates--> Application per apps/bootstrap/*
human kubectl apply -----------------------> the other ApplicationSets --generate---> Application per app directory
```

There is no root `Application` that owns the ApplicationSets: a new or changed ApplicationSet
file takes effect only after `kubectl apply -f`. No hand-written `Application` manifests exist;
every Application is generated, named after its directory (or list element), in project `default`.

## ApplicationSets (`apps/gitops/app-of-apps`)

Git-directory generators: a new directory under the glob becomes an Application named after it.

| ApplicationSet file | Generator | Destination namespace | Sync |
|---|---|---|---|
| `bootstrap.yaml` | `apps/bootstrap/*` | directory name (kustomization overrides) | auto |
| `data-services.yaml` | `apps/data-services/*` | `data-services` | auto |
| `system-hardware.yaml` | `apps/system/hardware/*` | directory name | auto |
| `system-networking.yaml` | `apps/system/networking/*`, excludes tailscale | directory name | auto |
| `system-observability.yaml` | `apps/system/observability/*`, excludes uptime | `observability` | auto |
| `system-security.yaml` | `apps/system/security/*` | `security` | auto |
| `system-storage.yaml` | `apps/system/storage/*` | directory name | auto |
| `workloads-automation.yaml` | `apps/workloads/automation/*`, excludes kestra | `automation` | auto |
| `workloads-comms.yaml` | `apps/workloads/comms/*` | `comms` | auto |
| `workloads-home.yaml` | `apps/workloads/home/*` | `home` | auto |
| `workloads-iot.yaml` | `apps/workloads/iot/*` | `iot` | auto |
| `workloads-media.yaml` | `apps/workloads/media/*` | `media` | auto |
| `workloads-tools.yaml` | `apps/workloads/tools/*` | `tools` | auto |
| `workloads-games-auto.yaml` | list: romm, mc-router | `games` | auto |
| `workloads-games.yaml` | list: minecraft overlays, satisfactory | `games` | manual |

All use `ServerSideApply=true` and `preserveResourcesOnDeletion`. A `namespace:` in the app's
`kustomization.yaml` wins over the destination namespace.

## Lifecycle apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| argocd | `apps/bootstrap/argocd` | argocd | - | HTTPRoute, CNP, ExtSecret | Config in `argocd-cm.yaml`, `argocd-rbac-cm.yaml`; OIDC client `argocd` in Authelia; repo creds via ExternalSecret |
| namespaces | `apps/bootstrap/namespaces` | cluster-scoped | - | - | Every namespace and its Pod Security level: `namespaces.yaml`. New namespace = edit here |

## Dependency automation

| What | Pointer |
|---|---|
| Renovate rules (automerge, schedules, grouping, custom managers) | `renovate.json` at the repo root |
| What Renovate can see | Images listed under `images:` in a `kustomization.yaml`, `helmCharts` versions, and values preceded by a `# renovate:` comment |
| Self-hosted Renovate server | `apps/workloads/automation/renovate` (see applications.md) |
| Koshin (runs alongside Renovate on the same host) | `apps/workloads/automation/koshin` |
| CI validation pipeline | `.github/workflows/ci.yaml` (mirrors AGENTS.md section 3) |
| Tofu CI | `.github/workflows/tofu.yaml` |
| Pausing autosync for a debugging session | AGENTS.md section 7 |

## Config reloading

No ConfigMap/Secret reloader controller is deployed. Config changes roll pods through
kustomize `configMapGenerator` name hashes; generators that set `disableNameSuffixHash`
(for example dashboards and error pages) and Secrets refreshed by External Secrets do not restart pods.
