# Decisions

## D1 · floci-az does not persist storage security properties
floci-az 0.15.0 accepts but does not store `https_traffic_only_enabled`, `min_tls_version`,
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
