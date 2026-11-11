# Domain: Storage & Databases

Scope: `apps/system/storage/`, `apps/data-services/`, and the databases that live off-cluster
on the NAS (`fortress`, 10.10.1.218). Decision rules: flows/storage-and-secrets.md.

## Storage apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| longhorn | `apps/system/storage/longhorn` | longhorn-system | - | Helm, HTTPRoute, Middleware, CNP, ExtSecret, StorageClass | Replicated block storage. `storageclass-retain.yaml`, `backup-job.yaml` (RecurringJobs: S3 backup, snapshot cleanup), `volume-trimmer.yaml`. Backs up to S3 on the NAS (OpenBao `platform/s3/backup-filers`). UI behind forward-auth (admin only) |
| synology-csi | `apps/system/storage/synology-csi` | synology-csi | - | CNP, ExtSecret, StorageClass | iSCSI + NFS provisioner against the NAS. StorageClasses in `synology-iscsi.yaml`, `synology-iscsi-persistent.yaml`, `nfs-storage-class.yml`. Credentials: OpenBao `synology-csi/client-info` |
| shared-resources | `apps/system/storage/shared-resources` | media (PVCs) | - | PVC, PV | Static NFS volumes shared across apps: `media-pvc` (media library) and `fonts-pvc`, in `volumes` |
| talos-backup | `apps/system/storage/talos-backup` | talos-backup | - | CNP, PVC, PV, CronJob | etcd snapshots from the control-plane nodes to an NFS export |
| tofu-sync | `apps/system/storage/tofu-sync` | tofu-sync | - | CNP, ExtSecret, CronJob | rclone mirror of the OpenTofu state bucket from Cloudflare R2 to S3 on the NAS. OpenBao `tofu-sync/tofu-sync`, `platform/s3/backup-filers` |

Node prerequisites (nodes-and-hardware.md): the `iscsi-tools` Talos extension for Longhorn and
Synology iSCSI volumes, and the worker label `node.longhorn.io/create-default-disk`.

## Data services (in-cluster, shared)

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| meilisearch | `apps/data-services/meilisearch` | data-services | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret, PVC | Shared search engine on `longhorn-retain`. Consumers (must be listed in its `network-policy.yaml`): fluxer, bar-assistant. Exposed on both gateways |
| kafka | `apps/data-services/kafka` | data-services | - | Helm, CNP | Strimzi operator only; no Kafka cluster or consumer is wired yet |

## StorageClasses

| StorageClass | Provisioner | Mode | Reclaim | Defined in | Used by |
|---|---|---|---|---|---|
| `longhorn-retain` | Longhorn | RWO | Retain | `apps/system/storage/longhorn/storageclass-retain.yaml` | Default choice for app config/state: *arr stack, plex, jellyfin, meilisearch, ntfy, mqtt, otbr, game data |
| `longhorn` | Longhorn | RWO | chart default | chart default (`apps/system/storage/longhorn/values`) | Helm-templated volumes: prometheus stack, n8n, fluxer |
| `longhorn-single-replica` | Longhorn | RWO | Delete | `apps/system/storage/longhorn/storageclass-single-replica.yaml` | One replica, no S3 backup, for data the app replicates itself: koshin Valkey |
| `synostorage-nfs` | Synology CSI | RWX | Retain | `apps/system/storage/synology-csi/nfs-storage-class.yml` | Static PV/PVC pairs on NAS exports: media library, backups, home-assistant, mealie, z2mqtt, matter-server, wedding-share, romm |
| `synology-iscsi` | Synology CSI | RWO | class default | `apps/system/storage/synology-csi/synology-iscsi.yaml` | Cluster default class; no workload in git requests it by name |
| `synology-iscsi-persistent` | Synology CSI | RWO | Retain | `apps/system/storage/synology-csi/synology-iscsi-persistent.yaml` | Only the undeployed uptime app |

## Databases on the NAS (off-cluster)

Not managed in this repo. Apps reach them by `toCIDR` 10.10.1.218/32 in their own
`CiliumNetworkPolicy`; credentials and DB names come from OpenBao via `ExternalSecret`.

| Service | Port | Consumers |
|---|---|---|
| PostgreSQL | 15432 | authelia, lldap, crowdsec, n8n, fluxer, bar-assistant, mealie, miniflux, home-assistant (recorder), autobrr, bazarr, prowlarr, radarr, sonarr, seerr, kaneo, keeper, penpot, kestra (undeployed) |
| MariaDB | 3306 | romm |
| S3 (SeaweedFS) | 8333 | longhorn backups, tofu-sync, fluxer, kaneo, penpot |
| OpenBao (`bao.kerrlab.app`) | 443 | external-secrets |
| NFS | 2049 | synology-csi, talos-backup, kubelet mounts of `synostorage-nfs` volumes |

## Per-app caches and queues (in-cluster, not shared)

Each lives in its owner's directory and has its own network policy; do not share them across apps.

| Owner | Sidecar service |
|---|---|
| authelia | Dragonfly (`apps/system/security/authelia/dragonfly.yaml`) |
| media-webhook-notifier | Dragonfly |
| n8n, renovate, bar-assistant | Redis |
| kaneo, keeper, launchpad, penpot | Valkey |
| koshin | Valkey (sentinel, `longhorn-single-replica`) + NATS (emptyDir), from its Helm chart |
| mqtt | Mosquitto broker for the IoT stack (see applications.md) |
