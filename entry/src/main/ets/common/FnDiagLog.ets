/**
 * 本机诊断日志：订阅系统崩溃 / 卡死，并记录播放失败等关键路径。
 * 不上传；用户在「我的」或登录页导出后自行发给开发者。
 * 每次进程启动清空运行记录；崩溃文件保留，便于闪退后再次打开再导出。
 */
import { bundleManager, common, errorManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';

const DOMAIN: number = 0xFF00;
const TAG: string = 'FnDiag';
const DIR_NAME: string = 'diag';
const RUNTIME_NAME: string = 'runtime.log';
const RUNTIME_PREV_NAME: string = 'runtime.prev.log';
const EXPORT_NAME: string = 'fmphoto-diag.txt';
const MAX_RUNTIME_BYTES: number = 256 * 1024;
const MAX_RING: number = 400;
const MAX_CRASH_FILES: number = 4;
const MAX_SECTION_CHARS: number = 180000;

let filesRoot: string = '';
let cacheRoot: string = '';
let dirReady: boolean = false;
let watcherInstalled: boolean = false;
const ring: string[] = [];
let appendChain: Promise<void> = Promise.resolve();

export function fnDiagInit(filesDir: string, cacheDir: string = ''): void {
  const files = trimPath(filesDir);
  if (files.length === 0) {
    return;
  }
  filesRoot = files;
  const cache = trimPath(cacheDir);
  if (cache.length > 0) {
    cacheRoot = cache;
  }
  dirReady = false;
  ring.splice(0, ring.length);
  appendChain = Promise.resolve();
  resetRuntimeLogSync();
  fnDiagRecord('I', TAG, 'session start');
  fnDiagInstallCrashWatcher();
  fnDiagInstallErrorObservers();
}

export function fnDiagRecord(level: string, tag: string, message: string): void {
  const line = `${formatStamp(Date.now())} ${level} [${tag}] ${sanitizeDiagText(message)}`;
  pushRing(line);
  enqueueAppend(line + '\n');
}

/** 卡死回调里必须同步落盘，进程随后可能被系统杀掉。 */
export function fnDiagRecordSync(level: string, tag: string, message: string): void {
  const line = `${formatStamp(Date.now())} ${level} [${tag}] ${sanitizeDiagText(message)}`;
  pushRing(line);
  appendRuntimeSync(line + '\n');
}

export async function fnDiagShare(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    bindShareRoots(ctx);
    const path = await buildExportFile();
    if (path.length === 0) {
      hilog.error(DOMAIN, TAG, 'diag export wrote empty path');
      return false;
    }
    const shareUri = fileUri.getUriFromPath(path);
    const record: systemShare.SharedRecord = {
      utd: 'general.plain-text',
      uri: shareUri,
      title: '飞马相册诊断日志'
    };
    const shareData = new systemShare.SharedData(record);
    const ctrl = new systemShare.ShareController(shareData);
    try {
      await ctrl.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (_detail) {
      await ctrl.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    }
    return true;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'diag share failed: %{public}s', String(e));
    fnDiagRecord('E', TAG, `share failed ${String(e)}`);
    return false;
  }
}

function fnDiagInstallCrashWatcher(): void {
  if (watcherInstalled) {
    return;
  }
  watcherInstalled = true;
  const watcher: hiAppEvent.Watcher = {
    name: 'fmphotoCrashWatcher',
    appEventFilters: [
      {
        domain: hiAppEvent.domain.OS,
        names: [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE]
      }
    ],
    onReceive: (_domain: string, groups: Array<hiAppEvent.AppEventGroup>): void => {
      for (let gi = 0; gi < groups.length; gi++) {
        const group = groups[gi];
        for (let ei = 0; ei < group.appEventInfos.length; ei++) {
          const info = group.appEventInfos[ei];
          void persistSystemEvent(info.name, info.params as Record<string, Object>);
        }
      }
    }
  };
  try {
    hiAppEvent.addWatcher(watcher);
    fnDiagRecord('I', TAG, 'crash watcher ready');
  } catch (e) {
    fnDiagRecord('W', TAG, `crash watcher failed ${String(e)}`);
  }
}

let errorObserversInstalled: boolean = false;

function fnDiagInstallErrorObservers(): void {
  if (errorObserversInstalled) {
    return;
  }
  errorObserversInstalled = true;
  try {
    errorManager.on('globalUnhandledRejectionDetected', (err: errorManager.GlobalError): void => {
      const stack = err.stack !== undefined ? err.stack : '';
      fnDiagRecord('E', 'Promise', `${err.name}: ${err.message} ${stack}`);
    });
  } catch (e) {
    fnDiagRecord('W', TAG, `promise observer failed ${String(e)}`);
  }
  try {
    errorManager.on('freeze', (): void => {
      fnDiagRecordSync('E', 'AppFreeze', 'main thread freeze');
    });
  } catch (e) {
    fnDiagRecord('W', TAG, `freeze observer failed ${String(e)}`);
  }
}

async function persistSystemEvent(eventName: string, params: Record<string, Object>): Promise<void> {
  const crashType = paramText(params, 'crash_type');
  const timeText = paramText(params, 'time');
  const exceptionText = paramText(params, 'exception');
  const parts: string[] = [];
  parts.push(`event=${eventName}`);
  parts.push(`crash_type=${crashType}`);
  parts.push(`time=${timeText}`);
  parts.push(`foreground=${paramText(params, 'foreground')}`);
  parts.push(`bundle_version=${paramText(params, 'bundle_version')}`);
  parts.push(`pid=${paramText(params, 'pid')}`);
  parts.push(`process_life_time=${paramText(params, 'process_life_time')}`);
  parts.push(`exception=${exceptionText}`);
  parts.push(`memory=${paramText(params, 'memory')}`);
  const hilogText = paramText(params, 'hilog');
  if (hilogText.length > 0) {
    parts.push('--- hilog ---');
    parts.push(hilogText);
  }
  const extLogs = paramStringList(params, 'external_log');
  for (let i = 0; i < extLogs.length; i++) {
    const p = extLogs[i];
    parts.push(`--- external_log ${p} ---`);
    parts.push(await readFileCapped(p, MAX_SECTION_CHARS));
  }
  const body = sanitizeDiagText(parts.join('\n'));
  const safeType = (crashType.length > 0 ? crashType : eventName).replace(/[^A-Za-z0-9_-]/g, '_');
  const fileName = `crash-${timeText.length > 0 ? timeText : `${Date.now()}`}-${safeType}.log`;
  await ensureDir();
  await writeUtf8File(`${diagDir()}/${fileName}`, body);
  await pruneCrashFiles();
  fnDiagRecord('E', TAG, `${eventName} ${safeType} ${clip(exceptionText, 240)}`);
}

function enqueueAppend(chunk: string): void {
  appendChain = appendChain.then((): Promise<void> => {
    return appendRuntime(chunk);
  }).catch((_e: Error): void => {
  });
}

/** 进程启动时丢掉上一轮运行记录，导出只含本次会话。崩溃文件仍保留。 */
function resetRuntimeLogSync(): void {
  if (!ensureDirSync()) {
    return;
  }
  try {
    fileIo.unlink(`${diagDir()}/${RUNTIME_NAME}`);
  } catch (_e) {
  }
}

async function appendRuntime(chunk: string): Promise<void> {
  if (!(await ensureDir())) {
    return;
  }
  const path = `${diagDir()}/${RUNTIME_NAME}`;
  try {
    const st = await fileIo.stat(path);
    if (Number(st.size) > MAX_RUNTIME_BYTES) {
      const prev = `${diagDir()}/${RUNTIME_PREV_NAME}`;
      try {
        await fileIo.unlink(prev);
      } catch (_e) {
      }
      await fileIo.rename(path, prev);
    }
  } catch (_e) {
  }
  const f = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
  try {
    await fileIo.write(f.fd, chunk);
  } finally {
    await fileIo.close(f.fd);
  }
}

function appendRuntimeSync(chunk: string): void {
  if (!ensureDirSync()) {
    return;
  }
  const path = `${diagDir()}/${RUNTIME_NAME}`;
  try {
    const f = fileIo.openSync(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
    try {
      fileIo.writeSync(f.fd, chunk);
    } finally {
      fileIo.closeSync(f.fd);
    }
  } catch (_e) {
  }
}

function ensureDirSync(): boolean {
  if (filesRoot.length === 0) {
    return false;
  }
  if (dirReady) {
    return true;
  }
  const dir = diagDir();
  try {
    fileIo.mkdirSync(dir);
  } catch (_e) {
  }
  try {
    const probe = `${dir}/.keep`;
    const f = fileIo.openSync(probe, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
    fileIo.closeSync(f.fd);
    dirReady = true;
    return true;
  } catch (_e) {
    return false;
  }
}

async function buildExportFile(): Promise<string> {
  const outDir = exportDir();
  if (outDir.length === 0) {
    return '';
  }
  const blocks: string[] = [];
  blocks.push('=== 飞马相册诊断日志 ===');
  blocks.push(await buildHeader());
  blocks.push('');
  blocks.push('--- 崩溃 / 卡死 ---');
  const crashBody = await collectCrashFiles();
  blocks.push(crashBody.length > 0 ? crashBody : '(无。若刚才闪退，请打开应用后再导出一次。)');
  blocks.push('');
  blocks.push('--- 运行记录 ---');
  const cur = await readFileCapped(`${diagDir()}/${RUNTIME_NAME}`, MAX_SECTION_CHARS);
  if (cur.length > 0) {
    blocks.push(cur);
  } else if (ring.length > 0) {
    blocks.push(ring.join('\n'));
  } else {
    blocks.push('(暂无运行记录，请先复现问题再导出。)');
  }
  const outPath = `${outDir}/${EXPORT_NAME}`;
  await writeUtf8File(outPath, blocks.join('\n'));
  return outPath;
}

async function buildHeader(): Promise<string> {
  const lines: string[] = [];
  lines.push(`exported_at=${formatStamp(Date.now())}`);
  try {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    lines.push(`app=${info.versionName} (${info.versionCode})`);
    lines.push(`bundle=${info.name}`);
  } catch (_e) {
    lines.push('app=unknown');
  }
  try {
    lines.push(`sdkApi=${deviceInfo.sdkApiVersion}`);
  } catch (_e) {
    lines.push('sdkApi=');
  }
  try {
    lines.push(`os=${deviceInfo.displayVersion} / ${deviceInfo.osFullName}`);
  } catch (_e) {
    lines.push('os=');
  }
  try {
    lines.push(`device=${deviceInfo.marketName} / ${deviceInfo.productModel}`);
  } catch (_e) {
    lines.push('device=');
  }
  try {
    lines.push(`deviceType=${deviceInfo.deviceType}`);
  } catch (_e) {
    lines.push('deviceType=');
  }
  return lines.join('\n');
}

async function collectCrashFiles(): Promise<string> {
  const names = await listCrashNames();
  if (names.length === 0) {
    return '';
  }
  const chunks: string[] = [];
  for (let i = 0; i < names.length; i++) {
    const name = names[i];
    chunks.push(`==== ${name} ====`);
    chunks.push(await readFileCapped(`${diagDir()}/${name}`, MAX_SECTION_CHARS));
  }
  return chunks.join('\n');
}

async function pruneCrashFiles(): Promise<void> {
  const names = await listCrashNames();
  if (names.length <= MAX_CRASH_FILES) {
    return;
  }
  const extra = names.length - MAX_CRASH_FILES;
  for (let i = 0; i < extra; i++) {
    try {
      await fileIo.unlink(`${diagDir()}/${names[i]}`);
    } catch (_e) {
    }
  }
}

async function listCrashNames(): Promise<string[]> {
  if (!(await ensureDir())) {
    return [];
  }
  let names: string[] = [];
  try {
    names = await fileIo.listFile(diagDir());
  } catch (_e) {
    return [];
  }
  const crash: string[] = [];
  for (let i = 0; i < names.length; i++) {
    const n = names[i];
    if (n.indexOf('crash-') === 0 && n.indexOf('.log') > 0) {
      crash.push(n);
    }
  }
  crash.sort();
  return crash;
}

async function ensureDir(): Promise<boolean> {
  if (filesRoot.length === 0) {
    return false;
  }
  if (dirReady) {
    return true;
  }
  const dir = diagDir();
  try {
    await fileIo.mkdir(dir);
  } catch (_e) {
  }
  try {
    const probe = `${dir}/.keep`;
    const f = await fileIo.open(probe, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
    await fileIo.close(f.fd);
    dirReady = true;
    return true;
  } catch (_e) {
    return false;
  }
}

function bindShareRoots(ctx: common.UIAbilityContext): void {
  const files = trimPath(ctx.filesDir);
  if (filesRoot.length === 0 && files.length > 0) {
    filesRoot = files;
    dirReady = false;
  }
  const cache = trimPath(ctx.cacheDir);
  if (cache.length > 0) {
    cacheRoot = cache;
  }
}

function trimPath(p: string): string {
  let s = p.trim();
  while (s.length > 1 && s.charAt(s.length - 1) === '/') {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

function diagDir(): string {
  return `${filesRoot}/${DIR_NAME}`;
}

function exportDir(): string {
  if (cacheRoot.length > 0) {
    return cacheRoot;
  }
  return filesRoot;
}

async function writeUtf8File(path: string, text: string): Promise<void> {
  const f = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    await fileIo.write(f.fd, text);
  } finally {
    await fileIo.close(f.fd);
  }
}

async function readFileCapped(path: string, maxChars: number): Promise<string> {
  if (path.length === 0 || filesRoot.length === 0) {
    return '';
  }
  try {
    const text = await fileIo.readText(path);
    return clip(sanitizeDiagText(text), maxChars);
  } catch (_e) {
    return '';
  }
}

function pushRing(line: string): void {
  ring.push(line);
  if (ring.length > MAX_RING) {
    ring.splice(0, ring.length - MAX_RING);
  }
}

function paramText(params: Record<string, Object>, key: string): string {
  const v = params[key];
  if (v === undefined) {
    return '';
  }
  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
    return `${v}`;
  }
  try {
    return JSON.stringify(v);
  } catch (_e) {
    return String(v);
  }
}

function paramStringList(params: Record<string, Object>, key: string): string[] {
  const raw = paramText(params, key);
  if (raw.length === 0) {
    return [];
  }
  if (raw.charAt(0) !== '[') {
    return [raw];
  }
  const out: string[] = [];
  try {
    const arr = JSON.parse(raw) as Object[];
    for (let i = 0; i < arr.length && i < 16; i++) {
      const item = `${arr[i]}`;
      if (item.length > 0 && item !== 'undefined') {
        out.push(item);
      }
    }
  } catch (_e) {
    out.push(raw);
  }
  return out;
}

function joinNonEmpty(parts: string[]): string {
  const keep: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length > 0) {
      keep.push(parts[i]);
    }
  }
  return keep.join('\n');
}

function clip(s: string, maxChars: number): string {
  if (s.length <= maxChars) {
    return s;
  }
  return `${s.substring(0, maxChars)}\n...truncated ${s.length - maxChars} chars`;
}

function formatStamp(ms: number): string {
  const d = new Date(ms);
  const p = (n: number): string => {
    return n < 10 ? `0${n}` : `${n}`;
  };
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function sanitizeDiagText(raw: string): string {
  let s = raw;
  s = stripQuery(s);
  s = s.replace(/(cookie\s*[=:]\s*)[^\s&;]+/gi, '$1***');
  s = s.replace(/(authorization\s*[=:]\s*)[^\s&;]+/gi, '$1***');
  s = s.replace(/(authx[_-]?(?:token|sign|secret|key)?\s*[=:]\s*)[^\s&;]+/gi, '$1***');
  s = s.replace(/((?:access)?token\s*[=:]\s*)[^\s&;]+/gi, '$1***');
  s = s.replace(/(password\s*[=:]\s*)[^\s&;]+/gi, '$1***');
  s = s.replace(/(secret\s*[=:]\s*)[^\s&;]+/gi, '$1***');
  return s;
}

function stripQuery(s: string): string {
  let out = '';
  let i = 0;
  while (i < s.length) {
    const http = s.indexOf('http', i);
    if (http < 0) {
      out += s.substring(i);
      break;
    }
    out += s.substring(i, http);
    let end = http;
    while (end < s.length && s.charAt(end) !== ' ' && s.charAt(end) !== '\n' && s.charAt(end) !== '"') {
      end++;
    }
    const url = s.substring(http, end);
    const q = url.indexOf('?');
    out += q >= 0 ? url.substring(0, q) : url;
    i = end;
  }
  return out;
}
