/**
 * 相册备份/同步设置（对齐官方备份客户端语义）。
 * 服务端字段：folder_manage_mode(1-4)、rename_strategy；其余为客户端策略。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fnDiagError } from '../common/FnDiagLog';

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

/** 界面顺序与官方一致，对应服务端 folder_manage_mode 的 1–4（具体映射以 NAS 为准）。 */
export const FOLDER_MANAGE_MODE_LABELS: string[] = [
  '默认',
  '按拍摄日期',
  '按设备文件夹',
  '保存在一个文件夹下'
];

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

export async function loadAlbumBackupSettings(ctx: common.UIAbilityContext): Promise<AlbumBackupSettings> {
  const p = await openPrefs(ctx);
  const out = defaults();
  if (p === null) {
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
  const srcJson = await prefsGet(p, K_SOURCE_FOLDERS, '[]');
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
    }
  } catch (e) {
    // 源文件夹 JSON 损坏时 backupSourceFolders 被静默清空。
    fnDiagError(TAG, 'parse source folders failed', e);
    out.backupSourceFolders = [];
  }
  memoryCache = out;
  return out;
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
    await p.put(K_SOURCE_FOLDERS, JSON.stringify(settings.backupSourceFolders));
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
  return c;
}

export function invalidateAlbumBackupSettingsCache(): void {
  memoryCache = null;
}
