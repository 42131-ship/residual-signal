#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把当前楼位锚点画到背景上，带坐标网格，方便对着底图校正。

为什么需要：生图底图我看不到，锚点是否压在楼上是你的眼睛说了算。
这张图把 32px 网格、坐标数字和当前锚点（十字 + id）叠上去，
你只要说「学校应该往右 12、往下 6」，我改 data/travel/map_layout.json 就行。

用法：
    python tools/map_layout_probe.py            # -> design/previews/MAP_LAYOUT_probe.png
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG = ROOT / "art" / "generated_candidates" / "maps" / "map_topdown.png"
LAYOUT = ROOT / "data" / "travel" / "map_layout.json"
OUT = ROOT / "design" / "previews" / "MAP_LAYOUT_probe.png"
SCALE = 3
GRID = 32


def main() -> int:
    if not BG.exists():
        raise SystemExit(f"missing background: {BG}")
    base = Image.open(BG).convert("RGB")
    width, height = base.size
    canvas = base.copy()
    draw = ImageDraw.Draw(canvas)

    for x in range(0, width, GRID):
        draw.line([(x, 0), (x, height)], fill=(60, 80, 96), width=1)
        draw.text((x + 1, 1), str(x), fill=(150, 170, 180))
    for y in range(0, height, GRID):
        draw.line([(0, y), (width, y)], fill=(60, 80, 96), width=1)
        draw.text((1, y + 1), str(y), fill=(150, 170, 180))

    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    for entry in layout.get("buildings", []):
        ax, ay = entry["at"]
        sw, sd = entry["size"]
        h = entry["height"]
        # 锚点十字
        draw.line([(ax - 5, ay), (ax + 5, ay)], fill=(255, 90, 90), width=1)
        draw.line([(ax, ay - 5), (ax, ay + 5)], fill=(255, 90, 90), width=1)
        # 楼体轮廓（正面 + 顶面斜边）
        draw.rectangle([ax, ay - h, ax + sw, ay], outline=(120, 220, 220), width=1)
        draw.polygon([
            (ax, ay - h), (ax + sw, ay - h),
            (ax + sw + sd * 0.6, ay - h - sd), (ax + sd * 0.6, ay - h - sd),
        ], outline=(120, 220, 220))
        draw.text((ax + 2, ay - h - sd - 10), f'{entry["id"]} ({ax},{ay})', fill=(240, 240, 230))

    canvas = canvas.resize((width * SCALE, height * SCALE), Image.Resampling.NEAREST)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT)
    print(f"WROTE {OUT}  {canvas.size}  anchors={len(layout.get('buildings', []))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
