import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { URL } from 'node:url';
import test from 'node:test';

function page(simulation = false) {
  const config = { action: 'sign_up', state: 'request-state', sitekey: 'public-key', simulation };
  const messages = [];
  let options;
  const script = readFileSync(
    new URL('../../apps/backend/src/farmable_backend/static/turnstile.js', import.meta.url),
    'utf8',
  );
  const context = {
    document: { getElementById: () => ({ dataset: { config: JSON.stringify(config) } }) },
    FarmableChallenge: { postMessage: (message) => messages.push(JSON.parse(message)) },
    turnstile: {
      render: (_selector, value) => {
        options = value;
      },
    },
  };
  runInNewContext(script, context);
  return { context, messages, options: () => options };
}

test('live challenge waits for Cloudflare and binds the returned token to its request', () => {
  const run = page();
  assert.deepEqual(run.messages, []);
  run.context.onFarmableChallengeReady();
  assert.equal(run.options().sitekey, 'public-key');
  assert.equal(run.options().action, 'sign_up');
  run.options().callback('one-use-token');
  assert.deepEqual(run.messages, [
    { state: 'request-state', status: 'success', token: 'one-use-token' },
  ]);
});

test('errors and token expiry fail closed without forwarding provider details', () => {
  for (const callback of ['error-callback', 'expired-callback', 'timeout-callback']) {
    const run = page();
    run.context.onFarmableChallengeReady();
    run.options()[callback]('sensitive-provider-detail');
    assert.deepEqual(run.messages, [{ state: 'request-state', status: 'error' }]);
  }
});

test('only the explicitly simulated page can finish without the external provider', () => {
  const run = page(true);
  assert.equal(run.options(), undefined);
  assert.deepEqual(run.messages, [
    {
      state: 'request-state',
      status: 'success',
      token: 'ci-turnstile-sign_up-request-state',
    },
  ]);
});
