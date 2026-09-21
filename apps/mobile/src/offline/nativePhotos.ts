import { Directory, File, FileMode, Paths } from 'expo-file-system';
import type { PhotoFiles } from './photos';
import { OfflineError } from './types';

export function nativePhotoFiles(
  rootName: 'offline-media' | 'offline-probe-media' = 'offline-media',
): PhotoFiles {
  const root = new Directory(Paths.document, rootName);
  function relative(value: string) {
    if (!/^[0-9a-f-]{36}\/[0-9a-f-]{36}(\/[0-9a-f-]{36}\.(png|jpg|tmp))?$/.test(value))
      throw new OfflineError('invalid_media_path');
    return value;
  }
  return {
    async stat(uri) {
      const file = new File(uri);
      return file.exists ? { size: file.size, modifiedAt: file.lastModified } : null;
    },
    async header(uri) {
      const handle = new File(uri).open(FileMode.ReadOnly);
      try {
        return handle.readBytes(8);
      } finally {
        handle.close();
      }
    },
    async copy(source, destination) {
      await new File(source).copy(new File(destination), { overwrite: false });
    },
    async move(source, destination) {
      await new File(source).move(new File(destination), { overwrite: false });
    },
    async remove(uri) {
      if (!uri.startsWith(root.uri.endsWith('/') ? root.uri : `${root.uri}/`))
        throw new OfflineError('invalid_media_path');
      new File(uri).delete();
    },
    async prepareDirectory(path) {
      new Directory(root, relative(path)).create({ intermediates: true, idempotent: true });
    },
    uri: (path) => new File(root, relative(path)).uri,
    async temporaryFiles(path) {
      const directory = new Directory(root, relative(path));
      return directory.exists
        ? directory
            .list()
            .filter((item) => item instanceof File && item.name.endsWith('.tmp'))
            .map((item) => item.name)
        : [];
    },
  };
}
