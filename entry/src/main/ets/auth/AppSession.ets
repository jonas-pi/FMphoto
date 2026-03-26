/**
 * 内存会话：FnHttpClient 与当前 StoredSession 镜像
 */
import { common } from '@kit.AbilityKit';
import { FnHttpClient } from '../network/FnHttpClient';
import { CertPolicy } from '../network/CertPolicy';
import { SessionPreferences, StoredSession } from './SessionPreferences';

export class AppSession {
  private static stored: StoredSession | null = null;
  private static client: FnHttpClient | null = null;

  static getClient(): FnHttpClient | null {
    return AppSession.client;
  }

  static getStored(): StoredSession | null {
    return AppSession.stored;
  }

  static apply(s: StoredSession): void {
    AppSession.stored = s;
    const long = s.fnosLongToken !== undefined && s.fnosLongToken.length > 0 ? s.fnosLongToken : '';
    AppSession.client = new FnHttpClient(s.baseUrl, s.token, long);
  }

  static updateAlbumParentGuid(guid: string): void {
    if (AppSession.stored !== null) {
      AppSession.stored.albumParentGuid = guid;
    }
  }

  static clear(): void {
    AppSession.stored = null;
    AppSession.client = null;
  }

  /** 从磁盘加载并应用信任列表与 HttpClient */
  static async restore(ctx: common.UIAbilityContext): Promise<StoredSession | null> {
    const s = await SessionPreferences.load(ctx);
    if (s === null) {
      AppSession.clear();
      return null;
    }
    CertPolicy.loadAll(s.trustedHosts);
    AppSession.apply(s);
    return s;
  }

  static async persist(ctx: common.UIAbilityContext): Promise<void> {
    if (AppSession.stored !== null) {
      AppSession.stored.trustedHosts = CertPolicy.dumpAll();
      await SessionPreferences.save(ctx, AppSession.stored);
    }
  }
}
