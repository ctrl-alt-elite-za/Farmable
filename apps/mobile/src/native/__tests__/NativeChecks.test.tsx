import { act, render, waitFor } from '@testing-library/react-native';
import type { ComponentProps } from 'react';
import type { CameraViewProps } from 'react-native-vision-camera';

import { NativeChecks } from '../NativeChecks';

type ArProps = ComponentProps<typeof import('@reactvision/react-viro').ViroARScene>;
let mockCamera: CameraViewProps | undefined;
let mockAr: ArProps | undefined;
let mockDevices = [
  { position: 'back', type: 'lidar-depth', mediaTypes: ['video', 'depth'], physicalDevices: [] },
];
const mockOrder: string[] = [];
const mockDepth = {
  isValid: true,
  width: 2,
  height: 2,
  getDepthData: jest.fn(() => new ArrayBuffer(8)),
  dispose: jest.fn(),
};
const mockPhoto = { depth: mockDepth as typeof mockDepth | undefined, dispose: jest.fn() };
const mockOutput = {
  supportsDepthDataDelivery: true,
  capturePhoto: jest.fn(async () => mockPhoto),
  dispose: jest.fn(),
};
const mockFactory = {
  get cameraDevices() {
    return mockDevices;
  },
  dispose: jest.fn(),
};
const mockPermission = jest.fn(async () => true);
const mockCreateFactory = jest.fn(async () => mockFactory);
const mockSupport = jest.fn(async () => ({ isARSupported: true }));
const mockArPermission = jest.fn(async () => ({ camera: true }));
// Expo preserves dynamic import(), which Jest's non-ESM VM cannot execute.
// Inject SDK loaders, just as API tests inject fetch; callbacks remain real React.
const mockLoaders = {
  vision: async () =>
    jest.requireMock<typeof import('react-native-vision-camera')>('react-native-vision-camera'),
  viro: async () =>
    jest.requireMock<typeof import('@reactvision/react-viro')>('@reactvision/react-viro'),
};

jest.mock('react-native-vision-camera', () => {
  const React = jest.requireActual<typeof import('react')>('react');
  return {
    VisionCamera: {
      requestCameraPermission: mockPermission,
      createDeviceFactory: mockCreateFactory,
    },
    usePhotoOutput: () => mockOutput,
    Camera: (props: CameraViewProps) => {
      mockCamera = props;
      React.useEffect(() => {
        mockOrder.push('camera-mount');
        return () => {
          mockOrder.push('camera-unmount');
        };
      }, []);
      return null;
    },
  };
});
jest.mock('@reactvision/react-viro', () => {
  const React = jest.requireActual<typeof import('react')>('react');
  return {
    isARSupportedOnDevice: mockSupport,
    requestRequiredPermissions: mockArPermission,
    ViroARScene: (props: ArProps) => {
      mockAr = props;
      return null;
    },
    ViroARSceneNavigator: (props: { initialScene: { scene: () => React.JSX.Element } }) => {
      mockOrder.push('ar-mount');
      return React.createElement(props.initialScene.scene);
    },
  };
});

beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  mockCamera = undefined;
  mockAr = undefined;
  mockOrder.length = 0;
  mockDevices = [
    { position: 'back', type: 'lidar-depth', mediaTypes: ['video', 'depth'], physicalDevices: [] },
  ];
  mockDepth.isValid = true;
  mockPhoto.depth = mockDepth;
  mockOutput.supportsDepthDataDelivery = true;
  mockOutput.capturePhoto.mockResolvedValue(mockPhoto);
  mockPermission.mockResolvedValue(true);
  mockCreateFactory.mockResolvedValue(mockFactory);
  mockSupport.mockResolvedValue({ isARSupported: true });
  mockArPermission.mockResolvedValue({ camera: true });
});
afterEach(() => jest.useRealTimers());

async function start() {
  const complete = jest.fn();
  const view = await render(<NativeChecks onComplete={complete} loaders={mockLoaders} />);
  await waitFor(() =>
    expect({ camera: mockCamera, completed: complete.mock.calls }).toEqual(
      expect.objectContaining({ camera: expect.anything() }),
    ),
  );
  return { complete, view };
}
async function stopCamera() {
  await act(async () => {
    mockCamera?.onStopped?.();
  });
  await waitFor(() => expect(mockAr).toBeDefined());
}
async function plane() {
  await act(async () => {
    mockAr?.onAnchorFound?.({
      anchorId: 'plane',
      type: 'plane',
      position: [0, 0, 0],
      rotation: [0, 0, 0],
      scale: [1, 1, 1],
    });
  });
}

it('passes only observed preview, one nonempty depth capture, and a plane after camera unmount', async () => {
  const { complete } = await start();
  expect(complete).not.toHaveBeenCalled();
  expect(mockAr).toBeUndefined();
  await act(async () => {
    mockCamera?.onPreviewStarted?.();
    mockCamera?.onPreviewStarted?.();
  });
  expect(mockOutput.capturePhoto).toHaveBeenCalledTimes(1);
  expect(mockOutput.capturePhoto).toHaveBeenCalledWith({ enableDepthData: true }, {});
  expect(mockPhoto.dispose).toHaveBeenCalledTimes(1);
  expect(mockDepth.dispose).toHaveBeenCalledTimes(1);
  expect(mockCamera?.isActive).toBe(false);
  expect(mockAr).toBeUndefined();
  await stopCamera();
  expect(mockOrder.indexOf('camera-unmount')).toBeLessThan(mockOrder.indexOf('ar-mount'));
  await act(async () => {
    mockAr?.onAnchorFound?.({
      anchorId: 'other',
      type: 'anchor',
      position: [0, 0, 0],
      rotation: [0, 0, 0],
      scale: [1, 1, 1],
    });
  });
  expect(complete).not.toHaveBeenCalled();
  await plane();
  expect(complete).toHaveBeenCalledWith([
    { id: 'camera_preview', status: 'pass' },
    { id: 'lidar_depth', status: 'pass' },
    { id: 'ar_plane', status: 'pass' },
  ]);
});

it('support alone never passes camera, depth, or AR; missing observations time out', async () => {
  const { complete } = await start();
  await act(async () => {
    jest.advanceTimersByTime(15000);
  });
  expect(mockCamera?.isActive).toBe(false);
  expect(mockOutput.capturePhoto).not.toHaveBeenCalled();
  await stopCamera();
  expect(complete).not.toHaveBeenCalled();
  await act(async () => {
    jest.advanceTimersByTime(20000);
  });
  expect(complete.mock.calls[0][0].map((item: { status: string }) => item.status)).toEqual([
    'fail',
    'fail',
    'fail',
  ]);
});

it('never opens AR if native camera stop is not observed', async () => {
  const { complete } = await start();
  await act(async () => {
    mockCamera?.onPreviewStarted?.();
  });
  await act(async () => {
    jest.advanceTimersByTime(5000);
  });
  expect(mockAr).toBeUndefined();
  expect(mockSupport).not.toHaveBeenCalled();
  expect(complete.mock.calls[0][0][2].status).toBe('fail');
});

it.each(['empty', 'invalid', 'rejected', 'unsupported-output'])(
  'fails depth delivery: %s',
  async (failure) => {
    if (failure === 'empty') mockPhoto.depth = undefined;
    if (failure === 'invalid') mockDepth.isValid = false;
    if (failure === 'rejected')
      mockOutput.capturePhoto.mockRejectedValue(new Error('synthetic capture failure'));
    if (failure === 'unsupported-output') mockOutput.supportsDepthDataDelivery = false;
    const { complete } = await start();
    await act(async () => {
      mockCamera?.onPreviewStarted?.();
    });
    await stopCamera();
    await plane();
    expect(complete.mock.calls[0][0][0].status).toBe('pass');
    expect(complete.mock.calls[0][0][1].status).toBe('fail');
  },
);

it('reports unsupported hardware honestly, without capability passes', async () => {
  mockDevices = [
    { position: 'back', type: 'wide-angle', mediaTypes: ['video'], physicalDevices: [] },
  ];
  mockSupport.mockResolvedValue({ isARSupported: false });
  const { complete } = await start();
  await act(async () => {
    mockCamera?.onPreviewStarted?.();
  });
  await act(async () => {
    mockCamera?.onStopped?.();
  });
  await waitFor(() => expect(complete).toHaveBeenCalled());
  expect(complete.mock.calls[0][0].map((item: { status: string }) => item.status)).toEqual([
    'pass',
    'unsupported',
    'unsupported',
  ]);
  expect(mockOutput.capturePhoto).not.toHaveBeenCalled();
});

it('permission refusal fails without mounting a camera or AR session', async () => {
  mockPermission.mockResolvedValue(false);
  mockArPermission.mockResolvedValue({ camera: false });
  const complete = jest.fn();
  await render(<NativeChecks onComplete={complete} loaders={mockLoaders} />);
  await waitFor(() => expect(complete).toHaveBeenCalled());
  expect(mockCamera).toBeUndefined();
  expect(mockAr).toBeUndefined();
  expect(
    complete.mock.calls[0][0].every((item: { status: string }) => item.status === 'fail'),
  ).toBe(true);
});

it('native session errors fail explicitly', async () => {
  const { complete } = await start();
  await act(async () => {
    mockCamera?.onError?.(new Error('synthetic camera error'));
  });
  await stopCamera();
  await act(async () => {
    mockAr?.onError?.({
      nativeEvent: { error: new Error('synthetic AR error') },
    } as Parameters<NonNullable<ArProps['onError']>>[0]);
  });
  expect(complete.mock.calls[0][0].map((item: { status: string }) => item.status)).toEqual([
    'fail',
    'fail',
    'fail',
  ]);
});

it('unmount cancels observers and cleans native resources without completing', async () => {
  const { complete, view } = await start();
  await view.unmount();
  await act(async () => {
    jest.advanceTimersByTime(60000);
  });
  expect(mockFactory.dispose).toHaveBeenCalledTimes(1);
  expect(mockOutput.dispose).toHaveBeenCalledTimes(1);
  expect(complete).not.toHaveBeenCalled();
  expect(mockAr).toBeUndefined();
});
