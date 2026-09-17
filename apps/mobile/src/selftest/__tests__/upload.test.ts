import { buildSelfTestReport, type SelfTestMeta } from '../report';
import { uploadSelfTestReport } from '../upload';

const meta: SelfTestMeta = {
  platform: 'android',
  appVersion: '0.1.0',
  buildSha: 'abc1234',
  deviceModel: 'Pixel 7',
  detectorMs: 11,
  startedAt: '2026-09-17T08:00:00.000Z',
};

const report = buildSelfTestReport(
  [
    { id: 'camera_preview', status: 'pass' },
    { id: 'lidar_depth', status: 'unsupported', note: 'Android has no LiDAR (#4)' },
    { id: 'ar_plane', status: 'pass' },
    { id: 'mic_record', status: 'pass' },
  ],
  meta,
);

describe('uploadSelfTestReport', () => {
  it('posts the report to /devices/self-test as JSON', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({ ok: true, status: 201 });

    const result = await uploadSelfTestReport(report, { apiUrl: 'http://api.test', fetchImpl });

    expect(result).toEqual({ uploaded: true, status: 201 });
    const [url, init] = fetchImpl.mock.calls[0];
    expect(url).toBe('http://api.test/devices/self-test');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body)).toEqual(report);
  });

  it('sends no credential of any kind - the report is the whole request', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({ ok: true, status: 201 });

    await uploadSelfTestReport(report, { apiUrl: 'http://api.test', fetchImpl });

    const [, init] = fetchImpl.mock.calls[0];
    expect(Object.keys(init.headers)).toEqual(['content-type']);
    expect(init.headers['content-type']).toBe('application/json');
  });

  it('reports a failed upload instead of throwing when the server is unreachable', async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error('Network request failed'));

    await expect(
      uploadSelfTestReport(report, { apiUrl: 'http://api.test', fetchImpl }),
    ).resolves.toEqual({ uploaded: false, status: 0 });
  });

  it('reports a failed upload when the server answers with an error status', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({ ok: false, status: 503 });

    await expect(
      uploadSelfTestReport(report, { apiUrl: 'http://api.test', fetchImpl }),
    ).resolves.toEqual({ uploaded: false, status: 503 });
  });
});
