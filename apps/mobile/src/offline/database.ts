/** The only database port used by the queue; native and real-SQLite tests share SQL. */
export type Bind = string | number | null;
export interface SqlConnection {
  exec(sql: string): Promise<void>;
  run(sql: string, ...params: Bind[]): Promise<{ changes: number }>;
  first<T>(sql: string, ...params: Bind[]): Promise<T | null>;
  all<T>(sql: string, ...params: Bind[]): Promise<T[]>;
}
export interface LocalDatabase extends SqlConnection {
  transaction<T>(work: (tx: SqlConnection) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

// Static, versioned phone-local schema. Never substitute user input here.
export const SCHEMA_V1 = `
CREATE TABLE observations (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, farm_id TEXT NOT NULL,
 payload TEXT NOT NULL, created_at INTEGER NOT NULL,
 sync_state TEXT NOT NULL CHECK(sync_state IN ('pending','syncing','synced','failed','conflict')),
 UNIQUE(id, owner_id, farm_id)
);
CREATE TABLE media (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, farm_id TEXT NOT NULL,
 observation_id TEXT NOT NULL, relative_path TEXT NOT NULL UNIQUE,
 content_type TEXT NOT NULL CHECK(content_type IN ('image/jpeg','image/png')),
 byte_length INTEGER NOT NULL CHECK(byte_length BETWEEN 1 AND 5000000),
 cloud_id TEXT,
 UNIQUE(id, owner_id, farm_id),
 FOREIGN KEY(observation_id, owner_id, farm_id) REFERENCES observations(id, owner_id, farm_id)
);
CREATE TABLE mutations (
 mutation_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, farm_id TEXT NOT NULL,
 entity_type TEXT NOT NULL CHECK(entity_type IN ('observation','media')),
 entity_id TEXT NOT NULL,
 operation TEXT NOT NULL CHECK((entity_type='observation' AND operation='create') OR (entity_type='media' AND operation='upload')),
 payload TEXT NOT NULL, created_at INTEGER NOT NULL,
 attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
 budget_count INTEGER NOT NULL DEFAULT 0 CHECK(budget_count BETWEEN 0 AND 8),
 sync_state TEXT NOT NULL DEFAULT 'pending' CHECK(sync_state IN ('pending','syncing','synced','failed','conflict')),
 next_attempt_at INTEGER NOT NULL DEFAULT 0, dependency_id TEXT,
 error_code TEXT,
 UNIQUE(mutation_id, owner_id, farm_id),
 UNIQUE(entity_type, entity_id, operation, owner_id, farm_id),
 FOREIGN KEY(dependency_id, owner_id, farm_id) REFERENCES mutations(mutation_id, owner_id, farm_id)
);
CREATE INDEX mutations_due ON mutations(owner_id, farm_id, sync_state, next_attempt_at, created_at);
CREATE INDEX observations_scope ON observations(owner_id, farm_id, created_at);
PRAGMA user_version = 1;
`;
