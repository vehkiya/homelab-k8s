# Domain: Monitoring & Observability

Scope: `apps/system/observability/`. All Applications land in namespace `observability`
unless the app's `kustomization.yaml` overrides it.

## Apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| prometheus | `apps/system/observability/prometheus` | observability | - | Helm, HTTPRoute, CNP, ExtSecret, PromRule | kube-prometheus-stack: Prometheus, Alertmanager, Grafana (`grafana.kerrlab.app`), operator, node-exporter, kube-state-metrics. Provides the `ServiceMonitor`/`PodMonitor`/`PrometheusRule` CRDs. Values in `values/values.yaml`; volumes on StorageClass `longhorn`. Secrets: OpenBao `observability/grafana`, `telegram/bots`, `telegram/channels` (alert delivery) |
| metrics-server | `apps/system/observability/metrics-server` | kube-system | - | Helm, CNP | Resource metrics API for HPA and `kubectl top` |
| headlamp | `apps/system/observability/headlamp` | observability | - | Helm, HTTPRoute, CNP, ExtSecret | Cluster UI at `cluster.kerrlab.app`; OIDC client `headlamp` (admin only) |
| spegel | `apps/system/observability/spegel` | spegel | - | Helm, CNP | Node-local registry mirror (P2P image cache) |
| uptime | `apps/system/observability/uptime` | observability | - | HTTPRoute, CNP, PVC, PV | Uptime Kuma. Excluded from the ApplicationSet: not deployed |

## Hardware telemetry

| Exporter | Where |
|---|---|
| node-exporter (CPU, memory, disk, NIC per node) | Part of the kube-prometheus-stack chart in `apps/system/observability/prometheus` |
| kube-state-metrics (plus custom-resource metrics for edge alerts) | Same chart; configured in `values/values.yaml` |
| Intel GPU driver health monitoring | Enabled in `apps/system/hardware/intel-gpu-resource-driver/kustomization.yaml` |

No `smartctl-exporter` or other disk-health exporter is deployed. Node inventory and
extensions: nodes-and-hardware.md.

## Alert rules (`PrometheusRule`)

| File | Covers |
|---|---|
| `apps/system/observability/prometheus/critical-alerts.yaml` | Cluster-level critical alerts |
| `apps/system/observability/prometheus/cilium-alerts.yaml` | Cilium health, rejected policies (`CiliumPolicyInvalid`) |
| `apps/system/observability/prometheus/argocd-alerts.yaml` | ArgoCD sync/health |
| `apps/system/observability/prometheus/envoy-gateway-alerts.yaml` | Envoy Gateway edge |
| `apps/system/security/crowdsec/blocklist-mirror-alerts.yaml` | CrowdSec blocklist mirror (lives with its app) |

New alerts for a platform component go next to the others in the prometheus directory and
into its `kustomization.yaml`; app-specific rules stay in the app's directory.

## Scrape targets (`ServiceMonitor` / `PodMonitor`)

| Target | Kind | File |
|---|---|---|
| Envoy Gateway controller | ServiceMonitor | `apps/system/networking/envoy-gateway/servicemonitor.yaml` |
| Envoy proxy fleets | PodMonitor | `apps/system/networking/envoy-gateway/podmonitor.yaml` |
| Traefik | ServiceMonitor | `apps/system/networking/traefik/servicemonitor.yaml` |
| Authelia | ServiceMonitor | `apps/system/security/authelia/servicemonitor.yaml` |
| CrowdSec blocklist mirror | ServiceMonitor | `apps/system/security/crowdsec/blocklist-mirror-servicemonitor.yaml` |
| CrowdSec Envoy bouncer | ServiceMonitor | `apps/system/security/crowdsec/envoy-bouncer-servicemonitor.yaml` |
| MQTT exporter (Zigbee) | PodMonitor | `apps/workloads/iot/mqtt/exporter.yaml` |
| OTBR agent (Thread) | PodMonitor | `apps/workloads/iot/otbr/podmonitor.yaml` |

Helm-managed components (for example cilium, external-secrets, crowdsec) enable their
monitors through chart values in their own directories.

## Adding a scrape target (three edits)

1. `ServiceMonitor` or `PodMonitor` in the app's directory, listed in its `kustomization.yaml`.
2. Egress from Prometheus to the target's pods and metrics port:
   `apps/system/observability/prometheus/network-policies.yaml`.
3. Ingress in the app's own `CiliumNetworkPolicy` from
   `k8s:io.kubernetes.pod.namespace: observability` + `app.kubernetes.io/name: prometheus`
   on the metrics port. Reference: `apps/workloads/iot/otbr/network-policy.yaml`.

Under default-deny, a monitor without steps 2 and 3 shows the target as down.

## Grafana dashboards

Dashboards are ConfigMaps labeled `grafana_dashboard: "1"`, generated with
`configMapGenerator` from JSON in a `dashboards` directory next to the owning app:

| Owner | Path |
|---|---|
| Cilium | `apps/bootstrap/cilium/dashboards` |
| External Secrets | `apps/bootstrap/external-secrets/dashboards` |
| Envoy Gateway | `apps/system/networking/envoy-gateway/dashboards` |
| cert-manager | `apps/system/networking/cert-manager/dashboards` |
| Traefik | `apps/system/networking/traefik/dashboards` |
| CrowdSec | `apps/system/security/crowdsec/dashboards` |
| Cross-app (IoT communication) | `apps/system/observability/prometheus/dashboards` |

Spegel wires its dashboard in `apps/system/observability/spegel/kustomization.yaml`.
Grafana customisation: `patch-grafana-deployment.yaml` and `patch-grafana-service.yaml` in the
prometheus directory.
