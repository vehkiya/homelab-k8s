# Domain: Source Repos (in-house images and charts)

Images and charts under `ghcr.io/hononeko/` are built from separate repos owned by the user.
This repo only pins the published artifact; the code, Dockerfile, chart and release workflow
live in the source repo. Open it when a change needs app behaviour, an image's contents, a
config schema or a new release, not just a manifest edit.

## Fetching a Source Repo On Demand

1. **Local checkout first.** If `~/projects/<repo>` exists, `git -C ~/projects/<repo> fetch`
   and read from `origin/main` (`git show origin/main:<path>`). Other sessions may use that
   checkout: never switch its branch; make a `git worktree` for edits.
2. **No checkout:** `gh repo clone hononeko/<repo> ~/projects/<repo>`.
3. **One file, read-only:**
   `gh api repos/hononeko/<repo>/contents/<path>?ref=main -H 'Accept: application/vnd.github.raw'`.

All repos use the default branch `main`. Private repos need the authenticated `gh` CLI or the
GitHub MCP; public ones also work anonymously.

## Release Flow

Each source repo builds and pushes its own image (shared workflows in `hononeko/actions`) on a
release tag. Renovate then opens the bump PR here (`renovate.json`). Pin stable releases only;
`pr-<N>-<sha>` snapshot tags from the `snapshot` PR label are for testing, never for commits.

## In-House Repos

| Artifact (`ghcr.io/hononeko/...`) | Source repo | Lang | Visibility | Consumers in this repo |
|---|---|---|---|---|
| `k8s-config-tools` | `hononeko/homelab-utils-docker` | Dockerfile | public | Config-render initContainers (gomplate): `apps/workloads/media/sonarr`, `apps/workloads/media/radarr`, `apps/workloads/media/prowlarr`, `apps/workloads/media/jellyfin`, `apps/workloads/media/kometa`, `apps/workloads/media/posterizarr`, `apps/workloads/iot/home-assistant`, `apps/workloads/iot/go2rtc`, `apps/workloads/games/minecraft/base`, `apps/workloads/automation/media-webhook-notifier`, `apps/system/security/crowdsec`, `apps/system/storage/longhorn` |
| `k8s-backup-tools` | `hononeko/homelab-utils-docker` | Dockerfile | public | Backup/sync sidecars: `apps/workloads/media/plex`, `apps/workloads/media/jellyfin` |
| `media-webhook-notifier` | `hononeko/media-webhook-notifier` | Kotlin | public | `apps/workloads/automation/media-webhook-notifier` |
| `agentic-ticket-proxy` | `hononeko/agentic-ticket-proxy` | Kotlin | private | `apps/workloads/ai/agentic-ticket-proxy` |
| `charts/koshin`, `koshin-worker`, `koshin-proxy` | `hononeko/koshin` (app + Helm chart) | Kotlin | public | `apps/workloads/automation/koshin` (chart vendored under `charts/`) |
| `thread-udp-proxy` | `hononeko/thread-udp-proxy` | Go | public | Sidecar in `apps/workloads/iot/otbr` |
| `qbit-gluetun-sync` | `hononeko/qbit-gluetun-sync` | Go | public | Sidecar in `apps/workloads/media/qbittorrent` (VPN port forward) |
| `qbit-ntfy-sidecar` | `hononeko/qbit-ntfy-sidecar` | Go | public | Sidecar in `apps/workloads/media/qbittorrent` |
| `cs-edl-bouncer` | `hononeko/cs-edl-bouncer` | Go | public | Blocklist mirror and UniFi sync in `apps/system/security/crowdsec` |
| `homelab-launchpad` | `hononeko/homelab-launchpad` | TypeScript | public | `apps/workloads/tools/launchpad` |
| `miru` | `hononeko/miru` | Kotlin | public | `apps/workloads/media/miru` |
| `traefik-plugin-cloudflare-realip` (`ghcr.io/vehkiya/...`) | `hononeko/traefik-plugin-cloudflare-realip` | Go | public | Packaged by `.github/workflows/build-traefik-plugins-oci.yaml`; loaded in `apps/system/networking/traefik/values` |

## Repackaged Upstream Artifacts (not in-house)

Built by this repo's workflows from upstream releases; the source is upstream, so changes go
into the workflow here, not into a source repo.

| Artifact (`ghcr.io/vehkiya/...`) | Upstream | Workflow |
|---|---|---|
| `vuetorrent` | `VueTorrent/VueTorrent` | `.github/workflows/build-vuetorrent-oci.yaml` |
| `crowdsec-bouncer-traefik-plugin` | `maxlerebourg/crowdsec-bouncer-traefik-plugin` | `.github/workflows/build-traefik-plugins-oci.yaml` |
| `traefik-plugin-request-id` | `mdklapwijk/traefik-plugin-request-id` | `.github/workflows/build-traefik-plugins-oci.yaml` |

## Keeping It in Sync

A new `ghcr.io/hononeko/*` or `ghcr.io/vehkiya/*` image in `apps/`, `infra/` or `renovate.json`
needs a row here. `go run .context/sync-inventory.go --check` fails on any unlisted one.
