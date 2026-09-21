import { DEMO_MODE, TEST_MODE } from '../config';
import sampleDetections from './fixtures/sample-detections.json';

export type CameraSourceKind = 'device' | 'simulated';

export interface CameraSource {
  kind: CameraSourceKind;
  /** Only set for 'simulated': the recorded frames the camera screens replay. */
  fixture?: string;
}

export interface BuildModeFlags {
  testMode: boolean;
  demoMode: boolean;
}

export const SIMULATED_FIXTURE = 'src/testmode/fixtures/sample-detections.json';

export const BOTH_MODES_MESSAGE =
  'EXPO_PUBLIC_TEST_MODE=1 and EXPO_PUBLIC_DEMO_MODE=1 cannot both be set: test mode replays ' +
  'recorded frames, so a demo build would present fake detections as real ones.';

/** The flags this build was compiled with. */
export const currentBuildModeFlags: BuildModeFlags = { testMode: TEST_MODE, demoMode: DEMO_MODE };

/**
 * Refusing the combination here is the second of two guards; scripts/check-test-mode.sh
 * fails the build before it is ever compiled. Both exist because a demo that silently
 * showed recorded detections would be indistinguishable from a working product.
 */
export function resolveCameraSource(flags: BuildModeFlags): CameraSource {
  if (flags.testMode && flags.demoMode) {
    throw new Error(BOTH_MODES_MESSAGE);
  }
  return flags.testMode ? { kind: 'simulated', fixture: SIMULATED_FIXTURE } : { kind: 'device' };
}

export interface SimulatedDetection {
  label: string;
  confidence: number;
  box: number[];
}

export interface SimulatedFrame {
  index: number;
  timestamp_ms: number;
  detections: SimulatedDetection[];
}

export function loadSimulatedFrames(): SimulatedFrame[] {
  return (sampleDetections as { frames: SimulatedFrame[] }).frames;
}
