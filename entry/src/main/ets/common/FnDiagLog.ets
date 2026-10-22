/**
 * 本机诊断日志：订阅系统崩溃 / 卡死，并记录播放失败等关键路径。
 * 不自动上传。反馈页把脱敏后的日志写在本机，由用户在飞书表单里自行选择上传。
 * 保留上次进程记录与系统故障文件，便于闪退后再次打开再导出。
 */
import { bundleManager, common, errorManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { connection } from '@kit.NetworkKit';
import { hiAppEvent, hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';

const DOMAIN: number = 0xFF00;
const TAG: string = 'FnDiag';
const DIR_NAME: string = 'diag';
const RUNTIME_NAME: string = 'runtime.log';
const RUNTIME_ROLL_NAME: string = 'runtime.roll.log';
const RUNTIME_PREV_NAME: string = 'runtime.prev.log';
const RUNTIME_PREV_ROLL_NAME: string = 'runtime.prev.roll.log';
const EXPORT_NAME: string = 'fmphoto-diag.txt';
const MAX_RUNTIME_BYTES: number = 256 * 1024;
const MAX_RING: number = 400;
const MAX_CRASH_FILES: number = 12;
const MAX_SECTION_CHARS: number = 180000;
const MAX_DRAIN_EVENTS: number = 32;

/** tag 条数统计项。 */
interface DiagTagCount {
  tag: string;
  count: number;
}

/** 故障文件分段结果。 */
interface DiagCrashSections {
  crash: string;
  lifecycle: string[];
}

let filesRoot: string = '';
let cacheRoot: string = '';
let dirReady: boolean = false;
let watcherInstalled: boolean = false;
const ring: string[] = [];
/** 最后一条已入队（待落盘）的日志行，用于导出时补上未落盘的部分。 */
let lastEnqueuedLine: string = '';
let appendChain: Promise<void> = Promise.resolve();
let eventPersistChain: Promise<void> = Promise.resolve();
let eventHolder: hiAppEvent.AppEventPackageHolder | null = null;
/** 各级别条数，供导出时的「错误摘要」使用。 */
const levelCounts: Map<string, number> = new Map();
/** 各 tag 的条数，供导出时快速定位问题模块。 */
const tagCounts: Map<string, number> = new Map();
/** 关键状态快照（当前地址、登录结果、同步状态等），导出时单列一段。 */
const stateMap: Map<string, string> = new Map();

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
  eventPersistChain = Promise.resolve();
  archiveRuntimeLogSync();
  fnDiagRecord('I', TAG, 'session start');
  fnDiagInstallCrashWatcher();
  fnDiagInstallErrorObservers();
  fnDiagConfigureSystemEvents();
}

export function fnDiagRecord(level: string, tag: string, message: string): void {
  const line = `${formatStamp(Date.now())} ${level} [${tag}] ${sanitizeDiagText(message)}`;
  pushRing(line);
  countRecord(level, tag);
  enqueueAppend(line + '\n');
  lastEnqueuedLine = line;
  // W/E 同时进 hilog，hdc hilog 抓日志时能直接看到关键失败
  if (level === 'W') {
    hilog.warn(DOMAIN, hilogSafeTag(tag), '%{public}s', sanitizeDiagText(message));
  } else if (level === 'E') {
    hilog.error(DOMAIN, hilogSafeTag(tag), '%{public}s', sanitizeDiagText(message));
  }
}

/** hilog 的 tag 只能有字母数字下划线且不超过 31 字符。 */
function hilogSafeTag(tag: string): string {
  const t = tag.trim();
  if (t.length === 0) {
    return 'FnDiag';
  }
  let out = '';
  for (let i = 0; i < t.length && out.length < 31; i++) {
    const c = t.charAt(i);
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c === '_') {
      out += c;
    } else {
      out += '_';
    }
  }
  if (out.length === 0 || !(out.charAt(0) >= 'a' && out.charAt(0) <= 'z') &&
    !(out.charAt(0) >= 'A' && out.charAt(0) <= 'Z')) {
    out = `T${out}`;
  }
  return out;
}

/**
 * 统一错误埋点：把异常类型、消息与截断后的堆栈一起记下来。
 * catch 里只要调一次，就不会再出现「静默失败、事后无迹可查」。
 */
export function fnDiagError(tag: string, context: string, err?: Object | Error | null): void {
  fnDiagRecord('E', tag, `${context}${describeDiagError(err)}`);
}

/** 关键状态快照：会出现在导出日志的「关键状态」段，便于复现时对齐现场。 */
export function fnDiagSetState(key: string, value: string): void {
  const k = key.trim();
  if (k.length === 0) {
    return;
  }
  const v = sanitizeDiagText(value);
  stateMap.set(k, v);
  fnDiagRecord('I', 'State', `${k}=${v}`);
}

/** 耗时埋点：慢请求、慢同步用。 */
export function fnDiagTiming(tag: string, name: string, costMs: number): void {
  fnDiagRecord('I', tag, `${name} cost=${Math.round(costMs)}ms`);
}

/**
 * 主机名脱敏：日志与导出会被用户分享出去，域名不能原样落盘。
 * IP 字面量只留地址族，域名只留后缀，中继子域保留 <fnid> 形式。
 */
export function fnDiagMaskHost(host: string): string {
  const h = host.trim().toLowerCase();
  if (h.length === 0) {
    return '<host>';
  }
  if (h.indexOf(':') >= 0) {
    return '<ipv6>';
  }
  // 点分四段且每段 0-255 才算 IPv4；只看最后一个点两侧会把 192.168.0.18 误判成域名
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h) && isIpv4Octets(h)) {
    return '<ipv4>';
  }
  const dot = h.lastIndexOf('.');
  if (dot <= 0) {
    return '<domain>';
  }
  const tld = h.substring(dot + 1);
  if (h.endsWith('.fnos.net') || h.endsWith('.5ddd.com')) {
    // 中继子域保留后缀，既能分辨中继集群，又不暴露 FN ID
    const relaySuffix = h.endsWith('.fnos.net') ? '.fnos.net' : '.5ddd.com';
    return `<fnid>${h.substring(h.length - relaySuffix.length)}`;
  }
  return `<domain>.${tld}`;
}

function isIpv4Octets(h: string): boolean {
  const parts = h.split('.');
  for (let i = 0; i < parts.length; i++) {
    const n = parseInt(parts[i], 10);
    if (isNaN(n) || n < 0 || n > 255) {
      return false;
    }
  }
  return true;
}

/** 路径脱敏：保留目录结构，文件名换成 ***（文件名可能是私人内容）。 */
export function fnDiagMaskPath(path: string): string {
  const p = path.trim();
  if (p.length === 0) {
    return '';
  }
  const slash = p.lastIndexOf('/');
  if (slash < 0) {
    return '***';
  }
  return `${p.substring(0, slash + 1)}***`;
}

/** 标识脱敏：FN ID 等只留首尾各两位。 */
export function fnDiagMaskId(id: string): string {
  const s = id.trim();
  if (s.length <= 4) {
    return '***';
  }
  return `${s.substring(0, 2)}***${s.substring(s.length - 2)}`;
}

/** URL 脱敏：保留协议、路径与端口，主机名换成掩码。 */
export function fnDiagMaskUrl(url: string): string {
  const u = url.trim();
  const schemeEnd = u.indexOf('://');
  if (schemeEnd < 0) {
    return fnDiagMaskHost(u);
  }
  const scheme = u.substring(0, schemeEnd + 3);
  const rest = u.substring(schemeEnd + 3);
  const slash = rest.indexOf('/');
  const authority = slash >= 0 ? rest.substring(0, slash) : rest;
  const tail = slash >= 0 ? rest.substring(slash) : '';
  const portAt = authority.lastIndexOf(':');
  const host = portAt > 0 ? authority.substring(0, portAt) : authority;
  const port = portAt > 0 ? authority.substring(portAt) : '';
  return `${scheme}${fnDiagMaskHost(host)}${port}${tail}`;
}

/**
 * 记录某主机当前的解析结果条数（A / AAAA）。
 * 只记条数不记地址：用于判断「是不是只有 AAAA 可用 / AAAA 指向不可达」，
 * 同时避免把域名与 IP 写进可分享的导出文件。
 */
export async function fnDiagRecordResolve(host: string): Promise<void> {
  const h = host.trim();
  if (h.length === 0) {
    return;
  }
  const masked = fnDiagMaskHost(h);
  if (masked === '<ipv4>' || masked === '<ipv6>') {
    return;
  }
  try {
    const addrs = await connection.getAddressesByName(h);
    let v4 = 0;
    let v6 = 0;
    for (let i = 0; i < addrs.length; i++) {
      const raw = addrs[i].address !== undefined ? String(addrs[i].address).trim() : '';
      if (raw.length === 0) {
        continue;
      }
      if (raw.indexOf(':') >= 0) {
        v6++;
      } else {
        v4++;
      }
    }
    fnDiagRecord('W', 'Dns', `resolve ${masked} A=${v4} AAAA=${v6}`);
  } catch (e) {
    fnDiagRecord('W', 'Dns', `resolve ${masked} failed ${describeDiagError(e)}`);
  }
}

function countRecord(level: string, tag: string): void {
  const lv = levelCounts.get(level);
  levelCounts.set(level, lv !== undefined ? lv + 1 : 1);
  const tc = tagCounts.get(tag);
  tagCounts.set(tag, tc !== undefined ? tc + 1 : 1);
}

function describeDiagError(err?: Object | Error | null): string {
  const flat = (s: string): string => {
    // 一条记录必须只占一行，否则导出摘要与解析都会被堆栈打断
    return s.replace(/\r?\n/g, ' | ');
  };
  if (err === undefined || err === null) {
    return '';
  }
  try {
    if (err instanceof Error) {
      const name = err.name !== undefined && err.name.length > 0 ? err.name : 'Error';
      const msg = err.message !== undefined ? err.message : '';
      const stack = err.stack !== undefined ? err.stack : '';
      let out = ` [${name}${msg.length > 0 ? `: ${msg}` : ''}]`;
      if (stack.length > 0) {
        out += ` stack=${clip(flat(sanitizeDiagText(stack)), 240)}`;
      }
      return flat(out);
    }
    // ArkTS 的网络/系统错误多为 BusinessError，不是 Error 实例，
    // 直接 String() 会得到 [object Object]，这里优先序列化出 code/message。
    const json = JSON.stringify(err);
    if (json !== undefined && json.length > 2 && json !== '{}') {
      return ` [${clip(flat(sanitizeDiagText(json)), 300)}]`;
    }
    return ` [${clip(flat(sanitizeDiagText(String(err))), 300)}]`;
  } catch (_e) {
    return ' [unprintable error]';
  }
}

/** 卡死回调里必须同步落盘，进程随后可能被系统杀掉。 */
export function fnDiagRecordSync(level: string, tag: string, message: string): void {
  const line = `${formatStamp(Date.now())} ${level} [${tag}] ${sanitizeDiagText(message)}`;
  pushRing(line);
  countRecord(level, tag);
  appendRuntimeSync(line + '\n');
}

/** 写成手机上的 fmphoto-diag.txt，返回本机路径。调用方不要把文件内容发出去。 */
export async function fnDiagPreparePhoneFile(ctx: common.UIAbilityContext): Promise<string> {
  try {
    bindShareRoots(ctx);
    const path = await buildExportFile();
    if (path.length === 0) {
      fnDiagRecord('E', TAG, 'prepare phone file: empty path');
      return '';
    }
    const raw = await fileIo.readText(path);
    await writeUtf8FileAtomic(path, sanitizeDiagText(raw));
    fnDiagRecord('I', TAG, 'prepare phone file ok');
    return path;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'diag phone file failed: %{public}s', String(e));
    fnDiagRecord('E', TAG, `prepare phone file failed ${String(e)}`);
    return '';
  }
}

export async function fnDiagShare(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    bindShareRoots(ctx);
    // 与反馈页附件走同一条路径：导出后再整体过一遍脱敏，崩溃原文也不会漏
    const path = await fnDiagPreparePhoneFile(ctx);
    if (path.length === 0) {
      hilog.error(DOMAIN, TAG, 'diag export wrote empty path');
      fnDiagRecord('E', TAG, 'share aborted: empty export path');
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
  const watcher: hiAppEvent.Watcher = {
    name: 'fmphotoCrashWatcher',
    appEventFilters: [
      {
        domain: hiAppEvent.domain.OS,
        names: [
          hiAppEvent.event.APP_CRASH,
          hiAppEvent.event.APP_FREEZE,
          hiAppEvent.event.MAIN_THREAD_JANK,
          hiAppEvent.event.RESOURCE_OVERLIMIT,
          hiAppEvent.event.APP_KILLED
        ]
      }
    ],
    onReceive: (_domain: string, groups: Array<hiAppEvent.AppEventGroup>): void => {
      for (let gi = 0; gi < groups.length; gi++) {
        const group = groups[gi];
        for (let ei = 0; ei < group.appEventInfos.length; ei++) {
          const info = group.appEventInfos[ei];
          enqueueSystemEvent(info.name, info.params as Record<string, Object>);
        }
      }
    }
  };
  try {
    eventHolder = hiAppEvent.addWatcher(watcher);
    watcherInstalled = eventHolder !== null;
    if (!watcherInstalled) {
      fnDiagRecord('W', TAG, 'crash watcher returned empty holder');
      return;
    }
    fnDiagRecord('I', TAG, 'crash watcher ready');
    scheduleEventDrain(0);
    scheduleEventDrain(30000);
    scheduleEventDrain(120000);
  } catch (e) {
    watcherInstalled = false;
    eventHolder = null;
    fnDiagRecord('W', TAG, `crash watcher failed ${String(e)}`);
  }
}

function enqueueSystemEvent(eventName: string, params: Record<string, Object>): void {
  eventPersistChain = eventPersistChain.then((): Promise<void> => {
    return persistSystemEvent(eventName, params);
  }).catch((e: Error): void => {
    fnDiagRecord('W', TAG, `persist system event failed ${String(e)}`);
  });
}

function scheduleEventDrain(delayMs: number): void {
  setTimeout((): void => {
    drainPendingSystemEvents();
  }, delayMs);
}

function drainPendingSystemEvents(): void {
  const holder = eventHolder;
  if (holder === null) {
    return;
  }
  try {
    holder.setRow(MAX_DRAIN_EVENTS);
    for (let i = 0; i < MAX_DRAIN_EVENTS; i++) {
      const pkg = holder.takeNext() as hiAppEvent.AppEventPackage | null;
      if (pkg === null || pkg.appEventInfos === undefined || pkg.appEventInfos.length === 0) {
        break;
      }
      for (let j = 0; j < pkg.appEventInfos.length; j++) {
        const info = pkg.appEventInfos[j];
        enqueueSystemEvent(info.name, info.params as Record<string, Object>);
      }
      if (pkg.appEventInfos.length < MAX_DRAIN_EVENTS) {
        break;
      }
    }
  } catch (e) {
    fnDiagRecord('W', TAG, `drain system events failed ${String(e)}`);
  }
}

function fnDiagConfigureSystemEvents(): void {
  if (deviceInfo.sdkApiVersion < 22) {
    return;
  }
  if (deviceInfo.sdkApiVersion >= 24) {
    const policy: hiAppEvent.EventPolicy = {
      mainThreadJankPolicy: {
        logType: 1,
        sampleInterval: 150,
        sampleCount: 10,
        reportTimesPerApp: 5,
        autoStopSampling: true
      },
      appCrashPolicy: { pageSwitchLogEnable: true },
      appFreezePolicy: { pageSwitchLogEnable: true },
      resourceOverlimitPolicy: {
        pageSwitchLogEnable: true
      }
    };
    void hiAppEvent.configEventPolicy(policy)
      .catch((e: Error): void => fnDiagRecord('W', TAG, `config event policy failed${describeDiagError(e)}`));
    return;
  }
  const jankPolicy: hiAppEvent.EventPolicy = {
    mainThreadJankPolicy: {
      logType: 1,
      sampleInterval: 150,
      sampleCount: 10,
      reportTimesPerApp: 5,
      autoStopSampling: true
    }
  };
  void hiAppEvent.configEventPolicy(jankPolicy)
    .catch((e: Error): void => fnDiagRecord('W', TAG, `config jank policy failed ${String(e)}`));
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
      // 一条记录只占一行：堆栈里的换行会打断导出摘要与日志解析
      const oneLine = `${err.name}: ${err.message} ${stack}`.replace(/\r?\n/g, ' | ');
      fnDiagRecord('E', 'Promise', clip(oneLine, 500));
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
  const eventId = paramText(params, 'uuid');
  const safeEvent = safeFilePart(eventName);
  const safeType = safeFilePart(crashType.length > 0 ? crashType : eventName);
  const safeTime = safeFilePart(timeText.length > 0 ? timeText : `${Date.now()}`);
  const safeId = safeFilePart(eventId.length > 0 ? eventId.substring(0, 20) : 'noid');
  const fileName = `fault-${safeTime}-${safeEvent}-${safeType}-${safeId}.log`;
  if (await fileExists(`${diagDir()}/${fileName}`)) {
    return;
  }
  const parts: string[] = [];
  const paramKeys: string[] = [
    'time', 'begin_time', 'end_time', 'crash_type', 'foreground',
    'release_type', 'cpu_abi', 'app_running_unique_id',
    'bundle_version', 'bundle_name', 'process_name', 'pid', 'uid', 'uuid',
    'process_life_time', 'exception', 'memory', 'log_over_limit',
    'event_handler_size_3s', 'event_handler_size_6s', 'external_callback_log',
    'app_start_jiffies_time', 'heaviest_stack'
  ];
  parts.push(`event=${eventName}`);
  for (let i = 0; i < paramKeys.length; i++) {
    const key = paramKeys[i];
    const value = paramText(params, key);
    if (value.length > 0) {
      parts.push(`${key}=${clip(value, MAX_SECTION_CHARS)}`);
    }
  }
  const sectionKeys: string[] = [
    'page_switch_log', 'hilog', 'threads', 'event_handler', 'peer_binder'
  ];
  for (let i = 0; i < sectionKeys.length; i++) {
    const key = sectionKeys[i];
    const value = paramText(params, key);
    if (value.length > 0) {
      parts.push(`--- ${key} ---`);
      parts.push(clip(value, MAX_SECTION_CHARS));
    }
  }
  const extLogs = paramStringList(params, 'external_log');
  const copiedExternalLogs: string[] = [];
  for (let i = 0; i < extLogs.length; i++) {
    const p = extLogs[i];
    parts.push(`--- external_log ${p} ---`);
    const read = await readExternalLog(p);
    parts.push(read.text);
    if (read.success) {
      copiedExternalLogs.push(p);
    }
  }
  const body = sanitizeDiagText(parts.join('\n'));
  if (!(await ensureDir())) {
    throw new Error('diag directory unavailable');
  }
  await writeUtf8FileAtomic(`${diagDir()}/${fileName}`, body);
  await cleanupExternalLogs(copiedExternalLogs);
  await pruneCrashFiles();
  fnDiagRecord('E', TAG, `${eventName} ${safeType} ${clip(exceptionText, 240)}`);
}

interface ExternalLogRead {
  success: boolean;
  text: string;
}

async function readExternalLog(path: string): Promise<ExternalLogRead> {
  if (path.length === 0) {
    return { success: false, text: '(路径为空)' };
  }
  if (path.endsWith('.trace') || path.endsWith('.dmp') || path.endsWith('.rawheap')) {
    return { success: false, text: `(二进制故障文件未内嵌，保留原文件：${path})` };
  }
  try {
    const text = await fileIo.readText(path);
    return { success: true, text: clip(sanitizeDiagText(text), MAX_SECTION_CHARS) };
  } catch (e) {
    return { success: false, text: `(读取失败：${sanitizeDiagText(String(e))})` };
  }
}

async function cleanupExternalLogs(paths: string[]): Promise<void> {
  for (let i = 0; i < paths.length; i++) {
    try {
      await fileIo.unlink(paths[i]);
    } catch (_e) {
    }
  }
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await fileIo.stat(path);
    return true;
  } catch (_e) {
    return false;
  }
}

function safeFilePart(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9_-]/g, '_');
  return safe.length > 0 ? safe : 'unknown';
}

function enqueueAppend(chunk: string): void {
  appendChain = appendChain.then((): Promise<void> => {
    return appendRuntime(chunk);
  }).catch((_e: Error): void => {
  });
}
/** 上一进程的运行记录必须保留到下次导出，HiAppEvent 正是在下次启动回调崩溃事件。 */
function archiveRuntimeLogSync(): void {
  if (!ensureDirSync()) {
    return;
  }
  const current = `${diagDir()}/${RUNTIME_NAME}`;
  const currentRoll = `${diagDir()}/${RUNTIME_ROLL_NAME}`;
  const previous = `${diagDir()}/${RUNTIME_PREV_NAME}`;
  const previousRoll = `${diagDir()}/${RUNTIME_PREV_ROLL_NAME}`;
  if (fileExistsSync(current)) {
    try {
      fileIo.unlink(previous);
    } catch (_e) {
    }
    try {
      fileIo.renameSync(current, previous);
    } catch (_e) {
    }
  }
  if (fileExistsSync(currentRoll)) {
    try {
      fileIo.unlink(previousRoll);
    } catch (_e) {
    }
    try {
      fileIo.renameSync(currentRoll, previousRoll);
    } catch (_e) {
    }
  }
}

function fileExistsSync(path: string): boolean {
  try {
    fileIo.statSync(path);
    return true;
  } catch (_e) {
    return false;
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
      const prev = `${diagDir()}/${RUNTIME_ROLL_NAME}`;
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
    fnDiagRecord('E', TAG, 'export skipped: no writable dir');
    return '';
  }
  const startedAt = Date.now();
  await eventPersistChain;
  await appendChain;
  const blocks: string[] = [];
  blocks.push('=== 飞马相册诊断日志 ===');
  blocks.push('说明：本文件只在本机生成，由你自行上传；已自动去掉密码、token、Cookie 与 URL 查询参数。');
  blocks.push('');
  blocks.push(await buildHeader());
  blocks.push('');
  blocks.push('--- 错误摘要（本次会话）---');
  blocks.push(buildErrorSummary());
  blocks.push('');
  blocks.push('--- 关键状态 ---');
  blocks.push(buildStateSection());
  blocks.push('');
  blocks.push('--- 网络环境 ---');
  blocks.push(await buildNetworkInfo());
  blocks.push('');
  blocks.push('--- 导出信息 ---');
  blocks.push(`exported_at=${formatStamp(Date.now())}`);
  blocks.push('sections=header,summary,state,network,crash,prev_session,current_session');
  blocks.push('');
  blocks.push('--- 崩溃 / 卡死 ---');
  const crashBody = await collectCrashFiles();
  blocks.push(crashBody.crash.length > 0 ? crashBody.crash : '(无。若刚才闪退，请打开应用后再导出一次。)');
  if (crashBody.lifecycle.length > 0) {
    blocks.push('');
    blocks.push('--- 应用被结束（正常生命周期，非崩溃）---');
    blocks.push(crashBody.lifecycle.join('\n'));
  }
  blocks.push('');
  blocks.push('--- 上次会话（含闪退前记录）---');
  const prevRoll = await readFileCapped(`${diagDir()}/${RUNTIME_PREV_ROLL_NAME}`, MAX_SECTION_CHARS);
  if (prevRoll.length > 0) {
    blocks.push(prevRoll);
  }
  const prev = await readFileCapped(`${diagDir()}/${RUNTIME_PREV_NAME}`, MAX_SECTION_CHARS);
  blocks.push(prev.length > 0 ? prev : '(无上次会话记录)');
  blocks.push('');
  blocks.push('--- 本次会话 ---');
  const curRoll = await readFileCapped(`${diagDir()}/${RUNTIME_ROLL_NAME}`, MAX_SECTION_CHARS);
  if (curRoll.length > 0) {
    blocks.push(curRoll);
  }
  const cur = await readFileCapped(`${diagDir()}/${RUNTIME_NAME}`, MAX_SECTION_CHARS);
  if (cur.length > 0) {
    blocks.push(cur);
  } else if (ring.length > 0) {
    blocks.push(ring.join('\n'));
  } else {
    blocks.push('(暂无运行记录，请先复现问题再导出。)');
  }
  // 落盘可能滞后或失败：若文件里找不到内存中最新一条，就把内存缓冲补在后面
  if (ring.length > 0) {
    const newest = ring[ring.length - 1];
    if (newest.length > 0 && cur.indexOf(newest) < 0) {
      blocks.push('');
      blocks.push('--- 内存缓冲（文件里没有的最新日志）---');
      const from = ring.length > 80 ? ring.length - 80 : 0;
      for (let i = from; i < ring.length; i++) {
        blocks.push(ring[i]);
      }
    }
  }
  const body = blocks.join('\n');
  const outPath = `${outDir}/${EXPORT_NAME}`;
  await writeUtf8FileAtomic(outPath, body);
  fnDiagRecord('I', TAG, `export ok size=${body.length} chars cost=${Date.now() - startedAt}ms`);
  return outPath;
}

/** 错误摘要：先看这里就知道本次会话大致出了什么问题。 */
function buildErrorSummary(): string {
  const lines: string[] = [];
  const i = levelCounts.get('I');
  const w = levelCounts.get('W');
  const e = levelCounts.get('E');
  lines.push(`counts I=${i !== undefined ? i : 0} W=${w !== undefined ? w : 0} E=${e !== undefined ? e : 0}`);
  const items: DiagTagCount[] = [];
  tagCounts.forEach((count: number, tag: string): void => {
    items.push({ tag: tag, count: count });
  });
  items.sort((a: DiagTagCount, b: DiagTagCount): number => {
    return b.count - a.count;
  });
  const top: string[] = [];
  for (let i2 = 0; i2 < items.length && i2 < 12; i2++) {
    top.push(`${items[i2].tag}=${items[i2].count}`);
  }
  lines.push(`tags ${top.length > 0 ? top.join(' ') : '(无)'}`);
  const recent: string[] = [];
  for (let idx = ring.length - 1; idx >= 0 && recent.length < 30; idx--) {
    const line = ring[idx];
    if (line.indexOf(' W [') >= 0 || line.indexOf(' E [') >= 0) {
      recent.push(line);
    }
  }
  if (recent.length > 0) {
    lines.push('最近告警/错误：');
    for (let j = 0; j < recent.length; j++) {
      lines.push(recent[j]);
    }
  } else {
    lines.push('最近告警/错误：(无)');
  }
  return lines.join('\n');
}

/** 关键状态：现场快照，方便对齐复现条件。 */
function buildStateSection(): string {
  if (stateMap.size === 0) {
    return '(无状态记录)';
  }
  const lines: string[] = [];
  stateMap.forEach((value: string, key: string): void => {
    lines.push(`${key}=${value}`);
  });
  return lines.join('\n');
}

/** 网络环境：默认网络类型与能力，排查「WiFi 能连、流量能连」这类问题用得上。 */
async function buildNetworkInfo(): Promise<string> {
  const lines: string[] = [];
  try {
    const netHandle = connection.getDefaultNetSync();
    const caps = connection.getNetCapabilitiesSync(netHandle);
    lines.push(`defaultNetId=${netHandle.netId !== undefined ? netHandle.netId : '?'}`);
    const bearers: string[] = [];
    if (caps.bearerTypes !== undefined) {
      for (let i = 0; i < caps.bearerTypes.length; i++) {
        bearers.push(`${caps.bearerTypes[i]}`);
      }
    }
    lines.push(`bearerTypes=${bearers.length > 0 ? bearers.join(',') : '?'}`);
    const netCaps: string[] = [];
    let validated = false;
    if (caps.networkCap !== undefined) {
      for (let i = 0; i < caps.networkCap.length; i++) {
        netCaps.push(`${caps.networkCap[i]}`);
        if (caps.networkCap[i] === connection.NetCap.NET_CAPABILITY_VALIDATED) {
          validated = true;
        }
      }
    }
    lines.push(`networkCap=${netCaps.length > 0 ? netCaps.join(',') : '?'}`);
    lines.push(`validated=${validated}`);
  } catch (e) {
    lines.push(`netinfo failed ${String(e)}`);
  }
  return lines.join('\n');
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

/**
 * 收集故障文件。
 * APP_KILLED 是「应用被结束」的正常生命周期事件，不是崩溃；
 * 混进崩溃段会把真正的崩溃淹掉，所以单独列成紧凑清单。
 */
async function collectCrashFiles(): Promise<DiagCrashSections> {
  const names = await listCrashNames();
  if (names.length === 0) {
    return { crash: '', lifecycle: [] };
  }
  const chunks: string[] = [];
  const lifecycle: string[] = [];
  for (let i = 0; i < names.length; i++) {
    const name = names[i];
    if (name.indexOf('APP_KILLED') >= 0) {
      lifecycle.push(name);
      continue;
    }
    chunks.push(`==== ${name} ====`);
    chunks.push(await readFileCapped(`${diagDir()}/${name}`, MAX_SECTION_CHARS));
  }
  return { crash: chunks.join('\n'), lifecycle: lifecycle };
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
    if ((n.indexOf('crash-') === 0 || n.indexOf('fault-') === 0) && n.endsWith('.log')) {
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

async function writeUtf8FileAtomic(path: string, text: string): Promise<void> {
  const tempPath = `${path}.tmp-${Date.now()}`;
  await writeUtf8File(tempPath, text);
  try {
    try {
      await fileIo.unlink(path);
    } catch (_e) {
    }
    await fileIo.rename(tempPath, path);
  } catch (e) {
    try {
      await fileIo.unlink(tempPath);
    } catch (_cleanup) {
    }
    throw new Error(String(e));
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

export function sanitizeDiagText(raw: string): string {
  let s = raw;
  s = stripQuery(s);
  s = maskHostsInText(s);
  const quotedKey =
    /(["']?(?:[a-z0-9_-]*token|cookie|authorization|password|passwd|pwd|secret|authx[a-z0-9_-]*|trim[-_]sign|keypassword|storepassword|signkey|sign[-_]key|hmackey|hmac[-_]key|apikey|api[-_]key|privkey|privatekey|sessionid|session[-_]id|deviceid|device[-_]id)["']?\s*[:=]\s*)/gi;
  s = s.replace(new RegExp(`${quotedKey.source}"[^"]*"`, 'gi'), '$1"***"');
  s = s.replace(new RegExp(`${quotedKey.source}'[^']*'`, 'gi'), "$1'***'");
  s = s.replace(/(cookie\s*[=:]\s*)[^\r\n]+/gi, '$1***');
  s = s.replace(/(authorization\s*[=:]\s*)[^\r\n]+/gi, '$1***');
  s = s.replace(
    /(["']?(?:[a-z0-9_-]*token|password|passwd|pwd|secret|authx[a-z0-9_-]*|trim[-_]sign|keypassword|storepassword|signkey|sign[-_]key|hmackey|hmac[-_]key|apikey|api[-_]key|privkey|privatekey|sessionid|session[-_]id|deviceid|device[-_]id)["']?\s*[=:]\s*)[^\s,;}\]]+/gi,
    '$1***'
  );
  return s;
}

function stripQuery(s: string): string {
  return s.replace(/((?:https?|wss?):\/\/[^\s"'<>?#]+)[?#][^\s"'<>]*/gi, '$1');
}

/**
 * 兜底：把文本里所有 `scheme://host` 的主机名换成掩码。
 * 埋点很多，万一某处漏了掩码函数，也不会把域名带进可分享的导出文件。
 */
function maskHostsInText(raw: string): string {
  let out = '';
  let rest = raw;
  for (let guard = 0; guard < 64; guard++) {
    const at = firstSchemeIndex(rest);
    if (at < 0) {
      break;
    }
    const schemeEnd = rest.indexOf('://', at);
    if (schemeEnd < 0) {
      break;
    }
    out += rest.substring(0, schemeEnd + 3);
    const after = rest.substring(schemeEnd + 3);
    let end = after.length;
    for (let i = 0; i < after.length; i++) {
      const c = after.charAt(i);
      if (c === '/' || c === '?' || c === '#' || c === '"' || c === '\'' || c === '<' || c === '>' ||
        c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === ',' || c === ')' || c === ']') {
        end = i;
        break;
      }
    }
    out += maskAuthority(after.substring(0, end));
    rest = after.substring(end);
  }
  return `${out}${rest}`;
}

function firstSchemeIndex(s: string): number {
  const lower = s.toLowerCase();
  const schemes: string[] = ['https://', 'http://', 'wss://', 'ws://'];
  let best = -1;
  for (let i = 0; i < schemes.length; i++) {
    const idx = lower.indexOf(schemes[i]);
    if (idx >= 0 && (best < 0 || idx < best)) {
      best = idx;
    }
  }
  return best;
}

/** authority 形如 user@host:port，只掩主机名、保留端口与 userinfo 结构。 */
function maskAuthority(authority: string): string {
  if (authority.length === 0) {
    return authority;
  }
  const at = authority.lastIndexOf('@');
  const userPart = at >= 0 ? authority.substring(0, at + 1) : '';
  const hostPort = at >= 0 ? authority.substring(at + 1) : authority;
  const bracket = hostPort.indexOf(']');
  let host = hostPort;
  let port = '';
  if (bracket >= 0) {
    host = hostPort.substring(0, bracket + 1);
    const after = hostPort.substring(bracket + 1);
    if (after.startsWith(':')) {
      port = after.substring(1);
    }
  } else {
    const colon = hostPort.lastIndexOf(':');
    if (colon > 0) {
      host = hostPort.substring(0, colon);
      port = hostPort.substring(colon + 1);
    }
  }
  const masked = fnDiagMaskHost(host);
  return port.length > 0 ? `${userPart}${masked}:${port}` : `${userPart}${masked}`;
}
