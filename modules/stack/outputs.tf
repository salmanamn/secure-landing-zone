output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "pe_subnet_id" {
  value = module.network.pe_subnet_id
}

output "private_dns_zone_ids" {
  value = module.network.private_dns_zone_ids
}

output "storage_account_name" {
  value = module.storage.name
}

output "key_vault_name" {
  value = module.keyvault.name
}

output "profile" {
  value = var.hardened ? "hardened" : "weak"
}
