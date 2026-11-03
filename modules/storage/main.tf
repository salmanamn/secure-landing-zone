terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV2_AZURE_1:CMK added in Week 2 (needs Key Vault key + managed identity)
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
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    # floci-az doesn't store it (D1); set-at-creation on Azure anyway
    ignore_changes = [infrastructure_encryption_enabled]
  }
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
