# Generated API client

Run `make client` at the repo root after changing API models or routes. This
regenerates `openapi.json`, `src/schema.d.ts`, and `src/index.ts` from FastAPI;
never hand-edit these files.

```ts
import { createApiClient } from '@farmable/api-client';

const api = createApiClient('http://localhost:8000');
const { data, error } = await api.GET('/health/ready');
```

`pnpm -C apps/mobile typecheck` verifies a typed consumer against this schema.
The checked-in OpenAPI snapshot is also compared with the live application schema
in a unit test. Unknown routes and invalid response status values fail type checks.
