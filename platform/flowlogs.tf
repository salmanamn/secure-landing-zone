locals {
  # Deterministic, globally-unique-enough suffix without the random provider.
  flowlog_suffix       = substr(sha1(data.azurerm_subscription.current.subscription_id), 0, 8)
  flowlog_account_name = "st${var.prefix}flow${local.flowlog_suffix}"
}

# Azure-managed watcher (NetworkWatcherRG); referenced, not owned.
data "azurerm_network_watcher" "region" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

resource "azurerm_storage_account" "flowlogs" {
  #checkov:skip=CKV_AZURE_43:Name is computed (sha1 of subscription id); Checkov can't render it. Naming rule enforced by the lifecycle precondition below
  #checkov:skip=CKV_AZURE_59:Flow logs reach storage via the trusted-services exception, which needs public access = selected networks (default Deny)
  #checkov:skip=CKV2_AZURE_33:No private endpoint; Network Watcher writes as a trusted service (D19)
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys; CMK rotation breaks flow logs until re-enabled (D19)
  #checkov:skip=CKV_AZURE_206:LRS by design (lab, D13)
  #checkov:skip=CKV_AZURE_33:Queue logging needs the data plane; no queues used
  #checkov:skip=CKV2_AZURE_21:Blob read logging handled in Milestone D pattern; flow-log writes would dominate volume
  name                              = local.flowlog_account_name
  resource_group_name               = azurerm_resource_group.platform.name
  location                          = azurerm_resource_group.platform.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard" # flow logs: Standard only
  account_replication_type          = "LRS"
  access_tier                       = "Hot"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  sftp_enabled                      = false
  public_network_access_enabled     = true # selected networks only (network_rules below)
  tags                              = local.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  share_properties {
    retention_policy {
      days = 7 # keep share soft delete (azurerm gotcha)
    }
    smb {
      versions                        = ["SMB3.1.1"]
      authentication_types            = ["Kerberos"]
      kerberos_ticket_encryption_type = ["AES-256"]
      channel_encryption_type         = ["AES-256-GCM"]
    }
  }

  sas_policy {
    expiration_period = "00.01:00:00"
    expiration_action = "Log"
  }

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9]{3,24}$", local.flowlog_account_name))
      error_message = "Storage account name must be 3-24 lowercase letters/digits: ${local.flowlog_account_name}"
    }
  }
}

# Belt-and-braces with the flow-log retention policy: shorter rule wins.
resource "azurerm_storage_management_policy" "flowlogs" {
  storage_account_id = azurerm_storage_account.flowlogs.id

  rule {
    name    = "expire-flowlogs-90d"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["insights-logs-flowlogflowevent/"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 90
      }
    }
  }
}

# azurerm 4.81 has no user_assigned_identity_id on flow logs (checked 2026-11-07).
# Network Watcher writes via the trusted-services exception (bypass = AzureServices).
resource "azurerm_network_watcher_flow_log" "hub" {
  name                 = "fl-${var.prefix}-hub"
  network_watcher_name = data.azurerm_network_watcher.region.name
  resource_group_name  = data.azurerm_network_watcher.region.resource_group_name
  location             = var.location
  target_resource_id   = azurerm_virtual_network.hub.id
  storage_account_id   = azurerm_storage_account.flowlogs.id
  enabled              = true
  version              = 2
  tags                 = local.tags

  retention_policy {
    enabled = true
    days    = 90
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.platform.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.platform.location
    workspace_resource_id = azurerm_log_analytics_workspace.platform.id
    interval_in_minutes   = 60
  }
}
