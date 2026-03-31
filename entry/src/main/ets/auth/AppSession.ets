/**
 * 内存会话：FnHttpClient 与当前 StoredSession 镜像
 */
import { common } from '@kit.AbilityKit';
import { FnHttpClient } from '../network/FnHttpClient';
import { CertPolicy } from '../network/CertPolicy';
import { clearOpenApiAuthxCredentials, setOpenApiAuthxCredentials } from '../network/AuthxSigner';
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
    // 会话切换时同步注入 OpenAPI Authx 凭据，确保 /v/api/v1 签名始终使用当前登录上下文。
    setOpenApiAuthxCredentials(s.openApiAuthxKey, s.openApiAuthxSecret);
    const long = s.fnosLongToken !== undefined && s.fnosLongToken.length > 0 ? s.fnosLongToken : '';
    const signKey = s.wsSignKeyB64 !== undefined ? s.wsSignKeyB64 : '';
    AppSession.client = new FnHttpClient(s.baseUrl, s.token, long, signKey);
  }

  static updateAlbumParentGuid(guid: string): void {
    if (AppSession.stored !== null) {
      AppSession.stored.albumParentGuid = guid;
    }
  }

  static clear(): void {
    AppSession.stored = null;
    AppSession.client = null;
    // 退出会话时清理内存中的签名凭据，避免跨账号误用。
    clearOpenApiAuthxCredentials();
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
