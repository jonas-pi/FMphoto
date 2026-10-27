/**
 * 本机同步账本：记录本机媒体是否已经在当前账号的这台 NAS。
 * 键是 uri + 大小 + 修改时间。大小和修改时间没变就直接跳过，不再读文件。
 * 文件按账号和 NAS 分开，退出登录不删除，同一账号再进来还能接着用。
 * 不保存 NAS 全库索引。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { fnDiagError, fnDiagRecord } from '../common/FnDiagLog';
import { dropUnscopedSyncFiles, gallerySyncScopeToken } from './GalleryAutoSyncScope';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

const TAG = 'AutoSyncLedger';

export class LedgerPut {
  uri: string = '';
  size: number = 0;
  mtimeMs: number = 0;
  role: string = 'file';
}

class LedgerRow {
  uri: string = '';
  size: number = 0;
  mtimeMs: number = 0;
  fileConfirmed: boolean = false;
  coverConfirmed: boolean = false;
  videoConfirmed: boolean = false;
  liveConfirmed: boolean = false;
}

export class GalleryAutoSyncLedger {
  private static rows: Map<string, LedgerRow> | null = null;
  /** rows 属于哪一份账本。换账号或换 NAS 后必须重读，不能沿用内存里的上一份。 */
  private static loadedScope: string = '';
  private static tail: Promise<void> = Promise.resolve();

  static invalidate(): void {
    GalleryAutoSyncLedger.rows = null;
    GalleryAutoSyncLedger.loadedScope = '';
  }

  static isSettled(uri: string, size: number, mtimeMs: number): boolean {
    const row = GalleryAutoSyncLedger.rowOf(uri, size, mtimeMs);
    if (row === null) {
      return false;
    }
    if (row.fileConfirmed) {
      return true;
    }
    return row.coverConfirmed && row.videoConfirmed;
  }

  /** 实况账本按 URI 记录，不使用封面大小。 */
  static isLiveSettled(uri: string): boolean {
    if (GalleryAutoSyncLedger.rows === null || uri.length === 0) {
      return false;
    }
    const row = GalleryAutoSyncLedger.rows.get(GalleryAutoSyncLedger.liveKey(uri));
    if (row === undefined) {
      return false;
    }
    return row.liveConfirmed;
  }

  /** 兼容旧调用。传入的集合不再使用，以本机账本文件为准。 */
  static hasEntry(_ledger: Set<string>, entry: LocalPhotoEntry): boolean {
    return GalleryAutoSyncLedger.isSettled(entry.uri, entry.fileSize, entry.dateModifiedMs);
  }

  static async load(ctx: common.UIAbilityContext): Promise<void> {
    const scope = gallerySyncScopeToken();
    if (GalleryAutoSyncLedger.rows !== null && GalleryAutoSyncLedger.loadedScope === scope) {
      return;
    }
    await dropUnscopedSyncFiles(ctx);
    const rows = new Map<string, LedgerRow>();
    try {
      const text = await fileIo.readText(GalleryAutoSyncLedger.filePath(ctx, scope));
      GalleryAutoSyncLedger.parseInto(text, rows);
    } catch (e) {
      // 账本读不出来时所有条目都会被当成未同步，重复上传。
      fnDiagError(TAG, 'ledger load failed', e);
    }
    GalleryAutoSyncLedger.rows = rows;
    GalleryAutoSyncLedger.loadedScope = scope;
  }

  static remember(ctx: common.UIAbilityContext, put: LedgerPut): Promise<void> {
    const batch: LedgerPut[] = [put];
    return GalleryAutoSyncLedger.rememberMany(ctx, batch);
  }

  static rememberMany(ctx: common.UIAbilityContext, puts: LedgerPut[]): Promise<void> {
    const run = GalleryAutoSyncLedger.tail.then((): Promise<void> => {
      return GalleryAutoSyncLedger.rememberManyBody(ctx, puts);
    });
    GalleryAutoSyncLedger.tail = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  /**
   * 只清当前账号这份账本。退出登录不要调用：换回去还要用。
   * 全库扫描发现本机已经没有的照片，用 pruneAbsent。
   */
  static async clear(ctx: common.UIAbilityContext): Promise<void> {
    const scope = gallerySyncScopeToken();
    GalleryAutoSyncLedger.rows = new Map<string, LedgerRow>();
    GalleryAutoSyncLedger.loadedScope = scope;
    await GalleryAutoSyncLedger.deleteFile(GalleryAutoSyncLedger.filePath(ctx, scope));
  }

  /**
   * 丢掉 URI 已经不在本机图库里的行。只在扫过全部相册之后调用。
   * 只扫部分备份源时不能调用，那些没扫到的照片还在手机上。
   */
  static pruneAbsent(ctx: common.UIAbilityContext, liveUris: Set<string>): Promise<void> {
    const run = GalleryAutoSyncLedger.tail.then((): Promise<void> => {
      return GalleryAutoSyncLedger.pruneAbsentBody(ctx, liveUris);
    });
    GalleryAutoSyncLedger.tail = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  private static async pruneAbsentBody(ctx: common.UIAbilityContext, liveUris: Set<string>): Promise<void> {
    await GalleryAutoSyncLedger.load(ctx);
    const rows = GalleryAutoSyncLedger.rows;
    if (rows === null || rows.size === 0) {
      return;
    }
    const kept = new Map<string, LedgerRow>();
    let dropped = 0;
    rows.forEach((row: LedgerRow, key: string): void => {
      if (liveUris.has(row.uri)) {
        kept.set(key, row);
      } else {
        dropped++;
      }
    });
    if (dropped === 0) {
      return;
    }
    GalleryAutoSyncLedger.rows = kept;
    await GalleryAutoSyncLedger.persist(ctx);
    fnDiagRecord('I', TAG, `ledger prune dropped=${dropped} kept=${kept.size}`);
  }

  private static async rememberManyBody(ctx: common.UIAbilityContext, puts: LedgerPut[]): Promise<void> {
    await GalleryAutoSyncLedger.load(ctx);
    if (puts.length === 0 || GalleryAutoSyncLedger.rows === null) {
      return;
    }
    for (let i = 0; i < puts.length; i++) {
      GalleryAutoSyncLedger.applyPut(puts[i]);
    }
    await GalleryAutoSyncLedger.persist(ctx);
  }

  private static applyPut(put: LedgerPut): void {
    if (GalleryAutoSyncLedger.rows === null) {
      return;
    }
    GalleryAutoSyncLedger.applyPutTo(GalleryAutoSyncLedger.rows, put);
  }

  private static rowOf(uri: string, size: number, mtimeMs: number): LedgerRow | null {
    if (GalleryAutoSyncLedger.rows === null) {
      return null;
    }
    const row = GalleryAutoSyncLedger.rows.get(GalleryAutoSyncLedger.rowKey(uri, size, mtimeMs));
    return row === undefined ? null : row;
  }

  private static rowKey(uri: string, size: number, mtimeMs: number): string {
    return `${size}\t${mtimeMs}\t${uri}`;
  }

  private static liveKey(uri: string): string {
    return `0\t0\t${uri}`;
  }

  private static filePath(ctx: common.UIAbilityContext, scope: string): string {
    return `${ctx.filesDir}/auto_sync_ledger_v4_${scope}.txt`;
  }

  private static parseInto(text: string, rows: Map<string, LedgerRow>): void {
    const lines = text.split('\n');
    if (lines.length === 0 || lines[0].trim() !== 'v3') {
      return;
    }
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i];
      if (line.length === 0) {
        continue;
      }
      const parts = line.split('\t');
      if (parts.length < 5) {
        continue;
      }
      let uri = '';
      try {
        uri = decodeURIComponent(parts[0]);
      } catch (_e) {
        continue;
      }
      const size = Number(parts[1]);
      const mtimeMs = Number(parts[2]);
      const role = parts[3];
      const marker = parts[4].trim();
      if (uri.length === 0 || !Number.isFinite(size) || marker.length === 0) {
        continue;
      }
      if (size <= 0 && role !== 'live') {
        continue;
      }
      const put = new LedgerPut();
      put.uri = uri;
      put.size = Math.floor(size);
      put.mtimeMs = Number.isFinite(mtimeMs) ? Math.floor(mtimeMs) : 0;
      put.role = role;
      GalleryAutoSyncLedger.applyPutTo(rows, put);
    }
  }

  private static applyPutTo(rows: Map<string, LedgerRow>, put: LedgerPut): void {
    if (put.uri.length === 0) {
      return;
    }
    if (put.role !== 'live' && put.size <= 0) {
      return;
    }
    const key = put.role === 'live'
      ? GalleryAutoSyncLedger.liveKey(put.uri)
      : GalleryAutoSyncLedger.rowKey(put.uri, put.size, put.mtimeMs);
    let row = rows.get(key);
    if (row === undefined) {
      row = new LedgerRow();
      row.uri = put.uri;
      row.size = put.size;
      row.mtimeMs = put.mtimeMs;
      rows.set(key, row);
    }
    if (put.role === 'live') {
      row.size = 0;
      row.mtimeMs = 0;
      row.fileConfirmed = false;
      row.coverConfirmed = false;
      row.videoConfirmed = false;
      row.liveConfirmed = true;
      return;
    }
    if (put.role === 'cover') {
      row.fileConfirmed = false;
      row.coverConfirmed = true;
      return;
    }
    if (put.role === 'video') {
      row.fileConfirmed = false;
      row.videoConfirmed = true;
      return;
    }
    row.coverConfirmed = false;
    row.videoConfirmed = false;
    row.fileConfirmed = true;
  }

  private static async persist(ctx: common.UIAbilityContext): Promise<void> {
    const rows = GalleryAutoSyncLedger.rows;
    if (rows === null) {
      return;
    }
    const lines: string[] = ['v3'];
    rows.forEach((row: LedgerRow): void => {
      const enc = encodeURIComponent(row.uri);
      if (row.fileConfirmed) {
        lines.push(`${enc}\t${row.size}\t${row.mtimeMs}\tfile\t1`);
      }
      if (row.coverConfirmed) {
        lines.push(`${enc}\t${row.size}\t${row.mtimeMs}\tcover\t1`);
      }
      if (row.videoConfirmed) {
        lines.push(`${enc}\t${row.size}\t${row.mtimeMs}\tvideo\t1`);
      }
      if (row.liveConfirmed) {
        lines.push(`${enc}\t0\t0\tlive\t1`);
      }
    });
    const path = GalleryAutoSyncLedger.filePath(ctx, GalleryAutoSyncLedger.loadedScope);
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, lines.join('\n'));
    } finally {
      await fileIo.close(file.fd);
    }
  }

  private static async deleteFile(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_e) {
    }
  }
}
