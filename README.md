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

## Results on real Azure (uaenorth, Nov 2026)

| | Weak profile (before) | Hardened profile (after) |
|---|---|---|
| Prowler — stack (`rg-slz-azure`) | **18 FAIL** / 10 PASS | **0 FAIL** / 4 muted / 28 PASS |
| Prowler — subscription-level (out of scope) | 21 FAIL | 21 FAIL |
| Azure Policy (Deny) | not assigned | blocks Shared Key, public access, missing purge protection — [evidence](docs/evidence/policy-deny-shared-key.txt) |
| Checkov | — | 26 passed / 0 failed / 4 skipped (documented) |

- **Before/after summaries:** [before](docs/prowler/before.txt) · [after](docs/prowler/after.txt). Raw Prowler output is not committed (tenant details).
- **Accepted risks** (muted with reasons, [mutelist](docs/prowler/mutelist.yaml)): DDoS Network Protection, GRS, access-key rotation, Key Vault rotation false positive — see D13.
- **Private by design:** the CMK is created through ARM, so Terraform never needs the vault's data plane (D3).
- **Subscription-level findings** (activity-log alerts, Network Watcher flow logs, Bastion) belong to subscription governance, not this landing zone.
- **Found on real Azure, not in the emulator:** a 409 on storage create (recovered by `terraform import`), ARM template type-casing drift, and azurerm disabling share soft delete when `share_properties` is set.

## CI/CD to Azure

Keyless GitHub Actions → Azure through OIDC federated credentials on two managed identities (D15).
Remote state lives in an Entra-only storage account created by `bootstrap/` (D14).

| Trigger | Identity | Result |
|---|---|---|
| Pull request | `id-slz-plan` (Reader) | `terraform plan` in the job summary |
| Dispatch `apply` / `destroy` | `id-slz-plan` → `id-slz-apply` after approval | Saved plan applied exactly as reviewed |

Run: `./scripts/ci-deploy.sh apply` … `./scripts/ci-deploy.sh destroy`
## Subscription baseline (S2-4)

Persistent `platform/` layer: activity log → `log-slz-platform`, activity-log alerts (CIS set + role assignments + Key Vault delete) and Service Health, lock-admin custom role, hub VNet with VNet flow logs + Traffic Analytics, state-account SMB hardening and access logging. Prowler 5.47, full subscription, lab down, 2026-11-07:

| Service | Before FAIL | After FAIL | After muted | After PASS |
|---|---:|---:|---:|---:|
| appinsights | 1 | 0 | 1 | 0 |
| defender | 15 | 0 | 15 | 2 |
| entra | 13 | 0 | 13 | 2 |
| iam | 3 | 0 | 2 | 11 |
| monitor | 13 | 0 | 0 | 13 |
| network | 8 | 0 | 3 | 7 |
| policy | 0 | 0 | 0 | 1 |
| storage | 5 | 0 | 12 | 26 |
| **Total** | **58** | **0** | **46** | **62** |

Every muted finding is an accepted risk with a reason in `docs/prowler/mutelist.yaml` and `docs/decisions.md` (D13, D14, D19, D21).
