/**
 * 登录前选路：短超时并行探测；公网拆成「域名 / IP」双候选，都通则优先域名。
 * 中继走云端 `fn` 主机（可能是 *.fnos.net 或 *.5ddd.com），第三方 WSS 可被反代转发。
 */
import { http } from '@kit.NetworkKit';
import { fnRelayProbeUrl, isFnRelayBaseUrl } from './FnConnectApi';
import { preferPublicEndpointUrl } from './PublicDns';
import { normalizeServerUrl } from './ServerUrl';

export const LOGIN_ENDPOINT_PREF_AUTO = 'auto';
export const LOGIN_ENDPOINT_PREF_PUBLIC = 'public';
export const LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN = 'public_domain';
export const LOGIN_ENDPOINT_PREF_PUBLIC_IP = 'public_ip';
export const LOGIN_ENDPOINT_PREF_PUBLIC_IPV6 = 'public_ipv6';
export const LOGIN_ENDPOINT_PREF_LAN = 'lan';
export const LOGIN_ENDPOINT_PREF_LAN_IPV6 = 'lan_ipv6';
export const LOGIN_ENDPOINT_PREF_RELAY = 'relay';
export const LOGIN_ENDPOINT_PREF_BANDWIDTH = 'bandwidth';
export const LOGIN_ENDPOINT_PREF_LATENCY = 'latency';

export interface LoginEndpointPool {
  lanIpv4Url: string;
  lanIpv6Url: string;
  publicDomainUrl: string;
  publicIpv4Url: string;
  publicIpv6Url: string;
  /** FN Connect 官方中继，仅作内网/公网都不可达时的兜底 */
  relayUrl: string;
}

export function emptyEndpointPool(): LoginEndpointPool {
  return {
    lanIpv4Url: '',
    lanIpv6Url: '',
    publicDomainUrl: '',
    publicIpv4Url: '',
    publicIpv6Url: '',
    relayUrl: ''
  };
}

/** 连通性探测：短超时，只确认可达（官方竞速思路） */
const FAST_CONNECT_TIMEOUT_MS = 1600;
const FAST_READ_TIMEOUT_MS = 1600;
const FAST_MAX_BYTES = 8 * 1024;
/** 带宽测速仅在「带宽优先」时使用 */
const BW_CONNECT_TIMEOUT_MS = 4500;
const BW_READ_TIMEOUT_MS = 4500;
const BW_MAX_BYTES = 512 * 1024;
/** 中继隧道 DNS 可能短暂 NXDOMAIN；直连都失败后再短重试，不拖慢内网/公网选路 */
const RELAY_PROBE_EXTRA_ATTEMPTS = 3;
const RELAY_PROBE_RETRY_DELAY_MS = 1200;

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

export interface LoginEndpointProbeLine {
  label: string;
  address: string;
  baseUrl: string;
  ok: boolean;
  latencyMs: number;
  selected: boolean;
}

export interface LoginEndpointSelectionResult {
  server: string;
  summary: string;
  /** 「我的」公网切换用：域名优先于 IP */
  preferredPublicUrl: string;
  selectedKind: string;
  selectedLabel: string;
  selectedAddress: string;
  selectedOk: boolean;
  selectedLatencyMs: number;
  probeLines: LoginEndpointProbeLine[];
}

function endpointLabel(kind: string): string {
  if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    return '内网';
  }
  if (kind === LOGIN_ENDPOINT_PREF_LAN_IPV6) {
    return '内网IPv6';
  }
  if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
    return '中继';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
    return '公网域名';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
    return '公网IPv4';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_IPV6) {
    return '公网IPv6';
  }
  return '公网';
}

function kindPriority(kind: string): number {
  if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    return 0;
  }
  if (kind === LOGIN_ENDPOINT_PREF_LAN_IPV6) {
    return 1;
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN || kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    return 2;
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
    return 3;
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC_IPV6) {
    return 4;
  }
  if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
    return 5;
  }
  return 9;
}

function isPublicKind(kind: string): boolean {
  return kind === LOGIN_ENDPOINT_PREF_PUBLIC ||
    kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN ||
    kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP ||
    kind === LOGIN_ENDPOINT_PREF_PUBLIC_IPV6;
}

function isLanKind(kind: string): boolean {
  return kind === LOGIN_ENDPOINT_PREF_LAN || kind === LOGIN_ENDPOINT_PREF_LAN_IPV6;
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

function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

async function probeEndpoint(
  candidate: LoginEndpointCandidate,
  bandwidthMode: boolean,
  probeTimeoutMs: number = 0
): Promise<LoginEndpointProbeResult> {
  const req = http.createHttp();
  const startedAt = Date.now();
  // 中继：门户 HTML 恒 200，改探测云端 fn 主机上的 /trimcon（保留 fnos.net / 5ddd.com 原集群）
  let probeUrl = `${candidate.baseUrl}/`;
  if (candidate.kind === LOGIN_ENDPOINT_PREF_RELAY || isFnRelayBaseUrl(candidate.baseUrl)) {
    const relayProbe = fnRelayProbeUrl(candidate.baseUrl);
    if (relayProbe.length > 0) {
      probeUrl = relayProbe;
    }
  }
  try {
    let connectTimeout = bandwidthMode ? BW_CONNECT_TIMEOUT_MS : FAST_CONNECT_TIMEOUT_MS;
    let readTimeout = bandwidthMode ? BW_READ_TIMEOUT_MS : FAST_READ_TIMEOUT_MS;
    if (probeTimeoutMs > 0 && !bandwidthMode) {
      connectTimeout = probeTimeoutMs;
      readTimeout = probeTimeoutMs;
    }
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout,
      readTimeout,
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

function isRelayKind(kind: string): boolean {
  return kind === LOGIN_ENDPOINT_PREF_RELAY;
}

/** 自动选路或手动选中继时，才为中继 DNS 做额外等待 */
function shouldRetryRelayProbe(preference: string): boolean {
  return preference === LOGIN_ENDPOINT_PREF_RELAY
    || preference === LOGIN_ENDPOINT_PREF_AUTO
    || preference === LOGIN_ENDPOINT_PREF_BANDWIDTH
    || preference === LOGIN_ENDPOINT_PREF_LATENCY
    || preference.length === 0;
}

function findRelayCandidate(candidates: LoginEndpointCandidate[]): LoginEndpointCandidate | null {
  for (let i = 0; i < candidates.length; i++) {
    if (isRelayKind(candidates[i].kind) || isFnRelayBaseUrl(candidates[i].baseUrl)) {
      return candidates[i];
    }
  }
  return null;
}

function replaceRelayProbe(
  scored: LoginEndpointProbeResult[],
  retried: LoginEndpointProbeResult
): LoginEndpointProbeResult[] {
  const out: LoginEndpointProbeResult[] = [];
  let replaced = false;
  for (let i = 0; i < scored.length; i++) {
    if (!replaced && isRelayKind(scored[i].candidate.kind)) {
      out.push(retried);
      replaced = true;
    } else {
      out.push(scored[i]);
    }
  }
  if (!replaced) {
    out.push(retried);
  }
  return out;
}

/** 并行探测失败后，再给中继几次短间隔机会（隧道 DNS 晚于直连探测结束） */
async function retryRelayProbe(
  candidate: LoginEndpointCandidate,
  bandwidthMode: boolean,
  probeTimeoutMs: number
): Promise<LoginEndpointProbeResult> {
  let last: LoginEndpointProbeResult = {
    candidate,
    ok: false,
    latencyMs: 0,
    bytesPerSecond: 0,
    score: 0,
    message: ''
  };
  for (let i = 0; i < RELAY_PROBE_EXTRA_ATTEMPTS; i++) {
    await delayMs(RELAY_PROBE_RETRY_DELAY_MS);
    last = await probeEndpoint(candidate, bandwidthMode, probeTimeoutMs);
    if (last.ok) {
      return last;
    }
  }
  return last;
}

function pickBest(results: LoginEndpointProbeResult[]): LoginEndpointProbeResult | null {
  let bestDirect: LoginEndpointProbeResult | null = null;
  let bestRelay: LoginEndpointProbeResult | null = null;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      continue;
    }
    // 中继只作兜底：只要内网/公网任一可达，就不选中继
    if (isRelayKind(r.candidate.kind)) {
      if (bestRelay === null || r.score > bestRelay.score) {
        bestRelay = r;
      }
      continue;
    }
    if (bestDirect === null || r.score > bestDirect.score) {
      bestDirect = r;
    }
  }
  return bestDirect !== null ? bestDirect : bestRelay;
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
  let ipv6Ok: LoginEndpointProbeResult | null = null;
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
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_IPV6) {
      ipv6Ok = r;
    }
  }
  if (domainOk !== null && ipOk !== null) {
    return domainOk;
  }
  if (domainOk !== null && ipv6Ok !== null) {
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

function buildCandidatesFromPool(pool: LoginEndpointPool): LoginEndpointCandidate[] {
  const out: LoginEndpointCandidate[] = [];
  const seen: string[] = [];
  const push = (kind: string, url: string): void => {
    const u = url.trim();
    if (u.length === 0) {
      return;
    }
    // 中继即使与公网 DDNS 同主机也要单独成行，否则「我的」探测列表看不到中继
    if (kind !== LOGIN_ENDPOINT_PREF_RELAY) {
      for (let i = 0; i < seen.length; i++) {
        if (seen[i] === u) {
          return;
        }
      }
      seen.push(u);
    } else {
      for (let j = 0; j < out.length; j++) {
        if (out[j].kind === LOGIN_ENDPOINT_PREF_RELAY && out[j].baseUrl === u) {
          return;
        }
      }
    }
    out.push({ kind, baseUrl: u });
  };
  push(LOGIN_ENDPOINT_PREF_LAN, pool.lanIpv4Url);
  push(LOGIN_ENDPOINT_PREF_LAN_IPV6, pool.lanIpv6Url);
  push(LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN, pool.publicDomainUrl);
  push(LOGIN_ENDPOINT_PREF_PUBLIC_IP, pool.publicIpv4Url);
  push(LOGIN_ENDPOINT_PREF_PUBLIC_IPV6, pool.publicIpv6Url);
  push(LOGIN_ENDPOINT_PREF_RELAY, pool.relayUrl);
  return out;
}

function hasRelayProbeLine(lines: LoginEndpointProbeLine[]): boolean {
  const relayLabel = endpointLabel(LOGIN_ENDPOINT_PREF_RELAY);
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].label === relayLabel) {
      return true;
    }
  }
  return false;
}

/** 会话里有中继地址时，探测结果必须带上中继行 */
function ensureRelayProbeLine(
  lines: LoginEndpointProbeLine[],
  pool: LoginEndpointPool,
  scored: LoginEndpointProbeResult[]
): LoginEndpointProbeLine[] {
  const relayUrl = pool.relayUrl.trim();
  if (relayUrl.length === 0 || hasRelayProbeLine(lines)) {
    return lines;
  }
  let ok = false;
  let latencyMs = 0;
  for (let i = 0; i < scored.length; i++) {
    if (isRelayKind(scored[i].candidate.kind) || scored[i].candidate.baseUrl === relayUrl) {
      ok = scored[i].ok;
      latencyMs = scored[i].ok ? scored[i].latencyMs : 0;
      break;
    }
  }
  const extra: LoginEndpointProbeLine[] = [];
  for (let j = 0; j < lines.length; j++) {
    extra.push(lines[j]);
  }
  extra.push({
    label: endpointLabel(LOGIN_ENDPOINT_PREF_RELAY),
    address: compactProbeAddress(relayUrl),
    baseUrl: relayUrl,
    ok,
    latencyMs,
    selected: false
  });
  return extra;
}

function filterCandidatesByPreference(
  candidates: LoginEndpointCandidate[],
  preference: string
): LoginEndpointCandidate[] {
  if (preference === LOGIN_ENDPOINT_PREF_LAN) {
    const lanOnly: LoginEndpointCandidate[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (isLanKind(candidates[i].kind)) {
        lanOnly.push(candidates[i]);
      }
    }
    return lanOnly.length > 0 ? lanOnly : candidates;
  }
  if (preference === LOGIN_ENDPOINT_PREF_PUBLIC) {
    const publicOnly: LoginEndpointCandidate[] = [];
    for (let j = 0; j < candidates.length; j++) {
      if (isPublicKind(candidates[j].kind)) {
        publicOnly.push(candidates[j]);
      }
    }
    return publicOnly.length > 0 ? publicOnly : candidates;
  }
  if (preference === LOGIN_ENDPOINT_PREF_RELAY) {
    const relayOnly: LoginEndpointCandidate[] = [];
    for (let k = 0; k < candidates.length; k++) {
      if (isRelayKind(candidates[k].kind)) {
        relayOnly.push(candidates[k]);
      }
    }
    return relayOnly.length > 0 ? relayOnly : candidates;
  }
  return candidates;
}

function preferPublicFromCandidates(candidates: LoginEndpointCandidate[]): string {
  let domain = '';
  let ipv4 = '';
  let ipv6 = '';
  for (let i = 0; i < candidates.length; i++) {
    if (candidates[i].kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
      domain = candidates[i].baseUrl;
    }
    if (candidates[i].kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
      ipv4 = candidates[i].baseUrl;
    }
    if (candidates[i].kind === LOGIN_ENDPOINT_PREF_PUBLIC_IPV6) {
      ipv6 = candidates[i].baseUrl;
    }
  }
  if (domain.length > 0) {
    return domain;
  }
  return preferPublicEndpointUrl(ipv4, ipv6);
}

function preferredPublicFromProbes(
  results: LoginEndpointProbeResult[],
  pool: LoginEndpointPool
): string {
  let domainOk = false;
  let ipv4Ok = false;
  let ipv6Ok = false;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      continue;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_DOMAIN) {
      domainOk = true;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_IP) {
      ipv4Ok = true;
    }
    if (r.candidate.kind === LOGIN_ENDPOINT_PREF_PUBLIC_IPV6) {
      ipv6Ok = true;
    }
  }
  if (domainOk) {
    return pool.publicDomainUrl.trim();
  }
  if (ipv4Ok) {
    return pool.publicIpv4Url.trim();
  }
  if (ipv6Ok) {
    return pool.publicIpv6Url.trim();
  }
  return preferPublicFromPool(pool);
}

function preferPublicFromPool(pool: LoginEndpointPool): string {
  if (pool.publicDomainUrl.trim().length > 0) {
    return pool.publicDomainUrl.trim();
  }
  return preferPublicEndpointUrl(pool.publicIpv4Url, pool.publicIpv6Url);
}

export function compactProbeAddress(baseUrl: string): string {
  let u = baseUrl.trim();
  if (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.startsWith('https://')) {
    u = u.substring('https://'.length);
  } else if (u.startsWith('http://')) {
    u = u.substring('http://'.length);
  }
  return u;
}

function emptyProbeLines(): LoginEndpointProbeLine[] {
  return [];
}

function emptySelection(): LoginEndpointSelectionResult {
  return {
    server: '',
    summary: '',
    preferredPublicUrl: '',
    selectedKind: '',
    selectedLabel: '',
    selectedAddress: '',
    selectedOk: false,
    selectedLatencyMs: 0,
    probeLines: emptyProbeLines()
  };
}

function selectionFromCandidate(
  kind: string,
  server: string,
  preferredPublicUrl: string,
  summary: string
): LoginEndpointSelectionResult {
  const label = endpointLabel(kind);
  const address = compactProbeAddress(server);
  const lines: LoginEndpointProbeLine[] = [];
  if (server.length > 0) {
    lines.push({
      label,
      address,
      baseUrl: server,
      ok: true,
      latencyMs: 0,
      selected: true
    });
  }
  return {
    server,
    summary,
    preferredPublicUrl,
    selectedKind: kind,
    selectedLabel: label,
    selectedAddress: address,
    selectedOk: server.length > 0,
    selectedLatencyMs: 0,
    probeLines: lines
  };
}

function selectionFromProbes(
  best: LoginEndpointProbeResult,
  all: LoginEndpointProbeResult[],
  preferredPublicUrl: string,
  summary: string
): LoginEndpointSelectionResult {
  const lines: LoginEndpointProbeLine[] = [];
  for (let i = 0; i < all.length; i++) {
    const r = all[i];
    const selected = r.candidate.kind === best.candidate.kind &&
      r.candidate.baseUrl === best.candidate.baseUrl;
    lines.push({
      label: endpointLabel(r.candidate.kind),
      address: compactProbeAddress(r.candidate.baseUrl),
      baseUrl: r.candidate.baseUrl,
      ok: r.ok,
      latencyMs: r.ok ? r.latencyMs : 0,
      selected
    });
  }
  return {
    server: best.candidate.baseUrl,
    summary,
    preferredPublicUrl,
    selectedKind: best.candidate.kind,
    selectedLabel: endpointLabel(best.candidate.kind),
    selectedAddress: compactProbeAddress(best.candidate.baseUrl),
    selectedOk: best.ok,
    selectedLatencyMs: best.ok ? best.latencyMs : 0,
    probeLines: lines
  };
}

/**
 * 在内网 V4/V6、公网域名 / IPv4 / IPv6、官方中继中并行短探测选路。
 * 中继优先级最低：仅当直连候选都不可达时选用。
 */
export async function selectAmongEndpointPool(
  pool: LoginEndpointPool,
  preference: string,
  probeTimeoutMs: number = 0
): Promise<LoginEndpointSelectionResult> {
  const all = buildCandidatesFromPool(pool);
  const fallbackPublic = preferPublicFromPool(pool);
  if (all.length === 0) {
    return emptySelection();
  }
  const candidates = filterCandidatesByPreference(all, preference);
  if (candidates.length === 0) {
    return emptySelection();
  }
  // 单条候选也探测，便于登录页展示路径与延迟
  const bandwidthMode = preference === LOGIN_ENDPOINT_PREF_BANDWIDTH;
  const probed = await Promise.all(
    candidates.map((c: LoginEndpointCandidate) => probeEndpoint(c, bandwidthMode, probeTimeoutMs))
  );
  let scored = assignScores(probed, preference);
  let best = pickBest(scored);
  // 直连都失败时：中继 DNS 可能尚未就绪，短间隔再探，不臆造其它集群
  if (best === null && shouldRetryRelayProbe(preference)) {
    const relayCand = findRelayCandidate(candidates);
    if (relayCand !== null) {
      const retried = await retryRelayProbe(relayCand, bandwidthMode, probeTimeoutMs);
      scored = assignScores(replaceRelayProbe(scored, retried), preference);
      if (retried.ok) {
        best = pickBest(scored);
      }
    }
  }
  if (best === null) {
    // 全部探测失败：自动选路不把尚未可达的中继交给 WSS；手动点中继仍试一次
    let fallbackBest: LoginEndpointProbeResult = scored.length > 0 ? scored[0] : {
      candidate: candidates[0],
      ok: false,
      latencyMs: 0,
      bytesPerSecond: 0,
      score: -1,
      message: ''
    };
    for (let i = 0; i < scored.length; i++) {
      if (isRelayKind(scored[i].candidate.kind)) {
        fallbackBest = scored[i];
        break;
      }
    }
    const failed = selectionFromProbes(
      fallbackBest,
      scored.length > 0 ? scored : [fallbackBest],
      fallbackPublic,
      '公网、内网与官方中继均不可达'
    );
    failed.probeLines = ensureRelayProbeLine(failed.probeLines, pool, scored);
    if (preference !== LOGIN_ENDPOINT_PREF_RELAY) {
      failed.server = '';
    }
    return failed;
  }
  best = preferDomainIfBothPublicOk(scored, best);
  const selected = selectionFromProbes(
    best,
    scored,
    preferredPublicFromProbes(scored, pool),
    describeProbeChoice(best, scored)
  );
  selected.probeLines = ensureRelayProbeLine(selected.probeLines, pool, scored);
  return selected;
}

/**
 * 在公网域名 / 公网 IP / 内网中并行短探测选路。
 */
export async function selectAmongEndpoints(
  publicDomainUrl: string,
  publicIpUrl: string,
  lanUrl: string,
  relayUrl: string,
  preference: string
): Promise<LoginEndpointSelectionResult> {
  return selectAmongEndpointPool({
    lanIpv4Url: lanUrl,
    lanIpv6Url: '',
    publicDomainUrl: publicDomainUrl,
    publicIpv4Url: publicIpUrl,
    publicIpv6Url: '',
    relayUrl: relayUrl
  }, preference);
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
    const server = publicServer.length > 0 ? publicServer : lanServer;
    const kind = publicServer.length > 0 ? LOGIN_ENDPOINT_PREF_PUBLIC : LOGIN_ENDPOINT_PREF_LAN;
    return selectionFromCandidate(kind, server, publicServer, '');
  }
  if (publicServer.length === 0) {
    return selectionFromCandidate(LOGIN_ENDPOINT_PREF_LAN, lanServer, '', '');
  }
  return selectAmongEndpoints(publicServer, '', lanServer, '', preference);
}
