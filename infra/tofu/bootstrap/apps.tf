locals {
  root_dir = abspath("${path.module}/../../..")

  cilium_dir           = "${local.root_dir}/apps/bootstrap/cilium"
  coredns_dir          = "${local.root_dir}/apps/bootstrap/coredns"
  external_secrets_dir = "${local.root_dir}/apps/bootstrap/external-secrets"
  argocd_dir           = "${local.root_dir}/apps/bootstrap/argocd"
  app_of_apps_file     = "${local.root_dir}/apps/gitops/app-of-apps/bootstrap.yaml"

  cilium_files = [for f in fileset(local.cilium_dir, "**") : "${local.cilium_dir}/${f}"]
  cilium_hash  = sha256(join("", [for f in local.cilium_files : filesha256(f)]))

  coredns_files = [for f in fileset(local.coredns_dir, "**") : "${local.coredns_dir}/${f}"]
  coredns_hash  = sha256(join("", [for f in local.coredns_files : filesha256(f)]))

  external_secrets_files = [for f in fileset(local.external_secrets_dir, "**") : "${local.external_secrets_dir}/${f}"]
  external_secrets_hash  = sha256(join("", [for f in local.external_secrets_files : filesha256(f)]))

  argocd_files = [for f in fileset(local.argocd_dir, "**") : "${local.argocd_dir}/${f}"]
  argocd_hash  = sha256(join("", [for f in local.argocd_files : filesha256(f)]))
}

# 1. Deploy Cilium CNI
resource "terraform_data" "cilium" {
  input = local.cilium_hash

  triggers_replace = [
    local.cilium_hash
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
    command = <<-EOT
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

  input = local.coredns_hash

  triggers_replace = [
    local.coredns_hash
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
    command = <<-EOT
      echo "[*] Applying CoreDNS from ${local.coredns_dir}..."
      kustomize build --enable-helm "${local.coredns_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for CoreDNS DaemonSet rollout..."
      kubectl rollout status ds/coredns -n kube-system --timeout=300s
    EOT
  }
}

# 3. Deploy External Secrets Operator
resource "terraform_data" "external_secrets" {
  depends_on = [
    terraform_data.coredns,
    kubernetes_secret.vaultwarden_credentials
  ]

  input = local.external_secrets_hash

  triggers_replace = [
    local.external_secrets_hash
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
    command = <<-EOT
      echo "[*] Applying External Secrets Operator from ${local.external_secrets_dir}..."
      kustomize build --enable-helm "${local.external_secrets_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for External Secrets deployment rollout..."
      kubectl rollout status deployment/external-secrets -n external-secrets --timeout=300s
    EOT
  }
}

# 4. Deploy ArgoCD
resource "terraform_data" "argocd" {
  depends_on = [terraform_data.external_secrets]

  input = local.argocd_hash

  triggers_replace = [
    local.argocd_hash
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
    command = <<-EOT
      echo "[*] Applying ArgoCD from ${local.argocd_dir}..."
      kustomize build --enable-helm "${local.argocd_dir}" | kubectl apply --server-side --force-conflicts -f -
      echo "[*] Waiting for ArgoCD server rollout..."
      kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
    EOT
  }
}

# 5. Connect ArgoCD Root Bootstrap ApplicationSet
resource "terraform_data" "bootstrap_app_of_apps" {
  depends_on = [terraform_data.argocd]

  triggers_replace = [
    filesha256(local.app_of_apps_file)
  ]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
    command = <<-EOT
      echo "[*] Applying Bootstrap ApplicationSet to ArgoCD..."
      kubectl apply -f "${local.app_of_apps_file}"
    EOT
  }
}
