import { OfflineError, scope, uuid } from './types';
import type { Media, Scope } from './types';

export interface PhotoInput {
  uri: string;
  contentType: Media['contentType'];
}
export interface PhotoFiles {
  stat(uri: string): Promise<{ size: number; modifiedAt: number | null } | null>;
  header(uri: string): Promise<Uint8Array>;
  copy(source: string, destination: string): Promise<void>;
  move(source: string, destination: string): Promise<void>;
  remove(uri: string): Promise<void>;
  prepareDirectory(relative: string): Promise<void>;
  uri(relative: string): string;
  temporaryFiles(relativeDirectory: string): Promise<string[]>;
}

export class PhotoStorage {
  readonly scope: Readonly<Scope>;
  constructor(
    private readonly files: PhotoFiles,
    value: Scope,
    private readonly newId: () => string,
  ) {
    this.scope = Object.freeze(scope(value));
  }
  private path(id: string, type: Media['contentType']): string {
    uuid(id);
    if (type !== 'image/jpeg' && type !== 'image/png') throw new OfflineError('invalid_photo');
    return `${this.scope.ownerId}/${this.scope.farmId}/${id}.${type === 'image/jpeg' ? 'jpg' : 'png'}`;
  }
  private async validate(uri: string, type: Media['contentType']): Promise<number> {
    const stat = await this.files.stat(uri);
    if (!stat || stat.size < 1 || stat.size > 5000000) throw new OfflineError('invalid_photo_size');
    const bytes = await this.files.header(uri);
    const signature = type === 'image/png' ? [137, 80, 78, 71, 13, 10, 26, 10] : [255, 216, 255];
    if (!signature.every((value, index) => bytes[index] === value))
      throw new OfflineError('invalid_photo_type');
    return stat.size;
  }
  async stage(input: PhotoInput, id: string): Promise<Media> {
    if (!input.uri.startsWith('file:///')) throw new OfflineError('invalid_photo_uri');
    const relativePath = this.path(id, input.contentType);
    const directory = `${this.scope.ownerId}/${this.scope.farmId}`;
    const temp = this.files.uri(`${directory}/${uuid(this.newId())}.tmp`);
    const final = this.files.uri(relativePath);
    // Neither input nor an existing attachment is ever overwritten or removed.
    await this.validate(input.uri, input.contentType);
    if (await this.files.stat(final)) throw new OfflineError('media_exists');
    await this.files.prepareDirectory(directory);
    try {
      await this.files.copy(input.uri, temp);
      const byteLength = await this.validate(temp, input.contentType);
      await this.files.move(temp, final);
      return {
        id,
        ...this.scope,
        relativePath,
        contentType: input.contentType,
        byteLength,
        cloudId: null,
      };
    } finally {
      // A copy may leave a partial temporary file. Cleanup failure must not mask
      // a successful move; startup cleanup handles these unreferenced temp files.
      try {
        if (await this.files.stat(temp)) await this.files.remove(temp);
      } catch {
        /* retain for recovery */
      }
    }
  }
  private checkedPath(media: Media): string {
    if (
      media.ownerId !== this.scope.ownerId ||
      media.farmId !== this.scope.farmId ||
      media.relativePath !== this.path(media.id, media.contentType)
    )
      throw new OfflineError('invalid_media_scope');
    return this.files.uri(media.relativePath);
  }
  async view(media: Media): Promise<string> {
    const uri = this.checkedPath(media);
    if ((await this.files.stat(uri))?.size !== media.byteLength)
      throw new OfflineError('missing_media');
    return uri;
  }
  /** Only for the newly staged, unreferenced attachment after a failed DB commit. */
  async discardUncommitted(media: Media): Promise<void> {
    await this.files.remove(this.checkedPath(media));
  }
  /** Called once at startup, before any saves; only .tmp files can be removed. */
  async recover(now: number): Promise<void> {
    const directory = `${this.scope.ownerId}/${this.scope.farmId}`;
    for (const name of await this.files.temporaryFiles(directory)) {
      if (!/^[0-9a-f-]{36}\.tmp$/.test(name)) continue;
      const uri = this.files.uri(`${directory}/${name}`);
      const stat = await this.files.stat(uri);
      if (
        stat?.modifiedAt !== null &&
        stat?.modifiedAt !== undefined &&
        stat.modifiedAt < now - 86400000
      )
        await this.files.remove(uri);
    }
  }
}
