#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""下载华为审核测试账号用图：Commons 自由许可风景 + 公开人物肖像。"""

from __future__ import annotations

import json
import re
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "review-test-photos"
UA = "FMphotoReviewAssets/1.0 (HarmonyOS app review sample photos; non-commercial)"
CTX = ssl.create_default_context()

# 场景差距尽量大，方便 NAS 场景识别
SCENES: list[tuple[str, list[str], int]] = [
    ("分类-海边", ["Category:Featured pictures of beaches", "tropical beach coastline photograph"], 8),
    ("分类-沙漠", ["Category:Featured pictures of deserts", "sahara sand dunes desert landscape"], 8),
    ("分类-森林", ["Category:Featured pictures of forests", "sunlight dense forest trees photograph"], 8),
    ("分类-雪山", ["Category:Featured pictures of mountains", "snow mountain peak landscape"], 6),
    ("分类-城市夜景", ["city skyline at night photograph", "urban night lights skyline"], 6),
    ("分类-草原", ["green grassland prairie landscape photograph", "savanna grassland photograph"], 6),
    ("分类-瀑布", ["Category:Featured pictures of waterfalls", "waterfall cascade landscape photograph"], 6),
    ("分类-星空", ["milky way night sky photograph", "starry night landscape photograph"], 6),
    ("分类-湖泊", ["alpine lake reflection photograph", "mountain lake landscape photograph"], 6),
    ("分类-田野", ["wheat field farmland photograph", "rice terrace paddy field photograph"], 6),
    ("分类-冰川", ["glacier ice landscape photograph", "polar iceberg glacier photograph"], 5),
    ("分类-火山", ["volcano crater landscape photograph", "volcanic mountain landscape"], 5),
    ("分类-极光", ["aurora borealis northern lights photograph", "aurora night sky photograph"], 5),
    ("分类-峡谷", ["canyon cliffs landscape photograph", "grand canyon landscape photograph"], 5),
]

# 同一人多张，便于人脸聚类。仅 Commons 自由许可公开照，不下载商业图库/未授权写真
PEOPLE: list[tuple[str, list[str], list[str], int]] = [
    ("人物-成龙", ["Jackie Chan"], ["Jackie Chan photograph", "Jackie Chan Cannes", "Jackie Chan portrait"], 6),
    ("人物-李连杰", ["Jet Li"], ["Jet Li photograph", "Jet Li portrait Cannes"], 5),
    ("人物-杨紫琼", ["Michelle Yeoh"], ["Michelle Yeoh photograph", "Michelle Yeoh portrait"], 5),
    ("人物-姚明", ["Yao Ming"], ["Yao Ming basketball photograph", "Yao Ming portrait"], 5),
    ("人物-刘翔", ["Liu Xiang"], ["Liu Xiang hurdler photograph", "Liu Xiang athlete"], 5),
    ("人物-梅西", ["Lionel Messi", "Messi"], ["Lionel Messi photograph", "Lionel Messi portrait"], 5),
    ("人物-奥巴马", ["Barack Obama", "Obama"], ["Barack Obama official portrait", "Barack Obama 2015 photograph"], 6),
]

FREE_LICENSE_HINTS = (
    "cc0",
    "cc by",
    "cc-by",
    "cc by-sa",
    "cc-by-sa",
    "public domain",
    "pdm",
    "copyrighted free use",
)
BLOCK_LICENSE_HINTS = ("fair use", "non-free", "all rights reserved")
SKIP_TITLE = (
    "department store",
    "family portrait",
    "cabinet",
    "aerial photograph",
    "map of",
    "logo",
    "flag of",
    "signature",
    "autograph",
    "diagram",
    "svg",
)


def http_get(url: str, timeout: int = 45) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as resp:
        return resp.read()


def http_get_json(url: str) -> dict:
    return json.loads(http_get(url).decode("utf-8"))


def safe_name(text: str, fallback: str = "image") -> str:
    text = re.sub(r"[^\w\u4e00-\u9fff\-]+", "_", text, flags=re.UNICODE).strip("_")
    return (text[:72] or fallback)


def is_photo_file(name: str, mime: str = "") -> bool:
    name = name.lower()
    mime = mime.lower()
    if any(x in name for x in (".svg", ".pdf", ".gif", ".tif")):
        return False
    if mime and mime not in ("image/jpeg", "image/jpg", "image/png", "image/webp"):
        return False
    return True


def license_ok(text: str) -> bool:
    low = (text or "").lower()
    if not low or any(x in low for x in BLOCK_LICENSE_HINTS):
        return False
    if "by-nc" in low or "noncommercial" in low or "non-commercial" in low:
        return False
    return any(x in low for x in FREE_LICENSE_HINTS)


def ext_of(url: str, mime: str = "") -> str:
    if "png" in mime:
        return "png"
    if "webp" in mime:
        return "webp"
    path = urllib.parse.urlparse(url).path.lower()
    for ext in ("jpg", "jpeg", "png", "webp"):
        if path.endswith("." + ext):
            return "jpg" if ext == "jpeg" else ext
    return "jpg"


def download_file(url: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    try:
        data = http_get(url, timeout=70)
        if len(data) < 25_000:
            return False
        tmp.write_bytes(data)
        tmp.replace(dest)
        return True
    except (urllib.error.URLError, TimeoutError, OSError, ssl.SSLError):
        if tmp.exists():
            tmp.unlink(missing_ok=True)
        return False


def commons_query(extra: dict) -> list[dict]:
    params = {
        "action": "query",
        "format": "json",
        "prop": "imageinfo",
        "iiprop": "url|size|extmetadata|mime",
        "iiurlwidth": "1600",
    }
    params.update(extra)
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    try:
        data = http_get_json(url)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ssl.SSLError, urllib.error.HTTPError):
        return []
    pages = (data.get("query") or {}).get("pages") or {}
    items = [p for p in pages.values() if int(p.get("ns") or 0) == 6]
    items.sort(key=lambda x: int(x.get("index") or x.get("pageid") or 0))
    return items


def search_commons(query: str, limit: int = 24) -> list[dict]:
    return commons_query(
        {
            "generator": "search",
            "gsrsearch": query,
            "gsrnamespace": "6",
            "gsrlimit": str(limit),
        }
    )


def category_commons(category: str, limit: int = 24) -> list[dict]:
    title = category if category.startswith("Category:") else f"Category:{category}"
    return commons_query(
        {
            "generator": "categorymembers",
            "gcmtitle": title,
            "gcmtype": "file",
            "gcmlimit": str(limit),
        }
    )


def meta_of(info: dict) -> tuple[str, str, str, str]:
    ext = info.get("extmetadata") or {}

    def val(key: str) -> str:
        node = ext.get(key) or {}
        return re.sub(r"<[^>]+>", "", str(node.get("value") or ""))

    license_name = val("LicenseShortName") or val("UsageTerms") or val("License")
    artist = val("Artist") or val("Credit") or "unknown"
    desc = val("ObjectName") or val("ImageDescription") or ""
    landing = str(info.get("descriptionurl") or "")
    return license_name, artist, desc, landing


def candidate_ok(page: dict, require_any: list[str] | None = None) -> tuple[dict, str, str, str, str] | None:
    infos = page.get("imageinfo") or []
    if not infos:
        return None
    info = infos[0]
    title = str(page.get("title") or "")
    low = title.lower()
    mime = str(info.get("mime") or "")
    url = str(info.get("thumburl") or info.get("url") or "")
    width = int(info.get("thumbwidth") or info.get("width") or 0)
    height = int(info.get("thumbheight") or info.get("height") or 0)
    license_name, artist, desc, landing = meta_of(info)
    if not url or not is_photo_file(title, mime=mime):
        return None
    if any(x in low for x in SKIP_TITLE):
        return None
    if not license_ok(license_name):
        return None
    if min(width, height) < 500:
        return None
    if require_any:
        blob = f"{title} {desc}".lower()
        if not any(key.lower() in blob for key in require_any):
            return None
        if "department store" in blob or "family portrait" in blob:
            return None
    return info, url, license_name, artist, landing


def collect_folder(folder: str, queries: list[str], need: int, require_any: list[str] | None = None) -> list[dict]:
    dest_dir = OUT_DIR / folder
    existing = [p for p in dest_dir.glob("*") if p.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp")]
    got = len(existing)
    records: list[dict] = []
    seen = {p.stem.lower() for p in existing}
    print(f"[{folder}] start have={got} need={need}")
    for query in queries:
        if got >= need:
            break
        pages = category_commons(query, 30) if query.startswith("Category:") else search_commons(query, 30)
        print(f"  query {query} hits={len(pages)}")
        for page in pages:
            if got >= need:
                break
            parsed = candidate_ok(page, require_any)
            if not parsed:
                continue
            info, url, license_name, artist, landing = parsed
            title = str(page.get("title") or "photo")
            stem = safe_name(title.replace("File:", ""))
            if stem.lower() in seen:
                continue
            ext = ext_of(url, str(info.get("mime") or ""))
            dest = dest_dir / f"{got + 1:02d}-{stem}.{ext}"
            if download_file(url, dest):
                seen.add(stem.lower())
                got += 1
                records.append(
                    {
                        "file": str(dest.relative_to(OUT_DIR)),
                        "title": title,
                        "creator": artist,
                        "license": license_name,
                        "source": landing or url,
                    }
                )
                print(f"  saved {dest.name}")
            time.sleep(0.35)
        time.sleep(0.5)
    print(f"[{folder}] got {got}/{need}")
    return records


def cleanup_bad_people() -> None:
    roots = list((OUT_DIR / "20-公开人物肖像").glob("**/*")) + list(OUT_DIR.glob("人物-*/*"))
    for path in roots:
        if not path.is_file():
            continue
        name = path.name.lower()
        if any(x in name for x in ("department_store", "family_portrait", "full_cabinet", "lebron_james")):
            path.unlink(missing_ok=True)
            print(f"removed bad file {path.name}")


def write_sources(records: list[dict]) -> None:
    lines = [
        "# 审核测试图来源与许可",
        "",
        "本目录分类风景 / 公开人物肖像仅用于华为应用审核测试账号与 NAS AI 识别，不入库。",
        "全部来自 Wikimedia Commons 上 CC0 / 公有领域 / CC BY / CC BY-SA 照片。",
        "未下载商业图库、狗仔队或未授权明星写真。",
        "",
        "| 文件 | 作者 | 许可 | 来源 |",
        "| --- | --- | --- | --- |",
    ]
    old = OUT_DIR / "SOURCES.md"
    if old.exists():
        # 保留此前条目，避免覆盖已有图的署名
        for line in old.read_text(encoding="utf-8").splitlines():
            if line.startswith("| `") and line not in lines:
                lines.append(line)
    for item in records:
        creator = str(item.get("creator") or "").replace("|", "/")
        title = str(item.get("title") or "").replace("|", "/")
        row = f"| `{item['file']}` | {creator} / {title} | {item.get('license')} | {item.get('source')} |"
        if row not in lines:
            lines.append(row)
    (OUT_DIR / "SOURCES.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cleanup_bad_people()
    records: list[dict] = []
    for folder, queries, need in SCENES:
        records.extend(collect_folder(folder, queries, need))
    for folder, keys, queries, need in PEOPLE:
        records.extend(collect_folder(folder, queries, need, require_any=keys))
    write_sources(records)
    print(f"done new={len(records)} dir={OUT_DIR}")


if __name__ == "__main__":
    main()
