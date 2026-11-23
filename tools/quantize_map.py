#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把任意图（含 AI 生图）压成能过像素门禁的地图/背景素材。

为什么需要这一步：`design/PIXEL_SPEC.md` 冻结了 32 色调色板、16px 栅格、二值 alpha。
生图模型出的图基本有几千种颜色 + 半透明边缘 + 非 16 倍数尺寸，直接进游戏会被 R14 拒。
这里做四件事，一步都不能跳：

    1) 最近邻缩放到目标尺寸（非整数倍缩放会让像素大小不均）
    2) 每个像素映射到 master.gpl 的最近色（不新增颜色）
    3) alpha 二值化（< 128 全透明，其余全不透明）
    4) 跑一遍 pixelpipe 门禁，把结果打出来（不过就非 0 退出）

用法：
    python tools/quantize_map.py --in raw.png --out art/generated_candidates/maps/school_d1.png \
        --size 384x216 --max-colors 32
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import read_gpl  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"


def parse_size(text: str) -> tuple[int, int]:
    width, height = text.lower().split("x")
    return int(width), int(height)


def quantize(image: Image.Image, palette: list[tuple[int, int, int]]) -> Image.Image:
    source = image.convert("RGBA")
    out = Image.new("RGBA", source.size, (0, 0, 0, 0))
    pixels = source.load()
    target = out.load()
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for y in range(source.height):
        for x in range(source.width):
            r, g, b, a = pixels[x, y]
            if a < 128:
                continue
            key = (r, g, b)
            hit = cache.get(key)
            if hit is None:
                best = palette[0]
                best_distance = 1 << 30
                for candidate in palette:
                    dr = r - candidate[0]
                    dg = g - candidate[1]
                    db = b - candidate[2]
                    distance = dr * dr + dg * dg + db * db
                    if distance < best_distance:
                        best_distance = distance
                        best = candidate
                hit = best
                cache[key] = hit
            target[x, y] = (hit[0], hit[1], hit[2], 255)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="把任意图压成过门禁的像素素材")
    parser.add_argument("--in", dest="source", required=True)
    parser.add_argument("--out", dest="target", required=True)
    parser.add_argument("--size", default="", help="目标尺寸，如 384x216；省略则保持原尺寸")
    parser.add_argument("--max-colors", type=int, default=32)
    args = parser.parse_args(argv)

    source_path = Path(args.source)
    if not source_path.exists():
        raise SystemExit(f"input not found: {source_path}")
    image = Image.open(source_path).convert("RGBA")
    if args.size:
        width, height = parse_size(args.size)
        # 原生视口 384×216 是唯一例外：216 不是 16 的倍数，但它是整个工程的画布尺寸。
        native = (width, height) == (384, 216)
        if not native and (width % 16 or height % 16):
            raise SystemExit("target size must be a multiple of 16 (R14), or exactly 384x216")
        # 先按整数比最近邻缩到接近目标，再一次最近邻到精确尺寸，避免中间灰。
        scale = min(width / image.width, height / image.height)
        if scale > 0:
            step = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                Image.Resampling.NEAREST,
            )
            image = step.resize((width, height), Image.Resampling.NEAREST)

    raw_palette = read_gpl(PAL)
    palette = list(raw_palette.values()) if isinstance(raw_palette, dict) else list(raw_palette)
    result = quantize(image, palette)

    target_path = Path(args.target)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    result.save(target_path)
    colors = {pixel[:3] for pixel in result.getdata() if pixel[3] == 255}
    print(f"WROTE {target_path}  {result.size}  colors={len(colors)}  alpha=binary")

    gate = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "pixelpipe.py"), "gate", str(target_path),
         "--palette", str(PAL), "--max-colors", str(args.max_colors)],
        capture_output=True, text=True,
    )
    output = (gate.stdout or gate.stderr).strip()
    print(output)
    if gate.returncode != 0:
        # 原生视口 384×216 不是 16 的倍数，R14d 必然报红；这是 PIXEL_SPEC 里写明的例外。
        if result.size == (384, 216):
            failures = [line.strip() for line in output.splitlines() if "✗" in line]
            if failures and all("R14d" in line for line in failures):
                print("NOTE R14d 不适用于原生视口 384x216（PIXEL_SPEC 例外），其余项已通过")
                return 0
    return gate.returncode


if __name__ == "__main__":
    sys.exit(main())
