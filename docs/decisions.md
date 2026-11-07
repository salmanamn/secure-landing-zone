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

- Re-checked on floci-az 0.16.0 (2026-11-07): `share_properties` (SMB 3.1.1 / AES-256-GCM + share soft delete) and blob/container retention are accepted on create but not persisted → same perpetual in-place diff (`2 to change`). No emulator switch needed; verified on real Azure by Prowler (SMB checks PASS).

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

## D13 · Accepted Prowler findings (lab scope)
Muted in `docs/prowler/mutelist.yaml`, each with a reason: DDoS Network Protection (~$2,900/month, not justified
for a lab VNet); geo-redundant storage (LRS by design, prod uses GZRS); storage access-key rotation (Shared Key is
disabled, so keys are unusable); Key Vault key rotation (policy verified via ARM: rotate 30 days before a 180-day
expiry. Prowler reads it over the data plane, which is private by design, D3).
Subscription-level findings (activity-log alerts, Network Watcher flow logs, Bastion) are subscription governance,
outside this landing zone, and are reported separately.

## D14 — Remote state in a persistent bootstrap RG

- `bootstrap/` is a separate root module, applied by hand. It creates `rg-slz-bootstrap` with the state account
  (Entra-only, Shared Key off, versioning + 30-day blob/container soft delete, LRS), containers `tfstate`
  (CI identities + operator) and `bootstrap` (operator only; holds bootstrap's own state), and the CI identities (D15).
- Persistent: not destroyed per session (cost: cents/month). It sits outside `rg-slz-azure`, so the stack's Deny
  initiative does not apply to it.
- Public endpoint stays on: GitHub-hosted runners have no fixed IPs. Protection is Entra auth plus container-scoped RBAC.
  Network lockdown (private endpoint/firewall) waits for a self-hosted runner in the VNet.
- Accepted Checkov skips: CKV_AZURE_59, CKV_AZURE_35, CKV2_AZURE_33 (network, above), CKV2_AZURE_1 (Microsoft-managed
  keys), CKV_AZURE_206 (LRS), CKV_AZURE_33 (no queues), CKV2_AZURE_21 (state access logging deferred to the
  subscription baseline module, which will have a persistent Log Analytics workspace).
- Teardown: migrate bootstrap state back to local (`terraform init -migrate-state` without the backend block), then destroy.

## D15 — CI identities and deploy flow

- Two user-assigned managed identities with GitHub federated credentials: no app registration, no secret, no Graph permissions.
  - `id-slz-plan`: Reader (subscription) + Storage Blob Data Contributor (`tfstate` container; write is needed for the
    lease lock). Trusted subjects: `pull_request`, `ref:refs/heads/main`.
    Plus a custom role with only `Microsoft.Resources/deployments/exportTemplate/action`: refreshing the ARM-template CMK key (D3) reads the template back, which Reader does not cover. Found when the first CI destroy plan failed.
  - `id-slz-apply`: Contributor + Resource Policy Contributor + Role Based Access Control Administrator, with an
    ABAC condition that only allows assigning/deleting Key Vault Crypto Service Encryption User + Storage Blob Data
    Contributor (`tfstate`). Trusted subject: `environment:azure` only (required reviewer, `main` only).
    Its client ID is an environment secret.
  - Subjects use the `sub` prefix read from a real token (GitHub's immutable owner/repo-ID format where applicable).
- Flow: PR → plan to the job summary. Dispatch `apply|destroy` → plan → encrypted artifact (1 day) → approval →
  `terraform apply` of that exact plan. A concurrency group serialises state access.
- CI deploys the hardened stack only; the weak → hardened Prowler comparison stays manual (D5).
- Trade-offs: Contributor is at subscription scope because the stack creates its own RG. The plan identity can write
  state, and anyone with repo write access can trigger a PR plan; acceptable for a single-maintainer repo.
  The subscription ID is a secret so it is masked in logs, and the plan summary is sanitised.
  
## D16 — Nightly lab watchdog (check, not auto-destroy)

- `lab-watchdog.yml` runs at 02:00 Asia/Bahrain (23:00 UTC) and on dispatch. It uses `id-slz-plan` (trusted for
  `ref:refs/heads/main`) to count managed resources in `envs/azure` state (data sources excluded).
- If the count is not 0, the run fails and a `lab-up` issue is opened (once, while one is open): GitHub notifies on both.
- No auto-destroy: that would need the apply identity without the environment approval, a second ungated trust path.
  The budget alerts remain the backstop.
- `terraform state list` takes no lock, so the watchdog never blocks a deploy.
- GitHub disables scheduled workflows in public repos after 60 days without repo activity.
- Gotcha: Resource Mover needs its identity's Contributor + User Access Administrator even to *delete* move resources. Removing the roles first left a `Failed`/`PreparePending` move resource that blocked RG deletion. Fix: re-grant both temporarily (5 min propagation) → delete move resource → delete RG → delete orphaned assignments.

## D17 Persistent `platform/` root module for the subscription baseline
- Subscription-wide controls (activity-log export, activity-log alerts, Service Health, flow-log storage) live in `platform/` → `rg-slz-platform`, not in the stack: they must outlive nightly destroys, and the activity log is subscription-scoped.
- Persistent workspace `log-slz-platform` (Entra-only, 90-day retention, 1 GB/day cap). Activity logs: no ingestion charge; AzureActivity retained 90 days free.
- State: same bootstrap account, key `platform.tfstate`. Applied by hand from the laptop (like `bootstrap/`); changes rarely. The watchdog only checks `envs/azure` state, so a persistent platform doesn't trip it.
- Outside the stack's Deny scope by design. Teardown order: platform → bootstrap (D14).
- Azure-only: no `envs/local` equivalent (floci-az doesn't emulate subscription diagnostics/alerts).

## D18 Subscription activity-log alerts
- One activity-log alert per operation (Prowler/CIS match a single operationName per rule), `Succeeded` only, subscription scope, one email action group `ag-slz-security`.
- Prowler set (policy assignment, NSG, security solution, SQL firewall, public IP: write/delete) + role assignment write/delete + Key Vault delete.
- Service Health split: Incident-only rule (CIS condition) + advisories (Security, ActionRequired, Maintenance).
- Accepted noise: ~8–10 emails per lab apply/destroy (NSG, role/policy assignments, vault). Activity-log alerts can't exclude callers; filter in the mailbox instead.
- Custom role "SLZ Resource Lock Administrator" (locks/* + reads), unassigned.

## D19 Flow logs on a persistent hub VNet
- Prowler/CIS score flow logs per Network Watcher; the stack VNet is destroyed nightly, so the flow log lives on a persistent hub `vnet-slz-hub` (10.100.0.0/24, `snet-runners` reserved for the self-hosted runner) in `platform/`.
- VNet flow logs (NSG flow-log creation is retired), version 2, 90-day retention + lifecycle rule, Traffic Analytics → `log-slz-platform` every 60 min.
- Storage `stslzflow<sha1(sub)[0:8]>`: Standard LRS, Shared Key off, Entra default, default Deny + trusted-services bypass (why public access stays "selected networks"), no PE, Microsoft-managed keys (CMK rotation breaks flow logs). Keyless writes via UAMI `id-slz-flowlogs` (Storage Blob Data Contributor) where the provider supports it.
- Unused watchers (eastus, westus2 from the Resource Mover experiment) deleted; `network_watcher_enabled` (all regions) muted: a watcher per region would add a flow-log FAIL per region.
- Stack VNet gets no flow log: no compute, and private-endpoint traffic isn't captured. Data-path test deferred until the runner VM exists.
- Provider: `features.storage.data_plane_available = false` (account denies public data-plane traffic).

## D20 State-account hardening (bootstrap)
- SMB 3.1.1 / Kerberos AES-256 / channel AES-256-GCM, share soft delete 7d (no shares used; closes Prowler `storage_smb_channel_encryption_with_secure_algorithm`).
- Blob StorageRead/Write/Delete → `log-slz-platform` via diagnostic setting on `blobServices/default`: who read, locked or changed state (StorageBlobLogs; all OAuth).
- CKV2_AZURE_21 stays skipped: Checkov only recognises `azurerm_log_analytics_storage_insights`, which needs the account key (Shared Key off). The diagnostic setting is the real control.
- bootstrap now reads the platform workspace → teardown order platform → bootstrap requires removing `logging.tf` first (or destroying bootstrap before platform's workspace).

## D21 Subscription-scope Prowler mutes
- Defender plans (15): paid, out of scope for the lab; `auto_provisioning_log_analytics_agent` is the retired MMA agent.
- Entra tenant (13): Conditional Access, named locations and CA-based MFA need Entra ID P1. Seven `entra_policy_*` toggles are free → candidate S2-5 (tenant hardening via Graph), not Terraform.
- `network_watcher_enabled`: watchers only where VNets exist; one per region would add a flow-log FAIL per region (D19).
- `network_bastion_host_exists`, `appinsights_ensure_is_configured`: not part of this design. `iam_subscription_owners_between_2_and_3`: single-person lab.
- Flow-log storage `storage_blob_versioning_is_enabled`: flow logs append blocks every minute; versioning would keep a version per write.
- `iam_custom_role_has_permissions_to_administer_resource_locks`: Prowler false positive, raised on "SLZ Terraform Plan - Export Deployment Template". "SLZ Resource Lock Administrator" carries `Microsoft.Authorization/locks/*` (verify: `az role definition list --custom-role-only true`). Not fixed by adding locks to the plan role (least privilege, D15).
- Service Health incidents alert deployed via ARM template (flat `allOf`: category + properties.incidentType); azurerm's `service_health` block nests incidentType in `anyOf`, which CIS/Prowler don't match.
- Result (lab down, 2026-11-07): 58 FAIL → 0 FAIL / 46 muted / 62 PASS; table in README.

## D22 Checkov per root, pinned
- `checkov -d .` builds one graph across all root modules (envs/local, envs/azure, bootstrap, platform) and resolved `module.stack` inputs inconsistently once `platform/` was added (CKV_AZURE_35 on the stack storage account; each root passes on its own). Terraform never evaluates the repo as one graph, so CI scans each root separately.
- Checkov pinned (`3.4.3`) in CI and locally so a release can't change results between runs; bump deliberately.
- PR #6 was merged with this check red → branch protection now requires CI on `main`.
