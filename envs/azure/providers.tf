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

# Real Azure. Identity comes from `az login` (use_cli defaults to true); subscription is pinned explicitly.
# No emulator settings here: in particular NEVER skip_import_check_on_create_... (D10).
provider "azurerm" {
  subscription_id = var.subscription_id

  # Register only what this stack uses instead of ~70 providers
  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.Authorization",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.PolicyInsights", # compliance results in the portal
    "Microsoft.Storage",
  ]

  storage_use_azuread = true # Shared Key is disabled when hardened

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false # purge protection makes purging impossible anyway
      recover_soft_deleted_key_vaults = false
    }

    resource_group {
      prevent_deletion_if_contains_resources = true # destroy fails loudly if something was created outside Terraform
    }

    storage {
      # The account is private when hardened, so the laptop can't reach its data plane (D3).
      # Safe because the stack uses no queue_properties / static_website blocks.
      data_plane_available = false
    }

    template_deployment {
      # The CMK is created through an ARM deployment (D3). ARM can't delete vault keys;
      # the key goes away with the vault.
      delete_nested_items_during_deletion = false
    }
  }
}
