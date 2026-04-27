import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../../auth/AppSession';
import { isHttpUnauthorizedMessage, tryRecoverSessionAfterAuthFailure } from '../../auth/SessionReauth';
import { SessionPreferences } from '../../auth/SessionPreferences';
import {
  AiPersonItem,
  GalleryGetListData,
  GalleryListItem,
  MediaCategoryItem,
  SmartCategoryItem
} from '../../model/FnApiTypes';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { GalleryHomeTimelineCache } from '../GalleryHomeTimelineCache';
import {
  galleryMediaCategoryModeLoader,
  galleryPersonModeLoader,
  gallerySmartCategoryModeLoader
} from './GalleryAlbumModeLoaders';
import {
  DATE_FEED_BATCH,
  DAY_MAX_ROUNDS,
  EMPTY_PAGE_ADVANCE_THRESHOLD,
  GALLERY_BATCH_VERBOSE_LOG,
  GALLERY_TAB_DOMAIN as DOMAIN,
  GALLERY_TAB_TAG as TAG,
  PUMP_UI_GAP_MS
} from './GalleryAlbumTabConstants';
import {
  dayKey,
  fmtDayEnd,
  fmtDayStart,
  listFromData,
  parseTimelineDayCells,
  sortDaysDesc,
  TimelineDayModel
} from './GalleryAlbumTabTypes';
import { GalleryAlbumDaySectionState } from './GalleryAlbumState';

export interface GalleryAlbumLoadOrchestratorHost {
  getUIContext(): UIContext;
  inSearchMode: boolean;
  inCategoryMode: boolean;
  inSmartCategoryMode: boolean;
  inPersonMode: boolean;
  categoryLoading: boolean;
  categoryError: string;
  categoryItems: MediaCategoryItem[];
  smartCategoryLoading: boolean;
  smartCategoryError: string;
  smartSceneItems: SmartCategoryItem[];
  smartInfoItems: SmartCategoryItem[];
  personLoading: boolean;
  personError: string;
  personItems: AiPersonItem[];
  personStatOverrides: Map<string, string>;
  personStatVersion: number;
  personStatGen: number;
  lastBootstrapSatisfiedRefreshVersion: number;
  galleryTimelineAtTopForPull: boolean;
  gallerySelectionMode: boolean;
  galleryTimelineRefreshing: boolean;
  galleryPullRefreshThresholdHapticDone: boolean;
  loadGen: number;
  exhausted: boolean;
  dayIndex: number;
  orderedDays: TimelineDayModel[];
  dayOffsets: Map<string, number>;
  dayRounds: Map<string, number>;
  dayEmptyRounds: Map<string, number>;
  bootLoading: boolean;
  loadError: string;
  sections: GalleryAlbumDaySectionState[];
  footText: string;
  loadingMore: boolean;
  pumpEpoch: number;
  lastVisibleLoadDayIdx: number;
  bootstrapDebounceTimer: number;
  scrollerRef: Scroller;
  applyDeleteSyncIfNeeded(): void;
  enrichPersonStats(items: AiPersonItem[], gen: number): Promise<void>;
  rebuildFlow(): void;
  countGalleryListedItems(): number;
  upsertSection(day: TimelineDayModel, list: GalleryListItem[], newOffset: number): void;
  clearBootstrapDebounceTimer(): void;
}

export function galleryAlbumMarkTimelineRefreshCaughtUp(host: GalleryAlbumLoadOrchestratorHost): void {
  host.lastBootstrapSatisfiedRefreshVersion = GalleryTimelineRefreshStore.version;
}

export async function galleryAlbumRefreshMediaCategoriesInPlace(
  host: GalleryAlbumLoadOrchestratorHost
): Promise<void> {
  if (!host.inCategoryMode || host.categoryLoading) {
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  host.categoryLoading = true;
  host.categoryError = '';
  const client = AppSession.getClient();
  if (client === null) {
    host.categoryLoading = false;
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  const result = await galleryMediaCategoryModeLoader.load(client);
  host.categoryItems = result.data.items;
  host.categoryLoading = false;
  galleryAlbumMarkTimelineRefreshCaughtUp(host);
}

export async function galleryAlbumRefreshSmartCategoriesInPlace(
  host: GalleryAlbumLoadOrchestratorHost
): Promise<void> {
  if (!host.inSmartCategoryMode || host.smartCategoryLoading) {
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  host.smartCategoryLoading = true;
  host.smartCategoryError = '';
  const client = AppSession.getClient();
  if (client === null) {
    host.smartCategoryLoading = false;
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  const result = await gallerySmartCategoryModeLoader.load(client);
  host.smartSceneItems = result.data.sceneItems;
  host.smartInfoItems = result.data.infoItems;
  host.smartCategoryLoading = false;
  galleryAlbumMarkTimelineRefreshCaughtUp(host);
}

export async function galleryAlbumRefreshPersonListInPlace(
  host: GalleryAlbumLoadOrchestratorHost
): Promise<void> {
  if (!host.inPersonMode || host.personLoading) {
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  host.personStatOverrides.clear();
  host.personStatVersion++;
  host.personStatGen++;
  const gen = host.personStatGen;
  host.personLoading = true;
  host.personError = '';
  const client = AppSession.getClient();
  if (client === null) {
    host.personLoading = false;
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  const result = await galleryPersonModeLoader.load(client);
  if (gen !== host.personStatGen) {
    host.personLoading = false;
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }
  host.personItems = result.data.items;
  if (result.data.items.length > 0) {
    void host.enrichPersonStats(result.data.items, gen);
  }
  host.personLoading = false;
  galleryAlbumMarkTimelineRefreshCaughtUp(host);
}

export function galleryAlbumOnTabVisibleAgain(host: GalleryAlbumLoadOrchestratorHost): void {
  host.applyDeleteSyncIfNeeded();
  const needTimelineCatchUp = GalleryTimelineRefreshStore.version > host.lastBootstrapSatisfiedRefreshVersion;
  if (host.inSearchMode) {
    if (needTimelineCatchUp) {
      galleryAlbumMarkTimelineRefreshCaughtUp(host);
    }
    return;
  }
  if (host.inCategoryMode || host.inSmartCategoryMode || host.inPersonMode) {
    if (needTimelineCatchUp) {
      if (host.inCategoryMode) {
        void galleryAlbumRefreshMediaCategoriesInPlace(host);
      } else if (host.inSmartCategoryMode) {
        void galleryAlbumRefreshSmartCategoriesInPlace(host);
      } else {
        void galleryAlbumRefreshPersonListInPlace(host);
      }
    }
    return;
  }
  if (needTimelineCatchUp) {
    host.clearBootstrapDebounceTimer();
    void galleryAlbumBootstrap(host, true);
  }
}

export function galleryAlbumSyncTimelineAtTopForPull(host: GalleryAlbumLoadOrchestratorHost): void {
  try {
    const off = host.scrollerRef.currentOffset();
    const yRaw = off.yOffset;
    const y = typeof yRaw === 'number' ? yRaw : 0;
    host.galleryTimelineAtTopForPull = !Number.isFinite(y) || y <= 0.5;
  } catch (_e) {
    host.galleryTimelineAtTopForPull = true;
  }
}

export async function galleryAlbumOnTimelinePullRefresh(host: GalleryAlbumLoadOrchestratorHost): Promise<void> {
  galleryAlbumSyncTimelineAtTopForPull(host);
  if (!host.galleryTimelineAtTopForPull || host.gallerySelectionMode) {
    host.galleryTimelineRefreshing = false;
    return;
  }
  host.galleryTimelineRefreshing = true;
  try {
    host.clearBootstrapDebounceTimer();
    await galleryAlbumBootstrap(host, false);
  } finally {
    host.galleryTimelineRefreshing = false;
    host.galleryPullRefreshThresholdHapticDone = false;
  }
}

export async function galleryAlbumBootstrap(
  host: GalleryAlbumLoadOrchestratorHost,
  showFullBleedSkeleton: boolean = true
): Promise<void> {
  GalleryHomeTimelineCache.invalidate();
  const gen = ++host.loadGen;
  host.exhausted = false;
  host.dayIndex = 0;
  host.orderedDays = [];
  host.dayOffsets.clear();
  host.dayRounds.clear();
  host.dayEmptyRounds.clear();
  host.bootLoading = showFullBleedSkeleton;
  host.loadError = '';
  host.sections = [];
  host.footText = '';
  host.rebuildFlow();

  const client = AppSession.getClient();
  if (client === null) {
    if (gen !== host.loadGen) {
      return;
    }
    host.bootLoading = false;
    host.loadError = '未登录';
    return;
  }

  let workClient = client;
  if (workClient.getLongToken().length === 0) {
    const tok = await workClient.fetchFnosLongTokenProbe(12000);
    if (tok.length > 0) {
      const cur = AppSession.getStored();
      if (cur !== null) {
        cur.fnosLongToken = tok;
        AppSession.apply(cur);
        try {
          const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
          void SessionPreferences.save(ctx, cur);
        } catch (_e) {
        }
        const refreshed = AppSession.getClient();
        if (refreshed !== null) {
          workClient = refreshed;
        }
      }
    }
  }

  let tl = await workClient.getGalleryTimeline();
  if (gen !== host.loadGen) {
    return;
  }
  if (tl.success !== true || tl.data === undefined) {
    const em0 = tl.message !== undefined && tl.message.length > 0 ? tl.message : '';
    if (isHttpUnauthorizedMessage(em0)) {
      const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
      const ok = await tryRecoverSessionAfterAuthFailure(ctx);
      if (ok) {
        const c2 = AppSession.getClient();
        if (c2 !== null) {
          workClient = c2;
          tl = await workClient.getGalleryTimeline();
        }
      }
    }
  }
  if (gen !== host.loadGen) {
    return;
  }
  if (tl.success !== true || tl.data === undefined) {
    const em = tl.message !== undefined && tl.message.length > 0 ? tl.message : '时间轴加载失败';
    hilog.warn(DOMAIN, TAG, 'timeline fail: %{public}s body: %{public}s', em, '');
    host.bootLoading = false;
    host.loadError = em;
    return;
  }

  const rawList = tl.data.list ?? [];
  const cellsIn: Array<Record<string, number | undefined>> = [];
  for (let i = 0; i < rawList.length; i++) {
    const el = rawList[i];
    if (typeof el === 'object' && el !== null) {
      cellsIn.push(el as Record<string, number | undefined>);
    }
  }
  const cells = sortDaysDesc(parseTimelineDayCells(cellsIn)).filter(
    (c: TimelineDayModel): boolean => c.itemCount > 0
  );
  if (cells.length === 0) {
    host.bootLoading = false;
    host.footText = '时间轴暂无数据';
    host.rebuildFlow();
    galleryAlbumMarkTimelineRefreshCaughtUp(host);
    return;
  }

  host.orderedDays = cells;
  host.bootLoading = false;
  galleryAlbumMarkTimelineRefreshCaughtUp(host);
  galleryAlbumPumpLoad(host);
}

export function galleryAlbumPumpLoad(
  host: GalleryAlbumLoadOrchestratorHost,
  singleBatch: boolean = false
): void {
  if (host.loadingMore || host.exhausted) {
    return;
  }
  if (host.orderedDays.length === 0) {
    return;
  }
  host.loadingMore = true;
  const gen = host.loadGen;
  const epoch = host.pumpEpoch;
  void galleryAlbumLoadOneBatch(host).then((added: number): void => {
    if (epoch !== host.pumpEpoch) {
      host.loadingMore = false;
      return;
    }
    host.loadingMore = false;
    if (gen !== host.loadGen || host.exhausted) {
      return;
    }
    if (added === -1) {
      return;
    }
    if (added === -2) {
      if (singleBatch) {
        return;
      }
      const retryEpoch = host.pumpEpoch;
      setTimeout((): void => {
        if (retryEpoch !== host.pumpEpoch) {
          return;
        }
        galleryAlbumPumpLoad(host);
      }, 3000);
      return;
    }
    if (added === -3) {
      if (singleBatch) {
        return;
      }
      const retryEpoch = host.pumpEpoch;
      setTimeout((): void => {
        if (retryEpoch !== host.pumpEpoch) {
          return;
        }
        galleryAlbumPumpLoad(host);
      }, 500);
      return;
    }
    if (singleBatch) {
      return;
    }
    const nextEpoch = host.pumpEpoch;
    setTimeout((): void => {
      if (nextEpoch !== host.pumpEpoch) {
        return;
      }
      galleryAlbumPumpLoad(host);
    }, added > 0 ? PUMP_UI_GAP_MS : 0);
  });
}

export async function galleryAlbumLoadOneBatch(host: GalleryAlbumLoadOrchestratorHost): Promise<number> {
  if (host.exhausted) {
    return -1;
  }
  if (host.dayIndex >= host.orderedDays.length) {
    if (host.orderedDays.length === 0) {
      return -1;
    }
    host.exhausted = true;
    host.footText = host.countGalleryListedItems() > 0
      ? '\u5df2\u52a0\u8f7d\u5168\u90e8\u5a92\u4f53'
      : '\u672a\u83b7\u53d6\u5230\u5a92\u4f53';
    return -1;
  }

  const gen = host.loadGen;
  const epoch = host.pumpEpoch;
  const day = host.orderedDays[host.dayIndex];
  const key = dayKey(day.year, day.month, day.day);
  const off = host.dayOffsets.get(key) ?? 0;
  const rounds = host.dayRounds.get(key) ?? 0;
  const emptyRounds = host.dayEmptyRounds.get(key) ?? 0;
  const itemCountBasedMax = day.itemCount > 0
    ? Math.ceil(day.itemCount / DATE_FEED_BATCH) + 20
    : DAY_MAX_ROUNDS;
  const dayMaxRounds = Math.max(DAY_MAX_ROUNDS, itemCountBasedMax);

  if (rounds >= dayMaxRounds) {
    hilog.warn(DOMAIN, TAG, 'day %{public}s exceeded max rounds %{public}d, force advance', key, dayMaxRounds);
    host.dayIndex++;
    return 0;
  }

  const client = AppSession.getClient();
  if (client === null) {
    host.footText = '未登录';
    host.exhausted = true;
    return -1;
  }

  try {
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    let res = await client.getGalleryList(st, et, DATE_FEED_BATCH, off, 'index');
    if (gen !== host.loadGen || epoch !== host.pumpEpoch) {
      return -1;
    }

    if (res.success !== true) {
      const em0 = res.message !== undefined && res.message.length > 0 ? res.message : '';
      if (isHttpUnauthorizedMessage(em0)) {
        const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
        const recovered = await tryRecoverSessionAfterAuthFailure(ctx);
        if (recovered) {
          const c2 = AppSession.getClient();
          if (c2 !== null) {
            res = await c2.getGalleryList(st, et, DATE_FEED_BATCH, off, 'index');
          }
        }
      }
    }
    if (gen !== host.loadGen || epoch !== host.pumpEpoch) {
      return -1;
    }

    if (res.success !== true) {
      const em = res.message !== undefined && res.message.length > 0 ? res.message : '加载失败';
      hilog.warn(DOMAIN, TAG, 'getList fail %{public}s off=%{public}d: %{public}s', key, off, em);
      host.footText = em;
      return -2;
    }

    const list = listFromData(res.data as GalleryGetListData | undefined);
    const total = res.data?.total;
    const newOff = off + list.length;
    host.dayOffsets.set(key, newOff);

    if (list.length > 0) {
      host.upsertSection(day, list, newOff);
      host.dayEmptyRounds.set(key, 0);
    } else {
      host.dayEmptyRounds.set(key, emptyRounds + 1);
    }

    if (list.length > 0 && list.length < DATE_FEED_BATCH) {
      host.dayRounds.set(key, rounds + 1);
      if (GALLERY_BATCH_VERBOSE_LOG) {
        hilog.warn(
          DOMAIN,
          TAG,
          'short page end day %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d',
          key,
          off,
          list.length,
          newOff,
          day.itemCount
        );
      }
      host.dayIndex++;
      return list.length;
    }

    const emptyNow = list.length === 0 ? (emptyRounds + 1) : 0;
    const timelineSaysMore = day.itemCount > 0 && newOff < day.itemCount;
    const transientEmpty = list.length === 0 && timelineSaysMore;

    if (GALLERY_BATCH_VERBOSE_LOG) {
      hilog.warn(
        DOMAIN,
        TAG,
        'batch %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d total=%{public}s emptyRounds=%{public}d transient=%{public}d',
        key,
        off,
        list.length,
        newOff,
        day.itemCount,
        total !== undefined ? String(total) : 'n/a',
        list.length === 0 ? (emptyRounds + 1) : 0,
        transientEmpty ? 1 : 0
      );
    }

    if (!transientEmpty) {
      host.dayRounds.set(key, rounds + 1);
    }

    if (transientEmpty) {
      return -3;
    }

    const reachTimelineEnd = day.itemCount > 0 && newOff >= day.itemCount;
    const shouldAdvanceDay = list.length === 0 && (
      reachTimelineEnd ||
      (day.itemCount <= 0 && emptyNow >= EMPTY_PAGE_ADVANCE_THRESHOLD)
    );
    if (shouldAdvanceDay) {
      host.dayIndex++;
    }

    return list.length;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'loadOneBatch error: %{public}s', String(e));
    host.footText = String(e) || '请求异常';
    return -2;
  }
}
