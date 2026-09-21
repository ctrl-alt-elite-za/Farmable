import { decodeDetections, MAX_DETECTIONS } from '../decoder';
import { CropTracker, nonMaxSuppression } from '../tracker';
import type { Detection } from '../types';

const raw = { label: 'tomato', confidence: 0.9, box: [0.1, 0.2, 0.4, 0.7] };
const detection = (label: Detection['label'] = 'tomato', x = 0.1): Detection => ({
  label,
  rawLabel: label,
  confidence: 0.9,
  box: { x, y: 0.2, width: 0.3, height: 0.5 },
});
test('maps canonical crop identities and preserves raw prompt labels', () => {
  expect(decodeDetections([{ ...raw, label: 'tomato fruit' }])[0]).toMatchObject({
    label: 'tomato',
    rawLabel: 'tomato fruit',
  });
  expect(decodeDetections([{ ...raw, label: 'cabbage head' }])[0].label).toBe('cabbage');
  expect(decodeDetections([{ ...raw, label: 'spinach plant' }])[0].label).toBe('spinach');
});
test.each([
  null,
  {},
  'bad',
  [null],
  [{ ...raw, label: 'healthy' }],
  [{ ...raw, label: 'check_suggested' }],
  [{ ...raw, confidence: NaN }],
  [{ ...raw, confidence: 1.1 }],
  [{ ...raw, confidence: 0.2 }],
  [{ ...raw, box: [0, 0, Infinity, 1] }],
  [{ ...raw, box: [0.5, 0, 0.1, 1] }],
  [{ ...raw, box: [-0.1, 0, 1, 1] }],
  [{ ...raw, box: [0, 0, 2, 1] }],
  [{ ...raw, box: new Array(4) }],
])('rejects malformed, non-crop or low confidence output %#', (input) => {
  expect(decodeDetections(input)).toEqual([]);
});
test('validates threshold and bounds output work', () => {
  expect(() => decodeDetections([], NaN)).toThrow();
  expect(() => decodeDetections([], -1)).toThrow();
  expect(decodeDetections(Array.from({ length: 1000 }, () => raw))).toHaveLength(MAX_DETECTIONS);
});
test('suppresses same-crop duplicates, but never another crop', () => {
  expect(
    nonMaxSuppression([detection(), { ...detection(), confidence: 0.5 }, detection('cabbage')]),
  ).toHaveLength(2);
});
test('stable IDs survive a pan and do not transfer to a different crop', () => {
  const tracker = new CropTracker();
  const a = tracker.update([detection()])[0];
  expect(tracker.update([detection('tomato', 0.14)])[0].id).toBe(a.id);
  expect(tracker.update([detection('cabbage', 0.14)])[0].id).not.toBe(a.id);
});
test('stale tracks retire; reset and caller mutations cannot corrupt internal tracks', () => {
  const tracker = new CropTracker({ maxMissedFrames: 1 });
  const input = detection();
  const a = tracker.update([input])[0];
  input.box.x = 0.9;
  a.box.x = 0.9;
  expect(tracker.update([detection()])[0].id).toBe(1);
  tracker.update([]);
  tracker.update([]);
  expect(tracker.update([detection()])[0].id).toBe(2);
  tracker.reset();
  expect(tracker.update([detection()])[0].id).toBe(1);
});
test('tracker boundary validates direct typed inputs and configuration at runtime', () => {
  expect(new CropTracker().update([{ ...detection(), confidence: NaN }])).toEqual([]);
  expect(() => new CropTracker({ matchIou: NaN })).toThrow();
  expect(() => new CropTracker({ maxMissedFrames: -1 })).toThrow();
  expect(() => nonMaxSuppression([], -1)).toThrow();
});
