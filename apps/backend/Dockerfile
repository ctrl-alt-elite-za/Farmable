FROM ghcr.io/astral-sh/uv:0.12.15 AS uv
FROM python:3.12.14-slim
COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PATH="/app/.venv/bin:$PATH"
COPY pyproject.toml uv.lock alembic.ini ./
COPY apps/backend apps/backend
COPY migrations migrations
COPY scripts scripts
RUN uv sync --locked && useradd --create-home farmable
USER farmable
EXPOSE 8000
CMD ["uvicorn", "farmable_backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-proxy-headers", "--no-access-log", "--log-config", "apps/backend/logging.json"]
