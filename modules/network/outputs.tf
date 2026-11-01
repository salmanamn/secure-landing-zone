output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "pe_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}
