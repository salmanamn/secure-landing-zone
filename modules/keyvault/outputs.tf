output "id" {
  value = azurerm_key_vault.this.id
}

output "name" {
  value = azurerm_key_vault.this.name
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "cmk_key_id" {
  description = "Versionless key URI (enables auto-rotation for consumers); null when not hardened"
  value       = try(jsondecode(azurerm_resource_group_template_deployment.cmk[0].output_content).keyUri.value, null)
}
