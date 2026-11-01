locals {
  name = "slz-local"
  tags = {
    project    = "secure-landing-zone"
    managed_by = "terraform"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name}"
  location = "eastus"
  tags     = local.tags
}

module "network" {
  source              = "../../modules/network"
  name                = local.name
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

output "pe_subnet_id" {
  value = module.network.pe_subnet_id
}
