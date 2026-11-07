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

# Service Health advisories (Security, ActionRequired, Maintenance) via the native resource.
resource "azurerm_monitor_activity_log_alert" "service_health" {
  for_each = {
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

# Service Health incidents with the flat CIS condition (category + properties.incidentType in one allOf).
# azurerm's service_health block nests incidentType in anyOf, which CIS/Prowler don't recognise (D18).
# New name on purpose: reusing the old one would let the azurerm destroy delete the template's alert.
resource "azurerm_resource_group_template_deployment" "service_health_incidents" {
  name                = "ala-${var.prefix}-service-health-cis"
  resource_group_name = azurerm_resource_group.platform.name
  deployment_mode     = "Incremental"
  tags                = local.tags

  parameters_content = jsonencode({
    alertName     = { value = "ala-${var.prefix}-service-health-cis" }
    scope         = { value = data.azurerm_subscription.current.id }
    actionGroupId = { value = azurerm_monitor_action_group.security.id }
    tags          = { value = local.tags }
  })

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      alertName     = { type = "String" } # title case: ARM normalises types
      scope         = { type = "String" }
      actionGroupId = { type = "String" }
      tags          = { type = "Object" }
    }
    resources = [{
      type       = "Microsoft.Insights/activityLogAlerts"
      apiVersion = "2020-10-01"
      name       = "[parameters('alertName')]"
      location   = "global"
      tags       = "[parameters('tags')]"
      properties = {
        enabled     = true
        description = "Service Health incidents (CIS condition)"
        scopes      = ["[parameters('scope')]"]
        condition = {
          allOf = [
            { field = "category", equals = "ServiceHealth" },
            { field = "properties.incidentType", equals = "Incident" },
          ]
        }
        actions = {
          actionGroups = [{ actionGroupId = "[parameters('actionGroupId')]" }]
        }
      }
    }]
  })
}
