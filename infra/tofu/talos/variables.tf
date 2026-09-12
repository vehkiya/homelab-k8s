variable "cluster_name" {
  description = "Name of the Talos Kubernetes cluster"
  type        = string
  default     = "homecluster"
}

variable "cluster_vip" {
  description = "Virtual IP shared by control plane nodes"
  type        = string
  default     = "10.10.1.250"
}

variable "cluster_endpoint" {
  description = "Kubernetes API Server endpoint"
  type        = string
  default     = "https://kube.kerrlab.app:6443"
}

variable "talos_version" {
  description = "Talos OS version"
  type        = string
  default     = "v1.14.0"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.37.0"
}

variable "schematic_id" {
  description = "Talos Image Factory schematic ID (optional override; computed automatically from image-factory-parameters.yaml if empty)"
  type        = string
  default     = ""
}

variable "tofu_encryption_passphrase" {
  description = "Passphrase used for client-side state encryption"
  type        = string
  sensitive   = true
  default     = ""
}

variable "nodes" {
  description = "Topology map of all bare-metal nodes in the cluster"
  type = map(object({
    role          = string # "controlplane" or "worker"
    ip            = string
    ipv6          = string
    vlan2_ip      = string
    nic_driver    = string # "r8152" or "igc"
    mac_addresses = list(string)
    install_disk  = string
  }))
}

variable "cluster_secrets" {
  description = "Existing cluster secrets imported from backup"
  type = object({
    client_configuration = optional(object({
      ca_certificate     = string
      client_certificate = string
      client_key         = string
    }))
    machine = object({
      token = string
      ca = object({
        crt = string
        key = string
      })
    })
    cluster = object({
      id                        = string
      secret                    = string
      token                     = string
      secretboxEncryptionSecret = string
      ca = object({
        crt = string
        key = string
      })
      aggregatorCA = object({
        crt = string
        key = string
      })
      serviceAccount = object({
        key = string
      })
      etcd = object({
        ca = object({
          crt = string
          key = string
        })
      })
    })
  })
  sensitive = true
  default   = null
}

variable "docker_hub_username" {
  description = "Docker Hub (docker.io) registry username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "docker_hub_token" {
  description = "Docker Hub (docker.io) registry Personal Access Token (PAT) or password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dhi_username" {
  description = "Docker Hardened Images (dhi.io) registry username (defaults to docker_hub_username if unset)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dhi_token" {
  description = "Docker Hardened Images (dhi.io) registry token/PAT (defaults to docker_hub_token if unset)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ghcr_username" {
  description = "GitHub Container Registry (ghcr.io) username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ghcr_token" {
  description = "GitHub Container Registry (ghcr.io) Personal Access Token (read:packages)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "extra_registry_auths" {
  description = "Optional additional registry credentials mapped by registry host"
  type = map(object({
    username = string
    password = string
  }))
  default   = {}
  sensitive = true
}

variable "enable_nut_client" {
  description = "Whether to configure nut-client ExtensionServiceConfig"
  type        = bool
  default     = true
}

variable "nut_host" {
  description = "IP address or hostname of the NUT UPS server"
  type        = string
  default     = "10.10.1.218"
}

variable "nut_ups_name" {
  description = "Name of UPS on the NUT server"
  type        = string
  default     = "ups"
}

variable "nut_user" {
  description = "Username for NUT client authentication"
  type        = string
  default     = "monuser"
}

variable "nut_password" {
  description = "Password for NUT client authentication"
  type        = string
  default     = "secret"
  sensitive   = true
}

