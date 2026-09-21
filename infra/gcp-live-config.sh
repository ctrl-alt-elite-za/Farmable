#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

service_json="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" --format=json)"

jq -e '
  any(.status.conditions[]?; .type == "Ready" and .status == "True")
' <<<"$service_json" >/dev/null

api_url="$(jq -er '.status.url | select(type == "string" and length > 0)' \
  <<<"$service_json")"
revision="$(jq -er '
  [.status.traffic[]? | select(.percent == 100 and .revisionName != null)
    | .revisionName] | unique
  | if length == 1 then .[0]
    else error("service must route 100% traffic to exactly one revision")
    end
' <<<"$service_json")"

revision_json="$(gcloud run revisions describe "$revision" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" --format=json)"
jq -e '
  any(.status.conditions[]?; .type == "Ready" and .status == "True")
' <<<"$revision_json" >/dev/null
commit_sha="$(jq -er '
  [.spec.containers[].env[]?
    | select(.name == "COMMIT_SHA" and (.value | type == "string"))
    | .value]
  | unique
  | if length == 1 and (.[0] | test("^[0-9a-f]{40}$")) then .[0]
    else error("live revision must contain exactly one full COMMIT_SHA")
    end
' <<<"$revision_json")"

{
  printf 'api_url=%s\n' "$api_url"
  printf 'commit_sha=%s\n' "$commit_sha"
} >>"$GITHUB_OUTPUT"
