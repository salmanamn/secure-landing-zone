# Composition root: everything both environments deploy.
# envs/local and envs/azure differ ONLY in provider config and inputs.
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    random  = { source = "hashicorp/random" }
  }
}

data "azurerm_client_config" "current" {}

# Storage + Key Vault names are global DNS names -> random suffix
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

module "network" {
  source              = "../network"
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

module "monitoring" {
  count               = var.log_analytics_enabled ? 1 : 0
  source              = "../monitoring"
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

module "storage" {
  source                     = "../storage"
  name                       = "st${replace(var.name, "-", "")}${random_string.suffix.result}"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  pe_subnet_id               = module.network.pe_subnet_id
  blob_private_dns_zone_id   = module.network.private_dns_zone_ids["blob"]
  log_analytics_workspace_id = var.log_analytics_enabled ? module.monitoring[0].workspace_id : null
  diagnostics_enabled        = var.log_analytics_enabled
  hardened                   = var.hardened
  tags                       = var.tags
}

module "keyvault" {
  source                       = "../keyvault"
  name                         = "kv-${var.name}-${random_string.suffix.result}"
  location                     = azurerm_resource_group.this.location
  resource_group_name          = azurerm_resource_group.this.name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  pe_subnet_id                 = module.network.pe_subnet_id
  keyvault_private_dns_zone_id = module.network.private_dns_zone_ids["keyvault"]
  log_analytics_workspace_id   = var.log_analytics_enabled ? module.monitoring[0].workspace_id : null
  diagnostics_enabled          = var.log_analytics_enabled
  hardened                     = var.hardened
  tags                         = var.tags
}
