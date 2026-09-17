import { DEMO_MODE } from '../config';
import { decodeDetections } from './decoder';
import type { Detection } from './types';
export const detectorModels = {
  'crop-detector-1': { version: '1.0.0', asset: 'crop-detector-1.tflite' },
} as const;
export type DetectorModelId = keyof typeof detectorModels;
export function assertDetectorAllowed(modelId: string, demoMode = DEMO_MODE): DetectorModelId {
  if (!Object.prototype.hasOwnProperty.call(detectorModels, modelId))
    throw new Error(`Detector model ${modelId} is not approved${demoMode ? ' for demo_mode' : ''}`);
  return modelId as DetectorModelId;
}

export interface CropDetector {
  readonly modelId: DetectorModelId;
  detect(rawOutput: unknown): Detection[];
}

export function createCropDetector(modelId: string, demoMode = DEMO_MODE): CropDetector {
  const approvedModel = assertDetectorAllowed(modelId, demoMode);
  return { modelId: approvedModel, detect: (rawOutput) => decodeDetections(rawOutput) };
}
