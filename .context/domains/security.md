# Domain: Security & Identity

Scope: `apps/system/security/`, the secret provider in `apps/bootstrap/external-secrets`,
`apps/common/`, the forward-auth overlays in `apps/system/networking/policies`, and the
cluster-wide policy baselines. There is no OAuth2-Proxy: Authelia covers both OIDC and
forward-auth. Gateways and the CrowdSec gateway policy are in networking.md.

## Apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| authelia | `apps/system/security/authelia` | security | - | HTTPRoute, Middleware, BTP, CNP, ExtSecret, SvcMon | OIDC provider + forward-auth at `auth.kerrlab.app`, runs as a DaemonSet. Config: `templates/configuration.yaml` (access rules, OIDC clients). Needs LLDAP (LDAPS), Postgres on the NAS, its own Dragonfly (`dragonfly.yaml`), SMTP. Secrets: OpenBao `security/authelia`, `security/authelia/oidc-clients` |
| lldap | `apps/system/security/lldap` | security | - | HTTPRoute, CNP, ExtSecret | User/group directory. Needs Postgres on the NAS. Consumers over LDAPS: authelia, jellyfin |
| crowdsec | `apps/system/security/crowdsec` | security | - | Helm, HTTPRoute, CNP, ExtSecret, SvcMon, PromRule, CronJob | LAPI + agents, Envoy bouncer (`envoy-bouncer-*.yaml`, ext-auth backend of the DMZ gateway), blocklist mirror, UniFi bouncer/sync. Needs Postgres on the NAS. Consumers: `apps/system/networking/edge` (gateway policy), Traefik bouncer plugin |
| policies | `apps/system/networking/policies` | iot, longhorn-system, media, tools | - | SecPol | One `authelia-forward-auth` `SecurityPolicy` per namespace (`forward-auth/base`), plus `forward-auth/reference-grant.yaml` letting those namespaces call the `authelia` Service |
| forward-auth | `apps/common/forward-auth` | consumer's | - | Middleware | Shared kustomize Component, no Application. Legacy Traefik `Middleware` `authelia-forward-auth`; pulled in once per namespace: `apps/workloads/media/common` for media, `apps/workloads/tools/whoami` for tools |
| external-secrets | `apps/bootstrap/external-secrets` | external-secrets | - | Helm, CNP, SecretStore | Operator + `ClusterSecretStore` `openbao-store` (`openbao-cluster-secret-store.yaml`): OpenBao on the NAS, Kubernetes auth. Day-0 install by OpenTofu, then Argo. Every `ExternalSecret` in the repo depends on it |

## Zero-trust baselines

| Baseline | File |
|---|---|
| Network default-deny + label-driven allows (`networking/expose-*`, `networking/oidc-client`) | `apps/bootstrap/cilium/global-network-policies.yaml` |
| Pod Security level per namespace | `apps/bootstrap/namespaces/namespaces.yaml` |
| Envoy route policies must merge with gateway policies | `apps/system/networking/edge/admission-policy.yaml` |
| CrowdSec on every DMZ request | `apps/system/networking/edge/crowdsec-security-policy.yaml` |
| Authelia `default_policy: deny` and domain rules | `apps/system/security/authelia/templates/configuration.yaml` |
| Rejected-policy and auth-coverage alerts | `apps/system/observability/prometheus/cilium-alerts.yaml`, `apps/system/observability/prometheus/envoy-gateway-alerts.yaml` |

Selector details: flows/cilium-network-policies.md.

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
