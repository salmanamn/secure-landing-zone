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

## D3 · Key Vault data plane needs DNS to the vault
After create/refresh, azurerm calls the vault data plane (`https://<vault>.vault.azure.net`).
Locally: floci-az publishes 443 and /etc/hosts maps the vault host to 127.0.0.1.
Real Azure: the vault is private, so Terraform must run from a network that can reach the
private endpoint, or temporarily allow the runner IP.

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

## D10 · Import check disabled on the local provider only
floci-az has no role-assignment handler; its ARM fallthrough answers 200 to the GET azurerm sends before
create, so every `azurerm_role_assignment` fails with "already exists". `envs/local` sets
`skip_import_check_on_create_and_allow_overwriting_existing_resources = true`. Never set it in envs/azure:
there it would silently take over existing resources instead of failing.

## D11 · CMK is planned everywhere but not attached on floci-az applies
Before attaching a CMK, azurerm reads the vault and requires purge protection + soft delete. floci-az
returns them as false (D1), so the attach fails locally. Plans (gate, CI) keep the CMK, so the policy
rule is enforced; `rebuild-local.sh` applies with `storage_cmk_enabled=false`. The key, its rotation
policy and both role assignments are still created locally. The attach itself is verified on real Azure.
