/**
 * 内存会话：FnHttpClient 与当前 StoredSession 镜像
 */
import { common } from '@kit.AbilityKit';
import { FnHttpClient } from '../network/FnHttpClient';
import { CertPolicy } from '../network/CertPolicy';
import { clearOpenApiAuthxCredentials, setOpenApiAuthxCredentials } from '../network/AuthxSigner';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import { SessionPreferences, StoredSession } from './SessionPreferences';

/** 当前图库/预览用的 Web 根地址；切网时原地更新，页面用 @StorageProp 跟随，避免重载。 */
export const FN_MEDIA_BASE_URL: string = 'FN_MEDIA_BASE_URL';

export class AppSession {
  private static stored: StoredSession | null = null;
  private static client: FnHttpClient | null = null;

  static getClient(): FnHttpClient | null {
    return AppSession.client;
  }

  static getStored(): StoredSession | null {
    return AppSession.stored;
  }

  static currentWebBaseUrl(): string {
    if (AppSession.stored === null) {
      return '';
    }
    return fnWebViewBaseUrl(AppSession.stored.baseUrl);
  }

  static apply(s: StoredSession): void {
    AppSession.stored = s;
    // 会话切换时同步注入 OpenAPI Authx 凭据，确保 /v/api/v1 签名始终使用当前登录上下文。
    setOpenApiAuthxCredentials(s.openApiAuthxKey, s.openApiAuthxSecret);
    const long = s.fnosLongToken !== undefined && s.fnosLongToken.length > 0 ? s.fnosLongToken : '';
    const signKey = s.wsSignKeyB64 !== undefined ? s.wsSignKeyB64 : '';
    if (AppSession.client === null) {
      AppSession.client = new FnHttpClient(s.baseUrl, s.token, long, signKey);
    } else {
      if (AppSession.client.getBaseUrl() !== s.baseUrl) {
        AppSession.client.cancelPendingRequests();
      }
      AppSession.client.setBaseUrl(s.baseUrl);
      AppSession.client.setToken(s.token);
      AppSession.client.setLongToken(long);
      AppSession.client.setWsSignKeyB64(signKey);
    }
    AppStorage.setOrCreate<string>(FN_MEDIA_BASE_URL, fnWebViewBaseUrl(s.baseUrl));
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
    AppStorage.setOrCreate<string>(FN_MEDIA_BASE_URL, '');
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
