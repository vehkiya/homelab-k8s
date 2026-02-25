# Kerrlab Homelab 🚀

A robust, GitOps-managed Kubernetes homelab running on **Talos OS**. This repository serves as the single source of truth for the entire cluster configuration, utilizing a modern cloud-native stack to host a wide variety of personal services, media applications, and home automation tools.

## 🏗️ Architecture & Core Components

The cluster is built on a foundation of security, automation, and high availability.

### Base Infrastructure
- **Operating System:** [Talos OS](https://www.talos.dev/) - A secure, immutable, and minimal Linux distribution built for Kubernetes.
- **GitOps Engine:** [ArgoCD](https://argoproj.github.io/cd/) - Automatically synchronizes the cluster state with this repository.
- **Networking (CNI):** [Cilium](https://cilium.io/) - Advanced networking with BGP peering, IP address management (IPAM), and network policies.
- **Ingress Controller:** [Traefik](https://doc.traefik.io/traefik/) - Gateway API and Ingress management with automatic TLS.

### Security & Identity
- **Secrets Management:** [External Secrets Operator](https://external-secrets.io/) - Integrates with a Vaultwarden backend to securely inject secrets without hardcoding them in Git.
- **Certificate Management:** [Cert-Manager](https://cert-manager.io/) - Automated SSL/TLS certificates via Cloudflare (DNS-01 challenge) and ZeroSSL.
- **Authentication:** [Authelia](https://www.authelia.com/) - Single Sign-On (SSO) with OpenID Connect (OIDC) and 2FA protection for all internal services.
- **VPN:** [Tailscale](https://tailscale.com/) - Secure remote access to the cluster and internal services.

### Storage Strategy
- **Synology CSI:** Direct integration with Synology NAS for high-performance persistent storage via iSCSI.
- **Longhorn:** Distributed block storage for cluster-native data resiliency.
- **Databases:** Automated management of PostgreSQL (CloudNativePG) and Redis instances.

---

## 📱 Application Gallery

The cluster hosts a diverse ecosystem of applications, organized by domain:

### 🎬 Media & Entertainment
- **Streaming:** Plex Media Server (with Intel QuickSync hardware transcoding).
- **Automation:** Radarr, Sonarr, Bazarr, Prowlarr, and Overseerr.
- **Management:** Kometa (Plex Meta Manager), Tautulli, and Posterizarr.
- **Downloaders:** qBittorrent, Autobrr, and Unpackerr.

### 🏠 Home & IoT
- **Automation:** Home Assistant, Zigbee2MQTT, and go2rtc.
- **Management:** Mealie (Recipe Manager), Bar Assistant (Cocktail management), and Wedding Share.
- **Connectivity:** Matter Server and MQTT broker.

### 🛠️ Developer & Power Tools
- **Automation:** n8n, Renovate (for automated dependency updates).
- **Utilities:** IT-Tools, Excalidraw, Speedtest, and Mermaid.
- **Communication:** IRC client and ntfy for push notifications.

---

## 📂 Repository Structure

```text
├── apps/
│   ├── cluster-core/       # Foundation (Cilium, Cert-Manager, Traefik)
│   ├── cluster-addons/     # Common services (Authelia, OAuth-Proxy)
│   ├── gitops/             # ArgoCD & Renovate configuration
│   ├── storage/            # Synology CSI, Longhorn, Databases
│   ├── monitoring/         # Prometheus, Metrics-Server, Uptime
│   └── applications/       # End-user services (Media, Home, IoT, Games)
├── talos/
│   └── cluster-config/     # Talos machine configurations and backup scripts
└── README.md
```

---

## 🔧 Maintenance & Management

### Automated Updates
[Renovate](https://www.whitesource.com/free-developer-tools/renovate/) is configured to automatically monitor this repository and create Pull Requests for:
- Docker image updates
- Helm chart version increments
- Talos OS and Kubernetes version upgrades

### Hardware Acceleration
The cluster utilizes Intel GPU hardware for media transcoding:
- **NFD (Node Feature Discovery):** Detects hardware capabilities.
- **Intel Device Plugin:** Exposes the i915 GPU to containers for Plex and other media tools.

### Backup Strategy
Cluster state and critical configurations are backed up using the scripts provided in `talos/cluster-config/`, ensuring quick recovery in the event of hardware failure.

---
*Maintained with ❤️ by vehkiya*
