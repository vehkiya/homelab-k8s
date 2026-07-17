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

Before pushing any changes or finalizing a pull request, the agent **MUST** run the validation and linting pipeline to verify manifest syntax, schemas, and security practices.

### Validation Sequence
1.  **YAML Linting:** Check all modified YAML files for syntax and formatting.
    ```bash
    yamllint <file.yaml>
    ```
2.  **Kubernetes Best Practices (Kube-Linter):** Audit manifests against security policies.
    ```bash
    kube-linter lint <file.yaml>
    ```
3.  **Kubernetes Conformity (Kubeconform):** Validate manifests against Kubernetes API schemas.
    ```bash
    kubeconform -strict -summary <file.yaml>
    ```

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


