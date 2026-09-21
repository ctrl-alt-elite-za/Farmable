import * as SQLite from 'expo-sqlite';
import type { LocalDatabase, SqlConnection } from './database';

export async function openNativeDatabase(name: string): Promise<LocalDatabase> {
  const db = await SQLite.openDatabaseAsync(name, { useNewConnection: true });
  const connection: SqlConnection = {
    exec: (sql) => db.execAsync(sql),
    run: (sql, ...params) => db.runAsync(sql, params),
    first: <T>(sql: string, ...params: (string | number | null)[]) =>
      db.getFirstAsync<T>(sql, params),
    all: <T>(sql: string, ...params: (string | number | null)[]) => db.getAllAsync<T>(sql, params),
  };
  return {
    ...connection,
    async transaction<T>(work: (tx: SqlConnection) => Promise<T>) {
      // OfflineStore serializes every use of this private connection. BEGIN
      // IMMEDIATE isolates the callback without Expo's ambient async transaction
      // capture, or a second connection missing our FK/durability PRAGMAs.
      await db.execAsync('BEGIN IMMEDIATE');
      try {
        const result = await work(connection);
        await db.execAsync('COMMIT');
        return result;
      } catch (error) {
        await db.execAsync('ROLLBACK');
        throw error;
      }
    },
    close: () => db.closeAsync(),
  };
}
