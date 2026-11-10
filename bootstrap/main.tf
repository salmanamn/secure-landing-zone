data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  github_issuer = "https://token.actions.githubusercontent.com"
  audience      = ["api://AzureADTokenExchange"]

  tags = {
    project   = "secure-landing-zone"
    component = "bootstrap"
  }

  # Fixed id (uuid5 of the role's URL) so the Project 3 stack, its Conftest allowlist and the ABAC condition can
  # name it before it exists.
  email_sender_role_id = "fca60e2f-9abf-5087-a329-0814cea30909"

  # Only roles the stacks deployed by CI assign (D15, D23). Project 1: Key Vault Crypto Service Encryption User (CMK).
  # Project 3 (ticket-triage-agent): the app identity's data roles, the Event Grid dead-letter role, the operator's
  # OpenAI role and the custom email-sender role below. Its Conftest gate also pins scopes and principal types.
  assignable_role_ids = [
    "e147488a-f6f5-4113-8e2d-b22465e65bf6", # Key Vault Crypto Service Encryption User
    "b7e6dc6d-f1e8-4753-8033-0f276bb0955b", # Storage Blob Data Owner (Functions host storage)
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe", # Storage Blob Data Contributor (Event Grid dead-letter container)
    "69a216fc-b8fb-44d8-bc22-1f3c2cd27a39", # Azure Service Bus Data Sender
    "4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0", # Azure Service Bus Data Receiver
    "d5a91429-5739-47e2-a06b-3470a27159e7", # EventGrid Data Sender
    "3913510d-42f4-4e42-8a64-420c390055eb", # Monitoring Metrics Publisher
    "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd", # Cognitive Services OpenAI User
    local.email_sender_role_id,             # SLZ Email Sender (custom, below)
  ]
  assignable_roles = join(", ", local.assignable_role_ids)

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

  share_properties {
    retention_policy {
      days = 7 # keep share soft delete (azurerm drops it if retention_policy is omitted)
    }
    smb {
      versions                        = ["SMB3.1.1"]
      authentication_types            = ["Kerberos"]
      kerberos_ticket_encryption_type = ["AES-256"]
      channel_encryption_type         = ["AES-256-GCM"]
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Checkov only accepts azurerm_log_analytics_storage_insights (needs account key; Shared Key off). Blob read/write/delete logged via diagnostic setting (logging.tf, D20)
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Bootstrap's own state: only the human operator gets a data role here.
resource "azurerm_storage_container" "bootstrap" {
  #checkov:skip=CKV2_AZURE_21:Checkov only accepts azurerm_log_analytics_storage_insights (needs account key; Shared Key off). Blob read/write/delete logged via diagnostic setting (logging.tf, D20)
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

# Project 3 (ticket-triage-agent) deploys through the same two identities (D23), so Project 2's KnownPrincipals
# allowlist (SLZ-001/003) keeps covering CI. Same three subjects, written after the Project 1 ones.
resource "azurerm_federated_identity_credential" "triage_plan_pr" {
  name                      = "github-ticket-triage-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci["plan"].id
  issuer                    = local.github_issuer
  audience                  = local.audience
  subject                   = "${var.triage_oidc_subject_prefix}:pull_request"

  depends_on = [azurerm_federated_identity_credential.plan_main]
}

resource "azurerm_federated_identity_credential" "triage_plan_main" {
  name                      = "github-ticket-triage-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci["plan"].id
  issuer                    = local.github_issuer
  audience                  = local.audience
  subject                   = "${var.triage_oidc_subject_prefix}:ref:refs/heads/main"

  depends_on = [azurerm_federated_identity_credential.triage_plan_pr]
}

resource "azurerm_federated_identity_credential" "triage_apply_env" {
  name                      = "github-ticket-triage-env-${var.github_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci["apply"].id
  issuer                    = local.github_issuer
  audience                  = local.audience
  subject                   = "${var.triage_oidc_subject_prefix}:environment:${var.github_environment}"

  depends_on = [azurerm_federated_identity_credential.apply_env]
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

# ---------- Plan identity: refresh of ARM template deployments (D3 CMK key) ----------
# Reader covers */read only; azurerm reads template content via exportTemplate (POST action).

resource "azurerm_role_definition" "plan_export_template" {
  name        = "SLZ Terraform Plan - Export Deployment Template"
  scope       = data.azurerm_subscription.current.id
  description = "Lets the CI plan identity refresh azurerm_resource_group_template_deployment (not covered by Reader)."

  permissions {
    actions = ["Microsoft.Resources/deployments/exportTemplate/action"]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "plan_export_template" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.plan_export_template.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.ci["plan"].principal_id
  principal_type     = "ServicePrincipal"
}

# ---------- Project 3 (D23) ----------

# Send email through Azure Communication Services with Entra ID: the documented minimum (ACS Read + Write, Email
# Services write) instead of the built-in Communication and Email Service Owner. The stack assigns it to the app
# identity on its ACS resource only; the apply identity may assign it (ABAC list above).
resource "azurerm_role_definition" "email_sender" {
  role_definition_id = local.email_sender_role_id
  name               = "SLZ Email Sender"
  scope              = data.azurerm_subscription.current.id
  description        = "Send email through an Azure Communication Services resource with Microsoft Entra ID."

  permissions {
    actions = [
      "Microsoft.Communication/CommunicationServices/Read",
      "Microsoft.Communication/CommunicationServices/Write",
      "Microsoft.Communication/EmailServices/write",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

# Refreshing the Project 3 stack: azurerm reads these through POST actions that Reader doesn't cover, even with
# local auth disabled (Cosmos keys + connection strings, Event Grid topic keys and subscription URL, Function App
# config lists). The keys
# are useless while local auth is off; Project 2 SLZ-003 still sees every listing.
resource "azurerm_role_definition" "plan_refresh" {
  name        = "SLZ Terraform Plan - Refresh List Actions"
  scope       = data.azurerm_subscription.current.id
  description = "Lets the CI plan identity refresh Cosmos DB, Event Grid and Function App resources (POST list actions)."

  permissions {
    actions = [
      "Microsoft.DocumentDB/databaseAccounts/listKeys/action",
      "Microsoft.DocumentDB/databaseAccounts/readonlykeys/action",
      "Microsoft.DocumentDB/databaseAccounts/listConnectionStrings/action",
      "Microsoft.EventGrid/topics/listKeys/action",
      "Microsoft.EventGrid/eventSubscriptions/getFullUrl/action",
      "Microsoft.Web/sites/config/list/action",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "plan_refresh" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.plan_refresh.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.ci["plan"].principal_id
  principal_type     = "ServicePrincipal"
}
