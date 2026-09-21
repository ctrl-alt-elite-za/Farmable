import { ScanLatencyMetrics, type OverlayFrame } from '../latency';

const frame = (sequence = 1, sessionId = 1): OverlayFrame => ({
  sessionId,
  sequence,
  capturedAt: 10,
  inferenceStartedAt: 12,
  inferenceEndedAt: 20,
  visibleBoxes: 1,
});
test('accepts only the newest matching presentation, once', () => {
  const metrics = new ScanLatencyMetrics(1);
  metrics.stage(frame(1));
  metrics.stage(frame(2));
  expect(metrics.present({ sessionId: 1, sequence: 1 }, 30)).toBe(false);
  expect(metrics.present({ sessionId: 2, sequence: 2 }, 30)).toBe(false);
  expect(metrics.summary).toBeNull();
  expect(metrics.present({ sessionId: 1, sequence: 2 }, 35)).toBe(true);
  expect(metrics.present({ sessionId: 1, sequence: 2 }, 40)).toBe(false);
  metrics.stage(frame(2));
  expect(metrics.present({ sessionId: 1, sequence: 2 }, 40)).toBe(false);
  expect(metrics.summary).toEqual({ samples: 1, p50Milliseconds: 25, p95Milliseconds: 25 });
});
test('unmounted overlays, zero detections and session resets cannot record old samples', () => {
  const metrics = new ScanLatencyMetrics(1);
  metrics.stage(frame());
  metrics.invalidateOverlay();
  expect(metrics.present(frame(), 30)).toBe(false);
  metrics.stage({ ...frame(2), visibleBoxes: 0 });
  expect(metrics.present(frame(2), 30)).toBe(false);
  metrics.stage(frame(3));
  metrics.startSession(2);
  expect(metrics.present(frame(3), 30)).toBe(false);
  expect(metrics.summary).toBeNull();
  expect(() => metrics.startSession(2)).toThrow();
  metrics.stage(frame(1, 2));
  expect(metrics.present(frame(1, 2), 30)).toBe(true);
});
test.each([
  { capturedAt: -1 },
  { capturedAt: NaN },
  { inferenceStartedAt: Infinity },
  { inferenceStartedAt: 5 },
  { inferenceEndedAt: 11 },
  { visibleBoxes: -1 },
  { visibleBoxes: 1.2 },
  { sequence: 1.2 },
])('invalid frame is not measured: %o', (bad) => {
  const metrics = new ScanLatencyMetrics(1);
  expect(metrics.stage({ ...frame(), ...bad })).toBe(false);
  expect(metrics.present(frame(), 30)).toBe(false);
  expect(metrics.summary).toBeNull();
});
test.each([NaN, Infinity, -1, 19])('invalid presentation %s is rejected', (at) => {
  const metrics = new ScanLatencyMetrics(1);
  metrics.stage(frame());
  expect(metrics.present(frame(), at)).toBe(false);
  expect(metrics.summary).toBeNull();
});
test('copies staged metadata rather than trusting caller mutation', () => {
  const metrics = new ScanLatencyMetrics(1);
  const input = frame();
  metrics.stage(input);
  input.capturedAt = 0;
  input.sequence = 99;
  expect(metrics.present(frame(), 30)).toBe(true);
  expect(metrics.summary?.p50Milliseconds).toBe(20);
});
test('bounds samples at 512 and uses nearest-rank percentiles', () => {
  const metrics = new ScanLatencyMetrics(1);
  for (let i = 1; i <= 600; i++) {
    metrics.stage(frame(i));
    metrics.present(frame(i), 20 + i);
  }
  expect(metrics.summary).toEqual({ samples: 512, p50Milliseconds: 354, p95Milliseconds: 585 });
  metrics.startSession(2);
  expect(metrics.summary).toBeNull();
});
