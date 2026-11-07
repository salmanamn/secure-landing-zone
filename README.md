[![ci](https://github.com/salmanamn/secure-landing-zone/actions/workflows/ci.yml/badge.svg)](https://github.com/salmanamn/secure-landing-zone/actions/workflows/ci.yml)

# Secure Landing Zone (Terraform)

Hardened Azure Storage + Key Vault behind private endpoints, with resource logs to Log Analytics, on top of a persistent subscription baseline (activity-log export, alerts, flow logs).
Built locally against the floci-az emulator, gated in CI by Checkov and custom Conftest policies, deployed to Azure keylessly through GitHub OIDC.

## Layout
- `modules/stack`: composition root used by every environment (`hardened` switch)
- `modules/network`: VNet, private endpoint subnet + NSG, private DNS zones
- `modules/monitoring`: Log Analytics workspace
- `modules/storage`: Entra-only auth, no public access, TLS 1.2, soft delete, CMK, private endpoint, diagnostics
- `modules/keyvault`: RBAC, purge protection, firewall deny, private endpoint, diagnostics
- `modules/governance`: custom Azure Policy definitions → initiative → Deny assignment
- `envs/local`, `envs/azure`: same stack, different provider + inputs (floci-az vs real Azure)
- `bootstrap/`: persistent remote state (Entra-only) + CI managed identities; state access logged (D14, D20)
- `platform/`: persistent subscription baseline: activity log, alerts, hub VNet, flow logs (D17–D19)
- `policy/`: Conftest rules on the plan JSON + unit tests
- `scripts/`: local rebuild, CI deploy with scripted approval, Prowler summaries and before/after tables
- `docs/decisions.md`: design decisions and emulator limits (D1–D22)

## Run locally
    docker compose up -d && ./scripts/trust-floci-cert.sh
    ./scripts/rebuild-local.sh

## Checks (same as CI)
    terraform fmt -recursive -check
    for d in envs/local envs/azure bootstrap platform; do checkov -d "$d" --framework terraform --compact --quiet; done
    conftest verify --policy policy/

Checkov runs per root module and is pinned (3.4.3), because a repo-wide `-d .` graph resolves module inputs inconsistently (D22).

## Results on real Azure (uaenorth, Nov 2026)

| | Weak profile (before) | Hardened profile (after) |
|---|---|---|
| Prowler — stack (`rg-slz-azure`) | **18 FAIL** / 10 PASS | **0 FAIL** / 4 muted / 28 PASS |
| Prowler — subscription | 58 FAIL | **0 FAIL** / 46 muted / 62 PASS — see [Subscription baseline](#subscription-baseline-s2-4) |
| Azure Policy (Deny) | not assigned | blocks Shared Key, public access, missing purge protection — [evidence](docs/evidence/policy-deny-shared-key.txt) |
| Checkov | — | 0 failed across all four roots; every skip documented inline |

- **Before/after summaries:** stack [before](docs/prowler/before.txt) · [after](docs/prowler/after.txt); subscription [before](docs/prowler/subscription-before.txt) · [after](docs/prowler/subscription-after.txt) (empty = no unmuted FAIL). Raw Prowler output is not committed (tenant details).
- **Accepted risks** (muted with reasons, [mutelist](docs/prowler/mutelist.yaml)): D13 (stack), D14 (state account), D19 (flow-log storage), D21 (Defender plans, Entra P1 features, single-owner lab).
- **Private by design:** the CMK is created through ARM, so Terraform never needs the vault's data plane (D3).
- **Found on real Azure, not in the emulator:** a 409 on storage create (recovered by `terraform import`), ARM template type-casing drift, azurerm disabling share soft delete when `share_properties` is set, and azurerm nesting Service Health conditions in `anyOf` (D21).

## CI/CD to Azure

Keyless GitHub Actions → Azure through OIDC federated credentials on two managed identities (D15).
Remote state lives in an Entra-only storage account created by `bootstrap/` (D14). `main` is protected: both CI checks must pass.

| Trigger | Identity | Result |
|---|---|---|
| Pull request | `id-slz-plan` (Reader) | `terraform plan` in the job summary |
| Dispatch `apply` / `destroy` | `id-slz-plan` → `id-slz-apply` after approval | Saved plan applied exactly as reviewed |
| Nightly 02:00 Bahrain | `id-slz-plan` | Watchdog: fails + opens a `lab-up` issue if the stack is still deployed (D16) |

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
