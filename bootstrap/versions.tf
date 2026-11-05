terraform {
  required_version = ">= 1.17.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    storage {
      data_plane_available = false # same as the stack (D3): control plane only
    }
  }
}
