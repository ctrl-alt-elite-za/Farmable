import { CropTracker, intersectionOverUnion, nonMaxSuppression } from '../tracker';
import type { Detection } from '../types';
import { decodeDetections } from '../decoder';
import { loadSimulatedFrames } from '../../testmode/source';
const detection = (x: number, y: number, label = 'plant'): Detection => ({
  label,
  confidence: 0.9,
  box: { x, y, width: 0.08, height: 0.08 },
});

test('recorded ten_plants_slow_pan preserves identities when warning classes change', () => {
  const tracker = new CropTracker();
  const identities = new Set<number>();
  const frames = loadSimulatedFrames();
  for (let frame = 0; frame < 8; frame += 1) {
    const tracks = tracker.update(decodeDetections(frames[frame % frames.length].detections));
    expect(tracks).toHaveLength(10);
    tracks.forEach((track) => identities.add(track.id));
  }
  expect(identities.size).toBe(10);
});
test('NMS removes duplicate boxes but keeps different labels', () => {
  expect(
    nonMaxSuppression([detection(0, 0), { ...detection(0.01, 0.01), confidence: 0.8 }]),
  ).toHaveLength(1);
  expect(intersectionOverUnion(detection(0, 0).box, detection(0, 0, 'fruit').box)).toBe(1);
});
test('ten_plants_slow_pan keeps ten stable tracks', () => {
  const tracker = new CropTracker(),
    frames = Array.from({ length: 8 }, (_, frame) =>
      Array.from({ length: 10 }, (_, plant) =>
        detection(plant * 0.09 + frame * 0.003, plant * 0.02),
      ),
    );
  const ids = new Set(tracker.update(frames[0]).map((track) => track.id));
  frames.slice(1).forEach((frame) => {
    const tracks = tracker.update(frame);
    expect(tracks).toHaveLength(10);
    tracks.forEach((track) => ids.add(track.id));
  });
  expect(ids.size).toBe(10);
});
