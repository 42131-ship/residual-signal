#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""资产入库：门禁不过，就进不了 manifest

这条脚本是「流程」的执行器，不是文档。它保证下面这句话成立：
    **没有 gate 通过的资产，物理上进不了 art/asset-manifest.json。**

两种用法：
    # ① 散装：一组同类别文件
    python tools/asset_intake.py --files a.png b.png --category character --id-prefix chr_x

    # ② 清单：按构造器产出的 candidates 批量入库（推荐，能带 derived_from / slots）
    python tools/asset_intake.py --spec art/generated_candidates/characters/characters.candidates.json

门禁不过 → 打印违规项、退出 1、**manifest 原样不动**。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import BG_MAX, FRAME_MAX, gate, read_gpl  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"
MANIFEST = ROOT / "art" / "asset-manifest.json"
FRAME_CATS = {"character", "tile", "prop_icon", "ui", "weapon_layer", "zombie_variant", "vfx", "font"}
BIG_CATS = {"background", "parallax", "tile_sheet"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def load_manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {"schema": "asset-manifest.v1", "assets": []}


def resolve(p: str) -> Path:
    path = Path(p)
    return path if path.is_absolute() else ROOT / path


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="资产入库（门禁不过就拒收）")
    ap.add_argument("--spec", help="批量清单 JSON（assets[] 含 asset_id/category/output_path 等）")
    ap.add_argument("--files", nargs="+", default=[])
    ap.add_argument("--category", choices=sorted(FRAME_CATS | BIG_CATS))
    ap.add_argument("--id-prefix")
    ap.add_argument("--source", choices=["authoritative", "generated"], default="authoritative")
    ap.add_argument("--derived-from", default=None)
    ap.add_argument("--provenance", default="{}", help="JSON: model/provider/input_assets")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    palette = read_gpl(PAL)
    prov = json.loads(args.provenance)

    tasks: list[tuple[Path, dict]] = []
    if args.spec:
        spec = json.loads(resolve(args.spec).read_text(encoding="utf-8"))
        for a in spec.get("assets", []):
            tasks.append((resolve(a["output_path"]), dict(a)))
    else:
        if not (args.category and args.id_prefix):
            raise SystemExit("散装模式需要 --category 与 --id-prefix")
        for i, f in enumerate(args.files):
            aid = f"{args.id_prefix}_{i:02d}" if len(args.files) > 1 else args.id_prefix
            tasks.append((resolve(f), {
                "asset_id": aid, "category": args.category,
                "source": args.source, "derived_from": args.derived_from,
            }))

    passed, failed = [], []
    for path, meta in tasks:
        cat = meta.get("category", "character")
        cap = BG_MAX if cat in BIG_CATS else FRAME_MAX
        aid = meta.get("asset_id", path.stem)
        if not path.exists():
            failed.append((aid, ["文件不存在"]))
            print(f"[MISS] {aid}  {path}")
            continue
        r = gate(path, palette, max_colors=cap,
                 per_tile=16 if cat == "tile_sheet" else 0)
        if r["pass"]:
            passed.append((path, meta, r))
            print(f"[PASS] {aid:<28} {r['size'][0]}×{r['size'][1]:<4} {r['colors']:>2} 色")
        else:
            bad = [k for k, v in r["checks"].items() if not v]
            if r["off_palette"]:
                bad.append(f"调色板外 {len(r['off_palette'])} 色")
            failed.append((aid, bad))
            print(f"[FAIL] {aid:<28} {'; '.join(bad)}")

    if failed:
        print(f"\n拒收 {len(failed)} 个，manifest 未改动。")
        return 1
    if args.dry_run:
        print(f"\n候选 {len(passed)} 个全部合格（dry-run，未写入）")
        return 0

    man = load_manifest()
    by_id = {a.get("asset_id"): a for a in man["assets"]}
    for path, meta, r in passed:
        aid = meta["asset_id"]
        entry = {
            "asset_id": aid,
            "category": meta.get("category", "character"),
            "grid": list(r["size"]),
            "palette": "art/palettes/master.gpl",
            "source": meta.get("source", "authoritative"),
            "status": meta.get("status", "draft"),
            "pixel_gate": "pass",
            "pixel_colors": r["colors"],
            "sha256": sha256(path),
            "output_path": str(path.relative_to(ROOT)).replace("\\", "/"),
            "derived_from": meta.get("derived_from"),
            "accessory_slots": meta.get("accessory_slots"),
            "npc_ref": meta.get("npc_ref"),
            "directions": meta.get("directions", ["r"]),
            "reviewer": None,
            "approved_at": None,
            "provider": prov.get("model") or prov.get("provider") or meta.get("provider"),
            "input_refs": prov.get("input_assets", []),
            "ingested_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }
        by_id[aid] = entry
    man["assets"] = sorted(by_id.values(), key=lambda a: a["asset_id"])
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n写入 manifest：{len(passed)} 条（status=draft），总计 {len(man['assets'])} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
