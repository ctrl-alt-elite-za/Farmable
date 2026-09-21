import { SCHEMA_V1, type LocalDatabase, type SqlConnection } from './database';
import { normalizeObservation, OfflineError, payload, scope, timestamp, uuid } from './types';
import type { Media, Mutation, Observation, ObservationInput, Scope, SyncState } from './types';

export interface Attachment {
  media: Media;
  mutationId: string;
}
interface ObservationRow {
  payload: string;
  created_at: number;
  sync_state: SyncState;
}
interface MediaRow {
  id: string;
  owner_id: string;
  farm_id: string;
  relative_path: string;
  content_type: Media['contentType'];
  byte_length: number;
  cloud_id: string | null;
}

/** Owns its connection. All operations are serialized, including reads and close. */
export class OfflineStore {
  readonly scope: Readonly<Scope>;
  private tail: Promise<unknown> = Promise.resolve();
  private closed = false;
  private constructor(
    private readonly db: LocalDatabase,
    value: Scope,
  ) {
    this.scope = Object.freeze(scope(value));
  }

  static async open(db: LocalDatabase, value: Scope): Promise<OfflineStore> {
    try {
      const store = new OfflineStore(db, value);
      await db.exec(
        'PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 1000; PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL;',
      );
      await db.transaction(async (tx) => {
        const version = await tx.first<{ user_version: number }>('PRAGMA user_version');
        if (version?.user_version === 0) await tx.exec(SCHEMA_V1);
        else if (version?.user_version !== 1) throw new OfflineError('unsupported_schema');
        await tx.run(
          `UPDATE mutations SET sync_state = CASE WHEN budget_count >= 8 THEN 'failed' ELSE 'pending' END,
          error_code = 'interrupted' WHERE owner_id = ? AND farm_id = ? AND sync_state = 'syncing'`,
          value.ownerId,
          value.farmId,
        );
      });
      return store;
    } catch (error) {
      await db.close();
      throw error;
    }
  }

  private serial<T>(work: () => Promise<T>): Promise<T> {
    if (this.closed) return Promise.reject(new OfflineError('store_closed'));
    const result = this.tail.then(work);
    this.tail = result.catch(() => undefined);
    return result;
  }
  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    await this.tail;
    await this.db.close();
  }
  private get ids(): [string, string] {
    return [this.scope.ownerId, this.scope.farmId];
  }

  enqueue(
    input: ObservationInput,
    mutationId: string,
    now: number,
    attachment?: Attachment,
  ): Promise<Observation> {
    const normalized = normalizeObservation(input);
    uuid(mutationId);
    timestamp(now);
    const logical = payload({ ...normalized, localMediaId: attachment?.media.id ?? null });
    if (attachment) {
      const m = attachment.media;
      uuid(m.id);
      uuid(attachment.mutationId);
      if (
        m.ownerId !== this.scope.ownerId ||
        m.farmId !== this.scope.farmId ||
        !['image/jpeg', 'image/png'].includes(m.contentType) ||
        m.relativePath !==
          `${m.ownerId}/${m.farmId}/${m.id}.${m.contentType === 'image/jpeg' ? 'jpg' : 'png'}` ||
        !Number.isInteger(m.byteLength) ||
        m.byteLength < 1 ||
        m.byteLength > 5000000
      )
        throw new OfflineError('invalid_media');
    }
    return this.serial(() =>
      this.db.transaction(async (tx) => {
        const existing = await tx.first<Mutation>(
          'SELECT * FROM mutations WHERE mutation_id = ?',
          mutationId,
        );
        if (existing) {
          if (
            existing.owner_id !== this.scope.ownerId ||
            existing.farm_id !== this.scope.farmId ||
            existing.payload !== logical ||
            existing.entity_type !== 'observation' ||
            existing.dependency_id !== (attachment?.mutationId ?? null)
          )
            throw new OfflineError('mutation_reused');
          if (attachment) {
            const prior = await tx.first<MediaRow>(
              'SELECT * FROM media WHERE id = ? AND owner_id = ? AND farm_id = ?',
              attachment.media.id,
              ...this.ids,
            );
            if (
              !prior ||
              prior.byte_length !== attachment.media.byteLength ||
              prior.content_type !== attachment.media.contentType ||
              prior.relative_path !== attachment.media.relativePath
            )
              throw new OfflineError('mutation_reused');
          }
          return (await this.readObservations(tx, normalized.id))[0];
        }
        if (attachment?.media.cloudId) throw new OfflineError('invalid_media');
        await tx.run(
          'INSERT INTO observations(id, owner_id, farm_id, payload, created_at, sync_state) VALUES (?, ?, ?, ?, ?, ?)',
          normalized.id,
          ...this.ids,
          logical,
          now,
          'pending',
        );
        if (attachment) {
          const m = attachment.media;
          await tx.run(
            `INSERT INTO media(id, owner_id, farm_id, observation_id, relative_path, content_type, byte_length) VALUES (?, ?, ?, ?, ?, ?, ?)`,
            m.id,
            ...this.ids,
            normalized.id,
            m.relativePath,
            m.contentType,
            m.byteLength,
          );
          await this.insertMutation(
            tx,
            attachment.mutationId,
            'media',
            m.id,
            'upload',
            payload({ id: m.id, contentType: m.contentType, byteLength: m.byteLength }),
            now,
            null,
          );
        }
        await this.insertMutation(
          tx,
          mutationId,
          'observation',
          normalized.id,
          'create',
          logical,
          now,
          attachment?.mutationId ?? null,
        );
        return (await this.readObservations(tx, normalized.id))[0];
      }),
    );
  }

  private async insertMutation(
    tx: SqlConnection,
    id: string,
    entity: string,
    entityId: string,
    operation: string,
    body: string,
    now: number,
    dependency: string | null,
  ): Promise<void> {
    await tx.run(
      `INSERT INTO mutations(mutation_id, owner_id, farm_id, entity_type, entity_id, operation, payload, created_at, dependency_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id,
      ...this.ids,
      entity,
      entityId,
      operation,
      body,
      now,
      dependency,
    );
  }
  private async readObservations(
    tx: SqlConnection,
    id: string | null = null,
  ): Promise<Observation[]> {
    const rows = await tx.all<ObservationRow>(
      `SELECT o.payload, o.created_at, m.sync_state FROM observations o
      JOIN mutations m ON m.entity_id = o.id AND m.entity_type = 'observation' AND m.owner_id = o.owner_id AND m.farm_id = o.farm_id
      WHERE o.owner_id = ? AND o.farm_id = ? AND (? IS NULL OR o.id = ?) ORDER BY o.created_at, o.id`,
      ...this.ids,
      id,
      id,
    );
    return rows.map((row) => ({
      ...JSON.parse(row.payload),
      ...this.scope,
      createdAt: row.created_at,
      updatedAt: row.created_at,
      version: 1,
      syncState: row.sync_state,
    }));
  }
  observations(): Promise<Observation[]> {
    return this.serial(() => this.readObservations(this.db));
  }
  mutations(): Promise<Mutation[]> {
    return this.serial(() =>
      this.db.all<Mutation>(
        'SELECT * FROM mutations WHERE owner_id = ? AND farm_id = ? ORDER BY created_at, mutation_id',
        ...this.ids,
      ),
    );
  }
  media(id: string): Promise<Media | null> {
    uuid(id);
    return this.serial(async () => {
      const row = await this.db.first<MediaRow>(
        'SELECT * FROM media WHERE id = ? AND owner_id = ? AND farm_id = ?',
        id,
        ...this.ids,
      );
      return row
        ? {
            id: row.id,
            ...this.scope,
            relativePath: row.relative_path,
            contentType: row.content_type,
            byteLength: row.byte_length,
            cloudId: row.cloud_id,
          }
        : null;
    });
  }

  claim(now: number): Promise<Mutation | null> {
    timestamp(now);
    return this.serial(() =>
      this.db.transaction(async (tx) => {
        // A store has one runner. The SQL guard also prevents accidental second claims.
        const active = await tx.first(
          'SELECT mutation_id FROM mutations WHERE owner_id = ? AND farm_id = ? AND sync_state = ?',
          ...this.ids,
          'syncing',
        );
        if (active) return null;
        const row = await tx.first<Mutation>(
          `SELECT m.* FROM mutations m WHERE m.owner_id = ? AND m.farm_id = ?
        AND m.sync_state = 'pending' AND m.budget_count < 8 AND m.next_attempt_at <= ?
        AND (m.dependency_id IS NULL OR EXISTS (SELECT 1 FROM mutations d WHERE d.mutation_id = m.dependency_id AND d.owner_id = m.owner_id AND d.farm_id = m.farm_id AND d.sync_state = 'synced'))
        ORDER BY m.created_at, m.mutation_id LIMIT 1`,
          ...this.ids,
          now,
        );
        if (!row) return null;
        await tx.run(
          "UPDATE mutations SET sync_state = 'syncing', attempt_count = attempt_count + 1, budget_count = budget_count + 1, error_code = NULL WHERE mutation_id = ? AND owner_id = ? AND farm_id = ?",
          row.mutation_id,
          ...this.ids,
        );
        return {
          ...row,
          sync_state: 'syncing',
          attempt_count: row.attempt_count + 1,
          budget_count: row.budget_count + 1,
          error_code: null,
        };
      }),
    );
  }
  nextDue(): Promise<number | null> {
    return this.serial(async () => {
      const result = await this.db.first<{ due: number | null }>(
        `SELECT MIN(m.next_attempt_at) AS due FROM mutations m
        WHERE m.owner_id = ? AND m.farm_id = ? AND m.sync_state = 'pending' AND m.budget_count < 8
        AND (m.dependency_id IS NULL OR EXISTS (SELECT 1 FROM mutations d WHERE d.mutation_id = m.dependency_id AND d.owner_id = m.owner_id AND d.farm_id = m.farm_id AND d.sync_state = 'synced'))`,
        ...this.ids,
      );
      return result?.due ?? null;
    });
  }
  acknowledge(mutation: Mutation, cloudId?: string): Promise<void> {
    if (mutation.entity_type === 'media') uuid(cloudId!);
    return this.serial(() =>
      this.db.transaction(async (tx) => {
        const result = await tx.run(
          `UPDATE mutations SET sync_state = 'synced', error_code = NULL
        WHERE mutation_id = ? AND owner_id = ? AND farm_id = ? AND sync_state = 'syncing' AND attempt_count = ?`,
          mutation.mutation_id,
          ...this.ids,
          mutation.attempt_count,
        );
        if (result.changes !== 1) throw new OfflineError('stale_claim');
        if (mutation.entity_type === 'media') {
          const changed = await tx.run(
            'UPDATE media SET cloud_id = ? WHERE id = ? AND owner_id = ? AND farm_id = ?',
            cloudId!,
            mutation.entity_id,
            ...this.ids,
          );
          if (changed.changes !== 1) throw new OfflineError('missing_media');
        }
      }),
    );
  }
  release(
    mutation: Mutation,
    state: 'pending' | 'failed' | 'conflict',
    code: string,
    due: number,
    refund = false,
  ): Promise<void> {
    timestamp(due);
    if (!/^[a-z_]{1,40}$/.test(code)) throw new OfflineError('invalid_error_code');
    return this.serial(async () => {
      const result = await this.db.run(
        `UPDATE mutations SET sync_state = ?, error_code = ?, next_attempt_at = ?, budget_count = budget_count - ?
        WHERE mutation_id = ? AND owner_id = ? AND farm_id = ? AND sync_state = 'syncing' AND attempt_count = ?`,
        state,
        code,
        due,
        refund ? 1 : 0,
        mutation.mutation_id,
        ...this.ids,
        mutation.attempt_count,
      );
      if (result.changes !== 1) throw new OfflineError('stale_claim');
    });
  }
  retry(id: string): Promise<void> {
    uuid(id);
    return this.serial(async () => {
      const result = await this.db.run(
        "UPDATE mutations SET sync_state = 'pending', budget_count = 0, next_attempt_at = 0, error_code = NULL WHERE mutation_id = ? AND owner_id = ? AND farm_id = ? AND sync_state = 'failed'",
        id,
        ...this.ids,
      );
      if (result.changes !== 1) throw new OfflineError('not_retryable');
    });
  }
}
