# CIS: a custom role scoped to lock administration, so locks can be managed without Owner/Contributor.
resource "azurerm_role_definition" "lock_admin" {
  name        = "SLZ Resource Lock Administrator"
  scope       = data.azurerm_subscription.current.id
  description = "Create, update and delete management locks; read-only otherwise."

  permissions {
    actions = [
      "Microsoft.Authorization/locks/*",
      "Microsoft.Authorization/*/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/read",
    ]
    not_actions = []
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}
