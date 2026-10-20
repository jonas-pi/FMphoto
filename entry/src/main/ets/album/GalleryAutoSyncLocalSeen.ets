/**
 * 本机已见照片快照。
 * 第一次扫描只记下当前图库，不上传（官方客户端往往已经传过）。
 * 之后只有新增或改过的照片才拿去和 NAS 去重。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSeen';
const SEEN_FILE = 'auto_sync_local_seen_v1.txt';

export class LocalSeenDiff {
  /** 还没有快照：本次只建立基线，added 为空。 */
  freshBaseline: boolean = false;
  added: LocalPhotoEntry[] = [];
  baselineCount: number = 0;
}

function seenKey(photo: LocalPhotoEntry): string {
  const size = Number.isFinite(photo.fileSize) ? Math.floor(photo.fileSize) : 0;
  const mtime = Number.isFinite(photo.dateModifiedMs) ? Math.floor(photo.dateModifiedMs) : 0;
  return `${encodeURIComponent(photo.uri)}\t${size}\t${mtime}`;
}

export class GalleryAutoSyncLocalSeen {
  private static filePath(ctx: common.UIAbilityContext): string {
    return `${ctx.filesDir}/${SEEN_FILE}`;
  }

  private static async readKeys(ctx: common.UIAbilityContext): Promise<Set<string> | null> {
    try {
      const text = await fileIo.readText(GalleryAutoSyncLocalSeen.filePath(ctx));
      const lines = text.split('\n');
      if (lines.length === 0 || lines[0].trim() !== 'v1') {
        return null;
      }
      const keys = new Set<string>();
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line.length > 0) {
          keys.add(line);
        }
      }
      return keys;
    } catch (_e) {
      return null;
    }
  }

  private static async writeKeys(ctx: common.UIAbilityContext, keys: Set<string>): Promise<void> {
    const lines: string[] = ['v1'];
    keys.forEach((key: string): void => {
      lines.push(key);
    });
    const file = await fileIo.open(
      GalleryAutoSyncLocalSeen.filePath(ctx),
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await fileIo.write(file.fd, lines.join('\n'));
    } finally {
      await fileIo.close(file.fd);
    }
  }

  static async diff(ctx: common.UIAbilityContext, photos: LocalPhotoEntry[]): Promise<LocalSeenDiff> {
    const result = new LocalSeenDiff();
    const known = await GalleryAutoSyncLocalSeen.readKeys(ctx);
    if (known === null) {
      const keys = new Set<string>();
      for (let i = 0; i < photos.length; i++) {
        if (photos[i].uri.length > 0) {
          keys.add(seenKey(photos[i]));
        }
      }
      await GalleryAutoSyncLocalSeen.writeKeys(ctx, keys);
      result.freshBaseline = true;
      result.baselineCount = keys.size;
      hilog.info(DOMAIN, TAG, 'baseline count=%{public}d', keys.size);
      return result;
    }
    const added: LocalPhotoEntry[] = [];
    for (let i = 0; i < photos.length; i++) {
      const photo = photos[i];
      if (photo.uri.length === 0) {
        continue;
      }
      if (!known.has(seenKey(photo))) {
        added.push(photo);
      }
    }
    result.added = added;
    result.baselineCount = known.size;
    hilog.info(DOMAIN, TAG, 'seen=%{public}d added=%{public}d', known.size, added.length);
    return result;
  }

  static async remember(ctx: common.UIAbilityContext, photos: LocalPhotoEntry[]): Promise<void> {
    if (photos.length === 0) {
      return;
    }
    let known = await GalleryAutoSyncLocalSeen.readKeys(ctx);
    if (known === null) {
      known = new Set<string>();
    }
    let changed = false;
    for (let i = 0; i < photos.length; i++) {
      if (photos[i].uri.length === 0) {
        continue;
      }
      const key = seenKey(photos[i]);
      if (!known.has(key)) {
        known.add(key);
        changed = true;
      }
    }
    if (changed) {
      await GalleryAutoSyncLocalSeen.writeKeys(ctx, known);
    }
  }
}
