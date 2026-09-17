import { decodeDetections } from '../decoder';

const valid = { label: 'plant', confidence: 0.9, box: [0.1, 0.2, 0.4, 0.6] };

test('decodes finite normalized detector corners', () => {
  expect(decodeDetections([valid])).toEqual([
    {
      label: 'plant',
      confidence: 0.9,
      box: { x: 0.1, y: 0.2, width: 0.30000000000000004, height: 0.39999999999999997 },
    },
  ]);
});

test.each(
  [
    [NaN, 0.2, 0.4, 0.6],
    [0.1, Infinity, 0.4, 0.6],
    new Array(4),
    [0.1, 0.2, 0.1, 0.6],
    [0.4, 0.2, 0.1, 0.6],
    [-0.1, 0.2, 0.4, 0.6],
    [0.1, 0.2, 1.1, 0.6],
    [0.1, 0.6, 0.4, 0.2],
    [0.1, 0.2, 0.4],
  ].map((box) => ({ box })),
)('rejects malformed normalized box $box', ({ box }) => {
  expect(decodeDetections([{ ...valid, box }])).toEqual([]);
});

test('rejects missing confidence even when the threshold is zero', () => {
  expect(decodeDetections([{ label: 'plant', box: valid.box }], 0)).toEqual([]);
});

test.each([NaN, Infinity, -0.1, 1.1, 0.2])('rejects confidence %p', (confidence) => {
  expect(decodeDetections([{ ...valid, confidence }])).toEqual([]);
});

test.each([NaN, Infinity, -0.1, 1.1])('rejects invalid threshold %p', (threshold) => {
  expect(() => decodeDetections([valid], threshold)).toThrow(RangeError);
});
