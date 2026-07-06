import { http } from '@kit.NetworkKit';
import { normalizeServerUrl } from './ServerUrl';

export const LOGIN_ENDPOINT_PREF_AUTO = 'auto';
export const LOGIN_ENDPOINT_PREF_PUBLIC = 'public';
export const LOGIN_ENDPOINT_PREF_LAN = 'lan';
export const LOGIN_ENDPOINT_PREF_BANDWIDTH = 'bandwidth';
export const LOGIN_ENDPOINT_PREF_LATENCY = 'latency';

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
}

function endpointLabel(kind: string): string {
  return kind === LOGIN_ENDPOINT_PREF_LAN ? '内网' : '公网';
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

async function probeEndpoint(candidate: LoginEndpointCandidate): Promise<LoginEndpointProbeResult> {
  const req = http.createHttp();
  const startedAt = Date.now();
  try {
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 4500,
      readTimeout: 4500,
      maxLimit: 512 * 1024
    };
    // 测速不携带凭据，只用于比较公网/内网可达性；真正登录仍由原 WS 流程处理证书信任确认。
    opt.remoteValidation = 'skip';
    const resp = await req.request(`${candidate.baseUrl}/`, opt);
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
  const latencyWeight = preference === LOGIN_ENDPOINT_PREF_LATENCY ? 0.82 : 0.56;
  const bandwidthWeight = preference === LOGIN_ENDPOINT_PREF_BANDWIDTH ? 0.82 : 0.44;
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (!r.ok) {
      r.score = -1;
      continue;
    }
    const latencyScore = bestLatency / Math.max(1, r.latencyMs);
    const bandwidthScore = bestBandwidth > 0 ? r.bytesPerSecond / bestBandwidth : 0;
    r.score = latencyScore * latencyWeight + bandwidthScore * bandwidthWeight;
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

function describeProbeChoice(best: LoginEndpointProbeResult, all: LoginEndpointProbeResult[]): string {
  const parts: string[] = [];
  for (let i = 0; i < all.length; i++) {
    const r = all[i];
    if (!r.ok) {
      parts.push(`${endpointLabel(r.candidate.kind)}不可用`);
      continue;
    }
    const kb = r.bytesPerSecond > 0 ? Math.round(r.bytesPerSecond / 1024) : 0;
    parts.push(`${endpointLabel(r.candidate.kind)}${r.latencyMs}ms/${kb}KB/s`);
  }
  return `已选择${endpointLabel(best.candidate.kind)}地址（${parts.join('，')}）`;
}

export async function selectLoginEndpoint(
  publicInput: string,
  lanInput: string,
  useHttps: boolean,
  preference: string
): Promise<LoginEndpointSelectionResult> {
  const publicServer = normalizeServerUrl(publicInput, useHttps);
  const lanServer = normalizeServerUrl(lanInput, useHttps);
  if (lanServer.length === 0 || publicServer === lanServer) {
    return { server: publicServer, summary: '' };
  }
  if (publicServer.length === 0) {
    return { server: lanServer, summary: '' };
  }
  if (preference === LOGIN_ENDPOINT_PREF_PUBLIC) {
    return { server: publicServer, summary: '已按偏好使用公网地址' };
  }
  if (preference === LOGIN_ENDPOINT_PREF_LAN) {
    return { server: lanServer, summary: '已按偏好使用内网地址' };
  }
  const candidates: LoginEndpointCandidate[] = [
    { kind: LOGIN_ENDPOINT_PREF_PUBLIC, baseUrl: publicServer },
    { kind: LOGIN_ENDPOINT_PREF_LAN, baseUrl: lanServer }
  ];
  const probed = await Promise.all([
    probeEndpoint(candidates[0]),
    probeEndpoint(candidates[1])
  ]);
  const scored = assignScores(probed, preference);
  const best = pickBest(scored);
  if (best === null) {
    return { server: publicServer, summary: '测速失败，已回退使用公网地址' };
  }
  return { server: best.candidate.baseUrl, summary: describeProbeChoice(best, scored) };
}
