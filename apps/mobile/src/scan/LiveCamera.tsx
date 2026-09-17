import {
  Camera,
  useCameraDevices,
  useCameraPermission,
  useFrameOutput,
  type CameraDevice,
} from 'react-native-vision-camera';
import { useEffect, useState } from 'react';
import { AppState, Linking, Pressable, StyleSheet, Text, View } from 'react-native';

/**
 * The native frame boundary. VisionCamera owns the YUV buffer and drops a frame
 * when this synchronous callback is still busy; no frame is copied to storage or
 * sent over the network. This is preview infrastructure only: the model asset
 * and inference adapter are not bundled yet (#16/#18). It is not live detection.
 */
export function LiveCamera() {
  const { hasPermission, canRequestPermission, requestPermission } = useCameraPermission();
  const [permissionError, setPermissionError] = useState(false);
  if (!hasPermission)
    return (
      <View>
        <Text style={styles.message}>Camera permission is needed to scan crops.</Text>
        {permissionError && (
          <Text style={styles.message}>Could not update camera permission. Try Settings.</Text>
        )}
        <Pressable
          testID="scan-camera-permission"
          onPress={() => {
            const update = canRequestPermission ? requestPermission() : Linking.openSettings();
            void update.catch(() => setPermissionError(true));
          }}
        >
          <Text style={styles.message}>
            {canRequestPermission ? 'Allow camera' : 'Open Settings'}
          </Text>
        </Pressable>
      </View>
    );
  return <CameraPreview />;
}

function CameraPreview() {
  const devices = useCameraDevices();
  const device = devices.find(
    (candidate) =>
      candidate.position === 'back' &&
      candidate.mediaTypes.includes('video') &&
      candidate.mediaTypes.includes('depth') &&
      (candidate.type === 'lidar-depth' ||
        candidate.physicalDevices.some((physical) => physical.type === 'lidar-depth')),
  );
  const [active, setActive] = useState(AppState.currentState === 'active');
  const [cameraError, setCameraError] = useState(false);
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) =>
      setActive(state === 'active'),
    );
    return () => subscription.remove();
  }, []);
  if (!device)
    return <Text style={styles.message}>A back LiDAR video/depth camera is required (#18).</Text>;
  if (cameraError)
    return <Text style={styles.message}>Camera unavailable. Reopen Scan to try again (#18).</Text>;
  return <CameraStream device={device} active={active} onError={() => setCameraError(true)} />;
}

function CameraStream({
  device,
  active,
  onError,
}: {
  device: CameraDevice;
  active: boolean;
  onError: () => void;
}) {
  const frameOutput = useFrameOutput({
    pixelFormat: 'yuv',
    dropFramesWhileBusy: true,
    onFrame(frame) {
      'worklet';
      frame.dispose();
    },
  });
  useEffect(() => () => frameOutput.dispose(), [frameOutput]);

  return (
    <Camera
      style={StyleSheet.absoluteFill}
      device={device}
      outputs={[frameOutput]}
      isActive={active}
      onError={onError}
    />
  );
}

const styles = StyleSheet.create({ message: { color: '#fff', padding: 16 } });
