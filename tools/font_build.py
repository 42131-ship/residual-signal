#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build PF-01 (legacy 5×7 HUD) and PF-02 (hard-alpha inspection text).

Usage: python tools/font_build.py
PF-02 bakes only the glyphs used by the current inspection catalog and key hints.
The bundled OFL font is a build input; the scene draws the PNG at native size.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated_candidates" / "fonts" / "PF-01_5x7.png"
CJK_OUT = ROOT / "art" / "generated_candidates" / "fonts" / "PF-02_cjk_12.png"
CJK_MAP_OUT = ROOT / "art" / "generated_candidates" / "fonts" / "PF-02_cjk_12.json"
CJK_FONT = ROOT / "art" / "fonts" / "NotoSansSC-VF.ttf"
INSPECTIONS = ROOT / "data" / "prop_inspections.json"
PAL = ROOT / "art" / "palettes" / "master.gpl"
CELL_SIZE = 16
CJK_COLUMNS = 16

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

GLYPHS: dict[str, list[str]] = {
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "0": ["01110", "10011", "10101", "10101", "10101", "11001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}
ORDER = list(GLYPHS.keys()) + [" ", " "]      # 14 格


def read_gpl_named(path: Path) -> dict[str, tuple[int, int, int]]:
    out: dict[str, tuple[int, int, int]] = {}
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        ln = ln.strip()
        if not ln or ln.startswith(("#", "GIMP", "Name:", "Columns:")):
            continue
        p = ln.split()
        if len(p) >= 3 and all(x.isdigit() for x in p[:3]):
            out[p[3] if len(p) > 3 else f"#{len(out):02d}"] = (int(p[0]), int(p[1]), int(p[2]))
    return out


def _build_cjk_atlas(ink: tuple[int, int, int]) -> int:
    from PIL import ImageDraw, ImageFont

    if not CJK_FONT.exists():
        raise SystemExit(f"CJK font source missing: {CJK_FONT}")
    data = json.loads(INSPECTIONS.read_text(encoding="utf-8"))
    characters = set("EESC") | set(str(data.get("ui", {}).get("inspect", "查看"))) | set(str(data.get("ui", {}).get("close", "关闭")))
    for record in data.get("records", []):
        characters.update(str(record.get("title", "")))
        for line in record.get("lines", []):
            characters.update(str(line))
    characters = sorted(characters - {"", "\n", "\r", "\t", " "})

    rows = (len(characters) + CJK_COLUMNS - 1) // CJK_COLUMNS
    atlas = Image.new("RGBA", (CJK_COLUMNS * CELL_SIZE, rows * CELL_SIZE), (0, 0, 0, 0))
    font = ImageFont.truetype(str(CJK_FONT), 14)
    if hasattr(font, "set_variation_by_axes"):
        font.set_variation_by_axes([650])
    draw = ImageDraw.Draw(atlas)
    glyph_map: dict[str, list[int]] = {}
    for index, char in enumerate(characters):
        cell_x = (index % CJK_COLUMNS) * CELL_SIZE
        cell_y = (index // CJK_COLUMNS) * CELL_SIZE
        bounds = font.getbbox(char)
        mask = Image.new("L", (bounds[2] - bounds[0] + 2, bounds[3] - bounds[1] + 2), 0)
        ImageDraw.Draw(mask).text((1 - bounds[0], 1 - bounds[1]), char, font=font, fill=255)
        mask = mask.point(lambda value: 255 if value >= 96 else 0)
        ink_bounds = mask.getbbox()
        if ink_bounds is None:
            raise SystemExit(f"empty glyph: {char}")
        mask = mask.crop(ink_bounds)
        scale = min(10 / mask.width, 12 / mask.height, 1.0)
        target = (max(1, round(mask.width * scale)), max(1, round(mask.height * scale)))
        if target != mask.size:
            mask = mask.resize(target, Image.Resampling.NEAREST)
        glyph = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
        left = (CELL_SIZE - mask.width) // 2
        top = (CELL_SIZE - mask.height) // 2
        colored = Image.new("RGBA", mask.size, (*ink, 0))
        colored.putalpha(mask)
        glyph.alpha_composite(colored, (left, top))
        atlas.paste(glyph, (cell_x, cell_y))
        glyph_map[char] = {
            "region": [cell_x + left, cell_y + top, mask.width, mask.height],
            "offset": [left, top],
        }

    CJK_OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(CJK_OUT)
    CJK_MAP_OUT.write_text(json.dumps({
        "schema": "pixel-font-atlas.v1",
        "font": "Noto Sans SC",
        "cell_size": CELL_SIZE,
        "advance": 12,
        "columns": CJK_COLUMNS,
        "characters": glyph_map,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    return len(characters)


def main() -> int:
    P = read_gpl_named(PAL)
    ink = P.get("c30_white", (246, 246, 240))
    img = Image.new("RGB", (16 * 6, 16), P.get("c00_void", (3, 5, 10)))
    px = img.load()

    for idx, ch in enumerate(ORDER):
        bits = GLYPHS.get(ch)
        if bits is None:
            continue
        ox = idx * 6
        for y, row in enumerate(bits):
            for x, c in enumerate(row):
                if c == "1":
                    px[ox + x, y] = ink

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    count = _build_cjk_atlas(ink)
    print(f"{OUT}  {img.size}  字符 {len(GLYPHS)} + 空格")
    print(f"{CJK_OUT}  cell={CELL_SIZE}  CJK={count}")
    print("顺序: " + "".join(ORDER))
    return 0


if __name__ == "__main__":
    sys.exit(main())
