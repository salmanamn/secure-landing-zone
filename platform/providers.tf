provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    storage {
      # Flow-log account denies public traffic; manage it via ARM only (same as envs, D3).
      data_plane_available = false
    }
  }
}
