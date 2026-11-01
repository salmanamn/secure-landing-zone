#!/usr/bin/env bash
set -euo pipefail
curl -sf http://localhost:4577/_floci/tls-cert -o floci-az.crt
grep -q "BEGIN CERTIFICATE" floci-az.crt || { echo "No cert — is FLOCI_AZ_TLS_ENABLED=true?"; exit 1; }
sudo cp floci-az.crt /usr/local/share/ca-certificates/floci-az.crt
sudo update-ca-certificates --fresh >/dev/null
curl -sf https://localhost:4577/metadata/endpoints >/dev/null && echo "floci-az cert trusted ✔"