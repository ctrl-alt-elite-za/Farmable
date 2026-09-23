FROM ghcr.io/astral-sh/uv:0.12.15 AS uv
FROM python:3.12.14-slim AS base
COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PATH="/app/.venv/bin:$PATH"
COPY pyproject.toml uv.lock alembic.ini ./
COPY apps/backend apps/backend
COPY migrations migrations
COPY scripts scripts
COPY e2e e2e
COPY infra/cloudrun-entrypoint.sh /app/cloudrun-entrypoint.sh
COPY infra/cloudrun-migrate.sh /app/cloudrun-migrate.sh
COPY conftest.py ./
RUN uv sync --locked --no-dev && useradd --create-home farmable

FROM base AS testing
COPY ml/forecast/fixtures ml/forecast/fixtures
RUN uv sync --locked
USER farmable

FROM base AS forecast-import
COPY ml/forecast/results ml/forecast/results
USER farmable

FROM base AS runtime
USER farmable
EXPOSE 8000
CMD ["uvicorn", "farmable_backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-proxy-headers", "--no-access-log", "--log-config", "apps/backend/logging.json"]
