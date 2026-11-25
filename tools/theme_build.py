#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build per-building theme art (tiles + themed props + props scene).

D7：五楼不再共用学校美术。学校保留现有资产；其余四楼按
`data/buildings/<id>.json` 的主题角色生成：

  - `art/generated_candidates/themes/<id>/tiles_<id>.png`   8×16 的 tile 表（与 TILE_INDEX 同序）
  - `art/generated_candidates/themes/<id>/props/*.png`      15 件道具的主题换色版（形状沿用）
  - `art/generated_candidates/themes/<id>/signature/*.png`  该楼专属 4 件标志物（程序化绘制）
  - `game/scenes/props_<id>.tscn`                           道具场景（位置与学校一致 + 标志物）

所有输出都在 master.gpl 内取色、二值 alpha、16px 整数边界；生成后会自检
（像素门禁由 `pixelpipe gate` 在 CI 里再跑一次）。

用法：python tools/theme_build.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def _pixels(image: Image.Image):
    """兼容 Pillow 13/14：getdata 已弃用，新的叫 get_flattened_data。"""
    getter = getattr(image, "get_flattened_data", None)
    return getter() if getter is not None else image.getdata()


sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import read_gpl_named  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PALETTE = ROOT / "art" / "palettes" / "master.gpl"
THEMES = ROOT / "art" / "generated_candidates" / "themes"
DATA = ROOT / "data" / "buildings"
SCHOOL_PROPS = ROOT / "art" / "generated_candidates" / "props" / "stage1"
SCHOOL_MANIFEST = SCHOOL_PROPS / "props.json"
SCENES = ROOT / "game" / "scenes"
GRID = 16
PROP = 32
TILES = ["void", "wall", "dado", "cracked", "base", "floor", "wet", "scuff"]
GENERATED = ["gas_station", "hospital", "fire_station", "military_base"]
SIGNATURE_POSITIONS = [(2, 9), (7, 11), (20, 11), (27, 11)]

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def palette_roles() -> dict[str, tuple[int, int, int]]:
    out: dict[str, tuple[int, int, int]] = {}
    for rgb, name in read_gpl_named(PALETTE):
        out[name] = rgb
    return out


def load_theme(building: str) -> dict:
    path = DATA / f"{building}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema") != "building-theme.v1":
        raise SystemExit(f"bad theme schema: {path}")
    if data.get("id") != building:
        raise SystemExit(f"theme id mismatch: {path}")
    return data


def role_colors(theme: dict, P: dict[str, tuple[int, int, int]]) -> dict[str, tuple[int, int, int]]:
    out: dict[str, tuple[int, int, int]] = {}
    for role, name in (theme.get("roles") or {}).items():
        if name not in P:
            raise SystemExit(f"{theme['id']}: palette role missing: {name}")
        out[role] = P[name]
    missing = {"void", "wall", "dado", "floor", "lit", "top", "edge", "accent", "accent_lit", "wet"} - set(out)
    if missing:
        raise SystemExit(f"{theme['id']}: missing theme roles: {sorted(missing)}")
    return out


# ---------------------------------------------------------------- tiles


def build_tiles(theme: dict, C: dict[str, tuple[int, int, int]], out: Path) -> Path:
    img = Image.new("RGB", (GRID * len(TILES), GRID), C["void"])
    d = ImageDraw.Draw(img)
    motif = str(theme.get("motif", "plain"))
    dark = C["dado"]
    shadow = C["accent_lit"]
    for index, name in enumerate(TILES):
        ox = index * GRID

        def rect(x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
            d.rectangle([ox + x0, y0, ox + x1, y1], fill=color)

        def line(x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
            d.line([ox + x0, y0, ox + x1, y1], fill=color)

        def point(x: int, y: int, color: tuple[int, int, int]) -> None:
            d.point((ox + x, y), fill=color)

        if name == "void":
            rect(0, 0, GRID - 1, GRID - 1, C["void"])
        elif name == "wall":
            rect(0, 0, GRID - 1, GRID - 1, C["wall"])
            rect(0, 0, GRID - 1, 1, C["lit"])
            rect(0, GRID - 2, GRID - 1, GRID - 1, dark)
            if motif == "oil":
                line(2, 6, 13, 6, C["accent"])
                line(4, 7, 11, 7, dark)
                point(12, 4, C["accent_lit"])
                point(13, 9, C["wet"])
            elif motif == "tile_grid":
                line(7, 0, 7, GRID - 1, C["edge"])
                line(0, 7, GRID - 1, 7, C["edge"])
                point(1, 1, C["lit"])
                point(8, 8, C["accent"])
                point(14, 3, C["accent"])
            elif motif == "hazard":
                for k in range(0, GRID, 4):
                    rect(k, GRID - 6, k + 1, GRID - 3, C["accent"])
                point(3, 4, C["accent_lit"])
                line(2, 9, 13, 9, C["accent"])
            elif motif == "sand":
                for (x, y) in ((3, 4), (7, 6), (11, 5), (5, 9), (12, 10), (8, 12)):
                    point(x, y, C["accent"])
                line(2, 8, 12, 8, C["accent_lit"])
        elif name == "dado":
            rect(0, 0, GRID - 1, GRID - 1, dark)
            rect(0, 0, GRID - 1, 0, C["wall"])
            rect(0, GRID - 2, GRID - 1, GRID - 1, C["void"])
            line(2, 5, 13, 5, C["accent"])
            point(4, 9, C["accent_lit"])
        elif name == "cracked":
            rect(0, 0, GRID - 1, GRID - 1, C["wall"])
            rect(0, 0, GRID - 1, 1, C["lit"])
            pts = [(4, 3), (6, 6), (5, 9), (9, 13)]
            for a, b in zip(pts, pts[1:]):
                line(a[0], a[1], b[0], b[1], dark)
            line(2, GRID - 2, 14, GRID - 2, dark)
            point(11, 8, C["accent"])
        elif name == "base":
            rect(0, 0, GRID - 1, GRID - 1, C["floor"])
            rect(0, 0, GRID - 1, 0, C["top"])
            rect(0, GRID - 1, GRID - 1, GRID - 1, dark)
            point(5, 5, C["edge"])
            point(11, 9, C["edge"])
        elif name == "floor":
            rect(0, 0, GRID - 1, GRID - 1, C["floor"])
            rect(0, 0, GRID - 1, 1, C["top"])
            rect(0, GRID - 1, GRID - 1, GRID - 1, dark)
            if motif == "oil":
                rect(4, 8, 11, 12, C["accent"])
                point(7, 7, C["accent_lit"])
                point(12, 5, C["wet"])
            elif motif == "tile_grid":
                line(7, 0, 7, GRID - 1, C["edge"])
                line(0, 7, GRID - 1, 7, C["edge"])
                point(8, 8, C["lit"])
            elif motif == "hazard":
                line(3, 10, 12, 10, C["accent"])
                point(6, 6, C["accent_lit"])
            elif motif == "sand":
                for (x, y) in ((3, 5), (6, 8), (10, 4), (12, 11), (8, 12)):
                    point(x, y, C["accent"])
                line(2, 13, 13, 13, C["accent_lit"])
        elif name == "wet":
            rect(0, 0, GRID - 1, GRID - 1, C["floor"])
            rect(0, 0, GRID - 1, 0, C["top"])
            rect(3, 5, 12, 12, C["wet"])
            point(6, 7, C["edge"])
            point(9, 9, C["edge"])
            point(5, 11, C["accent"])
            rect(0, GRID - 1, GRID - 1, GRID - 1, dark)
        elif name == "scuff":
            rect(0, 0, GRID - 1, GRID - 1, C["floor"])
            rect(0, 0, GRID - 1, 0, C["top"])
            line(2, 6, 9, 12, C["accent"])
            line(6, 5, 13, 10, shadow)
            point(4, 9, C["accent_lit"])
            rect(0, GRID - 1, GRID - 1, GRID - 1, dark)

    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    # 自检：逐格 ≤16 色 + 色集 ⊆ master.gpl
    valid = set(C.values())
    for index in range(len(TILES)):
        tile = img.crop((index * GRID, 0, (index + 1) * GRID, GRID))
        colors = {px for px in _pixels(tile)}
        if len(colors) > 16:
            raise SystemExit(f"{theme['id']}: tile {TILES[index]} has {len(colors)} colors")
        if not colors <= valid:
            raise SystemExit(f"{theme['id']}: tile {TILES[index]} has off-palette colors")
    return out


# ---------------------------------------------------------------- props

ROLE_BY_RGB: dict[tuple[int, int, int], str] = {}


def build_prop_variants(theme: dict, P: dict[str, tuple[int, int, int]], out_dir: Path) -> list[dict]:
    global ROLE_BY_RGB
    if not ROLE_BY_RGB:
        ROLE_BY_RGB = {rgb: name for name, rgb in P.items()}
    role_map: dict[str, str] = dict(theme.get("role_map") or {})
    manifest = json.loads(SCHOOL_MANIFEST.read_text(encoding="utf-8"))
    out_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    for asset in manifest.get("assets", []):
        src = SCHOOL_PROPS / str(asset["filename"])
        img = Image.open(src).convert("RGBA")
        px = img.load()
        for y in range(img.height):
            for x in range(img.width):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                role = ROLE_BY_RGB.get((r, g, b))
                if role is None:
                    continue
                target = role_map.get(role, role)
                if target not in P:
                    raise SystemExit(f"{theme['id']}: role_map target missing: {target}")
                px[x, y] = (*P[target], a)
        out = out_dir / str(asset["filename"])
        img.save(out)
        records.append({
            "name": str(asset["name"]),
            "filename": str(asset["filename"]),
            "tile_position": list(asset["tile_position"]),
            "pivot": list(asset["pivot"]),
            "texture": f"res://art/generated_candidates/themes/{theme['id']}/props/{asset['filename']}",
            "asset_id": f"prop_{theme['id']}_{asset['name']}",
        })
    return records


# ---------------------------------------------------------------- signature props

OUTLINE = "c31_dead_black"
METAL = "c21_grey"
LIGHT = "c22_grey_lit"


def draw_signature(kind: str, theme: dict, P: dict[str, tuple[int, int, int]]) -> Image.Image:
    C = role_colors(theme, P)
    dark = C["dado"]
    mid = P[METAL]
    light = P[LIGHT]
    accent = C["accent"]
    accent_lit = C["accent_lit"]
    outline = P[OUTLINE]
    img = Image.new("RGBA", (PROP, PROP), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(x0: int, y0: int, x1: int, y1: int, color, edge=None) -> None:
        d.rectangle([x0, y0, x1, y1], fill=(*color, 255), outline=(*(edge or outline), 255))

    def line(x0: int, y0: int, x1: int, y1: int, color) -> None:
        d.line([x0, y0, x1, y1], fill=(*color, 255))

    def ellipse(x0: int, y0: int, x1: int, y1: int, color) -> None:
        d.ellipse([x0, y0, x1, y1], fill=(*color, 255), outline=(*outline, 255))

    if kind == "pump":
        box(8, 4, 23, 28, mid)
        box(10, 6, 21, 12, dark)
        line(12, 8, 19, 8, accent_lit)
        line(12, 10, 17, 10, light)
        line(23, 8, 28, 8, dark)
        line(28, 8, 28, 20, dark)
        line(28, 20, 24, 22, accent)
        line(24, 22, 23, 24, accent)
        box(10, 25, 21, 28, dark)
    elif kind == "shelf":
        box(2, 6, 29, 28, dark, mid)
        for y in (10, 16, 22):
            line(3, y, 28, y, mid)
            line(4, y + 1, 12, y + 1, accent)
            line(16, y + 1, 26, y + 1, light)
    elif kind == "sign":
        box(13, 12, 19, 29, dark)
        box(5, 3, 27, 13, mid, accent)
        line(8, 6, 24, 6, accent_lit)
        line(8, 9, 18, 9, light)
    elif kind == "drum":
        ellipse(6, 12, 26, 18, accent)
        box(6, 15, 26, 26, accent, dark)
        line(6, 18, 26, 18, accent_lit)
        line(6, 23, 26, 23, dark)
    elif kind == "gurney":
        box(2, 14, 30, 20, light, mid)
        line(3, 19, 29, 19, mid)
        line(4, 21, 4, 26, dark)
        line(28, 21, 28, 26, dark)
        ellipse(2, 25, 7, 30, dark)
        ellipse(25, 25, 30, 30, dark)
        box(4, 10, 16, 14, mid)
    elif kind == "iv_stand":
        line(16, 4, 16, 26, mid)
        line(16, 4, 23, 4, mid)
        box(21, 4, 27, 9, light, mid)
        line(22, 9, 22, 13, accent)
        ellipse(6, 25, 10, 29, dark)
        ellipse(22, 25, 26, 29, dark)
        line(11, 27, 21, 27, dark)
    elif kind == "wheelchair":
        ellipse(4, 12, 24, 28, mid)
        ellipse(9, 17, 19, 25, dark)
        box(12, 8, 20, 12, accent)
        line(20, 10, 25, 10, dark)
        line(25, 10, 25, 20, dark)
        ellipse(20, 24, 27, 30, dark)
    elif kind == "med_cabinet":
        box(7, 4, 25, 28, light, mid)
        line(16, 5, 16, 27, dark)
        box(10, 8, 13, 11, accent)
        box(10, 12, 13, 20, accent)
        box(18, 8, 22, 10, dark)
        line(9, 24, 23, 24, dark)
    elif kind == "hose_reel":
        ellipse(5, 8, 27, 26, accent)
        ellipse(10, 12, 22, 22, dark)
        line(6, 6, 26, 6, mid)
        line(24, 22, 28, 27, accent_lit)
        line(22, 10, 28, 8, dark)
    elif kind == "axe_board":
        box(5, 3, 27, 26, dark, mid)
        line(9, 6, 9, 23, mid)
        box(9, 6, 17, 12, accent, dark)
        line(17, 12, 23, 16, accent_lit)
        line(13, 18, 22, 23, light)
    elif kind == "helmet_rack":
        line(3, 8, 29, 8, mid)
        line(6, 9, 6, 24, dark)
        line(26, 9, 26, 24, dark)
        for x in (8, 15, 22):
            ellipse(x, 3, x + 6, 8, accent)
            line(x, 8, x, 12, dark)
        line(4, 24, 28, 24, mid)
    elif kind == "relay":
        line(16, 2, 16, 28, mid)
        line(10, 6, 22, 6, accent)
        line(12, 10, 20, 10, accent_lit)
        box(8, 16, 24, 26, dark, mid)
        line(10, 19, 22, 19, light)
        ellipse(6, 27, 10, 30, dark)
        ellipse(22, 27, 26, 30, dark)
    elif kind == "sandbag":
        for (x, y) in ((2, 22), (10, 22), (18, 22), (6, 15), (14, 15), (22, 15)):
            d.rectangle([x, y, x + 11, y + 8], fill=(*accent, 255), outline=(*outline, 255))
            line(x + 2, y + 2, x + 8, y + 2, accent_lit)
    elif kind == "crate":
        box(4, 8, 28, 28, dark, mid)
        line(4, 14, 28, 14, mid)
        line(14, 8, 14, 28, mid)
        line(6, 10, 12, 10, accent)
        line(18, 16, 26, 16, light)
    elif kind == "barricade":
        for k in range(0, 30, 6):
            d.rectangle([2 + k, 12, 7 + k, 24], fill=(*accent, 255))
        d.rectangle([2, 12, 30, 24], outline=(*outline, 255))
        line(2, 16, 30, 16, accent_lit)
        line(6, 24, 6, 29, dark)
        line(26, 24, 26, 29, dark)
    elif kind == "antenna":
        line(16, 2, 16, 28, mid)
        line(9, 8, 23, 8, accent)
        line(16, 2, 9, 8, accent_lit)
        line(16, 2, 23, 8, accent_lit)
        box(10, 20, 22, 28, dark, mid)
        line(13, 23, 19, 23, light)
    else:
        raise SystemExit(f"unknown signature kind: {kind}")

    # 二值 alpha 自检
    alpha_values = {px[3] for px in _pixels(img)}
    if not alpha_values <= {0, 255}:
        raise SystemExit(f"{kind}: non-binary alpha {sorted(alpha_values)}")
    colors = {px[:3] for px in _pixels(img) if px[3]}
    if len(colors) > 16:
        raise SystemExit(f"{kind}: {len(colors)} colors > 16")
    return img


# ---------------------------------------------------------------- scene


def write_props_scene(theme: dict, entries: list[dict], sig_entries: list[dict], out: Path) -> None:
    lines: list[str] = []
    ext: list[str] = []
    for index, entry in enumerate(entries + sig_entries, start=1):
        ext.append(f'[ext_resource type="Texture2D" path="{entry["texture"]}" id="{index}"]')
    lines.append(f"[gd_scene load_steps={len(ext) + 1} format=3]")
    lines.append("")
    lines.extend(ext)
    lines.append("")
    lines.append('[node name="Props" type="Node2D"]')
    for index, entry in enumerate(entries, start=1):
        tx = int(entry["tile_position"][0]) * GRID + PROP // 2
        ty = int(entry["tile_position"][1]) * GRID + PROP // 2
        lines.append("")
        lines.append(f'[node name="{entry["name"]}" type="Sprite2D" parent="."]')
        lines.append(f"position = Vector2({tx}, {ty})")
        lines.append(f'texture = ExtResource("{index}")')
    for offset, entry in enumerate(sig_entries):
        index = len(entries) + offset + 1
        tile = SIGNATURE_POSITIONS[offset]
        tx = int(tile[0]) * GRID + PROP // 2
        ty = int(tile[1]) * GRID + PROP // 2
        lines.append("")
        lines.append(f'[node name="{entry["name"]}" type="Sprite2D" parent="."]')
        lines.append(f"position = Vector2({tx}, {ty})")
        lines.append(f'texture = ExtResource("{index}")')
        lines.append("metadata/decor = true")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    P = palette_roles()
    for building in GENERATED:
        theme = load_theme(building)
        out_dir = THEMES / building
        tiles = build_tiles(theme, role_colors(theme, P), out_dir / f"tiles_{building}.png")
        entries = build_prop_variants(theme, P, out_dir / "props")
        sig_entries: list[dict] = []
        sig_dir = out_dir / "signature"
        sig_dir.mkdir(parents=True, exist_ok=True)
        for slot, signature in enumerate(theme.get("signature", [])):
            img = draw_signature(str(signature["kind"]), theme, P)
            path = sig_dir / f'{signature["id"]}.png'
            img.save(path)
            sig_entries.append({
                "name": str(signature["id"]),
                "filename": f'{signature["id"]}.png',
                "tile_position": list(SIGNATURE_POSITIONS[slot]),
                "pivot": [16, 16],
                "texture": f"res://art/generated_candidates/themes/{building}/signature/{signature['id']}.png",
                "asset_id": f"prop_{building}_{signature['id']}",
            })
        scene = SCENES / f"props_{building}.tscn"
        write_props_scene(theme, entries, sig_entries, scene)
        (out_dir / "manifest.json").write_text(json.dumps({
            "schema": "building-theme-assets.v1",
            "building": building,
            "tileset": f"res://art/generated_candidates/themes/{building}/tiles_{building}.png",
            "props_scene": f"res://game/scenes/props_{building}.tscn",
            "props": entries,
            "signature": sig_entries,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{building}: tiles={tiles.name} props={len(entries)} signature={len(sig_entries)} scene={scene.name}")
    print("THEME_BUILD_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
