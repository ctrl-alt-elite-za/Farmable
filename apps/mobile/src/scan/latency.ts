import { validIdentity, type FrameIdentity } from './types';

export interface OverlayFrame extends FrameIdentity {
  capturedAt: number;
  inferenceStartedAt: number;
  inferenceEndedAt: number;
  visibleBoxes: number;
}
export interface LatencySummary {
  samples: number;
  p50Milliseconds: number;
  p95Milliseconds: number;
}

/**
 * A native adapter must acknowledge actual presentation on the same clock.
 * React commits/RAF and fixture replay are NOT camera-to-visible-box evidence.
 * This collector is deliberately not wired to a JS rendering callback.
 */
export class ScanLatencyMetrics {
  private pending?: OverlayFrame;
  private samples: number[] = [];
  private lastSequence = 0;
  constructor(private sessionId: number) {
    if (!validIdentity({ sessionId, sequence: 1 }))
      throw new RangeError('Invalid session identity');
  }
  startSession(sessionId: number): void {
    if (!validIdentity({ sessionId, sequence: 1 }) || sessionId <= this.sessionId)
      throw new RangeError('Session identity must increase');
    this.sessionId = sessionId;
    this.lastSequence = 0;
    this.pending = undefined;
    this.samples = [];
  }
  stage(frame: OverlayFrame): boolean {
    if (
      !validIdentity(frame) ||
      frame.sessionId !== this.sessionId ||
      frame.sequence <= this.lastSequence
    )
      return false;
    this.lastSequence = frame.sequence;
    this.pending = undefined;
    const { capturedAt, inferenceStartedAt, inferenceEndedAt, visibleBoxes } = frame;
    if (
      ![capturedAt, inferenceStartedAt, inferenceEndedAt].every(
        (n) => Number.isFinite(n) && n >= 0,
      ) ||
      capturedAt > inferenceStartedAt ||
      inferenceStartedAt > inferenceEndedAt ||
      !Number.isSafeInteger(visibleBoxes) ||
      visibleBoxes < 1
    )
      return false;
    this.pending = { ...frame };
    return true;
  }
  invalidateOverlay(): void {
    this.pending = undefined;
  }
  present(identity: FrameIdentity, presentedAt: number): boolean {
    const frame = this.pending;
    if (!frame || identity.sessionId !== this.sessionId || identity.sequence !== frame.sequence)
      return false;
    this.pending = undefined;
    if (!Number.isFinite(presentedAt) || presentedAt < frame.inferenceEndedAt) return false;
    const latency = presentedAt - frame.capturedAt;
    if (!Number.isFinite(latency)) return false;
    if (this.samples.length === 512) this.samples.shift();
    this.samples.push(latency);
    return true;
  }
  get summary(): LatencySummary | null {
    if (!this.samples.length) return null;
    const sorted = [...this.samples].sort((a, b) => a - b);
    return {
      samples: sorted.length,
      p50Milliseconds: sorted[Math.ceil(sorted.length * 0.5) - 1],
      p95Milliseconds: sorted[Math.ceil(sorted.length * 0.95) - 1],
    };
  }
}
