#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""归属标记对照探针

v0.5 有一处自相矛盾：归属标记写成「暖橙 3×5」，而同一份文档又说
枪口闪光是「Day 3 之后唯一暖色光源」。两个都自称唯一。

定这种事不能靠嘴。这个脚本把四种方案画在**同一条走廊、同一套光照**里——
四个角色并排站，只有脚下的标记不同。这样"哪个是我"是在完全相同的
条件下比较的，不给任何一方额外优势。

四个方案：
    A  暖橙 3×5（v0.5 原文）
    B  中性灰 3×5（PIXEL_SPEC v1.0 临时处置）
    C  脚下影（比地板暗一档，比脚宽）
    D  不画（对照）

判据（写死，避免事后找理由）：
    1× 大小、不开任何辅助，能否在 3 秒内指出哪个是自己
    同时不能稀释「暖色 = 你在暴露自己」这条语义
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import named_map  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"
OUT = ROOT / "design" / "previews" / "MARKER_probe.png"

W, H = 256, 48
FLOOR_Y = 28
FEET_Y = 42
XS = [20, 84, 148, 212]          # 四个角色的 x
VARIANTS = ["A", "B", "C", "D"]
LABELS = {"A": "暖橙3x5", "B": "灰3x5", "C": "脚下影", "D": "对照"}


def draw_character(d: ImageDraw.ImageDraw, P: dict, x: int) -> None:
    top = FEET_Y - 18
    d.rectangle([x + 3, top, x + 6, top + 4], fill=P["c26_skin"])
    d.rectangle([x + 2, top + 5, x + 7, top + 12], fill=P["c23_cloth"])
    d.rectangle([x, top + 6, x + 1, top + 11], fill=P["c25_leather"])
    d.rectangle([x + 3, top + 13, x + 4, FEET_Y], fill=P["c02_dark"])
    d.rectangle([x + 5, top + 13, x + 6, FEET_Y], fill=P["c02_dark"])


def marker(d: ImageDraw.ImageDraw, P: dict, x: int, v: str) -> None:
    if v == "A":
        d.rectangle([x + 3, FEET_Y - 4, x + 5, FEET_Y], fill=P["c14_warm"])
        d.point((x + 4, FEET_Y - 5), fill=P["c15_warm_high"])
    elif v == "B":
        d.rectangle([x + 3, FEET_Y - 4, x + 5, FEET_Y], fill=P["c21_grey"])
        d.point((x + 4, FEET_Y - 5), fill=P["c22_grey_lit"])
    elif v == "C":
        d.ellipse([x - 3, FEET_Y - 1, x + 9, FEET_Y + 3], fill=P["c01_shadow"])
        d.line([x - 3, FEET_Y + 3, x + 9, FEET_Y + 3], fill=P["c02_dark"])


def build_fade() -> Image.Image:
    """方案 D 的实现：暖橙 3×5 只在 Day 0–2 存在，Day 3 断电当夜褪掉，之后不再出现。

    五格 = Day0 / Day1 / Day2 / Day3（褪） / Day4+（无）
    颜色按日历退档，不靠透明度（调色板没有 alpha）：
        Day0  c14_warm + c15_warm_high
        Day1  c14_warm
        Day2  c13_warm_dim
        Day3  c02_dark（只剩一个几乎看不见的印子）
        Day4+ 不画
    """
    P = named_map(PAL)
    steps = [("c14_warm", "c15_warm_high"), ("c14_warm", None),
             ("c13_warm_dim", None), ("c02_dark", None), (None, None)]
    gap = 32
    img = Image.new("RGB", (W + gap * (len(steps) - 1), H), P["c01_shadow"])
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, W + gap * (len(steps) - 1) - 1, FLOOR_Y - 1], fill=P["c03_wall"])
    d.line([0, 0, W + gap * (len(steps) - 1) - 1, 0], fill=P["c05_lit"])
    d.line([0, FLOOR_Y - 1, W + gap * (len(steps) - 1) - 1, FLOOR_Y - 1], fill=P["c02_dark"])
    d.rectangle([0, FLOOR_Y, W + gap * (len(steps) - 1) - 1, H - 1], fill=P["c04_floor"])
    d.line([0, H - 1, W + gap * (len(steps) - 1) - 1, H - 1], fill=P["c02_dark"])

    for i, (body, hi) in enumerate(steps):
        x = 24 + i * 72
        draw_character(d, P, x)
        if body:
            # 去掉顶部的亮点：那一点会让它读成「一盏小灯」而不是「一个标记」
            d.rectangle([x + 3, FEET_Y - 3, x + 5, FEET_Y], fill=P[body])
        if hi:
            d.point((x + 4, FEET_Y - 2), fill=P[hi])
    return img


def main() -> int:
    P = named_map(PAL)
    img = Image.new("RGB", (W, H), P["c01_shadow"])
    d = ImageDraw.Draw(img)

    # 同一条走廊
    d.rectangle([0, 0, W - 1, FLOOR_Y - 1], fill=P["c03_wall"])
    d.line([0, 0, W - 1, 0], fill=P["c05_lit"])
    d.line([0, FLOOR_Y - 1, W - 1, FLOOR_Y - 1], fill=P["c02_dark"])
    d.rectangle([0, FLOOR_Y, W - 1, H - 1], fill=P["c04_floor"])
    d.line([0, H - 1, W - 1, H - 1], fill=P["c02_dark"])
    # 墙面接缝，给空间一点纵深参照
    for x in range(48, W, 64):
        d.line([x, 8, x, FLOOR_Y - 1], fill=P["c02_dark"])

    for x, v in zip(XS, VARIANTS):
        draw_character(d, P, x)
        marker(d, P, x, v)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    img.resize((W * 6, H * 6), Image.NEAREST).save(OUT.with_name("MARKER_probe_x6.png"))
    print(f"{OUT}  {img.size}")
    print("左→右：" + " · ".join(f"{v}={LABELS[v]}" for v in VARIANTS))

    fade = build_fade()
    fout = OUT.with_name("MARKER_fade.png")
    fade.save(fout)
    fade.resize((fade.width * 4, fade.height * 4), Image.NEAREST).save(
        fout.with_name("MARKER_fade_x4.png"))
    print(f"{fout}  {fade.size}")
    print("左→右：Day0 · Day1 · Day2 · Day3(褪) · Day4+(无)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
