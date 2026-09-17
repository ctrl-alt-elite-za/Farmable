import { API_URL } from '../config';

/** The smallest slice of `fetch` this app uses, so a test can pass a plain function. */
export type FetchLike = (url: string, init?: { signal?: AbortSignal }) => Promise<{ ok: boolean }>;

export type ApiHealth = 'online' | 'offline';

const defaultFetch: FetchLike = (url, init) => fetch(url, init as RequestInit);

export interface FetchApiHealthOptions {
  apiUrl?: string;
  fetchImpl?: FetchLike;
  timeoutMs?: number;
}

/**
 * Every failure - unreachable server, timeout, non-2xx - becomes 'offline' rather
 * than an exception, so the app opens and stays usable when the API is down
 * (issue #4, reliability criteria).
 */
export async function fetchApiHealth(options: FetchApiHealthOptions = {}): Promise<ApiHealth> {
  const { apiUrl = API_URL, fetchImpl = defaultFetch, timeoutMs = 3000 } = options;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(`${apiUrl}/healthz`, { signal: controller.signal });
    return response.ok ? 'online' : 'offline';
  } catch {
    return 'offline';
  } finally {
    clearTimeout(timer);
  }
}
