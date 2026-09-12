# OpenTofu Infrastructure as Code (Homelab K8s)

This directory contains the declarative Infrastructure-as-Code (IaC) configuration for the homelab Kubernetes cluster using **OpenTofu v1.12.6+**.

The architecture is decoupled into two distinct operational layers:

```
infra/tofu/
├── README.md
├── talos/           # Layer 1: Talos OS & Node Matrix
│   ├── backend.tf
│   ├── versions.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── secrets.tf
│   ├── nodes.tf
│   ├── backups.tf
│   ├── outputs.tf
│   ├── templates/
│   │   ├── common.yaml.tftpl
│   │   ├── controlplane.yaml.tftpl
│   │   └── worker.yaml.tftpl
│   └── _output/     # Auto-generated offline recovery artifacts (git-ignored)
│       ├── machineconfigs/
│       ├── talosconfig
│       └── kubeconfig
└── bootstrap/       # Layer 2: Day-0 Kubernetes Bootstrapping
    ├── backend.tf
    ├── versions.tf
    ├── variables.tf
    ├── main.tf
    ├── vaultwarden.tf
    ├── apps.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

---

## Remote State & Client-Side Encryption

Both layers utilize a remote S3 backend backed by NAS SeaweedFS (`https://s3.kerrlab.app`), stored in bucket `homelab-k8s-terraform`:

- **Layer 1 State Key:** `talos/cluster.tfstate`
- **Layer 2 State Key:** `bootstrap/k8s.tfstate`

### State & Plan Encryption

State files and execution plans are protected via **client-side AES-GCM encryption** using a PBKDF2 key derived from `tofu_encryption_passphrase`. Unencrypted state is never written to disk or the remote S3 bucket.

> **Security Note:** `terraform.tfvars`, `*.tfvars.json`, `*.tfstate`, and `_output/` are strictly git-ignored under the **Zero-Credential Leakage Policy**. Store your `tofu_encryption_passphrase` securely in Vaultwarden.

---

## Layer 1: Talos OS & Node Topology (`infra/tofu/talos/`)

Layer 1 manages bare-metal node configuration, kernel modules, network interfaces, VLANs, and Talos/Kubernetes version upgrades.

### Features:

- **Declarative Node Matrix:** All 4 nodes (`lab-1`, `lab-2`, `lab-3`, `worker-1`) declared in `variables.tf` / `terraform.tfvars`.
- **Modern Talos Manifest Documents:** Uses dedicated `kind: HostnameConfig` documents and v1.14+ HostDNS / admission control configurations.
- **Factory Schematic Pinning:** Computes and pins Talos Image Factory schematic ID for extensions (`iscsi-tools`, `nut-client`, `thunderbolt`, `realtek-r8152`).
- **Automated Offline Recovery Backups:** Every plan/apply renders and updates offline recovery artifacts in `_output/` with `0600` file permissions:
  - `_output/machineconfigs/<node>.yaml`
  - `_output/talosconfig`
  - `_output/kubeconfig`

### Quick Start:

```bash
cd infra/tofu/talos

# 1. Provide your encryption passphrase and node topology
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration

# 2. Initialize and verify
tofu init
tofu plan

# 3. Apply non-destructively
tofu apply
```

### Performing Node OS & Kubernetes Version Upgrades

To upgrade node OS or Kubernetes:

1. Update `talos_version` or `kubernetes_version` in `terraform.tfvars`.
2. Run `tofu plan` to review the rendered diffs.
3. Apply changes node-by-node or across the cluster with `tofu apply`.

---

## Layer 2: Day-0 Kubernetes Bootstrapping (`infra/tofu/bootstrap/`)

Layer 2 establishes the foundational Kubernetes cluster services and bridges the gap between bare-metal provisioning and continuous GitOps (ArgoCD).

### Components Managed:

1. **`vaultwarden-credentials` Secret:** Declared in `external-secrets` namespace with `argocd.argoproj.io/sync-options: Prune=false` and `helm.sh/resource-policy: keep` so ArgoCD never prunes the Day-0 bootstrap secret.
2. **Cilium CNI (`apps/bootstrap/cilium`):** Deploys Cilium via Kustomize + Helm, waits for `ds/cilium` rollout.
3. **CoreDNS (`apps/bootstrap/coredns`):** Deploys CoreDNS DaemonSet, waits for `ds/coredns` rollout.
4. **External Secrets Operator (`apps/bootstrap/external-secrets`):** Deploys ESO, waits for controller deployment rollout.
5. **ArgoCD (`apps/bootstrap/argocd`):** Deploys ArgoCD HA stack, waits for `argocd-server` rollout.
6. **Root Bootstrap ApplicationSet (`apps/gitops/app-of-apps/bootstrap.yaml`):** Enrolls bootstrap apps into ArgoCD continuous sync.

### Quick Start:

```bash
cd infra/tofu/bootstrap

# 1. Copy sample variables
cp terraform.tfvars.example terraform.tfvars

# 2. Populate credentials in terraform.tfvars:
# - tofu_encryption_passphrase
# - vaultwarden_client_id
# - vaultwarden_client_secret
# - vaultwarden_password

# 3. Initialize and plan
tofu init
tofu plan

# 4. Apply
tofu apply
```
