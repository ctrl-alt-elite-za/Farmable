export type CropLabel = 'cabbage' | 'tomato' | 'spinach';
export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface Detection {
  label: CropLabel;
  rawLabel: string;
  confidence: number;
  box: Box;
}
export interface Track extends Detection {
  id: number;
  missedFrames: number;
}
export interface FrameIdentity {
  sessionId: number;
  sequence: number;
}

export function validIdentity(frame: FrameIdentity): boolean {
  return (
    Number.isSafeInteger(frame.sessionId) &&
    frame.sessionId > 0 &&
    Number.isSafeInteger(frame.sequence) &&
    frame.sequence > 0
  );
}
