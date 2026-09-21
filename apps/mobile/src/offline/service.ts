import type { PhotoInput, PhotoStorage } from './photos';
import type { OfflineStore } from './store';
import { normalizeObservation, OfflineError, uuid } from './types';
import type { ObservationInput } from './types';

export interface SaveObservation {
  observation: ObservationInput;
  mutationId: string;
  photo?: { input: PhotoInput; mediaId: string; mutationId: string };
}

/** IDs are allocated before confirmation and retained if the caller retries. */
export class ObservationService {
  private tail: Promise<unknown> = Promise.resolve();
  private closed = false;
  constructor(
    private readonly store: OfflineStore,
    private readonly photos: PhotoStorage,
    private readonly now = Date.now,
    private readonly onSaved: () => void = () => {},
  ) {}
  save(request: SaveObservation) {
    if (this.closed) return Promise.reject(new OfflineError('service_closed'));
    // Snapshot caller-owned data before asynchronous work.
    const input = normalizeObservation(request.observation);
    const mutationId = uuid(request.mutationId);
    const photo = request.photo
      ? {
          input: { ...request.photo.input },
          mediaId: uuid(request.photo.mediaId),
          mutationId: uuid(request.photo.mutationId),
        }
      : undefined;
    const work = this.tail.then(async () => {
      const existing = photo ? await this.store.media(photo.mediaId) : null;
      if (existing && existing.contentType !== photo!.input.contentType)
        throw new OfflineError('mutation_reused');
      const media = photo
        ? (existing ?? (await this.photos.stage(photo.input, photo.mediaId)))
        : undefined;
      try {
        const result = await this.store.enqueue(
          input,
          mutationId,
          this.now(),
          media && photo ? { media, mutationId: photo.mutationId } : undefined,
        );
        this.onSaved();
        return result;
      } catch (error) {
        // Do not remove an attachment which existed before this operation.
        if (media && !existing) {
          try {
            if (!(await this.store.media(media.id))) await this.photos.discardUncommitted(media);
          } catch {
            /* retain on ambiguous commit/cleanup failure */
          }
        }
        throw error;
      }
    });
    this.tail = work.catch(() => undefined);
    return work;
  }
  async stop(): Promise<void> {
    this.closed = true;
    await this.tail;
  }
}
