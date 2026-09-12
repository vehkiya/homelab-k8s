variable "tofu_encryption_passphrase" {
  type        = string
  description = "Passphrase for OpenTofu state and plan client-side encryption"
  sensitive   = true
}

variable "kubeconfig_path" {
  type        = string
  description = "Explicit path to kubeconfig file (defaults to Layer 1 output, then ~/.kube/config)"
  default     = null
}

variable "vaultwarden_client_id" {
  type        = string
  description = "Vaultwarden API Client ID"
  sensitive   = true
}

variable "vaultwarden_client_secret" {
  type        = string
  description = "Vaultwarden API Client Secret"
  sensitive   = true
}

variable "vaultwarden_host" {
  type        = string
  description = "Vaultwarden URL"
  default     = "https://vaultwarden.kerrlab.app"
}

variable "vaultwarden_password" {
  type        = string
  description = "Vaultwarden Master Password"
  sensitive   = true
}
