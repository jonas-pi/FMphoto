/**
 * 相册备份/同步设置（对齐官方备份客户端语义）。
 * 服务端字段：folder_manage_mode(1-4)、rename_strategy；其余为客户端策略。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fnDiagError, fnDiagRecord } from '../common/FnDiagLog';

const TAG: string = 'AlbumBackup';
const PREF_NAME: string = 'fnos_client_prefs';
const K_FOLDER_MODE: string = 'album_backup_folder_manage_mode';
const K_RENAME: string = 'album_backup_rename_strategy';
const K_PHOTOS_ONLY: string = 'album_backup_photos_only';
const K_CELLULAR: string = 'album_backup_cellular';
const K_LOW_BATTERY: string = 'album_backup_low_battery_stop';
const K_SYNC_ALBUM: string = 'album_backup_sync_create_album';
const K_DISPLAY_PATH: string = 'album_backup_display_path';
const K_BACKUP_PATH: string = 'album_backup_device_path';
const K_DEVICE_NAME: string = 'album_backup_device_name';
const K_SOURCE_FOLDERS: string = 'album_backup_source_folders_json';
/**
 * 影子副本：每次成功保存源列表时同步写一份。
 * 主键万一损坏（写入截断、外部改坏），还能恢复出上一次的选择，
 * 既不用用户全部重选，导出到云端/WebDAV 时也不会把云端那份列表弄丢。
 */
const K_SOURCE_FOLDERS_LAST: string = 'album_backup_source_folders_last_json';

/** 界面顺序与官方一致，对应服务端 folder_manage_mode 的 1–4（具体映射以 NAS 为准）。 */
export const FOLDER_MANAGE_MODE_LABELS: string[] = [
  '默认',
  '按拍摄日期',
  '按设备文件夹',
  '保存在一个文件夹下'
];

/**
 * 备份设置数据。必须加 @Observed：页面里用 @State 持有本对象，
 * 整体替换（this.settings = merged）时 ArkUI 才会重新渲染，
 * 否则界面会一直停留在替换前（缓存）的旧值。
 */
@Observed
export class AlbumBackupSettings {
  /** 1–4 */
  folderManageMode: number = 4;
  /** 0 关闭，1 按拍摄日期重命名 */
  renameStrategy: number = 0;
  photosOnly: boolean = false;
  useCellularData: boolean = false;
  stopWhenBatteryLow: boolean = true;
  syncCreateAlbum: boolean = false;
  displayPath: string = '';
  deviceBackupPath: string = '';
  deviceName: string = 'FMphoto';
  /** NAS 已登记的备份源目录；空表示「备份所有文件夹」语义（merge 时由界面决定）。 */
  backupSourceFolders: string[] = [];
  /**
   * 源文件夹列表是否可信。false 表示磁盘 JSON 读取失败：
   * 此时 backupSourceFolders 为空并不代表「备份所有文件夹」，保存时也不能用它覆盖磁盘原文。
   */
  backupSourceFoldersValid: boolean = true;
  /**
   * 主键损坏时从影子副本恢复出来的「上一次选择」，仅供恢复/导出使用，
   * 不代表当前生效配置；为空表示没有可恢复的历史。
   */
  backupSourceFoldersRecoverable: string[] = [];
  /**
   * 影子副本是否存在（解析成功）。true 且列表为空表示「上次就是备份所有文件夹」，
   * 这同样是有效信息，不能和「没有影子」混为一谈。
   */
  backupSourceFoldersRecoverablePresent: boolean = false;
}

/**
 * 备份源的实际生效范围。
 * 主键读失败时必须用影子副本还原上一次的选择，绝不能把「读失败」当成「备份所有文件夹」。
 */
export class BackupSourceScope {
  /** true = 只扫 keys 里的相册；false = 备份所有文件夹（扫全库） */
  scoped: boolean = false;
  keys: string[] = [];
  /** 主键不可读，结论来自影子副本（或完全无从判断） */
  degraded: boolean = false;
  /** 连影子副本都没有，degraded 时为 true，表示「按备份所有处理」属于兜底猜测 */
  guessed: boolean = false;
}

export function resolveBackupSourceScope(s: AlbumBackupSettings): BackupSourceScope {
  const out = new BackupSourceScope();
  if (s.backupSourceFoldersValid) {
    out.scoped = s.backupSourceFolders.length > 0;
    out.keys = s.backupSourceFolders.slice();
    return out;
  }
  out.degraded = true;
  if (s.backupSourceFoldersRecoverablePresent) {
    // 影子存在：空数组表示上次就是「备份所有文件夹」，非空表示上次的选择。
    out.keys = s.backupSourceFoldersRecoverable.slice();
    out.scoped = out.keys.length > 0;
    return out;
  }
  // 连影子都没有：只能按备份所有处理，但标记为猜测，让调用方记告警。
  out.scoped = false;
  out.guessed = true;
  return out;
}

let memoryCache: AlbumBackupSettings | null = null;

function clampMode(mode: number): number {
  if (mode < 1) {
    return 1;
  }
  if (mode > 4) {
    return 4;
  }
  return Math.floor(mode);
}

function defaults(): AlbumBackupSettings {
  return new AlbumBackupSettings();
}

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (_e) {
    return null;
  }
}

async function prefsGet(p: preferences.Preferences, key: string, def: string): Promise<string> {
  try {
    return await p.get(key, def) as string;
  } catch (_e) {
    return def;
  }
}

/**
 * 读取失败或值不是字符串时返回 null，与「键不存在 / 值为空」区分，
 * 避免把读取故障当成空列表，也避免对非字符串调用字符串方法。
 */
async function prefsGetOptional(p: preferences.Preferences, key: string): Promise<string | null> {
  try {
    const raw = await p.get(key, '');
    if (typeof raw === 'string') {
      return raw;
    }
    return null;
  } catch (_e) {
    return null;
  }
}

export async function loadAlbumBackupSettings(ctx: common.UIAbilityContext): Promise<AlbumBackupSettings> {
  const p = await openPrefs(ctx);
  const out = defaults();
  if (p === null) {
    out.backupSourceFoldersValid = false;
    memoryCache = out;
    return out;
  }
  const mode = Number(await prefsGet(p, K_FOLDER_MODE, '4'));
  out.folderManageMode = clampMode(Number.isFinite(mode) ? mode : 4);
  out.renameStrategy = (await prefsGet(p, K_RENAME, '0')) === '1' ? 1 : 0;
  out.photosOnly = (await prefsGet(p, K_PHOTOS_ONLY, '0')) === '1';
  out.useCellularData = (await prefsGet(p, K_CELLULAR, '0')) === '1';
  out.stopWhenBatteryLow = (await prefsGet(p, K_LOW_BATTERY, '1')) !== '0';
  out.syncCreateAlbum = (await prefsGet(p, K_SYNC_ALBUM, '0')) === '1';
  out.displayPath = await prefsGet(p, K_DISPLAY_PATH, '');
  out.deviceBackupPath = await prefsGet(p, K_BACKUP_PATH, '');
  out.deviceName = await prefsGet(p, K_DEVICE_NAME, 'FMphoto');
  const srcJson = await prefsGetOptional(p, K_SOURCE_FOLDERS);
  if (srcJson === null) {
    // 读取失败：保持空列表，但标记为不可信，界面不得显示「备份所有文件夹」。
    out.backupSourceFoldersValid = false;
    fnDiagError(TAG, 'read source folders failed', null);
    await loadRecoverableSources(p, out);
  } else if (srcJson.trim().length > 0) {
    try {
      const parsed = JSON.parse(srcJson) as Object;
      if (Array.isArray(parsed)) {
        const parsedArr = parsed as Object[];
        const arr: string[] = [];
        for (let i = 0; i < parsedArr.length; i++) {
          const el: Object = parsedArr[i];
          if (typeof el === 'string' && el.trim().length > 0) {
            arr.push(el.trim());
          }
        }
        out.backupSourceFolders = arr;
      } else {
        out.backupSourceFoldersValid = false;
        fnDiagRecord('W', TAG, 'source folders json is not array');
        await loadRecoverableSources(p, out);
      }
    } catch (e) {
      // JSON 损坏：保留磁盘原文，标记列表不可信；不能把空数组当成「全部文件夹」。
      out.backupSourceFoldersValid = false;
      fnDiagError(TAG, 'parse source folders failed', e);
      await loadRecoverableSources(p, out);
    }
  }
  memoryCache = out;
  return out;
}

/**
 * 主键不可读时，尝试从影子副本里恢复出「上一次的选择」。
 * 只作为恢复/导出素材，不写回主键（主键原文保留，等用户确认后再修）。
 */
async function loadRecoverableSources(p: preferences.Preferences, out: AlbumBackupSettings): Promise<void> {
  const raw = await prefsGetOptional(p, K_SOURCE_FOLDERS_LAST);
  if (raw === null || raw.trim().length === 0) {
    return;
  }
  try {
    const parsed = JSON.parse(raw) as Object;
    if (!Array.isArray(parsed)) {
      return;
    }
    const arr: string[] = [];
    const parsedArr = parsed as Object[];
    for (let i = 0; i < parsedArr.length; i++) {
      const el: Object = parsedArr[i];
      if (typeof el === 'string' && el.trim().length > 0) {
        arr.push(el.trim());
      }
    }
    if (arr.length > 0) {
      out.backupSourceFoldersRecoverable = arr;
      fnDiagRecord('I', TAG, 'recoverable source folders from shadow n=' + String(arr.length));
    }
    // 影子是空数组 = 上次就是「备份所有文件夹」，同样算有效信息。
    out.backupSourceFoldersRecoverablePresent = true;
  } catch (e) {
    fnDiagError(TAG, 'parse shadow source folders failed', e);
  }
}

export async function saveAlbumBackupSettings(
  ctx: common.UIAbilityContext,
  settings: AlbumBackupSettings
): Promise<boolean> {
  const p = await openPrefs(ctx);
  if (p === null) {
    fnDiagError(TAG, 'save settings failed', null);
    return false;
  }
  try {
    await p.put(K_FOLDER_MODE, String(clampMode(settings.folderManageMode)));
    await p.put(K_RENAME, settings.renameStrategy > 0 ? '1' : '0');
    await p.put(K_PHOTOS_ONLY, settings.photosOnly ? '1' : '0');
    await p.put(K_CELLULAR, settings.useCellularData ? '1' : '0');
    await p.put(K_LOW_BATTERY, settings.stopWhenBatteryLow ? '1' : '0');
    await p.put(K_SYNC_ALBUM, settings.syncCreateAlbum ? '1' : '0');
    await p.put(K_DISPLAY_PATH, settings.displayPath);
    await p.put(K_BACKUP_PATH, settings.deviceBackupPath);
    await p.put(K_DEVICE_NAME, settings.deviceName);
    // 列表不可信时跳过源文件夹键：保留磁盘原文，避免整包保存把空数组（=全部）写回去。
    if (settings.backupSourceFoldersValid) {
      const json = JSON.stringify(settings.backupSourceFolders);
      await p.put(K_SOURCE_FOLDERS, json);
      // 影子副本同步写：主键损坏时还能恢复出上一次的选择。
      await p.put(K_SOURCE_FOLDERS_LAST, json);
    }
    await p.flush();
    memoryCache = settings;
    return true;
  } catch (e) {
    fnDiagError(TAG, 'save settings failed', e);
    return false;
  }
}

export function getAlbumBackupSettingsCached(): AlbumBackupSettings {
  if (memoryCache !== null) {
    return memoryCache;
  }
  return defaults();
}

export function cloneAlbumBackupSettings(src: AlbumBackupSettings): AlbumBackupSettings {
  const c = new AlbumBackupSettings();
  c.folderManageMode = src.folderManageMode;
  c.renameStrategy = src.renameStrategy;
  c.photosOnly = src.photosOnly;
  c.useCellularData = src.useCellularData;
  c.stopWhenBatteryLow = src.stopWhenBatteryLow;
  c.syncCreateAlbum = src.syncCreateAlbum;
  c.displayPath = src.displayPath;
  c.deviceBackupPath = src.deviceBackupPath;
  c.deviceName = src.deviceName;
  c.backupSourceFolders = src.backupSourceFolders.slice();
  c.backupSourceFoldersValid = src.backupSourceFoldersValid;
  c.backupSourceFoldersRecoverable = src.backupSourceFoldersRecoverable.slice();
  c.backupSourceFoldersRecoverablePresent = src.backupSourceFoldersRecoverablePresent;
  return c;
}

/**
 * 把 src 的字段就地写入 target。
 * 页面用 @State 持有同一个 AlbumBackupSettings 对象：整体替换对象时 ArkUI 只会在
 * build 里直接读取的状态上失效，界面容易停留在旧值；就地写入才能让每一行都跟着刷新。
 */
export function applyAlbumBackupSettings(target: AlbumBackupSettings, src: AlbumBackupSettings): void {
  target.folderManageMode = src.folderManageMode;
  target.renameStrategy = src.renameStrategy;
  target.photosOnly = src.photosOnly;
  target.useCellularData = src.useCellularData;
  target.stopWhenBatteryLow = src.stopWhenBatteryLow;
  target.syncCreateAlbum = src.syncCreateAlbum;
  target.displayPath = src.displayPath;
  target.deviceBackupPath = src.deviceBackupPath;
  target.deviceName = src.deviceName;
  target.backupSourceFolders = src.backupSourceFolders.slice();
  target.backupSourceFoldersValid = src.backupSourceFoldersValid;
  target.backupSourceFoldersRecoverable = src.backupSourceFoldersRecoverable.slice();
  target.backupSourceFoldersRecoverablePresent = src.backupSourceFoldersRecoverablePresent;
}

export function invalidateAlbumBackupSettingsCache(): void {
  memoryCache = null;
}
