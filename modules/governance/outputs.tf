output "initiative_id" {
  value = azurerm_policy_set_definition.baseline.id
}

output "assignment_id" {
  value = try(azurerm_resource_group_policy_assignment.baseline[0].id, null)
}
