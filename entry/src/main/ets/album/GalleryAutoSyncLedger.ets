/**
 * 本机已同步账本：记录已成功上传到 NAS 的本地照片，避免重复上传浪费流量。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { LocalPhotoEntry } from './GalleryAutoSyncService';
import { localPhotoOfficialFingerprint } from './GalleryAutoSyncOfficialFingerprint';

const PREF_NAME = 'fnos_client_prefs';
const K_AUTO_SYNC_LEDGER = 'auto_sync_ledger_v2';
const MAX_LEDGER_ENTRIES: number = 4000;

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences> {
  return await preferences.getPreferences(ctx, PREF_NAME);
}

export class GalleryAutoSyncLedger {
  private static memory: Set<string> | null = null;

  static invalidate(): void {
    GalleryAutoSyncLedger.memory = null;
  }

  private static parseLedger(raw: string): Set<string> {
    const out = new Set<string>();
    if (raw.length === 0) {
      return out;
    }
    const lines = raw.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length > 0) {
        out.add(line);
      }
    }
    return out;
  }

  private static serializeLedger(set: Set<string>): string {
    const lines: string[] = Array.from(set);
    if (lines.length <= MAX_LEDGER_ENTRIES) {
      return lines.join('\n');
    }
    return lines.slice(lines.length - MAX_LEDGER_ENTRIES).join('\n');
  }

  static async load(ctx: common.UIAbilityContext): Promise<Set<string>> {
    if (GalleryAutoSyncLedger.memory !== null) {
      return new Set<string>(GalleryAutoSyncLedger.memory);
    }
    const p = await openPrefs(ctx);
    const raw = await p.get(K_AUTO_SYNC_LEDGER, '') as string;
    GalleryAutoSyncLedger.memory = GalleryAutoSyncLedger.parseLedger(raw);
    return new Set<string>(GalleryAutoSyncLedger.memory);
  }

  static async markSynced(ctx: common.UIAbilityContext, entries: LocalPhotoEntry[]): Promise<void> {
    if (entries.length === 0) {
      return;
    }
    const set = await GalleryAutoSyncLedger.load(ctx);
    for (let i = 0; i < entries.length; i++) {
      set.add(localPhotoOfficialFingerprint(entries[i]));
    }
    GalleryAutoSyncLedger.memory = set;
    const p = await openPrefs(ctx);
    await p.put(K_AUTO_SYNC_LEDGER, GalleryAutoSyncLedger.serializeLedger(set));
    await p.flush();
  }

  static async clear(ctx: common.UIAbilityContext): Promise<void> {
    GalleryAutoSyncLedger.memory = new Set<string>();
    const p = await openPrefs(ctx);
    await p.put(K_AUTO_SYNC_LEDGER, '');
    await p.flush();
  }
}
