#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""人物参考 → 真像素：出两个尺寸，回答两个不同的问题

    _ref_144.png   144×144   看得到细节：配件、色块、体态。这是「设计参考」。
    _sprite_32.png  32×32    游戏尺寸下还认不认得出「这是那个背书包的学生」。这是「资产可行性」。

为什么要两个：144 好看不代表 32 能用。人物资产的真问题是
「在 16/24/32 px 里，书包带和胸牌还剩下几个像素」——只剩两三个像素就该改设计，
不是加细节。

自动裁人：源图背景是近黑，按亮度阈值找 bbox，先紧裁再缩放，
这样人物在目标尺寸里占满，不被大片黑边吃掉分辨率。
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import nearest, named_map, read_gpl  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"
RAW_DIR = ROOT / "art" / "generated_candidates" / "characters"
OUT_DIR = RAW_DIR
PREV = ROOT / "design" / "previews"

TARGETS = ["CH-01_student_raw.png", "CH-02_teacher_raw.png", "CH-03_zombie_pair_raw.png"]


def bbox_of_figure(img: Image.Image, thresh: int = 14) -> tuple[int, int, int, int]:
    """按亮度找非背景区域。源图背景近黑，人物有布料/皮肤亮度。"""
    g = img.convert("L")
    w, h = g.size
    px = g.load()
    x0, y0, x1, y1 = w, h, 0, 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y] > thresh:
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    if x1 <= x0 or y1 <= y0:
        return (0, 0, w, h)
    m = 8
    return (max(0, x0 - m), max(0, y0 - m), min(w, x1 + m), min(h, y1 + m))


def snap(img: Image.Image, palette: list[tuple[int, int, int]]) -> Image.Image:
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            px[x, y] = nearest(px[x, y], palette)
    return img


def make_ref(raw: Path, palette) -> Path:
    img = Image.open(raw).convert("RGB")
    # 先紧裁人物，再降到 144 高（16 的整数倍）
    img = img.crop(bbox_of_figure(img))
    w, h = img.size
    target_h = 144
    target_w = max(16, round(w * target_h / h / 16) * 16)
    img = img.resize((target_w, target_h), Image.BOX).filter(ImageFilter.MedianFilter(3))
    img = snap(img, palette)
    out = OUT_DIR / raw.name.replace("_raw.png", "_ref_144.png")
    img.save(out)
    return out


def make_sprite(raw: Path, palette, size: int = 32) -> Path:
    img = Image.open(raw).convert("RGB")
    img = img.crop(bbox_of_figure(img))
    w, h = img.size
    # 单人要按缩放入；双人要整张塞进 32 宽会糊，所以按个数拆
    cols = 2 if "pair" in raw.name else 1
    cell_w = w / cols
    out_w = size * cols
    img = img.resize((out_w, size), Image.BOX).filter(ImageFilter.MedianFilter(3))
    img = snap(img, palette)
    out = OUT_DIR / raw.name.replace("_raw.png", f"_sprite_{size}.png")
    img.save(out)
    return out


def main() -> int:
    palette = read_gpl(PAL)
    PREV.mkdir(parents=True, exist_ok=True)
    refs, sprites = [], []
    for name in TARGETS:
        raw = RAW_DIR / name
        if not raw.exists():
            print(f"缺 {raw}")
            continue
        refs.append(make_ref(raw, palette))
        sprites.append(make_sprite(raw, palette))
        print(f"OK {name}")

    # 参考图并排（×2）
    if refs:
        imgs = [Image.open(p) for p in refs]
        gap = 16
        W = sum(i.width for i in imgs) + gap * (len(imgs) - 1)
        H = max(i.height for i in imgs)
        sheet = Image.new("RGB", (W, H), (3, 5, 10))
        x = 0
        for i in imgs:
            sheet.paste(i, (x, H - i.height))
            x += i.width + gap
        sheet.resize((W * 2, H * 2), Image.NEAREST).save(PREV / "CHAR_ref_x2.png")
        print(PREV / "CHAR_ref_x2.png", (W * 2, H * 2))

    # 精灵并排（×8）：这才是"游戏里认不认得出"的判据
    if sprites:
        imgs = [Image.open(p) for p in sprites]
        gap = 8
        W = sum(i.width for i in imgs) + gap * (len(imgs) - 1)
        H = max(i.height for i in imgs)
        sheet = Image.new("RGB", (W, H), (3, 5, 10))
        x = 0
        for i in imgs:
            sheet.paste(i, (x, H - i.height))
            x += i.width + gap
        sheet.resize((W * 8, H * 8), Image.NEAREST).save(PREV / "CHAR_sprite32_x8.png")
        print(PREV / "CHAR_sprite32_x8.png", (W * 8, H * 8))
    return 0


if __name__ == "__main__":
    sys.exit(main())
