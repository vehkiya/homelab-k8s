terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket                      = "homelab-k8s-terraform"
    key                         = "bootstrap/k8s.tfstate"
    region                      = "us-east-1"
    endpoint                    = "https://s3.kerrlab.app"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.tofu_encryption_passphrase
    }

    method "aes_gcm" "state_encryption" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }
  }
}
