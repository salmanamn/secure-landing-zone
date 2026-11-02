terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Authorization: Azure RBAC when hardened, legacy access policies when weak
  rbac_authorization_enabled = var.hardened

  # Recovery. Purge protection is one-way: weak -> hardened works, never back.
  soft_delete_retention_days = var.soft_delete_days
  purge_protection_enabled   = var.hardened

  enabled_for_deployment          = false
  enabled_for_disk_encryption     = false
  enabled_for_template_deployment = false

  # Exposure
  public_network_access_enabled = var.hardened ? false : true

  network_acls {
    default_action = var.hardened ? "Deny" : "Allow"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

resource "azurerm_private_endpoint" "vault" {
  count               = var.hardened ? 1 : 0
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.keyvault_private_dns_zone_id]
  }
}

moved {
  from = azurerm_private_endpoint.vault
  to   = azurerm_private_endpoint.vault[0]
}
