output "id" {
  value = azurerm_storage_account.this.id
}

output "name" {
  value = azurerm_storage_account.this.name
}

output "principal_id" {
  # floci-az doesn't return the managed identity; real Azure does
  value = try(azurerm_storage_account.this.identity[0].principal_id, null)
}
