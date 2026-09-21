/** Native test-build-only, two-process probe. Never installs a real transport. */
import { randomUUID } from 'expo-crypto';
import { Directory, EncodingType, File, Paths } from 'expo-file-system';
import { DEMO_MODE, TEST_MODE } from '../config';
import { openNativeDatabase } from './nativeDatabase';
import { nativePhotoFiles } from './nativePhotos';
import { PhotoStorage } from './photos';
import { MutationQueue } from './queue';
import { ObservationService } from './service';
import { OfflineStore } from './store';
import { OfflineError, TransportError, uuid } from './types';

const active = new Set<string>();
const OWNER = '10000000-0000-4000-8000-000000000001';
const FARM = '10000000-0000-4000-8000-000000000002';
const SECTION = '10000000-0000-4000-8000-000000000003';
const PNG =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE5sAAAAASUVORK5CYII=';

export async function runOfflineProbe(phase: 'seed' | 'verify', runId: string) {
  if (!TEST_MODE || DEMO_MODE) throw new OfflineError('test_mode_required');
  uuid(runId);
  if (phase !== 'seed' && phase !== 'verify') throw new OfflineError('invalid_probe_phase');
  if (active.has(runId)) throw new OfflineError('probe_busy');
  active.add(runId);
  let store: OfflineStore | undefined;
  let service: ObservationService | undefined;
  let queue: MutationQueue | undefined;
  try {
    store = await OfflineStore.open(await openNativeDatabase(`offline-probe-${runId}.db`), {
      ownerId: OWNER,
      farmId: FARM,
    });
    const photos = new PhotoStorage(
      nativePhotoFiles('offline-probe-media'),
      store.scope,
      randomUUID,
    );
    service = new ObservationService(store, photos);
    if (phase === 'seed') {
      if ((await store.observations()).length) throw new OfflineError('probe_already_seeded');
      const directory = new Directory(Paths.document, 'offline-probe-captures');
      directory.create({ intermediates: true, idempotent: true });
      const capture = new File(directory, `${runId}.png`);
      capture.create({ overwrite: false });
      capture.write(PNG, { encoding: EncodingType.Base64 });
      await service.save({
        observation: { id: runId, sectionId: SECTION, type: 'note', note: 'Offline restart probe' },
        mutationId: randomUUID(),
        photo: {
          mediaId: randomUUID(),
          mutationId: randomUUID(),
          input: { uri: capture.uri, contentType: 'image/png' },
        },
      });
      // Simulate a process dying with a claim in progress. No network call occurs.
      await store.claim(Date.now());
      capture.delete(); // Only this probe's synthetic source, never user photos.
      return {
        phase,
        result: 'saved_locally',
        runId,
        next: 'Terminate app WITHOUT clearing data; relaunch and run verify.',
      };
    }
    const rows = await store.observations();
    if (rows.length !== 1 || rows[0].id !== runId || !rows[0].localMediaId)
      throw new OfflineError('probe_record_missing');
    const media = await store.media(rows[0].localMediaId);
    if (!media) throw new OfflineError('probe_media_missing');
    const localUri = await photos.view(media);
    if ((await new File(localUri).base64()) !== PNG) throw new OfflineError('probe_photo_changed');
    const recovered = await store.mutations();
    if (recovered.length !== 2 || recovered.some((m) => m.sync_state !== 'pending'))
      throw new OfflineError('probe_recovery_failed');
    let attempted = false;
    queue = new MutationQueue(store, {
      photoUri: (item) => photos.view(item),
      transport: {
        async send() {
          attempted = true;
          throw new TransportError('transient');
        },
      },
    });
    await queue.setConditions({ online: true, foreground: true, authenticated: true });
    await queue.stop();
    if (!attempted) throw new OfflineError('probe_retry_not_due');
    if ((await store.observations()).length !== 1 || !(await photos.view(media)))
      throw new OfflineError('probe_data_lost');
    return {
      phase,
      result: 'restart_and_failed_upload_preserved',
      runId,
      localUri,
      serverSync: 'NOT_VERIFIED',
    };
  } finally {
    try {
      await queue?.stop();
      await service?.stop();
      await store?.close();
    } finally {
      active.delete(runId);
    }
  }
}

/** Exposed only in test-mode builds for React Native DevTools; no new app UI. */
export function installOfflineProbe() {
  if (TEST_MODE && !DEMO_MODE) {
    (
      globalThis as typeof globalThis & { farmableOfflineProbe?: typeof runOfflineProbe }
    ).farmableOfflineProbe = runOfflineProbe;
  }
}
