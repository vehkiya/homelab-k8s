# Agent Guidelines & Rules

This document outlines strict operational rules for AI coding assistants working in this repository.

---

## 1. Zero-Credential Leakage Policy (CRITICAL)

Before executing any `git commit` or `git push` operations, the agent **MUST** audit all staged changes to prevent the accidental leakage of sensitive credentials, keys, or configuration tokens.

### Audit Workflow

Before performing any commit, run:

```bash
git diff --cached
```

Review the diff output to ensure it does **NOT** contain any of the following:

* **Plaintext Secrets:** Passwords, API tokens, database connection strings, or Auth credentials.
* **Thread Datasets:** Active dataset keys, pre-shared keys (PSKc), or network keys (e.g., raw TLVs). These must be managed via Vault/ExternalSecrets.
* **Private Keys & Certificates:** SSL/TLS private keys, SSH keys, or certificate files (e.g. `-----BEGIN ...`).
* **Decrypted Vault Assets:** Raw data fetched from OpenBao/vault or config files that should remain git-ignored.

### Remediation Process

If any sensitive data is discovered in the audit:

1. **Unstage the file:** Immediately unstage the affected file(s) (`git restore --staged <file>`).
2. **Abort the operation:** Cancel the commit or push operation immediately. Do not attempt to proceed.
3. **Flag for human review:** Stop all automated edits or Git actions, report the specific leak details to the user, and wait for human review/remediation.

---

## 2. Mandatory Pod Resource Limits (CRITICAL)

To prevent resource exhaustion, noisy neighbor issues, and out-of-memory kills, **every pod container specification** (including init containers where appropriate) MUST explicitly set both resource requests and limits.

### Configuration Policy

* **CPU:** Must specify both `requests.cpu` and `limits.cpu`.
* **Memory:** Must specify both `requests.memory` and `limits.memory`.

Example:

```yaml
resources:
  requests:
    cpu: "10m"
    memory: "64Mi"
  limits:
    cpu: "250m"
    memory: "128Mi"
```

---

## 3. Pre-Push Validation & Linting Workflow

Before pushing any changes or finalizing a pull request, the agent **MUST** run the validation and linting pipeline matching the GitHub Actions CI (`.github/workflows/ci.yaml`):

### Validation Sequence

1. **Locate and Render Kustomize Layers:**
   Locate all directories containing a `kustomization.yaml` that are closest parents to the modified files. For each directory, render the layer using Kustomize:

   ```bash
   kustomize build <layer-directory> --enable-helm > built.yaml
   ```

2. **YAML Linting:**
   Check the modified YAML files (and the rendered `built.yaml`) for syntax and formatting:

   ```bash
   yamllint <file.yaml>
   ```

3. **Kubernetes Conformity (Kubeconform):**
   Validate the rendered manifest structure using `kubeconform`. Ensure you ignore missing CRD schemas and skip validations for `Secret` and `SealedSecret` resources:

   ```bash
   kubeconform -summary -ignore-missing-schemas -strict -skip "Secret,SealedSecret" -cache ~/.cache/kubeconform built.yaml
   ```

4. **Kubernetes Best Practices (Kube-Linter):**
   Audit the rendered manifests against security policies:

   ```bash
   kube-linter lint built.yaml
   ```

   *(Optional: If the layer uses Helm or remote sources, use `yq` to annotate Pod-bearing or Service resources with `"kube-linter.io/ignore-all" = "true"` to avoid upstream resource configuration alerts).*

---

## 4. Strict Image Tag Pinning Policy

To ensure reproducible deployments and compatibility with automated dependency managers (like Renovate):

* **No `:latest` or Generic Tags:** All container image declarations MUST be pinned to specific semantic tags (e.g., `v1.2.7`) or specific image digests (SHAs).
* **Renovate Compatibility:** Always specify tags in a format that can be easily parsed and updated by Renovate.

---

## 5. Secret Hygiene & OpenBao Integration

To ensure maximum security and prevent plaintext secrets from entering the repository:

* **No Base64 Standard Secrets:** Standard Kubernetes `Secret` manifests containing raw base64 data are strictly prohibited.
* **ExternalSecrets Only:** All sensitive variables, keys, and credentials must be declared using `ExternalSecret` resources that fetch target values dynamically from OpenBao (via the `openbao-store` `ClusterSecretStore`).

---

## 6. Network Policy & Zero-Trust Architecture (Cilium)

The cluster operates on a **default-deny network policy** baseline. To allow workload communication, you must define explicit ingress/egress rules using `CiliumNetworkPolicy` resources.

### Pre-configured Global Clusterwide Policies

Certain system-wide connections are already enabled globally in `apps/bootstrap/cilium/global-network-policies.yaml`. You do **not** need to redefine rules for these in local workload policies:

1. **DNS Resolution:** Egress to CoreDNS (port `53` UDP/TCP in `kube-system`) is allowed for all endpoints cluster-wide.
2. **Health Probes:** Ingress communication from the `host` and `health` entities is allowed for kubelet liveness/readiness probes.
3. **Traefik Ingress:**
   * Ingress from Traefik to any pod labeled with `networking/expose-web-ui: "true"` targeting a named port `"web-ui"` is automatically allowed.
   * Ingress from Traefik to any pod labeled with `networking/expose-http-api: "true"` targeting a named port `"http-api"` is automatically allowed.

### Named Port Ingress Mapping Example

For a workload to utilize the global Traefik ingress policies:

1. The **Pod template labels** must include `networking/expose-web-ui: "true"` (or `networking/expose-http-api: "true"`).
2. The **Pod container ports** must have a named port `"web-ui"` (or `"http-api"`).
3. The corresponding **Service** and **HTTPRoute** must target this `"web-ui"` (or `"http-api"`) named port.

Example configuration flow:

```yaml
# 1. Pod Spec (deployment.yaml)
spec:
  template:
    metadata:
      labels:
        networking/expose-web-ui: "true" # Matches the global policy
    spec:
      containers:
        - name: app
          ports:
            - name: web-ui # Named port allowed by global policy
              containerPort: 8080
              protocol: TCP

# 2. Service Spec (service.yaml)
spec:
  ports:
    - name: web-ui
      port: 80
      targetPort: web-ui # References the container's named port

# 3. Gateway Route Spec (http-route.yaml)
spec:
  rules:
    - backendRefs:
        - name: app-service
          port: 80 # Routes through the service to targetPort
```

---

## 7. Temporary ArgoCD Autosync Disabling for Debugging & Testing

When testing or debugging manual cluster edits (e.g. via `kubectl apply`), ArgoCD's `selfHeal` will automatically overwrite your test changes. To temporarily disable autosync during a debugging session:

1. **Locate the App-of-Apps Manifest:**
   Find the matching ApplicationSet in `apps/gitops/app-of-apps/` (e.g., `workloads-iot.yaml`, `workloads-media.yaml`).
2. **Comment out `automated` Sync Policy:**

   ```yaml
         syncPolicy:
           # automated:
           #   prune: true
           #   selfHeal: true
   ```

3. **Apply to Cluster:**

   ```bash
   kubectl apply -f apps/gitops/app-of-apps/<app-name>.yaml
   ```

4. **Perform Testing:** Run your `kubectl apply` commands for testing.
5. **Revert Local File:** Revert the `apps/gitops/app-of-apps/<app-name>.yaml` file back to its un-commented state so git remains clean.
6. **Post-Merge Cleanup (Only Upon Explicit User Confirmation):**
   Once testing is complete, the PR is merged, and the user explicitly requests to finalize/resume:
   * Switch to `master` and pull the latest changes (`git checkout master && git pull origin master`).
   * Re-apply the `app-of-apps` manifest (`kubectl apply -f apps/gitops/app-of-apps/<app-name>.yaml`) to restore ArgoCD automated sync in the cluster.

---

## 8. Infrastructure Changes & OpenTofu Workflow

Bare-metal node configurations and foundational Day-0 cluster bootstrapping are managed declaratively using OpenTofu in `infra/tofu/`.

### Architecture & Layer Boundaries

* **Layer 1 (`infra/tofu/talos/`):** Manages bare-metal Talos Linux node configurations (`lab-1`, `lab-2`, `lab-3`, `worker-1`), kernel parameters, hardware extensions via Talos Image Factory schematics (`image-factory-parameters.yaml`), network interfaces/VLANs, and automated offline disaster-recovery backups (`_output/`).
* **Layer 2 (`infra/tofu/bootstrap/`):** Bridges bare metal to GitOps. Manages the Day-0 `vaultwarden-credentials` secret (with `argocd.argoproj.io/sync-options: Prune=false` and `helm.sh/resource-policy: keep`), Cilium CNI, CoreDNS, External Secrets Operator, and ArgoCD root bootstrap enrollment.

### State & Secret Hygiene in Infrastructure

* **Client-Side State Encryption:** Both layers use remote S3 backend storage on NAS SeaweedFS with client-side AES-GCM encryption (`tofu_encryption_passphrase`).
* **Never Commit State or Credentials:** `terraform.tfvars`, `*.tfvars.json`, `*.tfstate`, and `_output/` must remain git-ignored. Never stage or commit unencrypted state, credentials, or passphrases.
* **Variable Hygiene:** When adding or modifying input variables in `variables.tf`, always update the corresponding `terraform.tfvars.example` with safe, placeholder defaults.

### Modern Talos Configuration Standards

* **No Deprecated `.machine.files`:** Use dedicated Talos configuration documents:
  * `kind: HostnameConfig` for node hostnames.
  * `kind: CRICustomizationConfig` for container runtime settings (e.g. `20-customization`).
  * `kind: EtcFileConfig` for system configurations (e.g. `nfsmount.conf`).
* **Schematic Pinning:** When adding Talos system extensions, update `image-factory-parameters.yaml` so the schematic ID is dynamically computed and pinned.

### Validation & Testing Workflow

Before committing any changes under `infra/`:

1. **Format Code:**
   Ensure all OpenTofu configuration files conform to standard formatting:

   ```bash
   tofu fmt -check -recursive infra/tofu
   ```

   To automatically format:

   ```bash
   tofu fmt -recursive infra/tofu
   ```

2. **Offline Validation (No Backend/Credentials Required):**
   For any modified layer directory (e.g., `infra/tofu/talos`, `infra/tofu/bootstrap`):

   ```bash
   tofu -chdir=<layer-directory> init -backend=false
   tofu -chdir=<layer-directory> validate
   ```

3. **Execution Safety & Live Testing:**
   * Always run `tofu plan` first to review prospective diffs before proposing or executing an apply.
   * Do not run `tofu apply -auto-approve` without explicit human authorization, especially on bare-metal control plane nodes.
   * Upgrades to Talos OS or Kubernetes must be coordinated sequentially node-by-node, verifying etcd health and node readiness between updates.

---

## 9. Identity & Access Management (LLDAP & Authelia OIDC / Forward-Auth)

Authentication and authorization across the cluster are centrally backed by **LLDAP** (Lightweight LDAP) and brokered via **Authelia** (OIDC Identity Provider and Traefik Forward-Auth).

### Group Taxonomy & Lifecycle Tiers

The cluster operates on a hybrid two-layer RBAC model consisting of **Global Lifecycle Personas** and **Scoped App Entitlements**:

1. **`administrators` (Platform Root):**
   * Infrastructure, OpenBao, Kubernetes `cluster-admin` (Headlamp), and Authelia root access.
2. **`privileged-users` (Global Power Users / Service Admins):**
   * Elevated admin/editor/superuser permissions inside workloads that support RBAC (e.g. RomM editor, Jellyfin admin).
   * Authorized to access backend infrastructure and media downloaders (*arr stack, Prowlarr, qBittorrent) via Forward-Auth.
3. **`users` (Standard Homelab Citizens):**
   * Default access to all general consumer workloads across `*.kerrlab.app` (recipes, media playback, Kaneo, etc.).
4. **`guests` (Default Unprivileged Tier):**
   * Default baseline group assigned upon new account creation. Denied access everywhere by default (`default_policy: deny`), except explicitly designated public/guest services (e.g., Bar Assistant).
5. **`app-<service>-users` (Scoped Per-App Guest Entitlements):**
   * Grants a `guest` user access to a single specific application (e.g., `app-mealie-users`, `app-kaneo-users`, `app-romm-users`) without promoting them to global `users`.

### OIDC Client Registration Standards (Authelia)

When integrating a workload via native OIDC in `apps/system/security/authelia/templates/configuration.yaml`:

1. **Secret Management:**
   * Generate an OIDC client secret and store it in OpenBao at `security/authelia/oidc-clients` under the key `<CLIENT>_SECRET`.
   * Add the property reference to [`apps/system/security/authelia/oidc-secrets.yaml`](apps/system/security/authelia/oidc-secrets.yaml).
   * In the target workload, inject the secret using an `ExternalSecret` pointing to `tools/<app>` or `security/authelia/oidc-clients`.
2. **Authorization Policies:**
   * **Admin Only:** Use `admin_only_policy` (e.g. OpenBao, Headlamp).
   * **Privileged Only:** Use `privileged_users_policy` (or a dedicated policy like `autobrr_policy`).
   * **Standard Workloads:** Create a dedicated policy (e.g. `<service>_policy`) that accepts `administrators`, `privileged-users`, `users`, and `app-<service>-users`.
3. **Claims & Scopes:**
   * Declare scopes: `openid`, `profile`, `email`, `groups` (and `offline_access` when refresh tokens are required).
   * Use `claims_policy: with_groups` whenever the workload consumes groups for in-app role mappings.

### Workload Role Mapping Hygiene

* **Do Not Restrict User Groups in App Config:** Avoid hardcoding single group restrictions inside app manifests (e.g. `OIDC_USER_GROUP: "users"`), as this rejects guests holding `app-<service>-users`. Let Authelia gate admission at the SSO layer.
* **Map Elevated Groups:** Map `administrators` to in-app Admin/Owner, and `privileged-users` to in-app Admin/Editor where supported.

### Forward-Auth Configuration Standards

* Forward-auth services utilize the Traefik middleware `authelia-forward-auth`.
* In Authelia's `access_control.rules`:
  * Specific domain rules **MUST** be placed before the catch-all `*.kerrlab.app`.
  * Administrative, torrent, and media management tools (`prowlarr`, `qbittorrent`, `sonarr`, `radarr`, `bazarr`, `posterizarr`) **MUST** be restricted to `administrators` and `privileged-users`.
  * Services supporting guest access must explicitly list their `group:app-<service>-users`.
