# Domain: Applications (`apps/workloads/`)

One directory per app; ApplicationSets map `apps/workloads/<group>/*` to namespace `<group>`
(see gitops-and-lifecycle.md). "PG" = PostgreSQL on the NAS, "FA" = Authelia forward-auth, "OIDC" =
native Authelia client, "DMZ" = also routed on `external-gateway`. Shared infrastructure names
resolve in storage-and-databases.md, security.md and networking.md.

## Media Stack (namespace `media`)

Shared mounts: `media-pvc` (library + downloads, RWX NFS) and `fonts-pvc`, both defined in
`apps/system/storage/shared-resources`. Config volumes are per-app `longhorn-retain` PVCs in
a `persistence` subdirectory.

Hardware transcoding uses DRA GPU claims (nodes-and-hardware.md): plex and jellyfin share
`shared-intel-gpu-claim` and are pinned to the `node-type: performance` node; nodecast-tv gets
its own claim from `intel-gpu-claim-template`.

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| common | `apps/workloads/media/common` | media | - | Middleware | Only instantiates the legacy Traefik forward-auth Component for the namespace |
| plex | `apps/workloads/media/plex` | media | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret, PVC, PV, CronJob | `media-pvc`, GPU claim, NFS backup volume. Own `plex` listener on both gateways (DMZ). API consumers: tautulli, kometa, imagemaid, posterizarr, bazarr, seerr, sonarr, radarr, home-assistant |
| jellyfin | `apps/workloads/media/jellyfin` | media | - | HTTPRoute, Middleware, SecPol, BTP, CNP, ExtSecret, PVC | `media-pvc`, GPU claim, LDAP against lldap, DMZ. Consumers: bazarr, seerr, home-assistant |
| sonarr | `apps/workloads/media/sonarr` | media | - | HTTPRoute, CNP, ExtSecret, PVC | Two instances (tv, anime) + portal under one host. PG, FA, `media-pvc`. Callers: prowlarr, bazarr, autobrr, kometa, recyclarr, seerr, unpackerr, posterizarr. Download client: qbittorrent |
| radarr | `apps/workloads/media/radarr` | media | - | HTTPRoute, CNP, ExtSecret, PVC | PG, FA, `media-pvc`. Same callers and download client as sonarr |
| prowlarr | `apps/workloads/media/prowlarr` | media | - | HTTPRoute, CNP, ExtSecret, PVC | PG, FA. Indexer manager for sonarr/radarr; uses flaresolverr; world egress |
| flaresolverr | `apps/workloads/media/flaresolverr` | media | - | CNP | Stateless, no route. Only prowlarr may call it (`http-api` port) |
| qbittorrent | `apps/workloads/media/qbittorrent` | media | - | HTTPRoute, CNP, ExtSecret, PVC | FA at `download.kerrlab.app`. VPN sidecar (OpenBao `media/gluetun`), `media-pvc`. Callers: sonarr, radarr, prowlarr, autobrr, n8n, home-assistant |
| autobrr | `apps/workloads/media/autobrr` | media | - | HTTPRoute, CNP, ExtSecret | OIDC, PG. Pushes releases to sonarr, radarr, qbittorrent |
| bazarr | `apps/workloads/media/bazarr` | media | - | HTTPRoute, CNP, ExtSecret, PVC | Two instances (main, anime). PG, FA, `media-pvc`. Calls sonarr, radarr, plex, jellyfin |
| seerr | `apps/workloads/media/seerr` | media | - | HTTPRoute, CNP, ExtSecret, PVC | PG, own auth. Calls plex, jellyfin, sonarr, radarr; sends webhooks |
| tautulli | `apps/workloads/media/tautulli` | media | - | HTTPRoute, CNP, PVC | Plex statistics; own auth. Consumer: kometa |
| kometa | `apps/workloads/media/kometa` | media | - | CNP, ExtSecret, PVC, CronJob | Plex metadata/overlays. `media-pvc`, `fonts-pvc`. Calls plex, sonarr, radarr, tautulli |
| imagemaid | `apps/workloads/media/imagemaid` | media | - | CNP, ExtSecret, CronJob | Mounts plex's RWO config PVC (must co-schedule with plex); shares OpenBao `media/kometa` |
| posterizarr | `apps/workloads/media/posterizarr` | media | - | HTTPRoute, CNP, ExtSecret, PVC | FA. `media-pvc`, `fonts-pvc`. Triggered by sonarr/radarr; calls plex |
| recyclarr | `apps/workloads/media/recyclarr` | media | - | CNP, ExtSecret, CronJob | Syncs quality profiles into sonarr (both instances) and radarr via API keys |
| unpackerr | `apps/workloads/media/unpackerr` | media | - | HTTPRoute, CNP, ExtSecret | FA. `media-pvc`; calls sonarr, radarr |
| nodecast-tv | `apps/workloads/media/nodecast-tv` | media | - | HTTPRoute, KEDA-HTTP, CNP, ExtSecret, PVC | OIDC, scale-to-zero, GPU claim |
| media-webhook-notifier | `apps/workloads/automation/media-webhook-notifier` | automation | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret | Receives webhooks from sonarr, radarr, seerr, plex, jellyfin, qbittorrent. Own Dragonfly. DMZ |

## Home & IoT (namespaces `home`, `iot`)

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| mealie | `apps/workloads/home/mealie` | home | - | HTTPRoute, Middleware, SecPol, BTP, CNP, ExtSecret, PVC, PV | `recipes.kerrlab.app`. OIDC, PG, NFS volume, DMZ with upload exceptions |
| bar-assistant | `apps/workloads/home/bar-assistant` | home | - | HTTPRoute, Middleware, SecPol, BTP, CNP, ExtSecret, PVC | API + salt-rim UI. OIDC, PG, own Redis, shared meilisearch, DMZ |
| miniflux | `apps/workloads/home/miniflux` | home | - | HTTPRoute, CNP, ExtSecret | PG, world egress. No volume |
| wedding-share | `apps/workloads/home/wedding-share` | home | - | HTTPRoute, KEDA-HTTP, CNP, ExtSecret, PVC, PV | `event.kerrlab.app`. NFS volume, scale-to-zero |
| home-assistant | `apps/workloads/iot/home-assistant` | iot | - | HTTPRoute, CNP, ExtSecret, PVC, PV | `hass.kerrlab.app`. NFS config, PG recorder, Multus attachment (`nad.yaml`). Calls mqtt, matter-server, go2rtc, plex, jellyfin, qbittorrent, seerr, minecraft; called by n8n |
| mqtt | `apps/workloads/iot/mqtt` | iot | - | CNP, ExtSecret, PVC, PodMon | Mosquitto + exporter. Clients: home-assistant, z2mqtt |
| z2mqtt | `apps/workloads/iot/z2mqtt` | iot | - | HTTPRoute, Middleware, CNP, PVC, PV | Zigbee2MQTT. FA, NFS volume. Publishes to mqtt; LAN coordinator by IP |
| matter-server | `apps/workloads/iot/matter-server` | iot | - | HTTPRoute, CNP, PVC, PV | FA, NFS volume, Multus. Client: home-assistant. Reaches Thread devices via otbr routes |
| otbr | `apps/workloads/iot/otbr` | iot | - | CNP, ExtSecret, PVC, PodMon | Thread border router, Multus. Dataset from OpenBao `iot/otbr` (never in git) |
| go2rtc | `apps/workloads/iot/go2rtc` | iot | - | HTTPRoute, CNP, ExtSecret | FA. Camera streams for home-assistant; mounts home-assistant's PVC |

## Gaming (namespace `games`)

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| romm | `apps/workloads/games/romm` | games | - | HTTPRoute, Middleware, SecPol, BTP, KEDA-HTTP, CNP, ExtSecret, PVC, PV | OIDC, MariaDB on the NAS, NFS library, scale-to-zero |
| mc-router | `apps/workloads/games/mc-router` | games | - | CNP | TCP router in front of all minecraft servers (LoadBalancer, no HTTP route) |
| minecraft base | `apps/workloads/games/minecraft/base` | games | - | CNP, PVC, PV, CronJob | Shared base, no Application. Data on `longhorn-retain` (S3 backup labels), backups on NFS |
| minecraft-vanilla | `apps/workloads/games/minecraft/overlays/vanilla` | games | - | CNP, ExtSecret, PVC, PV, CronJob | Overlay of base. Manual sync |
| minecraft-vault-hunters | `apps/workloads/games/minecraft/overlays/vault-hunters` | games | - | CNP, ExtSecret, PVC, PV, CronJob | Overlay of base. Manual sync |
| minecraft-create | `apps/workloads/games/minecraft/overlays/create` | games | - | CNP, ExtSecret, PVC, PV, CronJob | Overlay of base. Manual sync |
| satisfactory | `apps/workloads/games/satisfactory` | games | - | CNP, PVC, PV | Manual sync. Same storage pattern as minecraft |

New minecraft overlay or game server = new element in `apps/gitops/app-of-apps/workloads-games.yaml`.

## Self-Hosted Utilities & Dev Tools (namespaces `tools`, `automation`, `comms`)

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| launchpad | `apps/workloads/tools/launchpad` | tools | - | HTTPRoute, Middleware, BTP, CNP, PVC | Dashboard on the apex domain (own gateway listener). FA, own Valkey, reads the kube-apiserver |
| whoami | `apps/workloads/tools/whoami` | tools | - | HTTPRoute, Middleware, BTP, KEDA-HTTP, CNP | Edge test target (FA, DMZ, rate limit). Also instantiates the Traefik forward-auth Component for `tools` |
| it-tools | `apps/workloads/tools/it-tools` | tools | - | HTTPRoute, KEDA-HTTP, CNP | Stateless, scale-to-zero. Golden stateless template |
| excalidraw | `apps/workloads/tools/excalidraw` | tools | - | HTTPRoute, KEDA-HTTP, CNP | Stateless, scale-to-zero |
| iconify | `apps/workloads/tools/iconify` | tools | - | HTTPRoute, KEDA-HTTP, CNP | Stateless, scale-to-zero, world egress |
| mermaid | `apps/workloads/tools/mermaid` | tools | - | HTTPRoute, Middleware, BTP, KEDA-HTTP, CNP | Stateless, scale-to-zero, DMZ |
| bentopdf | `apps/workloads/tools/bentopdf` | tools | - | HTTPRoute, Middleware, BTP, KEDA-HTTP, CNP | `pdf.kerrlab.app`. Stateless, scale-to-zero, DMZ |
| speedtest | `apps/workloads/tools/speedtest` | tools | - | HTTPRoute, Middleware, KEDA-HTTP, CNP | `speed.kerrlab.app`. Stateless, scale-to-zero |
| irc | `apps/workloads/tools/irc` | tools | - | HTTPRoute, KEDA-HTTP, CNP, PVC | The Lounge. `longhorn-retain`, scale-to-zero |
| kaneo | `apps/workloads/tools/kaneo` | tools | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret | Project tracker. OIDC, PG, S3, own Valkey, DMZ |
| keeper | `apps/workloads/tools/keeper` | tools | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret | Calendar sync. PG, own Valkey, DMZ |
| penpot | `apps/workloads/tools/penpot` | tools | - | Helm, HTTPRoute, CNP, ExtSecret | OIDC, PG, S3, own Valkey |
| n8n | `apps/workloads/automation/n8n` | automation | - | Helm, HTTPRoute, Middleware, BTP, CNP, ExtSecret | PG, own Redis, DMZ webhooks. Calls home-assistant, sonarr, radarr, qbittorrent, ntfy |
| ntfy | `apps/workloads/automation/ntfy` | automation | - | HTTPRoute, Middleware, SecPol, BTP, CNP, ExtSecret, PVC | Push notifications, DMZ. Publishers must be listed in its `network-policy.yaml` (media apps, home-assistant, n8n) |
| renovate | `apps/workloads/automation/renovate` | automation | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret | Renovate server + Redis; GitHub webhooks on DMZ. Rules in `renovate.json` |
| koshin | `apps/workloads/automation/koshin` | automation | - | Helm, HTTPRoute, BTP, CNP, ExtSecret | Shares host and OpenBao path with renovate. Chart-managed Valkey + NATS |
| kestra | `apps/workloads/automation/kestra` | automation | - | HTTPRoute, CNP, ExtSecret | Excluded from the ApplicationSet: not deployed |
| fluxer | `apps/workloads/comms/fluxer` | comms | 1,2 | HTTPRoute, Middleware, SecPol, BTP, CNP, ExtSecret | Chat platform, many components ordered by sync-wave. OIDC, PG, S3, shared meilisearch, LiveKit media ports, DMZ |
