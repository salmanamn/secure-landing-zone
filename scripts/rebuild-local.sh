#!/usr/bin/env bash
# floci-az supports create/delete but not in-place updates for Key Vault (D6).
# Rebuild = destroy everything, recreate fresh, and map the new vault host to 127.0.0.1 (D3).
set -euo pipefail
curl -sf https://localhost:4577/metadata/endpoints >/dev/null || {
  echo "floci-az not reachable: run 'docker compose up -d && ./scripts/trust-floci-cert.sh'"; exit 1; }
cd "$(dirname "$0")/../envs/local"

terraform workspace select default
terraform destroy -auto-approve -refresh=false

# Create only the suffix first, so we know the vault hostname before the vault exists
terraform apply -auto-approve -target=module.stack.random_string.suffix
SUFFIX=$(terraform state show -no-color module.stack.random_string.suffix | awk -F'"' '/^ *result/{print $2}')
HOST="kv-slz-local-${SUFFIX}.vault.azure.net"

sudo sed -i '/\.vault\.azure\.net$/d' /etc/hosts          # drop old vault entries
echo "127.0.0.1 ${HOST}" | sudo tee -a /etc/hosts >/dev/null

terraform apply -auto-approve
echo "Rebuilt. Vault host: ${HOST}"
