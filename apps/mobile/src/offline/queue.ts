import type { OfflineStore } from './store';
import { OfflineError, TransportError, uuid } from './types';
import type { Media, Mutation, Scope } from './types';

export interface Acknowledgement extends Scope {
  mutationId: string;
  entityId: string;
  cloudMediaId?: string;
}
export interface Delivery {
  /** Immutable logical payload. A future HTTP adapter must retain stable wire IDs too. */
  mutation: Readonly<Mutation>;
  media?: Readonly<Omit<Media, 'relativePath'>>;
  /** Local attachment handle: never serialize this URI into a JSON request. */
  localUri?: string;
}
export interface SyncTransport {
  /** Must honor abort. The queue fences late results even if an adapter is faulty. */
  send(delivery: Delivery, signal: AbortSignal): Promise<Acknowledgement>;
}
export interface QueueOptions {
  transport?: SyncTransport;
  photoUri: (media: Media) => Promise<string>;
  now?: () => number;
  random?: () => number;
  onError?: (code: string) => void;
}
export function retryDelay(attempt: number, random: number): number {
  const cap = Math.min(300000, 2000 * 2 ** Math.min(20, Math.max(0, attempt - 1)));
  const jitter = Number.isFinite(random) ? Math.max(0, Math.min(1, random)) : 0.5;
  return Math.round(cap * (0.5 + jitter / 2));
}

/** One queue per open store. No transport is configured by production by default. */
export class MutationQueue {
  private online = false;
  private foreground = false;
  private authenticated = false;
  private authPaused = false;
  private stopped = false;
  private inFlight = false;
  private generation = 0;
  private controller?: AbortController;
  private timer?: ReturnType<typeof setTimeout>;
  private running?: Promise<void>;
  private readonly now: () => number;
  constructor(
    private readonly store: OfflineStore,
    private readonly options: QueueOptions,
  ) {
    this.now = options.now ?? Date.now;
  }

  setConditions(value: {
    online: boolean;
    foreground: boolean;
    authenticated: boolean;
  }): Promise<void> {
    this.online = value.online;
    this.foreground = value.foreground;
    if (!this.authenticated && value.authenticated) this.authPaused = false;
    this.authenticated = value.authenticated;
    if (!this.ready()) {
      this.generation++;
      this.controller?.abort();
      this.clearTimer();
    }
    return this.wake();
  }
  credentialsUpdated(): Promise<void> {
    this.authPaused = false;
    return this.wake();
  }
  private ready(): boolean {
    return (
      !this.stopped &&
      this.online &&
      this.foreground &&
      this.authenticated &&
      !this.authPaused &&
      !!this.options.transport
    );
  }
  private clearTimer() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
  }
  wake(): Promise<void> {
    if (this.running) return this.running;
    if (!this.ready() || this.inFlight) return Promise.resolve();
    this.clearTimer();
    let storageFailed = false;
    this.running = this.drain()
      .catch(() => {
        storageFailed = true;
        this.options.onError?.('queue_storage_error');
      })
      .finally(async () => {
        try {
          if (storageFailed || !this.ready() || this.inFlight) return;
          const due = await this.store.nextDue();
          if (due !== null && this.ready())
            this.timer = setTimeout(
              () => {
                void this.wake();
              },
              Math.max(10, Math.min(300000, due - this.now())),
            );
        } catch {
          this.options.onError?.('queue_storage_error');
        } finally {
          this.running = undefined;
        }
      });
    return this.running;
  }
  async stop(): Promise<void> {
    this.stopped = true;
    this.generation++;
    this.clearTimer();
    this.controller?.abort();
    await this.running;
  }
  private async drain(): Promise<void> {
    while (this.ready() && !this.inFlight) {
      const epoch = this.generation;
      const mutation = await this.store.claim(this.now());
      if (!mutation) return;
      try {
        if (!this.ready() || epoch !== this.generation) throw new OfflineError('cancelled');
        const delivery: Delivery = { mutation: Object.freeze({ ...mutation }) };
        const localMediaId =
          mutation.entity_type === 'media'
            ? mutation.entity_id
            : (JSON.parse(mutation.payload) as { localMediaId: string | null }).localMediaId;
        if (localMediaId) {
          const media = await this.store.media(localMediaId);
          if (!media) throw new TransportError('missing_media');
          delivery.media = Object.freeze({
            id: media.id,
            ownerId: media.ownerId,
            farmId: media.farmId,
            contentType: media.contentType,
            byteLength: media.byteLength,
            cloudId: media.cloudId,
          });
          if (mutation.entity_type === 'media') {
            try {
              delivery.localUri = await this.options.photoUri(media);
            } catch {
              throw new TransportError('missing_media');
            }
          } else if (!media.cloudId) throw new TransportError('validation');
        }
        if (!this.ready() || epoch !== this.generation) throw new OfflineError('cancelled');
        const result = await this.deliver(delivery);
        if (!this.ready() || epoch !== this.generation) throw new OfflineError('cancelled');
        if (
          !result ||
          result.mutationId !== mutation.mutation_id ||
          result.entityId !== mutation.entity_id ||
          result.ownerId !== mutation.owner_id ||
          result.farmId !== mutation.farm_id
        )
          throw new TransportError('validation');
        if (mutation.entity_type === 'media') {
          try {
            uuid(result.cloudMediaId!);
          } catch {
            throw new TransportError('validation');
          }
        }
        await this.store.acknowledge(mutation, result.cloudMediaId);
      } catch (error) {
        // A local commit failure after remote acceptance must retain the same ID.
        const cancelled =
          !this.ready() ||
          epoch !== this.generation ||
          (error instanceof OfflineError && error.code === 'cancelled');
        if (cancelled) {
          await this.store.release(mutation, 'pending', 'cancelled', this.now(), true);
          return;
        }
        const kind = error instanceof TransportError ? error.kind : 'transient';
        if (kind === 'auth') {
          this.authPaused = true;
          await this.store.release(mutation, 'pending', 'auth_required', this.now(), true);
          return;
        }
        const state =
          kind === 'conflict'
            ? 'conflict'
            : kind !== 'transient' || mutation.budget_count >= 8
              ? 'failed'
              : 'pending';
        const due =
          state === 'pending'
            ? this.now() + retryDelay(mutation.budget_count, (this.options.random ?? Math.random)())
            : this.now();
        await this.store.release(mutation, state, kind, due);
      }
    }
  }
  private async deliver(delivery: Delivery): Promise<Acknowledgement> {
    const controller = new AbortController();
    this.controller = controller;
    this.inFlight = true;
    let timeout = false;
    let abort!: () => void;
    const interrupted = new Promise<never>((_, reject) => {
      abort = () =>
        reject(timeout ? new TransportError('transient') : new OfflineError('cancelled'));
      controller.signal.addEventListener('abort', abort, { once: true });
    });
    const timer = setTimeout(() => {
      timeout = true;
      controller.abort();
    }, 30000);
    const request = Promise.resolve().then(() =>
      this.options.transport!.send(delivery, controller.signal),
    );
    // A non-cooperative adapter cannot fan out requests after timeout. Keep the
    // slot occupied until the actual promise settles; its late result is ignored.
    void request
      .then(
        () => undefined,
        () => undefined,
      )
      .finally(() => {
        this.inFlight = false;
        if (!this.running && this.ready()) void this.wake();
      });
    try {
      return await Promise.race([request, interrupted]);
    } finally {
      clearTimeout(timer);
      controller.signal.removeEventListener('abort', abort);
      this.controller = undefined;
    }
  }
}
