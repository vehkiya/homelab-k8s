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
*   **Plaintext Secrets:** Passwords, API tokens, database connection strings, or Auth credentials.
*   **Thread Datasets:** Active dataset keys, pre-shared keys (PSKc), or network keys (e.g., raw TLVs). These must be managed via Vault/ExternalSecrets.
*   **Private Keys & Certificates:** SSL/TLS private keys, SSH keys, or certificate files (e.g. `-----BEGIN ...`).
*   **Decrypted Vault Assets:** Raw data fetched from Vaultwarden or config files that should remain git-ignored.

### Remediation Process
If any sensitive data is discovered in the audit:
1.  **Unstage the file:** Immediately unstage the affected file(s) (`git restore --staged <file>`).
2.  **Abort the operation:** Cancel the commit or push operation immediately. Do not attempt to proceed.
3.  **Flag for human review:** Stop all automated edits or Git actions, report the specific leak details to the user, and wait for human review/remediation.

---

## 2. Mandatory Pod Resource Limits (CRITICAL)

To prevent resource exhaustion, noisy neighbor issues, and out-of-memory kills, **every pod container specification** (including init containers where appropriate) MUST explicitly set both resource requests and limits.

### Configuration Policy
*   **CPU:** Must specify both `requests.cpu` and `limits.cpu`.
*   **Memory:** Must specify both `requests.memory` and `limits.memory`.

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
*   **No `:latest` or Generic Tags:** All container image declarations MUST be pinned to specific semantic tags (e.g., `v1.2.7`) or specific image digests (SHAs).
*   **Renovate Compatibility:** Always specify tags in a format that can be easily parsed and updated by Renovate.

---

## 5. Secret Hygiene & Vaultwarden Integration

To ensure maximum security and prevent plaintext secrets from entering the repository:
*   **No Base64 Standard Secrets:** Standard Kubernetes `Secret` manifests containing raw base64 data are strictly prohibited.
*   **ExternalSecrets Only:** All sensitive variables, keys, and credentials must be declared using `ExternalSecret` resources that fetch target values dynamically from Vaultwarden (or the cluster's default `SecretStore`).

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
