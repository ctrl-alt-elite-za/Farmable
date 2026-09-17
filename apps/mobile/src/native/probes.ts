/**
 * Audio/detector checks. Camera/depth/AR observations come from NativeChecks,
 * which mounts actual native views and serializes their camera ownership.
 */
import type { CheckResult } from '../selftest/report';
import { Platform } from 'react-native';

function reason(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function wait(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

type AudioSDK = typeof import('expo-audio');

interface FastTfliteLike {
  loadTensorflowModel?: (source: unknown) => Promise<unknown>;
}

/** Records for three seconds and plays the recording back, as issue #4 asks. */
export async function probeMicRecord(
  loadAudio: () => Promise<AudioSDK> = () => import('expo-audio'),
): Promise<CheckResult> {
  let audio: AudioSDK | undefined;
  let recorder: import('expo-audio').AudioRecorder | undefined;
  let player: import('expo-audio').AudioPlayer | undefined;
  try {
    audio = await loadAudio();
    const permission = await audio.requestRecordingPermissionsAsync();
    if (!permission.granted)
      return { id: 'mic_record', status: 'fail', note: 'microphone permission refused (#4)' };
    await audio.setAudioModeAsync({ allowsRecording: true, playsInSilentMode: true });
    const preset = audio.RecordingPresets.HIGH_QUALITY;
    // The native constructor expects flattened platform options, as Expo's hook does.
    recorder = new audio.AudioModule.AudioRecorder({
      ...preset,
      ...(Platform.OS === 'ios' ? preset.ios : preset.android),
    });
    await recorder.prepareToRecordAsync(preset);
    recorder.record();
    await wait(3000);
    await recorder.stop();
    if (!recorder.uri) {
      return { id: 'mic_record', status: 'fail', note: 'the recording produced no file' };
    }
    await audio.setAudioModeAsync({ allowsRecording: false, playsInSilentMode: true });
    player = audio.createAudioPlayer(recorder.uri);
    const loadDeadline = Date.now() + 5000;
    while (!player.isLoaded && Date.now() < loadDeadline) {
      await wait(250);
    }
    if (!player.isLoaded) {
      return {
        id: 'mic_record',
        status: 'fail',
        note: 'the recording could not be loaded for playback',
      };
    }
    player.play();
    await wait(500);
    if (!player.playing && player.currentTime <= 0) {
      return {
        id: 'mic_record',
        status: 'fail',
        note: 'the recording did not start playing',
      };
    }
    await wait(2500);
    return { id: 'mic_record', status: 'pass' };
  } catch (error) {
    return { id: 'mic_record', status: 'fail', note: reason(error) };
  } finally {
    try {
      player?.remove();
    } catch {
      /* Preserve the check result if native teardown fails. */
    }
    try {
      if (recorder?.isRecording) await recorder.stop();
    } catch {
      /* Best-effort stop before releasing. */
    }
    try {
      recorder?.release();
    } catch {
      /* Missing/disposed native resource. */
    }
    try {
      await audio?.setAudioModeAsync({ allowsRecording: false });
    } catch {
      /* Best-effort audio session reset. */
    }
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

/**
 * NativeChecks must finish and unmount its camera/AR views before audio starts.
 */
export async function runDeviceProbes(observedChecks: CheckResult[]): Promise<CheckResult[]> {
  return [...observedChecks, await probeMicRecord()];
}
