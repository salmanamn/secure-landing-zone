locals {
  # One alert per operation: Prowler/CIS match a single operationName per rule.
  activity_alerts = {
    # --- Prowler monitor_alert_* (CIS) ---
    "policy-assignment-write"  = { operation = "Microsoft.Authorization/policyAssignments/write", description = "Policy assignment created or updated" }
    "policy-assignment-delete" = { operation = "Microsoft.Authorization/policyAssignments/delete", description = "Policy assignment deleted" }
    "nsg-write"                = { operation = "Microsoft.Network/networkSecurityGroups/write", description = "Network security group created or updated" }
    "nsg-delete"               = { operation = "Microsoft.Network/networkSecurityGroups/delete", description = "Network security group deleted" }
    "security-solution-write"  = { operation = "Microsoft.Security/securitySolutions/write", description = "Security solution created or updated" }
    "security-solution-delete" = { operation = "Microsoft.Security/securitySolutions/delete", description = "Security solution deleted" }
    "sql-firewall-write"       = { operation = "Microsoft.Sql/servers/firewallRules/write", description = "SQL server firewall rule created or updated" }
    "sql-firewall-delete"      = { operation = "Microsoft.Sql/servers/firewallRules/delete", description = "SQL server firewall rule deleted" }
    "public-ip-write"          = { operation = "Microsoft.Network/publicIPAddresses/write", description = "Public IP address created or updated" }
    "public-ip-delete"         = { operation = "Microsoft.Network/publicIPAddresses/delete", description = "Public IP address deleted" }

    # --- Beyond Prowler: privilege and key-material changes (KQL lab inputs) ---
    "role-assignment-write"  = { operation = "Microsoft.Authorization/roleAssignments/write", description = "Role assignment created" }
    "role-assignment-delete" = { operation = "Microsoft.Authorization/roleAssignments/delete", description = "Role assignment deleted" }
    "keyvault-delete"        = { operation = "Microsoft.KeyVault/vaults/delete", description = "Key Vault deleted" }
  }
}

resource "azurerm_monitor_action_group" "security" {
  name                = "ag-${var.prefix}-security"
  resource_group_name = azurerm_resource_group.platform.name
  location            = "global"
  short_name          = "slzsec" # max 12 chars; appears in SMS/email
  tags                = local.tags

  email_receiver {
    name                    = "owner"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_activity_log_alert" "admin" {
  for_each = local.activity_alerts

  name                = "ala-${var.prefix}-${each.key}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = "global"
  scopes              = [data.azurerm_subscription.current.id]
  description         = each.value.description
  enabled             = true
  tags                = local.tags

  criteria {
    category       = "Administrative"
    operation_name = each.value.operation
    statuses       = ["Succeeded"]
  }

  action {
    action_group_id = azurerm_monitor_action_group.security.id
  }
}

# Service Health: Incident-only rule matches the CIS condition (incidentType = Incident);
# a second rule carries security advisories, required actions and maintenance.
resource "azurerm_monitor_activity_log_alert" "service_health" {
  for_each = {
    "incidents"  = ["Incident"]
    "advisories" = ["Security", "ActionRequired", "Maintenance"]
  }

  name                = "ala-${var.prefix}-service-health-${each.key}"
  resource_group_name = azurerm_resource_group.platform.name
  location            = "global"
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Service Health: ${join(", ", each.value)}"
  enabled             = true
  tags                = local.tags

  criteria {
    category = "ServiceHealth"

    service_health {
      events = each.value
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.security.id
  }
}
