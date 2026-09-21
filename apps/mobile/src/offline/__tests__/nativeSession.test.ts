import { randomUUID } from 'expo-crypto';
import { addNetworkStateListener, getNetworkStateAsync } from 'expo-network';
import type { NetworkState } from 'expo-network';
import { AppState, Platform } from 'react-native';
import { openNativeDatabase } from '../nativeDatabase';
import { nativePhotoFiles } from '../nativePhotos';
import { openOfflineSession } from '../nativeSession';
import { sqlite } from './sqlite';
import { farmId, mutationId, observation, otherId, ownerId } from './fixtures';
import type { Acknowledgement, Delivery } from '../queue';

jest.mock('expo-crypto', () => ({ randomUUID: jest.fn() }));
jest.mock('expo-network', () => ({
  addNetworkStateListener: jest.fn(),
  getNetworkStateAsync: jest.fn(),
}));
jest.mock('../nativeDatabase', () => ({ openNativeDatabase: jest.fn() }));
jest.mock('../nativePhotos', () => ({ nativePhotoFiles: jest.fn() }));

describe('native lifecycle orchestration (native adapters are injected)', () => {
  const originalAppState = AppState.currentState;
  let session: Awaited<ReturnType<typeof openOfflineSession>> | undefined;
  let networkChanged: (state: NetworkState) => void;
  const networkRemove = jest.fn();
  const appRemove = jest.fn();
  const send = jest.fn<Promise<Acknowledgement>, [Delivery, AbortSignal]>();
  beforeEach(() => {
    jest.replaceProperty(Platform, 'OS', 'android');
    AppState.currentState = 'active';
    jest.spyOn(AppState, 'addEventListener').mockReturnValue({ remove: appRemove });
    jest.mocked(addNetworkStateListener).mockImplementation((callback) => {
      networkChanged = callback;
      return { remove: networkRemove };
    });
    jest.mocked(getNetworkStateAsync).mockResolvedValue({ isConnected: false });
    jest.mocked(openNativeDatabase).mockImplementation(async () => sqlite(':memory:'));
    jest.mocked(nativePhotoFiles).mockReturnValue({
      temporaryFiles: async () => [],
      stat: async () => null,
      header: async () => new Uint8Array(),
      uri: () => '',
      copy: async () => {},
      move: async () => {},
      remove: async () => {},
      prepareDirectory: async () => {},
    });
    jest.mocked(randomUUID).mockReturnValue(otherId);
    send.mockImplementation(async ({ mutation }) => ({
      mutationId: mutation.mutation_id,
      entityId: mutation.entity_id,
      ownerId: mutation.owner_id,
      farmId: mutation.farm_id,
    }));
  });
  afterEach(async () => {
    await session?.close();
    session = undefined;
    jest.restoreAllMocks();
    jest.clearAllMocks();
    AppState.currentState = originalAppState;
  });

  test('production session has no default transport or invented authentication', async () => {
    session = await openOfflineSession({ ownerId, farmId });
    await session.save({ observation, mutationId });
    networkChanged({ isConnected: true, isInternetReachable: true });
    await session.setAuthenticated(true);
    expect((await session.mutations())[0]).toMatchObject({
      sync_state: 'pending',
      attempt_count: 0,
    });
    expect(send).not.toHaveBeenCalled();
  });
  test('network restoration only delivers after authentication is explicitly available', async () => {
    session = await openOfflineSession({ ownerId, farmId }, { transport: { send } });
    await session.save({ observation, mutationId });
    networkChanged({ isConnected: true, isInternetReachable: true });
    expect(send).not.toHaveBeenCalled();
    await session.setAuthenticated(true);
    expect(send).toHaveBeenCalledTimes(1);
    expect((await session.mutations())[0].sync_state).toBe('synced');
  });
  test('late initial connectivity result cannot overwrite a newer network event', async () => {
    let resolve!: (state: NetworkState) => void;
    jest.mocked(getNetworkStateAsync).mockReturnValue(
      new Promise((done) => {
        resolve = done;
      }),
    );
    session = await openOfflineSession({ ownerId, farmId }, { transport: { send } });
    await session.save({ observation, mutationId });
    networkChanged({ isConnected: true, isInternetReachable: true });
    resolve({ isConnected: false });
    await session.setAuthenticated(true);
    expect(send).toHaveBeenCalledTimes(1);
  });
  test('two sessions cannot recover or claim work in the same database concurrently', async () => {
    session = await openOfflineSession({ ownerId, farmId });
    await expect(openOfflineSession({ ownerId, farmId })).rejects.toThrow('scope_already_open');
    await session.close();
    session = await openOfflineSession({ ownerId, farmId });
  });
  test('close removes subscriptions and prevents old-session saves', async () => {
    session = await openOfflineSession({ ownerId, farmId });
    await Promise.all([session.close(), session.close()]);
    expect(networkRemove).toHaveBeenCalledTimes(1);
    expect(appRemove).toHaveBeenCalledTimes(1);
    await expect(session.save({ observation, mutationId })).rejects.toThrow('service_closed');
    networkChanged({ isConnected: true });
    expect(send).not.toHaveBeenCalled();
  });
  test('unsupported platform fails instead of using ephemeral web storage', async () => {
    jest.replaceProperty(Platform, 'OS', 'web');
    await expect(openOfflineSession({ ownerId, farmId })).rejects.toThrow('unsupported_platform');
    expect(openNativeDatabase).not.toHaveBeenCalled();
  });
  test('invalid identity never opens a database', async () => {
    await expect(openOfflineSession({ ownerId: '', farmId })).rejects.toThrow('invalid_uuid');
    expect(openNativeDatabase).not.toHaveBeenCalled();
  });
  test('failed database open releases the scope lock for a later explicit attempt', async () => {
    jest.mocked(openNativeDatabase).mockRejectedValueOnce(new Error('unavailable'));
    await expect(openOfflineSession({ ownerId, farmId })).rejects.toThrow('unavailable');
    session = await openOfflineSession({ ownerId, farmId });
  });
});
