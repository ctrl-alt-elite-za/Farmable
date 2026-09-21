# Almanac mobile

Flutter 3.47.1 application scaffold, design tokens and client for the local demo
planning API. The current screen reports connectivity; authentication and the
production farm, observation, task and finance endpoints are not implemented here.

## Run and test

From `apps/mobile`:

```sh
flutter pub get --enforce-lockfile
flutter run --dart-define=API_URL=https://your-api.example
flutter analyze
flutter test --exclude-tags demo-api
dart run tool/generate_tokens.dart --verify
```

From the repository root, run the API contract tests:

```sh
uv run python scripts/test_mobile_contract.py
```

The Linux/macOS runner starts an isolated demo API on an ephemeral loopback port,
runs the Flutter contract tests, and cleans up its server and temporary database.
CI runs both test suites. Selected contract tests fail when the backend is absent;
they never silently pass without exercising it.

## Mutations and retries

Every section or plan mutation requires a caller-supplied `mutationId`. Generate
and persist it with the user action, then reuse it with the identical payload on
every retry, including after restart. A timeout can happen after the server has
committed the change. Use a new ID for a new action. This repository provides the
HTTP contract; a durable local mutation queue remains separate work.

Release CI validates device API URLs with `scripts/mobile-api.mjs`. Without a
configured URL, artifacts are explicitly labelled compile-only and remain offline.
The emulator uses `http://10.0.2.2:8000`; physical devices need a reachable HTTPS API.
