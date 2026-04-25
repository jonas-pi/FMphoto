import { fileIo } from '@kit.CoreFileKit';

const ALBUM_COPY_BUFFER_SIZE = 256 * 1024;

export async function copyGalleryUriContentToAlbumUri(srcUri: string, destUri: string): Promise<boolean> {
  let srcFd = -1;
  let destFd = -1;
  try {
    const srcFile = await fileIo.open(srcUri, fileIo.OpenMode.READ_ONLY);
    srcFd = srcFile.fd;
    const destFile = await fileIo.open(destUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    destFd = destFile.fd;
    const buffer = new ArrayBuffer(ALBUM_COPY_BUFFER_SIZE);
    let readOffset = 0;
    while (true) {
      const readLen = await fileIo.read(srcFd, buffer, {
        offset: readOffset,
        length: ALBUM_COPY_BUFFER_SIZE
      });
      if (readLen <= 0) {
        break;
      }
      await fileIo.write(destFd, buffer, { length: readLen });
      readOffset += readLen;
      if (readLen < ALBUM_COPY_BUFFER_SIZE) {
        break;
      }
    }
    return true;
  } catch (_e) {
    return false;
  } finally {
    if (srcFd >= 0) {
      try {
        await fileIo.close(srcFd);
      } catch (_e) {
      }
    }
    if (destFd >= 0) {
      try {
        await fileIo.close(destFd);
      } catch (_e) {
      }
    }
  }
}
