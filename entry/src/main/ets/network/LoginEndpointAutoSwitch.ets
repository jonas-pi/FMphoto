/**
 * 已登录后按网络变化自动选路：重新解析 FN ID，并行探测内网/公网 V4/V6，切到当前最优地址。
 */
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences, StoredSession } from '../auth/SessionPreferences';
import { lookupFnConnect } from './FnConnectApi';
import {
  endpointPoolFromStored,
  resolveEndpointConnectionInfo,
  switchStoredLoginEndpointToUrl
} from './LoginEndpointSwitch';
import { selectAmongEndpointPool } from './LoginEndpointSelector';
import { preferPublicEndpointUrl } from './PublicDns';

const DOMAIN = 0xFF00;
const TAG = 'LoginEndpointAutoSwitch';
const DEBOUNCE_MS = 1600;

export const FN_ENDPOINT_SWITCH_VERSION: string = 'FN_ENDPOINT_SWITCH_VERSION';
export const FN_ENDPOINT_SWITCH_MESSAGE: string = 'FN_ENDPOINT_SWITCH_MESSAGE';

let netConnection: connection.NetConnection | null = null;
let abilityContext: common.UIAbilityContext | null = null;
let debounceTimer: number = -1;
let running: boolean = false;
let pending: boolean = false;

export function ensureEndpointSwitchStorage(): void {
  AppStorage.setOrCreate<number>(FN_ENDPOINT_SWITCH_VERSION, 0);
  AppStorage.setOrCreate<string>(FN_ENDPOINT_SWITCH_MESSAGE, '');
}

function notifyEndpointSwitched(message: string): void {
  AppStorage.setOrCreate<string>(FN_ENDPOINT_SWITCH_MESSAGE, message);
  const old = AppStorage.get<number>(FN_ENDPOINT_SWITCH_VERSION);
  const next = (old !== undefined ? old : 0) + 1;
  AppStorage.setOrCreate<number>(FN_ENDPOINT_SWITCH_VERSION, next);
}

function applyLookupToStored(stored: StoredSession, lookedLan4: string, lookedLan6: string,
  lookedPub4: string, lookedPub6: string, lookedDomain: string): void {
  if (lookedLan4.length > 0) {
    stored.endpointLanUrl = lookedLan4;
  }
  if (lookedLan6.length > 0) {
    stored.endpointLanIpv6Url = lookedLan6;
  }
  if (lookedPub4.length > 0) {
    stored.endpointPublicIpUrl = lookedPub4;
  }
  if (lookedPub6.length > 0) {
    stored.endpointPublicIpv6Url = lookedPub6;
  }
  if (stored.domainInput.trim().length === 0 && lookedDomain.length > 0) {
    stored.endpointPublicDomainUrl = lookedDomain;
  }
  stored.endpointPublicUrl = preferPublicEndpointUrl(
    stored.endpointPublicDomainUrl,
    stored.endpointPublicIpUrl.length > 0 ? stored.endpointPublicIpUrl : stored.endpointPublicIpv6Url
  );
}

async function refreshFnConnectAddresses(stored: StoredSession): Promise<void> {
  const fnId = stored.fnIdInput.trim();
  if (fnId.length === 0) {
    return;
  }
  const looked = await lookupFnConnect(fnId, stored.useHttps);
  if (!looked.ok) {
    hilog.warn(DOMAIN, TAG, 'FN Connect refresh skipped: %{public}s', looked.message);
    return;
  }
  applyLookupToStored(
    stored,
    looked.lanIpv4Server,
    looked.lanIpv6Server,
    looked.publicIpv4Server,
    looked.publicIpv6Server,
    looked.publicDomainServer
  );
}

async function runAutoSwitch(): Promise<void> {
  const ctx = abilityContext;
  if (ctx === null) {
    return;
  }
  const stored = AppSession.getStored();
  if (stored === null || stored.token.length === 0) {
    return;
  }
  const info = resolveEndpointConnectionInfo(stored);
  if (!info.canSwitch && stored.fnIdInput.trim().length === 0) {
    return;
  }
  try {
    await refreshFnConnectAddresses(stored);
    const latest = AppSession.getStored();
    if (latest === null) {
      return;
    }
    await SessionPreferences.save(ctx, latest);
    const pool = endpointPoolFromStored(latest);
    const selected = await selectAmongEndpointPool(pool, latest.loginEndpointPreference);
    if (selected.server.length === 0) {
      return;
    }
    const res = await switchStoredLoginEndpointToUrl(ctx, selected.server, true);
    if (!res.ok) {
      hilog.warn(DOMAIN, TAG, 'auto switch failed: %{public}s', res.message);
      return;
    }
    if (res.message.length === 0) {
      return;
    }
    const summary = selected.summary.length > 0 ? selected.summary : '已自动切换连接';
    hilog.info(DOMAIN, TAG, 'auto switched: %{public}s', summary);
    notifyEndpointSwitched(summary);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'auto switch error: %{public}s', String(e));
  }
}

async function runGuarded(): Promise<void> {
  if (running) {
    pending = true;
    return;
  }
  running = true;
  try {
    await runAutoSwitch();
  } finally {
    running = false;
    if (pending) {
      pending = false;
      scheduleCheck();
    }
  }
}

export function scheduleCheck(): void {
  if (debounceTimer >= 0) {
    clearTimeout(debounceTimer);
  }
  debounceTimer = setTimeout((): void => {
    debounceTimer = -1;
    void runGuarded();
  }, DEBOUNCE_MS);
}

function onNetEvent(): void {
  hilog.info(DOMAIN, TAG, 'network changed, schedule endpoint reselect');
  scheduleCheck();
}

export function ensureStarted(ctx: common.UIAbilityContext): void {
  abilityContext = ctx;
  ensureEndpointSwitchStorage();
  if (netConnection !== null) {
    return;
  }
  try {
    const netCon = connection.createNetConnection();
    netCon.on('netAvailable', (_data: connection.NetHandle) => {
      onNetEvent();
    });
    netCon.on('netLost', (_data: connection.NetHandle) => {
      onNetEvent();
    });
    netCon.on('netCapabilitiesChange', (_data: connection.NetCapabilityInfo) => {
      onNetEvent();
    });
    netCon.register((err: BusinessError) => {
      if (err !== undefined && err !== null && err.code !== 0) {
        hilog.warn(DOMAIN, TAG, 'net register failed %{public}d', err.code);
      }
    });
    netConnection = netCon;
    hilog.info(DOMAIN, TAG, 'network listener registered');
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'start listener failed: %{public}s', String(e));
  }
}

export function stop(): void {
  if (debounceTimer >= 0) {
    clearTimeout(debounceTimer);
    debounceTimer = -1;
  }
  const netCon = netConnection;
  netConnection = null;
  abilityContext = null;
  if (netCon === null) {
    return;
  }
  try {
    netCon.unregister((err: BusinessError) => {
      if (err !== undefined && err !== null && err.code !== 0) {
        hilog.warn(DOMAIN, TAG, 'net unregister failed %{public}d', err.code);
      }
    });
  } catch (_e) {
  }
}
