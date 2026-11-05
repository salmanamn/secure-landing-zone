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

# Audit every secret/key/certificate access (AuditEvent)
resource "azurerm_monitor_diagnostic_setting" "vault" {
  count                      = var.hardened && var.diagnostics_enabled ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # CIS / Prowler expect both category groups (audit is a subset of allLogs)
  enabled_log {
    category_group = "audit"
  }

  enabled_log {
    category_group = "allLogs"
  }
}

# --- Customer-managed key for storage (hardened only) ---
# Created through ARM (control plane), not the vault data plane: the vault's firewall and
# private endpoint don't apply, so Terraform needs no network path to the vault and no
# data-plane role (D3). Off on floci-az together with role assignments (D10).
resource "azurerm_resource_group_template_deployment" "cmk" {
  count               = var.hardened && var.role_assignments_enabled ? 1 : 0
  name                = "cmk-storage"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"

  parameters_content = jsonencode({
    vaultName = { value = azurerm_key_vault.this.name }
    expiresOn = { value = var.cmk_expiration_date }
  })

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      vaultName = { type = "string" }
      expiresOn = { type = "string" }
    }
    resources = [
      {
        type       = "Microsoft.KeyVault/vaults/keys"
        apiVersion = "2024-11-01"
        name       = "[format('{0}/cmk-storage', parameters('vaultName'))]"
        properties = {
          kty        = "RSA"
          keySize    = 3072
          keyOps     = ["wrapKey", "unwrapKey"]
          attributes = { exp = "[dateTimeToEpoch(parameters('expiresOn'))]" }

          # Same policy as before: rotate 30 days before a 180-day expiry; storage follows
          # because it uses the versionless URI
          rotationPolicy = {
            attributes = { expiryTime = "P180D" }
            lifetimeActions = [
              { trigger = { timeBeforeExpiry = "P30D" }, action = { type = "rotate" } },
              { trigger = { timeBeforeExpiry = "P29D" }, action = { type = "notify" } },
            ]
          }
        }
      }
    ]
    outputs = {
      keyUri = {
        type  = "string"
        value = "[reference(resourceId('Microsoft.KeyVault/vaults/keys', parameters('vaultName'), 'cmk-storage'), '2024-11-01').keyUri]"
      }
    }
  })
}
