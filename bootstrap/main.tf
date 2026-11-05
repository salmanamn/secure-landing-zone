data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  github_issuer = "https://token.actions.githubusercontent.com"
  audience      = ["api://AzureADTokenExchange"]

  tags = {
    project   = "secure-landing-zone"
    component = "bootstrap"
  }

  # Only roles the stack itself assigns. Key Vault Crypto Service Encryption User (CMK identity).
  assignable_role_ids = ["e147488a-f6f5-4113-8e2d-b22465e65bf6"]
  assignable_roles    = join(", ", local.assignable_role_ids)

  # RBAC Administrator may only create/delete assignments of the roles above.
  rbac_admin_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_roles}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_roles}}
     )
    )
  EOT
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "bootstrap" {
  name     = "rg-slz-bootstrap"
  location = var.location
  tags     = local.tags
}

# ---------- Remote state ----------

resource "azurerm_storage_account" "tfstate" {
  #checkov:skip=CKV_AZURE_59:GitHub-hosted runners have no fixed IPs; access is Entra-only (D14)
  #checkov:skip=CKV_AZURE_35:Same as CKV_AZURE_59; network lockdown waits for a self-hosted runner (D14)
  #checkov:skip=CKV2_AZURE_33:No private endpoint; runners are outside the VNet (D14)
  #checkov:skip=CKV2_AZURE_1:State encrypted with Microsoft-managed keys; CMK not worth it for a lab state store
  #checkov:skip=CKV_AZURE_206:LRS by design; versioning and soft delete cover state recovery
  #checkov:skip=CKV_AZURE_33:No queues; data plane disabled for Terraform (D3)
  name                              = "stslztfstate${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.bootstrap.name
  location                          = azurerm_resource_group.bootstrap.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  local_user_enabled                = false
  infrastructure_encryption_enabled = true
  cross_tenant_replication_enabled  = false

  sas_policy {
    expiration_period = "1.00:00:00"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:No persistent Log Analytics workspace in bootstrap yet; state access logging deferred to the subscription baseline module (D14)
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Bootstrap's own state: only the human operator gets a data role here.
resource "azurerm_storage_container" "bootstrap" {
  #checkov:skip=CKV2_AZURE_21:No persistent Log Analytics workspace in bootstrap yet; state access logging deferred to the subscription baseline module (D14)
  name                  = "bootstrap"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# ---------- CI identities ----------

resource "azurerm_user_assigned_identity" "ci" {
  for_each = toset(["plan", "apply"])

  name                = "id-slz-${each.key}"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location
  tags                = local.tags
}

# Federated credentials on one identity must be written sequentially (Azure rejects concurrent writes).
resource "azurerm_federated_identity_credential" "plan_pr" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci["plan"].id
  issuer                    = local.github_issuer
  audience                  = local.audience
  subject                   = "${var.oidc_subject_prefix}:pull_request"
}

resource "azurerm_federated_identity_credential" "plan_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci["plan"].id
  issuer                    = local.github_issuer
  audience                  = local.audience
  subject                   = "${var.oidc_subject_prefix}:ref:refs/heads/main"

  depends_on = [azurerm_federated_identity_credential.plan_pr]
}

resource "azurerm_federated_identity_credential" "apply_env" {
  name                      = "github-env-${var.github_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci["apply"].id
  issuer                    = local.github_issuer
  audience                  = local.audience
  subject                   = "${var.oidc_subject_prefix}:environment:${var.github_environment}"
}

# ---------- Control-plane roles ----------

resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.ci["plan"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ci["apply"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_policy" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Resource Policy Contributor"
  principal_id         = azurerm_user_assigned_identity.ci["apply"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.ci["apply"].principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.rbac_admin_condition
}

# ---------- State data-plane roles ----------

locals {
  state_access = {
    plan = {
      scope     = azurerm_storage_container.tfstate.id
      principal = azurerm_user_assigned_identity.ci["plan"].principal_id
      type      = "ServicePrincipal"
    }
    apply = {
      scope     = azurerm_storage_container.tfstate.id
      principal = azurerm_user_assigned_identity.ci["apply"].principal_id
      type      = "ServicePrincipal"
    }
    me-tfstate = {
      scope     = azurerm_storage_container.tfstate.id
      principal = data.azurerm_client_config.current.object_id
      type      = "User"
    }
    me-bootstrap = {
      scope     = azurerm_storage_container.bootstrap.id
      principal = data.azurerm_client_config.current.object_id
      type      = "User"
    }
  }
}

resource "azurerm_role_assignment" "state" {
  for_each = local.state_access

  scope                = each.value.scope
  role_definition_name = "Storage Blob Data Contributor" # plan needs write too: state lock = blob lease
  principal_id         = each.value.principal
  principal_type       = each.value.type
}
