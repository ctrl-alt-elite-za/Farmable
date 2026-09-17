import { assertDetectorAllowed } from '../models';
test('test_demo_mode_rejects_unknown_model', () => {
  expect(() => assertDetectorAllowed('unknown-model', true)).toThrow(/not approved/);
  expect(assertDetectorAllowed('crop-detector-1', true)).toBe('crop-detector-1');
});
