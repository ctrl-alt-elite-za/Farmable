#!/usr/bin/env bash
set -Eeuo pipefail

: "${API_URL:?API_URL is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

live="$(curl --fail --silent --show-error --max-time 10 "$API_URL/health/live")"
[[ "$(jq -r '.sha // empty' <<<"$live")" == "$COMMIT_SHA" ]]
jq -e '.status == "ok"' <<<"$live" >/dev/null

ready="$(curl --fail --silent --show-error --max-time 10 "$API_URL/health/ready")"
[[ "$(jq -r '.sha // empty' <<<"$ready")" == "$COMMIT_SHA" ]]
jq -e '.database == "ok" and .worker == "ok"' <<<"$ready" >/dev/null

openapi="$(curl --fail --silent --show-error --max-time 10 "$API_URL/openapi.json")"
jq -e '.paths["/health/ready"] != null' <<<"$openapi" >/dev/null
echo "Cloud Run demo smoke passed"
