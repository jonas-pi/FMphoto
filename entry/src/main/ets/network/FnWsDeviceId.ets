/**
 * 飞牛 WebSocket 登录设备标识（did）。
 * 「信任本设备」依赖同一 did 在 user.login 与 user.2fa.loginVerify 中一致，并跨会话持久化。
 */
export function createFnWsDeviceId(): string {
  const t = Date.now().toString(36);
  const r1 = Math.random().toString(36).substring(2, 12);
  const r2 = Math.random().toString(36).substring(2, 12);
  return `${t}-${r1}-${r2}`.toLowerCase();
}

/** 给人看的短识别码字母表：去掉 0/O、1/I/L，避免口头核对时混淆。 */
const DEVICE_DISPLAY_ALPHABET: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function fnv1a32(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h = Math.imul(h ^ text.charCodeAt(i), 16777619) >>> 0;
  }
  return h;
}

function fourCharsFromHash(h: number): string {
  let x = h >>> 0;
  let out = '';
  for (let i = 0; i < 4; i++) {
    out += DEVICE_DISPLAY_ALPHABET.charAt(x & 31);
    x = x >>> 5;
  }
  return out;
}

/**
 * 由本机 did 稳定派生的短识别码（XXXX-XXXX），给用户区分设备。
 * 不是 did 本身，也不写入信封。
 */
export function wsDeviceDisplayCode(deviceId: string): string {
  const raw = deviceId.trim().toLowerCase();
  if (raw.length === 0) {
    return '';
  }
  const left = fourCharsFromHash(fnv1a32(raw));
  const right = fourCharsFromHash(fnv1a32(`fmphoto:${raw}`));
  return `${left}-${right}`;
}
