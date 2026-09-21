import { validIdentity, type FrameIdentity } from './types';

export interface OwnedFrame extends FrameIdentity {
  /** Milliseconds on the session's monotonic clock, not Date.now(). */
  readonly capturedAt: number;
  /** Ownership is transferred to the processor by submit(). */
  dispose(): void;
}

/** One in-flight operation plus one replaceable pending handle. No native inference here. */
export class LatestFrameProcessor<T extends OwnedFrame, R> {
  private latest?: T;
  private busy = false;
  private disposed = false;
  private active = true;
  private generation = 0;
  private lastSequence = 0;
  private readonly submitted = new WeakSet<T>();

  constructor(
    private readonly sessionId: number,
    private readonly process: (frame: T) => Promise<R>,
    private readonly onResult: (result: R, frame: T) => void,
    private readonly onError: (error: unknown) => void = () => undefined,
  ) {
    if (!validIdentity({ sessionId, sequence: 1 }))
      throw new RangeError('Invalid session identity');
  }

  submit(frame: T): void {
    // A handle may be transferred only once; duplicate submission must not
    // dispose a resource that is still in use or release it twice.
    if (this.submitted.has(frame)) return;
    this.submitted.add(frame);
    if (
      this.disposed ||
      !this.active ||
      !validIdentity(frame) ||
      frame.sessionId !== this.sessionId ||
      frame.sequence <= this.lastSequence ||
      !Number.isFinite(frame.capturedAt) ||
      frame.capturedAt < 0
    ) {
      this.release(frame);
      return;
    }
    this.lastSequence = frame.sequence;
    const replaced = this.latest;
    this.latest = frame;
    if (replaced) this.release(replaced);
    if (!this.busy) void this.drain();
  }

  setActive(active: boolean): void {
    if (this.disposed || active === this.active) return;
    this.active = active;
    this.generation++;
    if (!active) this.clearPending();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.generation++;
    this.clearPending();
  }

  private report(error: unknown): void {
    if (this.disposed || !this.active) return;
    try {
      this.onError(error);
    } catch {
      /* Observer failure cannot strand handles. */
    }
  }
  private release(frame: T, notify = true): void {
    try {
      frame.dispose();
    } catch (error) {
      if (notify) this.report(error);
    }
  }
  private clearPending(): void {
    const pending = this.latest;
    this.latest = undefined;
    if (pending) this.release(pending);
  }
  private async drain(): Promise<void> {
    this.busy = true;
    try {
      while (!this.disposed && this.active && this.latest) {
        const frame = this.latest;
        this.latest = undefined;
        const generation = this.generation;
        try {
          const result = await this.process(frame);
          if (!this.disposed && this.active && generation === this.generation)
            this.onResult(result, frame);
        } catch (error) {
          if (generation === this.generation) this.report(error);
        } finally {
          this.release(frame, generation === this.generation);
        }
      }
    } finally {
      this.busy = false;
    }
  }
}
