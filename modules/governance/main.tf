terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

data "azurerm_subscription" "current" {}

# Custom definitions: the same rules the Conftest gate checks at plan time,
# enforced by Azure at request time. One definition per control.
locals {
  definitions = {
    "storage-no-public-network" = {
      display_name = "Storage accounts must disable public network access"
      rule = jsonencode({
        "if" = {
          allOf = [
            { field = "type", equals = "Microsoft.Storage/storageAccounts" },
            { field = "Microsoft.Storage/storageAccounts/publicNetworkAccess", notEquals = "Disabled" },
          ]
        }
        "then" = { effect = var.effect }
      })
    }
    "storage-no-shared-key" = {
      display_name = "Storage accounts must not allow Shared Key access"
      rule = jsonencode({
        "if" = {
          allOf = [
            { field = "type", equals = "Microsoft.Storage/storageAccounts" },
            { field = "Microsoft.Storage/storageAccounts/allowSharedKeyAccess", notEquals = false },
          ]
        }
        "then" = { effect = var.effect }
      })
    }
    "keyvault-no-public-network" = {
      display_name = "Key vaults must disable public network access"
      rule = jsonencode({
        "if" = {
          allOf = [
            { field = "type", equals = "Microsoft.KeyVault/vaults" },
            { field = "Microsoft.KeyVault/vaults/publicNetworkAccess", notEquals = "Disabled" },
          ]
        }
        "then" = { effect = var.effect }
      })
    }
    "keyvault-purge-protection" = {
      display_name = "Key vaults must have purge protection enabled"
      rule = jsonencode({
        "if" = {
          allOf = [
            { field = "type", equals = "Microsoft.KeyVault/vaults" },
            { field = "Microsoft.KeyVault/vaults/enablePurgeProtection", notEquals = true },
          ]
        }
        "then" = { effect = var.effect }
      })
    }
  }
}

resource "azurerm_policy_definition" "this" {
  for_each     = local.definitions
  name         = "${var.name}-${each.key}"
  policy_type  = "Custom"
  mode         = "Indexed" # only evaluates resource types that support tags + location
  display_name = each.value.display_name
  policy_rule  = each.value.rule
  metadata     = jsonencode({ category = "Secure Landing Zone" })
}

# Initiative (policy set): assign all controls as one unit
resource "azurerm_policy_set_definition" "baseline" {
  name         = "${var.name}-baseline"
  policy_type  = "Custom"
  display_name = "Secure landing zone baseline (${var.name})"

  dynamic "policy_definition_reference" {
    for_each = azurerm_policy_definition.this
    content {
      policy_definition_id = policy_definition_reference.value.id
      reference_id         = policy_definition_reference.key
    }
  }
}

# Only the hardened profile is governed; the weak "before" profile must be deployable
resource "azurerm_resource_group_policy_assignment" "baseline" {
  count                = var.hardened ? 1 : 0
  name                 = "${var.name}-baseline"
  resource_group_id    = var.resource_group_id
  policy_definition_id = azurerm_policy_set_definition.baseline.id
  enforce              = true
  description          = "Blocks storage/key vault configurations the baseline forbids. Subscription: ${data.azurerm_subscription.current.display_name}"
}
