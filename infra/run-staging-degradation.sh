#!/usr/bin/env bash
set -euo pipefail
: "${INSTANCE_ID:?INSTANCE_ID is required}"
: "${API_URL:?API_URL is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

run_remote() {
  local command_id
  command_id="$(aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript --parameters "commands=$1" --query Command.CommandId --output text)"
  aws ssm wait command-executed --command-id "$command_id" --instance-id "$INSTANCE_ID"
}

export API_URL COMMIT_SHA
run_remote "cd /opt/farmable && docker compose --env-file .env -f compose.yaml -f compose.staging.yaml stop worker"
pytest e2e/degradation -q -k worker_down
run_remote "cd /opt/farmable && docker compose --env-file .env -f compose.yaml -f compose.staging.yaml start worker"
pytest e2e/degradation -q -k recovered
run_remote "cd /opt/farmable && docker compose --env-file .env -f compose.yaml -f compose.staging.yaml stop database"
pytest e2e/degradation -q -k database_down
run_remote "cd /opt/farmable && docker compose --env-file .env -f compose.yaml -f compose.staging.yaml start database worker"
