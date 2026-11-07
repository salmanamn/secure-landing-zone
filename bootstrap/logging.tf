# Persistent platform workspace (platform/). Teardown order stays platform -> bootstrap:
# destroy this diagnostic setting (or bootstrap) before the workspace disappears.
data "azurerm_log_analytics_workspace" "platform" {
  name                = "log-slz-platform"
  resource_group_name = "rg-slz-platform"
}

# Who read, wrote, locked or deleted Terraform state. Entra-only path:
# classic Storage Analytics logging and storage insights both need account keys.
resource "azurerm_monitor_diagnostic_setting" "state_blob" {
  name                       = "diag-blob-to-log-slz-platform"
  target_resource_id         = "${azurerm_storage_account.tfstate.id}/blobServices/default"
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.platform.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
