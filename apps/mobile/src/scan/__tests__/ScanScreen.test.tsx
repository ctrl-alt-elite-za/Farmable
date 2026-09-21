import { act, fireEvent, render } from '@testing-library/react-native';
import { AccessibilityInfo, AppState, Text, type AppStateStatus } from 'react-native';
import { ScanScreen } from '../ScanScreen';
import { currentBuildModeFlags } from '../../testmode/source';

const mockPreview = jest.fn(() => <Text>Native preview mock</Text>);
jest.mock('../previewLoader', () => ({
  loadPreview: async () => ({ default: () => mockPreview() }),
}));
let stateChanged: (state: AppStateStatus) => void;
let motionChanged: (enabled: boolean) => void;
const removeApp = jest.fn(),
  removeMotion = jest.fn();
const initialAppState = AppState.currentState;
beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  mockPreview.mockImplementation(() => <Text>Native preview mock</Text>);
  jest.spyOn(globalThis, 'setInterval');
  jest.spyOn(globalThis, 'clearInterval');
  currentBuildModeFlags.testMode = true;
  currentBuildModeFlags.demoMode = false;
  AppState.currentState = 'active';
  jest.spyOn(AppState, 'addEventListener').mockImplementation((_, listener) => {
    stateChanged = listener;
    return { remove: removeApp };
  });
  // This native-boundary stub implements the only subscription method used by
  // the component; RN's last overload describes an unrelated announcement event.
  jest.spyOn(AccessibilityInfo, 'addEventListener').mockImplementation(((
    _event: string,
    listener: (value: boolean) => void,
  ) => {
    motionChanged = listener;
    return { remove: removeMotion };
  }) as unknown as typeof AccessibilityInfo.addEventListener);
  jest.spyOn(AccessibilityInfo, 'isReduceMotionEnabled').mockResolvedValue(false);
  jest.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('No network in scan tests'));
});
afterEach(() => {
  AppState.currentState = initialAppState;
  jest.restoreAllMocks();
  jest.useRealTimers();
});
async function mount() {
  const view = await render(<ScanScreen />);
  await fireEvent(view.getByTestId('scan-camera'), 'layout', {
    nativeEvent: { layout: { width: 375, height: 200 } },
  });
  return view;
}
function expectNoReplayTimers() {
  // React also schedules internal timers. Assert every replay interval is
  // cleared, rather than confusing renderer timers with scan resource leaks.
  for (const { value } of jest.mocked(setInterval).mock.results)
    expect(clearInterval).toHaveBeenCalledWith(value);
}
test('replays canonical crops without invoking camera, network, or a live latency claim', async () => {
  const view = await mount();
  expect(view.getByText('Recorded test scan')).toBeTruthy();
  expect(view.getByRole('button', { name: 'tomato crop 1, recorded fixture' })).toBeTruthy();
  expect(view.getByTestId('crop-box-2')).toBeTruthy();
  expect(view.getByText(/Camera-to-visible-box latency: unmeasured/)).toBeTruthy();
  expect(view.queryByText(/camera_to_visible_box_ms/)).toBeNull();
  expect(mockPreview).not.toHaveBeenCalled();
  expect(fetch).not.toHaveBeenCalled();
  await act(async () => {
    jest.advanceTimersByTime(100);
  });
  expect(view.getByTestId('crop-box-1')).toBeTruthy();
  expect(view.queryByTestId('crop-box-2')).toBeNull();
  await view.unmount();
  expectNoReplayTimers();
});
test('pausing freezes the current frame; stepping and selecting are usable without motion', async () => {
  const view = await mount();
  await fireEvent.press(view.getByRole('button', { name: 'Next recorded frame' }));
  const position = view.getByTestId('crop-box-1').props.style;
  await act(async () => {
    jest.advanceTimersByTime(1000);
  });
  expect(view.getByTestId('crop-box-1').props.style).toEqual(position);
  await fireEvent.press(view.getByTestId('crop-select-1'));
  expect(view.getByText(/Recorded tomato crop 1/)).toBeTruthy();
  await fireEvent.press(view.getByRole('button', { name: 'Next recorded frame' }));
  expect(view.queryByTestId('crop-box-1')).toBeNull();
  await view.unmount();
});
test('background stops timers and drops boxes; resume starts deterministic fresh replay', async () => {
  const view = await mount();
  await act(async () => {
    stateChanged('background');
  });
  expectNoReplayTimers();
  expect(view.queryByTestId('crop-box-1')).toBeNull();
  await act(async () => {
    jest.advanceTimersByTime(1000);
    stateChanged('active');
  });
  expect(view.getByTestId('crop-box-1')).toBeTruthy();
  await view.unmount();
  expect(removeApp).toHaveBeenCalledTimes(1);
  expect(removeMotion).toHaveBeenCalledTimes(1);
});
test('reduced motion starts with a still frame and requires explicit stepping', async () => {
  jest.mocked(AccessibilityInfo.isReduceMotionEnabled).mockResolvedValue(true);
  const view = await mount();
  expect(view.getByText('Reduced motion: replay paused')).toBeTruthy();
  expect(setInterval).not.toHaveBeenCalled();
  await fireEvent.press(view.getByRole('button', { name: 'Next recorded frame' }));
  expect(view.getByTestId('crop-box-1')).toBeTruthy();
  expect(view.queryByTestId('crop-box-2')).toBeNull();
  await view.unmount();
});
test('new motion event wins over a late initial preference query', async () => {
  let resolve!: (value: boolean) => void;
  jest.mocked(AccessibilityInfo.isReduceMotionEnabled).mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const view = await mount();
  expect(setInterval).not.toHaveBeenCalled();
  await act(async () => {
    motionChanged(true);
    resolve(false);
  });
  expect(view.getByText('Reduced motion: replay paused')).toBeTruthy();
  expect(setInterval).not.toHaveBeenCalled();
  await view.unmount();
});
test.each([false, true])('production/demo mode %s never replays fixtures', async (demoMode) => {
  currentBuildModeFlags.testMode = false;
  currentBuildModeFlags.demoMode = demoMode;
  const view = await mount();
  expect(view.getByText(/Live detection unavailable/)).toBeTruthy();
  expect(view.queryByTestId('crop-box-1')).toBeNull();
  expect(view.queryByText('Recorded test scan')).toBeNull();
  expect(view.getByText('Native preview mock')).toBeTruthy();
  expect(fetch).not.toHaveBeenCalled();
  await act(async () => {
    stateChanged('background');
  });
  expect(view.queryByText('Native preview mock')).toBeNull();
  await view.unmount();
});
test('mixed demo/test flags fail before opening camera or starting replay', async () => {
  currentBuildModeFlags.demoMode = true;
  const consoleError = jest.spyOn(console, 'error').mockImplementation(() => undefined);
  await expect(render(<ScanScreen />)).rejects.toThrow(/cannot both be set/);
  expect(mockPreview).not.toHaveBeenCalled();
  expect(setInterval).not.toHaveBeenCalled();
  consoleError.mockRestore();
});

test('native view failure is contained and a new visit can retry', async () => {
  currentBuildModeFlags.testMode = false;
  const log = jest.spyOn(console, 'error').mockImplementation(() => undefined);
  mockPreview.mockImplementation(() => {
    throw new Error('native view failed');
  });
  const view = await mount();
  expect(view.getByText(/Camera preview unavailable in this build/)).toBeTruthy();
  expect(view.getByText(/Live detection unavailable/)).toBeTruthy();
  await view.unmount();
  mockPreview.mockImplementation(() => <Text>Native preview mock</Text>);
  const next = await mount();
  expect(next.getByText('Native preview mock')).toBeTruthy();
  await next.unmount();
  log.mockRestore();
});

test('an unresolved accessibility query cannot resurrect an unmounted replay', async () => {
  let resolve!: (value: boolean) => void;
  jest.mocked(AccessibilityInfo.isReduceMotionEnabled).mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const view = await mount();
  await view.unmount();
  await act(async () => {
    resolve(false);
  });
  expect(setInterval).not.toHaveBeenCalled();
  expect(fetch).not.toHaveBeenCalled();
});

test('focusing an overlay action pauses moving replay without moving the current box', async () => {
  const view = await mount();
  const before = view.getByTestId('crop-box-1').props.style;
  await fireEvent(view.getByTestId('crop-select-1'), 'focus', {});
  await act(async () => {
    jest.advanceTimersByTime(500);
  });
  expect(view.getByTestId('crop-box-1').props.style).toEqual(before);
  expect(view.getByRole('button', { name: 'Resume replay' })).toBeTruthy();
  await view.unmount();
});
