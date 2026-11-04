terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

data "azurerm_client_config" "current" {}

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

# Audit every secret/key/certificate access (AuditEvent)
resource "azurerm_monitor_diagnostic_setting" "vault" {
  count                      = var.hardened && var.diagnostics_enabled ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

# --- Customer-managed key for storage (hardened only) ---

# Built-in role IDs are the same in every tenant
locals {
  role_crypto_officer = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/14b46e9e-c2b7-41b4-b07b-48a6ebf60603" # Key Vault Crypto Officer
}

# Whoever runs Terraform needs data-plane rights to create the key (RBAC vault)
resource "azurerm_role_assignment" "deployer_crypto_officer" {
  count              = var.hardened ? 1 : 0
  scope              = azurerm_key_vault.this.id
  role_definition_id = local.role_crypto_officer
  principal_id       = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "cmk" {
  #checkov:skip=CKV_AZURE_112:HSM-backed keys need a Premium vault; Standard is enough for a lab
  count           = var.hardened ? 1 : 0
  name            = "cmk-storage"
  key_vault_id    = azurerm_key_vault.this.id
  key_type        = "RSA"
  key_size        = 3072
  key_opts        = ["wrapKey", "unwrapKey"]
  expiration_date = var.cmk_expiration_date

  # Azure rotates the key automatically; storage follows because it uses the versionless ID
  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P180D"
    notify_before_expiry = "P29D"
  }

  depends_on = [azurerm_role_assignment.deployer_crypto_officer]
}
