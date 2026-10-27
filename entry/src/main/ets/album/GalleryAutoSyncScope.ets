/**
 * 同步账本和已见快照的归属。
 * 同一账号、同一台 NAS 共用一份：公网、内网、中继只是入口，不拆成三份。
 * 文件名用摘要，避免账号或地址里的符号进路径。
 * NAS 身份优先用登录后问到的机器码；没有机器码时才退回 FN ID 或地址。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { StoredSession } from '../auth/SessionPreferences';
import { fnDiagRecord } from '../common/FnDiagLog';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncScope';
const PREF_NAME = 'fnos_client_prefs';
/** 旧版账本写在 preferences 里，分文件后不再使用。 */
const K_AUTO_SYNC_LEDGER = 'auto_sync_ledger_v2';
const LEGACY_LEDGER_FILE = 'auto_sync_ledger_v3.txt';
const LEGACY_SEEN_FILE = 'auto_sync_local_seen_v1.txt';
/**
 * 读不到主板序列号时，飞牛会写成这一段。多台这种设备的值相同，不能当 NAS 身份。
 * 末尾 5452494d 是 ASCII「TRIM」。
 */
const MACHINE_ID_PLACEHOLDER = '000000000000000000000000000000005452494d';

/**
 * 能用来定死 NAS 的机器码。空串、非十六进制、全 0、占位码都丢掉。
 * 调用方拿到空串就继续用 FN ID 或地址。
 */
export function usableNasMachineId(raw: string): string {
  const id = raw.trim().toLowerCase();
  if (!/^[0-9a-f]{8,128}$/.test(id)) {
    return '';
  }
  if (id === MACHINE_ID_PLACEHOLDER || /^0+$/.test(id)) {
    return '';
  }
  return id;
}

let legacyDrop: Promise<void> | null = null;

/** 从手填地址或 URL 取出主机，去掉协议、路径和端口。IPv6 去掉方括号。 */
export function stableSyncHost(raw: string): string {
  let text = raw.trim().toLowerCase();
  if (text.length === 0) {
    return '';
  }
  const scheme = text.indexOf('://');
  if (scheme >= 0) {
    text = text.substring(scheme + 3);
  }
  const slash = text.indexOf('/');
  if (slash >= 0) {
    text = text.substring(0, slash);
  }
  if (text.startsWith('[')) {
    const close = text.indexOf(']');
    if (close > 1) {
      return text.substring(1, close);
    }
  }
  const colon = text.lastIndexOf(':');
  if (colon > 0 && text.indexOf(':') === colon) {
    const tail = text.substring(colon + 1);
    if (/^\d+$/.test(tail)) {
      return text.substring(0, colon);
    }
  }
  return text;
}

/**
 * 这台 NAS 的稳定身份。
 * 优先机器码：同一台设备换域名、内网、中继都不变。
 * 没有机器码时用 FN ID，再退回用户填写的域名。当前连上的网址不能当身份。
 */
export function nasIdentityOf(stored: StoredSession): string {
  const machineId = usableNasMachineId(stored.machineId);
  if (machineId.length > 0) {
    return `mid:${machineId}`;
  }
  return nasFallbackIdentity(stored);
}

/**
 * 机器码还没问到时的身份。登录失败或旧会话走这里，和改机器码之前的规则一致。
 */
export function nasFallbackIdentity(stored: StoredSession): string {
  const fnId = stored.fnIdInput.trim().toLowerCase();
  if (fnId.length > 0) {
    return `fn:${fnId}`;
  }
  const domain = stableSyncHost(stored.domainInput);
  if (domain.length > 0) {
    return `host:${domain}`;
  }
  const publicDomain = stableSyncHost(stored.endpointPublicDomainUrl);
  if (publicDomain.length > 0) {
    return `host:${publicDomain}`;
  }
  const lan = stableSyncHost(stored.lanInput);
  if (lan.length > 0) {
    return `host:${lan}`;
  }
  const lanUrl = stableSyncHost(stored.endpointLanUrl);
  if (lanUrl.length > 0) {
    return `host:${lanUrl}`;
  }
  const lan6 = stableSyncHost(stored.endpointLanIpv6Url);
  if (lan6.length > 0) {
    return `host:${lan6}`;
  }
  const pub4 = stableSyncHost(stored.publicIpInput);
  if (pub4.length > 0) {
    return `host:${pub4}`;
  }
  const pub4Url = stableSyncHost(stored.endpointPublicIpUrl);
  if (pub4Url.length > 0) {
    return `host:${pub4Url}`;
  }
  const pub6 = stableSyncHost(stored.publicIpv6Input);
  if (pub6.length > 0) {
    return `host:${pub6}`;
  }
  const pub6Url = stableSyncHost(stored.endpointPublicIpv6Url);
  if (pub6Url.length > 0) {
    return `host:${pub6Url}`;
  }
  const active = stableSyncHost(stored.baseUrl);
  if (active.length > 0) {
    return `host:${active}`;
  }
  return 'unknown';
}

/** 账号原文保留大小写。NAS 身份已经在 nasIdentityOf 里规范过。 */
export function syncScopeTokenFrom(account: string, nas: string): string {
  const text = `${account.trim()}\n${nas}`;
  const hi = fnv1a(text, 0x811c9dc5);
  const lo = fnv1a(text, 0x811c9dc5 ^ 0x9e3779b9);
  return `${toHex8(hi)}${toHex8(lo)}`;
}

/** 当前登录的账本文件名片段。未登录时单独占一份，不写回任何账号的文件。 */
export function gallerySyncScopeToken(): string {
  const stored = AppSession.getStored();
  if (stored === null) {
    return syncScopeTokenFrom('', 'nosession');
  }
  return syncScopeTokenFrom(stored.account, nasIdentityOf(stored));
}

/**
 * 旧的全机一份文件不能迁进某个账号：里面可能混了上一台 NAS 的「已同步」。
 * 删掉之后，当前账号会按 NAS 重新核对，不会把别的库当成已经传过。
 */
export function dropUnscopedSyncFiles(ctx: common.UIAbilityContext): Promise<void> {
  if (legacyDrop !== null) {
    return legacyDrop;
  }
  legacyDrop = dropUnscopedSyncFilesBody(ctx);
  return legacyDrop;
}

async function dropUnscopedSyncFilesBody(ctx: common.UIAbilityContext): Promise<void> {
  await unlinkQuiet(`${ctx.filesDir}/${LEGACY_LEDGER_FILE}`);
  await unlinkQuiet(`${ctx.filesDir}/${LEGACY_SEEN_FILE}`);
  try {
    const prefs = await preferences.getPreferences(ctx, PREF_NAME);
    await prefs.put(K_AUTO_SYNC_LEDGER, '');
    await prefs.flush();
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'clear old ledger prefs failed: %{public}s', String(e));
  }
  fnDiagRecord('I', TAG, 'dropped unscoped sync files');
}

async function unlinkQuiet(path: string): Promise<void> {
  try {
    await fileIo.unlink(path);
  } catch (_e) {
  }
}

function fnv1a(text: string, seed: number): number {
  let hash = seed;
  for (let i = 0; i < text.length; i++) {
    hash = hash ^ text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function toHex8(value: number): string {
  let hex = value.toString(16);
  while (hex.length < 8) {
    hex = `0${hex}`;
  }
  return hex;
}
