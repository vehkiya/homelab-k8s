output "vaultwarden_secret_name" {
  description = "Name of the provisioned Vaultwarden credentials secret"
  value       = kubernetes_secret.vaultwarden_credentials.metadata[0].name
}

output "vaultwarden_secret_namespace" {
  description = "Namespace of the provisioned Vaultwarden credentials secret"
  value       = kubernetes_secret.vaultwarden_credentials.metadata[0].namespace
}

output "bootstrap_status" {
  description = "Status of bootstrap application chain"
  value = {
    cilium           = "deployed"
    coredns          = "deployed"
    external_secrets = "deployed"
    argocd           = "deployed"
    app_of_apps      = "configured"
  }
}
