// Compile-time API contract; #4 will add the Expo UI, not this issue.
import { createApiClient, type components } from '@farmable/api-client';

export async function checkHealthContract(baseUrl: string) {
  const client = createApiClient(baseUrl);
  const { data, error } = await client.GET('/health/ready');
  if (data) {
    const database: 'ok' | 'down' = data.database;
    const worker: 'ok' | 'down' = data.worker;
    const sha: string = data.sha;
    return { database, worker, sha };
  }
  return error;
}

export function rejectInvalidContract() {
  const response: components['schemas']['ReadyResponse'] = {
    database: 'ok',
    worker: 'down',
    sha: 'test',
  };
  // @ts-expect-error schema changes must not silently permit unknown status values
  response.database = 'unhealthy';
  const client = createApiClient('http://localhost:8000');
  // @ts-expect-error arbitrary endpoints must not be accepted by the generated client
  void client.GET('/not-an-api-route');
  return response;
}
