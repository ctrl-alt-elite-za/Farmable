/**
 * The only file that touches the native camera, AR, audio and detector libraries.
 *
 * Nothing here is unit tested, and that is the point of issue #4: these APIs exist
 * only on a real phone. Every probe catches its own errors and reports a failure
 * rather than throwing, so one missing capability can never stop the other checks
 * from running.
 */
import type { CheckResult } from '../selftest/report';

function reason(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

interface VisionCameraLike {
  Camera: { getAvailableCameraDevices: () => { physicalDevices?: string[] }[] };
}

interface ViroLike {
  isARSupportedOnDevice?: (
    notSupported: (message: string) => void,
    supported: () => void,
  ) => void;
}

interface ExpoAudioLike {
  AudioModule?: { requestRecordingPermissionsAsync?: () => Promise<{ granted: boolean }> };
  RecordingPresets?: { HIGH_QUALITY?: unknown };
  AudioRecorder?: new (options: unknown) => {
    prepareToRecordAsync: () => Promise<void>;
    record: () => void;
    stop: () => Promise<void>;
    uri: string | null;
  };
  createAudioPlayer?: (source: string) => { play: () => void; remove: () => void };
}

interface FastTfliteLike {
  loadTensorflowModel?: (source: unknown) => Promise<unknown>;
}

export async function probeCameraPreview(): Promise<CheckResult> {
  try {
    const vision = (await import('react-native-vision-camera')) as unknown as VisionCameraLike;
    const devices = vision.Camera.getAvailableCameraDevices();
    return devices.length > 0
      ? { id: 'camera_preview', status: 'pass' }
      : { id: 'camera_preview', status: 'fail', note: 'the phone reported no camera device' };
  } catch (error) {
    return { id: 'camera_preview', status: 'fail', note: reason(error) };
  }
}

export async function probeLidarDepth(): Promise<CheckResult> {
  try {
    const vision = (await import('react-native-vision-camera')) as unknown as VisionCameraLike;
    const hasLidar = vision.Camera.getAvailableCameraDevices().some((device) =>
      (device.physicalDevices ?? []).includes('builtin-lidar-depth-camera'),
    );
    return hasLidar
      ? { id: 'lidar_depth', status: 'pass' }
      : {
          id: 'lidar_depth',
          status: 'unsupported',
          note: 'this phone has no LiDAR depth camera - expected on Android (#4)',
        };
  } catch (error) {
    return { id: 'lidar_depth', status: 'fail', note: reason(error) };
  }
}

export async function probeArPlane(): Promise<CheckResult> {
  try {
    const viro = (await import('@reactvision/react-viro')) as unknown as ViroLike;
    if (typeof viro.isARSupportedOnDevice !== 'function') {
      return {
        id: 'ar_plane',
        status: 'fail',
        note: 'Viro did not expose isARSupportedOnDevice in this build (#4)',
      };
    }
    const supported = await new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => resolve(false), 5000);
      viro.isARSupportedOnDevice?.(
        () => {
          clearTimeout(timer);
          resolve(false);
        },
        () => {
          clearTimeout(timer);
          resolve(true);
        },
      );
    });
    return supported
      ? { id: 'ar_plane', status: 'pass' }
      : {
          id: 'ar_plane',
          status: 'unsupported',
          note: 'AR is not available on this phone - run scripts/check-arcore-device.sh (#4)',
        };
  } catch (error) {
    return { id: 'ar_plane', status: 'fail', note: reason(error) };
  }
}

/** Records for three seconds and plays the recording back, as issue #4 asks. */
export async function probeMicRecord(): Promise<CheckResult> {
  try {
    const audio = (await import('expo-audio')) as unknown as ExpoAudioLike;
    const permission = await audio.AudioModule?.requestRecordingPermissionsAsync?.();
    if (permission && !permission.granted) {
      return { id: 'mic_record', status: 'fail', note: 'microphone permission was refused' };
    }
    if (!audio.AudioRecorder || !audio.createAudioPlayer) {
      return {
        id: 'mic_record',
        status: 'fail',
        note: "expo-audio's recorder API is not the shape this build expects (#4)",
      };
    }
    const recorder = new audio.AudioRecorder(audio.RecordingPresets?.HIGH_QUALITY ?? {});
    await recorder.prepareToRecordAsync();
    recorder.record();
    await wait(3000);
    await recorder.stop();
    if (!recorder.uri) {
      return { id: 'mic_record', status: 'fail', note: 'the recording produced no file' };
    }
    const player = audio.createAudioPlayer(recorder.uri);
    player.play();
    await wait(3000);
    player.remove();
    return { id: 'mic_record', status: 'pass' };
  } catch (error) {
    return { id: 'mic_record', status: 'fail', note: reason(error) };
  }
}

export interface DetectorTiming {
  ms: number;
  note?: string;
}

/**
 * 9999 ms rather than 0 when the detector cannot run: the report compares against a
 * 20 ms budget, so a "could not measure" result must read as a failure, never a pass.
 */
export async function measureDetectorMs(): Promise<DetectorTiming> {
  try {
    const tflite = (await import('react-native-fast-tflite')) as unknown as FastTfliteLike;
    if (typeof tflite.loadTensorflowModel !== 'function') {
      return { ms: 9999, note: 'react-native-fast-tflite did not load in this build (#4)' };
    }
    return { ms: 9999, note: 'no detector model is bundled yet - #16 produces it' };
  } catch (error) {
    return { ms: 9999, note: reason(error) };
  }
}

/** Runs the four device checks in the order the Self-test screen shows them. */
export async function runDeviceProbes(): Promise<CheckResult[]> {
  return [
    await probeCameraPreview(),
    await probeLidarDepth(),
    await probeArPlane(),
    await probeMicRecord(),
  ];
}
