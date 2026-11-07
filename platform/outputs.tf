output "resource_group_name" {
  value = azurerm_resource_group.platform.name
}

output "workspace_id" {
  description = "ARM ID, used by diagnostic settings in the stack and bootstrap."
  value       = azurerm_log_analytics_workspace.platform.id
}

output "workspace_customer_id" {
  description = "Workspace GUID, used for KQL queries."
  value       = azurerm_log_analytics_workspace.platform.workspace_id
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.platform.name
}

output "action_group_id" {
  description = "Security action group, reused by stack/bootstrap alerts later."
  value       = azurerm_monitor_action_group.security.id
}
