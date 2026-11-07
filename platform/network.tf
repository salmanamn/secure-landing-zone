locals {
  # Hub is not peered to the stack, so overlap with the stack VNet doesn't matter; keep it distinct anyway.
  hub_address_space    = ["10.100.0.0/24"]
  runner_subnet_prefix = ["10.100.0.0/27"]
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.prefix}-hub"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  address_space       = local.hub_address_space
  tags                = local.tags
}

# Reserved for the future self-hosted GitHub runner (state-account lockdown, D14).
resource "azurerm_network_security_group" "runners" {
  name                = "nsg-${var.prefix}-hub-runners"
  location            = azurerm_resource_group.platform.location
  resource_group_name = azurerm_resource_group.platform.name
  tags                = local.tags

  security_rule {
    name                       = "deny-internet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet" "runners" {
  name                            = "snet-runners"
  resource_group_name             = azurerm_resource_group.platform.name
  virtual_network_name            = azurerm_virtual_network.hub.name
  address_prefixes                = local.runner_subnet_prefix
  default_outbound_access_enabled = false
}

resource "azurerm_subnet_network_security_group_association" "runners" {
  subnet_id                 = azurerm_subnet.runners.id
  network_security_group_id = azurerm_network_security_group.runners.id
}
