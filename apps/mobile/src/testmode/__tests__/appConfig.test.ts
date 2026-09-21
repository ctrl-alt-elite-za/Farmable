import type { ExpoConfig } from 'expo/config';

const originalTestMode = process.env.EXPO_PUBLIC_TEST_MODE;

afterEach(() => {
  if (originalTestMode === undefined) delete process.env.EXPO_PUBLIC_TEST_MODE;
  else process.env.EXPO_PUBLIC_TEST_MODE = originalTestMode;
});

function loadConfig(): ExpoConfig {
  let config: ExpoConfig | undefined;
  jest.isolateModules(() => {
    config =
      jest.requireActual<typeof import('../../../app.config')>('../../../app.config').default;
  });
  if (!config) throw new Error('App config did not load');
  return config;
}

function viroModes(config: ExpoConfig): string[] {
  const plugin = config.plugins?.find(
    (entry) => Array.isArray(entry) && entry[0] === '@reactvision/react-viro',
  );
  if (!Array.isArray(plugin)) throw new Error('Viro plugin is missing');
  return (plugin[1] as { android: { xRMode: string[] } }).android.xRMode;
}

it.each([undefined, '0', 'true'])('keeps native AR registration outside test mode (%s)', (mode) => {
  if (mode === undefined) delete process.env.EXPO_PUBLIC_TEST_MODE;
  else process.env.EXPO_PUBLIC_TEST_MODE = mode;
  expect(viroModes(loadConfig())).toEqual(['AR', 'GVR']);
});

it('does not initialize the ARM-only Viro renderer in an x86_64 test build', () => {
  process.env.EXPO_PUBLIC_TEST_MODE = '1';
  const config = loadConfig();
  expect(viroModes(config)).toEqual([]);
  // The plugin remains enabled, so this changes Android registration only.
  expect(config.plugins).toContain('./with-viro-monorepo');
  expect(config.ios?.bundleIdentifier).toBe('za.co.ctrlaltelite.farmable');
});
