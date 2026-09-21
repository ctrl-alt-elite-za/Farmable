import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { OfflineStore } from '../store';
import { sqlite } from './sqlite';
import {
  attachment,
  cloudId,
  farmId,
  mutationId,
  observation,
  otherId,
  ownerId,
  uploadId,
} from './fixtures';
import { normalizeObservation, payload } from '../types';

test('committed observation and pending mutation survive a real database reopen', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'farmable-queue-'));
  const path = join(directory, 'queue.db');
  let store = await OfflineStore.open(sqlite(path), { ownerId, farmId });
  try {
    await store.enqueue(observation, mutationId, 1000);
    await store.close();
    store = await OfflineStore.open(sqlite(path), { ownerId, farmId });
    expect((await store.observations())[0].note).toBe('Saved offline');
    expect((await store.mutations())[0]).toMatchObject({
      mutation_id: mutationId,
      sync_state: 'pending',
      attempt_count: 0,
    });
  } finally {
    await store.close();
    await rm(directory, { recursive: true });
  }
});

describe('transaction and queue invariants', () => {
  let db: ReturnType<typeof sqlite>;
  let store: OfflineStore;
  beforeEach(async () => {
    db = sqlite(':memory:');
    store = await OfflineStore.open(db, { ownerId, farmId });
  });
  afterEach(async () => {
    await store.close();
  });

  test('duplicate ID is idempotent; changed payload is rejected', async () => {
    const first = await store.enqueue(observation, mutationId, 100);
    expect(await store.enqueue({ ...observation }, mutationId, 200)).toEqual(first);
    await expect(
      store.enqueue({ ...observation, note: 'Changed' }, mutationId, 200),
    ).rejects.toThrow('mutation_reused');
    expect(await store.observations()).toHaveLength(1);
    expect(await store.mutations()).toHaveLength(1);
  });
  test('concurrent enqueues serialize without duplicate records', async () => {
    await Promise.all(Array.from({ length: 5 }, () => store.enqueue(observation, mutationId, 100)));
    expect(await store.mutations()).toHaveLength(1);
  });
  test('a new mutation for an existing entity does not replace it', async () => {
    await store.enqueue(observation, mutationId, 100);
    await expect(
      store.enqueue({ ...observation, note: 'Changed' }, otherId, 200),
    ).rejects.toThrow();
    expect((await store.observations())[0].note).toBe(observation.note);
  });
  test('failure after observation insert rolls all rows back', async () => {
    await db.exec(
      "CREATE TRIGGER reject_mutation BEFORE INSERT ON mutations BEGIN SELECT RAISE(ABORT, 'synthetic_full'); END;",
    );
    await expect(store.enqueue(observation, mutationId, 100, attachment)).rejects.toThrow(
      'synthetic_full',
    );
    expect(await db.all('SELECT * FROM observations')).toHaveLength(0);
    expect(await db.all('SELECT * FROM media')).toHaveLength(0);
    expect(await store.mutations()).toHaveLength(0);
  });
  test('photo dependency precedes observation and persists cloud ID atomically', async () => {
    await store.enqueue(observation, mutationId, 100, attachment);
    const upload = (await store.claim(100))!;
    expect(upload.mutation_id).toBe(uploadId);
    expect(await store.claim(100)).toBeNull();
    await store.acknowledge(upload, cloudId);
    expect((await store.media(attachment.media.id))?.cloudId).toBe(cloudId);
    expect((await store.claim(100))?.mutation_id).toBe(mutationId);
  });
  test('failed upload blocks only its dependent observation', async () => {
    await store.enqueue(observation, mutationId, 100, attachment);
    await store.enqueue({ ...observation, id: otherId }, cloudId, 101);
    await store.release((await store.claim(200))!, 'failed', 'validation', 200);
    expect((await store.claim(200))?.mutation_id).toBe(cloudId);
    expect(await store.observations()).toHaveLength(2);
  });
  test('deadline persists; manual retry resets budget but not total attempt history', async () => {
    await store.enqueue(observation, mutationId, 100);
    const claimed = (await store.claim(100))!;
    await store.release(claimed, 'pending', 'transient', 500);
    expect(await store.claim(499)).toBeNull();
    const next = (await store.claim(500))!;
    await store.release(next, 'failed', 'validation', 500);
    await store.retry(mutationId);
    expect((await store.mutations())[0]).toMatchObject({
      attempt_count: 2,
      budget_count: 0,
      sync_state: 'pending',
    });
  });
  test('conflicts cannot be silently retried', async () => {
    await store.enqueue(observation, mutationId, 100);
    await store.release((await store.claim(100))!, 'conflict', 'conflict', 100);
    await expect(store.retry(mutationId)).rejects.toThrow('not_retryable');
  });
  test('stale completion cannot acknowledge a subsequent claim', async () => {
    await store.enqueue(observation, mutationId, 100);
    const old = (await store.claim(100))!;
    await store.release(old, 'pending', 'cancelled', 100, true);
    await store.claim(100);
    await expect(store.acknowledge(old)).rejects.toThrow('stale_claim');
    expect((await store.mutations())[0].sync_state).toBe('syncing');
  });
  test('user text is parameter-bound, not executable SQL', async () => {
    const note = "'); DROP TABLE observations; --";
    await store.enqueue({ ...observation, note }, mutationId, 100);
    expect((await store.observations())[0].note).toBe(note);
  });
  test('schema foreign keys reject cross-scope dependencies', async () => {
    await store.enqueue(observation, mutationId, 100, attachment);
    await expect(
      db.run('UPDATE mutations SET farm_id = ? WHERE mutation_id = ?', otherId, mutationId),
    ).rejects.toThrow();
  });
  test('closed store refuses operations rather than using a disposed connection', async () => {
    await store.close();
    await expect(store.mutations()).rejects.toThrow('store_closed');
  });
});

test.each(['owner', 'farm'])(
  'separate %s scope cannot read or claim existing records',
  async (kind) => {
    const directory = await mkdtemp(join(tmpdir(), 'farmable-scope-'));
    const path = join(directory, 'queue.db');
    let store = await OfflineStore.open(sqlite(path), { ownerId, farmId });
    try {
      await store.enqueue(observation, mutationId, 100, attachment);
      await store.close();
      store = await OfflineStore.open(sqlite(path), {
        ownerId: kind === 'owner' ? otherId : ownerId,
        farmId: kind === 'farm' ? otherId : farmId,
      });
      expect(await store.observations()).toEqual([]);
      expect(await store.mutations()).toEqual([]);
      expect(await store.media(attachment.media.id)).toBeNull();
      expect(await store.claim(100)).toBeNull();
      await expect(store.enqueue(observation, mutationId, 100)).rejects.toThrow('mutation_reused');
    } finally {
      await store.close();
      await rm(directory, { recursive: true });
    }
  },
);

test.each([1, 8])(
  'reopen recovers interrupted work at attempt %i without resetting the budget',
  async (attempts) => {
    const directory = await mkdtemp(join(tmpdir(), 'farmable-recovery-'));
    const path = join(directory, 'queue.db');
    let store = await OfflineStore.open(sqlite(path), { ownerId, farmId });
    try {
      await store.enqueue(observation, mutationId, 100);
      for (let i = 1; i <= attempts; i++) {
        const claim = (await store.claim(100))!;
        if (i < attempts) await store.release(claim, 'pending', 'transient', 100);
      }
      await store.close();
      store = await OfflineStore.open(sqlite(path), { ownerId, farmId });
      expect((await store.mutations())[0]).toMatchObject({
        attempt_count: attempts,
        budget_count: attempts,
        sync_state: attempts === 8 ? 'failed' : 'pending',
      });
      expect(await store.observations()).toHaveLength(1);
    } finally {
      await store.close();
      await rm(directory, { recursive: true });
    }
  },
);

test('unknown schema fails closed and preserves data', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'farmable-version-'));
  const path = join(directory, 'queue.db');
  const db = sqlite(path);
  await db.exec(
    "CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES ('keep'); PRAGMA user_version = 42;",
  );
  await db.close();
  try {
    await expect(OfflineStore.open(sqlite(path), { ownerId, farmId })).rejects.toThrow(
      'unsupported_schema',
    );
    const check = sqlite(path);
    try {
      expect(await check.first('SELECT value FROM sentinel')).toEqual({ value: 'keep' });
    } finally {
      await check.close();
    }
  } finally {
    await rm(directory, { recursive: true });
  }
});

test.each([
  { id: '../invalid' },
  { sectionId: '' },
  { note: ' ' },
  { note: 'x'.repeat(10001) },
  { type: 'x'.repeat(101) },
  { healthStatus: 'x'.repeat(101) },
  { createdByVoice: 'yes' },
])('invalid observation fails validation case %#', (change) => {
  expect(() => normalizeObservation({ ...observation, ...change } as typeof observation)).toThrow();
});
test('UTF-8 payload limit includes multibyte characters', () => {
  expect(() => payload('🌱'.repeat(17000))).toThrow('payload_too_large');
  expect(() => payload('\ud800')).not.toThrow(); // JSON escapes isolated surrogates.
});
