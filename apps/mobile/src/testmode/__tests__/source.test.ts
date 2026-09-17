import { loadSimulatedFrames, resolveCameraSource, SIMULATED_FIXTURE } from '../source';

describe('resolveCameraSource', () => {
  it('uses the real camera in a normal build', () => {
    expect(resolveCameraSource({ testMode: false, demoMode: false })).toEqual({ kind: 'device' });
  });

  it('uses recorded frames in a test-mode build', () => {
    expect(resolveCameraSource({ testMode: true, demoMode: false })).toEqual({
      kind: 'simulated',
      fixture: SIMULATED_FIXTURE,
    });
  });

  it('uses the real camera in a demo build', () => {
    expect(resolveCameraSource({ testMode: false, demoMode: true })).toEqual({ kind: 'device' });
  });

  it('refuses a build that is both test mode and demo mode', () => {
    expect(() => resolveCameraSource({ testMode: true, demoMode: true })).toThrow(
      'cannot both be set',
    );
  });
});

describe('loadSimulatedFrames', () => {
  it('loads the recorded frames the camera screens replay', () => {
    const frames = loadSimulatedFrames();

    expect(frames.length).toBeGreaterThan(0);
    expect(frames[0].detections[0].label).toBe('check_suggested');
  });
});
