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
    # floci-az answers 200 to any unknown path, so azurerm's "already exists?" check always
    # trips (D10). Local emulator only; never on real Azure, where it would overwrite resources.
    skip_import_check_on_create_and_allow_overwriting_existing_resources = true

    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
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
