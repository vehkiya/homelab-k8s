terraform {
  required_version = ">= 1.8.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6.0"
    }
  }
}
