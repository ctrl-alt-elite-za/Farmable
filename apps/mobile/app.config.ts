import type { ExpoConfig } from 'expo/config';

const CAMERA_REASON = 'To scan your crops and animals';
const MICROPHONE_REASON = 'To talk to the assistant';
const LOCATION_REASON = 'To map your farm sections';

/**
 * Every native library the features need is configured here at once. Each native
 * change costs a fresh build and a fresh manual install on the iPhone, so finding a
 * missing library later would cost a day (issue #4).
 *
 * No key or secret belongs in this file: the API URL is the app's only setting and
 * it arrives as EXPO_PUBLIC_API_URL at build time.
 */
const config: ExpoConfig = {
  name: 'Farmable',
  slug: 'farmable',
  scheme: 'farmable',
  version: '0.1.0',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  // New Architecture is the default in Expo SDK 57; no config flag is needed.
  ios: {
    bundleIdentifier: 'za.co.ctrlaltelite.farmable',
    supportsTablet: false,
    infoPlist: {
      NSCameraUsageDescription: CAMERA_REASON,
      NSMicrophoneUsageDescription: MICROPHONE_REASON,
      NSLocationWhenInUseUsageDescription: LOCATION_REASON,
      ITSAppUsesNonExemptEncryption: false,
    },
  },
  android: {
    package: 'za.co.ctrlaltelite.farmable',
    permissions: [
      'android.permission.CAMERA',
      'android.permission.RECORD_AUDIO',
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
    ],
  },
  plugins: [
    'expo-dev-client',
    [
      'expo-build-properties',
      {
        ios: { deploymentTarget: '16.4' },
        android: {
          minSdkVersion: 26,
          compileSdkVersion: 36,
          targetSdkVersion: 36,
          // Only isolated emulator test builds may use the runner's HTTP API.
          usesCleartextTraffic: process.env.EXPO_PUBLIC_TEST_MODE === '1',
        },
      },
    ],
    ['expo-location', { locationWhenInUsePermission: LOCATION_REASON }],
    ['expo-audio', { microphonePermissionText: MICROPHONE_REASON }],
    './with-viro-monorepo',
    '@reactvision/react-viro',
  ],
};

export default config;
