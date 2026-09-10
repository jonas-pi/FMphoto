#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补下更典型的海边/雪山，并删掉明显跑题图。"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from download_review_test_photos import (  # noqa: E402
    OUT_DIR,
    collect_folder,
    commons_query,
    download_file,
    ext_of,
    meta_of,
    safe_name,
    write_sources,
)

BAD_NAME_BITS = (
    "ensis_ensis",
    "crown_of_thorns_starfish",
    "australia_cairns_01",  # 红树林幼苗特写
    "chimney_rock_trail",
    "machu_picchu",
    "crkva_gospa",
    "tianzishan",
    "zhangjiajie",
    "bali_khila",
    "police_horse",
    "lebron_james",
    "zuckerberg",
    "kazan_2015",
    "department_store",
    "family_portrait",
    "full_cabinet",
    "emi_koussi",  # 卫星图
    "linear_dunes_great_sand_sea_egypt_-_nasa",
)

EXACT_FILES = {
    "分类-海边": [
        "File:Anse Source d'Argent 2-La Digue.jpg",
        "File:Whitehaven Beach.jpg",
        "File:Navagio – Shipwreck Beach, Zakynthos.jpg",
        "File:Maya Bay Ko Phi Phi Lee.jpg",
        "File:Tulum (16525955117).jpg",
        "File:Bondi Beach, New South Wales, Australia.jpg",
        "File:Waikiki Beach April 2015.JPG",
        "File:Maldives 10 2014 53.jpg",
        "File:Railay Beach Krabi Thailand.jpg",
        "File:Pantai Pink, Lombok.jpg",
    ],
    "分类-雪山": [
        "File:Matterhorn from Domhütte - 2.jpg",
        "File:Everest North Face toward Base Camp Tibet Luca Galuzzi 2006.jpg",
        "File:Mont Blanc from Aiguille du Midi.jpg",
        "File:Aoraki Mount Cook.jpg",
        "File:Denali (Mount McKinley).jpg",
        "File:K2 2006b.jpg",
        "File:Aconcagua 2009.jpg",
        "File:Snow-covered mountains in Valais.jpg",
    ],
}


def delete_bad() -> int:
    n = 0
    for path in OUT_DIR.rglob("*"):
        if not path.is_file():
            continue
        name = path.name.lower()
        if any(bit in name for bit in BAD_NAME_BITS):
            path.unlink(missing_ok=True)
            print(f"removed {path.relative_to(OUT_DIR)}")
            n += 1
    return n


def download_exact(folder: str, titles: list[str]) -> list[dict]:
    dest_dir = OUT_DIR / folder
    existing = list(dest_dir.glob("*.jpg")) + list(dest_dir.glob("*.png")) + list(dest_dir.glob("*.webp"))
    got = len(existing)
    seen = {p.stem.lower() for p in existing}
    records: list[dict] = []
    # MediaWiki titles 一次最多约 50
    pages = commons_query({"titles": "|".join(titles)})
    print(f"[{folder}] exact hits={len(pages)} have={got}")
    for page in pages:
        if page.get("missing") is not None:
            continue
        infos = page.get("imageinfo") or []
        if not infos:
            print(f"  missing {page.get('title')}")
            continue
        info = infos[0]
        title = str(page.get("title") or "photo")
        url = str(info.get("thumburl") or info.get("url") or "")
        license_name, artist, _, landing = meta_of(info)
        stem = safe_name(title.replace("File:", ""))
        if not url or stem.lower() in seen:
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
            print(f"  saved {dest.name} ({license_name})")
    return records


def main() -> None:
    delete_bad()
    records: list[dict] = []
    for folder, titles in EXACT_FILES.items():
        records.extend(download_exact(folder, titles))
    records.extend(
        collect_folder(
            "人物-李连杰",
            ["Jet Li 2006", "Jet Li Davos", "Jet Li 2010 photograph"],
            5,
            require_any=["Jet Li"],
        )
    )
    records.extend(
        collect_folder(
            "人物-刘翔",
            ["Liu Xiang 2004 Olympics", "Liu Xiang 110 metres hurdles"],
            5,
            require_any=["Liu Xiang"],
        )
    )
    write_sources(records)
    print(f"supplement new={len(records)}")


if __name__ == "__main__":
    main()
