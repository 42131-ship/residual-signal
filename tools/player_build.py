#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""主角专用构造器：32×48 原生画布（2×3 格），可见高度 41px。

char_build.py 的学生轮廓是 32×32 / 可见 24px（HANDOFF-STAGE2 的「24px 角色可读」），
在 384×216 里只有 11% 高，Stage 2 复盘（2026-11-23）认为偏小。这里用同一张
master.gpl 与同一套色角色，按 32×48 重画主角：可见 41px（19%），像素仍是原生 1px，
不做任何非整数缩放。只产主角，不动 NPC 的 32×32 资产（R25/R43 语义槽依赖它们）。

输出：
  art/generated_candidates/characters/SPR-player_32x48.png        站立
  art/generated_candidates/characters/SPR-player_walk1_32x48.png  走路 A
  art/generated_candidates/characters/SPR-player_walk2_32x48.png  走路 B
  design/previews/PLAYER-02_x6.png                                三帧 ×6 审阅图
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import named_map  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"
OUT_DIR = ROOT / "art" / "generated_candidates" / "characters"
PREV = ROOT / "design" / "previews"

W, H = 32, 48
FEET_ROW = 46  # 鞋底最后一行；47 行留 1px 余量，便于脚底对齐


def draw_frame(P: dict, leg_offset: int = 0) -> Image.Image:
    """leg_offset = -1/0/+1：只改两条腿的前后错位，身体不动（走路两帧）。"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    skin = P["c26_skin"]
    skin_lit = P["c27_skin_lit"]
    hair = P["c01_shadow"]
    cloth = P["c23_cloth"]
    cloth_lit = P["c24_cloth_lit"]
    leather = P["c25_leather"]
    dark = P["c02_dark"]
    shoe = P["c01_shadow"]
    eye = P["c31_dead_black"]

    # ── 背后层：书包 + 后腿 ───────────────────────────────────
    d.polygon([(6, 24), (11, 23), (12, 26), (12, 33), (9, 35), (6, 33), (5, 28)],
              fill=leather)
    d.line([(6, 24), (11, 23), (12, 26)], fill=cloth_lit)
    d.point((7, 32), fill=eye)

    back_shift = -leg_offset
    d.polygon([(13, 33), (16, 33), (16 + back_shift, 42), (15 + back_shift, 44), (12 + back_shift, 44), (12, 42)],
              fill=dark)
    # 两只鞋之间必须留 1 列透明（x=16），否则脚底会被读成一整块。
    d.rectangle([11, 44, 15, 46], fill=shoe)

    # ── 躯干（校服外套，肩窄腰收） ─────────────────────────────
    d.polygon([(11, 20), (14, 19), (19, 19), (21, 21), (22, 25), (21, 31),
               (19, 33), (12, 32), (10, 29), (10, 23)], fill=cloth)
    d.polygon([(11, 20), (14, 19), (19, 19), (20, 21), (14, 22), (12, 21)],
              fill=cloth_lit)
    d.line([(16, 22), (16, 31)], fill=leather)
    d.rectangle([18, 24, 19, 25], fill=P["c22_grey_lit"])          # 胸牌
    d.line([(12, 31), (19, 32)], fill=P["c01_shadow"])             # 衣摆阴影

    # ── 手臂：近侧压在躯干上，远侧更暗 ────────────────────────
    d.polygon([(9, 22), (11, 22), (11, 29), (10, 31), (8, 30)], fill=dark)
    d.polygon([(20, 22), (22, 22), (23, 26), (22, 31), (20, 31), (20, 27)], fill=dark)
    d.point((22, 31), fill=skin_lit)
    d.point((21, 32), fill=skin_lit)

    # ── 前腿（走路时前后错开；鞋底始终在 44..46，保证脚底线不动）──
    front_shift = leg_offset
    d.polygon([(17, 33), (20, 33), (20 + front_shift, 42), (21 + front_shift, 44), (17 + front_shift, 44), (17, 42)],
              fill=dark)
    d.line([(17, 38), (20, 38)], fill=P["c21_grey"])               # 裤线
    d.rectangle([18, 44, 23, 46], fill=shoe)
    d.point((22, 45), fill=P["c21_grey"])                          # 鞋尖高光

    # ── 斜挎带（压在躯干上） ─────────────────────────────────
    for dx, dy in [(13, 21), (14, 22), (15, 23), (16, 24), (17, 25), (18, 26)]:
        d.point((dx, dy), fill=leather)

    # ── 头：侧脸朝右，发型 + 眼睛 + 颈部 ─────────────────────
    d.polygon([(13, 7), (18, 6), (20, 8), (20, 10), (18, 11), (13, 11), (12, 9)],
              fill=hair)
    d.polygon([(13, 11), (19, 11), (19, 17), (17, 18), (14, 18), (13, 16)],
              fill=skin)
    d.rectangle([17, 12, 19, 17], fill=skin_lit)
    d.point((17, 13), fill=eye)
    d.point((18, 13), fill=P["c02_dark"])
    d.rectangle([15, 17, 17, 18], fill=skin_lit)                   # 颈部
    d.point((18, 16), fill=P["c01_shadow"])                        # 下颌阴影

    # ── 右缘轮廓光：与 16px tile 的「光只来自上方」一致 ───────
    d.line([(21, 22), (22, 26)], fill=P["c05_lit"])
    d.line([(19, 18), (20, 19)], fill=P["c05_lit"])

    return img


def validate(img: Image.Image, P: dict) -> None:
    rgba = img.convert("RGBA")
    if rgba.size != (W, H):
        raise ValueError(f"expected {W}x{H}, got {rgba.size}")
    samples = rgba.getcolors(maxcolors=W * H)
    if any(pixel[3] not in (0, 255) for _, pixel in samples):
        raise ValueError("semi-transparent pixels are not allowed")
    colors = {pixel[:3] for _, pixel in samples if pixel[3] == 255}
    if not 1 <= len(colors) <= 16:
        raise ValueError(f"palette budget exceeded: {len(colors)} colors")
    if not colors.issubset(set(P.values())):
        raise ValueError("colors outside master.gpl")
    bounds = rgba.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("empty sprite")
    if bounds[1] != 6 or bounds[3] != 47:
        raise ValueError(f"silhouette must span rows 6..46, got {bounds}")
    print(f"  ok {rgba.size[0]}x{rgba.size[1]} colors={len(colors)} bounds={bounds}")


def main() -> int:
    P = named_map(PAL)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREV.mkdir(parents=True, exist_ok=True)

    frames = [
        ("SPR-player_32x48.png", draw_frame(P, 0)),
        ("SPR-player_walk1_32x48.png", draw_frame(P, -1)),
        ("SPR-player_walk2_32x48.png", draw_frame(P, 1)),
    ]
    for name, img in frames:
        validate(img, P)
        img.save(OUT_DIR / name)
        print(OUT_DIR / name)

    sheet = Image.new("RGBA", (W * 3, H), (0, 0, 0, 0))
    for index, (_name, img) in enumerate(frames):
        sheet.alpha_composite(img, (index * W, 0))
    preview = sheet.convert("RGB").resize((W * 3 * 6, H * 6), Image.NEAREST)
    preview.save(PREV / "PLAYER-02_x6.png")
    print(PREV / "PLAYER-02_x6.png", preview.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
