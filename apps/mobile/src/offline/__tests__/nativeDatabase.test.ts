import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDatabaseAsync } from 'expo-sqlite';
import { openNativeDatabase } from '../nativeDatabase';
import { sqlite } from './sqlite';
import { OfflineStore } from '../store';
import { attachment, farmId, mutationId, observation, ownerId } from './fixtures';

jest.mock('expo-sqlite', () => ({ openDatabaseAsync: jest.fn() }));

test('native SQL adapter keeps transactions and PRAGMAs on its private connection', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'farmable-native-port-'));
  const path = join(directory, 'queue.db');
  const raw = sqlite(path);
  const execAsync = jest.fn(raw.exec.bind(raw));
  const closeAsync = jest.fn(raw.close.bind(raw));
  jest.mocked(openDatabaseAsync).mockResolvedValue({
    execAsync,
    runAsync: (sql: string, params: (string | number | null)[]) => raw.run(sql, ...params),
    getFirstAsync: (sql: string, params: (string | number | null)[]) => raw.first(sql, ...params),
    getAllAsync: (sql: string, params: (string | number | null)[]) => raw.all(sql, ...params),
    closeAsync,
  } as unknown as Awaited<ReturnType<typeof openDatabaseAsync>>);
  const db = await openNativeDatabase('queue.db');
  const store = await OfflineStore.open(db, { ownerId, farmId });
  try {
    expect(openDatabaseAsync).toHaveBeenCalledWith('queue.db', { useNewConnection: true });
    expect(await db.first('PRAGMA foreign_keys')).toEqual({ foreign_keys: 1 });
    expect(await db.first('PRAGMA synchronous')).toEqual({ synchronous: 2 });
    await db.exec(
      "CREATE TRIGGER reject_mutation BEFORE INSERT ON mutations BEGIN SELECT RAISE(ABORT, 'test_failure'); END;",
    );
    await expect(store.enqueue(observation, mutationId, 1000, attachment)).rejects.toThrow(
      'test_failure',
    );
    expect(execAsync).toHaveBeenCalledWith('BEGIN IMMEDIATE');
    expect(execAsync).toHaveBeenCalledWith('ROLLBACK');
    expect(await db.all('SELECT * FROM observations')).toHaveLength(0);
    await db.exec('DROP TRIGGER reject_mutation');
    await store.enqueue(observation, mutationId, 1000, attachment);
    expect(execAsync).toHaveBeenCalledWith('COMMIT');
  } finally {
    await store.close();
    await rm(directory, { recursive: true });
  }
  expect(closeAsync).toHaveBeenCalledTimes(1);
});
