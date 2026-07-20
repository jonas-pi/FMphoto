/**
 * 登录前选路：短超时并行探测；公网拆成「域名 / IP」双候选，都通则优先域名。
 */
import { http } from '@kit.NetworkKit';
import { extractFnId, isFnRelayBaseUrl } from './FnConnectApi';
import { preferPublicEndpointUrl } from './PublicDns';
import { normalizeServerUrl } from './ServerUrl';

export const LOGIN_ENDPOINT_PREF_AUTO = 'auto';
export const LOGIN_ENDPOINT_PREF_PUBLIC = 'public';
export const LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN = 'public_domain';
export const LOGIN_ENDPOINT_PREF_PUBLIC_IP = 'public_ip';
export const LOGIN_ENDPOINT_PREF_LAN = 'lan';
export const LOGIN_ENDPOINT_PREF_RELAY = 'relay';
export const LOGIN_ENDPOINT_PREF_BANDWIDTH = 'bandwidth';
export const LOGIN_ENDPOINT_PREF_LATENCY = 'latency';

/** 连通性探测：短超时，只确认可达（官方竞速思路） */
const FAST_CONNECT_TIMEOUT_MS = 1600;
const FAST_READ_TIMEOUT_MS = 1600;
const FAST_MAX_BYTES = 8 * 1024;
/** 带宽测速仅在「带宽优先」时使用 */
const BW_CONNECT_TIMEOUT_MS = 4500;
const BW_READ_TIMEOUT_MS = 4500;
const BW_MAX_BYTES = 512 * 1024;

export interface LoginEndpointCandidate {
  kind: string;
  baseUrl: string;
}

export interface LoginEndpointProbeResult {
  candidate: LoginEndpointCandidate;
  ok: boolean;
  latencyMs: number;
  bytesPerSecond: number;
  score: number;
  message: string;
}

export interface LoginEndpointSelectionResult {
  server: string;
  summary: string;
  /** 「我的」公网切换用：域名优先于 IP */
  preferredPublicUrl: string;
}

function endpointLabel(kind: string): string {
  if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    return '内网';
  }
  if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
    return '中继';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
    return '公网域名';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
    return '公网IP';
  }
  return '公网';
}

function kindPriority(kind: string): number {
  if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    return 0;
  }
  // 公网域名优于公网 IP
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN || kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    return 1;
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
    return 2;
  }
  if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
    return 3;
  }
  return 9;
}

function isPublicKind(kind: string): boolean {
  return kind === LOGIN_ENDPOINT_PREF_PUBLIC ||
    kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN ||
    kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP;
}

function byteLengthOfResult(result: string | ArrayBuffer | object | undefined): number {
  if (result === undefined || result === null) {
    return 0;
  }
  if (typeof result === 'string') {
    return result.length;
  }
  if (result instanceof ArrayBuffer) {
    return result.byteLength;
  }
  try {
    return JSON.stringify(result).length;
  } catch (_e) {
    return 0;
  }
}

async function probeEndpoint(
  candidate: LoginEndpointCandidate,
  bandwidthMode: boolean
): Promise<LoginEndpointProbeResult> {
  const req = http.createHttp();
  const startedAt = Date.now();
  // 中继：官方门户 HTML 恒为 200，改探测 {fnId}.fnos.net/trimcon（与 Connect SPA 一致）
  let probeUrl = `${candidate.baseUrl}/`;
  if (candidate.kind === LOGIN_ENDPOINT_PREF_RELAY || isFnRelayBaseUrl(candidate.baseUrl)) {
    const id = extractFnId(candidate.baseUrl);
    if (id.length > 0) {
      probeUrl = `https://${id}.fnos.net/trimcon`;
    }
  }
  try {
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: bandwidthMode ? BW_CONNECT_TIMEOUT_MS : FAST_CONNECT_TIMEOUT_MS,
      readTimeout: bandwidthMode ? BW_READ_TIMEOUT_MS : FAST_READ_TIMEOUT_MS,
      maxLimit: bandwidthMode ? BW_MAX_BYTES : FAST_MAX_BYTES
    };
    opt.remoteValidation = 'skip';
    const resp = await req.request(probeUrl, opt);
    const elapsed = Math.max(1, Date.now() - startedAt);
    const bytes = byteLengthOfResult(resp.result as string | ArrayBuffer | object | undefined);
    const bps = Math.floor(bytes * 1000 / elapsed);
    const ok = resp.responseCode >= 200 && resp.responseCode < 500;
    return {
      candidate,
      ok,
      latencyMs: elapsed,
      bytesPerSecond: bps,
      score: 0,
      message: ok ? '' : `HTTP ${resp.responseCode}`
    };
  } catch (e) {
    return {
      candidate,
      ok: false,
      latencyMs: Date.now() - startedAt,
      bytesPerSecond: 0,
      score: 0,
      message: String(e)
    };
  } finally {
    try {
      req.destroy();
    } catch (_e) {
    }
  }
}

function assignScores(
  results: LoginEndpointProbeResult[],
  preference: string
): LoginEndpointProbeResult[] {
  const okResults = results.filter((r: LoginEndpointProbeResult) => r.ok);
  let bestLatency = Number.MAX_SAFE_INTEGER;
  let bestBandwidth = 0;
  for (let i = 0; i < okResults.length; i++) {
    bestLatency = Math.min(bestLatency, Math.max(1, okResults[i].latencyMs));
    bestBandwidth = Math.max(bestBandwidth, okResults[i].bytesPerSecond);
  }
  const latencyWeight = preference === LOGIN_ENDPOINT_PREF_LATENCY ? 0.82 : 0.7;
  const bandwidthWeight = preference === LOGIN_ENDPOINT_PREF_BANDWIDTH ? 0.82 : 0.15;
  const typeWeight = preference === LOGIN_ENDPOINT_PREF_BANDWIDTH ? 0.05 : 0.15;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      r.score = -1;
      continue;
    }
    const latencyScore = bestLatency / Math.max(1, r.latencyMs);
    const bandwidthScore = bestBandwidth > 0 ? r.bytesPerSecond / bestBandwidth : 0;
    const typeScore = 1 - kindPriority(r.candidate.kind) * 0.1;
    r.score = latencyScore * latencyWeight + bandwidthScore * bandwidthWeight + typeScore * typeWeight;
  }
  return results;
}

function pickBest(results: LoginEndpointProbeResult[]): LoginEndpointProbeResult | null {
  let best: LoginEndpointProbeResult | null = null;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      continue;
    }
    if (best === null || r.score > best.score) {
      best = r;
    }
  }
  return best;
}

/** 公网域名与公网 IP 都通时，强制优先域名 */
function preferDomainIfBothPublicOk(
  results: LoginEndpointProbeResult[],
  best: LoginEndpointProbeResult
): LoginEndpointProbeResult {
  if (!isPublicKind(best.candidate.kind)) {
    return best;
  }
  let domainOk: LoginEndpointProbeResult | null = null;
  let ipOk: LoginEndpointProbeResult | null = null;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      continue;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
      domainOk = r;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
      ipOk = r;
    }
  }
  if (domainOk !== null && ipOk !== null) {
    return domainOk;
  }
  return best;
}

function describeProbeChoice(best: LoginEndpointProbeResult, all: LoginEndpointProbeResult[]): string {
  const parts: string[] = [];
  for (let i = 0; i < all.length; i++) {
    const r = all[i];
    if (!r.ok) {
      parts.push(`${endpointLabel(r.candidate.kind)}不可用`);
      continue;
    }
    parts.push(`${endpointLabel(r.candidate.kind)}${r.latencyMs}ms`);
  }
  return `已选择${endpointLabel(best.candidate.kind)}（${parts.join('，')}）`;
}

function buildCandidates(
  publicDomainUrl: string,
  publicIpUrl: string,
  lanUrl: string,
  relayUrl: string
): LoginEndpointCandidate[] {
  const out: LoginEndpointCandidate[] = [];
  const seen: string[] = [];
  const push = (kind: string, url: string): void => {
    const u = url.trim();
    if (u.length === 0) {
      return;
    }
    for (let i = 0; i < seen.length; i++) {
      if (seen[i] === u) {
        return;
      }
    }
    seen.push(u);
    out.push({ kind, baseUrl: u });
  };
  push(LOGIN_ENDPOINT_PREF_LAN, lanUrl);
  push(LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN, publicDomainUrl);
  push(LOGIN_ENDPOINT_PREF_PUBLIC_IP, publicIpUrl);
  // 中继暂不参与选路（官方隧道未对第三方开放）
  return out;
}

function pickForced(
  candidates: LoginEndpointCandidate[],
  preference: string
): LoginEndpointSelectionResult | null {
  if (preference === LOGIN_ENDPOINT_PREF_LAN) {
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].kind === preference) {
        return {
          server: candidates[i].baseUrl,
          summary: `已按偏好使用${endpointLabel(preference)}地址`,
          preferredPublicUrl: preferPublicFromCandidates(candidates)
        };
      }
    }
  }
  if (preference === LOGIN_ENDPOINT_PREF_PUBLIC) {
    // 优先公网域名，其次公网 IP
    for (let i = 0; i < candidates.length; i++) {
      if (candidates[i].kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
        return {
          server: candidates[i].baseUrl,
          summary: '已按偏好使用公网域名',
          preferredPublicUrl: candidates[i].baseUrl
        };
      }
    }
    for (let j = 0; j < candidates.length; j++) {
      if (candidates[j].kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
        return {
          server: candidates[j].baseUrl,
          summary: '已按偏好使用公网IP',
          preferredPublicUrl: candidates[j].baseUrl
        };
      }
    }
  }
  return null;
}

function preferPublicFromCandidates(candidates: LoginEndpointCandidate[]): string {
  let domain = '';
  let ip = '';
  for (let i = 0; i < candidates.length; i++) {
    if (candidates[i].kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
      domain = candidates[i].baseUrl;
    }
    if (candidates[i].kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
      ip = candidates[i].baseUrl;
    }
  }
  return preferPublicEndpointUrl(domain, ip);
}

function preferredPublicFromProbes(
  results: LoginEndpointProbeResult[],
  publicDomainUrl: string,
  publicIpUrl: string
): string {
  let domainOk = false;
  let ipOk = false;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      continue;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
      domainOk = true;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
      ipOk = true;
    }
  }
  if (domainOk) {
    return publicDomainUrl.trim();
  }
  if (ipOk) {
    return publicIpUrl.trim();
  }
  return preferPublicEndpointUrl(publicDomainUrl, publicIpUrl);
}

/**
 * 在公网域名 / 公网 IP / 内网 / 中继中并行短探测选路。
 */
export async function selectAmongEndpoints(
  publicDomainUrl: string,
  publicIpUrl: string,
  lanUrl: string,
  relayUrl: string,
  preference: string
): Promise<LoginEndpointSelectionResult> {
  const candidates = buildCandidates(publicDomainUrl, publicIpUrl, lanUrl, relayUrl);
  const fallbackPublic = preferPublicEndpointUrl(publicDomainUrl, publicIpUrl);
  if (candidates.length === 0) {
    return { server: '', summary: '', preferredPublicUrl: '' };
  }
  if (candidates.length === 1) {
    return {
      server: candidates[0].baseUrl,
      summary: '',
      preferredPublicUrl: isPublicKind(candidates[0].kind) ? candidates[0].baseUrl : fallbackPublic
    };
  }
  const forced = pickForced(candidates, preference);
  if (forced !== null) {
    return forced;
  }

  const bandwidthMode = preference === LOGIN_ENDPOINT_PREF_BANDWIDTH;
  const probed = await Promise.all(
    candidates.map((c: LoginEndpointCandidate) => probeEndpoint(c, bandwidthMode))
  );
  const scored = assignScores(probed, preference);
  let best = pickBest(scored);
  if (best === null) {
    return {
      server: candidates[0].baseUrl,
      summary: '连通性探测均失败，已按优先级尝试',
      preferredPublicUrl: fallbackPublic
    };
  }
  best = preferDomainIfBothPublicOk(scored, best);
  return {
    server: best.candidate.baseUrl,
    summary: describeProbeChoice(best, scored),
    preferredPublicUrl: preferredPublicFromProbes(scored, publicDomainUrl, publicIpUrl)
  };
}

/**
 * 双地址选路（兼容旧登录：公网栏 + 内网栏）。
 * 公网栏若是域名，调用方应先拆出 domain/ip 再走 selectAmongEndpoints。
 */
export async function selectLoginEndpoint(
  publicInput: string,
  lanInput: string,
  useHttps: boolean,
  preference: string
): Promise<LoginEndpointSelectionResult> {
  const publicServer = normalizeServerUrl(publicInput, useHttps);
  const lanServer = normalizeServerUrl(lanInput, useHttps);
  if (lanServer.length === 0 || publicServer === lanServer) {
    return {
      server: publicServer.length > 0 ? publicServer : lanServer,
      summary: '',
      preferredPublicUrl: publicServer
    };
  }
  if (publicServer.length === 0) {
    return { server: lanServer, summary: '', preferredPublicUrl: '' };
  }
  return selectAmongEndpoints(publicServer, '', lanServer, '', preference);
}
