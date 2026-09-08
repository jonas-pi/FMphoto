/**
 * 图库性能档：按整机内存容量选高性能 / 均衡 / 流畅，内存紧张时再降档。
 * 只在 Ability 启动与前后台切换探测，不进滑动热路径。
 * 内网连接时额外打开带宽爆发：提高缩略图并发，不关掉滑动/跳转解码闸门。
 */
import { AbilityConstant } from '@kit.AbilityKit';
import { hilog, hidebug } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { isIntranetServerUrl } from '../network/ServerUrl';

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
/** 当前会话走内网时拉高下载并发；切公网/中继后关闭 */
let galleryLanBurst: boolean = false;
let lanBurstListener: (() => void) | null = null;

function endpointUrlsMatch(left: string, right: string): boolean {
  const a = left.trim();
  const b = right.trim();
  if (a.length === 0 || b.length === 0) {
    return false;
  }
  const na = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  const nb = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  return na.toLowerCase() === nb.toLowerCase();
}

export function isGalleryLanBurstEnabled(): boolean {
  return galleryLanBurst;
}

export function registerGalleryLanBurstListener(cb: () => void): void {
  lanBurstListener = cb;
}

export function setGalleryLanBurstEnabled(enabled: boolean): void {
  if (galleryLanBurst === enabled) {
    return;
  }
  galleryLanBurst = enabled;
  hilog.info(DOMAIN, TAG, 'lan burst=%{public}d', enabled ? 1 : 0);
  if (lanBurstListener !== null) {
    lanBurstListener();
  }
}

/** 登录/切网后根据当前 baseUrl 与内网槽位决定是否拉满带宽 */
export function applyGalleryLanBurstForSession(
  baseUrl: string,
  endpointLanUrl: string,
  endpointLanIpv6Url: string
): void {
  const lanUrl = endpointLanUrl !== undefined ? endpointLanUrl : '';
  const lanIpv6Url = endpointLanIpv6Url !== undefined ? endpointLanIpv6Url : '';
  const bySlot = endpointUrlsMatch(baseUrl, lanUrl) || endpointUrlsMatch(baseUrl, lanIpv6Url);
  setGalleryLanBurstEnabled(bySlot || isIntranetServerUrl(baseUrl));
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
