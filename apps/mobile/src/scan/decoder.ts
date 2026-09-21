import type { CropLabel, Detection } from './types';

// Application handoff from docs/decisions/0016-vision-demo-model.md, NOT a raw
// tensor decoder or a claim that these model artifacts have been approved.
const LABELS: Readonly<Record<string, CropLabel>> = Object.freeze({
  cabbage: 'cabbage',
  'cabbage plant': 'cabbage',
  'cabbage head': 'cabbage',
  tomato: 'tomato',
  'tomato plant': 'tomato',
  'tomato fruit': 'tomato',
  spinach: 'spinach',
  'spinach plant': 'spinach',
});
export const MAX_DETECTIONS = 128;

export function decodeDetections(value: unknown, minimumConfidence = 0.35): Detection[] {
  if (!Number.isFinite(minimumConfidence) || minimumConfidence < 0 || minimumConfidence > 1)
    throw new RangeError('minimumConfidence must be between zero and one');
  if (!Array.isArray(value)) return [];
  const result: Detection[] = [];
  // Bound malformed input work as well as valid results; the native adapter
  // must apply its model-specific filtering before this compact handoff.
  for (const item of value.slice(0, MAX_DETECTIONS)) {
    if (!item || typeof item !== 'object') continue;
    const { label: rawLabel, confidence, box } = item;
    if (
      typeof rawLabel !== 'string' ||
      !Object.hasOwn(LABELS, rawLabel) ||
      typeof confidence !== 'number' ||
      !Number.isFinite(confidence) ||
      confidence < minimumConfidence ||
      confidence > 1 ||
      !Array.isArray(box) ||
      box.length !== 4 ||
      !Array.from(box).every((n) => typeof n === 'number' && Number.isFinite(n))
    )
      continue;
    const [x1, y1, x2, y2] = box as number[];
    if (x1 < 0 || y1 < 0 || x2 > 1 || y2 > 1 || x2 <= x1 || y2 <= y1) continue;
    result.push({
      label: LABELS[rawLabel],
      rawLabel,
      confidence,
      box: { x: x1, y: y1, width: x2 - x1, height: y2 - y1 },
    });
  }
  return result;
}

export function validDetection(d: Detection): boolean {
  const b = d.box;
  return (
    ['cabbage', 'tomato', 'spinach'].includes(d.label) &&
    typeof d.rawLabel === 'string' &&
    Object.hasOwn(LABELS, d.rawLabel) &&
    LABELS[d.rawLabel] === d.label &&
    Number.isFinite(d.confidence) &&
    d.confidence >= 0.35 &&
    d.confidence <= 1 &&
    !!b &&
    [b.x, b.y, b.width, b.height].every(Number.isFinite) &&
    b.x >= 0 &&
    b.y >= 0 &&
    b.width > 0 &&
    b.height > 0 &&
    b.x + b.width <= 1 &&
    b.y + b.height <= 1
  );
}
