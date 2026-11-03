terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

# Central sink for resource logs (Key Vault audit, blob reads/writes/deletes)
resource "azurerm_log_analytics_workspace" "this" {
  name                         = "log-${var.name}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "PerGB2018"
  retention_in_days            = var.retention_days
  local_authentication_enabled = false # Entra ID only, no workspace shared keys
  tags                         = var.tags
}
