output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "plan_client_id" {
  value = azurerm_user_assigned_identity.ci["plan"].client_id
}

output "apply_client_id" {
  value = azurerm_user_assigned_identity.ci["apply"].client_id
}

output "state_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

output "backend_hcl" {
  description = "Partial backend config for envs/azure."
  value       = <<-EOT
    resource_group_name  = "${azurerm_resource_group.bootstrap.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name       = "${azurerm_storage_container.tfstate.name}"
    key                  = "azure.tfstate"
    use_azuread_auth     = true
  EOT
}
