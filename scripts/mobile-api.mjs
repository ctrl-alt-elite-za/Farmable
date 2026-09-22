import { appendFileSync } from 'node:fs';
import { argv, env, exit, stdout } from 'node:process';
import { pathToFileURL, URL } from 'node:url';

export function mobileApiConfiguration(value) {
  if (!value) return { url: 'https://api.invalid', artifactKind: 'compile-only' };
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error('MOBILE_API_URL must be a public HTTPS API base URL');
  }
  const host = url.hostname.toLowerCase();
  if (
    url.protocol !== 'https:' ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    /\s/.test(value) ||
    host === 'localhost' ||
    host.endsWith('.localhost') ||
    host.startsWith('127.') ||
    ['[::1]', '[::]', '0.0.0.0', '10.0.2.2'].includes(host) ||
    host.endsWith('.invalid')
  ) {
    throw new Error(
      'MOBILE_API_URL must be HTTPS, phone-reachable, and contain no credentials, query, or fragment',
    );
  }
  return { url: url.href.replace(/\/$/, ''), artifactKind: 'device' };
}

if (argv[1] && import.meta.url === pathToFileURL(argv[1]).href) {
  try {
    const config = mobileApiConfiguration(env.MOBILE_API_URL);
    if (config.artifactKind === 'compile-only') {
      stdout.write(
        '::warning::No MOBILE_API_URL configured. Artifacts are compile-only/offline, not device acceptance evidence.\n',
      );
    }
    appendFileSync(
      env.GITHUB_ENV,
      `MOBILE_API_BASE_URL=${config.url}\nMOBILE_ARTIFACT_KIND=${config.artifactKind}\n`,
    );
  } catch {
    // Never echo the supplied value: someone may accidentally put a token in it.
    stdout.write(
      '::error::Invalid MOBILE_API_URL. Supply a phone-reachable HTTPS base URL without credentials, query, or fragment.\n',
    );
    exit(1);
  }
}
