resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
    labels = {
      "kubernetes.io/metadata.name" = "external-secrets"
    }
  }
}

resource "kubernetes_secret" "vaultwarden_credentials" {
  metadata {
    name      = "vaultwarden-credentials"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
    annotations = {
      "argocd.argoproj.io/sync-options" = "Prune=false"
      "helm.sh/resource-policy"         = "keep"
    }
  }

  type = "Opaque"

  data = {
    BW_CLIENTID     = var.vaultwarden_client_id
    BW_CLIENTSECRET = var.vaultwarden_client_secret
    BW_HOST         = var.vaultwarden_host
    BW_PASSWORD     = var.vaultwarden_password
  }
}
