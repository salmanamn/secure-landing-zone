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
  description = "Versionless key ID (enables auto-rotation for consumers); null when not hardened"
  value       = try(azurerm_key_vault_key.cmk[0].versionless_id, null)
}
