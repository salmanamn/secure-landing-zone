#!/usr/bin/env bash
# Usage: scripts/ci-deploy.sh apply|destroy
set -euo pipefail

ACTION="${1:?usage: $0 apply|destroy}"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

gh workflow run deploy.yml --ref main -f action="$ACTION"
sleep 8
RUN_ID=$(gh run list --workflow deploy.yml --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')
echo "run: https://github.com/$REPO/actions/runs/$RUN_ID"

job() { gh run view "$RUN_ID" --json jobs --jq ".jobs[] | select(.name==\"plan\") | .$1"; }
until [ "$(job status)" = completed ]; do sleep 10; done
gh run view --job "$(job databaseId)" --log | grep -E 'Plan:|No changes' || true
[ "$(job conclusion)" = success ] || { echo "plan failed"; exit 1; }

for _ in $(seq 1 30); do
  [ "$(gh api "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" --jq length)" -gt 0 ] && break
  if [ "$(gh run view "$RUN_ID" --json status --jq .status)" = completed ]; then
    echo "no changes, nothing to approve"; exit 0
  fi
  sleep 5
done

read -rp "Approve $ACTION? [y/N] " ok
STATE=$([ "${ok:-n}" = y ] && echo approved || echo rejected)
ENV_ID=$(gh api "repos/$REPO/environments/azure" --jq .id)
gh api -X POST "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" \
  -F "environment_ids[]=$ENV_ID" -f state="$STATE" -f comment="$ACTION via ci-deploy.sh" >/dev/null
echo "$STATE"
[ "$STATE" = approved ] && gh run watch "$RUN_ID" --exit-status