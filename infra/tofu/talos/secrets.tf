# Greenfield secret generator (only activated if existing secrets are not provided)
resource "talos_machine_secrets" "generated" {
  count         = var.cluster_secrets == null ? 1 : 0
  talos_version = var.talos_version
}

locals {
  is_existing = var.cluster_secrets != null

  # The machine secrets to pass to data.talos_machine_configuration
  machine_secrets = local.is_existing ? {
    certs = {
      etcd = {
        cert = var.cluster_secrets.cluster.etcd.ca.crt
        key  = var.cluster_secrets.cluster.etcd.ca.key
      }
      k8s = {
        cert = var.cluster_secrets.cluster.ca.crt
        key  = var.cluster_secrets.cluster.ca.key
      }
      k8s_aggregator = {
        cert = var.cluster_secrets.cluster.aggregatorCA.crt
        key  = var.cluster_secrets.cluster.aggregatorCA.key
      }
      k8s_serviceaccount = {
        key = var.cluster_secrets.cluster.serviceAccount.key
      }
      os = {
        cert = var.cluster_secrets.machine.ca.crt
        key  = var.cluster_secrets.machine.ca.key
      }
    }
    cluster = {
      id     = var.cluster_secrets.cluster.id
      secret = var.cluster_secrets.cluster.secret
    }
    secrets = {
      bootstrap_token             = var.cluster_secrets.cluster.token
      secretbox_encryption_secret = var.cluster_secrets.cluster.secretboxEncryptionSecret
      aescbc_encryption_secret    = null
    }
    trustdinfo = {
      token = var.cluster_secrets.machine.token
    }
  } : talos_machine_secrets.generated[0].machine_secrets

  # Client configuration for contacting Talos nodes
  talos_client_config = local.is_existing && var.cluster_secrets.client_configuration != null ? {
    ca_certificate     = var.cluster_secrets.client_configuration.ca_certificate
    client_certificate = var.cluster_secrets.client_configuration.client_certificate
    client_key         = var.cluster_secrets.client_configuration.client_key
  } : talos_machine_secrets.generated[0].client_configuration
}
