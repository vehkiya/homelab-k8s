# Domain: Nodes & Hardware

Scope: `infra/tofu/talos/` (Layer 1, rules in AGENTS.md section 8), hardware drivers in
`apps/system/hardware/`, runtime classes in `apps/bootstrap/runtime`.

## Node topology

| Role | Nodes | Defined in | Scheduling |
|---|---|---|---|
| Control plane | `lab-1`, `lab-2`, `lab-3` | `var.nodes` (shape in `infra/tofu/talos/variables.tf`, sample in `infra/tofu/talos/terraform.tfvars.example`; real values in git-ignored tfvars) | Schedulable for workloads (`allowSchedulingOnControlPlanes`), no taints |
| Worker | `worker-1` | same | No taints; the only `node-type: performance` node |

## Node labels set by Talos

| Label | On | Consumers |
|---|---|---|
| `topology.kubernetes.io/zone: <hostname>` | all nodes | One zone per node, so zone-aware routing prefers same-node backends |
| `intel.feature.node.kubernetes.io/gpu: "true"` | all nodes | Marks GPU-capable nodes |
| `node-type: "performance"` | worker | Affinity: plex, jellyfin, minecraft, satisfactory, n8n, koshin, renovate (required or preferred; nodecast-tv avoids it). Also the node selector of the `performance-lb-l2` policy in `apps/bootstrap/cilium/l2-announcements.yaml` |
| `node.longhorn.io/create-default-disk: "true"` | worker | Longhorn default disk creation |
| `node.kubernetes.io/exclude-from-external-load-balancers` | control plane | Standard Kubernetes label |

Templates: `infra/tofu/talos/templates` (`common`, `controlplane`, `worker`). Per-node wiring:
`infra/tofu/talos/nodes.tf`. Never print rendered machine configs: they embed keys.

## Talos image: extensions, kernel args, modules

Schematic input: `infra/tofu/talos/image-factory-parameters.yaml`; the schematic ID is computed
in `infra/tofu/talos/schematic.tf`. Adding an extension means editing the parameters file.

| Extension | Needed by |
|---|---|
| `i915`, `xe` | Intel GPU kernel drivers: GPU resource driver, hardware transcoding |
| `intel-ucode` | CPU microcode |
| `mei` | Intel management engine interface |
| `iscsi-tools` | Longhorn and Synology CSI iSCSI volumes |
| `btrfs` | btrfs filesystem support (with the `btrfs` kernel module) |
| `crun`, `wasmedge` | Container runtimes behind the `RuntimeClass` objects below |
| `nut-client` | UPS shutdown signalling from the NAS |
| `realtek-firmware` | Realtek device firmware |

| Setting | Where |
|---|---|
| Kernel modules loaded on every node (`nbd`, `btrfs`) | `infra/tofu/talos/templates/common.yaml.tftpl` |
| Kernel args (IOMMU, CPU governor, NVMe timeouts) | `infra/tofu/talos/image-factory-parameters.yaml` and the role templates |
| Sysctls, kubelet and API server settings | the three templates |
| Node upgrade procedure (one node at a time) | `infra/tofu/talos/upgrade-node.sh` |
| etcd snapshot backups | `apps/system/storage/talos-backup` (see storage-and-databases.md) |

Not present: `util-linux-tools` extension, USB or serial passthrough. Zigbee and Thread radios
are network-attached and reached by IP (see z2mqtt and otbr in applications.md).

## Hardware and runtime apps

| App | Path | Namespace | Wave | Contracts | Upstream Dependencies & Notes |
|---|---|---|---|---|---|
| nfd | `apps/system/hardware/nfd` | node-feature-discovery | - | Helm, CNP | Node labels consumed by the GPU driver and scheduling rules |
| intel-gpu-resource-driver | `apps/system/hardware/intel-gpu-resource-driver` | intel-gpu-resource-driver | - | Helm, CNP | DRA driver for Intel GPUs. Consumers request it through `ResourceClaimTemplate` from `resource-claims.yaml` (plex, jellyfin, nodecast-tv) |
| runtime | `apps/bootstrap/runtime` | cluster-scoped | - | - | `RuntimeClass` objects (crun, WasmEdge); no kustomization, plain manifests |

## Resources advertised to pods

GPUs are exposed through **Dynamic Resource Allocation**, not a device plugin: there is no
`gpu.intel.com/i915` extended resource and nothing to put under `resources.limits`.

| Resource | Kind / name | Defined in | Consumers |
|---|---|---|---|
| Intel GPU | `DeviceClass` `gpu.intel.com` | installed by the driver chart in `apps/system/hardware/intel-gpu-resource-driver` | every claim below |
| Shared GPU claim | `ResourceClaim` `shared-intel-gpu-claim` (namespace `media`) | `apps/system/hardware/intel-gpu-resource-driver/resource-claims.yaml` | plex, jellyfin (`resourceClaimName`) |
| Per-pod GPU claim | `ResourceClaimTemplate` `intel-gpu-claim-template` (namespaces `media`, `iot`) | same file | nodecast-tv (`resourceClaimTemplateName`); the `iot` one has no consumer in git |
| PCI feature labels | NFD labels for display controllers and co-processors | `apps/system/hardware/nfd/values` | scheduling rules |
| Runtime classes | `RuntimeClass` `crun`, `wasmedge` | `apps/bootstrap/runtime` | opt-in per pod via `runtimeClassName`; no workload in git sets it |

A claim is namespaced: a GPU consumer in a new namespace needs its own claim or template
added to `resource-claims.yaml`.

## Hardware telemetry

node-exporter ships with the Prometheus stack; see monitoring.md.
