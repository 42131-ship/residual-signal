#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给所有人物生成动作帧（idle / walk / hurt / death），并输出「部件拆解」元数据。

为什么是「拆解」：外部 2D 骨骼工具（see-through / Stretchy Studio / PuppetLoom 这类）
要吃的是「每一帧由哪些部件组成、各部件枢轴在哪」，而不是一张糊在一起的整图。
所以这里除了出图，还出一份 parts（head/torso/arm/leg 的矩形 + 枢轴），
骨骼工具可以按它自动切件；本工程自己则按帧播。

约束（与 PIXEL_SPEC / prop_build 一致）：
- 画布尺寸沿用源图（32×32 或 32×48），只做整数像素平移，不做缩放
- 只搬像素、不改颜色 → 调色板与二值 alpha 天然保持
- 脚底锚点不动（idle/walk/hurt）；只有 death 允许整体下沉

输出：
  art/generated_candidates/characters/anim/<id>.png        10 帧横排精灵表
  art/generated_candidates/characters/anim/anims.json      帧表 + 动作 + 部件拆解
  design/previews/ANIM-<id>_x4.png                         审阅图（前 6 个角色）
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import named_map  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "art" / "generated_candidates" / "characters"
OUT_DIR = SRC_DIR / "anim"
PAL = ROOT / "art" / "palettes" / "master.gpl"
MANIFEST = OUT_DIR / "anims.json"
PREVIEW = ROOT / "design" / "previews"

# 10 帧固定顺序：列号 = 帧号
ANIMS = [
    {"id": "idle", "label": "待机", "start": 0, "count": 4, "fps": 5, "loop": True},
    {"id": "walk", "label": "行走", "start": 4, "count": 6, "fps": 10, "loop": True},
    {"id": "attack", "label": "挥击", "start": 10, "count": 3, "fps": 12, "loop": False},
    {"id": "hurt", "label": "受击", "start": 13, "count": 2, "fps": 14, "loop": False},
    {"id": "death", "label": "倒地", "start": 15, "count": 5, "fps": 8, "loop": False},
]
FRAME_COUNT = 20

# 已经是动画产物、不用再当输入的角色文件
SKIP_PREFIX = ("SPR-player_walk",)


def shift_rows(img: Image.Image, top: int, dy: int) -> Image.Image:
    """把 [top, 底) 这段整体上下平移 dy 像素，超出画布的部分丢掉。"""
    if dy == 0:
        return img
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    band = img.crop((0, top, img.width, img.height))
    out.paste(img.crop((0, 0, img.width, top)), (0, 0))
    out.alpha_composite(band, (0, max(0, top + dy)) if dy > 0 else (0, top + dy))
    return out


def split_legs(img: Image.Image, hip: int, front_dx: int, back_dx: int) -> Image.Image:
    """下半身按左右两半分别平移，做出迈步。中线两侧各留 1px 不动，避免裂缝。"""
    out = img.copy()
    out.paste((0, 0, 0, 0), (0, hip, img.width, img.height))
    legs = img.crop((0, hip, img.width, img.height))
    mid = img.width // 2
    left = legs.crop((0, 0, mid, legs.height))
    right = legs.crop((mid, 0, legs.width, legs.height))
    canvas = Image.new("RGBA", legs.size, (0, 0, 0, 0))
    canvas.alpha_composite(left, (max(0, 0 + back_dx), 0)) if back_dx >= 0 else canvas.alpha_composite(left, (0, 0))
    if back_dx < 0:
        canvas.alpha_composite(left.crop((-back_dx, 0, left.width, left.height)), (0, 0))
    if front_dx >= 0:
        canvas.alpha_composite(right.crop((0, 0, right.width - front_dx, right.height)), (mid + front_dx, 0))
    else:
        canvas.alpha_composite(right, (mid + front_dx, 0))
    out.alpha_composite(canvas, (0, hip))
    return out


def body_metrics(img: Image.Image) -> tuple[int, int, int]:
    """返回 (bbox_top, hip_row, feet_row)。hip 取可见高度的 55%，够用且稳定。"""
    bbox = img.getbbox()
    if not bbox:
        raise SystemExit("empty sprite")
    top, bottom = bbox[1], bbox[3]
    visible = max(1, bottom - top)
    return top, top + int(round(visible * 0.55)), bottom - 1


def shift_frame(img: Image.Image, dx: int, dy: int) -> Image.Image:
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img, (dx, dy))
    return out


def build_frames(base: Image.Image) -> list[Image.Image]:
    top, hip, feet = body_metrics(base)
    frames: list[Image.Image] = []

    # ── idle 4 帧：吸气-停顿-呼气-停顿（呼吸靠上半身 1px，脚底不动）──
    frames.append(base.copy())
    frames.append(shift_rows(base, hip, -1))
    frames.append(base.copy())
    frames.append(shift_rows(base, hip, -1))

    # ── walk 6 帧：contact / down / passing / up 的像素化版本 ──
    # (前腿, 后腿, 上半身偏移)　上下起伏只在「down」帧压 1px，避免整段抖。
    steps = [(2, -2, 0), (1, -1, 1), (0, 0, 0), (-2, 2, 0), (-1, 1, 1), (0, 0, 0)]
    for front, back, bob in steps:
        step = split_legs(base, hip, front, back)
        if bob:
            step = shift_rows(step, 0, bob)
        frames.append(step)

    # ── attack 3 帧：预备（后拉 1px）→ 命中（前推 2px + 压 1px）→ 收招（回中 1px）──
    frames.append(shift_frame(base, -1, 0))
    strike = shift_frame(base, 2, 0)
    strike = shift_rows(strike, hip, -1)
    frames.append(strike)
    frames.append(shift_frame(base, 1, 0))

    # ── hurt 2 帧：后仰 1px → 2px ──
    frames.append(shift_frame(base, -1, 0))
    frames.append(shift_frame(base, -2, 0))

    # ── death 5 帧：逐帧下沉并截短，最后贴地 ──
    for drop in (1, 2, 4, 6, 9):
        fallen = Image.new("RGBA", base.size, (0, 0, 0, 0))
        fallen.alpha_composite(base.crop((0, 0, base.width, max(1, base.height - drop))), (0, drop))
        frames.append(fallen)

    if len(frames) != FRAME_COUNT:
        raise SystemExit(f"expected {FRAME_COUNT} frames, built {len(frames)}")
    return frames


def parts_of(base: Image.Image) -> list[dict]:
    """部件拆解：给骨骼工具用的矩形 + 枢轴（枢轴在部件底边中点）。"""
    bbox = base.getbbox()
    if not bbox:
        return []
    left, top, right, bottom = bbox
    height = bottom - top
    head_h = max(2, int(round(height * 0.30)))
    torso_h = max(2, int(round(height * 0.35)))
    head = [left, top, right, top + head_h]
    torso = [left, top + head_h, right, top + head_h + torso_h]
    legs = [left, top + head_h + torso_h, right, bottom]
    arm = [left, top + head_h, left + max(2, (right - left) // 4), top + head_h + torso_h]
    out = []
    for name, rect in (("head", head), ("torso", torso), ("arm", arm), ("legs", legs)):
        out.append({
            "id": name,
            "rect": rect,
            "pivot": [(rect[0] + rect[2]) // 2, rect[3]],
        })
    return out


def gate_frame(image: Image.Image, path_label: str) -> None:
    colors = {px[:3] for px in image.getdata() if px[3] == 255}
    if len(colors) > 16:
        raise SystemExit(f"{path_label}: {len(colors)} colors exceeds 16")
    if any(px[3] not in (0, 255) for px in image.getdata()):
        raise SystemExit(f"{path_label}: semi-transparent pixel found")
    if not image.getbbox():
        raise SystemExit(f"{path_label}: empty frame")


def main() -> int:
    palette = set(named_map(PAL).values())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)

    sources = [
        p for p in sorted(SRC_DIR.glob("SPR-*.png"))
        if not any(p.name.startswith(skip) for skip in SKIP_PREFIX)
    ]
    if not sources:
        raise SystemExit("no character sprites found")

    manifest = {"schema": "char-anim.v1", "frame_count": FRAME_COUNT, "anims": ANIMS, "characters": []}
    previews = 0
    for source in sources:
        char_id = source.stem.replace("SPR-", "").replace("_32x48", "").replace("_32", "")
        base = Image.open(source).convert("RGBA")
        frames = build_frames(base)
        sheet = Image.new("RGBA", (base.width * FRAME_COUNT, base.height), (0, 0, 0, 0))
        for index, frame in enumerate(frames):
            gate_frame(frame, f"{char_id}#{index}")
            used = {px[:3] for px in frame.getdata() if px[3] == 255}
            if not used <= palette:
                raise SystemExit(f"{char_id}#{index}: colour outside master.gpl")
            sheet.paste(frame, (index * base.width, 0))
        out_path = OUT_DIR / f"{char_id}.png"
        sheet.save(out_path)
        manifest["characters"].append({
            "id": char_id,
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "sheet": str(out_path.relative_to(ROOT)).replace("\\", "/"),
            "frame_size": [base.width, base.height],
            "anchor": [base.width // 2, base.height],
            "parts": parts_of(base),
        })
        if previews < 6:
            scale = 4
            strip = sheet.resize((sheet.width * scale, sheet.height * scale), Image.Resampling.NEAREST)
            strip.save(PREVIEW / f"ANIM-{char_id}_x{scale}.png")
            previews += 1

    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"roles={len(manifest['characters'])} frames_each={FRAME_COUNT} -> {MANIFEST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
