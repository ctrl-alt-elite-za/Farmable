import { Camera, useCameraDevice, useFrameOutput } from 'react-native-vision-camera';
import { StyleSheet } from 'react-native';

/**
 * The native frame boundary. VisionCamera owns the YUV buffer and drops a frame
 * when this synchronous callback is still busy; no frame is copied to storage or
 * sent over the network. The model adapter is intentionally injected at the next
 * boundary so model-specific tensor code cannot leak into the camera view.
 */
export function LiveCamera() {
  const device = useCameraDevice('back');
  const frameOutput = useFrameOutput({
    pixelFormat: 'yuv',
    dropFramesWhileBusy: true,
    onFrame(frame) {
      'worklet';
      frame.dispose();
    },
  });

  if (!device) return null;
  return (
    <Camera style={StyleSheet.absoluteFill} device={device} outputs={[frameOutput]} isActive />
  );
}
