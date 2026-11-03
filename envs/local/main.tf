variable "hardened" {
  type    = bool
  default = true
}

module "stack" {
  source   = "../../modules/stack"
  name     = "slz-local"
  location = "eastus"
  hardened = var.hardened

  log_analytics_enabled = false # floci-az can't create workspaces (D8)

  tags = {
    project    = "secure-landing-zone"
    managed_by = "terraform"
  }
}

# --- Refactor: these resources now live inside module.stack. Same objects, new addresses. ---
moved {
  from = azurerm_resource_group.lab
  to   = module.stack.azurerm_resource_group.this
}

moved {
  from = random_string.suffix
  to   = module.stack.random_string.suffix
}

moved {
  from = module.network
  to   = module.stack.module.network
}

moved {
  from = module.storage
  to   = module.stack.module.storage
}

moved {
  from = module.keyvault
  to   = module.stack.module.keyvault
}

output "summary" {
  value = module.stack
}
