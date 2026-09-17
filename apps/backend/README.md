# apps/backend

FastAPI API and Procrastinate worker sharing `src/farmable_backend`. Feature
tables and endpoints belong to later issues; the initial Alembic migration is empty.

## Run locally

Install dependencies with `make setup`. Copy `.env.example` to `.env`, replace the
password in both `POSTGRES_PASSWORD` and `DATABASE_URL`, and keep that file local.
Docker Compose reads it automatically. `DATABASE_URL` must use the `database`
hostname and percent-encoded credentials, matching the same login used by Postgres.

```bash
docker compose up -d --wait database
docker compose run --rm migrate
docker compose run --rm queue-schema  # once, on a new database
docker compose up --build api worker
```

The API is at `http://localhost:8000`, docs at `/docs`, and OpenAPI at `/openapi.json`.
`COMMIT_SHA` identifies the build; set it to `git rev-parse HEAD` when running Compose.
No migrations are run by API or worker startup. Deployment/migration orchestration
is #6. Queue schema changes must use Procrastinate's vendor migration tooling;
never copy its SQL into this repository or rerun initial schema installation.

The database has no published port by default. If running the API on the host,
forward a local-only database port with a Compose override and export `DATABASE_URL`
from the environment (the app never reads `.env` itself). Credentials with URL
special characters must be percent-encoded in the URL. The example password is
only a placeholder, never a production credential. Use the same database login
for API, worker, and migration commands.

To defer the example job:

```bash
docker compose exec worker python -m farmable_backend.manage example-job
```

## Safe defaults

- `/health/live` reports process liveness without checking dependencies.
- `/health/ready` checks the database via an ORM catalog model and looks for a
  Procrastinate heartbeat newer than 30 seconds (worker updates every 5 seconds).
  It returns only `database`, `worker`, and `sha`, with 503 on dependency failure.
- Every request has a validated/generated UUID in `X-Request-ID`, ASGI request
  state, and JSON log context. Outside requests, logs use `system`.
- All errors use `{"error":{"code":"...","message":"..."}}`. Validation errors
  never echo input, and internal errors never expose tracebacks. Health dependency
  failures intentionally use the health response schema instead of the error schema.
- Request DTOs inherit `StrictModel` (`extra="forbid"`). Test-only endpoints prove
  this without adding a public feature endpoint.
- A sliding 60-second window allows 120 requests per peer IP, then returns 429
  and `Retry-After`. Forwarding headers are not trusted. Run **one API process**:
  this in-memory limiter is not shared between replicas. Distributed deployment
  must introduce a shared limiter before adding API replicas/workers (#6).
- JSON logging masks phones (e.g. `+27******567`), emails, tokens, codes, and
  coordinates, including nested structured fields. Never log request bodies or
  credentials. Vendor job messages are replaced with a generic queue event because
  Procrastinate embeds arbitrary task arguments in them. Exceptions are not serialized.
- PostgreSQL connections impose a 5-second statement timeout, including worker
  connections. All application queries use ORM expressions, never SQL strings.
  Procrastinate owns its schema and internal queries; PostGIS is initialized by
  the Docker image. Their tables are excluded from application autogeneration,
  not from the raw-SQL scanner.

## Tests and API client

```bash
make test
make check-no-raw-sql
make test-integration
make client
pnpm -C apps/mobile typecheck
```

Unit tests need no database. Integration tests require Docker Compose v2+,
create a unique project with random credentials and a random local API port, and clean up only
that project's containers/volume. They exercise real jobs, unchanged-model
autogeneration, stopped/stale workers, recovery, and a stopped database while
liveness stays healthy. The runner never touches the development database.

`make client` generates the schema and typed `openapi-fetch` wrapper from the
actual app without connecting to a database. Generated files must not be edited.
`apps/mobile/tests/api-contract.ts` is a compile-time consumer; the Expo UI is #4.
