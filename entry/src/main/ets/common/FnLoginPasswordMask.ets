/** 登录密码框不用 InputType.Password，避免拉起 TEE 安全键盘；圆点遮罩在输入层自己做。 */
export const LOGIN_PASSWORD_MASK_CHAR: string = '\u2022';

export function loginPasswordMask(secret: string): string {
  if (secret.length <= 0) {
    return '';
  }
  return LOGIN_PASSWORD_MASK_CHAR.repeat(secret.length);
}

export function loginPasswordRangeIndex(value: number | undefined): number {
  if (value === undefined) {
    return 0;
  }
  return value;
}

export function applyLoginPasswordEdit(secret: string, info: EditableTextChangeValue): string {
  const options = info.options;
  if (options === undefined) {
    return applyLoginPasswordEditFallback(secret, info.content);
  }
  const startBefore: number = loginPasswordRangeIndex(options.rangeBefore.start);
  const endBefore: number = loginPasswordRangeIndex(options.rangeBefore.end);
  let next: string = secret.substring(0, startBefore) + secret.substring(endBefore);
  const startAfter: number = loginPasswordRangeIndex(options.rangeAfter.start);
  const endAfter: number = loginPasswordRangeIndex(options.rangeAfter.end);
  const added: string = info.content.substring(startAfter, endAfter);
  if (startAfter > next.length) {
    return next + added;
  }
  return next.substring(0, startAfter) + added + next.substring(startAfter);
}

export function applyLoginPasswordEditFallback(secret: string, newContent: string): string {
  let bulletCount: number = 0;
  while (bulletCount < newContent.length && newContent.charAt(bulletCount) === LOGIN_PASSWORD_MASK_CHAR) {
    bulletCount++;
  }
  const typed: string = newContent.substring(bulletCount);
  if (typed.length === 0) {
    if (newContent.length < secret.length) {
      return secret.substring(0, newContent.length);
    }
    return secret;
  }
  return secret.substring(0, bulletCount) + typed;
}
