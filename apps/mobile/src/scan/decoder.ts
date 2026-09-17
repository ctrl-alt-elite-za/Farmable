import type { Detection } from './types';

export function decodeDetections(value: unknown, minimumConfidence = 0.35): Detection[] {
  if (!Number.isFinite(minimumConfidence) || minimumConfidence < 0 || minimumConfidence > 1)
    throw new RangeError('minimumConfidence must be between zero and one');
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): Detection[] => {
    if (!item || typeof item !== 'object') return [];
    const candidate = item as Record<string, unknown>,
      rawBox = candidate.box;
    if (
      !Array.isArray(rawBox) ||
      rawBox.length !== 4 ||
      !Array.from(rawBox).every((part) => typeof part === 'number' && Number.isFinite(part))
    )
      return [];
    const [x1, y1, x2, y2] = rawBox as number[];
    const label = typeof candidate.label === 'string' ? candidate.label : null;
    const confidence = typeof candidate.confidence === 'number' ? candidate.confidence : NaN;
    // Detector coordinates are normalized corners, not pixel coordinates.
    return label &&
      Number.isFinite(confidence) &&
      confidence >= minimumConfidence &&
      confidence <= 1 &&
      x1 >= 0 &&
      y1 >= 0 &&
      x2 <= 1 &&
      y2 <= 1 &&
      x2 > x1 &&
      y2 > y1
      ? [
          {
            label,
            confidence,
            box: { x: x1, y: y1, width: x2 - x1, height: y2 - y1 },
          },
        ]
      : [];
  });
}
