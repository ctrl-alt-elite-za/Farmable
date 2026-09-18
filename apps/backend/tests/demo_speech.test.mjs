import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SpeechController } from '../src/farmable_backend/demo_api/web/speech.mjs';

function setup(options = {}) {
  const order = [];
  const states = [];
  const errors = [];
  const transcripts = [];
  const timers = new Map();
  let timerId = 0;
  const recognitions = [];
  class Recognition {
    constructor() {
      recognitions.push(this);
    }
    start() {
      order.push('start');
      if (options.startFails) throw new Error('denied');
    }
    abort() {
      order.push('abort');
      this.onend?.();
    }
  }
  const env = {
    isSecureContext: true,
    SpeechRecognition: Recognition,
    SpeechSynthesisUtterance: class {
      constructor(text) {
        this.text = text;
      }
    },
    speechSynthesis: {
      cancel() {
        order.push('cancel');
      },
      getVoices() {
        return [{ lang: 'en-ZA', localService: true }];
      },
      speak(utterance) {
        env.utterance = utterance;
        order.push('speak');
      },
    },
    setTimeout(callback) {
      timerId += 1;
      timers.set(timerId, callback);
      return timerId;
    },
    clearTimeout(id) {
      timers.delete(id);
    },
    ...options.env,
  };
  const controller = new SpeechController({
    env,
    onState: (state) => states.push(state),
    onTranscript: (text, final) => transcripts.push({ text, final }),
    onError: (error) => errors.push(error),
  });
  return { controller, env, recognitions, states, errors, transcripts, timers, order };
}
function result(text, final = true) {
  return { resultIndex: 0, results: [Object.assign([{ transcript: text }], { isFinal: final })] };
}

test('consent is required; unsupported and insecure contexts fall back', () => {
  const s = setup();
  s.controller.listen(false);
  assert.equal(s.recognitions.length, 0);
  assert.match(s.errors[0], /consent/);
  for (const env of [{ SpeechRecognition: undefined }, { isSecureContext: false }]) {
    const unavailable = setup({ env });
    unavailable.controller.listen(true);
    assert.equal(unavailable.recognitions.length, 0);
    assert.equal(unavailable.controller.state, 'idle');
    assert.match(unavailable.errors[0], /type/);
  }
});
test('webkit speech constructor is supported', () => {
  const s = setup();
  s.env.webkitSpeechRecognition = s.env.SpeechRecognition;
  delete s.env.SpeechRecognition;
  assert.equal(s.controller.supported(), true);
  s.controller.listen(true);
  assert.equal(s.recognitions[0].lang, 'en-ZA');
});
test('final transcript is returned once, then mic and timers stop', () => {
  const s = setup();
  s.controller.listen(true);
  const recognition = s.recognitions[0];
  recognition.onresult(result('keep half', false));
  recognition.onresult(result('keep half cabbage'));
  recognition.onresult(result('late duplicate'));
  assert.deepEqual(s.transcripts, [
    { text: 'keep half', final: false },
    { text: 'keep half cabbage', final: true },
  ]);
  assert.equal(s.controller.state, 'idle');
  assert.equal(s.timers.size, 0);
  assert.equal(s.errors.length, 0);
});
test('tap interrupt cancels playback before listening and ignores stale audio callbacks', () => {
  const s = setup();
  s.controller.speak('a reply', true);
  const old = s.env.utterance;
  s.order.length = 0;
  s.controller.listen(true);
  assert.deepEqual(s.order, ['cancel', 'start']);
  old.onend();
  old.onerror();
  assert.equal(s.controller.state, 'listening');
  assert.equal(s.errors.length, 0);
});
test('old recognition cannot replace a newer turn or report old errors', () => {
  const s = setup();
  s.controller.listen(true);
  const old = s.recognitions[0];
  s.controller.listen(true);
  old.onresult(result('stale budget'));
  old.onerror();
  old.onend();
  assert.equal(s.controller.state, 'listening');
  assert.equal(s.transcripts.length, 0);
  s.recognitions[1].onresult(result('new budget'));
  assert.equal(s.transcripts[0].text, 'new budget');
  assert.equal(s.errors.length, 0);
});
test('denied mic, empty results, long results, no final result and timeout return to typing', () => {
  const denied = setup({ startFails: true });
  denied.controller.listen(true);
  assert.equal(denied.controller.state, 'idle');
  assert.match(denied.errors[0], /type/);
  for (const action of [
    (r) => r.onerror(),
    (r) => r.onend(),
    (r) => r.onresult(result('')),
    (r) => r.onresult(result('x'.repeat(301))),
  ]) {
    const s = setup();
    s.controller.listen(true);
    action(s.recognitions[0]);
    assert.equal(s.controller.state, 'idle');
    assert.equal(s.timers.size, 0);
    assert.equal(s.errors.length, 1);
  }
  const s = setup();
  s.controller.listen(true);
  [...s.timers.values()][0]();
  assert.equal(s.controller.state, 'idle');
  assert.match(s.errors[0], /timed out/);
});
test('stop invalidates all callbacks and clears pending timers', () => {
  const s = setup();
  s.controller.listen(true);
  const old = s.recognitions[0];
  s.controller.stop();
  old.onresult(result('late'));
  assert.equal(s.transcripts.length, 0);
  assert.equal(s.timers.size, 0);
  assert.equal(s.controller.state, 'idle');
});
test('spoken replies select an English voice and failure retains text fallback', () => {
  const s = setup();
  s.controller.speak('test reply', true);
  assert.equal(s.env.utterance.text, 'test reply');
  assert.equal(s.env.utterance.voice.lang, 'en-ZA');
  s.env.utterance.onerror();
  assert.equal(s.controller.state, 'idle');
  assert.match(s.errors[0], /text/);
  const missing = setup({ env: { speechSynthesis: undefined } });
  missing.controller.speak('reply', true);
  assert.match(missing.errors[0], /read/);
  const noConsent = setup();
  noConsent.controller.speak('reply', false);
  assert.equal(noConsent.env.utterance, undefined);
});
