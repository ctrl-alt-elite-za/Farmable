import { act, fireEvent, render } from '@testing-library/react-native';
import { AppState, Linking, type AppStateStatus } from 'react-native';
import type { CameraViewProps } from 'react-native-vision-camera';
import { LiveCamera } from '../LiveCamera.native';

let mockCamera: CameraViewProps | undefined;
let mockDevices = [
  { position: 'back', type: 'lidar-depth', mediaTypes: ['video', 'depth'], physicalDevices: [] },
];
const mockPermission = {
  hasPermission: false,
  canRequestPermission: false,
  requestPermission: jest.fn(async () => false),
};
const mockOutput = { dispose: jest.fn() };
let mockFrameCallback: ((frame: { dispose: () => void }) => void) | undefined;
const mockFrameOutput = jest.fn(
  (options: { onFrame: (frame: { dispose: () => void }) => void }) => {
    mockFrameCallback = options.onFrame;
    return mockOutput;
  },
);
jest.mock('react-native-vision-camera', () => ({
  useCameraPermission: () => mockPermission,
  useCameraDevices: () => mockDevices,
  useFrameOutput: (options: { onFrame: (frame: { dispose: () => void }) => void }) =>
    mockFrameOutput(options),
  Camera: (props: CameraViewProps) => {
    mockCamera = props;
    return null;
  },
}));

beforeEach(() => {
  jest.clearAllMocks();
  mockCamera = undefined;
  mockFrameCallback = undefined;
  mockPermission.hasPermission = false;
  mockPermission.canRequestPermission = false;
  mockDevices = [
    { position: 'back', type: 'lidar-depth', mediaTypes: ['video', 'depth'], physicalDevices: [] },
  ];
});
afterEach(() => jest.restoreAllMocks());

test('denied permission explains Settings without creating a camera or frame output', async () => {
  const settings = jest.spyOn(Linking, 'openSettings').mockResolvedValue(undefined);
  const view = await render(<LiveCamera />);
  expect(view.getByText('Open Settings')).toBeTruthy();
  expect(mockCamera).toBeUndefined();
  expect(mockFrameOutput).not.toHaveBeenCalled();
  await fireEvent.press(view.getByTestId('scan-camera-permission'));
  expect(settings).toHaveBeenCalledTimes(1);
});

test('new permission can be requested instead of opening Settings', async () => {
  mockPermission.canRequestPermission = true;
  const view = await render(<LiveCamera />);
  await fireEvent.press(view.getByTestId('scan-camera-permission'));
  expect(mockPermission.requestPermission).toHaveBeenCalledTimes(1);
});

test('unsupported cameras never create a frame output', async () => {
  mockPermission.hasPermission = true;
  mockDevices = [
    { position: 'back', type: 'wide-angle', mediaTypes: ['video'], physicalDevices: [] },
  ];
  const view = await render(<LiveCamera />);
  expect(view.getByText(/LiDAR video\/depth camera is required/)).toBeTruthy();
  expect(mockFrameOutput).not.toHaveBeenCalled();
});

test('chooses LiDAR and releases the native frame output on camera error', async () => {
  mockPermission.hasPermission = true;
  const view = await render(<LiveCamera />);
  expect(mockCamera?.device).toBe(mockDevices[0]);
  await act(async () => {
    mockCamera?.onError?.(new Error('synthetic camera failure'));
  });
  expect(view.getByText(/Camera unavailable/)).toBeTruthy();
  expect(mockOutput.dispose).toHaveBeenCalledTimes(1);
});

test('tab unmount releases the native frame output', async () => {
  mockPermission.hasPermission = true;
  const view = await render(<LiveCamera />);
  await view.unmount();
  expect(mockOutput.dispose).toHaveBeenCalledTimes(1);
});

test('preview releases every incoming frame without inference or network access', async () => {
  mockPermission.hasPermission = true;
  const fetch = jest.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('No network'));
  const view = await render(<LiveCamera />);
  const frame = { dispose: jest.fn() };
  mockFrameCallback?.(frame);
  expect(frame.dispose).toHaveBeenCalledTimes(1);
  expect(fetch).not.toHaveBeenCalled();
  expect(mockFrameOutput).toHaveBeenCalledWith(
    expect.objectContaining({ dropFramesWhileBusy: true, pixelFormat: 'yuv' }),
  );
  await view.unmount();
});

test('background deactivates preview and unsubscribes on unmount', async () => {
  mockPermission.hasPermission = true;
  let changed!: (state: AppStateStatus) => void;
  const remove = jest.fn();
  jest.spyOn(AppState, 'addEventListener').mockImplementation((_, listener) => {
    changed = listener;
    return { remove };
  });
  const view = await render(<LiveCamera />);
  await act(async () => {
    changed('background');
  });
  expect(mockCamera?.isActive).toBe(false);
  await act(async () => {
    changed('active');
  });
  expect(mockCamera?.isActive).toBe(true);
  await view.unmount();
  expect(remove).toHaveBeenCalledTimes(1);
});

test('permission errors are visible and do not create a camera', async () => {
  mockPermission.canRequestPermission = true;
  mockPermission.requestPermission.mockRejectedValueOnce(new Error('native permission failure'));
  const view = await render(<LiveCamera />);
  await fireEvent.press(view.getByTestId('scan-camera-permission'));
  expect(view.getByText(/Could not update camera permission/)).toBeTruthy();
  expect(mockFrameOutput).not.toHaveBeenCalled();
});
