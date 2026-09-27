# Mobile signup and login verification

The existing signup/login forms remain in place. Before either submits credentials,
the app opens a verification prompt using the official Flutter WebView. It loads
`GET /auth/turnstile?action=sign_up|login&state=<UUID>` from the configured API origin.
Cloudflare issues a one-use token; the page passes it through a request-bound native
bridge. `ApiAuthService` sends that token in the existing `turnstile_token` field.
The API still validates it with Siteverify, including the action and hostname.

Cancellation, timeout, malformed responses and failed page loads do not submit
credentials. A new attempt gets a new challenge. Tokens are not saved to session
storage or logged. Main-frame navigation cannot leave the expected challenge URL;
provider subframes are limited to Cloudflare's HTTPS origin and its blank/srcdoc
frames. The prompt does not receive passwords, OTPs or account/session tokens.

## Live deployment prerequisites

Configure a Cloudflare Turnstile widget for the API's public hostname. Supply:

- `TURNSTILE_SITE_KEY`: the public key for that widget.
- `TURNSTILE_HOSTNAME`: the exact hostname serving the challenge page, without scheme/path.
- `TURNSTILE_SECRET`: the matching secret, kept only in backend secret storage.

The existing GCP Secret Manager pattern includes `turnstile-site-key` alongside
`turnstile-hostname` and `turnstile-secret`, with the deployment's normal name prefix.
The public key is not confidential, but keeping the three settings together avoids
separate build-time configuration. Terraform declares containers, not secret values;
the operator must populate enabled versions before rollout. No infrastructure is
applied by this change. Compose also passes the public key from the environment.

Use an HTTPS `API_URL` on devices. The widget's allowed hostname must match this
origin; the challenge endpoint fails closed when the hostname/configuration does
not match. No keys belong in Dart defines. Do not pin or proxy Cloudflare's widget
script. See [Cloudflare's mobile guidance](https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/).

## Isolated checks versus live verification

Only `ENVIRONMENT=ci` **and** `INTEGRATIONS_MODE=fake` produce a simulated challenge
page. It still traverses the native WebView bridge and the real mobile/API contract,
but cannot establish that Cloudflare or SMS/email delivery works on a live device.
No production/staging page generates fixture tokens. A test-mode mobile build can
use HTTP only for localhost/emulator addresses; production builds require HTTPS.

`make test` runs the page bridge and backend route tests. `make mobile-checks`
covers the mobile contract, cancellation, request binding and unchanged form
state. The existing Maestro signup/OTP/login journey runs through the native page
in `e2e-mobile`; its assertions are not relaxed for this integration.

Before claiming live readiness, install a build pointing at the approved HTTPS
API on Android and iOS, complete a real signup (phone then email), restart, sign
out and log in again. Check cancellation and loss of connectivity. Confirm that
the same token cannot be reused, and that bad actions/hostnames are rejected.
Live provider keys, approved hostname and physical-device results are external
prerequisites; unit tests and simulated CI do not replace them.

Scope: PR #74's backend regression fixes and its blocked signup/login verification
path. No farm-screen redesign, password-reset feature, provider migration or
production deployment is included.
