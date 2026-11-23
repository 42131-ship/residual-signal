#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""反向导入：读分层 PSD（我们的，或 see-through 真跑出来的），落成层表 + 图层 PNG，并验无损。

这是「接入 see-through」的另一半：上游只出 PSD，我们得能读。
读进来之后：
    - 层名必须落在官方 23 个语义名里（--strict 时不是就失败）
    - 按 bbox 把层贴回画布，必须与 --expect 指定的静态精灵**逐像素一致**

用法：
    python tools/see_through_import.py --psd art/.../layers/player.psd \
        --expect art/.../characters/SPR-player_32x48.png
    python tools/see_through_import.py --psd workspace/layerdiff_output/xxx.psd \
        --out art/imported/xxx --strict
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TAGS = ROOT / "data" / "see_through" / "bodytags_v3.json"


def official_names() -> list[str]:
    if not TAGS.exists():
        raise SystemExit(f"missing taxonomy, run tools/see_through_sync.py first: {TAGS}")
    return list(json.loads(TAGS.read_text(encoding="utf-8")).keys())


def import_psd(psd_path: Path, out_dir: Path, expect: Path | None, strict: bool) -> int:
    from psd_tools import PSDImage

    psd = PSDImage.open(str(psd_path))
    width, height = psd.size
    known = official_names()
    out_dir.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    rows = []
    for order, layer in enumerate(psd.descendants()):
        image = layer.topil()
        if image is None:
            continue
        image = image.convert("RGBA")
        left, top, right, bottom = [int(v) for v in layer.bbox]
        name = layer.name
        if name not in known:
            message = f"layer {name!r} is not in the official taxonomy"
            if strict:
                raise SystemExit(message)
            print("WARN " + message)
        if image.size != (right - left, bottom - top):
            raise SystemExit(f"{name}: PIL size {image.size} != bbox {(right - left, bottom - top)}")
        filename = f"{order:02d}_{name.replace(' ', '_')}.png"
        image.save(out_dir / filename)
        if image.size != (1, 1):
            canvas.alpha_composite(image, (left, top))
        rows.append({
            "order": order,
            "layer": name,
            "file": filename,
            "rect": [left, top, right - left, bottom - top],
            "pivot": [left + (right - left) // 2, bottom],
        })

    (out_dir / "layers.json").write_text(json.dumps({
        "schema": "see-through-layers.v1",
        "source_psd": str(psd_path),
        "size": [width, height],
        "decomposition": "psd-import",
        "layers": rows,
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    if expect is not None:
        reference = Image.open(expect).convert("RGBA")
        if reference.size != (width, height):
            raise SystemExit(f"expect size {reference.size} != psd {(width, height)}")
        if canvas.tobytes() != reference.tobytes():
            differing = sum(
                1 for a, b in zip(canvas.getdata(), reference.getdata()) if a != b
            )
            raise SystemExit(f"reassembled layers differ from {expect.name} at {differing} px")
        print(f"VERIFY_OK layers={len(rows)} exact={expect.name}")
    else:
        print(f"IMPORT_OK layers={len(rows)}")
    return len(rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="导入分层 PSD（see-through 契约）")
    parser.add_argument("--psd", required=True)
    parser.add_argument("--out", help="输出目录（默认 art/imported/<psd 名>）")
    parser.add_argument("--expect", help="用于逐像素比对的静态精灵")
    parser.add_argument("--strict", action="store_true", help="层名不在官方表里就失败")
    args = parser.parse_args(argv)

    psd_path = Path(args.psd)
    if not psd_path.exists():
        raise SystemExit(f"psd not found: {psd_path}")
    out_dir = Path(args.out) if args.out else ROOT / "art" / "imported" / psd_path.stem
    import_psd(psd_path, out_dir, Path(args.expect) if args.expect else None, args.strict)
    return 0


if __name__ == "__main__":
    sys.exit(main())
