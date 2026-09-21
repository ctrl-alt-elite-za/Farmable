import { constants } from 'node:fs';
import { copyFile, link, mkdir, open, readdir, stat, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import type { PhotoFiles } from '../photos';

export const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE5sAAAAASUVORK5CYII=',
  'base64',
);
export function diskPhotos(root: string): PhotoFiles {
  return {
    async stat(uri) {
      try {
        const s = await stat(fileURLToPath(uri));
        return { size: s.size, modifiedAt: s.mtimeMs };
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
        throw error;
      }
    },
    async header(uri) {
      const file = await open(fileURLToPath(uri), 'r');
      try {
        const buffer = Buffer.alloc(8);
        await file.read(buffer, 0, 8, 0);
        return buffer;
      } finally {
        await file.close();
      }
    },
    async copy(source, target) {
      await copyFile(fileURLToPath(source), fileURLToPath(target), constants.COPYFILE_EXCL);
    },
    async move(source, target) {
      await link(fileURLToPath(source), fileURLToPath(target));
      await unlink(fileURLToPath(source));
    },
    async remove(uri) {
      await unlink(fileURLToPath(uri));
    },
    async prepareDirectory(path) {
      await mkdir(join(root, path), { recursive: true });
    },
    uri(path) {
      return pathToFileURL(join(root, path)).href;
    },
    async temporaryFiles(path) {
      try {
        return await readdir(join(root, path));
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') return [];
        throw error;
      }
    },
  };
}
