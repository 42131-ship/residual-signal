#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""美术开工 guide 三张（A1）

这三张不是游戏资产，是**给画的人看的对齐图**。目的只有一个：
把「光只来自上方 / 不做渐变 / 每个色有活」这三条从文字变成能对着抄的东西。

尺寸都取 16 的整数倍，而且只用 master.gpl 里的颜色——
所以它们自己也能过门禁，guide 本身就是合格的像素图，不是示意图。

    G1_light_direction.png   64×64  受光方向与三档色阶的用法
    G2_no_gradient.png       96×48  左边对（两档硬边）/ 右边错（多档过渡）
    G3_palette_roles.png    128×96  32 色按角色分区上墙
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import named_map  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"
OUT = ROOT / "design" / "guides"


def g1(P: dict) -> Image.Image:
    """受光方向：顶面 c06_top、正面 c05_lit、暗部 c02_dark。三个方块一块地板。"""
    im = Image.new("RGB", (64, 64), P["c01_shadow"])
    d = ImageDraw.Draw(im)
    d.rectangle([0, 40, 63, 63], fill=P["c04_floor"])
    d.line([0, 40, 63, 40], fill=P["c06_top"])
    d.line([0, 63, 63, 63], fill=P["c02_dark"])

    def box(x: int, y: int, w: int, h: int, top: dict) -> None:
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=P["c05_lit"])      # 正面
        d.rectangle([x, y, x + w - 1, y], fill=P[top["t"]])               # 顶面
        d.rectangle([x + w - 2, y, x + w - 1, y + h - 1], fill=P["c02_dark"])  # 右侧暗
        d.line([x, y + h - 1, x + w - 1, y + h - 1], fill=P["c02_dark"])  # 底边暗

    box(6, 26, 12, 14, {"t": "c06_top"})
    box(26, 30, 10, 10, {"t": "c06_top"})
    box(44, 22, 14, 18, {"t": "c06_top"})
    # 一个反例：顶面用了暗色 —— 读起来像被挖掉一块
    d.rectangle([8, 46, 17, 57], fill=P["c05_lit"])
    d.line([8, 46, 17, 46], fill=P["c02_dark"])
    return im


def g2(P: dict) -> Image.Image:
    """左边两档硬边（对），右边多档过渡（错）。"""
    im = Image.new("RGB", (96, 48), P["c01_shadow"])
    d = ImageDraw.Draw(im)
    # 左：只允许两档 —— c03_wall -> c05_lit
    d.rectangle([0, 8, 39, 39], fill=P["c03_wall"])
    d.rectangle([0, 8, 39, 15], fill=P["c05_lit"])
    d.line([0, 39, 39, 39], fill=P["c02_dark"])
    # 右：用同一族颜色插出 8 档 —— 正是要禁的
    ramp = ["c02_dark", "c03_wall", "c05_lit", "c06_top", "c07_edge",
            "c09_coldmid", "c10_coldhigh", "c15_warm_high"]
    for i, name in enumerate(ramp):
        d.rectangle([48, 8 + i * 4, 95, 11 + i * 4], fill=P[name])
    return im


def g3(P: dict) -> Image.Image:
    """32 色按家族分行上墙：冷色阶 / 冷光 / 冷光源 / 暖光 / 土锈血 / UI / 布皮 / 皮肤 / 死亡 / 极值。"""
    fams = [
        ("c00_void", "c01_shadow", "c02_dark", "c03_wall", "c04_floor", "c05_lit", "c06_top", "c07_edge"),
        ("c08_coldtone", "c09_coldmid", "c10_coldhigh"),
        ("c11_cyan_dim", "c12_cyan"),
        ("c13_warm_dim", "c14_warm", "c15_warm_high"),
        ("c16_dirt", "c17_rust", "c18_rust_lit", "c19_dried", "c20_blood"),
        ("c21_grey", "c22_grey_lit"),
        ("c23_cloth", "c24_cloth_lit", "c25_leather"),
        ("c26_skin", "c27_skin_lit"),
        ("c28_pallid", "c29_pallid_lit"),
        ("c30_white", "c31_dead_black"),
    ]
    im = Image.new("RGB", (128, 96), P["c00_void"])
    d = ImageDraw.Draw(im)
    y = 0
    for fam in fams:
        x = 0
        for name in fam:
            d.rectangle([x, y, x + 11, y + 7], fill=P[name])
            x += 12
        y += 10
        if y > 88:
            break
    return im


def main() -> int:
    P = named_map(PAL)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("G1_light_direction", g1), ("G2_no_gradient", g2), ("G3_palette_roles", g3)):
        im = fn(P)
        p = OUT / f"{name}.png"
        im.save(p)
        big = im.resize((im.width * 6, im.height * 6), Image.NEAREST)
        big.save(OUT / f"{name}_x6.png")
        print(f"{p}  {im.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
