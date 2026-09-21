import { installOfflineProbe, runOfflineProbe } from '../nativeProbe.native';
import { installOfflineProbe as installWebProbe } from '../nativeProbe';
import { openNativeDatabase } from '../nativeDatabase';
import { otherId } from './fixtures';

jest.mock('../../config', () => ({ TEST_MODE: false, DEMO_MODE: false }));
jest.mock('expo-crypto', () => ({ randomUUID: jest.fn() }));
jest.mock('expo-file-system', () => ({
  Directory: jest.fn(),
  File: jest.fn(),
  Paths: {},
  EncodingType: {},
}));
jest.mock('../nativeDatabase', () => ({ openNativeDatabase: jest.fn() }));
jest.mock('../nativePhotos', () => ({ nativePhotoFiles: jest.fn() }));

const config = jest.requireMock<{ TEST_MODE: boolean; DEMO_MODE: boolean }>('../../config');

const probeGlobal = globalThis as typeof globalThis & {
  farmableOfflineProbe?: typeof runOfflineProbe;
};
afterEach(() => {
  delete probeGlobal.farmableOfflineProbe;
  jest.restoreAllMocks();
  jest.clearAllMocks();
});

test('production and default/web entry never install a persistence probe', async () => {
  installOfflineProbe();
  installWebProbe();
  expect(probeGlobal.farmableOfflineProbe).toBeUndefined();
  await expect(runOfflineProbe('seed', otherId)).rejects.toThrow('test_mode_required');
  expect(openNativeDatabase).not.toHaveBeenCalled();
});
test('test/demo combination refuses the probe and all storage operations', async () => {
  jest.replaceProperty(config, 'TEST_MODE', true);
  jest.replaceProperty(config, 'DEMO_MODE', true);
  installOfflineProbe();
  expect(probeGlobal.farmableOfflineProbe).toBeUndefined();
  await expect(runOfflineProbe('seed', otherId)).rejects.toThrow('test_mode_required');
  expect(openNativeDatabase).not.toHaveBeenCalled();
});
test('test mode installs the probe but validates phase/ID before opening files', async () => {
  jest.replaceProperty(config, 'TEST_MODE', true);
  installOfflineProbe();
  expect(probeGlobal.farmableOfflineProbe).toBe(runOfflineProbe);
  await expect(runOfflineProbe('seed', '../data')).rejects.toThrow('invalid_uuid');
  await expect(runOfflineProbe('clear' as 'seed', otherId)).rejects.toThrow('invalid_probe_phase');
  expect(openNativeDatabase).not.toHaveBeenCalled();
});
