import { buildSelfTestReport, type CheckResult, type SelfTestMeta } from '../report';

const meta: SelfTestMeta = {
  platform: 'ios',
  appVersion: '0.1.0',
  buildSha: 'abc1234',
  deviceModel: 'iPhone 12 Pro',
  detectorMs: 12,
  startedAt: '2026-09-17T08:00:00.000Z',
};

const allPassing: CheckResult[] = [
  { id: 'camera_preview', status: 'pass' },
  { id: 'lidar_depth', status: 'pass' },
  { id: 'ar_plane', status: 'pass' },
  { id: 'mic_record', status: 'pass' },
];

describe('buildSelfTestReport', () => {
  it('passes overall when all four checks pass inside the detector budget', () => {
    const report = buildSelfTestReport(allPassing, meta);

    expect(report.camera_preview).toBe('pass');
    expect(report.lidar_depth).toBe('pass');
    expect(report.ar_plane).toBe('pass');
    expect(report.mic_record).toBe('pass');
    expect(report.notes).toEqual([]);
    expect(report.overall).toBe('pass');
  });

  it('copies the server field names and the build it ran on', () => {
    const report = buildSelfTestReport(allPassing, meta);

    expect(report.build_sha).toBe('abc1234');
    expect(report.app_version).toBe('0.1.0');
    expect(report.device_model).toBe('iPhone 12 Pro');
    expect(report.detector_ms).toBe(12);
    expect(report.started_at).toBe('2026-09-17T08:00:00.000Z');
    expect(report.platform).toBe('ios');
  });

  it('keeps a failed check note, issue number and all', () => {
    const results: CheckResult[] = [
      ...allPassing.filter((result) => result.id !== 'lidar_depth'),
      { id: 'lidar_depth', status: 'fail', note: 'no depth camera reported (#31)' },
    ];

    const report = buildSelfTestReport(results, meta);

    expect(report.lidar_depth).toBe('fail');
    expect(report.notes).toContain('lidar_depth: no depth camera reported (#31)');
    expect(report.overall).toBe('fail');
  });

  it('says so when a failed check came with no note at all', () => {
    const results: CheckResult[] = [
      ...allPassing.filter((result) => result.id !== 'ar_plane'),
      { id: 'ar_plane', status: 'unsupported' },
    ];

    const report = buildSelfTestReport(results, meta);

    expect(report.notes).toContain(
      'ar_plane: no note recorded - add one naming the GitHub issue, e.g. #123',
    );
    expect(report.overall).toBe('fail');
  });

  it('treats a check that never ran as a failure', () => {
    const results = allPassing.filter((result) => result.id !== 'mic_record');

    const report = buildSelfTestReport(results, meta);

    expect(report.mic_record).toBe('fail');
    expect(report.notes).toContain('mic_record: not run');
    expect(report.overall).toBe('fail');
  });

  it('fails the report when the detector is slower than the 20 ms budget', () => {
    const report = buildSelfTestReport(allPassing, { ...meta, detectorMs: 21 });

    expect(report.notes).toContain('detector_ms: 21 ms is over the 20 ms budget');
    expect(report.overall).toBe('fail');
  });

  it('reports the detector note instead of the budget message when it could not be measured', () => {
    const report = buildSelfTestReport(allPassing, {
      ...meta,
      detectorMs: 9999,
      detectorNote: 'no detector model is bundled yet - #16 produces it',
    });

    expect(report.notes).toContain(
      'detector_ms: no detector model is bundled yet - #16 produces it',
    );
    expect(report.overall).toBe('fail');
  });
});
