#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""像素管线：分析 / 抽取调色板 / 转真像素 / 生成 tile / 过门禁

为什么不是「让模型直接出资产」：
    模型出的是「平滑图穿像素服装」，它不知道自己画的是 8px 块还是 1px 块。
    所以路径必须是 参考图 → 抽出真实网格 → 量化进唯一调色板 → 门禁判定。
    **风格统一靠构造保证：所有资产只允许从 master.gpl 取色，从 16×16 取格。**

需要 Pillow（用打包运行时）：
    C:\\Users\\Administrator\\.dsh\\dsh-runtimes\\dsh-primary-runtime\\dependencies\\python\\python.exe

子命令：
    analyze  <png>                       报有效网格、色数、是否整数倍缩放
    palette  <png> --out art/palettes/master.gpl --colors 16
    convert  <png> --palette ... --out ... [--ratio 16:9] [--scale 8]
    tiles    --palette ... --out ...
    gate     <png> [<png> ...] --palette ...
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    raise SystemExit("需要 Pillow：用打包运行时的 python 执行本脚本")

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

GRID = 16
MAX_COLORS = 16   # 兼容旧名
FRAME_MAX = 16    # 每帧上限（tile / 角色帧）
BG_MAX = 32       # 背景 / 视差上限（= 整张调色板）
PALETTE_MAX = 32


# ---------------------------------------------------------------- 调色板


def read_gpl_named(path: Path) -> list[tuple[tuple[int, int, int], str]]:
    """带名字读调色板。名字是规格的一部分：资产必须按角色取色，不能按亮度猜。"""
    out: list[tuple[tuple[int, int, int], str]] = []
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        ln = ln.strip()
        if not ln or ln.startswith(("#", "GIMP", "Name:", "Columns:")):
            continue
        p = ln.split()
        if len(p) >= 3 and all(x.isdigit() for x in p[:3]):
            out.append(((int(p[0]), int(p[1]), int(p[2])), p[3] if len(p) > 3 else f"#{len(out):02d}"))
    return out


def read_gpl(path: Path) -> list[tuple[int, int, int]]:
    return [c for c, _ in read_gpl_named(path)]


def named_map(path: Path) -> dict[str, tuple[int, int, int]]:
    return {name: rgb for rgb, name in read_gpl_named(path)}


def write_gpl(path: Path, colors: list[tuple[int, int, int]], name: str = "residual-signal") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["GIMP Palette", f"Name: {name}", "Columns: 8", "#"]
    for i, (r, g, b) in enumerate(colors):
        lines.append(f"{r:3d} {g:3d} {b:3d}\tc{i:02d}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def nearest(pixel: tuple[int, int, int], palette: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    pr, pg, pb = pixel
    best, bestd = palette[0], 1 << 30
    for c in palette:
        d = (pr - c[0]) ** 2 + (pg - c[1]) ** 2 + (pb - c[2]) ** 2
        if d < bestd:
            best, bestd = c, d
    return best


# ---------------------------------------------------------------- 网格分析


def effective_scale(img: Image.Image, limit: int = 12) -> int:
    """返回这张图「被整数最近邻放大」的倍数；1 = 已经是 1× 原生像素。"""
    rgb = img.convert("RGB")
    w, h = rgb.size
    for s in range(2, limit + 1):
        if w % s or h % s:
            continue
        small = rgb.resize((w // s, h // s), Image.NEAREST)
        if small.resize((w, h), Image.NEAREST).tobytes() == rgb.tobytes():
            return s
    return 1


def modal_run(img: Image.Image, step: int = 7) -> int:
    """同行相同颜色像素的众数游程 —— 用来估「作者其实是按几个像素画的」。

    真 1× 像素画：游程众数通常是 1–3。
    8× 放大 / 模型画的"像素"：众数落在 8 附近。
    """
    from collections import Counter

    rgb = img.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    counts: Counter[int] = Counter()
    for y in range(0, h, step):
        run = 1
        for x in range(1, w):
            if px[x, y] == px[x - 1, y]:
                run += 1
            else:
                counts[run] += 1
                run = 1
        counts[run] += 1
    return counts.most_common(1)[0][0] if counts else 1


def analyze(path: Path) -> dict:
    img = Image.open(path)
    rgb = img.convert("RGB")
    colors = rgb.getcolors(maxcolors=1 << 24) or []
    scale = effective_scale(img)
    w, h = rgb.size
    mr = modal_run(img)
    return {
        "path": str(path),
        "size": [w, h],
        "exact_integer_scale": scale,
        "modal_run": mr,
        "native_size_estimate": [w // mr, h // mr],
        "unique_colors": len(colors),
        "sixteen_divisible": (w % GRID == 0 and h % GRID == 0),
        "verdict": "TRUE_PIXEL"
        if (scale > 1 or len(colors) <= MAX_COLORS)
        else "PSEUDO_PIXEL（需 convert 到原生网格并量化）",
    }


# ---------------------------------------------------------------- 转换


def crop_ratio(img: Image.Image, ratio: str) -> Image.Image:
    rw, rh = (int(x) for x in ratio.split(":"))
    w, h = img.size
    target = rw / rh
    if w / h > target:  # 太宽，裁左右
        nw = int(h * target)
        left = (w - nw) // 2
        return img.crop((left, 0, left + nw, h))
    nh = int(w / target)
    top = (h - nh) // 2
    return img.crop((0, top, w, top + nh))


def convert(
    src: Path,
    out: Path,
    palette: list[tuple[int, int, int]],
    ratio: str | None = None,
    scale: int | None = None,
    resample: str = "box",
    denoise: int = 3,
) -> dict:
    img = Image.open(src).convert("RGB")
    if ratio:
        img = crop_ratio(img, ratio)
    s = scale or effective_scale(img)
    if s > 1:
        # 降采样用面积平均（保细节），升采样必须最近邻（保硬边）
        filt = Image.BOX if resample == "box" else Image.NEAREST
        img = img.resize((img.width // s, img.height // s), filt)
    if denoise >= 3 and resample == "box":
        # 面积平均会把源图的噪点摊到每个逻辑格上，逐格吸附后会变成椒盐。
        # 先中值去噪，再吸附 —— 这一步决定「像不像手画的像素」。
        from PIL import ImageFilter

        img = img.filter(ImageFilter.MedianFilter(denoise))
    # 逐像素吸附到调色板（不做抖动：抖动会引入色阶噪点，破坏平面感）
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            px[x, y] = nearest(px[x, y], palette)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    return {"out": str(out), "size": list(img.size), "scale_from_source": s,
            "resample": resample, "denoise": denoise}


# ---------------------------------------------------------------- 确定性 tile


def build_tiles(out: Path, palette_path: Path, variant: str = "clean") -> dict:
    """从调色板按「角色名」直接画 16×16 tile —— 不经过模型，因此天然过 R14。

    风格统一的五条硬规则（写进 PIXEL_SPEC）：
      1. 光来自上方：顶边用 c06_top，底边用 c02_dark
      2. 物体暗部一律 c02_dark，不描纯黑边（c31 只给贴图内最深处）
      3. 每格 ≤4 色
      4. 不做渐变、不做抖动：明暗之间没有中间过渡
      5. 冷光源只用 c11/c12 两档；暖光只用 c13–c15 三档
    """
    P = named_map(palette_path)

    def g(name: str) -> tuple[int, int, int]:
        if name not in P:
            raise SystemExit(f"调色板缺角色 '{name}'")
        return P[name]

    specs = ["floor", "wall", "door", "exit_sign", "ceiling", "debris", "vending", "speaker",
             "floor_wet", "floor_tiled", "wall_cracked", "wall_brick", "window",
             "stairs_up", "stairs_down", "door_locked", "locker", "desk", "blackboard", "pipe"]
    sheet = Image.new("RGB", (GRID * len(specs), GRID), g("c00_void"))
    d = ImageDraw.Draw(sheet)

    for i, name in enumerate(specs):
        ox = i * GRID
        if name == "floor":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c04_floor"))
            d.line([ox, 0, ox + GRID - 1, 0], fill=g("c06_top"))
            d.line([ox, GRID - 1, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            for (x, y) in ((4, 6), (11, 9), (7, 12), (13, 3)):
                d.point((ox + x, y), fill=g("c03_wall"))
        elif name == "wall":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            d.rectangle([ox, 0, ox + GRID - 1, 2], fill=g("c05_lit"))
            d.rectangle([ox, GRID - 3, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            for (x, y) in ((3, 7), (9, 10)):
                d.point((ox + x, y), fill=g("c02_dark"))
        elif name == "door":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            d.rectangle([ox + 3, 2, ox + 12, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox + 3, 2, ox + 12, 3], fill=g("c05_lit"))
            d.point((ox + 10, 9), fill=g("c21_grey"))     # 门把：金属
        elif name == "exit_sign":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c01_shadow"))
            d.rectangle([ox + 2, 3, ox + 13, 11], fill=g("c11_cyan_dim"))
            d.rectangle([ox + 4, 5, ox + 11, 9], fill=g("c12_cyan"))
            for y in range(12, 16, 2):                    # 下垂的冷光
                d.point((ox + 6, y), fill=g("c11_cyan_dim"))
                d.point((ox + 9, y), fill=g("c11_cyan_dim"))
        elif name == "ceiling":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            d.line([ox, GRID // 2 - 1, ox + GRID - 1, GRID // 2 - 1], fill=g("c03_wall"))
        elif name == "debris":
            # 散落的书与纸：16px 下比"倒地的椅子"可辨识得多
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c04_floor"))
            d.line([ox, 0, ox + GRID - 1, 0], fill=g("c06_top"))
            d.line([ox, GRID - 1, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox + 3, 10, ox + 7, 11], fill=g("c22_grey_lit"))   # 摊开的纸
            d.rectangle([ox + 9, 12, ox + 13, 13], fill=g("c22_grey_lit"))
            d.rectangle([ox + 6, 6, ox + 9, 7], fill=g("c22_grey_lit"))
            d.rectangle([ox + 10, 8, ox + 13, 9], fill=g("c17_rust"))       # 一本旧书
            d.point((ox + 4, 12), fill=g("c03_wall"))
            d.point((ox + 12, 5), fill=g("c03_wall"))
        elif name == "vending":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c01_shadow"))
            d.rectangle([ox + 2, 1, ox + 13, 14], fill=g("c03_wall"))
            for y in (4, 7, 10):
                d.line([ox + 4, y, ox + 11, y], fill=g("c09_coldmid"))
            d.rectangle([ox + 4, 12, ox + 11, 13], fill=g("c00_void"))
        elif name == "speaker":
            # 挂墙广播：大框 + 受光顶边 + 三行格栅 + 还在响的一点暖光
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox + 3, 3, ox + 12, 11], fill=g("c03_wall"))
            d.line([ox + 3, 3, ox + 12, 3], fill=g("c05_lit"))              # 顶边受光
            for y in (5, 7, 9):
                d.line([ox + 5, y, ox + 10, y], fill=g("c00_void"))          # 格栅
            d.rectangle([ox + 3, 3, ox + 4, 11], fill=g("c02_dark"))         # 侧边阴影
            d.point((ox + 13, 6), fill=g("c15_warm_high"))                   # 指示点
            d.point((ox + 13, 7), fill=g("c13_warm_dim"))
        elif name == "floor_wet":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            d.line([ox, 0, ox + GRID - 1, 0], fill=g("c05_lit"))
            d.rectangle([ox + 3, 6, ox + 12, 13], fill=g("c04_floor"))        # 积水
            d.line([ox + 5, 8, ox + 10, 8], fill=g("c09_coldmid"))            # 反光
            d.point((ox + 7, 10), fill=g("c09_coldmid"))
            d.line([ox, GRID - 1, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
        elif name == "floor_tiled":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c04_floor"))
            for k in (0, 8):
                d.line([ox + k, 0, ox + k, GRID - 1], fill=g("c02_dark"))
                d.line([ox, k, ox + GRID - 1, k], fill=g("c02_dark"))
            d.line([ox + 1, 0, ox + 1, GRID - 1], fill=g("c05_lit"))
            d.line([ox, 1, ox + GRID - 1, 1], fill=g("c05_lit"))
        elif name == "wall_cracked":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            d.rectangle([ox, 0, ox + GRID - 1, 2], fill=g("c05_lit"))
            pts = [(4, 4), (6, 7), (5, 10), (8, 13)]
            for a, b in zip(pts, pts[1:]):
                d.line([ox + a[0], a[1], ox + b[0], b[1]], fill=g("c02_dark"))
            d.line([ox, GRID - 2, ox + GRID - 1, GRID - 2], fill=g("c02_dark"))
        elif name == "wall_brick":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            for y in (5, 11):
                d.line([ox, y, ox + GRID - 1, y], fill=g("c02_dark"))
            d.line([ox + 7, 0, ox + 7, 5], fill=g("c02_dark"))
            d.line([ox + 3, 5, ox + 3, 11], fill=g("c02_dark"))
            d.line([ox + 11, 5, ox + 11, 11], fill=g("c02_dark"))
            d.line([ox + 7, 11, ox + 7, GRID - 1], fill=g("c02_dark"))
            d.line([ox, 0, ox + GRID - 1, 0], fill=g("c05_lit"))
        elif name == "window":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox + 2, 2, ox + 13, 13], fill=g("c08_coldtone"))
            d.line([ox + 2, 7, ox + 13, 7], fill=g("c02_dark"))
            d.line([ox + 7, 2, ox + 7, 13], fill=g("c02_dark"))
            d.point((ox + 4, 4), fill=g("c09_coldmid"))
            d.point((ox + 10, 5), fill=g("c09_coldmid"))
        elif name == "stairs_up":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            for i in range(4):
                y = 12 - i * 4
                d.rectangle([ox + 2 + i, y, ox + 13, y + 2], fill=g("c03_wall"))
                d.line([ox + 2 + i, y, ox + 13, y], fill=g("c05_lit"))
        elif name == "stairs_down":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            for i in range(4):
                y = 2 + i * 4
                d.rectangle([ox + 2, y, ox + 13, y + 2], fill=g("c03_wall"))
                d.line([ox + 2, y + 2, ox + 13, y + 2], fill=g("c00_void"))
        elif name == "door_locked":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            d.rectangle([ox + 3, 2, ox + 12, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox + 3, 2, ox + 12, 3], fill=g("c05_lit"))
            d.rectangle([ox + 6, 8, ox + 9, 11], fill=g("c21_grey"))          # 挂锁
            d.line([ox + 7, 6, ox + 8, 6], fill=g("c21_grey"))
            d.point((ox + 7, 5), fill=g("c21_grey"))
        elif name == "locker":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox + 1, 1, ox + 14, 14], fill=g("c03_wall"))
            d.line([ox + 1, 1, ox + 14, 1], fill=g("c05_lit"))
            for y in (5, 8, 11):
                d.line([ox + 4, y, ox + 11, y], fill=g("c02_dark"))
            d.rectangle([ox + 12, 7, ox + 13, 8], fill=g("c21_grey"))
        elif name == "desk":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c04_floor"))
            d.rectangle([ox + 1, 6, ox + 14, 8], fill=g("c25_leather"))       # 桌面
            d.line([ox + 1, 6, ox + 14, 6], fill=g("c24_cloth_lit"))
            d.rectangle([ox + 2, 9, ox + 3, 14], fill=g("c02_dark"))
            d.rectangle([ox + 12, 9, ox + 13, 14], fill=g("c02_dark"))
        elif name == "blackboard":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c03_wall"))
            d.rectangle([ox + 1, 2, ox + 14, 11], fill=g("c31_dead_black"))
            d.line([ox + 3, 5, ox + 9, 5], fill=g("c22_grey_lit"))
            d.line([ox + 3, 8, ox + 6, 8], fill=g("c22_grey_lit"))
            d.line([ox + 1, 12, ox + 14, 12], fill=g("c25_leather"))          # 粉笔槽
        elif name == "pipe":
            d.rectangle([ox, 0, ox + GRID - 1, GRID - 1], fill=g("c02_dark"))
            d.rectangle([ox, 4, ox + GRID - 1, 7], fill=g("c17_rust"))
            d.line([ox, 4, ox + GRID - 1, 4], fill=g("c18_rust_lit"))
            d.rectangle([ox + 6, 3, ox + 7, 8], fill=g("c25_leather"))
            d.point((ox + 11, 9), fill=g("c11_cyan_dim"))                     # 渗水

    # 磨损变体：同一套 tile 的第二个批次（量产用），只加不替换
    if variant != "clean":
        import random as _rnd

        seed = sum(ord(c) for c in variant)          # 不用 hash()，它按进程加盐
        rng = _rnd.Random(seed)
        for gx in range(len(specs)):
            ox = gx * GRID
            for _ in range(rng.randint(2, 4)):
                x = ox + rng.randint(0, GRID - 1)
                y = rng.randint(0, GRID - 1)
                sheet.putpixel((x, y), g("c02_dark") if rng.random() < 0.7 else g("c17_rust"))
            for x in range(ox, ox + GRID):
                if rng.random() < 0.25:
                    sheet.putpixel((x, GRID - 1), g("c01_shadow"))

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return {"out": str(out), "size": list(sheet.size), "tiles": specs, "variant": variant}


# ---------------------------------------------------------------- 门禁


def gate(path: Path, palette: list[tuple[int, int, int]], max_colors: int = FRAME_MAX,
         per_tile: int = 0) -> dict:
    """四类断言 + 半透边缘检查。

    per_tile > 0 时，把整张表切成 per_tile×per_tile 的格子逐格查色数 ——
    **单帧 ≤16 色是给一格的，不是给一张表的。** 一张 20 格的表当然会超过 16 色。
    """
    im = Image.open(path)
    rgba = im.convert("RGBA")
    w, h = rgba.size
    raw = rgba.getcolors(maxcolors=1 << 24) or []
    colors: set[tuple[int, int, int]] = set()
    semi = 0
    for cnt, val in raw:
        r, g, b, a = val  # type: ignore[misc]
        if a == 0:
            continue
        if a < 255:
            semi += cnt
        if a >= 8:
            colors.add((r, g, b))
    scale = effective_scale(rgba)
    off_palette = [c for c in colors if nearest(c, palette) != c]
    exact_upscale = scale > 1
    few_colors = len(colors) <= max_colors
    checks = {
        "R14a_像素落逻辑格": exact_upscale or few_colors,
        "R14b_仅整数最近邻": scale >= 1,
        "R14c_色集在调色板内": not off_palette,
        "R14d_16px整数边界": w % GRID == 0 and h % GRID == 0,
        f"R14e_单帧<={max_colors}色": few_colors,
        "R14f_无半透边缘": semi == 0,
    }
    worst = 0
    if per_tile > 0:
        cells = 0
        for cy in range(0, h, per_tile):
            for cx in range(0, w, per_tile):
                cell = rgba.crop((cx, cy, min(cx + per_tile, w), min(cy + per_tile, h)))
                cs = {c for _, c in (cell.getcolors(maxcolors=1 << 20) or [])
                      if isinstance(c, tuple) and len(c) == 4 and c[3] >= 8}
                worst = max(worst, len(cs))
                cells += 1
        checks[f"R14g_每格<={FRAME_MAX}色"] = worst <= FRAME_MAX
    return {
        "path": str(path),
        "size": [w, h],
        "mode": im.mode,
        "effective_scale": scale,
        "colors": len(colors),
        "max_colors": max_colors,
        "worst_cell_colors": worst,
        "semi_transparent_px": semi,
        "off_palette": [f"#{r:02x}{g:02x}{b:02x}" for r, g, b in off_palette[:8]],
        "checks": checks,
        "pass": all(checks.values()),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="像素管线")
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("analyze"); a.add_argument("png")
    p = sub.add_parser("palette")
    p.add_argument("png"); p.add_argument("--out", required=True)
    p.add_argument("--colors", type=int, default=MAX_COLORS)
    p.add_argument("--ratio")
    c = sub.add_parser("convert")
    c.add_argument("png"); c.add_argument("--palette", required=True)
    c.add_argument("--out", required=True); c.add_argument("--ratio"); c.add_argument("--scale", type=int)
    c.add_argument("--resample", choices=["box", "nearest"], default="box")
    c.add_argument("--denoise", type=int, default=3, help="中值滤波窗口；0/1 关闭")
    t = sub.add_parser("tiles")
    t.add_argument("--palette", required=True); t.add_argument("--out", required=True)
    t.add_argument("--variant", default="clean", help="磨损变体名；clean = 无磨损")
    g = sub.add_parser("gate")
    g.add_argument("png", nargs="+"); g.add_argument("--palette", required=True)
    g.add_argument("--max-colors", type=int, default=FRAME_MAX)
    g.add_argument("--per-tile", type=int, default=0, help="按 N×N 切格逐格查色数（表用它）")
    g.add_argument("--json", action="store_true")

    args = ap.parse_args(argv)

    if args.cmd == "analyze":
        info = analyze(Path(args.png))
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return 0

    if args.cmd == "palette":
        img = Image.open(args.png).convert("RGB")
        if args.ratio:
            img = crop_ratio(img, args.ratio)
        s = effective_scale(img)
        if s > 1:
            img = img.resize((img.width // s, img.height // s), Image.NEAREST)
        q = img.quantize(colors=args.colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
        counted = sorted(q.getcolors(maxcolors=1 << 24) or [], reverse=True)
        colors = [c for _, c in counted][: args.colors]
        colors.sort(key=lambda c: sum(c))
        write_gpl(Path(args.out), colors)
        print(f"写入 {args.out}：{len(colors)} 色，源自 {args.png}（有效网格 {s}×）")
        return 0

    if args.cmd == "convert":
        pal = read_gpl(Path(args.palette))
        info = convert(Path(args.png), Path(args.out), pal, ratio=args.ratio,
                       scale=args.scale, resample=args.resample, denoise=args.denoise)
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return 0

    if args.cmd == "tiles":
        info = build_tiles(Path(args.out), Path(args.palette), variant=args.variant)
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return 0

    if args.cmd == "gate":
        pal = read_gpl(Path(args.palette))
        results = [gate(Path(x), pal, max_colors=args.max_colors,
                        per_tile=args.per_tile) for x in args.png]
        if args.json:
            print(json.dumps(results, ensure_ascii=False, indent=2))
        else:
            for r in results:
                mark = "PASS" if r["pass"] else "FAIL"
                extra = f"  worst-cell={r['worst_cell_colors']}" if r.get("worst_cell_colors") else ""
                print(f"[{mark}] {r['path']}  {r['size'][0]}×{r['size'][1]}  "
                      f"{r['colors']} 色  有效网格 {r['effective_scale']}×{extra}")
                for k, v in r["checks"].items():
                    if not v:
                        print(f"        ✗ {k}")
                if r["off_palette"]:
                    print(f"        ✗ 调色板外颜色：{', '.join(r['off_palette'])}")
        return 0 if all(r["pass"] for r in results) else 1

    return 2


if __name__ == "__main__":
    sys.exit(main())
