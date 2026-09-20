terraform {
  required_version = ">= 1.5"

  required_providers {
    konnect = {
      source  = "kong/konnect"
      version = "~> 3.22"
    }
    konnect-beta = {
      source  = "kong/konnect-beta"
      version = "~> 0.22.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
  }
}
