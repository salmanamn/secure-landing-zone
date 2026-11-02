# Decisions

## D1 · floci-az does not persist storage security properties
floci-az 0.15.0 accepts but does not store the security properties of storage accounts AND key vaults (and key vault tags).
`https_traffic_only_enabled`, `min_tls_version`,
`allow_nested_items_to_be_public`, `local_user_enabled`, `default_to_oauth_authentication`,
`infrastructure_encryption_enabled`, `sas_policy`, `identity`. Effects locally: a perpetual in-place
diff, and a forced replacement on `infrastructure_encryption_enabled`, which is the only attribute in
`ignore_changes` (it is set-at-creation on Azure anyway).
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
The emulator returns defaults for storage security properties (D1). On an existing deployment,
`change.after` therefore reflects the emulator, not the code. The gate runs on a plan from an
empty state (a `gate` workspace locally, a clean emulator in CI), so `after` reflects exactly what
the code would deploy.

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
