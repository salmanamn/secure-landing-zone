terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV2_AZURE_1:CMK added in Week 2 (needs Key Vault key + managed identity)
  #checkov:skip=CKV_AZURE_206:LRS is intentional for a disposable lab; prod uses GZRS
  #checkov:skip=CKV_AZURE_33:Queues unused; diagnostics come with the Log Analytics module

  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Transport
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Exposure
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false

  # Authentication: Entra ID only
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  local_user_enabled               = false
  cross_tenant_replication_enabled = false

  # Encryption at rest
  infrastructure_encryption_enabled = true
  queue_encryption_key_type         = "Account" # lets a future CMK cover queues
  table_encryption_key_type         = "Account" # ...and tables

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  # Recovery: soft delete + versioning (ransomware / accidental delete)
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_days
    }
  }

  sas_policy {
    expiration_period = "00.04:00:00"
    expiration_action = "Log"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags

  lifecycle {
    # Set-at-creation only; Azure can't change it later anyway.
    # floci-az doesn't store it, which would force a replace on every apply.
    ignore_changes = [infrastructure_encryption_enabled]
  }
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-${var.name}-blob"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}-blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.blob_private_dns_zone_id]
  }
}
