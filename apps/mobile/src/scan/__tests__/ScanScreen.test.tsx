import { act, render } from '@testing-library/react-native';
import type { Track } from '../types';
import { ScanScreen } from '../ScanScreen';

let mockTracks: Track[] = [];
jest.mock('../../config', () => ({ DEMO_MODE: false, TEST_MODE: true }));
jest.mock('../LiveCamera', () => ({ LiveCamera: () => null }));
jest.mock('../overlay', () => ({
  CropOverlay: ({ tracks }: { tracks: Track[] }) => {
    mockTracks = tracks;
    return null;
  },
}));

beforeEach(() => {
  jest.useFakeTimers();
  mockTracks = [];
});
afterEach(() => jest.useRealTimers());

test('sampling replays every recorded fixture, including the changed warning box', async () => {
  const stopReplay = jest.spyOn(globalThis, 'clearInterval');
  const view = await render(<ScanScreen />);
  await act(async () => {
    jest.advanceTimersByTime(66);
  });
  expect(mockTracks).toHaveLength(10);
  expect(mockTracks.find((track) => track.label === 'check_suggested')?.box.x).toBe(0.02);
  await act(async () => {
    jest.advanceTimersByTime(66);
  });
  expect(mockTracks).toHaveLength(10);
  expect(mockTracks.find((track) => track.label === 'check_suggested')?.box.x).toBe(0.225);
  await view.unmount();
  expect(stopReplay).toHaveBeenCalledTimes(1);
  stopReplay.mockRestore();
});
