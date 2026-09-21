import { DatabaseSync } from 'node:sqlite';
import type { Bind, LocalDatabase, SqlConnection } from '../database';

/** Real SQLite, not a SQL interpreter mock. Each test owns its disposable file. */
export function sqlite(path: string): LocalDatabase {
  const db = new DatabaseSync(path);
  const connection: SqlConnection = {
    async exec(sql) {
      db.exec(sql);
    },
    async run(sql, ...params: Bind[]) {
      return { changes: Number(db.prepare(sql).run(...params).changes) };
    },
    async first<T>(sql: string, ...params: Bind[]) {
      return (db.prepare(sql).get(...params) as T) ?? null;
    },
    async all<T>(sql: string, ...params: Bind[]) {
      return db.prepare(sql).all(...params) as T[];
    },
  };
  return {
    ...connection,
    async transaction<T>(work: (tx: SqlConnection) => Promise<T>) {
      db.exec('BEGIN IMMEDIATE');
      try {
        const result = await work(connection);
        db.exec('COMMIT');
        return result;
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    },
    async close() {
      db.close();
    },
  };
}
