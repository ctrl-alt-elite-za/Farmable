// The public challenge bridge; no account information belongs on this page.
(() => {
  const config = JSON.parse(globalThis.document.getElementById('challenge-config').textContent);
  const send = (result) =>
    globalThis.FarmableChallenge.postMessage(JSON.stringify({ state: config.state, ...result }));
  const fail = () => send({ status: 'error' });
  globalThis.onFarmableChallengeReady = () => {
    try {
      globalThis.turnstile.render('#challenge', {
        sitekey: config.sitekey,
        action: config.action,
        size: 'compact',
        callback: (token) => send({ status: 'success', token }),
        'error-callback': fail,
        'expired-callback': fail,
        'timeout-callback': fail,
      });
    } catch {
      fail();
    }
  };
  if (config.simulation === true) {
    send({ status: 'success', token: `ci-turnstile-${config.action}-${config.state}` });
  }
})();
