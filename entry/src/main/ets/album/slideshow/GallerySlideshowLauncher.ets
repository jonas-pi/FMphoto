import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSession } from '../../auth/AppSession';
import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryPreviewNavStore } from '../GalleryPreviewNavStore';
import {
  GallerySlideshowStreamStore
} from './GallerySlideshowStreamStore';
import { gallerySlideshowSaveConfig } from './GallerySlideshowPreferences';
import { GallerySlideshowConfig, GallerySlideshowScope, GallerySlideshowScopeKind } from './GallerySlideshowTypes';

/**
 * 启动幻灯片：仅拉时间轴索引，随机解析首批条目后立即播放；后续边播边补。
 */
export async function gallerySlideshowLaunch(
  uiCtx: UIContext,
  baseUrl: string,
  scope: GallerySlideshowScope,
  config: GallerySlideshowConfig,
  toast: (msg: string) => void,
  shouldContinue?: () => boolean,
  preloadedItems?: GalleryListItem[]
): Promise<void> {
  if (AppSession.getClient() === null) {
    toast('未登录');
    return;
  }

  const index = await GallerySlideshowStreamStore.loadTimelineIndex(scope, preloadedItems);
  if (shouldContinue !== undefined && !shouldContinue()) {
    return;
  }
  if (index === null || index.totalCount <= 0) {
    toast('暂无可播放媒体');
    return;
  }

  GallerySlideshowStreamStore.begin(scope, config, index);
  const entries = await GallerySlideshowStreamStore.buildStartPlaylist();
  if (shouldContinue !== undefined && !shouldContinue()) {
    GallerySlideshowStreamStore.clear();
    return;
  }
  if (entries.length === 0) {
    GallerySlideshowStreamStore.clear();
    toast('没有符合筛选条件的媒体');
    return;
  }

  const playlist: GalleryListItem[] = [];
  const globalIndices: number[] = [];
  for (let i = 0; i < entries.length; i++) {
    playlist.push(entries[i].item);
    globalIndices.push(entries[i].globalIndex);
  }

  GallerySlideshowStreamStore.rememberEntries(entries);
  const intervalMs = Math.max(2000, Math.floor(config.intervalSec * 1000));

  try {
    const ctx = uiCtx.getHostContext() as common.UIAbilityContext;
    await gallerySlideshowSaveConfig(ctx, config);
  } catch (_e) {
  }

  GalleryPreviewNavStore.openSlideshowPreview(
    uiCtx, baseUrl, playlist, intervalMs, index.totalCount, globalIndices
  );
}

/** 人物相册随机幻灯片（预留入口，PersonPage 等可直接调用） */
export async function gallerySlideshowLaunchForPerson(
  uiCtx: UIContext,
  baseUrl: string,
  personId: string,
  personName: string,
  config: GallerySlideshowConfig,
  toast: (msg: string) => void,
  shouldContinue?: () => boolean
): Promise<void> {
  const scope: GallerySlideshowScope = {
    kind: GallerySlideshowScopeKind.PERSON_ALBUM,
    personId: personId,
    personName: personName
  };
  await gallerySlideshowLaunch(uiCtx, baseUrl, scope, config, toast, shouldContinue);
}

/** 智能分类随机幻灯片（基于 AI 语义搜索扁平结果） */
export async function gallerySlideshowLaunchForSmartCategory(
  uiCtx: UIContext,
  baseUrl: string,
  keyword: string,
  config: GallerySlideshowConfig,
  toast: (msg: string) => void,
  shouldContinue?: () => boolean,
  preloadedItems?: GalleryListItem[]
): Promise<void> {
  const scope: GallerySlideshowScope = {
    kind: GallerySlideshowScopeKind.SMART_CATEGORY,
    smartCategoryKeyword: keyword
  };
  await gallerySlideshowLaunch(uiCtx, baseUrl, scope, config, toast, shouldContinue, preloadedItems);
}
