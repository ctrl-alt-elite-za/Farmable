import type { Box, Detection, Track } from './types';
import { MAX_DETECTIONS, validDetection } from './decoder';

export function intersectionOverUnion(a: Box, b: Box): number {
  const left = Math.max(a.x, b.x),
    top = Math.max(a.y, b.y);
  const right = Math.min(a.x + a.width, b.x + b.width),
    bottom = Math.min(a.y + a.height, b.y + b.height);
  const intersection = Math.max(0, right - left) * Math.max(0, bottom - top);
  const union = a.width * a.height + b.width * b.height - intersection;
  return union <= 0 ? 0 : intersection / union;
}

export function nonMaxSuppression(
  detections: readonly Detection[],
  overlapThreshold = 0.45,
): Detection[] {
  if (!Number.isFinite(overlapThreshold) || overlapThreshold <= 0 || overlapThreshold > 1)
    throw new RangeError('overlapThreshold must be greater than zero and at most one');
  const result: Detection[] = [];
  const remaining = detections
    .slice(0, MAX_DETECTIONS)
    .filter(validDetection)
    .map((d) => ({ ...d, box: { ...d.box } }))
    .sort((a, b) => b.confidence - a.confidence);
  while (remaining.length) {
    const candidate = remaining.shift()!;
    result.push(candidate);
    for (let i = remaining.length - 1; i >= 0; i -= 1) {
      if (
        remaining[i].label === candidate.label &&
        intersectionOverUnion(candidate.box, remaining[i].box) >= overlapThreshold
      )
        remaining.splice(i, 1);
    }
  }
  return result;
}

export interface TrackerOptions {
  matchIou?: number;
  maxMissedFrames?: number;
}

export class CropTracker {
  private tracks: Track[] = [];
  private nextId = 1;
  private readonly matchIou: number;
  private readonly maxMissedFrames: number;
  constructor(options: TrackerOptions = {}) {
    this.matchIou = options.matchIou ?? 0.15;
    this.maxMissedFrames = options.maxMissedFrames ?? 4;
    if (!Number.isFinite(this.matchIou) || this.matchIou <= 0 || this.matchIou >= 1)
      throw new RangeError('matchIou must be greater than zero and less than one');
    if (
      !Number.isSafeInteger(this.maxMissedFrames) ||
      this.maxMissedFrames < 0 ||
      this.maxMissedFrames > 30
    )
      throw new RangeError('maxMissedFrames must be an integer between zero and thirty');
  }
  update(rawDetections: readonly Detection[]): Track[] {
    const detections = nonMaxSuppression(rawDetections),
      used = new Set<number>();
    const updated = this.tracks.map((track) => {
      let bestIndex = -1,
        bestIou = this.matchIou;
      detections.forEach((detection, index) => {
        if (used.has(index) || detection.label !== track.label) return;
        const iou = intersectionOverUnion(track.box, detection.box);
        if (iou > bestIou) {
          bestIou = iou;
          bestIndex = index;
        }
      });
      if (bestIndex < 0) return { ...track, missedFrames: track.missedFrames + 1 };
      used.add(bestIndex);
      return { ...detections[bestIndex], id: track.id, missedFrames: 0 };
    });
    const fresh = detections
      .filter((_, index) => !used.has(index))
      .map((detection) => ({ ...detection, id: this.nextId++, missedFrames: 0 }));
    this.tracks = [
      ...updated.filter((track) => track.missedFrames <= this.maxMissedFrames),
      ...fresh,
    ];
    return this.tracks
      .filter((track) => track.missedFrames === 0)
      .map((track) => ({ ...track, box: { ...track.box } }));
  }
  reset(): void {
    this.tracks = [];
    this.nextId = 1;
  }
}
