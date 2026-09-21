import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { URL } from 'node:url';

import { mobileApiConfiguration } from '../mobile-api.mjs';

test('unconfigured builds are explicitly compile-only, never phone-local', () => {
  assert.deepEqual(mobileApiConfiguration(undefined), {
    url: 'https://api.invalid',
    artifactKind: 'compile-only',
  });
});

test('public API base URL is normalized for device builds', () => {
  assert.deepEqual(mobileApiConfiguration('https://farmable.test/api/'), {
    url: 'https://farmable.test/api',
    artifactKind: 'device',
  });
});

for (const url of [
  'http://farmable.test',
  'https://localhost',
  'https://app.localhost',
  'https://127.0.0.2',
  'https://[::1]',
  'https://[::]',
  'https://0.0.0.0',
  'https://10.0.2.2',
  'https://api.invalid',
  'https://user:password@farmable.test',
  'https://farmable.test?token=private',
  'https://farmable.test#token',
  'https://farmable.test\nUNSAFE=value',
  'not-a-url',
]) {
  test('reject unsafe API configuration: ' + url.replace(/\n/g, '\\n'), () => {
    assert.throws(() => mobileApiConfiguration(url));
  });
}

test('source-only changes rebuild native artifacts and both builds validate their API URL', () => {
  const workflow = readFileSync(
    new URL('../../.github/workflows/mobile.yml', import.meta.url),
    'utf8',
  );
  assert.match(workflow, /apps\/mobile\/\|/);
  assert.equal((workflow.match(/node scripts\/mobile-api\.mjs/g) || []).length, 2);
  assert.equal((workflow.match(/env\.MOBILE_ARTIFACT_KIND/g) || []).length, 2);
  // A release build must never be pointed at a host-local address: it would
  // appear to work on a developer machine and silently fail on a phone.
  assert.doesNotMatch(workflow, /API_URL=["']?https?:\/\/(localhost|127\.|10\.0\.2\.2)/);
  // Both native builds must pass the validated URL through to Dart.
  assert.equal((workflow.match(/--dart-define=API_URL/g) || []).length, 2);
});
