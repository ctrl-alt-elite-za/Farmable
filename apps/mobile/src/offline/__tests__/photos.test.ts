import { mkdtemp, readFile, rm, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { PhotoStorage } from '../photos';
import { ObservationService } from '../service';
import { OfflineStore } from '../store';
import { diskPhotos, PNG } from './files';
import { sqlite } from './sqlite';
import { farmId, mediaId, mutationId, observation, otherId, ownerId, uploadId } from './fixtures';

describe('real local files and SQLite', () => {
  let directory: string;
  let source: string;
  let files: ReturnType<typeof diskPhotos>;
  let photos: PhotoStorage;
  let db: ReturnType<typeof sqlite>;
  let store: OfflineStore;
  let service: ObservationService;
  const input = () => ({
    observation,
    mutationId,
    photo: {
      mediaId,
      mutationId: uploadId,
      input: { uri: source, contentType: 'image/png' as const },
    },
  });
  beforeEach(async () => {
    directory = await mkdtemp(join(tmpdir(), 'farmable-photo-'));
    source = pathToFileURL(join(directory, 'camera.png')).href;
    await writeFile(fileURLToPath(source), PNG);
    files = diskPhotos(join(directory, 'owned'));
    photos = new PhotoStorage(files, { ownerId, farmId }, () => otherId);
    db = sqlite(join(directory, 'queue.db'));
    store = await OfflineStore.open(db, { ownerId, farmId });
    service = new ObservationService(store, photos, () => 1000);
  });
  afterEach(async () => {
    await service.stop();
    await store.close();
    await rm(directory, { recursive: true });
  });

  test('photo survives database reopen and deletion of the original capture', async () => {
    const saved = await service.save(input());
    expect(saved.localMediaId).toBe(mediaId);
    const media = (await store.media(mediaId))!;
    expect(media.relativePath).not.toContain('file:');
    await rm(fileURLToPath(source));
    await service.stop();
    await store.close();
    store = await OfflineStore.open(sqlite(join(directory, 'queue.db')), { ownerId, farmId });
    const uri = await photos.view((await store.media(mediaId))!);
    expect(await readFile(fileURLToPath(uri))).toEqual(PNG);
    expect(await store.observations()).toHaveLength(1);
  });
  test('failed DB commit removes only its new unreferenced attachment', async () => {
    await db.exec(
      "CREATE TRIGGER reject_mutation BEFORE INSERT ON mutations BEGIN SELECT RAISE(ABORT, 'synthetic_full'); END;",
    );
    await expect(service.save(input())).rejects.toThrow('synthetic_full');
    expect(await store.observations()).toHaveLength(0);
    expect(await files.stat(source)).not.toBeNull();
    expect(await files.stat(files.uri(`${ownerId}/${farmId}/${mediaId}.png`))).toBeNull();
  });
  test('duplicate confirmation retains existing file; changed content cannot overwrite it', async () => {
    await service.save(input());
    await service.save(input());
    await expect(
      service.save({ ...input(), observation: { ...observation, note: 'changed' } }),
    ).rejects.toThrow('mutation_reused');
    expect(await store.observations()).toHaveLength(1);
    expect(await readFile(fileURLToPath(await photos.view((await store.media(mediaId))!)))).toEqual(
      PNG,
    );
  });
  test('partial copy failure leaves no falsely saved observation and preserves capture', async () => {
    files.copy = async (_, destination) => {
      await writeFile(fileURLToPath(destination), PNG.subarray(0, 4));
      throw new Error('disk full');
    };
    await expect(service.save(input())).rejects.toThrow('disk full');
    expect(await store.observations()).toHaveLength(0);
    expect(await files.stat(source)).not.toBeNull();
    expect(await files.temporaryFiles(`${ownerId}/${farmId}`)).toEqual([]);
  });
  test('move failure preserves input and removes temporary copy', async () => {
    files.move = async () => {
      throw new Error('move failed');
    };
    await expect(service.save(input())).rejects.toThrow('move failed');
    expect(await files.stat(source)).not.toBeNull();
    expect(await store.mutations()).toHaveLength(0);
    expect(await files.temporaryFiles(`${ownerId}/${farmId}`)).toEqual([]);
  });
  test('existing final file is never overwritten or deleted', async () => {
    await photos.stage(input().photo.input, mediaId);
    await expect(service.save(input())).rejects.toThrow('media_exists');
    expect(await files.stat(files.uri(`${ownerId}/${farmId}/${mediaId}.png`))).not.toBeNull();
  });
  test('missing attachment does not remove its observation', async () => {
    await service.save(input());
    const media = (await store.media(mediaId))!;
    await files.remove(await photos.view(media));
    await expect(photos.view(media)).rejects.toThrow('missing_media');
    expect(await store.observations()).toHaveLength(1);
  });
  test('startup cleanup only removes stale temporary files', async () => {
    await service.save(input());
    const path = files.uri(`${ownerId}/${farmId}/${otherId}.tmp`);
    await writeFile(fileURLToPath(path), 'partial');
    const old = new Date(Date.now() - 172800000);
    await utimes(fileURLToPath(path), old, old);
    await photos.recover(Date.now());
    expect(await files.stat(path)).toBeNull();
    expect(await photos.view((await store.media(mediaId))!)).toContain('.png');
    expect(await files.stat(source)).not.toBeNull();
  });
  test('recent temp and unreferenced final files survive conservative startup cleanup', async () => {
    const orphan = await photos.stage(input().photo.input, mediaId);
    const temp = files.uri(`${ownerId}/${farmId}/${otherId}.tmp`);
    await writeFile(fileURLToPath(temp), 'partial');
    await photos.recover(Date.now());
    expect(await files.stat(temp)).not.toBeNull();
    expect(await photos.view(orphan)).toContain('.png');
  });
  test.each(['https://example.com/image.png', 'content://untrusted/image', '../camera.png'])(
    'rejects unsupported source %s',
    async (uri) => {
      await expect(photos.stage({ uri, contentType: 'image/png' }, mediaId)).rejects.toThrow(
        'invalid_photo_uri',
      );
    },
  );
  test.each([0, 5000001])('rejects photo size %i', async (size) => {
    await writeFile(fileURLToPath(source), Buffer.alloc(size));
    await expect(service.save(input())).rejects.toThrow('invalid_photo_size');
    expect(await store.observations()).toHaveLength(0);
  });
  test('file signature must match declared type', async () => {
    await expect(photos.stage({ uri: source, contentType: 'image/jpeg' }, mediaId)).rejects.toThrow(
      'invalid_photo_type',
    );
  });
  test('path traversal and another account cannot read media', async () => {
    await service.save(input());
    const media = (await store.media(mediaId))!;
    await expect(photos.view({ ...media, relativePath: '../camera.png' })).rejects.toThrow(
      'invalid_media_scope',
    );
    await expect(photos.view({ ...media, ownerId: otherId })).rejects.toThrow(
      'invalid_media_scope',
    );
  });
});
