locals {
  root_dir = abspath("${path.module}/../../..")

  cilium_dir           = "${local.root_dir}/apps/bootstrap/cilium"
  coredns_dir          = "${local.root_dir}/apps/bootstrap/coredns"
  namespaces_dir       = "${local.root_dir}/apps/bootstrap/namespaces"
  external_secrets_dir = "${local.root_dir}/apps/bootstrap/external-secrets"
  argocd_dir           = "${local.root_dir}/apps/bootstrap/argocd"
  app_of_apps_file     = "${local.root_dir}/apps/gitops/app-of-apps/bootstrap.yaml"

  # Hash only git-tracked inputs. Helm chart caches (charts/) and the git-ignored
  # vaultwarden-credentials.yaml differ per checkout and must not trigger re-applies.
  hash_exclude_regex = "^(charts/|vaultwarden-credentials\\.yaml$)"

  component_dirs = {
    cilium           = local.cilium_dir
    coredns          = local.coredns_dir
    namespaces       = local.namespaces_dir
    external_secrets = local.external_secrets_dir
    argocd           = local.argocd_dir
  }

  component_hashes = {
    for name, dir in local.component_dirs : name => sha256(join("", [
      for f in fileset(dir, "**") : filesha256("${dir}/${f}") if !can(regex(local.hash_exclude_regex, f))
    ]))
  }
}

# 1. Deploy Cilium CNI
resource "terraform_data" "cilium" {
  input = local.component_hashes.cilium

  triggers_replace = [
    local.component_hashes.cilium
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
      SKIP_APPLY = tostring(var.skip_component_apply)
    }
    command = <<-EOT
      set -eo pipefail
      if [ "$SKIP_APPLY" = "true" ]; then echo "[*] skip_component_apply=true, recording state only"; exit 0; fi
      echo "[*] Applying Cilium CNI from ${local.cilium_dir}..."
      kustomize build --enable-helm "${local.cilium_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for Cilium DaemonSet rollout..."
      kubectl rollout status ds/cilium -n kube-system --timeout=300s
    EOT
  }
}

# 2. Deploy CoreDNS
resource "terraform_data" "coredns" {
  depends_on = [terraform_data.cilium]

  input = local.component_hashes.coredns

  triggers_replace = [
    local.component_hashes.coredns
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
      SKIP_APPLY = tostring(var.skip_component_apply)
    }
    command = <<-EOT
      set -eo pipefail
      if [ "$SKIP_APPLY" = "true" ]; then echo "[*] skip_component_apply=true, recording state only"; exit 0; fi
      echo "[*] Applying CoreDNS from ${local.coredns_dir}..."
      kustomize build --enable-helm "${local.coredns_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for CoreDNS DaemonSet rollout..."
      kubectl rollout status ds/coredns -n kube-system --timeout=300s
    EOT
  }
}

# 3. Deploy Namespaces
resource "terraform_data" "namespaces" {
  depends_on = [terraform_data.coredns]

  input = local.component_hashes.namespaces

  triggers_replace = [
    local.component_hashes.namespaces
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
      SKIP_APPLY = tostring(var.skip_component_apply)
    }
    command = <<-EOT
      set -eo pipefail
      if [ "$SKIP_APPLY" = "true" ]; then echo "[*] skip_component_apply=true, recording state only"; exit 0; fi
      echo "[*] Applying Namespaces from ${local.namespaces_dir}..."
      kustomize build --enable-helm "${local.namespaces_dir}" | kubectl apply --server-side --force-conflicts -f -
    EOT
  }
}

# 4. Deploy External Secrets Operator
resource "terraform_data" "external_secrets" {
  depends_on = [
    terraform_data.coredns,
    terraform_data.namespaces,
    kubernetes_secret.vaultwarden_credentials
  ]

  input = local.component_hashes.external_secrets

  triggers_replace = [
    local.component_hashes.external_secrets
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
      SKIP_APPLY = tostring(var.skip_component_apply)
    }
    command = <<-EOT
      set -eo pipefail
      if [ "$SKIP_APPLY" = "true" ]; then echo "[*] skip_component_apply=true, recording state only"; exit 0; fi
      echo "[*] Applying External Secrets Operator from ${local.external_secrets_dir}..."
      kustomize build --enable-helm "${local.external_secrets_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for External Secrets deployment rollout..."
      kubectl rollout status deployment/external-secrets -n external-secrets --timeout=300s
    EOT
  }
}

# 5. Deploy ArgoCD
resource "terraform_data" "argocd" {
  depends_on = [
    terraform_data.external_secrets,
    terraform_data.namespaces
  ]

  input = local.component_hashes.argocd

  triggers_replace = [
    local.component_hashes.argocd
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
      SKIP_APPLY = tostring(var.skip_component_apply)
    }
    command = <<-EOT
      set -eo pipefail
      if [ "$SKIP_APPLY" = "true" ]; then echo "[*] skip_component_apply=true, recording state only"; exit 0; fi
      echo "[*] Applying ArgoCD from ${local.argocd_dir}..."
      kustomize build --enable-helm "${local.argocd_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for ArgoCD server rollout..."
      kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
    EOT
  }
}

# 6. Connect ArgoCD Root Bootstrap ApplicationSet
resource "terraform_data" "bootstrap_app_of_apps" {
  depends_on = [terraform_data.argocd]

  triggers_replace = [
    filesha256(local.app_of_apps_file)
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
      SKIP_APPLY = tostring(var.skip_component_apply)
    }
    command = <<-EOT
      set -eo pipefail
      if [ "$SKIP_APPLY" = "true" ]; then echo "[*] skip_component_apply=true, recording state only"; exit 0; fi
      echo "[*] Applying Bootstrap ApplicationSet to ArgoCD..."
      kubectl apply -f "${local.app_of_apps_file}"
    EOT
  }
}
