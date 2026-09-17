import { Component, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import type { CameraDevice } from 'react-native-vision-camera';

import type { CheckResult } from '../selftest/report';

type Vision = typeof import('react-native-vision-camera');
type Viro = typeof import('@reactvision/react-viro');
const nativeLoaders = {
  vision: () => import('react-native-vision-camera'),
  viro: () => import('@reactvision/react-viro'),
};
type CameraResult = { checks: CheckResult[]; released: boolean };
type Request =
  | {
      kind: 'camera';
      vision: Vision;
      device: CameraDevice;
      lidar: boolean;
      finish: (result: CameraResult) => void;
    }
  | { kind: 'ar'; viro: Viro; finish: (result: CheckResult) => void };

function fail(id: CheckResult['id'], note: string): CheckResult {
  return { id, status: 'fail', note: `${note} (#4)` };
}

async function within<T>(operation: Promise<T>, disposeLate?: (value: T) => void): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let expired = false;
  void operation.then(
    (value) => {
      if (expired) {
        try {
          disposeLate?.(value);
        } catch {
          /* Do not create an unhandled rejection during teardown. */
        }
      }
    },
    () => undefined,
  );
  try {
    return await Promise.race([
      operation,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          expired = true;
          reject(new Error('native setup timed out'));
        }, 15000);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

class NativeBoundary extends Component<
  { children: ReactNode; onFailure: () => void },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  componentDidCatch() {
    this.props.onFailure();
  }
  render() {
    return this.state.failed ? <Text>Native check failed (#4)</Text> : this.props.children;
  }
}

/** Mount camera, wait for its native stop, commit its unmount, THEN mount AR. */
export function NativeChecks({
  onComplete,
  loaders = nativeLoaders,
}: {
  onComplete: (checks: CheckResult[]) => void;
  loaders?: { vision: () => Promise<Vision>; viro: () => Promise<Viro> };
}) {
  const [request, setRequest] = useState<Request | null>(null);
  const cleared = useRef<(() => void) | null>(null);
  useEffect(() => {
    if (!request) {
      cleared.current?.();
      cleared.current = null;
    }
  }, [request]);

  useEffect(() => {
    let cancelled = false;
    let abandon: (() => void) | undefined;
    async function clear() {
      await new Promise<void>((resolve) => {
        cleared.current = resolve;
        setRequest(null);
      });
    }
    async function run() {
      const checks: CheckResult[] = [];
      let released = true;
      try {
        const vision = await within(loaders.vision());
        if (!(await within(vision.VisionCamera.requestCameraPermission())))
          throw new Error('camera permission refused');
        const factory = await within(vision.VisionCamera.createDeviceFactory(), (late) =>
          late.dispose(),
        );
        let device: CameraDevice | undefined;
        let lidar = false;
        try {
          const devices = factory.cameraDevices;
          const depthDevice = devices.find(
            (item) =>
              item.position === 'back' &&
              item.mediaTypes.includes('video') &&
              item.mediaTypes.includes('depth') &&
              (item.type === 'lidar-depth' ||
                item.physicalDevices.some((part) => part.type === 'lidar-depth')),
          );
          device =
            depthDevice ??
            devices.find((item) => item.position === 'back' && item.mediaTypes.includes('video'));
          lidar = !!depthDevice;
        } finally {
          factory.dispose();
        }
        if (!device) throw new Error('no back camera device');
        if (cancelled) return;
        const selected = device;
        const result = await new Promise<CameraResult>((finish) => {
          abandon = () => finish({ checks: [], released: false });
          setRequest({ kind: 'camera', vision, device: selected, lidar, finish });
        });
        if (cancelled) return;
        checks.push(...result.checks);
        released = result.released;
        await clear();
      } catch (error) {
        const note = error instanceof Error ? error.message : 'camera setup failed';
        checks.push(fail('camera_preview', note), fail('lidar_depth', note));
      }
      if (cancelled) return;
      if (!released) {
        checks.push(fail('ar_plane', 'camera stop was not observed; AR was not started'));
      } else {
        try {
          const viro = await within(loaders.viro());
          const support = await within(viro.isARSupportedOnDevice());
          if (!support.isARSupported) {
            checks.push({
              id: 'ar_plane',
              status: 'unsupported',
              note: 'AR unavailable on this phone (#4)',
            });
          } else {
            const permission = await within(viro.requestRequiredPermissions(['camera']));
            if (!permission.camera) throw new Error('AR camera permission refused');
            if (cancelled) return;
            checks.push(
              await new Promise<CheckResult>((finish) => {
                abandon = () => finish(fail('ar_plane', 'cancelled'));
                setRequest({ kind: 'ar', viro, finish });
              }),
            );
            if (cancelled) return;
            await clear();
          }
        } catch {
          checks.push(fail('ar_plane', 'AR setup failed or timed out'));
        }
      }
      if (!cancelled) onComplete(checks);
    }
    void run();
    return () => {
      cancelled = true;
      abandon?.();
      cleared.current?.();
    };
  }, [onComplete, loaders]);

  return (
    <View style={styles.container}>
      <Text>
        {request?.kind === 'ar'
          ? 'Move the phone slowly over a textured flat surface.'
          : 'Checking camera preview and depth...'}
      </Text>
      {request?.kind === 'camera' ? (
        <NativeBoundary
          key="camera"
          onFailure={() =>
            request.finish({
              checks: [
                fail('camera_preview', 'native camera crashed'),
                fail('lidar_depth', 'native camera crashed'),
              ],
              released: false,
            })
          }
        >
          <CameraCheck {...request} />
        </NativeBoundary>
      ) : null}
      {request?.kind === 'ar' ? (
        <NativeBoundary
          key="ar"
          onFailure={() => request.finish(fail('ar_plane', 'native AR crashed'))}
        >
          <ArCheck {...request} />
        </NativeBoundary>
      ) : null}
    </View>
  );
}

function CameraCheck({ vision, device, lidar, finish }: Extract<Request, { kind: 'camera' }>) {
  const [active, setActive] = useState(true);
  const output = vision.usePhotoOutput();
  const outputs = useMemo(() => (lidar ? [output] : []), [lidar, output]);
  const preview = useRef<CheckResult>(fail('camera_preview', 'no preview frame observed'));
  const depth = useRef<CheckResult>(
    lidar
      ? fail('lidar_depth', 'no depth capture observed')
      : { id: 'lidar_depth', status: 'unsupported', note: 'no back LiDAR video/depth device (#4)' },
  );
  const stopping = useRef(false);
  const complete = useRef(false);
  const capturing = useRef(false);
  const mounted = useRef(true);
  const releaseTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const deadline = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  function done(released: boolean) {
    if (complete.current || !mounted.current) return;
    complete.current = true;
    clearTimeout(deadline.current);
    clearTimeout(releaseTimer.current);
    finish({ checks: [preview.current, depth.current], released });
  }
  function stop() {
    if (stopping.current || !mounted.current) return;
    stopping.current = true;
    clearTimeout(deadline.current);
    setActive(false);
    releaseTimer.current = setTimeout(() => done(false), 5000);
  }
  useEffect(() => {
    deadline.current = setTimeout(stop, 15000);
    return () => {
      mounted.current = false;
      clearTimeout(deadline.current);
      clearTimeout(releaseTimer.current);
      output.dispose();
    };
    // One deadline per mounted native session, not per callback/render.
  }, [output]);
  async function observedPreview() {
    if (capturing.current || stopping.current || !mounted.current) return;
    capturing.current = true;
    preview.current = { id: 'camera_preview', status: 'pass' };
    try {
      if (lidar) {
        if (!output.supportsDepthDataDelivery) throw new Error('depth delivery unavailable');
        const photo = await output.capturePhoto({ enableDepthData: true }, {});
        try {
          const data = photo.depth;
          try {
            if (
              !data?.isValid ||
              data.width <= 0 ||
              data.height <= 0 ||
              !data.getDepthData().byteLength
            )
              throw new Error('empty depth capture');
            if (!stopping.current && mounted.current)
              depth.current = { id: 'lidar_depth', status: 'pass' };
          } finally {
            data?.dispose();
          }
        } finally {
          photo.dispose();
        }
      }
    } catch {
      depth.current = fail('lidar_depth', 'depth capture failed');
    } finally {
      stop();
    }
  }
  const Camera = vision.Camera;
  return (
    <Camera
      style={styles.preview}
      device={device}
      outputs={outputs}
      isActive={active}
      onPreviewStarted={() => void observedPreview()}
      onStopped={() => {
        if (stopping.current) done(true);
      }}
      onError={() => {
        preview.current = fail('camera_preview', 'camera session error');
        if (lidar) depth.current = fail('lidar_depth', 'camera session error');
        stop();
      }}
    />
  );
}

function ArCheck({ viro, finish }: Extract<Request, { kind: 'ar' }>) {
  const complete = useRef(false);
  function done(result: CheckResult) {
    if (complete.current) return;
    complete.current = true;
    finish(result);
  }
  useEffect(() => {
    const timer = setTimeout(
      () => done(fail('ar_plane', 'no plane anchor observed within 20 seconds')),
      20000,
    );
    return () => {
      complete.current = true;
      clearTimeout(timer);
    };
  }, []);
  const Scene = useMemo(
    () =>
      function PlaneScene() {
        const ARScene = viro.ViroARScene;
        return (
          <ARScene
            anchorDetectionTypes={['PlanesHorizontal', 'PlanesVertical']}
            onAnchorFound={(anchor) => {
              if (anchor.type === 'plane') done({ id: 'ar_plane', status: 'pass' });
            }}
            onError={() => done(fail('ar_plane', 'AR session error'))}
          />
        );
      },
    [viro],
  );
  const Navigator = viro.ViroARSceneNavigator;
  return <Navigator style={styles.preview} initialScene={{ scene: Scene }} autofocus />;
}

const styles = StyleSheet.create({
  container: { gap: 8 },
  preview: { height: 240, width: '100%' },
});
