#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build PF-01 (legacy 5×7 HUD) and PF-02 (hard-alpha inspection text).

Usage: python tools/font_build.py          # 重建 PF-01/PF-02 图集
       python tools/font_build.py --check  # 只读门禁：图集是否覆盖所有运行时文案
PF-02 bakes every glyph the runtime can draw: inspection catalog, loot/backpack UI,
status names, travel labels, event cards, endings, and CJK string literals in game/*.gd.
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
# 主字体：Fusion 像素字体 12px（TakWolf，SIL OFL 1.1）。它是「为 12px 设计」的点阵字体，
# 笔画直接对齐像素网格。之前用 NotoSansSC 缩到 13px 再二值化，复杂汉字墨迹占格 41%~85%，
# 必然糊成一团——这是「所有字都很糊」的真正原因，换成点阵字体就没了。
CJK_FONT = ROOT / "art" / "fonts" / "FusionPixel-12px-proportional-zh_hans.ttf"
# 兜底：Fusion 极少数未覆盖的字用 Noto 同尺寸渲染（同样是 OFL，可随包）。
CJK_FONT_FALLBACK = ROOT / "art" / "fonts" / "NotoSansSC-VF.ttf"
INSPECTIONS = ROOT / "data" / "prop_inspections.json"
LOOT_CONTAINERS = ROOT / "data" / "loot" / "containers.json"
LOOT_ITEMS = ROOT / "data" / "loot" / "items.json"
STATUS_DATA = ROOT / "data" / "systems" / "status.json"
TRAVEL_ROUTES = ROOT / "data" / "travel" / "routes.json"
CARD_DIR = ROOT / "data" / "cards"
ENDINGS_DIR = ROOT / "data" / "endings"
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
# 12px 点阵字体的设计尺寸就是 12：不降采样、不居中留白。
# 行内步进由每个字自己的 advance 决定（中文 12，拉丁 6~10，写进 JSON 的 advance 字段）；
# 这里的 CJK_ADVANCE 只是「缺该字段时的兜底」，也用于老存档/老图集的兼容。
CJK_ADVANCE = 12
CJK_MAX_INK_W = CELL_SIZE - 2      # 14：12px 字体墨迹 ≤12，留余量
CJK_MAX_INK_H = CELL_SIZE - 2      # 14
CJK_PIXEL_SIZE = 12                # 字体设计尺寸，改大改小都会毁掉点阵对齐


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
                # 不只中日韩：箭头 / 间隔号 / 引号 / 省略号 / 全角标点也会被画出来
                # （如 DayCycle 结算文案里的 "沉积 3→4 · 体力 80"）。
                found.update(re.findall(
                    r"[\u00b7\u00d7\u2010-\u2027\u2030-\u205e\u2190-\u21ff"
                    r"\u2500-\u257f\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]", literal))
    return found


def _collect_cjk_characters() -> list[str]:
    """所有**运行时会被画出来**的中日韩字符（单一来源，构建与检查共用）。"""
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
    # D15：事件卡文本（default 会替换槽位，所以槽位选项 + when 也要进图集）——
    # 卡牌每天都会渲染到 HUD，漏字会静默少字。
    if CARD_DIR.exists():
        for path in sorted(CARD_DIR.glob("*.json")):
            raw = json.loads(path.read_text(encoding="utf-8"))
            for card in raw.get("cards", []):
                for value in (card.get("text", {}) or {}).values():
                    characters.update(str(value))
                for slot in card.get("slots", []):
                    for option in slot.get("options", []):
                        characters.update(str(option))
                for effect in card.get("effects", []):
                    characters.update(str(effect.get("when", "")))
    # D15：结局栏（label / summary / 未解锁占位）由主菜单渲染。
    if ENDINGS_DIR.exists():
        for path in sorted(ENDINGS_DIR.glob("*.json")):
            raw = json.loads(path.read_text(encoding="utf-8"))
            for ending in raw.get("endings", []):
                for key in ("label", "locked_label", "locked_summary", "summary"):
                    characters.update(str(ending.get(key, "")))
    characters = sorted(characters - {"", "\n", "\r", "\t", " "})
    # 代码里的中文字面量（动词、提示语、报错文案）也要进图集：
    # 「搜索」的『索』只出现在 .gd 里，不扫脚本就会静默少字。
    # 兜底：data/ 下**所有** JSON 的字符串值都进图集。
    # 之前漏了 data/analytics/events.json 的隐私文案（同意页真的会画出来），
    # 运行时表现为「匿名收集」少「匿」「集」两个字。宁可多收字，不能少字。
    data_root = ROOT / "data"
    extra: set[str] = set()
    if data_root.exists():
        for path in sorted(data_root.rglob("*.json")):
            try:
                raw = json.loads(path.read_text(encoding="utf-8"))
            except Exception:  # noqa: BLE001
                continue
            stack: list[object] = [raw]
            while stack:
                node = stack.pop()
                if isinstance(node, dict):
                    stack.extend(node.values())
                elif isinstance(node, list):
                    stack.extend(node)
                elif isinstance(node, str):
                    extra.update(re.findall(
                        r"[\u00b7\u00d7\u2010-\u2027\u2030-\u205e\u2190-\u21ff"
                        r"\u2500-\u257f\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]", node))
    return sorted(set(characters) | extra | (_scan_script_cjk() - {"", "\n", "\r", "\t", " "}))


def _build_cjk_atlas(ink: tuple[int, int, int]) -> int:
    from PIL import ImageDraw, ImageFont

    if not CJK_FONT.exists():
        raise SystemExit(f"CJK font source missing: {CJK_FONT}")
    data = json.loads(INSPECTIONS.read_text(encoding="utf-8"))
    characters = _collect_cjk_characters()


    rows = (len(characters) + CJK_COLUMNS - 1) // CJK_COLUMNS
    atlas = Image.new("RGBA", (CJK_COLUMNS * CELL_SIZE, rows * CELL_SIZE), (0, 0, 0, 0))
    font = ImageFont.truetype(str(CJK_FONT), CJK_PIXEL_SIZE)
    fallback = ImageFont.truetype(str(CJK_FONT_FALLBACK), CJK_PIXEL_SIZE) if CJK_FONT_FALLBACK.exists() else None
    glyph_map: dict[str, list[int]] = {}
    shrunk = 0
    fell_back = 0
    widest = 0
    tallest = 0
    for index, char in enumerate(characters):
        cell_x = (index % CJK_COLUMNS) * CELL_SIZE
        cell_y = (index // CJK_COLUMNS) * CELL_SIZE
        used = font
        advance = int(round(font.getlength(char)))
        if advance <= 0 and fallback is not None:
            used, advance = fallback, int(round(fallback.getlength(char)))
            fell_back += 1
        if advance <= 0:
            raise SystemExit(f"zero advance: {char!r}")
        # 以「笔位」为原点渲染（PAD 只是量取缓冲）：
        # offset 记录墨迹相对笔位的偏移，这样成比例字距（拉丁 6~10px）才能正确排布；
        # 旧做法把字形在 16px 格子里居中，遇到非等宽 advance 会既粘又飘。
        pad = 4
        probe = Image.new("L", (advance + pad * 2, CELL_SIZE + pad * 2), 0)
        ImageDraw.Draw(probe).text((pad, pad), char, font=used, fill=255)
        probe = probe.point(lambda value: 255 if value >= 110 else 0)
        ink_bounds = probe.getbbox()
        if ink_bounds is None:
            raise SystemExit(f"empty glyph: {char}")
        mask = probe.crop(ink_bounds)
        scale = min(CJK_MAX_INK_W / mask.width, CJK_MAX_INK_H / mask.height, 1.0)
        target = (max(1, round(mask.width * scale)), max(1, round(mask.height * scale)))
        if target != mask.size:
            mask = mask.resize(target, Image.Resampling.NEAREST)
            shrunk += 1
        widest = max(widest, mask.width)
        tallest = max(tallest, mask.height)
        colored = Image.new("RGBA", mask.size, (*ink, 0))
        colored.putalpha(mask)
        atlas.paste(colored, (cell_x, cell_y))
        glyph_map[char] = {
            "region": [cell_x, cell_y, mask.width, mask.height],
            "offset": [ink_bounds[0] - pad, ink_bounds[1] - pad],
            "advance": advance,
        }

    CJK_OUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(CJK_OUT)
    CJK_MAP_OUT.write_text(json.dumps({
        "schema": "pixel-font-atlas.v1",
        "font": "Fusion Pixel 12px proportional (SIL OFL 1.1)",
        "fallback_font": "Noto Sans SC (SIL OFL 1.1)",
        "cell_size": CELL_SIZE,
        "advance": CJK_ADVANCE,
        "columns": CJK_COLUMNS,
        "characters": glyph_map,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CJK 字形: {len(characters)} 个 · 兜底字 {fell_back} · 中文步进 {CJK_ADVANCE}px · "
          f"墨迹最大 {widest}x{tallest} · 被缩小的字 {shrunk}")
    if widest > CJK_MAX_INK_W or tallest > CJK_MAX_INK_H:
        raise SystemExit(f"CJK atlas overflow: {widest}x{tallest}")
    if shrunk > 0:
        print(f"注意: {shrunk} 个字仍被降采样（字形超出 {CJK_MAX_INK_W}x{CJK_MAX_INK_H}）")
    return len(characters)


def _check_coverage() -> int:
    """D15 门禁：图集必须覆盖所有会在运行时被画出来的字符。

    只读：不重写 PNG/JSON。缺字时打印 `FONT_MISSING <chars>` 并返回 1。
    """
    if not CJK_MAP_OUT.exists():
        print(f"FONT_MAP_MISSING {CJK_MAP_OUT}")
        return 1
    atlas = json.loads(CJK_MAP_OUT.read_text(encoding="utf-8"))
    glyphs = set((atlas.get("characters") or {}).keys())
    required = set(_collect_cjk_characters())
    missing = sorted(required - glyphs)
    print(f"FONT_COVERAGE required={len(required)} glyphs={len(glyphs)} missing={len(missing)}")
    if missing:
        print("FONT_MISSING " + "".join(missing))
        return 1
    extra = len(glyphs - required)
    if extra:
        print(f"FONT_EXTRA {extra}（数据删字后图集允许冗余，不判失败）")
    return 0


def main() -> int:
    if "--check" in sys.argv[1:]:
        return _check_coverage()
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
