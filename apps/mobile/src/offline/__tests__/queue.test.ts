import { MutationQueue, retryDelay } from '../queue';
import type { Acknowledgement, Delivery } from '../queue';
import { OfflineStore } from '../store';
import { TransportError } from '../types';
import type { FailureKind } from '../types';
import { attachment, cloudId, farmId, mutationId, observation, otherId, ownerId } from './fixtures';
import { sqlite } from './sqlite';

const ready = { online: true, foreground: true, authenticated: true };
function acknowledgement({ mutation }: Delivery): Acknowledgement {
  return {
    ownerId: mutation.owner_id,
    farmId: mutation.farm_id,
    mutationId: mutation.mutation_id,
    entityId: mutation.entity_id,
    ...(mutation.entity_type === 'media' ? { cloudMediaId: cloudId } : {}),
  };
}

describe('queue using real SQLite and a fake transport', () => {
  let store: OfflineStore;
  let queue: MutationQueue;
  let send: jest.Mock<Promise<Acknowledgement>, [Delivery, AbortSignal]>;
  let photoUri: jest.Mock<Promise<string>, []>;
  beforeEach(async () => {
    jest.useFakeTimers();
    jest.setSystemTime(1000);
    store = await OfflineStore.open(sqlite(':memory:'), { ownerId, farmId });
    send = jest
      .fn<Promise<Acknowledgement>, [Delivery, AbortSignal]>()
      .mockImplementation(async (delivery) => acknowledgement(delivery));
    photoUri = jest.fn(async () => 'file:///private/photo.png');
    queue = new MutationQueue(store, { transport: { send }, photoUri, random: () => 1 });
  });
  afterEach(async () => {
    await queue.stop();
    await store.close();
    jest.useRealTimers();
  });

  test.each(['online', 'foreground', 'authenticated'])(
    'no attempts while %s is false',
    async (key) => {
      await store.enqueue(observation, mutationId, 1000);
      await queue.setConditions({ ...ready, [key]: false });
      expect(send).not.toHaveBeenCalled();
      expect((await store.mutations())[0].attempt_count).toBe(0);
      await queue.setConditions(ready);
      expect((await store.mutations())[0].sync_state).toBe('synced');
    },
  );
  test('absent transport never fabricates synced state', async () => {
    await queue.stop();
    queue = new MutationQueue(store, { photoUri });
    await store.enqueue(observation, mutationId, 1000);
    await queue.setConditions(ready);
    expect((await store.mutations())[0]).toMatchObject({ sync_state: 'pending', attempt_count: 0 });
  });
  test('photo acknowledgement is durable before dependent observation is sent', async () => {
    await store.enqueue(observation, mutationId, 1000, attachment);
    send.mockImplementation(async (delivery) => {
      if (delivery.mutation.entity_type === 'observation') {
        expect((await store.media(attachment.media.id))?.cloudId).toBe(cloudId);
        expect(delivery.localUri).toBeUndefined();
        expect(delivery.mutation.payload).not.toContain('file:');
      } else expect(delivery.localUri).toBe('file:///private/photo.png');
      return acknowledgement(delivery);
    });
    await queue.setConditions(ready);
    expect(send.mock.calls.map(([d]) => d.mutation.entity_type)).toEqual(['media', 'observation']);
    expect((await store.mutations()).every((item) => item.sync_state === 'synced')).toBe(true);
  });
  test.each(['validation', 'conflict', 'missing_media'] as FailureKind[])(
    '%s is terminal and preserves the observation',
    async (kind) => {
      await store.enqueue(observation, mutationId, 1000);
      send.mockRejectedValue(new TransportError(kind));
      await queue.setConditions(ready);
      expect((await store.mutations())[0].sync_state).toBe(
        kind === 'conflict' ? 'conflict' : 'failed',
      );
      expect(await store.observations()).toHaveLength(1);
      await jest.advanceTimersByTimeAsync(600000);
      expect(send).toHaveBeenCalledTimes(1);
    },
  );
  test('transient retries retain identity/payload, stop at eight, then allow explicit retry', async () => {
    await store.enqueue(observation, mutationId, 1000);
    send.mockRejectedValue(new Error('Do not persist sensitive provider text'));
    await queue.setConditions(ready);
    expect((await store.mutations())[0].next_attempt_at).toBe(3000);
    for (let attempt = 1; attempt < 8; attempt++)
      await jest.advanceTimersByTimeAsync(retryDelay(attempt, 1));
    expect(send).toHaveBeenCalledTimes(8);
    const failed = (await store.mutations())[0];
    expect(failed).toMatchObject({
      attempt_count: 8,
      budget_count: 8,
      sync_state: 'failed',
      error_code: 'transient',
    });
    expect(new Set(send.mock.calls.map(([d]) => d.mutation.payload)).size).toBe(1);
    expect(new Set(send.mock.calls.map(([d]) => d.mutation.mutation_id))).toEqual(
      new Set([mutationId]),
    );
    await store.retry(mutationId);
    send.mockImplementation(async (delivery) => acknowledgement(delivery));
    await queue.wake();
    expect((await store.mutations())[0]).toMatchObject({
      attempt_count: 9,
      budget_count: 1,
      sync_state: 'synced',
    });
  });
  test('auth failure pauses, refunds the retry budget, and resumes only after credentials change', async () => {
    await store.enqueue(observation, mutationId, 1000);
    send.mockRejectedValueOnce(new TransportError('auth'));
    await queue.setConditions(ready);
    expect((await store.mutations())[0]).toMatchObject({ sync_state: 'pending', budget_count: 0 });
    await queue.wake();
    await queue.setConditions(ready);
    expect(send).toHaveBeenCalledTimes(1);
    await queue.credentialsUpdated();
    expect((await store.mutations())[0].sync_state).toBe('synced');
  });
  test.each(['ownerId', 'farmId', 'mutationId', 'entityId'])(
    'mismatched acknowledgement %s fails closed',
    async (key) => {
      await store.enqueue(observation, mutationId, 1000);
      send.mockImplementation(async (delivery) => ({
        ...acknowledgement(delivery),
        [key]: otherId,
      }));
      await queue.setConditions(ready);
      expect((await store.mutations())[0].sync_state).toBe('failed');
    },
  );
  test('missing media never calls transport or removes the observation', async () => {
    await store.enqueue(observation, mutationId, 1000, attachment);
    photoUri.mockRejectedValue(new Error('missing file'));
    await queue.setConditions(ready);
    expect(send).not.toHaveBeenCalled();
    expect(await store.observations()).toHaveLength(1);
    expect((await store.mutations()).find((m) => m.entity_type === 'media')?.sync_state).toBe(
      'failed',
    );
  });
  test('simultaneous wakeups do not send a mutation twice', async () => {
    await store.enqueue(observation, mutationId, 1000);
    await Promise.all([queue.setConditions(ready), queue.wake(), queue.wake()]);
    expect(send).toHaveBeenCalledTimes(1);
  });
  test('timeout fences late success and keeps a non-cooperative transport from fanning out', async () => {
    await store.enqueue(observation, mutationId, 1000);
    let resolve!: (result: Acknowledgement) => void;
    send.mockImplementationOnce(
      () =>
        new Promise((done) => {
          resolve = done;
        }),
    );
    const running = queue.setConditions(ready);
    await jest.advanceTimersByTimeAsync(1);
    expect(send).toHaveBeenCalledTimes(1);
    await jest.advanceTimersByTimeAsync(30000);
    await running;
    expect(send.mock.calls[0][1].aborted).toBe(true);
    await jest.advanceTimersByTimeAsync(300000);
    await queue.wake();
    expect(send).toHaveBeenCalledTimes(1);
    // Stop before the stale response. A new account must never receive its ACK.
    await queue.stop();
    resolve(acknowledgement(send.mock.calls[0][0]));
    await jest.advanceTimersByTimeAsync(1);
    expect((await store.mutations())[0].sync_state).toBe('pending');
  });
  test('going offline aborts in-flight work and retains the mutation for replay', async () => {
    await store.enqueue(observation, mutationId, 1000);
    send.mockImplementationOnce(
      (_, signal) =>
        new Promise((__, reject) =>
          signal.addEventListener('abort', () => reject(new Error('aborted'))),
        ),
    );
    const running = queue.setConditions(ready);
    await jest.advanceTimersByTimeAsync(1);
    await queue.setConditions({ ...ready, online: false });
    await running;
    expect((await store.mutations())[0]).toMatchObject({ sync_state: 'pending', budget_count: 0 });
    await queue.setConditions(ready);
    expect((await store.mutations())[0].sync_state).toBe('synced');
  });
  test('lost acknowledgement replays the original ID against an idempotent fake server', async () => {
    await store.enqueue(observation, mutationId, 1000);
    const records = new Set<string>();
    send.mockImplementation(async (delivery) => {
      const existed = records.has(delivery.mutation.mutation_id);
      records.add(delivery.mutation.mutation_id);
      if (!existed) throw new TransportError('transient');
      return acknowledgement(delivery);
    });
    await queue.setConditions(ready);
    await jest.advanceTimersByTimeAsync(2000);
    expect(records.size).toBe(1);
    expect((await store.mutations())[0].sync_state).toBe('synced');
  });
});

test('backoff is capped and jitter remains bounded', () => {
  expect(retryDelay(1, 0)).toBe(1000);
  expect(retryDelay(1, 1)).toBe(2000);
  expect(retryDelay(100, 1)).toBe(300000);
  expect(retryDelay(100, -10)).toBe(150000);
});
