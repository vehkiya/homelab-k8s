# Domain: Security, Auth & Cluster Add-ons

Scope: `apps/system/security/`, `apps/system/hardware/`, `apps/common/`, the forward-auth
overlays in `apps/system/networking/policies`. The secret provider (External Secrets) lives in
`apps/bootstrap/external-secrets` and is indexed in core-and-gitops.md.

## Apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| authelia | `apps/system/security/authelia` | security | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret, SvcMon | OIDC provider + forward-auth at `auth.kerrlab.app`, runs as a DaemonSet. Config: `templates/configuration.yaml` (access rules, OIDC clients). Needs LLDAP (LDAPS), Postgres on the NAS, its own Dragonfly (`dragonfly.yaml`), SMTP. Secrets: OpenBao `security/authelia`, `security/authelia/oidc-clients` |
| lldap | `apps/system/security/lldap` | security | - | HTTPRoute, CNP, ExtSecret | User/group directory. Needs Postgres on the NAS. Consumers over LDAPS: authelia, jellyfin |
| crowdsec | `apps/system/security/crowdsec` | security | - | Helm, HTTPRoute, CNP, ExtSecret, SvcMon, PromRule, CronJob | LAPI + agents, Envoy bouncer (`envoy-bouncer-*.yaml`, ext-auth backend of the DMZ gateway), blocklist mirror, UniFi bouncer/sync. Needs Postgres on the NAS. Consumers: `apps/system/networking/edge` (gateway policy), Traefik bouncer plugin |
| policies | `apps/system/networking/policies` | iot, longhorn-system, media, tools | - | SecPol | One `authelia-forward-auth` `SecurityPolicy` per namespace (`forward-auth/base`), plus `forward-auth/reference-grant.yaml` letting those namespaces call the `authelia` Service |
| forward-auth | `apps/common/forward-auth` | consumer's | - | Middleware | Shared kustomize Component, no Application. Legacy Traefik `Middleware` `authelia-forward-auth`; pulled in once per namespace: `apps/workloads/media/common` for media, `apps/workloads/tools/whoami` for tools |
| nfd | `apps/system/hardware/nfd` | node-feature-discovery | - | Helm, CNP | Node labels consumed by the GPU driver and scheduling rules |
| intel-gpu-resource-driver | `apps/system/hardware/intel-gpu-resource-driver` | intel-gpu-resource-driver | - | Helm, CNP | DRA driver for Intel GPUs. Consumers request it through `ResourceClaimTemplate` from `resource-claims.yaml` (plex, jellyfin, nodecast-tv) |

## Auth consumers

Group taxonomy and the registration procedure are in AGENTS.md section 9. Edit points:

| Change | File |
|---|---|
| Forward-auth domain rules (order matters, specific before wildcard) | `apps/system/security/authelia/templates/configuration.yaml` -> `access_control.rules` |
| OIDC client + authorization policy | same file -> `identity_providers.oidc.clients` |
| OIDC client secret reference | `apps/system/security/authelia/oidc-secrets.yaml` |
| Enable forward-auth in a new namespace | new overlay in `apps/system/networking/policies/forward-auth` + entry in its `reference-grant.yaml` |

| Mechanism | Downstream apps |
|---|---|
| Native OIDC (pod label `networking/oidc-client: "true"`) | argocd, headlamp, bar-assistant, mealie, autobrr, romm, nodecast-tv, fluxer, kaneo, penpot; off-cluster: openbao, arcane |
| Forward-auth, privileged tier (`administrators`, `privileged-users`) | prowlarr, qbittorrent, sonarr, radarr, bazarr, posterizarr, unpackerr, z2mqtt, go2rtc, matter-server |
| Forward-auth, admin only | longhorn UI, Traefik dashboard |
| Forward-auth, catch-all `users` tier | whoami, launchpad (apex domain) |
| LDAP bind directly against LLDAP | jellyfin |
| No Authelia (own auth or public) | plex, seerr, tautulli, home-assistant, ntfy, miniflux, n8n, keeper, grafana, wedding-share, stateless tools |

## Secret provider consumers

Every app whose Contracts column lists `ExtSecret` depends on `ClusterSecretStore`
`openbao-store`. OpenBao KV paths follow `<namespace-or-group>/<app>` (for example
`media/sonarr-tv`, `home/mealie`, `tools/kaneo`); shared paths:

| OpenBao path | Consumers |
|---|---|
| `security/authelia/oidc-clients` | authelia, penpot |
| `platform/s3/backup-filers` | longhorn, tofu-sync, kaneo, penpot |
| `platform/cloudflare`, `platform/zerossl` | cert-manager |
| `platform/security/crowdsec` | traefik (bouncer key) |
| `automation/renovate` | renovate, koshin |
| `media/kometa` | kometa, imagemaid |

Wiring details: flows/storage-and-secrets.md.
