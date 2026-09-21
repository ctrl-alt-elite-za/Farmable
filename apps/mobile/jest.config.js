/**
 * Jest covers the pure modules and the React Native components that import no
 * native library. The device capabilities (camera, LiDAR, AR, microphone,
 * detector) cannot run here at all - that is what the Self-test screen on a real
 * phone is for. See docs/sideload.md.
 */
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  // Relative globs, not <rootDir>-prefixed ones: on Windows, <rootDir> resolves with
  // backslashes and jest's micromatch-based testMatch cannot match a mixed-separator
  // pattern, so every test silently fails to be discovered.
  testMatch: ['**/__tests__/**/*.test.ts', '**/__tests__/**/*.test.tsx'],
};
