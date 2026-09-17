/**
 * Everything the app reads from its build environment.
 *
 * There are no secrets here and there must never be: the API URL is the app's only
 * setting (issue #4, security criteria). EXPO_PUBLIC_* values are inlined into the
 * JavaScript bundle at build time, so anyone holding the app can read them.
 */
export const API_URL = process.env.EXPO_PUBLIC_API_URL ?? 'http://localhost:8000';

/** Test mode replaces live camera input with recorded frames (emulators, CI). */
export const TEST_MODE = process.env.EXPO_PUBLIC_TEST_MODE === '1';

/** Demo mode is for showing the product to people; never combined with test mode. */
export const DEMO_MODE = process.env.EXPO_PUBLIC_DEMO_MODE === '1';

export const APP_VERSION = process.env.EXPO_PUBLIC_APP_VERSION ?? '0.1.0';

/** Stamped by CI so a self-test report can be traced back to the build that ran it. */
export const BUILD_SHA = process.env.EXPO_PUBLIC_BUILD_SHA ?? 'unknown';
