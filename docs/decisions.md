# Decisions

## D1 · floci-az does not persist security properties
floci-az 0.15.0 accepts but does not store the security properties of storage accounts AND key vaults
(and key vault tags): e.g. `https_traffic_only_enabled`, `min_tls_version`, `allow_nested_items_to_be_public`,
`local_user_enabled`, `infrastructure_encryption_enabled`, `public_network_access_enabled`,
`purge_protection_enabled`, `rbac_authorization_enabled`, `network_acls`. Effects locally: a perpetual
in-place diff, and a forced replacement on `infrastructure_encryption_enabled`, which is the only attribute
in `ignore_changes` (it is set-at-creation on Azure anyway).
Security is therefore verified at plan time (Checkov + Conftest) and at runtime on real Azure (Prowler),
not by the emulator.

## D2 · queue/table encryption key type = Account
Account-scoped keys let a future customer-managed key cover queues and tables, not only blob and file.
This also matches what floci-az returns, so there is no forced replacement.

## D3 · Terraform never needs the vault data plane
After create/refresh, `azurerm_key_vault_key` calls `https://<vault>.vault.azure.net`. Locally floci-az publishes
443 and /etc/hosts maps the vault host (rebuild-local.sh). On real Azure the vault is private, and temporarily
allowing the runner IP would violate our own Deny policy (`publicNetworkAccess` must be Disabled).
The CMK is therefore created through ARM (`Microsoft.KeyVault/vaults/keys` in a template deployment): firewall rules
don't apply to the control plane, and the deployer needs `keys/write` (Owner / Key Vault Contributor) instead of a
data-plane role. Trade-offs: ARM keys are create-only (changes need a new key name), ARM can't delete keys
(`delete_nested_items_during_deletion = false`; the key goes with the vault), and Checkov's key checks no longer
apply. `azurerm_storage_account` data-plane checks are off (`data_plane_available = false`). Running Terraform inside
the VNet (self-hosted runner) remains the pattern for data-plane objects such as secrets.

## D4 · Policy gate runs on a fresh-deploy plan
The emulator returns defaults for security properties (D1). On an existing deployment, `change.after`
therefore reflects the emulator, not the code. The gate runs on a plan from an empty state (a `gate`
workspace locally, a clean emulator in CI), so `after` reflects exactly what the code would deploy.

## D5 · One stack, `hardened` switch
`modules/stack` holds everything; envs differ only in provider + inputs. `hardened=false` is a
deliberately weak baseline for the Prowler "before" run. Two settings are NOT toggled:
`infrastructure_encryption_enabled` (set-at-creation, toggling forces a replace) and
`min_tls_version` (Azure rejects < TLS1_2). Purge protection is one-way, so the only valid
order on real Azure is weak -> hardened, then destroy.

## D6 · Local lab is create/destroy only
floci-az rejects PATCH on key vaults, and D1 makes every existing vault and storage account look
drifted. Local changes are therefore applied by a full rebuild (`scripts/rebuild-local.sh`), never
by updating in place. In-place updates are exercised on real Azure only.

## D7 · Resource logs via diagnostic settings, not classic Storage Analytics
Key Vault (AuditEvent) and blob (StorageRead/Write/Delete) logs go to one Log Analytics workspace using
category group `allLogs`. Workspace shared keys are disabled (Entra ID only). Diagnostics exist only in the
hardened profile, so the weak "before" run shows "logging not enabled" findings.

## D8 · Log Analytics is skipped on floci-az
azurerm always lists `Microsoft.OperationalInsights/deletedWorkspaces` before creating a workspace;
floci-az 0.15.0 doesn't serve it (404), so workspaces can't be created locally. `log_analytics_enabled = false`
in envs/local skips the workspace and the diagnostic settings. The code is still scanned by Checkov
locally and in CI, and is deployed and verified on real Azure.

## D9 · Customer-managed key for storage (hardened only)
Storage is encrypted with an RSA-3072 key from the project's Key Vault, referenced by its versionless ID so
Azure's rotation policy (new version 30 days before a 180-day expiry) is picked up automatically. Access uses
a user-assigned identity with "Key Vault Crypto Service Encryption User" on the vault, created before the
account. Role definitions are referenced by built-in ID, not name. The deployer gets "Key Vault Crypto
Officer" to create the key. HSM-backed keys (Premium vault) are skipped for cost (CKV_AZURE_112).

## D10 · Role assignments are skipped on floci-az
floci-az has no `Microsoft.Authorization/roleAssignments` handler: 0.15.0 answered every lookup with 200
("already exists"), and 0.16.0 answers create with 404. `envs/local` sets `role_assignments_enabled = false`.
The emulator doesn't enforce RBAC, so the key is still created. On real Azure both assignments are required:
the deployer's Crypto Officer role (to create the key) and the storage identity's Crypto Service Encryption
User role (to use it).
`envs/local` also keeps `skip_import_check_on_create_and_allow_overwriting_existing_resources = true`, so a
rebuild after a state reset can overwrite leftovers in the emulator. Never set it in envs/azure.

## D11 · CMK is planned everywhere but not attached on floci-az applies
Before attaching a CMK, azurerm reads the vault and requires purge protection + soft delete. floci-az
returns them as false (D1), so the attach fails locally. Plans (gate, CI) keep the CMK, so the policy
rule is enforced; `rebuild-local.sh` applies with `storage_cmk_enabled=false`. The key, its rotation
policy and both role assignments are still created locally. The attach itself is verified on real Azure.

## D12 · Azure Policy enforces the baseline at request time
Four custom definitions (storage: no public network, no Shared Key; key vault: no public network, purge
protection) are grouped in one initiative and assigned with `Deny` to the resource group, hardened profile
only, so the weak "before" profile stays deployable. Storage and Key Vault depend on the governance module
so the assignment exists before they are written. Custom rather than built-in definitions because floci-az
ships no built-in catalogue. On real Azure a new assignment can take up to ~30 minutes to take effect.
Requires floci-az >= 0.16.0: 0.15.0 stores policy resources but does not evaluate them.
