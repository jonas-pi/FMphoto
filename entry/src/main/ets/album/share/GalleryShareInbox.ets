/**
 * 系统分享入站：解析 Want 中的媒体 URI，暂存待上传列表。
 */
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';

const DOMAIN: number = 0xFF00;
const TAG: string = 'ShareInbox';
const SEND_DATA_ACTION: string = 'ohos.want.action.sendData';
/** 官方 WantConstant.PARAMS_STREAM */
const PARAMS_STREAM_KEY: string = 'ability.params.stream';

export const FN_SHARE_INBOX_VERSION_KEY: string = 'FN_SHARE_INBOX_VERSION';

export class GalleryShareInbox {
  private static pending: string[] = [];
  private static loginHintShown: boolean = false;
  private static confirming: boolean = false;

  static ensureStorage(): void {
    AppStorage.setOrCreate<number>(FN_SHARE_INBOX_VERSION_KEY, 0);
  }

  static peekCount(): number {
    return GalleryShareInbox.pending.length;
  }

  static isConfirming(): boolean {
    return GalleryShareInbox.confirming;
  }

  static beginConfirm(): void {
    GalleryShareInbox.confirming = true;
  }

  static endConfirm(): void {
    GalleryShareInbox.confirming = false;
  }

  static shouldShowLoginHint(): boolean {
    if (GalleryShareInbox.pending.length === 0 || GalleryShareInbox.loginHintShown) {
      return false;
    }
    GalleryShareInbox.loginHintShown = true;
    return true;
  }

  static enqueue(uris: string[]): void {
    if (uris.length === 0) {
      return;
    }
    const merged = uniqueUris(GalleryShareInbox.pending.concat(uris));
    GalleryShareInbox.pending = merged;
    bumpShareInboxVersion();
  }

  static takeAll(): string[] {
    const out = GalleryShareInbox.pending.slice();
    GalleryShareInbox.pending = [];
    if (out.length > 0) {
      bumpShareInboxVersion();
    }
    return out;
  }

  /** 冷启动 onCreate / 热启动 onNewWant 解析分享 Want */
  static async ingestWant(want: Want): Promise<number> {
    const uris = await collectShareMediaUris(want);
    if (uris.length === 0) {
      return 0;
    }
    GalleryShareInbox.loginHintShown = false;
    GalleryShareInbox.enqueue(uris);
    hilog.info(DOMAIN, TAG, 'ingest share uris=%{public}d', uris.length);
    return uris.length;
  }
}

function bumpShareInboxVersion(): void {
  const old = AppStorage.get<number>(FN_SHARE_INBOX_VERSION_KEY) ?? 0;
  AppStorage.setOrCreate<number>(FN_SHARE_INBOX_VERSION_KEY, old + 1);
}

async function collectShareMediaUris(want: Want): Promise<string[]> {
  const collected: string[] = [];
  pushIfFileUri(collected, want.uri);
  pushUriList(collected, readStreamParam(want));
  if (!looksLikeShareWant(want, collected.length > 0)) {
    return [];
  }
  try {
    const data = await systemShare.getSharedData(want);
    const records = data.getRecords();
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      const utd = record.utd ?? '';
      if (!isAcceptableShareUtd(utd)) {
        continue;
      }
      pushIfFileUri(collected, record.uri);
    }
  } catch (_e) {
  }
  return uniqueUris(collected);
}

function looksLikeShareWant(want: Want, alreadyHasUri: boolean): boolean {
  const action = want.action ?? '';
  if (action === SEND_DATA_ACTION) {
    return true;
  }
  return alreadyHasUri;
}

function readStreamParam(want: Want): string[] {
  const params = want.parameters;
  if (params === undefined) {
    return [];
  }
  return normalizeUriList(params[PARAMS_STREAM_KEY]);
}

function normalizeUriList(raw: Object | undefined): string[] {
  if (raw === undefined) {
    return [];
  }
  if (typeof raw === 'string') {
    const one = (raw as string).trim();
    return one.length > 0 ? [one] : [];
  }
  const list = raw as string[];
  if (list === undefined || list.length === undefined) {
    return [];
  }
  const out: string[] = [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (typeof item === 'string') {
      const s = item.trim();
      if (s.length > 0) {
        out.push(s);
      }
    }
  }
  return out;
}

function pushUriList(target: string[], uris: string[]): void {
  for (let i = 0; i < uris.length; i++) {
    pushIfFileUri(target, uris[i]);
  }
}

function pushIfFileUri(target: string[], uri: string | undefined): void {
  if (uri === undefined) {
    return;
  }
  const trimmed = uri.trim();
  if (!isLikelyFileUri(trimmed)) {
    return;
  }
  target.push(trimmed);
}

function isLikelyFileUri(uri: string): boolean {
  return uri.startsWith('file://') || uri.startsWith('content://') ||
    uri.startsWith('datashare://') || uri.startsWith('fd://');
}

function isAcceptableShareUtd(utd: string): boolean {
  if (utd.length === 0) {
    return true;
  }
  if (utd === 'general.text' || utd === 'general.plain-text' ||
    utd === 'general.hyperlink' || utd === 'general.html') {
    return false;
  }
  return utd.indexOf('image') >= 0 || utd.indexOf('video') >= 0 ||
    utd.indexOf('media') >= 0 || utd === 'general.file-uri' ||
    utd === 'general.file' || utd === 'general.object';
}

function uniqueUris(uris: string[]): string[] {
  const seen: Record<string, boolean> = {};
  const out: string[] = [];
  for (let i = 0; i < uris.length; i++) {
    const uri = uris[i];
    if (seen[uri] === true) {
      continue;
    }
    seen[uri] = true;
    out.push(uri);
  }
  return out;
}
