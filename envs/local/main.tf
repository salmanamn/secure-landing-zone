locals {
  name = "slz-local"
  tags = {
    project    = "secure-landing-zone"
    managed_by = "terraform"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name}"
  location = "eastus"
  tags     = local.tags
}

module "network" {
  source              = "../../modules/network"
  name                = local.name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

output "pe_subnet_id" {
  value = module.network.pe_subnet_id
}

output "private_dns_zone_ids" {
  value = module.network.private_dns_zone_ids
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

module "storage" {
  source                   = "../../modules/storage"
  name                     = "stslzlocal${random_string.suffix.result}"
  location                 = azurerm_resource_group.lab.location
  resource_group_name      = azurerm_resource_group.lab.name
  pe_subnet_id             = module.network.pe_subnet_id
  blob_private_dns_zone_id = module.network.private_dns_zone_ids["blob"]
  tags                     = local.tags
}

output "storage_account_name" {
  value = module.storage.name
}

# Reads the tenant/subscription the provider is authenticated to
data "azurerm_client_config" "current" {}

module "keyvault" {
  source                       = "../../modules/keyvault"
  name                         = "kv-slz-local-${random_string.suffix.result}"
  location                     = azurerm_resource_group.lab.location
  resource_group_name          = azurerm_resource_group.lab.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  pe_subnet_id                 = module.network.pe_subnet_id
  keyvault_private_dns_zone_id = module.network.private_dns_zone_ids["keyvault"]
  tags                         = local.tags
}

output "key_vault_name" {
  value = module.keyvault.name
}
