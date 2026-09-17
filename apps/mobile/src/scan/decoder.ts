import type { Detection } from './types';

export function decodeDetections(value: unknown, minimumConfidence = 0.35): Detection[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): Detection[] => {
    if (!item || typeof item !== 'object') return [];
    const candidate = item as Record<string, unknown>,
      rawBox = candidate.box;
    if (
      !Array.isArray(rawBox) ||
      rawBox.length !== 4 ||
      rawBox.some((part) => typeof part !== 'number')
    )
      return [];
    const [x1, y1, x2, y2] = rawBox as number[];
    const label = typeof candidate.label === 'string' ? candidate.label : null;
    const confidence = typeof candidate.confidence === 'number' ? candidate.confidence : 0;
    return label && confidence >= minimumConfidence
      ? [
          {
            label,
            confidence,
            box: { x: x1, y: y1, width: Math.max(0, x2 - x1), height: Math.max(0, y2 - y1) },
          },
        ]
      : [];
  });
}
