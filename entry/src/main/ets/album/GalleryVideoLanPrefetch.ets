/**
 * 内网原片边下边播：官方 AVPlayer.dataSrc 从本地文件读，HTTP 只负责往文件里写。
 * 另拉文件尾（moov 常在末尾），避免半成品 mp4 无法 prepare。
 */
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import { isGalleryLanBurstEnabled } from './GalleryPerfProfile';

const DOMAIN: number = 0xFF00;
const TAG: string = 'VideoLanPrefetch';
const PREFETCH_FILE: string = 'gallery_video_lan_cache.bin';
const PREFETCH_MAX_BYTES: number = 2047 * 1024 * 1024;
const PREFETCH_CONNECT_TIMEOUT_MS: number = 15000;
const PREFETCH_READ_TIMEOUT_MS: number = 120000;
const PREFETCH_FLUSH_BYTES: number = 1024 * 1024;
const PREFETCH_TAIL_BYTES: number = 8 * 1024 * 1024;
const PREFETCH_HEAD_MIN_PLAYABLE: number = 64 * 1024;

let prefetchGen: number = 0;
let prefetchUrl: string = '';
let prefetchPath: string = '';
let prefetchWriteFd: number = -1;
let prefetchReadFd: number = -1;
let prefetchHeadBytes: number = 0;
let prefetchTotalBytes: number = -1;
let prefetchComplete: boolean = false;
let prefetchFastStart: boolean = false;
let prefetchTailStart: number = -1;
let prefetchTailBuf: ArrayBuffer | null = null;
let prefetchTailGot: number = 0;
let prefetchHeadReq: http.HttpRequest | null = null;
let prefetchTailReq: http.HttpRequest | null = null;
let playableWaiters: Array<(ok: boolean) => void> = [];

function isHlsUrl(url: string): boolean {
  return url.toLowerCase().indexOf('.m3u8') >= 0;
}

function headerLookup(headers: Object, name: string): string {
  const rec = headers as Record<string, string>;
  const want = name.toLowerCase();
  const keys = Object.keys(rec);
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === want) {
      const v = rec[keys[i]];
      return v !== undefined ? `${v}` : '';
    }
  }
  return '';
}

function parsePositiveInt(text: string): number {
  const n = Number(text.trim());
  if (!Number.isFinite(n) || n <= 0) {
    return -1;
  }
  return Math.floor(n);
}

function parseContentLength(headers: Object): number {
  return parsePositiveInt(headerLookup(headers, 'content-length'));
}

function isPlayableNow(): boolean {
  if (prefetchReadFd < 0 && prefetchHeadBytes < PREFETCH_HEAD_MIN_PLAYABLE) {
    return false;
  }
  if (prefetchHeadBytes < PREFETCH_HEAD_MIN_PLAYABLE && !prefetchComplete) {
    return false;
  }
  if (prefetchFastStart || prefetchComplete) {
    return true;
  }
  const tailNeed = prefetchTailBuf !== null ? prefetchTailBuf.byteLength : 0;
  return tailNeed > 0 && prefetchTailGot >= tailNeed;
}

function notifyPlayableWaiters(ok: boolean): void {
  if (!ok && playableWaiters.length === 0) {
    return;
  }
  if (ok && !isPlayableNow()) {
    return;
  }
  const ws = playableWaiters;
  playableWaiters = [];
  for (let i = 0; i < ws.length; i++) {
    ws[i](ok);
  }
}

function closeFd(fd: number): void {
  if (fd < 0) {
    return;
  }
  try {
    fileIo.closeSync(fd);
  } catch (_e) {
  }
}

function destroyReq(req: http.HttpRequest | null): void {
  if (req === null) {
    return;
  }
  try {
    req.destroy();
  } catch (_e) {
  }
}

export function stopGalleryVideoLanPrefetch(): void {
  prefetchGen++;
  prefetchUrl = '';
  prefetchPath = '';
  prefetchHeadBytes = 0;
  prefetchTotalBytes = -1;
  prefetchComplete = false;
  prefetchFastStart = false;
  prefetchTailStart = -1;
  prefetchTailBuf = null;
  prefetchTailGot = 0;
  notifyPlayableWaiters(false);
  const head = prefetchHeadReq;
  const tail = prefetchTailReq;
  prefetchHeadReq = null;
  prefetchTailReq = null;
  destroyReq(head);
  destroyReq(tail);
  const w = prefetchWriteFd;
  const r = prefetchReadFd;
  prefetchWriteFd = -1;
  prefetchReadFd = -1;
  closeFd(w);
  closeFd(r);
}

export function isGalleryVideoLanPrefetchForUrl(url: string): boolean {
  return prefetchUrl.length > 0 && prefetchUrl === url.trim();
}

export function galleryVideoLanPrefetchFileSize(): number {
  return prefetchTotalBytes > 0 ? prefetchTotalBytes : -1;
}

export function galleryVideoLanPrefetchBufferedMs(durationMs: number): number {
  if (durationMs <= 0) {
    return 0;
  }
  if (prefetchComplete) {
    return durationMs;
  }
  if (prefetchTotalBytes <= 0) {
    return 0;
  }
  const covered = prefetchHeadBytes + prefetchTailGot;
  const ratio = Math.max(0, Math.min(1, covered / prefetchTotalBytes));
  return Math.floor(durationMs * ratio);
}

export function waitGalleryVideoLanPrefetchPlayable(url: string, timeoutMs: number): Promise<boolean> {
  return new Promise<boolean>((resolve: (ok: boolean) => void) => {
    const want = url.trim();
    if (want.length === 0 || prefetchUrl !== want) {
      resolve(false);
      return;
    }
    if (isPlayableNow()) {
      resolve(true);
      return;
    }
    let settled = false;
    const finish = (ok: boolean): void => {
      if (settled) {
        return;
      }
      settled = true;
      resolve(ok);
    };
    const timer = setTimeout((): void => {
      finish(false);
    }, timeoutMs);
    playableWaiters.push((ok: boolean): void => {
      try {
        clearTimeout(timer);
      } catch (_e) {
      }
      finish(ok);
    });
  });
}

/**
 * dataSrc 回调：已缓存返回字节数；尚未下到返回 0；结束 -1；失败 -2。
 */
export function fillGalleryVideoLanPrefetch(buffer: ArrayBuffer, length: number, pos?: number): number {
  try {
    if (length <= 0) {
      return 0;
    }
    const total = prefetchTotalBytes;
    const start = pos !== undefined ? pos : prefetchHeadBytes;
    if (start < 0) {
      return -2;
    }
    if (total > 0 && start >= total) {
      return -1;
    }
    let want = length;
    if (total > 0 && start + want > total) {
      want = total - start;
    }
    if (want <= 0) {
      return -1;
    }
    const tailStart = prefetchTailStart;
    const tailBuf = prefetchTailBuf;
    if (tailBuf !== null && tailStart >= 0 && start >= tailStart && prefetchTailGot > 0) {
      const rel = start - tailStart;
      if (rel >= prefetchTailGot) {
        return prefetchComplete ? -1 : 0;
      }
      const take = Math.min(want, prefetchTailGot - rel);
      const dest = new Uint8Array(buffer);
      dest.set(new Uint8Array(tailBuf, rel, take), 0);
      return take;
    }
    if (start >= prefetchHeadBytes) {
      return prefetchComplete ? -1 : 0;
    }
    const take = Math.min(want, prefetchHeadBytes - start);
    if (prefetchReadFd < 0 || take <= 0) {
      return 0;
    }
    fileIo.lseek(prefetchReadFd, start, fileIo.WhenceType.SEEK_SET);
    return fileIo.readSync(prefetchReadFd, buffer, { length: take });
  } catch (_e) {
    return -2;
  }
}

export function scheduleGalleryVideoLanPrefetch(directUrl: string, cacheDir: string): void {
  const url = directUrl.trim();
  if (!isGalleryLanBurstEnabled() || url.length === 0 || isHlsUrl(url) || cacheDir.length === 0) {
    return;
  }
  // 同一 URL 只要还在写、已有字节或已完成，seek / 重入都不得 stop 后重拉
  if (prefetchUrl === url) {
    const busy = prefetchHeadReq !== null || prefetchTailReq !== null ||
      prefetchWriteFd >= 0 || prefetchHeadBytes > 0 || prefetchComplete;
    if (busy) {
      if (prefetchComplete) {
        notifyPlayableWaiters(true);
      }
      return;
    }
  }
  stopGalleryVideoLanPrefetch();
  prefetchUrl = url;
  prefetchPath = `${cacheDir}/${PREFETCH_FILE}`;
  const gen = prefetchGen;
  void runPrefetch(gen, url, prefetchPath);
}

function ensureReadFd(): void {
  if (prefetchReadFd >= 0 || prefetchPath.length === 0) {
    return;
  }
  try {
    const f = fileIo.openSync(prefetchPath, fileIo.OpenMode.READ_ONLY);
    prefetchReadFd = f.fd;
  } catch (_e) {
  }
}

function scanFastStart(nbytes: number): void {
  if (prefetchFastStart || prefetchReadFd < 0 || nbytes < 32) {
    return;
  }
  const cap = Math.min(nbytes, 2 * 1024 * 1024);
  const buf = new ArrayBuffer(cap);
  let n = 0;
  try {
    fileIo.lseek(prefetchReadFd, 0, fileIo.WhenceType.SEEK_SET);
    n = fileIo.readSync(prefetchReadFd, buf, { length: cap });
  } catch (_e) {
    return;
  }
  if (n < 16) {
    return;
  }
  const view = new DataView(buf);
  let off = 0;
  while (off + 8 <= n) {
    let size = view.getUint32(off);
    const t0 = view.getUint8(off + 4);
    const t1 = view.getUint8(off + 5);
    const t2 = view.getUint8(off + 6);
    const t3 = view.getUint8(off + 7);
    const type = String.fromCharCode(t0, t1, t2, t3);
    if (size === 1) {
      if (off + 16 > n) {
        return;
      }
      const hi = view.getUint32(off + 8);
      const lo = view.getUint32(off + 12);
      if (hi !== 0) {
        return;
      }
      size = lo;
    }
    if (size === 0) {
      size = n - off;
    }
    if (size < 8) {
      return;
    }
    if (type === 'moov') {
      prefetchFastStart = true;
      return;
    }
    if (type === 'mdat') {
      return;
    }
    off += size;
  }
}

function flushHead(acc: ArrayBuffer, accOff: number): boolean {
  if (prefetchWriteFd < 0 || accOff <= 0) {
    return true;
  }
  try {
    const payload = accOff === acc.byteLength ? acc : acc.slice(0, accOff);
    fileIo.writeSync(prefetchWriteFd, payload);
    prefetchHeadBytes += accOff;
    ensureReadFd();
    if (!prefetchFastStart && prefetchHeadBytes >= PREFETCH_HEAD_MIN_PLAYABLE) {
      scanFastStart(prefetchHeadBytes);
    }
    notifyPlayableWaiters(true);
    return true;
  } catch (_e) {
    return false;
  }
}

function appendHeadChunk(chunk: ArrayBuffer, acc: ArrayBuffer, accOffRef: number[]): boolean {
  const tailStart = prefetchTailStart;
  let remain = chunk.byteLength;
  let srcOff = 0;
  const src = new Uint8Array(chunk);
  while (remain > 0) {
    if (tailStart >= 0 && prefetchHeadBytes + accOffRef[0] >= tailStart) {
      return true;
    }
    let room = PREFETCH_FLUSH_BYTES - accOffRef[0];
    if (tailStart >= 0) {
      const beforeTail = tailStart - (prefetchHeadBytes + accOffRef[0]);
      if (beforeTail <= 0) {
        return true;
      }
      room = Math.min(room, beforeTail);
    }
    const take = Math.min(room, remain);
    const dest = new Uint8Array(acc);
    dest.set(src.subarray(srcOff, srcOff + take), accOffRef[0]);
    accOffRef[0] += take;
    srcOff += take;
    remain -= take;
    if (accOffRef[0] < PREFETCH_FLUSH_BYTES && !(tailStart >= 0 &&
      prefetchHeadBytes + accOffRef[0] >= tailStart)) {
      continue;
    }
    if (!flushHead(acc, accOffRef[0])) {
      return false;
    }
    accOffRef[0] = 0;
  }
  return true;
}

function copyHeaders(base: Record<string, string>): Record<string, string> {
  const out: Record<string, string> = {};
  const keys = Object.keys(base);
  for (let i = 0; i < keys.length; i++) {
    out[keys[i]] = base[keys[i]];
  }
  return out;
}

function applyCert(opt: http.HttpRequestOptions, storedBase: string): void {
  const activeBase = fnWebViewBaseUrl(storedBase);
  if (CertPolicy.isTrusted(activeBase)) {
    opt.remoteValidation = 'skip';
  }
}

async function runPrefetch(gen: number, url: string, filePath: string): Promise<void> {
  if (gen !== prefetchGen) {
    return;
  }
  const client = AppSession.getClient();
  const stored = AppSession.getStored();
  if (client === null || stored === null) {
    return;
  }
  try {
    await fileIo.unlink(filePath);
  } catch (_e) {
  }
  let headers: Record<string, string>;
  try {
    headers = await client.getGalleryStreamHeaders(url);
  } catch (_e) {
    return;
  }
  if (gen !== prefetchGen) {
    return;
  }
  try {
    const wf = await fileIo.open(
      filePath,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    prefetchWriteFd = wf.fd;
  } catch (_e) {
    return;
  }
  hilog.info(DOMAIN, TAG, 'lan cache start');
  const headDone = runHeadStream(gen, url, headers, stored.baseUrl);
  await headDone;
}

function maybeStartTail(gen: number, url: string, headers: Record<string, string>, storedBase: string): void {
  if (prefetchTailReq !== null) {
    return;
  }
  if (prefetchTotalBytes < PREFETCH_TAIL_BYTES * 2) {
    return;
  }
  // 先并行拉尾，成功 206 后再截断 head；未确认 Range 时 head 继续写完整文件，避免留下空洞
  const tailStart = prefetchTotalBytes - PREFETCH_TAIL_BYTES;
  void runTailStream(gen, url, headers, storedBase, tailStart);
}

async function runHeadStream(
  gen: number,
  url: string,
  headers: Record<string, string>,
  storedBase: string
): Promise<void> {
  const req = http.createHttp();
  prefetchHeadReq = req;
  const acc = new ArrayBuffer(PREFETCH_FLUSH_BYTES);
  const accOffRef: number[] = [0];
  let writeFailed = false;
  let dataEndResolve: (() => void) | undefined = undefined;
  const dataEndPromise = new Promise<void>((resolve: () => void) => {
    dataEndResolve = resolve;
  });
  const onHeaders = (h: Object): void => {
    if (gen !== prefetchGen) {
      return;
    }
    const len = parseContentLength(h);
    if (len > 0 && prefetchTotalBytes < 0) {
      prefetchTotalBytes = len;
      maybeStartTail(gen, url, headers, storedBase);
    }
  };
  const onData = (chunk: ArrayBuffer): void => {
    if (writeFailed || gen !== prefetchGen || chunk.byteLength === 0) {
      return;
    }
    if (!appendHeadChunk(chunk, acc, accOffRef)) {
      writeFailed = true;
    }
  };
  const onEnd = (): void => {
    if (dataEndResolve !== undefined) {
      dataEndResolve();
    }
  };
  req.on('headersReceive', onHeaders);
  req.on('dataReceive', onData);
  req.on('dataEnd', onEnd);
  try {
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: PREFETCH_CONNECT_TIMEOUT_MS,
      readTimeout: PREFETCH_READ_TIMEOUT_MS,
      maxLimit: PREFETCH_MAX_BYTES
    };
    applyCert(opt, storedBase);
    const code = await req.requestInStream(url, opt);
    if (gen !== prefetchGen) {
      return;
    }
    if (code < 200 || code >= 300) {
      hilog.warn(DOMAIN, TAG, 'lan cache http %{public}d', code);
      return;
    }
    await dataEndPromise;
    if (!writeFailed && accOffRef[0] > 0) {
      flushHead(acc, accOffRef[0]);
      accOffRef[0] = 0;
    }
    if (!writeFailed && gen === prefetchGen) {
      if (prefetchTailStart < 0) {
        prefetchComplete = true;
      } else {
        const tailNeed = prefetchTailBuf !== null ? prefetchTailBuf.byteLength : 0;
        if (prefetchHeadBytes >= prefetchTailStart && prefetchTailGot >= tailNeed && tailNeed > 0) {
          prefetchComplete = true;
        }
      }
      hilog.info(DOMAIN, TAG, 'lan cache head bytes=%{public}s total=%{public}s fast=%{public}s',
        `${prefetchHeadBytes}`, `${prefetchTotalBytes}`, `${prefetchFastStart}`);
      notifyPlayableWaiters(true);
    }
  } catch (_e) {
    if (gen === prefetchGen) {
      hilog.warn(DOMAIN, TAG, 'lan cache head abort');
    }
  } finally {
    try {
      req.off('headersReceive', onHeaders);
      req.off('dataReceive', onData);
      req.off('dataEnd', onEnd);
    } catch (_e) {
    }
    if (prefetchHeadReq === req) {
      prefetchHeadReq = null;
    }
    destroyReq(req);
  }
}

function appendTailChunk(chunk: ArrayBuffer): void {
  const tailBuf = prefetchTailBuf;
  if (tailBuf === null || chunk.byteLength === 0) {
    return;
  }
  const room = tailBuf.byteLength - prefetchTailGot;
  if (room <= 0) {
    return;
  }
  const take = Math.min(room, chunk.byteLength);
  new Uint8Array(tailBuf).set(new Uint8Array(chunk, 0, take), prefetchTailGot);
  prefetchTailGot += take;
  notifyPlayableWaiters(true);
}

async function runTailStream(
  gen: number,
  url: string,
  headers: Record<string, string>,
  storedBase: string,
  tailStart: number
): Promise<void> {
  const req = http.createHttp();
  prefetchTailReq = req;
  const h = copyHeaders(headers);
  h['Range'] = `bytes=${tailStart}-`;
  const pending: ArrayBuffer[] = [];
  let dataEndResolve: (() => void) | undefined = undefined;
  const dataEndPromise = new Promise<void>((resolve: () => void) => {
    dataEndResolve = resolve;
  });
  const onData = (chunk: ArrayBuffer): void => {
    if (gen !== prefetchGen || chunk.byteLength === 0) {
      return;
    }
    if (prefetchTailBuf !== null) {
      appendTailChunk(chunk);
      return;
    }
    pending.push(chunk);
  };
  const onEnd = (): void => {
    if (dataEndResolve !== undefined) {
      dataEndResolve();
    }
  };
  req.on('dataReceive', onData);
  req.on('dataEnd', onEnd);
  try {
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: h,
      connectTimeout: PREFETCH_CONNECT_TIMEOUT_MS,
      readTimeout: PREFETCH_READ_TIMEOUT_MS,
      maxLimit: PREFETCH_TAIL_BYTES + 1024
    };
    applyCert(opt, storedBase);
    const code = await req.requestInStream(url, opt);
    if (gen !== prefetchGen) {
      return;
    }
    // 只认 206。忽略 Range 的 200 会把文件头当成 moov
    if (code !== 206) {
      hilog.warn(DOMAIN, TAG, 'lan cache tail http %{public}d', code);
      return;
    }
    if (prefetchTailBuf === null) {
      prefetchTailStart = tailStart;
      prefetchTailBuf = new ArrayBuffer(PREFETCH_TAIL_BYTES);
    }
    for (let i = 0; i < pending.length; i++) {
      appendTailChunk(pending[i]);
    }
    await dataEndPromise;
    if (gen === prefetchGen) {
      hilog.info(DOMAIN, TAG, 'lan cache tail bytes=%{public}s', `${prefetchTailGot}`);
      notifyPlayableWaiters(true);
    }
  } catch (_e) {
    if (gen === prefetchGen) {
      hilog.warn(DOMAIN, TAG, 'lan cache tail abort');
      prefetchTailStart = -1;
      prefetchTailBuf = null;
      prefetchTailGot = 0;
    }
  } finally {
    try {
      req.off('dataReceive', onData);
      req.off('dataEnd', onEnd);
    } catch (_e) {
    }
    if (prefetchTailReq === req) {
      prefetchTailReq = null;
    }
    destroyReq(req);
  }
}
