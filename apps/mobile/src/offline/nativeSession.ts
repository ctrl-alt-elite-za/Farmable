import { randomUUID } from 'expo-crypto';
import { addNetworkStateListener, getNetworkStateAsync } from 'expo-network';
import { AppState, Platform } from 'react-native';
import { openNativeDatabase } from './nativeDatabase';
import { nativePhotoFiles } from './nativePhotos';
import { PhotoStorage } from './photos';
import { MutationQueue, type SyncTransport } from './queue';
import { ObservationService } from './service';
import { OfflineStore } from './store';
import { OfflineError, scope } from './types';
import type { ObservationInput, Scope } from './types';
import type { PhotoInput } from './photos';

// One owner of each private connection, including asynchronous open/close.
const openScopes = new Set<string>();

/** Requires real identity/farm supplied by a future authenticated app shell. */
export async function openOfflineSession(
  value: Scope,
  options: { transport?: SyncTransport; onError?: (code: string) => void } = {},
) {
  if (Platform.OS !== 'android' && Platform.OS !== 'ios')
    throw new OfflineError('unsupported_platform');
  const identity = scope(value);
  const name = `offline-${identity.ownerId}-${identity.farmId}.db`;
  if (openScopes.has(name)) throw new OfflineError('scope_already_open');
  openScopes.add(name);
  let store: OfflineStore | undefined;
  let network: ReturnType<typeof addNetworkStateListener> | undefined;
  let app: ReturnType<typeof AppState.addEventListener> | undefined;
  let queue: MutationQueue | undefined;
  try {
    store = await OfflineStore.open(await openNativeDatabase(name), identity);
    const ownedStore = store;
    const photos = new PhotoStorage(nativePhotoFiles(), identity, randomUUID);
    await photos.recover(Date.now());
    queue = new MutationQueue(store, { ...options, photoUri: (media) => photos.view(media) });
    const ownedQueue = queue;
    const service = new ObservationService(store, photos, Date.now, () => {
      void ownedQueue.wake();
    });
    let closed = false;
    let closePromise: Promise<void> | undefined;
    let online = false;
    let authenticated = false;
    let networkEvents = 0;
    const update = () =>
      closed
        ? Promise.resolve()
        : ownedQueue.setConditions({
            online,
            authenticated,
            foreground: AppState.currentState === 'active',
          });
    network = addNetworkStateListener((state) => {
      networkEvents++;
      online = state.isConnected === true && state.isInternetReachable !== false;
      void update();
    });
    app = AppState.addEventListener('change', () => {
      void update();
    });
    const initialEvents = networkEvents;
    void getNetworkStateAsync()
      .then((state) => {
        if (closed || networkEvents !== initialEvents) return;
        online = state.isConnected === true && state.isInternetReachable !== false;
        void update();
      })
      .catch(() => options.onError?.('connectivity_unavailable'));
    return {
      scope: identity,
      /** Allocate once before confirmation; retain this request if saving fails. */
      newObservation(input: Omit<ObservationInput, 'id'>, photo?: PhotoInput) {
        return {
          observation: { ...input, id: randomUUID() },
          mutationId: randomUUID(),
          photo: photo
            ? { input: photo, mediaId: randomUUID(), mutationId: randomUUID() }
            : undefined,
        };
      },
      save: service.save.bind(service),
      observations: () => ownedStore.observations(),
      mutations: () => ownedStore.mutations(),
      async photoUri(id: string) {
        const media = await ownedStore.media(id);
        if (!media) throw new OfflineError('missing_media');
        return photos.view(media);
      },
      async retry(id: string) {
        await ownedStore.retry(id);
        await ownedQueue.wake();
      },
      async setAuthenticated(available: boolean) {
        authenticated = available;
        await update();
      },
      credentialsUpdated: () => ownedQueue.credentialsUpdated(),
      close() {
        if (closePromise) return closePromise;
        closed = true;
        network?.remove();
        app?.remove();
        closePromise = (async () => {
          try {
            await Promise.all([ownedQueue.stop(), service.stop()]);
            await ownedStore.close();
          } finally {
            openScopes.delete(name);
          }
        })();
        return closePromise;
      },
    };
  } catch (error) {
    network?.remove();
    app?.remove();
    await queue?.stop();
    try {
      await store?.close();
    } finally {
      openScopes.delete(name);
    }
    throw error;
  }
}
