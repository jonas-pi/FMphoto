#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
飞牛 fnOS 中继 / 局域网探测脚本（独立、不依赖鸿蒙工程编译）。

用途：对照 FMphoto 实际请求，验证「中继 HTTPS 反代」能否：
  1) 打开 NAS Web 登录页
  2) 走 WSS `/websocket?type=main` 完成登录
  3) 用 Cookie + 图库 authx 访问 `/p/api/v1`

协议对齐（抓包/开源客户端 + 本仓库 ArkTS）：
  - WSS 登录：FNOSP/fnnas-api、Timandes/pyfnos、本仓库 FnWsLogin.ets
  - 图库 HTTP：ljmljz/fnphoto-tv API.md、本仓库 FnGalleryAuthx.ets / FnHttpClient
  - FN Connect：本仓库 FnConnectApi.ets（POST https://fnos.net/api/v1/fn/con）

依赖（任选一组密码库即可）：
  pip install websocket-client pycryptodome
  # 或：pip install websocket-client cryptography

示例：
  # 只探测中继 HTTP 页（不登录）
  python scripts/fnos_relay_probe.py --fn-id YOUR_FNID

  # 中继上 WSS 登录 + 打图库
  python scripts/fnos_relay_probe.py --fn-id YOUR_FNID --user NAME --password PASS

  # 局域网 WSS 拿 token，再到中继打 /p（混合路径）
  python scripts/fnos_relay_probe.py ^
    --lan-base http://192.168.1.10:5666 --relay-base https://xxxx.5ddd.com ^
    --user NAME --password PASS --insecure

  # 浏览器已登录：直接用 Cookie 测图库
  python scripts/fnos_relay_probe.py --base https://xxxx.5ddd.com --cookie "fnos-token=...; mode=relay"
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import random
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# 常量：与 FMphoto / 图库前端 bundle 一致
# ---------------------------------------------------------------------------

# 图库 GET authx（FnGalleryAuthx.ets / 官方照片 Web galleryApi.baseQuery）
GALLERY_AUTHX_KEY = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
GALLERY_AUTHX_UUID = "EAECCF25-80A6-4666-A7C2-A76904A74AB6"

# FN Connect 云端解析（FnConnectApi.ets）
FN_CONNECT_URL = "https://fnos.net/api/v1/fn/con"
FN_CONNECT_PATH = "/api/v1/fn/con"
FN_SIGN_SECRET = "anna"
CONNECT_AUTHX_PREFIX = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
CONNECT_AUTHX_API_KEY = "zIGtkc3dqZnJpd29qZXJqa2w7c"

FN_RELAY_CLUSTER = "5ddd.com"
FN_RELAY_CLUSTER_LEGACY = "fnos.net"

# 与 FnWebCookies.fnWebDefaultUserAgent 一致
UA_FMPHOTO = (
    "Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
)
# 桌面 Chrome，贴近官方 Web / fnnas-api 抓包
UA_DESKTOP = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

GALLERY_TIMELINE_SIGN_PATH = "/p/api/v1/gallery/timeline"
GALLERY_TIMELINE_PATHS = [
    "/p/api/v1/gallery/timeline",
    "/api/v1/gallery/timeline",
]
GALLERY_STAT_PATH = "/p/api/v1/user_photo/stat"

DEFAULT_BACK_ID = "0000000000000000"

# 登录 JSON 键序：与 FnWsLogin.buildLoginPlainJson 一致（服务端按 JSON 解析，顺序主要方便对照抓包）
# reqid -> req -> user -> password -> deviceType -> deviceName -> stay -> did -> si

_REQ_SEQ = 1


# ---------------------------------------------------------------------------
# 小工具
# ---------------------------------------------------------------------------

def _win_utf8() -> None:
    """Windows 控制台尽量用 UTF-8，避免中文乱码。"""
    if sys.platform != "win32":
        return
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


def log(msg: str) -> None:
    print(msg, flush=True)


def ok(msg: str) -> None:
    log("[OK]   " + msg)


def fail(msg: str) -> None:
    log("[FAIL] " + msg)


def info(msg: str) -> None:
    log("[..]   " + msg)


def skip(msg: str) -> None:
    log("[SKIP] " + msg)


def strip_slash(url: str) -> str:
    return url.strip().rstrip("/")


def origin_of(base: str) -> str:
    """https://host[:port] ，不含 path。"""
    p = urllib.parse.urlparse(strip_slash(base))
    if not p.scheme or not p.netloc:
        return strip_slash(base)
    return f"{p.scheme}://{p.netloc}"


def ws_url_from_http(base: str) -> str:
    """与 ServerUrl.buildFnMainWebSocketUrl 一致。"""
    u = strip_slash(base)
    if u.startswith("https://"):
        return "wss://" + u[len("https://") :] + "/websocket?type=main"
    if u.startswith("http://"):
        return "ws://" + u[len("http://") :] + "/websocket?type=main"
    return "wss://" + u + "/websocket?type=main"


def is_fn_id(text: str) -> bool:
    """字母开头、5–32 位字母数字与连字符，不以 - 结尾。"""
    t = text.strip()
    if not t or "." in t or ":" in t or "/" in t:
        return False
    return bool(re.match(r"^[a-zA-Z][a-zA-Z0-9-]{4,31}$", t)) and not t.endswith("-")


def extract_fn_id(raw: str) -> str:
    """从纯 ID / 子域名 / 路径门户提取 FN ID（对齐 FnConnectApi.extractFnId）。"""
    t = raw.strip()
    if is_fn_id(t):
        return t
    if t.startswith("http://"):
        t = t[len("http://") :]
    elif t.startswith("https://"):
        t = t[len("https://") :]
    slash = t.find("/")
    q = t.find("?")
    cut = len(t)
    if slash >= 0:
        cut = min(cut, slash)
    if q >= 0:
        cut = min(cut, q)
    authority = t[:cut]
    host = authority.split(":")[0].lower()
    path_seg = ""
    if slash >= 0:
        path_seg = t[slash + 1 :].split("/")[0].split("?")[0].strip()
    m = re.match(r"^([a-zA-Z][a-zA-Z0-9-]{4,31})\.(?:fnos\.net|5ddd\.com)$", host)
    if m and is_fn_id(m.group(1)):
        return m.group(1)
    if host in (FN_RELAY_CLUSTER, FN_RELAY_CLUSTER_LEGACY, f"www.{FN_RELAY_CLUSTER}", f"www.{FN_RELAY_CLUSTER_LEGACY}"):
        if is_fn_id(path_seg):
            return path_seg
    return ""


def relay_base_from_fn_id(fn_id: str, cluster: str = FN_RELAY_CLUSTER) -> str:
    return f"https://{fn_id}.{cluster}"


def md5_hex_utf8(text: str) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def sha256_hex_utf8(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def make_reqid(back_id: str = DEFAULT_BACK_ID) -> str:
    """
    对齐 FMphoto fnWsMakeReqId：毫秒时间戳 hex（至少 8 位）+ backId(16) + 序号 hex(4)。
    fnnas-api 用的是秒级 time.time()，官方 Web / 本应用用毫秒。
    """
    global _REQ_SEQ
    hx = format(int(time.time() * 1000), "x")
    while len(hx) < 8:
        hx = "0" + hx
    ez = format(_REQ_SEQ, "x").zfill(4)
    _REQ_SEQ += 1
    bid = back_id[:16] if len(back_id) >= 16 else back_id.rjust(16, "0")
    return f"{hx}{bid}{ez}"


def make_did() -> str:
    """对齐 FnWsDeviceId.createFnWsDeviceId。"""
    chars = "0123456789abcdefghijklmnopqrstuvwxyz"

    def b36(n: int) -> str:
        if n <= 0:
            return "0"
        out = []
        while n:
            n, r = divmod(n, 36)
            out.append(chars[r])
        return "".join(reversed(out))

    t = b36(int(time.time() * 1000))
    r1 = "".join(random.choice(chars) for _ in range(10))
    r2 = "".join(random.choice(chars) for _ in range(10))
    return f"{t}-{r1}-{r2}".lower()


def compact_json(obj: Dict[str, Any]) -> str:
    """与 JS JSON.stringify / Python json.dumps(separators=(',', ':')) 一致。"""
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)


# ---------------------------------------------------------------------------
# 密码学：pycryptodome 优先，其次 cryptography（对齐 fnnas-api encryption.py / pyfnos）
# ---------------------------------------------------------------------------

def _load_crypto():
    try:
        from Crypto.Cipher import AES, PKCS1_v1_5  # type: ignore
        from Crypto.PublicKey import RSA  # type: ignore
        from Crypto.Util.Padding import pad, unpad  # type: ignore

        def rsa_encrypt(pem: str, key32: bytes) -> str:
            rsa_key = RSA.import_key(pem)
            cipher = PKCS1_v1_5.new(rsa_key)
            return base64.b64encode(cipher.encrypt(key32)).decode("ascii")

        def aes_cbc_encrypt(plain: str, key32: bytes, iv: bytes) -> str:
            cipher = AES.new(key32, AES.MODE_CBC, iv)
            ct = cipher.encrypt(pad(plain.encode("utf-8"), AES.block_size))
            return base64.b64encode(ct).decode("ascii")

        def aes_cbc_decrypt(cipher_b64: str, key32: bytes, iv: bytes) -> bytes:
            cipher = AES.new(key32, AES.MODE_CBC, iv)
            raw = cipher.decrypt(base64.b64decode(cipher_b64))
            return unpad(raw, AES.block_size)

        return rsa_encrypt, aes_cbc_encrypt, aes_cbc_decrypt
    except ImportError:
        pass

    try:
        from cryptography.hazmat.primitives import padding as sym_padding
        from cryptography.hazmat.primitives.asymmetric import padding as asy_padding
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.primitives.serialization import load_pem_public_key

        def rsa_encrypt(pem: str, key32: bytes) -> str:
            pub = load_pem_public_key(pem.encode("utf-8"))
            out = pub.encrypt(key32, asy_padding.PKCS1v15())
            return base64.b64encode(out).decode("ascii")

        def aes_cbc_encrypt(plain: str, key32: bytes, iv: bytes) -> str:
            padder = sym_padding.PKCS7(128).padder()
            padded = padder.update(plain.encode("utf-8")) + padder.finalize()
            enc = Cipher(algorithms.AES(key32), modes.CBC(iv)).encryptor()
            ct = enc.update(padded) + enc.finalize()
            return base64.b64encode(ct).decode("ascii")

        def aes_cbc_decrypt(cipher_b64: str, key32: bytes, iv: bytes) -> bytes:
            raw = base64.b64decode(cipher_b64)
            dec = Cipher(algorithms.AES(key32), modes.CBC(iv)).decryptor()
            padded = dec.update(raw) + dec.finalize()
            unpadder = sym_padding.PKCS7(128).unpadder()
            return unpadder.update(padded) + unpadder.finalize()

        return rsa_encrypt, aes_cbc_encrypt, aes_cbc_decrypt
    except ImportError as e:
        raise SystemExit(
            "缺少加密库。请安装其一：\n"
            "  pip install pycryptodome\n"
            "  pip install cryptography\n"
            f"原始错误：{e}"
        ) from e


def ensure_pem_pub(pub: str) -> str:
    text = pub.strip()
    if "BEGIN PUBLIC KEY" in text:
        return text
    # 少数实现只给裸 Base64，补 PEM 头尾
    body = re.sub(r"\s+", "", text)
    lines = [body[i : i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PUBLIC KEY-----\n" + "\n".join(lines) + "\n-----END PUBLIC KEY-----"


def hmac_sign_concat(hmac_key: bytes, json_compact: str) -> str:
    """
    后续 WS 明文帧：Base64(HMAC-SHA256(key, json)) + json
    对齐 FnWsCrypto.fnWsHmacSha256SignConcatJson / fnnas-api get_signature_req。
    """
    mac = hmac.new(hmac_key, json_compact.encode("utf-8"), hashlib.sha256).digest()
    return base64.b64encode(mac).decode("ascii") + json_compact


def parse_ws_json(text: str) -> Optional[Dict[str, Any]]:
    """部分响应带 HMAC 前缀，先直接 parse，失败则从第一个 { 切开。"""
    s = text.strip()
    try:
        obj = json.loads(s)
        return obj if isinstance(obj, dict) else None
    except json.JSONDecodeError:
        idx = s.find("{")
        if idx <= 0:
            return None
        try:
            obj = json.loads(s[idx:])
            return obj if isinstance(obj, dict) else None
        except json.JSONDecodeError:
            return None


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

def ssl_context(insecure: bool) -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    if insecure:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    return ctx


def http_get(
    url: str,
    headers: Dict[str, str],
    timeout: float,
    insecure: bool,
    follow_redirects: bool = False,
) -> Tuple[int, Dict[str, str], bytes, str]:
    """返回 status, 响应头(小写), body, 最终 URL。默认不跟随 302，以免把 NAS 子域名误判成 Connect 门户。"""
    req = urllib.request.Request(url, headers=headers, method="GET")
    handlers: List[Any] = [urllib.request.HTTPSHandler(context=ssl_context(insecure))]
    if not follow_redirects:
        class _NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
                return None

        handlers.insert(0, _NoRedirect())
    opener = urllib.request.build_opener(*handlers)
    try:
        with opener.open(req, timeout=timeout) as resp:
            body = resp.read()
            hdrs = {k.lower(): v for k, v in resp.headers.items()}
            return int(resp.status), hdrs, body, resp.geturl()
    except urllib.error.HTTPError as e:
        body = e.read() if e.fp else b""
        hdrs = {k.lower(): v for k, v in e.headers.items()} if e.headers else {}
        return int(e.code), hdrs, body, url
    except Exception as e:
        raise RuntimeError(f"{url} -> {e}") from e


def http_post_json(
    url: str,
    body_str: str,
    headers: Dict[str, str],
    timeout: float,
    insecure: bool,
) -> Tuple[int, bytes]:
    data = body_str.encode("utf-8")
    h = dict(headers)
    h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=h, method="POST")
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ssl_context(insecure))
    )
    try:
        with opener.open(req, timeout=timeout) as resp:
            return int(resp.status), resp.read()
    except urllib.error.HTTPError as e:
        return int(e.code), e.read() if e.fp else b""


def snippet(body: bytes | str, limit: int = 240) -> str:
    if isinstance(body, bytes):
        text = body.decode("utf-8", errors="replace")
    else:
        text = body
    text = text.replace("\n", " ").replace("\r", " ")
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        return text[:limit] + "..."
    return text


def html_title(body: bytes) -> str:
    m = re.search(r"<title[^>]*>(.*?)</title>", body.decode("utf-8", errors="ignore"), re.I | re.S)
    return re.sub(r"\s+", " ", m.group(1)).strip() if m else ""


def classify_html_page(body: bytes, title: str) -> str:
    """区分 Connect 门户 SPA 与真正的 NAS os-web。"""
    title_l = title.lower()
    head = body[:2500]
    if b"polyfills-" in head or b"rolldown-runtime" in head or b"/locales/" in head:
        return "NAS os-web（官方桌面壳）"
    if "fn connect" in title_l or "远程访问" in title or b"static2.fnnas.com/connect/" in head:
        return "Connect 门户 SPA"
    blob = (title + " " + body.decode("utf-8", errors="ignore")[:4000]).lower()
    keys = ("飞牛", "fnos", "fn nas", "trim", "password", "登录", "login")
    if any((k.lower() in blob) if k.isascii() else (k in blob) for k in keys):
        return "疑似 NAS Web"
    return ""


# ---------------------------------------------------------------------------
# FN Connect
# ---------------------------------------------------------------------------

def lookup_fn_connect(fn_id: str, timeout: float) -> Dict[str, Any]:
    """POST fnos.net/api/v1/fn/con，签名与 FnConnectApi.lookupFnConnect 一致。"""
    ts = int(time.time() * 1000)
    body = compact_json({"fnId": fn_id})
    fn_sign = sha256_hex_utf8(f"trim_connect`{fn_id}`{ts}`{FN_SIGN_SECRET}")
    nonce = str(random.randint(100000, 999999))
    body_md5 = md5_hex_utf8(body)
    chain = f"{CONNECT_AUTHX_PREFIX}_{FN_CONNECT_PATH}_{nonce}_{ts}_{body_md5}_{CONNECT_AUTHX_API_KEY}"
    authx = f"nonce={nonce}&timestamp={ts}&sign={md5_hex_utf8(chain)}"
    status, raw = http_post_json(
        FN_CONNECT_URL,
        body,
        {"fn-sign": fn_sign, "authx": authx, "Accept": "application/json"},
        timeout,
        insecure=False,
    )
    text = raw.decode("utf-8", errors="replace")
    try:
        root = json.loads(text)
    except json.JSONDecodeError:
        return {"ok": False, "http": status, "message": f"响应不是 JSON: {snippet(raw)}"}
    if status < 200 or status >= 300:
        return {"ok": False, "http": status, "message": f"HTTP {status}", "raw": root}
    if root.get("code") != 0:
        return {"ok": False, "http": status, "message": root.get("msg") or f"code={root.get('code')}", "raw": root}
    data = root.get("data") or {}
    fn_hosts = _as_str_list(data.get("fn"))
    relay = ""
    if fn_hosts:
        host = fn_hosts[0]
        if host.startswith("http"):
            relay = strip_slash(host)
        else:
            relay = "https://" + host.split(":")[0]
    port_obj = data.get("port") if isinstance(data.get("port"), dict) else {}
    http_port = port_obj.get("httpPort") if isinstance(port_obj, dict) else None
    if not isinstance(http_port, int) or http_port <= 0:
        http_port = 5666
    return {
        "ok": True,
        "http": status,
        "raw": data,
        "relay": relay,
        "ipv4": _as_str_list(data.get("ipv4")),
        "ipv6": _as_str_list(data.get("ipv6")),
        "ddns": _as_str_list(data.get("ddns")),
        "publicIpv4": _as_str_list(data.get("publicIpv4")),
        "httpPort": http_port,
        "ver": data.get("ver") or "",
        "message": "解析成功",
    }


def _as_str_list(raw: Any) -> List[str]:
    if raw is None:
        return []
    if isinstance(raw, str):
        t = raw.strip()
        return [t] if t else []
    if isinstance(raw, list):
        return [str(x).strip() for x in raw if str(x).strip()]
    return []


def is_private_ipv4(host: str) -> bool:
    parts = host.split(".")
    if len(parts) != 4:
        return False
    try:
        n = [int(x) for x in parts]
    except ValueError:
        return False
    if n[0] == 10 or n[0] == 127:
        return True
    if n[0] == 192 and n[1] == 168:
        return True
    if n[0] == 172 and 16 <= n[1] <= 31:
        return True
    return False


def connect_spa_jump_candidates(fn_id: str, lookup: Dict[str, Any]) -> List[Tuple[str, str]]:
    """
    官方 Connect 门户 JS（static2.fnnas.com/connect）测速成功后会 window.location.href 整页跳转。
    urllib 只拿到 SPA 壳，这里按同一套地址列出浏览器几秒后可能进入的入口：
      1) 内网 http://{ipv4}:{httpPort}（你在家打开门户时最常见）
      2) 公网 IP / DDNS
      3) 中继 https://{fn}.fnos.net
      4) 旧固件回退 http://check.fnos.net/{fnId}/
    """
    out: List[Tuple[str, str]] = []
    port = int(lookup.get("httpPort") or 5666)
    seen = set()

    def add(label: str, url: str) -> None:
        u = strip_slash(url)
        if u and u not in seen:
            seen.add(u)
            out.append((label, u))

    for ip in lookup.get("ipv4") or []:
        if is_private_ipv4(ip):
            add(f"内网 IPv4（Connect iframe 探测 {ip}）", f"http://{ip}:{port}")
        else:
            add("公网 IPv4", f"http://{ip}:{port}")
    for ip in lookup.get("publicIpv4") or []:
        add("publicIpv4", f"http://{ip}:{port}")
    for d in lookup.get("ddns") or []:
        host = d.split(":")[0]
        add("DDNS", f"https://{host}")
    if lookup.get("relay"):
        add("中继反代", str(lookup.get("relay")))
    if fn_id:
        add("Connect 旧跳板 check.fnos.net", f"http://check.fnos.net/{fn_id}")
    return out


# ---------------------------------------------------------------------------
# 图库 authx + Cookie
# ---------------------------------------------------------------------------

def gallery_sorted_query(params: Dict[str, Any]) -> str:
    """对齐 FnGalleryAuthx.buildGallerySortedQuery：键排序、urlencode、空格为 %20。"""
    keys = sorted(k for k in params if params[k] is not None)
    parts = []
    for k in keys:
        v = params[k]
        if isinstance(v, bool):
            vs = "true" if v else "false"
        else:
            vs = str(v)
        parts.append(f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(vs, safe='')}")
    return "&".join(parts)


def percent_decode_for_inner(param_block: str) -> str:
    fixed = re.sub(r"%(?![0-9A-Fa-f]{2})", "%25", param_block)
    try:
        return urllib.parse.unquote(fixed)
    except Exception:
        return param_block


def gen_gallery_authx_get(sign_path: str, params: Dict[str, Any]) -> str:
    """对齐 genFnGalleryAuthxGet / fnphoto-tv AuthX。"""
    path_only = sign_path.split("?")[0]
    raw = gallery_sorted_query(params)
    inner = md5_hex_utf8(percent_decode_for_inner(raw))
    nonce_n = int(round(random.random() * 900000 + 100000))
    nonce = str(nonce_n).zfill(6) if nonce_n < 100000 else str(nonce_n)
    ts = int(time.time() * 1000)
    chain = f"{GALLERY_AUTHX_KEY}_{path_only}_{nonce}_{ts}_{inner}_{GALLERY_AUTHX_UUID}"
    sign = md5_hex_utf8(chain)
    return f"nonce={nonce}&timestamp={ts}&sign={sign}"


def build_fn_cookie(token: str, long_token: str = "") -> str:
    """对齐 FnHttpClientCookie.buildFnApiCookieHeader。"""
    if not token:
        return f"fnos-long-token={long_token}; mode=relay" if long_token else "mode=relay"
    s = f"fnos-token={token}; language=zh-CN"
    if long_token:
        s += f"; fnos-long-token={long_token}"
    s += f"; Trim-MC-token={token}; mode=relay"
    return s


def gallery_headers(base: str, authx: str, cookie: str, token: str, ua: str) -> Dict[str, str]:
    origin = origin_of(base)
    h = {
        "Cookie": cookie,
        "User-Agent": ua,
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
        "Accept-Encoding": "identity",
        "Origin": origin,
        "Referer": origin + "/p/",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
        "authx": authx,
    }
    if token:
        h["AccessToken"] = token
        h["accesstoken"] = token
    return h


# ---------------------------------------------------------------------------
# WSS 登录
# ---------------------------------------------------------------------------

def _import_websocket():
    try:
        import websocket  # type: ignore
        return websocket
    except ImportError as e:
        raise SystemExit(
            "缺少 websocket-client。请执行：\n  pip install websocket-client\n"
            f"原始错误：{e}"
        ) from e


def _ws_connect(http_base: str, ua: str, timeout: float, insecure: bool):
    """按官方 Web 抓包：Origin + Cookie mode=relay 连 wss://host/websocket?type=main。"""
    websocket = _import_websocket()
    url = ws_url_from_http(http_base)
    origin = origin_of(http_base)
    headers = [
        f"Origin: {origin}",
        f"User-Agent: {ua}",
        "Cookie: mode=relay; language=zh-CN",
        "Pragma: no-cache",
        "Cache-Control: no-cache",
    ]
    sslopt = {}
    if url.startswith("wss://"):
        sslopt = {"cert_reqs": ssl.CERT_NONE if insecure else ssl.CERT_REQUIRED}
        if insecure:
            sslopt["check_hostname"] = False
    ws = websocket.create_connection(url, timeout=timeout, header=headers, sslopt=sslopt)
    return ws, url


def probe_ws_rsa(http_base: str, ua: str, timeout: float, insecure: bool) -> bool:
    """不登录，只测中继是否转发 WSS（官方 Web 会先 getRSAPub）。"""
    url = ws_url_from_http(http_base)
    info(f"WSS 握手 {url}")
    try:
        ws, _u = _ws_connect(http_base, ua, timeout, insecure)
    except Exception as e:
        fail(f"WSS 无法连接：{e}")
        return False
    try:
        ws.send(compact_json({"reqid": make_reqid(), "req": "util.crypto.getRSAPub"}))
        raw = ws.recv()
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="replace")
        obj = parse_ws_json(raw)
        if obj and obj.get("pub") and obj.get("si") is not None:
            ok(f"WSS getRSAPub 成功  si={obj.get('si')}")
            return True
        fail(f"WSS 已连通但未返回公钥：{snippet(raw.encode('utf-8') if isinstance(raw, str) else raw)}")
        return False
    except Exception as e:
        fail(f"WSS getRSAPub 失败：{e}")
        return False
    finally:
        try:
            ws.close()
        except Exception:
            pass


def ws_login(
    http_base: str,
    username: str,
    password: str,
    ua: str,
    timeout: float,
    insecure: bool,
    otp: str,
    device_name: str,
    stay: bool,
) -> Dict[str, Any]:
    """
    流程（fnnas-api api.md + FnWsLogin.ets）：
      open → util.crypto.getRSAPub
           → encrypted(user.login)   AES-256-CBC + RSA-PKCS1 包装 AES key
           → [可选] user.2fa.loginVerify
           → HMAC 前缀 + user.authToken
    """
    rsa_encrypt, aes_cbc_encrypt, aes_cbc_decrypt = _load_crypto()
    url = ws_url_from_http(http_base)
    info(f"WSS 登录 {url}")
    try:
        ws, url = _ws_connect(http_base, ua, timeout, insecure)
    except Exception as e:
        return {"ok": False, "message": f"WSS 握手失败：{e}", "ws_url": url}

    def recv_obj() -> Dict[str, Any]:
        raw = ws.recv()
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", errors="replace")
        obj = parse_ws_json(raw)
        if obj is None:
            raise RuntimeError(f"非 JSON 帧：{raw[:180]!r}")
        return obj

    def send_json(obj: Any) -> None:
        if isinstance(obj, str):
            ws.send(obj)
        else:
            ws.send(compact_json(obj))

    try:
        back_id = DEFAULT_BACK_ID
        did = make_did()
        send_json({"reqid": make_reqid(back_id), "req": "util.crypto.getRSAPub"})
        pub_msg = recv_obj()
        if pub_msg.get("errno") not in (None, 0):
            return {"ok": False, "message": pub_msg.get("msg") or f"getRSAPub errno={pub_msg.get('errno')}", "raw": pub_msg}
        pub = pub_msg.get("pub") or ""
        si = str(pub_msg.get("si") or "")
        if not pub or not si:
            return {"ok": False, "message": "getRSAPub 未返回 pub/si", "raw": pub_msg}
        ok("已拿到 RSA 公钥与 si")

        # AES-256 密钥：32 随机字节（FMphoto / pyfnos）。fnnas-api 用 32 位字母数字字符串，等价于 ASCII 32 字节。
        aes_key = os.urandom(32)
        iv = os.urandom(16)
        pem = ensure_pem_pub(pub)

        login_plain = compact_json({
            "reqid": make_reqid(back_id),
            "req": "user.login",
            "user": username,
            "password": password,
            "deviceType": "Browser",
            "deviceName": device_name,
            "stay": stay,
            "did": did,
            "si": si,
        })
        frame = {
            "req": "encrypted",
            "iv": base64.b64encode(iv).decode("ascii"),
            "rsa": rsa_encrypt(pem, aes_key),
            "aes": aes_cbc_encrypt(login_plain, aes_key, iv),
        }
        send_json(frame)
        login_msg = recv_obj()
        if login_msg.get("errno") not in (None, 0):
            return {"ok": False, "message": login_msg.get("msg") or f"登录 errno={login_msg.get('errno')}", "raw": login_msg}

        # 2FA：已绑定 TOTP、当前设备未信任
        if (
            login_msg.get("result") == "succ"
            and login_msg.get("isBindTwofaSecret") is True
            and login_msg.get("isTrustedDevice") is False
            and login_msg.get("accessToken")
            and not login_msg.get("token")
        ):
            if not otp:
                return {
                    "ok": False,
                    "requires2fa": True,
                    "message": "需要 6 位 TOTP，请加 --otp 123456",
                    "accessToken": login_msg.get("accessToken"),
                }
            info("提交 user.2fa.loginVerify")
            verify_plain = compact_json({
                "reqid": make_reqid(back_id),
                "code": otp,
                "isTrustedDevice": True,
                "accessToken": login_msg["accessToken"],
                "stay": 1 if stay else 0,
                "deviceName": device_name,
                "deviceType": "Browser",
                "did": did,
                "req": "user.2fa.loginVerify",
                "si": si,
            })
            aes_key = os.urandom(32)
            iv = os.urandom(16)
            send_json({
                "req": "encrypted",
                "iv": base64.b64encode(iv).decode("ascii"),
                "rsa": rsa_encrypt(pem, aes_key),
                "aes": aes_cbc_encrypt(verify_plain, aes_key, iv),
            })
            login_msg = recv_obj()
            if login_msg.get("errno") not in (None, 0):
                return {"ok": False, "message": login_msg.get("msg") or "2FA 失败", "raw": login_msg}

        if login_msg.get("isTwofaEnforced") is True and login_msg.get("isBindTwofaSecret") is False:
            return {"ok": False, "requires2faSetup": True, "message": "账号需先在网页端绑定双重验证"}

        token = login_msg.get("token") or ""
        secret_b64 = login_msg.get("secret") or ""
        if login_msg.get("result") != "succ" or not token or not secret_b64:
            return {"ok": False, "message": login_msg.get("msg") or "登录未返回 token/secret", "raw": login_msg}

        long_token = login_msg.get("longToken") or login_msg.get("long_token") or ""
        if long_token is not None:
            long_token = str(long_token)
        back_id = login_msg.get("backId") or back_id
        si_auth = str(login_msg.get("si") or si)

        hmac_key = aes_cbc_decrypt(secret_b64, aes_key, iv)
        auth_json = compact_json({"req": "user.authToken", "token": token, "si": si_auth})
        send_json(hmac_sign_concat(hmac_key, auth_json))
        try:
            auth_msg = recv_obj()
        except Exception as e:
            # 部分网关 authToken 后不回包或回非 JSON；token 已到手，仍视为登录成功
            info(f"authToken 回包异常（可忽略）：{e}")
            auth_msg = {"note": str(e)}

        return {
            "ok": True,
            "token": token,
            "longToken": long_token,
            "uid": login_msg.get("uid"),
            "admin": login_msg.get("admin"),
            "backId": back_id,
            "signKeyB64": base64.b64encode(hmac_key).decode("ascii"),
            "authTokenResp": auth_msg,
            "ws_url": url,
            "message": "WSS 登录成功",
        }
    except Exception as e:
        return {"ok": False, "message": f"WSS 登录异常：{e}", "ws_url": url}
    finally:
        try:
            ws.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# 探测步骤
# ---------------------------------------------------------------------------

def dns_probe(host: str) -> str:
    try:
        infos = socket.getaddrinfo(host, None)
        ips = sorted({x[4][0] for x in infos})
        return ", ".join(ips) if ips else "(无记录)"
    except Exception as e:
        return f"解析失败：{e}"


def probe_http_page(base: str, path: str, ua: str, timeout: float, insecure: bool) -> None:
    url = strip_slash(base) + path
    headers = {
        "User-Agent": ua,
        "Accept": "text/html,application/xhtml+xml,application/javascript,application/json,*/*;q=0.8",
        # 官方 Web 抓包带 language；中继网关常看 mode=relay
        "Cookie": "mode=relay; language=zh-CN",
        "Origin": origin_of(base),
        "Referer": strip_slash(base) + "/",
    }
    try:
        status, hdrs, body, final = http_get(url, headers, timeout, insecure, follow_redirects=False)
    except Exception as e:
        fail(f"GET {url}  {e}")
        return
    title = html_title(body)
    ctype = hdrs.get("content-type", "")
    loc = hdrs.get("location", "")
    extra = []
    if title:
        extra.append(f"title={title!r}")
    extra.append(f"type={ctype.split(';')[0]}")
    extra.append(f"len={len(body)}")
    kind = classify_html_page(body, title)
    if kind:
        extra.append(kind)
    if loc:
        extra.append(f"Location={loc}")
    line = f"GET {url}  HTTP {status}  " + "  ".join(extra)
    if 200 <= status < 400:
        ok(line)
        if final != url:
            info(f"  最终 URL {final}")
        info(f"  body: {snippet(body)}")
    else:
        fail(line)
        info(f"  body: {snippet(body)}")


def probe_gallery(
    base: str,
    token: str,
    long_token: str,
    cookie_override: str,
    ua: str,
    timeout: float,
    insecure: bool,
) -> bool:
    cookie = cookie_override.strip() if cookie_override.strip() else build_fn_cookie(token, long_token)
    params: Dict[str, Any] = {}
    authx = gen_gallery_authx_get(GALLERY_TIMELINE_SIGN_PATH, params)
    headers = gallery_headers(base, authx, cookie, token, ua)
    last_ok = False
    for rel in GALLERY_TIMELINE_PATHS:
        url = strip_slash(base) + rel
        try:
            status, _hdrs, body, _final = http_get(url, headers, timeout, insecure)
        except Exception as e:
            fail(f"图库 {rel}  {e}")
            continue
        text = body.decode("utf-8", errors="replace")
        code = None
        try:
            parsed = json.loads(text)
            code = parsed.get("code", parsed.get("errno"))
        except json.JSONDecodeError:
            parsed = None
        tag = f"GET {rel}  HTTP {status}"
        if parsed is not None:
            tag += f"  code={code}  {snippet(text, 180)}"
        else:
            tag += f"  非 JSON  {snippet(body)}"
        # 业务成功：HTTP 200 且 code 为 0/缺省，且不是 SPA HTML 壳
        if status == 200 and parsed is not None and code in (0, None) and "list" in str(parsed.get("data", {})):
            ok(tag)
            last_ok = True
            break
        if status == 200 and parsed is not None and code == 0:
            ok(tag)
            last_ok = True
            break
        fail(tag)
        # 404 / HTML 壳则试下一条候选路径
        if status in (404, 502, 503):
            continue
        if parsed is None and b"<html" in body[:200].lower():
            continue
    # 额外打一条统计，方便确认 Cookie 是否被 /p 接受
    try:
        authx2 = gen_gallery_authx_get(GALLERY_STAT_PATH, {})
        h2 = gallery_headers(base, authx2, cookie, token, ua)
        st, _h, body2, _f = http_get(strip_slash(base) + GALLERY_STAT_PATH, h2, timeout, insecure)
        info(f"GET {GALLERY_STAT_PATH}  HTTP {st}  {snippet(body2, 160)}")
    except Exception as e:
        info(f"GET {GALLERY_STAT_PATH} 跳过：{e}")
    return last_ok


def save_session(path: str, payload: Dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    ok(f"会话已写入 {path}（含 token，勿提交 git）")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="探测飞牛 FN Connect 中继：登录页 / WSS / 图库 /p API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--fn-id", help="FN ID，将解析 Connect 并默认打 https://{id}.5ddd.com")
    p.add_argument("--base", help="单一探测入口，如 https://xxx.5ddd.com 或 http://IP:5666")
    p.add_argument("--lan-base", help="局域网登录入口（混合路径：在此 WSS 登录）")
    p.add_argument("--relay-base", help="中继图库入口（混合路径：用 token 打 /p）")
    p.add_argument("--user", help="NAS 用户名")
    p.add_argument("--password", help="NAS 密码")
    p.add_argument("--otp", default="", help="2FA 六位动态码")
    p.add_argument("--token", default="", help="已有 fnos-token，跳过 WSS")
    p.add_argument("--long-token", default="", dest="long_token", help="已有 fnos-long-token")
    p.add_argument("--cookie", default="", help="浏览器复制的完整 Cookie（优先于 --token 拼装）")
    p.add_argument("--skip-ws", action="store_true", help="不测 WSS")
    p.add_argument("--skip-gallery", action="store_true", help="不测图库 /p")
    p.add_argument("--insecure", action="store_true", help="跳过 TLS 校验（局域网自签证书）")
    p.add_argument("--desktop-ua", action="store_true", help="用桌面 Chrome UA（默认 FMphoto 移动 UA）")
    p.add_argument("--device-name", default="FMphoto", help="WSS user.login 的 deviceName")
    p.add_argument("--timeout", type=float, default=18.0, help="单次 HTTP/WSS 超时秒数")
    p.add_argument("--save-session", metavar="PATH", help="登录成功后把 token 写到 JSON")
    return p


def main(argv: Optional[List[str]] = None) -> int:
    _win_utf8()
    args = build_parser().parse_args(argv)
    ua = UA_DESKTOP if args.desktop_ua else UA_FMPHOTO

    fn_id = (args.fn_id or "").strip()
    if not fn_id:
        for cand in (args.base, args.relay_base):
            if cand:
                fn_id = extract_fn_id(cand)
                if fn_id:
                    break

    relay_base = strip_slash(args.relay_base or "")
    lan_base = strip_slash(args.lan_base or "")
    single = strip_slash(args.base or "")

    lookup: Optional[Dict[str, Any]] = None
    if fn_id:
        info(f"FN Connect 解析 fnId={fn_id}")
        try:
            lookup = lookup_fn_connect(fn_id, args.timeout)
        except Exception as e:
            fail(f"FN Connect 请求失败：{e}")
            lookup = {"ok": False, "message": str(e)}
        if lookup.get("ok"):
            ok(
                f"Connect 成功  relay={lookup.get('relay') or '(空)'}  "
                f"ipv4={lookup.get('ipv4')}  httpPort={lookup.get('httpPort')}  ver={lookup.get('ver') or '?'}"
            )
            if not relay_base and lookup.get("relay"):
                relay_base = strip_slash(str(lookup["relay"]))
            # 只打印浏览器可能跳转的地址，默认不探测内网/公网 IP（外网测中继会全超时）
            jumps = connect_spa_jump_candidates(fn_id, lookup)
            if jumps:
                info("Connect 门户测速候选（默认不探测，需要时再加 --lan-base）：")
                for label, url in jumps:
                    info(f"  - {label}: {url}")
        else:
            fail(f"Connect 失败：{lookup.get('message')}")
        if not relay_base:
            relay_base = relay_base_from_fn_id(fn_id)
            info(f"未拿到云端 fn 字段，回退拼 {relay_base}（无 DNS/证书时会失败）")

    http_probe_bases: List[str] = []
    # 默认只打中继 / 用户指定入口，不扫内网、公网 IP、Connect 门户
    for b in (single, relay_base, lan_base):
        if b and b not in http_probe_bases:
            http_probe_bases.append(b)
    if not http_probe_bases:
        fail("请至少提供 --fn-id / --base / --relay-base / --lan-base 之一")
        return 2

    # DNS + HTTP。NAS os-web 抓包还会请求 locales / license，用来和 Connect 门户区分。
    nas_extra = ["/locales/zh-CN/os.json", "/license/v1/device/baseInfo"]
    for b in http_probe_bases:
        host = urllib.parse.urlparse(b).hostname or b
        info(f"DNS {host} -> {dns_probe(host)}")
        probe_http_page(b, "/", ua, args.timeout, args.insecure)
        probe_http_page(b, "/trimcon", ua, args.timeout, args.insecure)
        probe_http_page(b, "/p/", ua, args.timeout, args.insecure)
        host_l = (urllib.parse.urlparse(b).hostname or "").lower()
        if host_l.endswith(".fnos.net") or host_l.endswith(".5ddd.com"):
            for extra in nas_extra:
                probe_http_page(b, extra, ua, args.timeout, args.insecure)

    token = args.token.strip()
    long_token = args.long_token.strip()
    # 未显式给 --lan-base 时，登录和图库都走中继
    login_base = lan_base or single or relay_base
    gallery_base = single or relay_base or lan_base

    # 官方 Web 抓包已证明中继会转发 WSS；无账密时仍测 getRSAPub。
    if args.skip_ws:
        skip("已指定 --skip-ws")
    else:
        ws_targets = []
        for b in (relay_base, login_base):
            if b and b not in ws_targets:
                ws_targets.append(b)
        for b in ws_targets:
            probe_ws_rsa(b, ua, args.timeout, args.insecure)

    # WSS 登录：有账密且未给 token 时执行；混合路径在 lan 上登录
    if args.skip_ws:
        pass
    elif token:
        skip("已提供 --token，跳过 WSS 登录")
    elif args.user and args.password:
        info(f"在 {login_base} 做 WSS 登录（deviceName={args.device_name}）")
        result = ws_login(
            login_base,
            args.user,
            args.password,
            ua,
            args.timeout,
            args.insecure,
            args.otp,
            args.device_name,
            stay=True,
        )
        if result.get("ok"):
            ok(f"{result.get('message')}  uid={result.get('uid')}  token={str(result.get('token'))[:12]}...")
            token = str(result.get("token") or "")
            long_token = str(result.get("longToken") or long_token)
            if args.save_session:
                save_session(args.save_session, {
                    "loginBase": login_base,
                    "galleryBase": gallery_base,
                    "token": token,
                    "longToken": long_token,
                    "uid": result.get("uid"),
                    "signKeyB64": result.get("signKeyB64"),
                    "savedAt": int(time.time()),
                })
        else:
            fail(result.get("message") or "WSS 登录失败")
            if result.get("requires2fa"):
                info("加 --otp 后再跑一次")
            if login_base != gallery_base:
                info("若仅中继 WSS 失败、局域网成功：对照官方 Web 的 Origin/Cookie 后再比")
    elif not token:
        skip("未提供 --user/--password，跳过 WSS 登录（握手已测）")

    gallery_ok = False
    if args.skip_gallery:
        skip("已指定 --skip-gallery")
    elif not token and not args.cookie.strip():
        skip("没有 token/cookie，仍用 mode=relay 空会话打一枪图库（预期 401/空 data）")
        probe_gallery(gallery_base, "", "", "", ua, args.timeout, args.insecure)
    else:
        info(f"图库探测 {gallery_base}  （Cookie+authx+AccessToken）")
        gallery_ok = probe_gallery(
            gallery_base, token, long_token, args.cookie, ua, args.timeout, args.insecure
        )

    log("")
    log("==== 结论 ====")
    if lookup is not None:
        log(f"Connect: {'成功' if lookup.get('ok') else '失败'}  {lookup.get('message', '')}")
    log(f"HTTP 探测入口: {', '.join(http_probe_bases)}")
    log(f"WSS 登录入口: {login_base if (args.user and args.password and not args.skip_ws and not args.token) else '(未跑)'}")
    log(f"图库 /p: {'业务成功' if gallery_ok else '未成功或未登录'}")
    log("官方 Web 在中继子域名上会拉 os-web，并连 wss://host/websocket?type=main。")
    log("脚本若 DNS NXDOMAIN，多半是中继隧道未就绪；浏览器开着门户时子域名才会解析。")
    return 0 if gallery_ok or (lookup and lookup.get("ok")) else 1


if __name__ == "__main__":
    sys.exit(main())
