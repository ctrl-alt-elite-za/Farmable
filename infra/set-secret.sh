#!/usr/bin/env bash
# Add or replace the value of one staging secret, without the value touching the
# screen, shell history, the repository, GitHub or a chat.
#
#   bash infra/set-secret.sh              # which secrets hold a value (names only)
#   bash infra/set-secret.sh <name>       # prompt for a value and store it
#
# <name> is the part after "farmable-staging-", e.g. infobip-api-key. The next
# deploy wires it into the backend; nothing else changes. Needs only permission to
# add a secret version (see CLOUD_RULES.md), never to read one back.
set -Eeuo pipefail

PROJECT="${GCP_PROJECT:-almanac-staging-za}"
PREFIX="${SECRET_PREFIX:-farmable-staging}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The secret list is Terraform's, read rather than copied so the two cannot drift.
mapfile -t names < <(
  sed -n '/provider_secrets = toset(\[/,/\])/p' "$here/gcp-staging.tf" |
    grep -oE '"[a-z0-9-]+"' | tr -d '"'
)
names+=(forecast-github-token)
if (( ${#names[@]} < 2 )); then
  echo "Could not read the secret list from infra/gcp-staging.tf" >&2
  exit 1
fi

# Formats the backend validates on startup. A value that fails one crashes the
# container, so refuse it here instead. Mirrors integrations/settings.py.
pattern_for() {
  case "$1" in
    twilio-account-sid) echo '^AC[0-9a-fA-F]{32}$' ;;
    twilio-verify-service-sid) echo '^VA[0-9a-fA-F]{32}$' ;;
    azure-speech-resource) echo '^[a-zA-Z0-9-]{1,63}$' ;;
    azure-speech-region) echo '^[a-z0-9-]{1,32}$' ;;
    gemini-model) echo '^[a-zA-Z0-9._-]{1,128}$' ;;
    turnstile-hostname) echo '^[a-zA-Z0-9.-]{1,253}$' ;;
    infobip-base-url) echo '^([a-z0-9-]+\.)?api\.infobip\.com$' ;;
    infobip-sms-sender) echo '^(\+?[0-9]{3,15}|[A-Za-z0-9 ]{1,11})$' ;;
    infobip-email-sender) echo '^[^@[:space:]<>]+@[^@[:space:]<>]+\.[^@[:space:]<>]+$' ;;
    database-url) echo '^postgresql\+psycopg://' ;;
    *) echo '' ;;
  esac
}

if (( $# == 0 )); then
  available="$(gcloud secrets list --project="$PROJECT" --format='value(name.basename())')"
  for name in "${names[@]}"; do
    id="$PREFIX-$name"
    if ! grep -qxF "$id" <<<"$available"; then
      state="missing (Terraform has not created it yet)"
    elif [[ -n "$(gcloud secrets versions list "$id" --project="$PROJECT" \
      --filter='state:ENABLED' --limit=1 --format='value(name)')" ]]; then
      state="has a value"
    else
      state="empty"
    fi
    printf '%-26s %s\n' "$name" "$state"
  done
  exit 0
fi

name="${1#"$PREFIX"-}"
if ! printf '%s\n' "${names[@]}" | grep -qxF "$name"; then
  echo "Unknown secret '$name'. Run with no arguments to list them." >&2
  exit 1
fi

IFS= read -rsp "Value for $name (hidden): " value || true
[[ -t 0 ]] && echo >&2
# Pasting on Windows can bring a carriage return; surrounding whitespace is never valid.
value="${value%%$'\r'*}"
if [[ "$name" == infobip-base-url ]]; then
  value="${value#https://}"
  value="${value%/}"
  value="${value,,}"
fi
if [[ -z "$value" || "$value" != "${value#[[:space:]]}" || "$value" != "${value%[[:space:]]}" ]]; then
  echo "Refused: the value is empty or starts or ends with whitespace." >&2
  exit 1
fi
pattern="$(pattern_for "$name")"
if [[ -n "$pattern" ]] && ! [[ "$value" =~ $pattern ]]; then
  # Never echo the value; the format is enough to fix it.
  echo "Refused: $name must match $pattern, or the backend will not start." >&2
  exit 1
fi

printf '%s' "$value" |
  gcloud secrets versions add "$PREFIX-$name" --project="$PROJECT" --data-file=- >/dev/null
unset value
echo "Stored a new value for $name. The next deploy picks it up."
