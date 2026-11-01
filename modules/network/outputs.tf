output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "pe_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "private_dns_zone_ids" {
  value = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}
