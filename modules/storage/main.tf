terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

data "azurerm_client_config" "current" {}

# Identity the storage account uses to reach its key. User-assigned, so it can be
# granted access BEFORE the account exists (a system identity only exists after).
resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk" {
  count              = var.hardened && var.role_assignments_enabled ? 1 : 0
  scope              = var.key_vault_id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/e147488a-f6f5-4113-8e2d-b22465e65bf6" # Key Vault Crypto Service Encryption User
  principal_id       = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV_AZURE_206:LRS is intentional for a disposable lab; prod uses GZRS
  #checkov:skip=CKV_AZURE_33:Classic queue logging is legacy and queues are unused; resource logs go to Log Analytics (D7)
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Transport (Azure no longer accepts TLS < 1.2, so same in both profiles)
  https_traffic_only_enabled = var.hardened
  min_tls_version            = "TLS1_2"

  # Exposure
  allow_nested_items_to_be_public = var.hardened ? false : true
  public_network_access_enabled   = var.hardened ? false : true

  # Authentication: Entra ID only when hardened
  shared_access_key_enabled        = var.hardened ? false : true
  default_to_oauth_authentication  = var.hardened
  local_user_enabled               = var.hardened ? false : true
  cross_tenant_replication_enabled = false

  # Encryption at rest: set-at-creation, so NOT toggled (a toggle would need a replace)
  infrastructure_encryption_enabled = true
  queue_encryption_key_type         = "Account"
  table_encryption_key_type         = "Account"

  network_rules {
    default_action = var.hardened ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    versioning_enabled = var.hardened

    dynamic "delete_retention_policy" {
      for_each = var.hardened ? [1] : []
      content {
        days = var.soft_delete_days
      }
    }

    dynamic "container_delete_retention_policy" {
      for_each = var.hardened ? [1] : []
      content {
        days = var.soft_delete_days
      }
    }
  }

  sas_policy {
    expiration_period = "00.04:00:00"
    expiration_action = "Log"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  # Encrypt with our key instead of a Microsoft-managed one (hardened only)
  dynamic "customer_managed_key" {
    for_each = var.hardened && var.cmk_enabled ? [1] : []
    content {
      key_vault_key_id          = var.cmk_key_id
      user_assigned_identity_id = azurerm_user_assigned_identity.this.id
    }
  }

  tags = var.tags

  lifecycle {
    # floci-az doesn't store it (D1); set-at-creation on Azure anyway
    ignore_changes = [infrastructure_encryption_enabled]
  }

  # The identity must be allowed to use the key before the account is encrypted with it
  depends_on = [azurerm_role_assignment.cmk]
}

resource "azurerm_private_endpoint" "blob" {
  count               = var.hardened ? 1 : 0
  name                = "pe-${var.name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.blob_private_dns_zone_id]
  }
}

# Adding `count` changed the address: blob -> blob[0]. Tell Terraform it's the same object.
moved {
  from = azurerm_private_endpoint.blob
  to   = azurerm_private_endpoint.blob[0]
}

# Resource logs for the blob service: StorageRead / StorageWrite / StorageDelete
resource "azurerm_monitor_diagnostic_setting" "blob" {
  count                      = var.hardened && var.diagnostics_enabled ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
