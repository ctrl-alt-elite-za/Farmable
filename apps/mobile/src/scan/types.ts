export type DetectionLabel = 'plant' | 'crop_head_or_fruit' | 'check_suggested' | string;

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface Detection {
  label: DetectionLabel;
  confidence: number;
  box: Box;
}
export interface Track extends Detection {
  id: number;
  missedFrames: number;
}
