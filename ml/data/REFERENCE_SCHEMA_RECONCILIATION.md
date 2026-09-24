# Issue 20 reference-schema reconciliation

**Reviewed:** 23 September 2026 against `origin/main` at `f375c0a`.

**Implementation update:** the runner branch now integrates `origin/main` at
`73e2c62`, including `0016_assistant_usage`. Reference migration `0017` revises
`0016` and adds the four reference tables without changing farmer-owned data.
Canonical crop identifiers are constrained to the eight supported values rather
than seeded in a separate lookup table. The import identity retains source filename,
source hash, payload hash, parser version, row count and creation time. Market rows
explicitly distinguish publication availability from analytical next-month
eligibility. Offline migration/ORM parity and SQLite transaction/race tests pass;
PostgreSQL migration and race tests are wired into the disposable integration
harness but still require execution. The original review and plan below are kept
as context, not as the current migration numbering.

Issue #8 was delivered by merge `bd1bb36` (PR #42). Its ORM models and migration
cover farmer-owned operational and synchronization data: users, farms, sections,
plantings, media, observations, tasks, financial records, saved plans, sync
mutations and sync changes. They do not define canonical crops, market prices,
crop calendars, costs or source imports.

`Planting.crop` is bounded nonblank text rather than a foreign key or canonical
identifier. Existing farmer data may contain arbitrary crop names. Issue #20 must
not convert that field to a reference-data foreign key or otherwise couple the
farmer schema to the eight-crop experiment contract.

Current `origin/main` has a single Alembic chain through
`0008_weather_climatology.py`; this stacked branch contains migrations only
through `0005`. Creating a migration numbered `0006` here would collide with
main's voice, forecast and weather migrations. Reference-schema implementation
must first integrate current main and then add `0009` revising `0008`. Apparent
deletions of current forecast/weather/voice files in branch comparisons are a
base-version artifact and must not be carried forward.

## Reusable contracts

Current main's forecast import path already demonstrates bounded file discovery,
input-size limits, SHA-256 identity, full Pydantic validation, ORM-only atomic
transactions, identical-import no-ops, changed-source conflicts, row locking and
PostgreSQL rollback/concurrency tests. Issue #20 should reuse those patterns while
keeping reference datasets separate from forecast-run payload tables.

The ML package already defines the eight canonical crop IDs and aliases,
`PriceObservation`, strict first-of-month price records and source hashes.
`VersionedValue` defines separate effective/availability dates, revisions and
strict as-of selection for costs and calendars.

## Additive schema plan

After reconciling with main:

1. Add a `0009` migration and matching ORM models. Leave Issue #8 tables intact.
2. Add canonical reference crops keyed by the eight ML identifiers. Seed through
   Alembic bulk operations, never handwritten SQL.
3. Add a reference-import identity table containing dataset kind/key, source hash,
   parser version, expected/actual row counts and timestamps.
4. Add normalized market-price rows with crop, market, observation month,
   availability date, positive ZAR/kg value and natural-key uniqueness.
5. Add versioned calendar and cost rows with region, effective/availability dates,
   revision, units and the protocol-approved calendar, VAT and marketing fields.
6. Parse, hash and validate the complete source before opening the transaction.
   In one ORM transaction, return a no-op for an identical logical import, reject
   changed bytes, persist all rows, verify the row count and commit atomically.
7. Cover ORM/migration parity, rollback, retry, natural-key uniqueness,
   concurrency and import idempotence on SQLite and PostgreSQL.

Real rows remain blocked by the source gates. Synthetic fixtures may exercise the
schema/import machinery, but the staged 2026 Joburg scrape, unknown market
release dates and unapproved calendar/cost values cannot be imported as historical
evidence.
