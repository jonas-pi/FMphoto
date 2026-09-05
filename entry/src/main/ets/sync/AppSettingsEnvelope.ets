/**
 * 跨设备配置信封：二维码与 WebDAV 共用同一份 JSON。
 * 只同步智能分类的关键词与顺序，不含封面 URL / 数量。
 */
import {
  SMART_CATEGORY_CUSTOM_MAX,
  SmartCategoryCustomKeyword,
  SmartCategoryLayout
} from '../album/SmartCategoryLayoutPreferences';
import { LoginSavedUser, upsertSavedUser } from '../auth/SessionPreferences';

export const APP_SETTINGS_SCHEMA: number = 1;
export const APP_SETTINGS_QR_PREFIX: string = 'FMPHOTOCFG1:';
/** Scan Kit 字符串码建议不超过 512 字符；超出改走字节码 */
export const APP_SETTINGS_QR_STRING_MAX: number = 512;
/** ArrayBuffer QR 建议不超过 2048 字节，预留余量 */
export const APP_SETTINGS_QR_BYTES_MAX: number = 1800;

type LooseJson = Record<string, Object | string | number | boolean | undefined | null>;

export interface AppSettingsCustomItem {
  id: string;
  keyword: string;
}

export interface AppSettingsSmartCategory {
  custom: AppSettingsCustomItem[];
  sceneOrder: string[];
  infoOrder: string[];
  customOrder: string[];
}

/** 登录页可同步字段；勾选保存密码时才带口令。 */
export interface AppSettingsLogin {
  fnId: string;
  domain: string;
  lan: string;
  username: string;
  endpointPref: string;
  useHttps: boolean;
  rememberPassword: boolean;
  password: string;
  users: LoginSavedUser[];
}

export interface AppSettingsEnvelope {
  schema: number;
  updatedAt: number;
  deviceId: string;
  account: string;
  smartCategory: AppSettingsSmartCategory;
  login: AppSettingsLogin;
}

export interface ParseEnvelopeResult {
  ok: boolean;
  message: string;
  envelope?: AppSettingsEnvelope;
}

export interface ApplyEnvelopeResult {
  ok: boolean;
  skipped: boolean;
  message: string;
  layout?: SmartCategoryLayout;
}

function asString(value: Object | string | number | boolean | undefined | null, fallback: string): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return fallback;
}

function asTime(value: Object | string | number | boolean | undefined | null): number {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
    return Math.floor(value);
  }
  if (typeof value === 'string') {
    const n = Number(value);
    if (Number.isFinite(n) && n >= 0) {
      return Math.floor(n);
    }
  }
  return 0;
}

function parseStringArray(raw: Object | string | number | boolean | undefined | null): string[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  const arr = raw as Object[];
  const out: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const text = asString(arr[i] as Object | string | number | boolean | undefined | null, '').trim();
    if (text.length > 0) {
      out.push(text);
    }
  }
  return out;
}

function emptySmartCategory(): AppSettingsSmartCategory {
  return {
    custom: [],
    sceneOrder: [],
    infoOrder: [],
    customOrder: []
  };
}

export function emptyLoginConfig(): AppSettingsLogin {
  return {
    fnId: '',
    domain: '',
    lan: '',
    username: '',
    endpointPref: 'auto',
    useHttps: true,
    rememberPassword: false,
    password: '',
    users: []
  };
}

function parseBoolFlag(raw: Object | string | number | boolean | undefined | null, fallback: boolean): boolean {
  if (typeof raw === 'boolean') {
    return raw;
  }
  if (typeof raw === 'number') {
    return raw !== 0;
  }
  if (typeof raw === 'string') {
    const t = raw.trim().toLowerCase();
    if (t === '1' || t === 'true' || t === 'yes') {
      return true;
    }
    if (t === '0' || t === 'false' || t === 'no') {
      return false;
    }
  }
  return fallback;
}

export function parseLoginUsers(raw: Object | string | number | boolean | undefined | null): LoginSavedUser[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  const arr = raw as Object[];
  const out: LoginSavedUser[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < arr.length; i++) {
    const el = arr[i] as Object | string | number | boolean | undefined | null;
    let username = '';
    let password = '';
    let remember = false;
    if (Array.isArray(el)) {
      const pair = el as Object[];
      username = pair.length > 0 ? asString(pair[0] as Object | string | number | boolean | undefined | null, '').trim() : '';
      password = pair.length > 1 ? asString(pair[1] as Object | string | number | boolean | undefined | null, '') : '';
      remember = pair.length > 2 ? parseBoolFlag(pair[2] as Object | string | number | boolean | undefined | null, false) : password.length > 0;
    } else if (typeof el === 'object' && el !== null) {
      const rec = el as LooseJson;
      username = asString(rec['username'] !== undefined ? rec['username'] : rec['u'], '').trim();
      password = asString(rec['password'] !== undefined ? rec['password'] : rec['p'], '');
      remember = parseBoolFlag(rec['rememberPassword'] !== undefined ? rec['rememberPassword'] : rec['r'], password.length > 0);
    }
    if (username.length === 0 || seen.has(username)) {
      continue;
    }
    seen.add(username);
    const item: LoginSavedUser = {
      username: username,
      password: remember ? password : '',
      rememberPassword: remember
    };
    out.push(item);
  }
  return out;
}

function mergeLoginUsersFromEnvelope(login: AppSettingsLogin, extra: LoginSavedUser[]): AppSettingsLogin {
  if (extra.length === 0) {
    return login;
  }
  let users = extra;
  if (login.users.length > 0) {
    users = login.users;
    for (let i = 0; i < extra.length; i++) {
      users = upsertSavedUser(users, extra[i].username, extra[i].password, extra[i].rememberPassword);
    }
  }
  return hydrateLoginFromUsers({
    fnId: login.fnId,
    domain: login.domain,
    lan: login.lan,
    username: login.username,
    endpointPref: login.endpointPref,
    useHttps: login.useHttps,
    rememberPassword: login.rememberPassword,
    password: login.password,
    users: users
  });
}

function hydrateLoginFromUsers(login: AppSettingsLogin): AppSettingsLogin {
  let users = login.users;
  if (login.username.length > 0) {
    users = upsertSavedUser(users, login.username, login.rememberPassword ? login.password : '', login.rememberPassword);
  }
  let password = login.password;
  let remember = login.rememberPassword;
  if (password.length === 0 && login.username.length > 0) {
    for (let i = 0; i < users.length; i++) {
      if (users[i].username === login.username && users[i].rememberPassword && users[i].password.length > 0) {
        password = users[i].password;
        remember = true;
        break;
      }
    }
  }
  return {
    fnId: login.fnId,
    domain: login.domain,
    lan: login.lan,
    username: login.username,
    endpointPref: login.endpointPref,
    useHttps: login.useHttps,
    rememberPassword: remember,
    password: remember ? password : '',
    users: users
  };
}

export function parseLoginConfig(raw: Object | string | number | boolean | undefined | null): AppSettingsLogin {
  const empty = emptyLoginConfig();
  if (raw === undefined || raw === null) {
    return empty;
  }
  if (Array.isArray(raw)) {
    const arr = raw as Object[];
    const username = arr.length > 3 ? asString(arr[3] as Object | string | number | boolean | undefined | null, '').trim() : '';
    const remember = arr.length > 6 ? parseBoolFlag(arr[6] as Object | string | number | boolean | undefined | null, false) : false;
    const password = arr.length > 7 ? asString(arr[7] as Object | string | number | boolean | undefined | null, '') : '';
    return hydrateLoginFromUsers({
      fnId: arr.length > 0 ? asString(arr[0] as Object | string | number | boolean | undefined | null, '').trim() : '',
      domain: arr.length > 1 ? asString(arr[1] as Object | string | number | boolean | undefined | null, '').trim() : '',
      lan: arr.length > 2 ? asString(arr[2] as Object | string | number | boolean | undefined | null, '').trim() : '',
      username: username,
      endpointPref: arr.length > 4 ? asString(arr[4] as Object | string | number | boolean | undefined | null, 'auto').trim() : 'auto',
      useHttps: arr.length > 5 ? parseBoolFlag(arr[5] as Object | string | number | boolean | undefined | null, true) : true,
      rememberPassword: remember,
      password: remember ? password : '',
      users: []
    });
  }
  if (typeof raw !== 'object') {
    return empty;
  }
  const rec = raw as LooseJson;
  const pref = asString(rec['endpointPref'] !== undefined ? rec['endpointPref'] : rec['p'], 'auto').trim();
  const remember = parseBoolFlag(rec['rememberPassword'] !== undefined ? rec['rememberPassword'] : rec['r'], false);
  const password = asString(rec['password'] !== undefined ? rec['password'] : rec['pw'], '');
  return hydrateLoginFromUsers({
    fnId: asString(rec['fnId'] !== undefined ? rec['fnId'] : rec['f'], '').trim(),
    domain: asString(rec['domain'] !== undefined ? rec['domain'] : rec['d'], '').trim(),
    lan: asString(rec['lan'] !== undefined ? rec['lan'] : rec['n'], '').trim(),
    username: asString(rec['username'] !== undefined ? rec['username'] : rec['u'], '').trim(),
    endpointPref: pref.length > 0 ? pref : 'auto',
    useHttps: parseBoolFlag(rec['useHttps'] !== undefined ? rec['useHttps'] : rec['h'], true),
    rememberPassword: remember,
    password: remember ? password : '',
    users: parseLoginUsers(rec['users'] !== undefined ? rec['users'] : rec['us'])
  });
}

export function loginConfigHasContent(login: AppSettingsLogin): boolean {
  return login.fnId.length > 0 || login.domain.length > 0 || login.lan.length > 0 ||
    login.username.length > 0 || login.users.length > 0 ||
    (login.endpointPref.length > 0 && login.endpointPref !== 'auto');
}

function parseCustomItems(raw: Object | string | number | boolean | undefined | null): AppSettingsCustomItem[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  const arr = raw as Object[];
  const out: AppSettingsCustomItem[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < arr.length; i++) {
    if (out.length >= SMART_CATEGORY_CUSTOM_MAX) {
      break;
    }
    const el = arr[i] as Object | string | number | boolean | undefined | null;
    if (Array.isArray(el)) {
      const pair = el as Object[];
      const id = pair.length > 0 ? asString(pair[0] as Object | string | number | boolean | undefined | null, '').trim() : '';
      const keyword = pair.length > 1 ? asString(pair[1] as Object | string | number | boolean | undefined | null, '').trim() : '';
      if (id.length === 0 || keyword.length === 0 || seen.has(id)) {
        continue;
      }
      seen.add(id);
      const pairItem: AppSettingsCustomItem = { id: id, keyword: keyword };
      out.push(pairItem);
      continue;
    }
    if (typeof el !== 'object' || el === null) {
      continue;
    }
    const rec = el as LooseJson;
    const id = asString(rec['id'] !== undefined ? rec['id'] : rec['i'], '').trim();
    const keyword = asString(rec['keyword'] !== undefined ? rec['keyword'] : rec['k'], '').trim();
    if (id.length === 0 || keyword.length === 0 || seen.has(id)) {
      continue;
    }
    seen.add(id);
    const recItem: AppSettingsCustomItem = { id: id, keyword: keyword };
    out.push(recItem);
  }
  return out;
}

function parseSmartCategory(raw: Object | string | number | boolean | undefined | null): AppSettingsSmartCategory {
  if (raw === undefined || raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return emptySmartCategory();
  }
  const rec = raw as LooseJson;
  const customRaw = rec['custom'] !== undefined ? rec['custom'] : rec['c'];
  const sceneRaw = rec['sceneOrder'] !== undefined ? rec['sceneOrder'] : rec['so'];
  const infoRaw = rec['infoOrder'] !== undefined ? rec['infoOrder'] : rec['io'];
  const customOrderRaw = rec['customOrder'] !== undefined ? rec['customOrder'] : rec['co'];
  return {
    custom: parseCustomItems(customRaw),
    sceneOrder: parseStringArray(sceneRaw),
    infoOrder: parseStringArray(infoRaw),
    customOrder: parseStringArray(customOrderRaw)
  };
}

function stripQrPrefix(text: string): string {
  const trimmed = text.trim();
  if (trimmed.startsWith(APP_SETTINGS_QR_PREFIX)) {
    return trimmed.substring(APP_SETTINGS_QR_PREFIX.length);
  }
  return trimmed;
}

export function layoutLocalUpdatedAt(layout: SmartCategoryLayout): number {
  const ts = layout.updatedAt;
  if (ts === undefined || ts <= 0) {
    return 0;
  }
  return ts;
}

export function envelopeFromLayout(
  layout: SmartCategoryLayout,
  deviceId: string,
  updatedAt: number,
  login: AppSettingsLogin = emptyLoginConfig()
): AppSettingsEnvelope {
  const custom: AppSettingsCustomItem[] = [];
  for (let i = 0; i < layout.custom.length; i++) {
    const row = layout.custom[i];
    const id = row.id.trim();
    const keyword = row.keyword.trim();
    if (id.length === 0 || keyword.length === 0) {
      continue;
    }
    const item: AppSettingsCustomItem = { id: id, keyword: keyword };
    custom.push(item);
  }
  return {
    schema: APP_SETTINGS_SCHEMA,
    updatedAt: updatedAt,
    deviceId: deviceId.trim(),
    account: layout.account.trim(),
    smartCategory: {
      custom: custom,
      sceneOrder: layout.sceneOrder,
      infoOrder: layout.infoOrder,
      customOrder: layout.customOrder
    },
    login: login
  };
}

export function serializeEnvelope(envelope: AppSettingsEnvelope): string {
  const customObjs: Record<string, string>[] = [];
  const src = envelope.smartCategory.custom;
  for (let i = 0; i < src.length; i++) {
    const rec: Record<string, string> = {};
    rec['id'] = src[i].id;
    rec['keyword'] = src[i].keyword;
    customObjs.push(rec);
  }
  const smart: LooseJson = {};
  smart['custom'] = customObjs;
  smart['sceneOrder'] = envelope.smartCategory.sceneOrder;
  smart['infoOrder'] = envelope.smartCategory.infoOrder;
  smart['customOrder'] = envelope.smartCategory.customOrder;
  const root: LooseJson = {};
  root['schema'] = envelope.schema;
  root['updatedAt'] = envelope.updatedAt;
  root['deviceId'] = envelope.deviceId;
  root['account'] = envelope.account;
  root['smartCategory'] = smart;
  const loginRec: LooseJson = {};
  loginRec['fnId'] = envelope.login.fnId;
  loginRec['domain'] = envelope.login.domain;
  loginRec['lan'] = envelope.login.lan;
  loginRec['username'] = envelope.login.username;
  loginRec['endpointPref'] = envelope.login.endpointPref;
  loginRec['useHttps'] = envelope.login.useHttps;
  loginRec['rememberPassword'] = envelope.login.rememberPassword;
  loginRec['password'] = envelope.login.rememberPassword ? envelope.login.password : '';
  const userObjs: Record<string, string | boolean>[] = [];
  for (let i = 0; i < envelope.login.users.length; i++) {
    const u = envelope.login.users[i];
    const rec: Record<string, string | boolean> = {};
    rec['username'] = u.username;
    rec['password'] = u.rememberPassword ? u.password : '';
    rec['rememberPassword'] = u.rememberPassword;
    userObjs.push(rec);
  }
  loginRec['users'] = userObjs;
  root['login'] = loginRec;
  return JSON.stringify(root);
}

function compactCustomPairs(custom: AppSettingsCustomItem[]): string[][] {
  const out: string[][] = [];
  for (let i = 0; i < custom.length; i++) {
    const pair: string[] = [];
    pair.push(`c${i}`);
    pair.push(custom[i].keyword);
    out.push(pair);
  }
  return out;
}

function remapOrder(order: string[], oldIds: string[]): string[] {
  const idMap: Map<string, string> = new Map<string, string>();
  for (let i = 0; i < oldIds.length; i++) {
    idMap.set(oldIds[i], `c${i}`);
  }
  const out: string[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < order.length; i++) {
    const mapped = idMap.get(order[i]);
    if (mapped !== undefined && !used.has(mapped)) {
      out.push(mapped);
      used.add(mapped);
    }
  }
  for (let i = 0; i < oldIds.length; i++) {
    const mapped = `c${i}`;
    if (!used.has(mapped)) {
      out.push(mapped);
      used.add(mapped);
    }
  }
  return out;
}

function compactRootObject(
  envelope: AppSettingsEnvelope,
  includeOrders: boolean
): LooseJson {
  const oldIds: string[] = [];
  for (let i = 0; i < envelope.smartCategory.custom.length; i++) {
    oldIds.push(envelope.smartCategory.custom[i].id);
  }
  const root: LooseJson = {};
  root['v'] = APP_SETTINGS_SCHEMA;
  root['t'] = envelope.updatedAt;
  root['a'] = envelope.account;
  root['c'] = compactCustomPairs(envelope.smartCategory.custom);
  const loginRow: string[] = [];
  loginRow.push(envelope.login.fnId);
  loginRow.push(envelope.login.domain);
  loginRow.push(envelope.login.lan);
  loginRow.push(envelope.login.username);
  loginRow.push(envelope.login.endpointPref);
  loginRow.push(envelope.login.useHttps ? '1' : '0');
  loginRow.push(envelope.login.rememberPassword ? '1' : '0');
  loginRow.push(envelope.login.rememberPassword ? envelope.login.password : '');
  root['l'] = loginRow;
  const userRows: string[][] = [];
  for (let i = 0; i < envelope.login.users.length; i++) {
    const u = envelope.login.users[i];
    const row: string[] = [];
    row.push(u.username);
    row.push(u.rememberPassword ? u.password : '');
    row.push(u.rememberPassword ? '1' : '0');
    userRows.push(row);
  }
  root['lu'] = userRows;
  if (includeOrders) {
    root['so'] = envelope.smartCategory.sceneOrder;
    root['io'] = envelope.smartCategory.infoOrder;
    root['co'] = remapOrder(envelope.smartCategory.customOrder, oldIds);
  } else {
    const empty: string[] = [];
    root['so'] = empty;
    root['io'] = empty;
    root['co'] = remapOrder(envelope.smartCategory.customOrder, oldIds);
  }
  return root;
}

export function encodeQrPayload(envelope: AppSettingsEnvelope): ParseEnvelopeResult {
  let body = JSON.stringify(compactRootObject(envelope, true));
  let text = `${APP_SETTINGS_QR_PREFIX}${body}`;
  if (utf8ByteLength(text) <= APP_SETTINGS_QR_BYTES_MAX) {
    return { ok: true, message: '', envelope: envelope };
  }
  body = JSON.stringify(compactRootObject(envelope, false));
  text = `${APP_SETTINGS_QR_PREFIX}${body}`;
  if (utf8ByteLength(text) <= APP_SETTINGS_QR_BYTES_MAX) {
    return { ok: true, message: '', envelope: envelope };
  }
  return { ok: false, message: '分类数据过多，二维码放不下，请改用 WebDAV' };
}

export function qrPayloadText(envelope: AppSettingsEnvelope): string {
  const encoded = encodeQrPayload(envelope);
  if (!encoded.ok) {
    return '';
  }
  const full = JSON.stringify(compactRootObject(envelope, true));
  const fullText = `${APP_SETTINGS_QR_PREFIX}${full}`;
  if (utf8ByteLength(fullText) <= APP_SETTINGS_QR_BYTES_MAX) {
    return fullText;
  }
  const slim = JSON.stringify(compactRootObject(envelope, false));
  return `${APP_SETTINGS_QR_PREFIX}${slim}`;
}

function utf8ByteLength(text: string): number {
  let n = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 0x80) {
      n += 1;
    } else if (c < 0x800) {
      n += 2;
    } else if (c < 0xd800 || c >= 0xe000) {
      n += 3;
    } else {
      i++;
      n += 4;
    }
  }
  return n;
}

export function parseEnvelopeJson(rawText: string): ParseEnvelopeResult {
  const body = stripQrPrefix(rawText);
  if (body.length === 0) {
    return { ok: false, message: '配置内容为空' };
  }
  try {
    const parsed = JSON.parse(body) as LooseJson;
    const smartRaw = parsed['smartCategory'] !== undefined ? parsed['smartCategory'] : parsed['s'];
    const compactCustom = parsed['c'];
    const hasFull = parsed['schema'] !== undefined || parsed['smartCategory'] !== undefined;
    const hasCompact = parsed['v'] !== undefined || compactCustom !== undefined;
    if (!hasFull && !hasCompact) {
      return { ok: false, message: '不是本应用的配置' };
    }
    const schema = asTime(parsed['schema'] !== undefined ? parsed['schema'] : parsed['v']);
    if (schema > 0 && schema !== APP_SETTINGS_SCHEMA) {
      return { ok: false, message: '配置版本不支持，请升级应用' };
    }
    const smart = hasFull ? parseSmartCategory(smartRaw) : parseSmartCategory(parsed);
    const envelope: AppSettingsEnvelope = {
      schema: APP_SETTINGS_SCHEMA,
      updatedAt: asTime(parsed['updatedAt'] !== undefined ? parsed['updatedAt'] : parsed['t']),
      deviceId: asString(parsed['deviceId'] !== undefined ? parsed['deviceId'] : parsed['d'], '').trim(),
      account: asString(parsed['account'] !== undefined ? parsed['account'] : parsed['a'], '').trim(),
      smartCategory: smart,
      login: mergeLoginUsersFromEnvelope(
        parseLoginConfig(parsed['login'] !== undefined ? parsed['login'] : parsed['l']),
        parseLoginUsers(parsed['lu'] !== undefined ? parsed['lu'] : parsed['users'])
      )
    };
    return { ok: true, message: '', envelope: envelope };
  } catch (_e) {
    return { ok: false, message: '配置内容无法解析' };
  }
}

export function parseQrPayload(rawText: string): ParseEnvelopeResult {
  const trimmed = rawText.trim();
  if (trimmed.length === 0) {
    return { ok: false, message: '未识别到内容' };
  }
  if (!trimmed.startsWith(APP_SETTINGS_QR_PREFIX) && !trimmed.startsWith('{')) {
    return { ok: false, message: '不是本应用的配置码' };
  }
  return parseEnvelopeJson(trimmed);
}

export function layoutFromEnvelope(envelope: AppSettingsEnvelope, account: string): SmartCategoryLayout {
  const custom: SmartCategoryCustomKeyword[] = [];
  const src = envelope.smartCategory.custom;
  for (let i = 0; i < src.length; i++) {
    if (custom.length >= SMART_CATEGORY_CUSTOM_MAX) {
      break;
    }
    const id = src[i].id.trim();
    const keyword = src[i].keyword.trim();
    if (id.length === 0 || keyword.length === 0) {
      continue;
    }
    const row: SmartCategoryCustomKeyword = { id: id, keyword: keyword };
    custom.push(row);
  }
  return {
    account: account,
    custom: custom,
    sceneOrder: envelope.smartCategory.sceneOrder,
    infoOrder: envelope.smartCategory.infoOrder,
    customOrder: envelope.smartCategory.customOrder,
    updatedAt: envelope.updatedAt > 0 ? envelope.updatedAt : Date.now()
  };
}

export function applyEnvelopeToAccount(
  envelope: AppSettingsEnvelope,
  account: string,
  localUpdatedAt: number,
  force: boolean
): ApplyEnvelopeResult {
  const acc = account.trim();
  if (acc.length === 0) {
    return { ok: false, skipped: false, message: '当前未登录，无法导入' };
  }
  if (!force && envelope.updatedAt > 0 && localUpdatedAt > envelope.updatedAt) {
    return { ok: false, skipped: true, message: '远程配置较旧，未覆盖本机' };
  }
  const layout = layoutFromEnvelope(envelope, acc);
  let message = '已导入自定义分类，请重新打开智能分类';
  const srcAccount = envelope.account.trim();
  if (srcAccount.length > 0 && srcAccount !== acc) {
    message = `已导入到当前账号（来源 ${srcAccount}）`;
  }
  return { ok: true, skipped: false, message: message, layout: layout };
}
