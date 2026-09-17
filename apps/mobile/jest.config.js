/**
 * Jest covers the pure modules and the React Native components that import no
 * native library. The device capabilities (camera, LiDAR, AR, microphone,
 * detector) cannot run here at all - that is what the Self-test screen on a real
 * phone is for. See docs/sideload.md.
 */
module.exports = {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  testMatch: [
    '<rootDir>/src/**/__tests__/**/*.test.ts',
    '<rootDir>/src/**/__tests__/**/*.test.tsx',
  ],
};
