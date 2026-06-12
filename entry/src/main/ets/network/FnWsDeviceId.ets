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
