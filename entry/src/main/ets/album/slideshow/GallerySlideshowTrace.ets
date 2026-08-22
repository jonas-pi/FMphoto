import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
/**
 * 幻灯片诊断日志 TAG。真机过滤：
 * hdc shell hilog | findstr FmSlide
 */
export const GALLERY_SLIDESHOW_LOG_TAG: string = 'FmSlide';

/** 抽下标：random=均匀随机，stride=随机未命中后的质数步长，none=库已用尽 */
export function slideshowLogPick(via: string, globalIdx: number, used: number, total: number): void {
  hilog.info(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'pick via=%{public}s g=%{public}d used=%{public}d/%{public}d',
    via, globalIdx, used, total);
}

export function slideshowLogRandomMiss(used: number, total: number): void {
  hilog.warn(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'pick random_miss used=%{public}d/%{public}d fallback=stride',
    used, total);
}

export function slideshowLogResolve(
  globalIdx: number,
  dayKey: string,
  dayOffset: number,
  itemKey: string,
  cacheHit: boolean,
  pageSize: number
): void {
  hilog.info(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'resolve g=%{public}d day=%{public}s off=%{public}d key=%{public}s cache=%{public}s page=%{public}d',
    globalIdx, dayKey, dayOffset, itemKey, cacheHit ? 'hit' : 'fetch', pageSize);
}

export function slideshowLogResolveFail(globalIdx: number, reason: string): void {
  hilog.warn(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'resolve_fail g=%{public}d reason=%{public}s',
    globalIdx, reason);
}

export function slideshowLogAcceptSkip(globalIdx: number, itemKey: string, reason: string): void {
  hilog.info(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'skip g=%{public}d key=%{public}s reason=%{public}s',
    globalIdx, itemKey, reason);
}

export function slideshowLogPrefetch(remaining: number, swiperIndex: number, totalCount: number, added: number): void {
  hilog.info(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'prefetch remain=%{public}d idx=%{public}d pages=%{public}d added=%{public}d',
    remaining, swiperIndex, totalCount, added);
}

export function slideshowLogAppend(
  incoming: number,
  unique: number,
  dropGlobal: number,
  dropKey: number,
  itemsLen: number,
  globalsLen: number
): void {
  hilog.info(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG,
    'append in=%{public}d uniq=%{public}d dropG=%{public}d dropK=%{public}d items=%{public}d globals=%{public}d',
    incoming, unique, dropGlobal, dropKey, itemsLen, globalsLen);
}

/**
 * 切页监控：fallback=标题回退到播放队列下标（会表现为 29/总数 顺延）；
 * seq=相邻两张全局下标差 1；dup=与上一张稳定键相同。
 */
export function slideshowLogPage(
  swiperIndex: number,
  globalIdx: number,
  itemKey: string,
  itemsLen: number,
  globalsLen: number,
  fallback: boolean,
  sequential: boolean,
  duplicateKey: boolean
): void {
  const format =
    'page idx=%{public}d g=%{public}d key=%{public}s items=%{public}d globals=%{public}d fallback=%{public}s seq=%{public}s dup=%{public}s';
  const fb = fallback ? '1' : '0';
  const seq = sequential ? '1' : '0';
  const dup = duplicateKey ? '1' : '0';
  if (fallback || sequential || duplicateKey) {
    hilog.warn(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG, format,
      swiperIndex, globalIdx, itemKey, itemsLen, globalsLen, fb, seq, dup);
    return;
  }
  hilog.info(DOMAIN, GALLERY_SLIDESHOW_LOG_TAG, format,
    swiperIndex, globalIdx, itemKey, itemsLen, globalsLen, fb, seq, dup);
}
