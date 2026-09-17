import { API_URL } from '../config';
import type { SelfTestReport } from './report';

/** The slice of `fetch` this upload needs, so a test can pass a plain function. */
export type PostLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number }>;

const defaultPost: PostLike = (url, init) => fetch(url, init);

export const SELF_TEST_PATH = '/devices/self-test';

export interface UploadSelfTestOptions {
  apiUrl?: string;
  fetchImpl?: PostLike;
}

export interface UploadResult {
  uploaded: boolean;
  status: number;
}

/**
 * Sends the report to the server. The request carries no credential: the report is
 * the only thing the app sends, and the API URL is the app's only setting (issue #4,
 * security criteria). Contract: docs/api/devices-self-test.md.
 */
export async function uploadSelfTestReport(
  report: SelfTestReport,
  options: UploadSelfTestOptions = {},
): Promise<UploadResult> {
  const { apiUrl = API_URL, fetchImpl = defaultPost } = options;
  try {
    const response = await fetchImpl(`${apiUrl}${SELF_TEST_PATH}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(report),
    });
    return { uploaded: response.ok, status: response.status };
  } catch {
    return { uploaded: false, status: 0 };
  }
}
