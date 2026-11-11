# Domain: Platform & GitOps

Scope: `apps/gitops/`, `infra/tofu/`, and the lifecycle apps in `apps/bootstrap/` and
`apps/system/hardware/`. Cilium, CoreDNS and gateways: networking.md. External Secrets and
the policy baseline: security.md. Versions and chart pins live in each `kustomization.yaml`.

## Bootstrap order (Day-0, OpenTofu)

`infra/tofu/bootstrap/apps.tf` applies, in order: cilium -> coredns -> namespaces ->
external-secrets -> argocd -> `apps/gitops/app-of-apps/bootstrap.yaml`. After that ArgoCD owns
everything. The other ApplicationSets in `apps/gitops/app-of-apps` are applied with `kubectl apply -f`
(see AGENTS.md section 7). Sync-waves are not used for ordering, except inside Traefik and Fluxer.

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

## Platform apps (`apps/bootstrap`)

The other three bootstrap apps are indexed elsewhere: `apps/bootstrap/cilium` and
`apps/bootstrap/coredns` in networking.md, `apps/bootstrap/external-secrets` in security.md.

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| namespaces | `apps/bootstrap/namespaces` | cluster-scoped | - | - | Every namespace and its Pod Security level: `namespaces.yaml`. New namespace = edit here |
| argocd | `apps/bootstrap/argocd` | argocd | - | HTTPRoute, CNP, ExtSecret | Config in `argocd-cm.yaml`, `argocd-rbac-cm.yaml`; OIDC client `argocd` in Authelia; repo creds via ExternalSecret |
| runtime | `apps/bootstrap/runtime` | cluster-scoped | - | - | `RuntimeClass` objects (crun, WasmEdge); no kustomization, plain manifests |

## Hardware add-ons (`apps/system/hardware`)

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| nfd | `apps/system/hardware/nfd` | node-feature-discovery | - | Helm, CNP | Node labels consumed by the GPU driver and scheduling rules |
| intel-gpu-resource-driver | `apps/system/hardware/intel-gpu-resource-driver` | intel-gpu-resource-driver | - | Helm, CNP | DRA driver for Intel GPUs. Consumers request it through `ResourceClaimTemplate` from `resource-claims.yaml` (plex, jellyfin, nodecast-tv) |

## Talos & OpenTofu

| What | Pointer |
|---|---|
| Node list, per-node patches | `infra/tofu/talos/nodes.tf` |
| Machine config templates | `infra/tofu/talos/templates` (`common`, `controlplane`, `worker`) |
| System extensions / schematic | `infra/tofu/talos/image-factory-parameters.yaml`, `infra/tofu/talos/schematic.tf` |
| Node upgrade procedure | `infra/tofu/talos/upgrade-node.sh` |
| Day-0 components + Vaultwarden secret | `infra/tofu/bootstrap/apps.tf`, `infra/tofu/bootstrap/vaultwarden.tf` |
| Rules for both layers | AGENTS.md section 8 |

## Renovate & CI

| What | Pointer |
|---|---|
| Renovate rules (automerge, schedules, custom managers) | `renovate.json` at the repo root |
| Self-hosted Renovate runner | `apps/workloads/automation/renovate`, `apps/workloads/automation/koshin` (see applications.md) |
| CI validation pipeline | `.github/workflows/ci.yaml` (mirrors AGENTS.md section 3) |
| Tofu CI | `.github/workflows/tofu.yaml` |
