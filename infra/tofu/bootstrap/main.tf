locals {
  kubeconfig_path = var.kubeconfig_path != null ? var.kubeconfig_path : (
    fileexists("${path.module}/../talos/_output/kubeconfig") ? "${path.module}/../talos/_output/kubeconfig" : pathexpand("~/.kube/config")
  )
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}
