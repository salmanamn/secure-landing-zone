terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81" # >= 4.81 and < 5.0
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7" # >= 3.5 and < 4.0
    }
  }
}

provider "azurerm" {
  features {}

  environment   = "stack"          # custom cloud, not public Azure
  metadata_host = "localhost:4577" # where to find the cloud's endpoints

  use_cli             = false
  subscription_id     = "00000000-0000-0000-0000-000000000001"
  tenant_id           = "00000000-0000-0000-0000-000000000002"
  client_id           = "00000000-0000-0000-0000-000000000003"
  client_secret       = "fake-secret" # the emulator doesn't validate credentials
  storage_use_azuread = true          # Shared Key will be disabled, so the provider must use Entra tokens
}
