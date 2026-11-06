data "azurerm_subscription" "current" {}

locals {
  tags = merge({
    project   = "secure-landing-zone"
    layer     = "platform"
    lifecycle = "persistent"
  }, var.tags)

  # All subscription activity-log categories. Prowler requires at least Administrative, Alert, Policy and Security.
  activity_log_categories = [
    "Administrative",
    "Security",
    "ServiceHealth",
    "Alert",
    "Recommendation",
    "Policy",
    "Autoscale",
    "ResourceHealth",
  ]
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-${var.prefix}-platform"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "platform" {
  name                         = "log-${var.prefix}-platform"
  location                     = azurerm_resource_group.platform.location
  resource_group_name          = azurerm_resource_group.platform.name
  sku                          = "PerGB2018"
  retention_in_days            = var.workspace_retention_days
  daily_quota_gb               = var.workspace_daily_quota_gb
  local_authentication_enabled = false # Entra-only, same as modules/monitoring
  tags                         = local.tags
}

# Subscription activity log -> platform workspace (AzureActivity table).
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-activity-log-to-${azurerm_log_analytics_workspace.platform.name}"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.platform.id

  dynamic "enabled_log" {
    for_each = toset(local.activity_log_categories)
    content {
      category = enabled_log.value
    }
  }
}
