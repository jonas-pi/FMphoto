/**
 * 会话恢复：长时间挂起后图库接口易出现 HTTP 401（token / Cookie 失效）。
 *
 * 策略：
 * 1) 静默 WebSocket 重登：依赖登录时写入的账号与 K_LAST_PASSWORD（与登录页回填同源）。
 * 2) 补充 long-token：重登后若仍无 longToken，再探测首页 Set-Cookie（与 Login.persistSessionAndGoHome 一致）。
 * 3) 回前台节流探测：仅刷新 long-token，减轻「很久后进相册」概率（不能替代 token 续期）。
 *
 * 说明：系统不允许应用无限制后台常驻；BackgroundKeepAliveController 仅为官方短时/数据传输任务，非「永久保活」。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from './AppSession';
import { SessionPreferences } from './SessionPreferences';
import { CertPolicy } from '../network/CertPolicy';
import { FnHttpClient } from '../network/FnHttpClient';
import { fnWsLogin } from '../network/FnWsLogin';

const DOMAIN = 0xFF00;
const TAG = 'SessionReauth';

/** 回前台 long-token 探测的最小间隔（毫秒），避免每次切换 Tab 都打 NAS */
const FOREGROUND_PROBE_MIN_INTERVAL_MS = 5 * 60 * 1000;

let lastForegroundProbeAtMs: number = 0;

/**
 * 是否为 HTTP 401（FnHttpClient.requestJson 失败文案为 `HTTP ${code}`）。
 */
export function isHttpUnauthorizedMessage(msg: string | undefined): boolean {
  if (msg === undefined || msg.length === 0) {
    return false;
  }
  const t = msg.trim();
  return t === 'HTTP 401' || t.indexOf('HTTP 401') === 0;
}

/**
 * 401 或会话失效后的恢复：优先静默 WS 重登（与当前工程唯一登录方式一致），再必要时补 long-token。
 *
 * @returns true 表示已更新 AppSession，调用方应使用 AppSession.getClient() 重试原请求
 */
export async function tryRecoverSessionAfterAuthFailure(ctx: common.UIAbilityContext): Promise<boolean> {
  const stored = AppSession.getStored();
  if (stored === null || stored.baseUrl.length === 0) {
    return false;
  }

  // WebSocket 登录会话：用本地保存的密码静默重登（最有效应对「很久未用 token 过期」）
  if (stored.loginViaWebSocket === true) {
    const defaults = await SessionPreferences.loadLoginFormDefaults(ctx);
    const pass = defaults.password;
    const user = stored.account.length > 0 ? stored.account : defaults.username;
    if (pass.length > 0 && user.length > 0) {
      const trusted = CertPolicy.isTrusted(stored.baseUrl);
      const wsRes = await fnWsLogin(stored.baseUrl, user, pass, trusted);
      if (wsRes.success === true && wsRes.token !== undefined && wsRes.token.length > 0) {
        const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
        let lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : '';
        if (lt.length === 0) {
          const probeClient = new FnHttpClient(stored.baseUrl, wsRes.token, '', sk);
          try {
            const probed = await probeClient.fetchFnosLongTokenProbe(12000);
            if (probed.length > 0) {
              lt = probed;
            }
          } catch (_e) {
            // 探测失败不阻断：已有新 token / signKey 仍可尝试图库
          }
        }
        stored.token = wsRes.token;
        stored.wsSignKeyB64 = sk;
        stored.fnosLongToken = lt;
        AppSession.apply(stored);
        await SessionPreferences.save(ctx, stored);
        hilog.info(DOMAIN, TAG, 'session recovered: silent WebSocket relogin');
        return true;
      }
      hilog.warn(
        DOMAIN,
        TAG,
        'silent WS relogin failed: %{public}s',
        wsRes.message !== undefined ? wsRes.message : 'unknown'
      );
    } else {
      hilog.warn(DOMAIN, TAG, 'silent WS relogin skipped: no saved password (re-login once to store)');
    }
  }

  // 兜底：仅尝试刷新 long-token（对「仅有 long-token 过期/缺失」类问题可能有效）
  const client = AppSession.getClient();
  if (client === null) {
    return false;
  }
  try {
    const tok = await client.fetchFnosLongTokenProbe(12000);
    if (tok.length > 0 && tok !== stored.fnosLongToken) {
      stored.fnosLongToken = tok;
      AppSession.apply(stored);
      await SessionPreferences.save(ctx, stored);
      hilog.info(DOMAIN, TAG, 'session recovered: fnos-long-token probe');
      return true;
    }
  } catch (_e) {
  }
  return false;
}

/**
 * 回到前台时节流调用：尽量刷新 fnos-long-token，降低图库鉴权失败概率。
 * 不发起 WebSocket 重登，避免后台频繁打扰用户设备与 NAS。
 */
/** @returns 是否写入了新的 long-token（便于 Home 同步 @State 到 Web 面板） */
export async function proactiveRefreshLongTokenOnForeground(ctx: common.UIAbilityContext): Promise<boolean> {
  const now = Date.now();
  if (now - lastForegroundProbeAtMs < FOREGROUND_PROBE_MIN_INTERVAL_MS) {
    return false;
  }
  const client = AppSession.getClient();
  const stored = AppSession.getStored();
  if (client === null || stored === null || stored.token.length === 0) {
    return false;
  }
  lastForegroundProbeAtMs = now;
  try {
    const tok = await client.fetchFnosLongTokenProbe(8000);
    if (tok.length > 0 && tok !== stored.fnosLongToken) {
      stored.fnosLongToken = tok;
      AppSession.apply(stored);
      await SessionPreferences.save(ctx, stored);
      hilog.info(DOMAIN, TAG, 'foreground: long-token refreshed');
      return true;
    }
  } catch (_e) {
    // 弱网或 NAS 休眠时忽略，相册页仍可按 401 路径恢复
  }
  return false;
}
