#!/usr/bin/env bash
# Usage: scripts/ci-deploy.sh apply|destroy
set -euo pipefail

ACTION="${1:?usage: $0 apply|destroy}"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

gh workflow run deploy.yml --ref main -f action="$ACTION"
sleep 8
RUN_ID=$(gh run list --workflow deploy.yml --event workflow_dispatch --limit 1 \
  --json databaseId --jq '.[0].databaseId')
URL="https://github.com/$REPO/actions/runs/$RUN_ID"
echo "run: $URL"

job() { gh run view "$RUN_ID" --json jobs --jq ".jobs[] | select(.name==\"plan\") | .$1"; }
until [ "$(job status)" = completed ]; do sleep 10; done

# Job logs via API: available as soon as the job finishes, even while the run is still waiting.
gh api "repos/$REPO/actions/jobs/$(job databaseId)/logs" | grep -E 'Plan:|No changes' || true
[ "$(job conclusion)" = success ] || { echo "plan failed: $URL"; exit 1; }

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

# POST without --jq (parsing the response is what failed before); verify via the approvals endpoint instead.
BODY=$(printf '{"environment_ids":[%s],"state":"%s","comment":"%s via ci-deploy.sh"}' "$ENV_ID" "$STATE" "$ACTION")
STATUS=$(gh api -X POST -i "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" --input - <<<"$BODY" 2>&1 | head -n 1) || true
echo "approval POST: $STATUS"

sleep 3
RECORDED=$(gh api "repos/$REPO/actions/runs/$RUN_ID/approvals" --jq "[.[] | select(.state==\"$STATE\")] | length")
[ "$RECORDED" -gt 0 ] || { echo "approval not recorded; approve in the browser: $URL"; exit 1; }
echo "$STATE"

[ "$STATE" = approved ] && gh run watch "$RUN_ID" --exit-status