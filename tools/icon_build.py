#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""应用图标生成器（2026-11-26）。

为什么要有它：Android 导出会在没有 `application/config/icon` 时报
`No project icon specified`，而商店页与启动器上默认的 Godot 图标会直接影响点击率。
这里是**唯一真源**：32×32 手排，整数倍放大，颜色只取 `art/palettes/master.gpl`。

产物（都在 art/generated_candidates/ui/）：
    icon_192.png              6×  -> Android launcher_icons/main_192x192
    icon_256.png              8×  -> 桌面窗口图标 / project.godot 的 config/icon
    icon_foreground_432.png   自适应图标前景（内容居中，四周透明安全区）
    icon_background_432.png   自适应图标背景（纯色）

用法：
    python tools/icon_build.py
    python tools/pixelpipe.py gate art/generated_candidates/ui/icon_192.png \
        --palette art/palettes/master.gpl --max-colors 16
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "art" / "generated_candidates" / "ui"

# 只允许用调色板里的角色色（见 master.gpl）
VOID = (3, 5, 10)            # c00_void
SHADOW = (6, 10, 18)         # c01_shadow
WALL = (17, 26, 38)          # c03_wall
FLOOR = (24, 36, 51)         # c04_floor
GREY = (99, 94, 87)          # c21_grey
WARM = (176, 112, 46)        # c14_warm
WARM_DIM = (74, 44, 18)      # c13_warm_dim

CELL = 32


def draw_icon() -> Image.Image:
    """32×32 手排：黑暗里一扇发暖光的门，门口站着一个人影。

    可读性优先：只靠「亮矩形 + 黑剪影」的反差，缩到 48px 也认得出。
    """
    img = Image.new("RGB", (CELL, CELL), SHADOW)
    d = ImageDraw.Draw(img)

    # 顶部与地面（极暗，只用来分出「房间」）
    d.rectangle([0, 0, CELL - 1, CELL - 1], fill=SHADOW)
    d.rectangle([0, 27, CELL - 1, CELL - 1], fill=FLOOR)

    # 门洞：暖光从里面透出来
    d.rectangle([9, 5, 22, 26], fill=GREY)          # 门框
    d.rectangle([10, 6, 21, 25], fill=WARM_DIM)     # 门洞暗部
    d.rectangle([11, 7, 20, 25], fill=WARM)         # 门洞亮部

    # 光在地面上的反光（一条，不做渐变）
    d.rectangle([10, 26, 21, 27], fill=WARM_DIM)

    # 人影：细长剪影，头/肩/躯干/腿各留一处收分，缩到 48px 也认得出是人
    d.rectangle([15, 9, 16, 11], fill=VOID)         # 头
    d.rectangle([14, 12, 17, 12], fill=VOID)        # 肩
    d.rectangle([14, 13, 17, 19], fill=VOID)        # 躯干
    d.rectangle([13, 14, 13, 18], fill=VOID)        # 左臂
    d.rectangle([18, 14, 18, 18], fill=VOID)        # 右臂
    d.rectangle([14, 20, 17, 20], fill=VOID)        # 胯
    d.rectangle([14, 21, 14, 25], fill=VOID)        # 左腿
    d.rectangle([17, 21, 17, 25], fill=VOID)        # 右腿

    return img


def upscale(img: Image.Image, factor: int) -> Image.Image:
    return img.resize((CELL * factor, CELL * factor), Image.NEAREST)


def adaptive_foreground(icon: Image.Image) -> Image.Image:
    """432×432，内容占中间 192（≈44%，落在自适应图标 66% 安全区内），四周透明。"""
    layer = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    art = upscale(icon, 6).convert("RGBA")
    layer.paste(art, ((432 - art.width) // 2, (432 - art.height) // 2))
    return layer


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    icon = draw_icon()

    written = []
    pairs = [
        ("icon_192.png", upscale(icon, 6)),
        ("icon_256.png", upscale(icon, 8)),
        ("icon_foreground_432.png", adaptive_foreground(icon)),
        ("icon_background_432.png", Image.new("RGB", (432, 432), SHADOW)),
    ]
    for name, art in pairs:
        path = OUT / name
        art.save(path)
        written.append((name, art.size))

    for name, size in written:
        print(f"ICON {name}  {size[0]}x{size[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
