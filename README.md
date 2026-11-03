[![ci](https://github.com/salmanamn/secure-landing-zone/actions/workflows/ci.yml/badge.svg)](https://github.com/salmanamn/secure-landing-zone/actions/workflows/ci.yml)

# Secure Landing Zone (Terraform)

Hardened Azure Storage + Key Vault behind private endpoints, with resource logs to Log Analytics.
Built locally against the floci-az emulator, gated in CI by Checkov and custom Conftest policies.

## Layout
- `modules/stack`: composition root used by every environment (`hardened` switch)
- `modules/network`: VNet, private endpoint subnet + NSG, private DNS zones
- `modules/monitoring`: Log Analytics workspace
- `modules/storage`: Entra-only auth, no public access, TLS 1.2, soft delete, private endpoint, diagnostics
- `modules/keyvault`: RBAC, purge protection, firewall deny, private endpoint, diagnostics
- `policy/`: Conftest rules on the plan JSON + unit tests
- `docs/decisions.md`: design decisions and emulator limits

## Run locally
    docker compose up -d && ./scripts/trust-floci-cert.sh
    ./scripts/rebuild-local.sh

## Checks (same as CI)
    terraform fmt -recursive -check
    checkov -d . --framework terraform --compact
    conftest verify --policy policy/
