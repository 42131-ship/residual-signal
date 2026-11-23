#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""走廊 tile 集 v2 —— 按明度阶梯重建

为什么重做：
    v1 的 tile 全是近黑的近似色，铺起来是一堆横向色带，看不出「地板 / 墙 / 天花板」。
    参照《逃脱者 2》的可读性原则（每个物件有清晰剪影、平涂 + 一档暗部 + 一档亮部），
    这里先把**明度阶梯**钉死，再画东西：

        ceiling_void   #05070c   最暗（吞噬）
        wall_dark      #1b2430
        wall           #263140
        wall_hi        #33404f   腰线受光
        floor_dark     #2c3833
        floor          #3b4a43   最大的亮面
        floor_hi       #4a5a51   接缝受光
        outline        #0b0f14   1px 描边
        amber          #c8863a   唯一暖色

规矩（沿用 pixelpipe 的门禁）：
    16×16 网格 / 色全取 master.gpl / 无半透边缘 / 无渐变无抖动

用法：
    python tools/tile_build_v2.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated_candidates" / "tiles" / "TL-04_corridor_v2.png"
PAL = ROOT / "art" / "palettes" / "master.gpl"
T = 16

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def read_gpl(path: Path) -> list[tuple[int, int, int]]:
    out = []
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        p = ln.split()
        if len(p) >= 3 and all(x.isdigit() for x in p[:3]):
            out.append((int(p[0]), int(p[1]), int(p[2])))
    return out


def snap(c: tuple[int, int, int], pal: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    return min(pal, key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2 + (p[2] - c[2]) ** 2)


# ── 明度阶梯（会被 snap 到最近的调色板色）
LADDER = {
    "void": (3, 5, 10),
    "wall_dark": (6, 10, 18),
    "wall": (11, 17, 25),
    "wall_hi": (17, 26, 38),
    "floor_dark": (11, 17, 25),
    "floor": (31, 46, 63),
    "floor_hi": (53, 75, 96),
    "outline": (6, 10, 18),
    "amber": (94, 62, 38),
    "steel": (74, 98, 120),
}


def build(pal: list[tuple[int, int, int]]) -> tuple[Image.Image, list[str]]:
    C = {k: snap(v, pal) for k, v in LADDER.items()}
    specs: list[tuple[str, "callable"]] = []

    def ceiling_void(d: ImageDraw.ImageDraw, w: int, h: int) -> None:
        d.rectangle([0, 0, w - 1, h - 1], fill=C["void"])

    def wall_plain(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=C["wall"])
        d.rectangle([0, 0, w - 1, 1], fill=C["wall_dark"])

    def wall_dado(d, w, h):
        # 腰线：上暗下亮，一条硬边
        d.rectangle([0, 0, w - 1, h - 1], fill=C["wall"])
        d.rectangle([0, h - 5, w - 1, h - 5], fill=C["wall_dark"])
        d.rectangle([0, h - 4, w - 1, h - 1], fill=C["wall_hi"])
        d.rectangle([0, 0, w - 1, 0], fill=C["wall_dark"])

    def wall_cracked(d, w, h):
        wall_plain(d, w, h)
        pts = [(4, 2), (5, 5), (4, 8), (6, 11), (5, 14)]
        for i in range(len(pts) - 1):
            d.line([pts[i], pts[i + 1]], fill=C["wall_dark"])

    def wall_base(d, w, h):
        # 踢脚：底部两行压暗
        wall_plain(d, w, h)
        d.rectangle([0, h - 2, w - 1, h - 1], fill=C["outline"])

    def floor_tile(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=C["floor"])

    def floor_wet(d, w, h):
        floor_tile(d, w, h)
        d.rectangle([3, 6, 8, 9], fill=C["floor_hi"])
        d.rectangle([4, 7, 7, 8], fill=C["floor_dark"])

    def floor_scuffed(d, w, h):
        floor_tile(d, w, h)
        d.line([(2, 11), (6, 11)], fill=C["floor_dark"])
        d.line([(9, 5), (12, 5)], fill=C["floor_dark"])

    def locker(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=C["wall_dark"])
        d.rectangle([1, 1, w - 2, h - 2], fill=C["wall"])
        for x in (4, 8, 12):
            d.line([(x, 2), (x, h - 3)], fill=C["wall_dark"])
        d.rectangle([2, 6, 3, 7], fill=C["steel"])             # 把手

    def door(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=C["outline"])
        d.rectangle([1, 1, w - 2, h - 2], fill=C["wall_hi"])
        d.rectangle([3, 3, w - 4, 7], fill=C["void"])          # 破窗
        d.point([(5, 4), (6, 5), (7, 4)], fill=C["wall_hi"])
        d.rectangle([11, 9, 12, 10], fill=C["steel"])

    def desk_down(d, w, h):
        # 翻倒的桌子：一条腿朝天，剪影靠描边拉出来
        d.rectangle([1, 7, 14, 13], fill=C["outline"])
        d.rectangle([2, 8, 13, 12], fill=C["wall_hi"])
        d.line([(4, 8), (4, 3)], fill=C["outline"])
        d.line([(11, 8), (11, 4)], fill=C["outline"])

    def poster(d, w, h):
        d.rectangle([2, 2, 13, 12], fill=C["outline"])
        d.rectangle([3, 3, 12, 11], fill=C["wall_hi"])
        d.rectangle([5, 5, 10, 6], fill=C["wall_dark"])
        d.rectangle([5, 8, 9, 8], fill=C["wall_dark"])

    def light_dead(d, w, h):
        d.rectangle([1, 5, 14, 9], fill=C["outline"])
        d.rectangle([2, 6, 13, 8], fill=C["steel"])
        d.line([(6, 6), (9, 8)], fill=C["wall_dark"])
        d.line([(2, 4), (13, 4)], fill=C["outline"])

    def window_night(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=C["outline"])
        d.rectangle([1, 1, w - 2, h - 2], fill=C["void"])
        d.line([(w // 2, 1), (w // 2, h - 2)], fill=C["outline"])
        d.line([(1, h // 2), (w - 2, h // 2)], fill=C["outline"])
        d.rectangle([2, 9, 4, 11], fill=C["amber"])            # 远处一点暖光

    def papers(d, w, h):
        d.rectangle([0, 0, w - 1, h - 1], fill=C["floor"])
        d.rectangle([3, 5, 8, 8], fill=C["wall_hi"])
        d.rectangle([9, 9, 13, 11], fill=C["wall_hi"])

    def pipe_h(d, w, h):
        d.rectangle([0, 3, w - 1, 6], fill=C["outline"])
        d.rectangle([0, 4, w - 1, 5], fill=C["steel"])

    def vent(d, w, h):
        d.rectangle([1, 2, 14, 12], fill=C["outline"])
        d.rectangle([2, 3, 13, 11], fill=C["wall_dark"])
        for y in (5, 7, 9):
            d.line([(3, y), (12, y)], fill=C["steel"])

    specs = [
        ("ceiling_void", ceiling_void), ("wall_plain", wall_plain),
        ("wall_dado", wall_dado), ("wall_cracked", wall_cracked),
        ("wall_base", wall_base), ("floor_tile", floor_tile),
        ("floor_wet", floor_wet), ("floor_scuffed", floor_scuffed),
        ("locker", locker), ("door", door), ("desk_down", desk_down),
        ("poster", poster), ("light_dead", light_dead), ("window_night", window_night),
        ("papers", papers), ("pipe_h", pipe_h),
    ]

    cols = 8
    rows = (len(specs) + cols - 1) // cols
    img = Image.new("RGB", (cols * T, rows * T), C["void"])
    for i, (_name, fn) in enumerate(specs):
        cell = Image.new("RGB", (T, T), C["void"])
        fn(ImageDraw.Draw(cell), T, T)
        img.paste(cell, ((i % cols) * T, (i // cols) * T))

    return img, [n for n, _ in specs]


def main() -> int:
    pal = read_gpl(PAL)
    img, names = build(pal)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"{OUT}  {img.size}  {len(names)} 格")
    for i, n in enumerate(names):
        print(f"  {i:2d} {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

