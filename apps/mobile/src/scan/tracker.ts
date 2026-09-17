import type { Box, Detection, Track } from './types';

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
  const result: Detection[] = [];
  const remaining = [...detections].sort((a, b) => b.confidence - a.confidence);
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
    return this.tracks.filter((track) => track.missedFrames === 0);
  }
  reset(): void {
    this.tracks = [];
    this.nextId = 1;
  }
}
