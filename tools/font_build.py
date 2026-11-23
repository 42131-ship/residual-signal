#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build PF-01 (legacy 5×7 HUD) and PF-02 (hard-alpha inspection text).

Usage: python tools/font_build.py
PF-02 bakes only the glyphs used by the current inspection catalog and key hints.
The bundled OFL font is a build input; the scene draws the PNG at native size.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "generated_candidates" / "fonts" / "PF-01_5x7.png"
CJK_OUT = ROOT / "art" / "generated_candidates" / "fonts" / "PF-02_cjk_12.png"
CJK_MAP_OUT = ROOT / "art" / "generated_candidates" / "fonts" / "PF-02_cjk_12.json"
CJK_FONT = ROOT / "art" / "fonts" / "NotoSansSC-VF.ttf"
INSPECTIONS = ROOT / "data" / "prop_inspections.json"
LOOT_CONTAINERS = ROOT / "data" / "loot" / "containers.json"
LOOT_ITEMS = ROOT / "data" / "loot" / "items.json"
STATUS_DATA = ROOT / "data" / "systems" / "status.json"
TRAVEL_ROUTES = ROOT / "data" / "travel" / "routes.json"
# 战利品面板的固定文案：与 corridor.gd 的 _search_container / _loot_lines 保持一致。
LOOT_UI_TEXT = "找到：共件已经搜过一次剧情模式不会刷新里面是空的连灰都没有、…（）"
# 背包与使用界面的固定文案（与 corridor.gd 的 _render_inventory / _use_selected_item 一致）。
INVENTORY_UI_TEXT = (
    "背包装备物资体力使用丢弃关闭搜柜子会拿到东西已放入背包满了剩件没拿用了丢掉"
    "这件东西现在用不上已经装备区开关门锁着撬钥匙挂上了或"
    "耐久弹敌人空手没有子弹按装填完成坏感染体抓伤你被了武器倒下的，发"
)
ASCII_EXTRA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ/×()"
PAL = ROOT / "art" / "palettes" / "master.gpl"
CELL_SIZE = 16
CJK_COLUMNS = 16
# 中文每字步进。以前是 12，为了「12px 步进内不重叠」把 14px 字形最近邻压到 10px，
# 笔画糊成一团——这是 Stage 2 之后「所有字体都很糊」的真正原因。
# 现在步进放到 14，字形不再降采样；面板最宽一行 12 字 = 168px，368px 面板放得下。
CJK_ADVANCE = 14
CJK_MAX_INK_W = CJK_ADVANCE - 1   # 13：留 1px 侧距，保证相邻字不粘
CJK_MAX_INK_H = CELL_SIZE - 2     # 14
CJK_PIXEL_SIZE = 13               # 栅格字号：13px 的汉字墨迹落在 13x13 内，不用降采样


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


def _scan_script_cjk() -> set[str]:
    """收集 game/*.gd 里所有**字符串字面量**中的中日韩字符。

    为什么扫脚本：图集原先只从 JSON 取字，结果「搜索」的『索』只写在
    corridor.gd 里，运行时静默少一个字。注释里的中文不扫——那是给人看的，
    烤进图集只会白占字形。
    """
    found: set[str] = set()
    roots = [ROOT / "game"]
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.gd")):
            text = path.read_text(encoding="utf-8", errors="replace")
            for literal in re.findall(r'"(?:[^"\\]|\\.)*"', text):
                found.update(re.findall(r"[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]", literal))
    return found


def _build_cjk_atlas(ink: tuple[int, int, int]) -> int:
    from PIL import ImageDraw, ImageFont

    if not CJK_FONT.exists():
        raise SystemExit(f"CJK font source missing: {CJK_FONT}")
    data = json.loads(INSPECTIONS.read_text(encoding="utf-8"))
    characters = set("EESCV") | set(ASCII_EXTRA) | set(INVENTORY_UI_TEXT) | set(str(data.get("ui", {}).get("inspect", "查看"))) | set(str(data.get("ui", {}).get("close", "关闭")))
    for record in data.get("records", []):
        characters.update(str(record.get("title", "")))
        for line in record.get("lines", []):
            characters.update(str(line))
    # 可搜索柜子的标签、物品名、固定提示也必须进图集，否则面板会缺字。
    if LOOT_CONTAINERS.exists():
        loot = json.loads(LOOT_CONTAINERS.read_text(encoding="utf-8"))
        for container in loot.get("containers", []):
            characters.update(str(container.get("label", "")))
        characters.update(LOOT_UI_TEXT)
    if LOOT_ITEMS.exists():
        items = json.loads(LOOT_ITEMS.read_text(encoding="utf-8"))
        for entry in items.get("items", []):
            characters.update(str(entry.get("name", "")))
    # 状态名（伤口/感染/中毒/成瘾）只在 data/systems/status.json 里，也要进图集。
    if STATUS_DATA.exists():
        status = json.loads(STATUS_DATA.read_text(encoding="utf-8"))
        for entry in status.get("statuses", []):
            characters.update(str(entry.get("label", "")))
    # 楼名（学校/加油站/医院/消防站/军事基地）只在 routes.json 里，地图要用。
    if TRAVEL_ROUTES.exists():
        routes = json.loads(TRAVEL_ROUTES.read_text(encoding="utf-8"))
        for entry in routes.get("buildings", []):
            characters.update(str(entry.get("label", "")))
    characters = sorted(characters - {"", "\n", "\r", "\t", " "})
    # 代码里的中文字面量（动词、提示语、报错文案）也要进图集：
    # 「搜索」的『索』只出现在 .gd 里，不扫脚本就会静默少字。
    characters = sorted(set(characters) | (_scan_script_cjk() - {"", "\n", "\r", "\t", " "}))


    rows = (len(characters) + CJK_COLUMNS - 1) // CJK_COLUMNS
    atlas = Image.new("RGBA", (CJK_COLUMNS * CELL_SIZE, rows * CELL_SIZE), (0, 0, 0, 0))
    font = ImageFont.truetype(str(CJK_FONT), CJK_PIXEL_SIZE)
    if hasattr(font, "set_variation_by_axes"):
        font.set_variation_by_axes([650])
    draw = ImageDraw.Draw(atlas)
    glyph_map: dict[str, list[int]] = {}
    shrunk = 0
    widest = 0
    tallest = 0
    for index, char in enumerate(characters):
        cell_x = (index % CJK_COLUMNS) * CELL_SIZE
        cell_y = (index // CJK_COLUMNS) * CELL_SIZE
        bounds = font.getbbox(char)
        mask = Image.new("L", (bounds[2] - bounds[0] + 2, bounds[3] - bounds[1] + 2), 0)
        ImageDraw.Draw(mask).text((1 - bounds[0], 1 - bounds[1]), char, font=font, fill=255)
        mask = mask.point(lambda value: 255 if value >= 110 else 0)
        ink_bounds = mask.getbbox()
        if ink_bounds is None:
            raise SystemExit(f"empty glyph: {char}")
        mask = mask.crop(ink_bounds)
        scale = min(CJK_MAX_INK_W / mask.width, CJK_MAX_INK_H / mask.height, 1.0)
        target = (max(1, round(mask.width * scale)), max(1, round(mask.height * scale)))
        if target != mask.size:
            mask = mask.resize(target, Image.Resampling.NEAREST)
            shrunk += 1
        widest = max(widest, mask.width)
        tallest = max(tallest, mask.height)
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
        "advance": CJK_ADVANCE,
        "columns": CJK_COLUMNS,
        "characters": glyph_map,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CJK 字形: {len(characters)} 个 · 步进 {CJK_ADVANCE}px · "
          f"墨迹最大 {widest}x{tallest} · 被缩小的字 {shrunk}")
    if widest > CJK_MAX_INK_W or tallest > CJK_MAX_INK_H:
        raise SystemExit(f"CJK atlas overflow: {widest}x{tallest}")
    if shrunk > 0:
        print(f"注意: {shrunk} 个字仍被降采样（字形超出 {CJK_MAX_INK_W}x{CJK_MAX_INK_H}）")
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
