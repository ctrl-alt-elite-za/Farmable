import { DEMO_MODE } from '../config';
export const detectorModels = {
  'crop-detector-1': { version: '1.0.0', asset: 'crop-detector-1.tflite' },
} as const;
export type DetectorModelId = keyof typeof detectorModels;
export function assertDetectorAllowed(modelId: string, demoMode = DEMO_MODE): DetectorModelId {
  if (demoMode && !(modelId in detectorModels))
    throw new Error(`Detector model ${modelId} is not approved for demo_mode`);
  return modelId as DetectorModelId;
}
