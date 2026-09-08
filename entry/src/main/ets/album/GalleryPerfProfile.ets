/**
 * 图库性能档：按整机内存容量选高性能 / 均衡 / 流畅，内存紧张时再降档。
 * 只在 Ability 启动与前后台切换探测，不进滑动热路径。
 * 内网连接时额外打开带宽爆发：只认会话 LAN 槽位，公网/中继不得自动漏到该档。
 * 「我的」页可手动打开满载；只活在本次进程，重启后关闭，避免一进应用就打满流量。
 */
import { AbilityConstant } from '@kit.AbilityKit';
import { hilog, hidebug } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { isFnRelayBaseUrl } from '../network/FnConnectApi';
import { isHomeLanHost, isPrivateLanHost, parseNormalizedBaseUrl } from '../network/ServerUrl';

const DOMAIN: number = 0xFF00;
const TAG: string = 'GalleryPerf';
const PROBE_COOLDOWN_MS: number = 15000;
/** 12GB 机官方 onMemoryLevel 水线约 1600MB～1800MB，启动时用可用内存提前降档 */
const AVAILABLE_SMOOTH_MB: number = 1600;
const AVAILABLE_BALANCED_MB: number = 2200;
const TOTAL_PERFORMANCE_MB: number = 11 * 1024;
const TOTAL_BALANCED_MB: number = 7 * 1024;

export enum GalleryPerfGear {
  SMOOTH = 0,
  BALANCED = 1,
  PERFORMANCE = 2
}

let deviceGear: GalleryPerfGear = GalleryPerfGear.BALANCED;
let pressureGear: GalleryPerfGear = GalleryPerfGear.PERFORMANCE;
let lastProbeAtMs: number = 0;
let probed: boolean = false;
/** 实际生效的爆发档：内网自动 或 用户手动满载 */
let galleryLanBurst: boolean = false;
/** 会话判定的内网自动爆发，切公网/中继后关闭 */
let galleryLanBurstAuto: boolean = false;
/** 用户在「我的」页打开的满载；不落盘，进程结束即失效 */
let galleryLanBurstForce: boolean = false;
let lanBurstListener: (() => void) | null = null;

function stripHostBrackets(host: string): string {
  const h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']') && h.length > 2) {
    return h.substring(1, h.length - 1);
  }
  return h;
}

function endpointUrlsMatch(left: string, right: string): boolean {
  const a = left.trim();
  const b = right.trim();
  if (a.length === 0 || b.length === 0) {
    return false;
  }
  const na = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  const nb = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  if (na.toLowerCase() === nb.toLowerCase()) {
    return true;
  }
  const pa = parseNormalizedBaseUrl(na);
  const pb = parseNormalizedBaseUrl(nb);
  if (pa === null || pb === null) {
    return false;
  }
  const ha = stripHostBrackets(pa.host);
  const hb = stripHostBrackets(pb.host);
  if (ha.length === 0 || hb.length === 0 || pa.scheme !== pb.scheme) {
    return false;
  }
  const portA = pa.port !== null ? pa.port : (pa.scheme === 'https' ? 443 : 80);
  const portB = pb.port !== null ? pb.port : (pb.scheme === 'https' ? 443 : 80);
  return ha === hb && portA === portB;
}

function matchesAnyEndpoint(baseUrl: string, slots: string[]): boolean {
  for (let i = 0; i < slots.length; i++) {
    if (endpointUrlsMatch(baseUrl, slots[i])) {
      return true;
    }
  }
  return false;
}

function currentHostOf(baseUrl: string): string {
  const parts = parseNormalizedBaseUrl(baseUrl);
  return parts !== null ? parts.host : '';
}

/**
 * 内网爆发只认会话通道，禁止 RFC1918 启发式把 VPN/公司 10.x 漏成千兆档。
 * 公网 / 中继槽位命中一律关闭；LAN 槽位命中且主机确是私网才开；
 * 单地址登录仅 192.168 / 链路本地 / ULA / .local 兜底。
 */
function shouldEnableLanBurst(
  baseUrl: string,
  lanUrl: string,
  lanIpv6Url: string,
  publicUrl: string,
  publicDomainUrl: string,
  publicIpUrl: string,
  publicIpv6Url: string,
  relayUrl: string
): boolean {
  const current = baseUrl.trim();
  if (current.length === 0 || isFnRelayBaseUrl(current)) {
    return false;
  }
  if (matchesAnyEndpoint(current, [relayUrl])) {
    return false;
  }
  if (matchesAnyEndpoint(current, [publicUrl, publicDomainUrl, publicIpUrl, publicIpv6Url])) {
    return false;
  }
  const host = currentHostOf(current);
  if (matchesAnyEndpoint(current, [lanUrl, lanIpv6Url])) {
    return isPrivateLanHost(host);
  }
  return isHomeLanHost(host);
}

export function isGalleryLanBurstEnabled(): boolean {
  return galleryLanBurst;
}

/** 「我的」页开关：只表示用户是否手动强制满载，不含内网自动档 */
export function isGalleryLanBurstForceEnabled(): boolean {
  return galleryLanBurstForce;
}

/** 当前是否由内网槽位自动拉满，供开关副文案区分 */
export function isGalleryLanBurstAutoEnabled(): boolean {
  return galleryLanBurstAuto;
}

export function registerGalleryLanBurstListener(cb: () => void): void {
  lanBurstListener = cb;
}

/** 按「手动满载 OR 内网自动」合成生效档，避免切网冲掉用户本次打开的开关 */
function syncGalleryLanBurstEffective(): void {
  const enabled = galleryLanBurstForce || galleryLanBurstAuto;
  if (galleryLanBurst === enabled) {
    return;
  }
  galleryLanBurst = enabled;
  hilog.info(DOMAIN, TAG, 'lan burst=%{public}d force=%{public}d auto=%{public}d',
    enabled ? 1 : 0, galleryLanBurstForce ? 1 : 0, galleryLanBurstAuto ? 1 : 0);
  if (lanBurstListener !== null) {
    lanBurstListener();
  }
}

/**
 * 用户手动打开/关闭满载。不写 Preferences，杀进程后回到自动判定，
 * 避免下次冷启动在公网仍满载、用户还没来得及关开关就耗掉流量。
 */
export function setGalleryLanBurstForceEnabled(enabled: boolean): void {
  if (galleryLanBurstForce === enabled) {
    return;
  }
  galleryLanBurstForce = enabled;
  syncGalleryLanBurstEffective();
}

/** 退出登录时清掉自动档和手动满载，避免下一账号沿用本次开关 */
export function resetGalleryLanBurstSession(): void {
  galleryLanBurstAuto = false;
  galleryLanBurstForce = false;
  syncGalleryLanBurstEffective();
}

/** 登录/切网后按会话槽位决定自动爆发；手动满载仍可在公网/中继叠加打开 */
export function applyGalleryLanBurstForSession(
  baseUrl: string,
  endpointLanUrl: string,
  endpointLanIpv6Url: string,
  endpointPublicUrl: string,
  endpointPublicDomainUrl: string,
  endpointPublicIpUrl: string,
  endpointPublicIpv6Url: string,
  endpointRelayUrl: string
): void {
  galleryLanBurstAuto = shouldEnableLanBurst(
    baseUrl,
    endpointLanUrl !== undefined ? endpointLanUrl : '',
    endpointLanIpv6Url !== undefined ? endpointLanIpv6Url : '',
    endpointPublicUrl !== undefined ? endpointPublicUrl : '',
    endpointPublicDomainUrl !== undefined ? endpointPublicDomainUrl : '',
    endpointPublicIpUrl !== undefined ? endpointPublicIpUrl : '',
    endpointPublicIpv6Url !== undefined ? endpointPublicIpv6Url : '',
    endpointRelayUrl !== undefined ? endpointRelayUrl : ''
  );
  syncGalleryLanBurstEffective();
}

function memKbToMb(kb: bigint): number {
  const n = parseInt(kb.toString(), 10);
  if (!Number.isFinite(n) || n <= 0) {
    return 0;
  }
  return n / 1024;
}

function minGear(a: GalleryPerfGear, b: GalleryPerfGear): GalleryPerfGear {
  return a <= b ? a : b;
}

function gearFromTotalMb(totalMb: number): GalleryPerfGear {
  if (totalMb >= TOTAL_PERFORMANCE_MB) {
    return GalleryPerfGear.PERFORMANCE;
  }
  if (totalMb >= TOTAL_BALANCED_MB) {
    return GalleryPerfGear.BALANCED;
  }
  if (totalMb > 0) {
    return GalleryPerfGear.SMOOTH;
  }
  return GalleryPerfGear.BALANCED;
}

function pressureFromAvailableMb(availableMb: number): GalleryPerfGear {
  if (availableMb > 0 && availableMb < AVAILABLE_SMOOTH_MB) {
    return GalleryPerfGear.SMOOTH;
  }
  if (availableMb > 0 && availableMb < AVAILABLE_BALANCED_MB) {
    return GalleryPerfGear.BALANCED;
  }
  return GalleryPerfGear.PERFORMANCE;
}

function probeAndAssign(force: boolean): void {
  const now = Date.now();
  if (!force && probed && (now - lastProbeAtMs) < PROBE_COOLDOWN_MS) {
    return;
  }
  lastProbeAtMs = now;
  probed = true;
  let totalMb: number = 0;
  let availableMb: number = 0;
  try {
    const info: hidebug.SystemMemInfo = hidebug.getSystemMemInfo();
    totalMb = memKbToMb(info.totalMem);
    availableMb = memKbToMb(info.availableMem);
  } catch (_e) {
  }
  deviceGear = gearFromTotalMb(totalMb);
  pressureGear = pressureFromAvailableMb(availableMb);
  hilog.info(
    DOMAIN,
    TAG,
    'perf gear=%{public}d totalMb=%{public}d availableMb=%{public}d',
    getGalleryPerfGear(),
    Math.floor(totalMb),
    Math.floor(availableMb)
  );
}

export function ensureGalleryPerfProfile(): void {
  probeAndAssign(false);
}

export function refreshGalleryPerfProfile(): void {
  probeAndAssign(true);
}

export function getGalleryPerfGear(): GalleryPerfGear {
  return minGear(deviceGear, pressureGear);
}

/**
 * 响应整机内存水位。返回建议保留的 PixelMap 上限；负数表示不必立刻裁缓存。
 * 不在此回调里拆 UI。
 */
export function applyGalleryMemoryLevel(level: AbilityConstant.MemoryLevel): number {
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) {
    pressureGear = GalleryPerfGear.SMOOTH;
    return 24;
  }
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
    pressureGear = GalleryPerfGear.SMOOTH;
    return Math.max(32, Math.floor(galleryPerfThumbCacheMax() * 0.4));
  }
  if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE) {
    pressureGear = minGear(pressureGear, GalleryPerfGear.BALANCED);
    return -1;
  }
  // API 24：UI_HIDDEN=3、BACKGROUND_LOW=5、BACKGROUND_CRITICAL=6。用数值比较以免兼容 SDK 20 告警。
  const rawLevel: number = level;
  if (rawLevel === 3 || rawLevel === 6) {
    return 24;
  }
  if (rawLevel === 5) {
    return 40;
  }
  return -1;
}

export function galleryPerfDayCachedCount(wideGrid: boolean): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return wideGrid ? 6 : 8;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return wideGrid ? 4 : 6;
  }
  return wideGrid ? 3 : 4;
}

export function galleryPerfMonthCachedCount(): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 8;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 6;
  }
  return 5;
}

export function galleryPerfYearCachedCount(): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 14;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 10;
  }
  return 8;
}

export function galleryPerfThumbCacheMax(): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 288;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 180;
  }
  return 96;
}

export function galleryPerfScrollCacheFloor(columns: number): number {
  const gear = getGalleryPerfGear();
  if (columns >= 17) {
    if (gear === GalleryPerfGear.PERFORMANCE) {
      return 192;
    }
    return gear === GalleryPerfGear.BALANCED ? 128 : 80;
  }
  if (columns >= 8) {
    if (gear === GalleryPerfGear.PERFORMANCE) {
      return 128;
    }
    return gear === GalleryPerfGear.BALANCED ? 96 : 64;
  }
  if (columns >= 4) {
    if (gear === GalleryPerfGear.PERFORMANCE) {
      return 96;
    }
    return gear === GalleryPerfGear.BALANCED ? 72 : 48;
  }
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 64;
  }
  return gear === GalleryPerfGear.BALANCED ? 56 : 40;
}

/** 视口吞吐档对应的原始并发；内网爆发时按千兆局域网拉高 */
export function galleryPerfThumbConcurrentRaw(demand: number): number {
  const level = Math.max(0, Math.floor(demand));
  if (galleryLanBurst) {
    if (level >= 3) {
      return 64;
    }
    if (level >= 2) {
      return 56;
    }
    if (level >= 1) {
      return 40;
    }
    return 32;
  }
  if (level >= 3) {
    return 28;
  }
  if (level >= 2) {
    return 20;
  }
  if (level >= 1) {
    return 16;
  }
  return 8;
}

export function galleryPerfDateFeedBatch(): number {
  if (galleryLanBurst) {
    return getGalleryPerfGear() === GalleryPerfGear.SMOOTH ? 80 : 100;
  }
  return 50;
}

export function galleryPerfCapThumbConcurrent(raw: number): number {
  const gear = getGalleryPerfGear();
  if (galleryLanBurst) {
    const cap = gear === GalleryPerfGear.PERFORMANCE ? 64 : (gear === GalleryPerfGear.BALANCED ? 40 : 24);
    return Math.min(raw, cap);
  }
  const cap = gear === GalleryPerfGear.PERFORMANCE ? raw : (gear === GalleryPerfGear.BALANCED ? 16 : 8);
  return Math.min(raw, cap);
}

export function galleryPerfPaintBatchMax(): number {
  if (galleryLanBurst) {
    return getGalleryPerfGear() === GalleryPerfGear.SMOOTH ? 6 : 12;
  }
  return getGalleryPerfGear() === GalleryPerfGear.SMOOTH ? 4 : 8;
}

export function galleryPerfFreezeResumeBatch(): number {
  const gear = getGalleryPerfGear();
  if (galleryLanBurst) {
    if (gear === GalleryPerfGear.PERFORMANCE) {
      return 16;
    }
    if (gear === GalleryPerfGear.BALANCED) {
      return 10;
    }
    return 6;
  }
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 10;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 6;
  }
  return 3;
}

export function galleryPerfFreezeResumeDelayMs(): number {
  const gear = getGalleryPerfGear();
  if (galleryLanBurst) {
    if (gear === GalleryPerfGear.PERFORMANCE) {
      return 8;
    }
    if (gear === GalleryPerfGear.BALANCED) {
      return 12;
    }
    return 20;
  }
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 16;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 24;
  }
  return 32;
}

export function galleryPerfScaleCacheKeep(baseKeep: number): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return baseKeep;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return Math.max(24, Math.floor(baseKeep * 0.75));
  }
  return Math.max(20, Math.floor(baseKeep * 0.5));
}

export function galleryPerfImageCacheCount(): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 100;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 72;
  }
  return 40;
}

export function galleryPerfImageRawDataCacheBytes(): number {
  const gear = getGalleryPerfGear();
  if (gear === GalleryPerfGear.PERFORMANCE) {
    return 64 * 1024 * 1024;
  }
  if (gear === GalleryPerfGear.BALANCED) {
    return 40 * 1024 * 1024;
  }
  return 24 * 1024 * 1024;
}

export function applyGalleryPerfImageCache(ui: UIContext): void {
  try {
    ui.setImageCacheCount(galleryPerfImageCacheCount());
    ui.setImageRawDataCacheSize(galleryPerfImageRawDataCacheBytes());
  } catch (_e) {
  }
}
