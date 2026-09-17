import { act, fireEvent, render } from '@testing-library/react-native';
import { Linking } from 'react-native';
import type { CameraViewProps } from 'react-native-vision-camera';
import { LiveCamera } from '../LiveCamera';

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
const mockFrameOutput = jest.fn(() => mockOutput);
jest.mock('react-native-vision-camera', () => ({
  useCameraPermission: () => mockPermission,
  useCameraDevices: () => mockDevices,
  useFrameOutput: () => mockFrameOutput(),
  Camera: (props: CameraViewProps) => {
    mockCamera = props;
    return null;
  },
}));

beforeEach(() => {
  jest.clearAllMocks();
  mockCamera = undefined;
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
