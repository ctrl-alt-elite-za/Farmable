import { fetchApiHealth } from '../health';

describe('fetchApiHealth', () => {
  it('reports online when the API answers', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({ ok: true });

    await expect(fetchApiHealth({ apiUrl: 'http://api.test', fetchImpl })).resolves.toBe('online');
    expect(fetchImpl).toHaveBeenCalledWith('http://api.test/healthz', expect.anything());
  });

  it('reports offline when the API cannot be reached', async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error('Network request failed'));

    await expect(fetchApiHealth({ apiUrl: 'http://api.test', fetchImpl })).resolves.toBe('offline');
  });

  it('reports offline when the API answers with a non-2xx status', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({ ok: false });

    await expect(fetchApiHealth({ apiUrl: 'http://api.test', fetchImpl })).resolves.toBe('offline');
  });
});
