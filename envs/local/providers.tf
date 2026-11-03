terraform {
  required_version = ">= 1.9.0"

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
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false # purge protection makes purging impossible anyway
      recover_soft_deleted_key_vaults = false # never silently resurrect an old vault
    }
  }

  environment   = "stack"          # custom cloud, not public Azure
  metadata_host = "localhost:4577" # floci-az serves the cloud endpoints here

  use_cli         = false
  subscription_id = "00000000-0000-0000-0000-000000000001"
  tenant_id       = "00000000-0000-0000-0000-000000000002"
  client_id       = "00000000-0000-0000-0000-000000000003"
  client_secret   = "fake-secret" # emulator doesn't validate credentials

  storage_use_azuread = true # Shared Key is disabled -> provider must use Entra tokens
}
