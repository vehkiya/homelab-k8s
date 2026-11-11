# Flow: Storage & Secrets

Inventory of classes, shared volumes and NAS databases: domains/storage-and-databases.md.

## Storage decision matrix

| Need | Use | Access | Pattern | Reference |
|---|---|---|---|---|
| App config / state, single pod | `longhorn-retain` | RWO | Dynamic PVC in a `persistence` subdirectory | `apps/workloads/media/prowlarr/persistence` |
| Same, and worth an off-site copy | `longhorn-retain` + backup labels | RWO | PVC labels below | `apps/workloads/media/plex/persistence/longhorn-config-pvc.yaml` |
| Bulk data, shared between pods or readable from the NAS | `synostorage-nfs` | RWX | Static `PersistentVolume` (NFS export path) + PVC bound by `pv-name` selector | `apps/workloads/home/mealie/persistence/nfs-storage.yaml` |
| The media library or fonts | existing `media-pvc` / `fonts-pvc` | RWX | Mount the shared claim (namespace `media` only) | `apps/system/storage/shared-resources/volumes` |
| Volume templated by a Helm chart | `longhorn` | RWO | Chart values | `apps/system/observability/prometheus/values/values.yaml` |
| Volume of an app that replicates its own data across pods | `longhorn-single-replica` | RWO | Chart values | `apps/workloads/automation/koshin/values/values.yml` |
| Relational database | PostgreSQL on the NAS | - | No PVC; `ExternalSecret` + `toCIDR` egress | `apps/workloads/home/miniflux` |
| Cache / queue | Per-app Redis, Valkey or Dragonfly | - | Sidecar Deployment in the app directory, usually no volume | `apps/workloads/tools/kaneo/valkey.yaml` |

Guidance:

- Prefer Longhorn for anything SQLite-like or latency-sensitive; never put SQLite on NFS.
- Prefer NFS when the data must outlive the cluster, be browsed on the NAS, or be mounted by
  several pods.
- The `synology-iscsi*` classes exist but no deployed workload requests them; do not pick
  them for new apps.
- An RWO volume mounted by two workloads forces them onto one node (imagemaid + plex).

## Volume safety conventions

| Convention | Where |
|---|---|
| `argocd.argoproj.io/sync-options: Prune=false,Delete=false` on every PV/PVC, set through `commonAnnotations` in the `persistence` kustomization | `apps/workloads/media/prowlarr/persistence/kustomization.yaml` |
| Reclaim policy `Retain` on every class used for app data | `apps/system/storage/longhorn/storageclass-retain.yaml` |
| Off-site backup opt-in: PVC labels `recurring-job.longhorn.io/source: "enabled"` and `recurring-job.longhorn.io/daily-s3-backup: "enabled"` | job definitions in `apps/system/storage/longhorn/backup-job.yaml` |
| Both RecurringJobs also belong to Longhorn's `default` group; read the file before assuming a volume is or is not backed up | same file |
| App-level backups to NFS via CronJob (games, plex) | `apps/workloads/games/minecraft/base`, `apps/workloads/media/plex` |

Removing a volume is always manual: Argo will not prune it.

## Secrets: OpenBao -> ExternalSecret -> Secret

```
OpenBao KV v2 (mount "secret", on the NAS)
   ^  Kubernetes auth, role eso-role, ServiceAccount external-secrets/external-secrets
ClusterSecretStore "openbao-store"        apps/bootstrap/external-secrets/openbao-cluster-secret-store.yaml
   ^  secretStoreRef (kind: ClusterSecretStore)
ExternalSecret in the app namespace  ->  Secret (creationPolicy: Owner)  ->  envFrom / volume in the pod
```

| Step | Detail |
|---|---|
| 1. Store the value | In OpenBao at `<group>/<app>` (for example `media/prowlarr`). A human does this; agents never write secret values into git |
| 2. Declare | `ExternalSecret` in the app directory (`secret.yaml`, `secrets.yaml` or `external-secrets.yaml`), `remoteRef.key` = the KV path, `property` = the field |
| 3. Consume | Reference `target.name` from the workload |
| Reference manifest | `apps/workloads/media/prowlarr/secret.yaml` |
| OIDC client secrets | OpenBao `security/authelia/oidc-clients`; Authelia side in `apps/system/security/authelia/oidc-secrets.yaml` |

Rules (AGENTS.md sections 1 and 5): no plain `Secret` manifests, no base64 data, no secret
values in ConfigMaps or kustomize generators. The store is cluster-scoped, so a new namespace
needs no extra wiring.

## Day-0 exceptions

| Secret | Managed by |
|---|---|
| `vaultwarden-credentials` (Day-0 secret, see AGENTS.md section 8) | `infra/tofu/bootstrap/vaultwarden.tf`, kept out of Argo pruning |
| Talos machine secrets | `infra/tofu/talos/secrets.tf` and git-ignored tfvars |
