# Local fallback demo backend (not for staging or production).
# Fake integrations: sign-up codes are 111111 (phone) and 222222 (email), the
# assistant answers with the scripted fake model, and nothing is billed.
export DATABASE_URL='postgresql+psycopg://farmable:farmable-local@127.0.0.1:5433/farmable'
export COMMIT_SHA=local-demo
export ENVIRONMENT=ci
export INTEGRATIONS_MODE=fake
export FORECAST_DATA_MODE=retrospective
export ASSISTANT_ENABLED=true
export ASSISTANT_DAILY_BUDGET_MICRO_USD=1000000
export ASSISTANT_TURN_RESERVE_MICRO_USD=1000
export ASSISTANT_POLICY_DATE="$(date -u +%F)"
export ASSISTANT_POLICY_MODEL=fixture-model
export UV_PYTHON=3.12
