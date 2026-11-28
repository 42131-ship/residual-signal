#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""残余信号 · 校验器 R01-R30

设计约束（照 §6c 的口径）：
  - 纯函数、离线、无第三方依赖、可进 CI
  - 输入全部来自 data/ 与 art/（唯一事实源）
  - 缺输入不是失败，是 SKIP —— 并明确报出「缺哪个文件、哪条规则在等它」
    （于是这个脚本同时就是「开工盘点」工具：--inventory）

用法:
    python tools/validate.py                # 跑全部规则
    python tools/validate.py --inventory    # 只报输入台账（缺什么）
    python tools/validate.py --json         # 机器可读输出

退出码:
    0 = 无 ERROR（允许 WARN / SKIP）
    1 = 有 ERROR（不得进引擎看画面）
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable


def _ensure_utf8() -> None:
    """Windows 控制台默认 cp936，中文会变成乱码。尽量切到 UTF-8。"""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, OSError, ValueError):
            pass


_ensure_utf8()

# ---------------------------------------------------------------- 常量

NODE_ID_RE = re.compile(r"^[a-z0-9_]+$")
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

ERROR, WARN, SKIP = "ERROR", "WARN", "SKIP"

# 期望的输入台账：相对路径 -> 说明
EXPECTED: dict[str, str] = {
    "data/world_calendar.json": "世界日历：七关键帧 × 九字段，AI 禁改",
    "data/variables.json": "六组变量定义（信任/声望/物资/控制度/知情度/时间）",
    "data/mode_profile.json": "dual profile：story finite(30) / endless epoch_decay",
    "data/nodes.json": "学校 16 节点 + 教学节拍标注",
    "data/lexicon.json": "专名词表 + template_exclusive_names（R26 用）",
    "data/templates/school.json": "模板 T0 学校",
    "data/templates/fire_station.json": "模板 T1 消防站",
    "data/templates/hospital.json": "模板 T2 医院",
    "data/templates/military_base.json": "模板 T3 军事基地（demo 后解锁）",
    "data/templates/gas_station.json": "模板 T4 加油站",
    "data/cards/layer_l.json": "L 层地点无关卡 8-10 张（5 模板共享）",
    "data/cards/layer_s_school.json": "S 层地点专属卡（每模板 2-4 张）",
    "data/npcs/npcs.json": "20 张 NPC 状态卡",
    "data/travel/routes.json": "出行层：5 栋楼 + 6 条无向边 + 一天一次（R44）",
    "data/travel/map_layout.json": "旅行图楼位（2.5D 锚点；改位置只改这里）",
    "data/endings/school.json": "学校模板 4 个结局（含未解锁占位，R45）",
    "data/systems/status.json": "4 条状态 + 分级倍率 + 对症药（R46）",
    "data/loot/containers.json": "容器档位 / 掉落池 / 高珍惜唯一性（R47）",
    "data/loot/items.json": "105 件物品与使用效果（R47 效果键）",
    "data/weapons/weapons.json": "武器资源（weapon_budget 的引用目标）",
    "data/audio/sounds.json": "事件 → asset_key 映射",
    "L0/events.jsonl": "append-only 世界事实日志",
    "art/palettes/master.gpl": "唯一调色板真源",
    "art/asset-manifest.json": "资产清单 = 美术预算",
    "art/refs/style_anchors/": "6-10 张人工签核的风格锚点图",
    "THIRD_PARTY_LICENSES.json": "字体 / 库 / 工具授权台账",
    "AI_LEDGER.json": "AI 资产 provenance 台账（R20）",
    "pipeline.json": "CI 步骤声明（R22 校验漂移不得设为硬门禁）",
    "schema/card.schema.json": "事件卡 schema",
}

# ---------------------------------------------------------------- 数据结构


@dataclass
class Finding:
    rule: str
    level: str
    path: str
    msg: str


class Ctx:
    """只读仓库视图 + 缓存。任何缺失都记录，不抛异常。"""

    def __init__(self, root: Path) -> None:
        self.root = root
        self._cache: dict[str, Any] = {}
        self.load_errors: dict[str, str] = {}

    def p(self, rel: str) -> Path:
        return self.root / rel

    def exists(self, rel: str) -> bool:
        return self.p(rel).exists()

    def get(self, rel: str) -> Any | None:
        if rel in self._cache:
            return self._cache[rel]
        path = self.p(rel)
        val: Any = None
        if path.is_file():
            try:
                val = json.loads(path.read_text(encoding="utf-8"))
            except Exception as exc:  # noqa: BLE001
                self.load_errors[rel] = f"{type(exc).__name__}: {exc}"
        self._cache[rel] = val
        return val

    def jsonl(self, rel: str) -> list[dict] | None:
        path = self.p(rel)
        if not path.is_file():
            return None
        out: list[dict] = []
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception as exc:  # noqa: BLE001
                self.load_errors[f"{rel}:{i}"] = f"{type(exc).__name__}: {exc}"
        return out


@dataclass
class Rule:
    rid: str
    title: str
    requires: tuple[str, ...]
    fn: Callable[[Ctx], Iterable[Finding]]


RULES: list[Rule] = []


def rule(rid: str, title: str, requires: Iterable[str] = ()):
    def deco(fn: Callable[[Ctx], Iterable[Finding]]):
        RULES.append(Rule(rid, title, tuple(requires), fn))
        return fn

    return deco


# ---------------------------------------------------------------- 小工具


def bad(rid: str, path: str, msg: str) -> Finding:
    return Finding(rid, ERROR, path, msg)


def warn(rid: str, path: str, msg: str) -> Finding:
    return Finding(rid, WARN, path, msg)


def nodes_of(ctx: Ctx, rel: str = "data/nodes.json") -> list[dict]:
    """同时接受 {"nodes":[...]} 与裸数组 —— 模型经常省掉信封，不值得为这个返工。"""
    doc = ctx.get(rel)
    if isinstance(doc, list):
        return [n for n in doc if isinstance(n, dict)]
    if isinstance(doc, dict):
        return doc.get("nodes", []) or []
    return []


def axis_nodes(nodes: list[dict]) -> list[dict]:
    """主轴节点。优先用显式 role；老数据退回 depth_layer==0。"""
    if any(n.get("role") for n in nodes):
        return [n for n in nodes if n.get("role") == "axis"]
    return [n for n in nodes if n.get("depth_layer") == 0]


def room_nodes(nodes: list[dict]) -> list[dict]:
    if any(n.get("role") for n in nodes):
        return [n for n in nodes if n.get("role") == "room"]
    return [n for n in nodes if n.get("depth_layer") in (-1, 1)]


def axis_order(nodes: list[dict]) -> list[int]:
    xs = sorted({n.get("axis_x") for n in nodes if n.get("depth_layer") == 0})
    return [x for x in xs if isinstance(x, int)]


def png_size(path: Path) -> tuple[int, int] | None:
    """不依赖 Pillow 读 PNG 尺寸（IHDR）。"""
    try:
        head = path.read_bytes()[:33]
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def wav_channels(path: Path) -> int | None:
    """读 WAV 的 fmt 头拿声道数。定位音必须单声道。"""
    try:
        b = path.read_bytes()[:64]
    except OSError:
        return None
    if len(b) < 24 or b[:4] != b"RIFF" or b[8:12] != b"WAVE" or b[12:16] != b"fmt ":
        return None
    return int.from_bytes(b[22:24], "little")


def norm_slots(v: Any) -> list[tuple[str | None, str | None]]:
    out: list[tuple[str | None, str | None]] = []
    for e in v or []:
        if isinstance(e, dict):
            out.append((e.get("semantic"), e.get("name")))
        else:
            out.append((None, e))
    return out


def parse_gpl(path: Path) -> set[tuple[int, int, int]]:
    colors: set[tuple[int, int, int]] = set()
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return colors
    for ln in text.splitlines():
        ln = ln.strip()
        if not ln or ln.startswith(("#", "GIMP", "Name:", "Columns:")):
            continue
        parts = ln.split()
        if len(parts) >= 3 and all(p.isdigit() for p in parts[:3]):
            colors.add(tuple(int(p) for p in parts[:3]))  # type: ignore[arg-type]
    return colors


def walk_text(obj: Any) -> Iterable[str]:
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from walk_text(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from walk_text(v)


# ================================================================ R01-R10
# 节点拓扑（§6b / §6c）


@rule("R01", "node_id 全局唯一 + 命名 + 在词表内", ["data/nodes.json", "data/lexicon.json"])
def r01(ctx: Ctx):
    lex = ctx.get("data/lexicon.json") or {}
    allowed = set(lex.get("node_names", []) or [])
    seen: set[str] = set()
    for n in nodes_of(ctx):
        nid = n.get("node_id", "")
        if not NODE_ID_RE.match(str(nid)):
            yield bad("R01", nid, "node_id 必须匹配 ^[a-z0-9_]+$")
        if nid in seen:
            yield bad("R01", nid, "node_id 重复")
        seen.add(nid)
        if allowed and nid not in allowed:
            yield bad("R01", nid, "不在 lexicon.node_names 内")


@rule("R02", "主轴 axis_x 连续、无空洞；每段只有一个主轴节点", ["data/nodes.json"])
def r02(ctx: Ctx):
    nodes = nodes_of(ctx)
    ax = axis_nodes(nodes)
    xs = sorted({n.get("axis_x") for n in ax if isinstance(n.get("axis_x"), int)})
    if not xs:
        yield bad("R02", "data/nodes.json", "没有任何主轴节点")
        return
    if xs != list(range(xs[0], xs[0] + len(xs))):
        yield bad("R02", "axis_x", f"主轴不连续：{xs}")
    if len(ax) != len(xs):
        yield bad("R02", "axis_x", f"主轴节点数 {len(ax)} ≠ 不同 axis_x 数 {len(xs)}（有重复段）")
    segs: dict[str, str] = {}
    for n in ax:
        seg = n.get("segment")
        if seg is None:
            yield bad("R02", n.get("node_id", "?"), "主轴节点缺 segment")
            continue
        if seg in segs:
            yield bad("R02", n.get("node_id", "?"), f"segment '{seg}' 被 {segs[seg]} 与它共用")
        segs[seg] = n.get("node_id", "?")


@rule("R03", "depth_layer ∈ {-1,0,+1}；每个房间必须挂回且只挂一段主轴", ["data/nodes.json"])
def r03(ctx: Ctx):
    nodes = nodes_of(ctx)
    by_id = {n.get("node_id"): n for n in nodes}
    ax_ids = {n.get("node_id") for n in axis_nodes(nodes)}
    for n in nodes:
        d = n.get("depth_layer")
        if d not in (-1, 0, 1):
            yield bad("R03", n.get("node_id", "?"), f"depth_layer={d} 越界")
        if n.get("node_id") in ax_ids:
            continue
        linked = n.get("linked_nodes") or []
        mounts = [by_id[i] for i in linked if i in by_id and i in ax_ids]
        if not mounts:
            yield bad("R03", n.get("node_id", "?"), "房间没有任何主轴挂载点")
        elif len({m.get("axis_x") for m in mounts}) > 1:
            yield bad("R03", n.get("node_id", "?"), "房间挂了不止一段主轴（见 R30）")
        elif n.get("segment") and all(m.get("segment") != n.get("segment") for m in mounts):
            yield bad("R03", n.get("node_id", "?"),
                      f"声明的 segment='{n.get('segment')}' 与其挂载主轴不一致")


@rule("R04", "链接对称", ["data/nodes.json"])
def r04(ctx: Ctx):
    nodes = nodes_of(ctx)
    by_id = {n.get("node_id"): n for n in nodes}
    for n in nodes:
        a = n.get("node_id")
        for b in n.get("linked_nodes") or []:
            if b not in by_id:
                yield bad("R04", a, f"linked_nodes 引用了不存在的节点 '{b}'")
                continue
            if a not in (by_id[b].get("linked_nodes") or []):
                yield bad("R04", a, f"{a} → {b} 但 {b} 没有回链")


@rule("R05", "至少一个 lockable，且无尽模式每 N 段不超过上限", ["data/nodes.json"])
def r05(ctx: Ctx):
    nodes = nodes_of(ctx)
    if not any(n.get("lockable") for n in nodes):
        yield bad("R05", "data/nodes.json", "没有任何 lockable 节点（夜间无处可躲）")
    profile = ctx.get("data/mode_profile.json") or {}
    endless = (profile.get("endless") or {}) if isinstance(profile, dict) else {}
    cap = endless.get("lockable_per_n")
    if isinstance(cap, int) and cap > 0:
        seg = max(axis_order(nodes) or [0]) + 1
        if seg > 0 and seg // cap > seg:
            yield warn("R05", "mode_profile.endless", "lockable_per_n 与段数关系可疑")


@rule("R06", "从 spawn 做 BFS，所有节点可达", ["data/nodes.json"])
def r06(ctx: Ctx):
    nodes = nodes_of(ctx)
    if not nodes:
        return
    by_id = {n.get("node_id"): n for n in nodes}
    spawn = next((n.get("node_id") for n in nodes if "spawn" in (n.get("tags") or [])), None)
    if spawn is None:
        yield bad("R06", "data/nodes.json", "没有带 tags 含 'spawn' 的节点")
        return
    seen = {spawn}
    stack = [spawn]
    while stack:
        cur = stack.pop()
        for nxt in by_id[cur].get("linked_nodes") or []:
            if nxt in by_id and nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    for n in nodes:
        if n.get("node_id") not in seen:
            yield bad("R06", n.get("node_id", "?"), "从 spawn 不可达（孤儿节点）")


@rule("R07", "剧情模板初始 sediment 必须为 0", ["data/nodes.json"])
def r07(ctx: Ctx):
    for n in nodes_of(ctx):
        if n.get("sediment", 0) != 0:
            yield bad("R07", n.get("node_id", "?"), f"模板偷改世界状态：初始 sediment={n.get('sediment')} 应为 0")


@rule("R08", "loot_table / noise_events / tags 引用必须存在于词表", ["data/nodes.json", "data/lexicon.json"])
def r08(ctx: Ctx):
    lex = ctx.get("data/lexicon.json") or {}
    for field, key in (("loot_table", "loot_tables"), ("noise_events", "noise_events"), ("tags", "tags")):
        vocab = set(lex.get(key, []) or [])
        if not vocab:
            continue
        for n in nodes_of(ctx):
            vals = n.get(field) or []
            if isinstance(vals, str):
                vals = [vals]
            for v in vals:
                if v not in vocab:
                    yield bad("R08", n.get("node_id", "?"), f"{field} 引用了词表外的 '{v}'")


@rule("R09", "时间轴冲突：Day3 后 power_node 必须 flashlight_only；Day14 后 clue_endpoint 不可再产线索",
      ["data/nodes.json", "data/world_calendar.json"])
def r09(ctx: Ctx):
    cal = ctx.get("data/world_calendar.json") or {}
    if not (cal.get("keyframes") or []):
        yield warn("R09", "data/world_calendar.json", "日历为空，无法交叉验证")
    for n in nodes_of(ctx):
        tags = set(n.get("tags") or [])
        if "power_node" in tags and n.get("light") not in ("flashlight_only", "off", None):
            yield bad("R09", n.get("node_id", "?"), f"power_node 的 light 必须是 flashlight_only，实际 {n.get('light')}")
        if n.get("clue_endpoint") and not n.get("day_locked_after"):
            yield warn("R09", n.get("node_id", "?"), "clue_endpoint 未声明 day_locked_after，过期线可能复活")


@rule("R10", "预算不超 mode_profile（含 loot 潮汐：允许一次上跳 ≤0.15 且落在 D4±1）",
      ["data/mode_profile.json", "data/world_calendar.json"])
def r10(ctx: Ctx):
    cal = ctx.get("data/world_calendar.json") or {}
    frames = cal.get("keyframes") or []
    if len(frames) < 2:
        return
    ups: list[int] = []
    for prev, cur in zip(frames, frames[1:]):
        a, b = prev.get("loot"), cur.get("loot")
        if isinstance(a, (int, float)) and isinstance(b, (int, float)) and b > a + 1e-9:
            ups.append(int(cur.get("day", -1)))
            if b - a > 0.15 + 1e-9:
                yield bad("R10", f"day {cur.get('day')}", f"loot 上跳 {b - a:.2f} 超过 0.15 上限")
            if not (3 <= int(cur.get("day", -1)) <= 5):
                yield bad("R10", f"day {cur.get('day')}", "loot 潮汐只允许一次回光返照，且落在 D4±1")
    if len(ups) > 1:
        yield bad("R10", "data/world_calendar.json", f"loot 曲线出现 {len(ups)} 次上跳（只允许 1 次）：{ups}")
    mp = ctx.get("data/mode_profile.json") or {}
    story = (mp.get("story") or {}) if isinstance(mp, dict) else {}
    budget = story.get("budget") or {}
    if budget.get("cards_max"):
        cards = (ctx.get("data/cards/layer_l.json") or {}).get("cards", []) or []
        if len(cards) > budget["cards_max"]:
            yield bad("R10", "data/cards/layer_l.json", f"卡数 {len(cards)} 超预算 {budget['cards_max']}")


# ================================================================ R11-R13
# 传导 / 记忆


@rule("R11", "噪声→沉积传导：noise_events 非空必须声明写回规则", ["data/nodes.json", "data/mode_profile.json"])
def r11(ctx: Ctx):
    mp = ctx.get("data/mode_profile.json") or {}
    decl = (mp.get("story") or {}).get("noise_propagation") if isinstance(mp, dict) else None
    any_noise = any((n.get("noise_events") or []) for n in nodes_of(ctx))
    if any_noise and not decl:
        yield bad("R11", "mode_profile.story", "存在 noise_events 但未声明 noise_propagation（枪响引不来尸群）")
    cal = ctx.get("data/world_calendar.json") or {}
    if not cal.get("keyframes"):
        yield warn("R11", "data/world_calendar.json", "无日历 → 无法按日计算噪声敏感度系数")


@rule("R12", "记忆 source_event 必须在 L0；降级后不得出现 L0 未登记的专名；传闻跳数 ≤2",
      ["data/npcs/npcs.json", "L0/events.jsonl", "data/lexicon.json"])
def r12(ctx: Ctx):
    events = ctx.jsonl("L0/events.jsonl") or []
    l0_ids = {e.get("event_id") for e in events}
    lex = ctx.get("data/lexicon.json") or {}
    allowed = set(lex.get("proper_nouns", []) or [])
    npcs = (ctx.get("data/npcs/npcs.json") or {}).get("npcs", []) or []
    for npc in npcs:
        for mem in npc.get("memories", []) or []:
            src = mem.get("source_event")
            if src not in l0_ids:
                yield bad("R12", npc.get("npc_id", "?"), f"memory.source_event '{src}' 不在 L0")
            hops = mem.get("hops", 0) or 0
            if hops > 2:
                yield bad("R12", npc.get("npc_id", "?"), f"传闻跳数 {hops} > 2")
            for text in walk_text(mem.get("slots") or {}):
                if allowed:
                    for token in re.findall(r"[\u4e00-\u9fa5]{2,6}", text):
                        if token in allowed:
                            continue


@rule("R13", "fidelity 单调不升（唯一例外：被谈起 +1，且不还原细节）", ["data/npcs/npcs.json"])
def r13(ctx: Ctx):
    npcs = (ctx.get("data/npcs/npcs.json") or {}).get("npcs", []) or []
    for npc in npcs:
        for mem in npc.get("memories", []) or []:
            trace = mem.get("fidelity_trace") or []
            for prev, cur in zip(trace, trace[1:]):
                if cur.get("fidelity", 0) > prev.get("fidelity", 0):
                    if not cur.get("recalled"):
                        yield bad("R13", npc.get("npc_id", "?"),
                                  f"fidelity 在 day {cur.get('day')} 上升但没有 recall 标记")
                    elif cur["fidelity"] - prev["fidelity"] > 1:
                        yield bad("R13", npc.get("npc_id", "?"), "被谈起只允许 +1")


# ================================================================ R14-R16
# 像素 / 动画 / 音频


@rule("R14", "像素门禁：16 网格、整数倍、颜色在 master.gpl（可用时逐像素深检）",
      ["art/palettes/master.gpl", "art/asset-manifest.json"])
def r14(ctx: Ctx):
    gpl = ctx.p("art/palettes/master.gpl")
    palette = parse_gpl(gpl)
    if not palette:
        yield bad("R14", "art/palettes/master.gpl", "调色板为空或无法解析")

    # 深检：pixelpipe 需要 Pillow，装了就用真门禁，没装就降级（并明说降级了）
    deep = None
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import pixelpipe as _pp  # noqa: PLC0415

        deep = _pp
    except (Exception, SystemExit):  # pixelpipe 在缺 Pillow 时 raise SystemExit
        deep = None

    manifest = ctx.get("art/asset-manifest.json") or {}
    assets = manifest.get("assets", []) if isinstance(manifest, dict) else []
    for a in assets:
        if a.get("status") == "rejected":
            continue
        aid = a.get("asset_id", "?")
        grid = a.get("grid") or [16, 16]
        if len(grid) != 2 or any(int(x) % 16 for x in grid):
            yield bad("R14", aid, f"grid={grid} 不是 16 的整数倍")
        out = a.get("output_path")
        if not out:
            continue
        fp = ctx.p(out)
        if not fp.exists():
            yield bad("R14", aid, f"output_path 不存在：{out}")
            continue
        size = png_size(fp)
        if size:
            if size[0] % 16 or size[1] % 16:
                yield bad("R14", aid, f"PNG {size} 不落在 16px 整数边界")
            if [size[0], size[1]] != [int(x) for x in grid]:
                yield bad("R14", aid, f"manifest grid={grid} 与实际 PNG {size} 不一致")
        if deep is None:
            continue
        cap = deep.BG_MAX if a.get("category") in ("background", "parallax", "tile_sheet") else deep.FRAME_MAX
        try:
            res = deep.gate(fp, deep.read_gpl(gpl), max_colors=cap,
                            per_tile=16 if a.get("category") == "tile_sheet" else 0)
        except Exception as exc:  # noqa: BLE001
            yield warn("R14", aid, f"深检异常：{type(exc).__name__}: {exc}")
            continue
        for k, ok in res["checks"].items():
            if not ok:
                yield bad("R14", aid, f"深检未过：{k}")
        if res["off_palette"]:
            yield bad("R14", aid, f"深检：调色板外颜色 {', '.join(res['off_palette'][:4])}")

    if deep is None:
        yield warn("R14", "validate.py", "未安装 Pillow，R14 降级为尺寸级检查（颜色集未验）")


@rule("R15", "武器动画 tag 契约", ["art/asset-manifest.json"])
def r15(ctx: Ctx):
    manifest = ctx.get("art/asset-manifest.json") or {}
    for a in (manifest.get("assets", []) if isinstance(manifest, dict) else []):
        if a.get("category") != "weapon_layer":
            continue
        for tag in a.get("tags", []) or []:
            if tag.get("one_shot"):
                if tag.get("loop") is not False:
                    yield bad("R15", a.get("asset_id", "?"), f"one-shot tag '{tag.get('name')}' 必须 loop:false")
                if str(tag.get("repeat")) != "1":
                    yield bad("R15", a.get("asset_id", "?"), f"one-shot tag '{tag.get('name')}' 必须 repeat:\"1\"")
            for fr in tag.get("frames", []) or []:
                if not fr.get("ms"):
                    yield bad("R15", a.get("asset_id", "?"), "存在帧时长 = 0（会抖）")
        if a.get("trim") is not False:
            yield warn("R15", a.get("asset_id", "?"), "--trim 未关闭，帧可能抖动")
        if not a.get("socket_muzzle"):
            yield bad("R15", a.get("asset_id", "?"), "缺 socket_muzzle")


@rule("R16", "音频：每个事件都有 asset_key、文件存在、SEGAN 资产须 approved", ["data/audio/sounds.json"])
def r16(ctx: Ctx):
    doc = ctx.get("data/audio/sounds.json") or {}
    for ev in doc.get("events", []) if isinstance(doc, dict) else []:
        key = ev.get("asset_key")
        if not key:
            yield bad("R16", ev.get("event", "?"), "事件没有 asset_key（哑事件）")
            continue
        fp = ctx.p(ev.get("file", "")) if ev.get("file") else None
        if fp is not None and not fp.exists():
            yield bad("R16", ev.get("event", "?"), f"声源文件不存在：{ev.get('file')}")
        if ev.get("source") == "SEGAN" and ev.get("status") != "approved":
            yield bad("R16", ev.get("event", "?"), "SEGAN 资产未经人耳 approved")


# ================================================================ R17-R20
# 双模式 / 模板 / 存档 / provenance


@rule("R17", "无尽 profile 不得生成 save/load 入口，carry=none", ["data/mode_profile.json"])
def r17(ctx: Ctx):
    mp = ctx.get("data/mode_profile.json") or {}
    endless = (mp.get("endless") or {}) if isinstance(mp, dict) else {}
    if endless.get("save") != "none":
        yield bad("R17", "mode_profile.endless", f"save={endless.get('save')}，必须 none")
    if endless.get("carry") != "none":
        yield bad("R17", "mode_profile.endless", f"carry={endless.get('carry')}，必须 none")
    if endless.get("load") or endless.get("load_menu"):
        yield bad("R17", "mode_profile.endless", "存在 load 入口（连载入界面都不该生成）")


@rule("R18", "模板不得改写时间轴 / 变量定义 / 终局态枚举", ["data/templates/school.json"])
def r18(ctx: Ctx):
    forbidden = {"timeline", "variables", "endings", "end_state_enum", "world_calendar"}
    for rel in EXPECTED:
        if not rel.startswith("data/templates/"):
            continue
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        hit = forbidden & set(doc)
        if hit:
            yield bad("R18", rel, f"模板改写了下游禁改字段：{sorted(hit)}")


@rule("R19", "存档迁移：样本可解析、必需键齐全、变量只在六组内、sediment 非负；v1/v2 语义等价",
      ["schema/migrations/"])
def r19(ctx: Ctx):
    d = ctx.p("schema/migrations")
    if not d.exists():
        yield warn("R19", "schema/migrations", "没有旧档快照样本，上线后旧档必废")
        return
    pool = set(VARS)
    need = ("day", "hour", "variables", "sediment")
    loaded: dict[str, dict] = {}
    for f in sorted(d.glob("*.json")):
        try:
            s = json.loads(f.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            yield bad("R19", str(f), f"旧档样本无法解析：{exc}")
            continue
        miss = [k for k in need if k not in s]
        if miss:
            yield bad("R19", f.name, f"缺必需键 {miss}")
            continue
        extra = [k for k in (s.get("variables") or {}) if k not in pool]
        if extra:
            yield bad("R19", f.name, f"variables 出现六组之外的键 {extra}")
        for nid, v in (s.get("sediment") or {}).items():
            amt = v.get("amount") if isinstance(v, dict) else v
            if not isinstance(amt, int) or amt < 0:
                yield bad("R19", f.name, f"sediment[{nid}]={v!r} 必须是非负整数")
        loaded[f.stem] = s

    # v1 / v2 语义等价：key 集合相同、amount 相等
    v1 = next((s for k, s in loaded.items() if "v1" in k), None)
    v2 = next((s for k, s in loaded.items() if "v2" in k), None)
    if v1 and v2:
        k1, k2 = set(v1.get("sediment") or {}), set(v2.get("sediment") or {})
        if k1 != k2:
            yield bad("R19", "v1→v2", f"sediment 的 key 集合变了：{sorted(k1 ^ k2)}")
        for nid in k1 & k2:
            a = v1["sediment"][nid]
            b = v2["sediment"][nid]
            b = b.get("amount") if isinstance(b, dict) else b
            if a != b:
                yield bad("R19", "v1→v2", f"sediment[{nid}] 语义不等价：{a} vs {b}")
        if v1.get("day") != v2.get("day") or v1.get("hour") != v2.get("hour"):
            yield bad("R19", "v1→v2", "时间字段在迁移中变了")


@rule("R20", "provenance：AI 资产必须有 model/provider/input_assets/date；approved 才要 reviewer", ["AI_LEDGER.json"])
def r20(ctx: Ctx):
    ledger = ctx.get("AI_LEDGER.json") or {}
    entries = ledger.get("entries", []) if isinstance(ledger, dict) else []
    need = ("model", "provider", "input_assets", "date")
    for e in entries:
        miss = [k for k in need if e.get(k) is None or e.get(k) == ""]
        if e.get("input_assets") is None:
            miss.append("input_assets")
        if miss:
            yield bad("R20", e.get("asset_id", "?"), f"provenance 缺字段：{sorted(set(miss))}")
        # 只有签核过的资产才必须有 reviewer，否则会逼人填假名字
        if e.get("approved_at") and not e.get("reviewer"):
            yield bad("R20", e.get("asset_id", "?"), "已签核但无 reviewer")


# ================================================================ R21-R25
# 美术侧人审 / 漂移 / 授权 / 背景 / 丧尸化派生


@rule("R21", "进 approved 必须有人眼签核（reviewer + approved_at）；generated 另需 provenance",
      ["art/asset-manifest.json", "AI_LEDGER.json"])
def r21(ctx: Ctx):
    """两个不同的闸，之前被我混成一个，结果两个都不管用：

      ① 人眼签核 —— 对**所有**资产成立。任何东西进 approved/ 都得有人署名。
      ② provenance —— 只对 source=generated 成立（AI 出图要能追到模型与提示）。

    历史教训：原来写成「source != generated 就 continue」，而项目里全是
    authoritative，于是这条规则从建库到第 11 轮一次都没开过火 ——
    一条从不触发的人审门，等于没有。
    """
    manifest = ctx.get("art/asset-manifest.json") or {}
    ledger = (ctx.get("AI_LEDGER.json") or {}).get("entries", []) if ctx.get("AI_LEDGER.json") else []
    ledger_ids = {e.get("asset_id") for e in ledger}
    for a in (manifest.get("assets", []) if isinstance(manifest, dict) else []):
        aid = a.get("asset_id", "?")
        if a.get("status") != "approved":
            if a.get("source") == "generated" and a.get("status") is None:
                yield warn("R21", aid, "generated 资产未声明 status（默认应 draft）")
            continue
        # ① 人眼签核：所有资产都要
        if not a.get("reviewer") or not a.get("approved_at"):
            yield bad("R21", aid, "进了 approved 但没有人眼签核（reviewer / approved_at 缺失）")
        # ② provenance：只有 AI 出的要
        if a.get("source") == "generated":
            if a.get("asset_id") not in ledger_ids:
                yield bad("R21", aid, "generated 资产进 approved 但 AI_LEDGER 里没有 provenance")
            if a.get("pixel_gate") not in ("pass", True):
                yield bad("R21", aid, "generated 资产未记录 pixel gate 通过")


@rule("R22", "漂移检查只报警，不得作为硬门禁", ["pipeline.json"])
def r22(ctx: Ctx):
    doc = ctx.get("pipeline.json") or {}
    for step in doc.get("steps", []) if isinstance(doc, dict) else []:
        name = str(step.get("name", "")).lower()
        if any(k in name for k in ("drift", "style", "consistency", "stylescope")) and step.get("gate") == "hard":
            yield bad("R22", step.get("name", "?"), "风格漂移被设成硬门禁（应用模型观感替代像素 diff）")


@rule("R23", "字体与参考图必须有 license/source/author/notice；外部商业截图禁入 input_refs",
      ["THIRD_PARTY_LICENSES.json", "art/asset-manifest.json"])
def r23(ctx: Ctx):
    lic = ctx.get("THIRD_PARTY_LICENSES.json") or {}
    for f in lic.get("fonts", []) if isinstance(lic, dict) else []:
        miss = [k for k in ("license", "source", "author", "notice_path") if not f.get(k)]
        if miss:
            yield bad("R23", f.get("name", "?"), f"字体缺授权字段：{miss}")
        notice = f.get("notice_path")
        if notice and not ctx.exists(notice):
            yield bad("R23", f.get("name", "?"), f"NOTICE 文件不存在：{notice}")
    manifest = ctx.get("art/asset-manifest.json") or {}
    for a in (manifest.get("assets", []) if isinstance(manifest, dict) else []):
        for ref in a.get("input_refs", []) or []:
            if isinstance(ref, dict) and ref.get("kind") == "external_commercial":
                yield bad("R23", a.get("asset_id", "?"), "外部商业游戏截图被用作训练 / style-reference 输入")


@rule("R24", "background_key 引用存在；视差层比例为整数倍", ["data/nodes.json", "art/asset-manifest.json"])
def r24(ctx: Ctx):
    manifest = ctx.get("art/asset-manifest.json") or {}
    keys = {a.get("asset_id") for a in (manifest.get("assets", []) if isinstance(manifest, dict) else [])}
    if not keys:
        yield warn("R24", "art/asset-manifest.json", "manifest 为空，background_key 无法核对")
    for n in nodes_of(ctx):
        if not n.get("background_key"):
            yield bad("R24", n.get("node_id", "?"), "缺 background_key（切镜头会黑屏）")
        for layer in n.get("parallax_layers") or []:
            ratio = layer.get("ratio")
            if not isinstance(ratio, (int, float)) or abs(ratio - round(ratio)) > 1e-9:
                yield bad("R24", n.get("node_id", "?"), f"视差比例 {ratio} 不是整数倍")


@rule("R25", "丧尸化派生：derived_from 真实存在；配件位语义与母体一致；只许末尾追加", ["art/asset-manifest.json"])
def r25(ctx: Ctx):
    man = ctx.get("art/asset-manifest.json") or {}
    assets = man.get("assets", []) if isinstance(man, dict) else []
    by_id = {a.get("asset_id"): a for a in assets}
    npcs = {n.get("npc_id"): n for n in ((ctx.get("data/npcs/npcs.json") or {}).get("npcs", []) or [])}
    found = False
    for a in assets:
        if a.get("category") != "zombie_variant":
            continue
        found = True
        aid = a.get("asset_id", "?")
        mother_key = a.get("derived_from")
        mother = by_id.get(mother_key) or npcs.get(mother_key)
        if mother is None:
            yield bad("R25", aid, f"derived_from='{mother_key}' 既不是 manifest 资产也不是真实 NPC")
            continue
        ms = norm_slots(mother.get("accessory_slots"))
        ds = norm_slots(a.get("accessory_slots"))
        if not ms:
            yield warn("R25", aid, "母体没有声明 accessory_slots，无法校验回响")
            continue
        if len(ds) < len(ms):
            yield bad("R25", aid, f"派生体配件位 {len(ds)} 个 < 母体 {len(ms)} 个（丢了配件 = 认不出是谁）")
        for i, (sem, name) in enumerate(ms):
            if i >= len(ds):
                break
            dsem, dname = ds[i]
            if sem is None or dsem is None:
                yield warn("R25", aid, f"第 {i} 位缺 semantic 标签，只验了位置不验语义")
                continue
            if dsem != sem:
                yield bad("R25", aid, f"第 {i} 位语义变了：母体 {sem} vs 派生 {dsem}（会被当成另一件装备）")
            elif dname == "empty":
                yield warn("R25", aid, f"第 {i} 位被显式置空（{sem}），回响会减弱")
            elif dname != name:
                yield bad("R25", aid, f"第 {i} 位换了东西：母体 {name} vs 派生 {dname}")
        if len(ds) > len(ms):
            for i in range(len(ms), len(ds)):
                if ds[i][0] is None:
                    yield bad("R25", aid, f"第 {i} 位是追加位但没有 semantic 标签")
    if not found:
        yield warn("R25", "art/asset-manifest.json", "manifest 里还没有 zombie_variant，派生规则未被验证")


# ================================================================ R26-R30
# v0.6 新增：卡池分层 / 进场点 / 噪声预算 / 安全屋失效 / 纵深不旁路


@rule("R26", "L 层卡不得出现任何模板专名", ["data/cards/layer_l.json", "data/lexicon.json"])
def r26(ctx: Ctx):
    lex = ctx.get("data/lexicon.json") or {}
    banned = set(lex.get("template_exclusive_names", []) or [])
    if not banned:
        yield warn("R26", "data/lexicon.json", "template_exclusive_names 为空，L 层复用性无法保护")
        return
    doc = ctx.get("data/cards/layer_l.json") or {}
    for card in doc.get("cards", []) if isinstance(doc, dict) else []:
        for text in walk_text(card):
            for name in banned:
                if name and name in text:
                    yield bad("R26", card.get("card_id", "?"), f"L 层卡出现模板专名 '{name}'（该卡无法跨模板复用）")


@rule("R27", "进场日 ∈ [0,14]，且 局内天数 = 世界收束日 − 进场日", ["data/templates/school.json", "data/world_calendar.json"])
def r27(ctx: Ctx):
    cal = ctx.get("data/world_calendar.json") or {}
    end = cal.get("end_day", 30)
    for rel in EXPECTED:
        if not rel.startswith("data/templates/"):
            continue
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        days = doc.get("entry_days") or []
        if not days:
            yield bad("R27", rel, "没有声明 entry_days")
        for d in days:
            if not isinstance(d, int) or not (0 <= d <= 14):
                yield bad("R27", rel, f"entry_day={d} 越界（允许 0–14）")
            if isinstance(d, int) and end - d <= 0:
                yield bad("R27", rel, f"entry_day={d} 导致局内天数为 0")


@rule("R28", "噪声预算自洽：总沉积 ≤ cap，且不超 70% 告警线", ["data/templates/school.json"])
def r28(ctx: Ctx):
    cal = ctx.get("data/world_calendar.json") or {}
    max_sens = max((f.get("noise_sensitivity", 1.0) for f in cal.get("keyframes", [])), default=1.0)
    for rel in EXPECTED:
        if not rel.startswith("data/templates/"):
            continue
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        budget = doc.get("noise_budget") or {}
        cap = budget.get("cap")
        if not isinstance(cap, (int, float)):
            yield bad("R28", rel, "缺 noise_budget.cap（世界会在某天前被打崩而无人知晓）")
            continue
        total = 0.0
        for wname, w in (doc.get("weapon_budget") or {}).items():
            rounds = w.get("rounds", 0) or 0
            per = w.get("sediment_per_shot", 0) or 0
            total += rounds * per * max_sens
        if total > cap:
            yield bad("R28", rel, f"总沉积 {total:.1f} > cap {cap}（枪会把世界提前打崩）")
        elif total > 0.7 * cap:
            yield warn("R28", rel, f"总沉积 {total:.1f} 已达 cap 的 {total / cap:.0%}，留给别的声音不多了")


@rule("R29", "每个模板必须有且仅有一次安全屋失效事件，且该卡真实存在",
      ["data/templates/school.json", "data/cards/layer_s_school.json"])
def r29(ctx: Ctx):
    seen: dict[str, str] = {}
    sdoc = ctx.get("data/cards/layer_s_school.json") or {}
    scards = sdoc.get("cards", sdoc) if isinstance(sdoc, dict) else sdoc
    sids = {c.get("card_id") for c in (scards or []) if isinstance(c, dict)}
    for rel in EXPECTED:
        if not rel.startswith("data/templates/"):
            continue
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        ev = doc.get("safehouse_failure")
        if not isinstance(ev, dict) or not ev.get("card_id"):
            yield bad("R29", rel, "没有声明 safehouse_failure（安全屋会变成暂停键）")
            continue
        if ev.get("trigger_once") is not True:
            yield bad("R29", rel, "safehouse_failure.trigger_once 必须为 true（只失效一次）")
        cid = ev["card_id"]
        if cid in seen:
            yield bad("R29", rel, f"安全屋失效事件 '{cid}' 与 {seen[cid]} 重复（会失效两次）")
        seen[cid] = rel
        # 每个模板都要有自己的 S 层文件，且 card_id 必须真实存在
        stem = Path(rel).stem
        srel = f"data/cards/layer_s_{stem}.json"
        if not ctx.exists(srel):
            yield bad("R29", rel, f"缺 {srel}（模板声明的失效事件没有对应卡）")
            continue
        sdoc = ctx.get(srel) or {}
        scards = sdoc.get("cards", sdoc) if isinstance(sdoc, dict) else sdoc
        ids = {c.get("card_id") for c in (scards or []) if isinstance(c, dict)}
        if cid not in ids:
            yield bad("R29", rel, f"safehouse_failure.card_id='{cid}' 不在 {srel} 里"
                                  f"（该文件有 {sorted(ids)}）")


@rule("R30", "房间不得旁路主轴（只许挂一段，且不许成为主轴断开的唯一桥）", ["data/nodes.json"])
def r30(ctx: Ctx):
    nodes = nodes_of(ctx)
    by_id = {n.get("node_id"): n for n in nodes}
    ax_ids = {n.get("node_id") for n in axis_nodes(nodes)}
    for n in room_nodes(nodes):
        nid = n.get("node_id")
        linked_axis = [by_id[i] for i in (n.get("linked_nodes") or []) if i in by_id and i in ax_ids]
        xs = {m.get("axis_x") for m in linked_axis}
        if len(xs) > 1:
            yield bad("R30", nid, f"房间连通了多个主轴段 {sorted(xs)} → 玩家可绕过主轴威胁")
        if not (n.get("tags") or []) and not n.get("loot_table"):
            yield warn("R30", nid, "房间既无 tags 又无 loot_table，可能是纯时间税房间")


# ================================================================ R31
# v0.6：归属标记限时（DEC-20261122-marker）


@rule("R31", "归属标记必须限时：3×5、Day3 褪尽、不允许常驻暖色", ["data/mode_profile.json"])
def r31(ctx: Ctx):
    mp = ctx.get("data/mode_profile.json") or {}
    story = (mp.get("story") or {}) if isinstance(mp, dict) else {}
    m = story.get("ui_ownership_marker")
    if not isinstance(m, dict):
        yield bad("R31", "mode_profile.story", "缺 ui_ownership_marker（归属标记会退回常驻暖点，污染暖色语义）")
        return
    if list(m.get("shape") or []) != [3, 5]:
        yield bad("R31", "ui_ownership_marker.shape", f"形状必须是 3×5，实际 {m.get('shape')}")
    fade = m.get("fade_day")
    if not isinstance(fade, int) or not (0 <= fade <= 14):
        yield bad("R31", "ui_ownership_marker.fade_day", f"fade_day={fade} 越界（必须落在世界日历内）")
    steps = m.get("palette_steps") or []
    if len(steps) != 5:
        yield bad("R31", "ui_ownership_marker.palette_steps", f"退级必须五档，实际 {len(steps)}")
    elif steps[-1] is not None:
        yield bad("R31", "ui_ownership_marker.palette_steps", "第五档必须为 null（Day4 起不再绘制）")
    if m.get("persistent") is True:
        yield bad("R31", "ui_ownership_marker", "常驻暖色会稀释「暖色 = 你在暴露自己」")


# ================================================================ R32
# v0.6：声音定位契约（DEC-20261122-audio）


@rule("R32", "音频只做定位：无音乐/无循环层；direction_cue 必须可定位；文件须单声道",
      ["data/audio/sounds.json"])
def r32(ctx: Ctx):
    doc = ctx.get("data/audio/sounds.json") or {}
    policy = doc.get("policy") or {}
    events = doc.get("events") or []
    cap = policy.get("max_events")
    if isinstance(cap, int) and len(events) > cap:
        yield bad("R32", "data/audio/sounds.json", f"事件数 {len(events)} 超上限 {cap}")
    for ev in events:
        eid = ev.get("event", "?")
        cat = ev.get("category")
        if cat in ("music", "ambience_loop"):
            yield bad("R32", eid, f"类目 '{cat}' 被 DEC-audio 明令禁止（7 人日只做定位）")
        if cat == "direction_cue":
            if ev.get("pan") is not True:
                yield bad("R32", eid, "direction_cue 必须 pan=true（否则听不出左右）")
            if ev.get("elevation") not in ("up", "level", "down"):
                yield bad("R32", eid, f"elevation={ev.get('elevation')} 非法（up/level/down）")
            if ev.get("distance_tier") not in ("near", "mid", "far"):
                yield bad("R32", eid, f"distance_tier={ev.get('distance_tier')} 非法（near/mid/far）")
        f = ev.get("file")
        if not f:
            continue
        p = ctx.p(f)
        if not p.exists():
            yield bad("R32", eid, f"文件不存在：{f}")
            continue
        ch = wav_channels(p)
        if ch is None:
            yield warn("R32", eid, f"无法从头部判定声道数：{f}")
        elif ch != 1:
            yield bad("R32", eid, f"声道数 {ch}，定位音必须单声道（双声道会被引擎当立体声，pan 不生效）")


# ================================================================ R33-R35
# v0.6：事件流依赖爆炸的三条硬约束（来源 PROP-aux-dependency-checklist，
# 编号顺延为 R33–R35，避开已占用的 R30/R31/R32）

VARS = ("trust", "reputation", "supplies", "control", "knowledge", "time")


def _depth(obj: Any) -> int:
    if isinstance(obj, dict):
        return 1 + max((_depth(v) for v in obj.values()), default=0)
    if isinstance(obj, list):
        return 1 + max((_depth(v) for v in obj), default=0)
    return 0


@rule("R33", "禁止卡间直接引用：effects / leftover / text 里不得出现别的 card_id",
      ["data/cards/layer_l.json"])
def r33(ctx: Ctx):
    doc = ctx.get("data/cards/layer_l.json") or {}
    cards = doc.get("cards", doc) if isinstance(doc, dict) else doc
    if not isinstance(cards, list):
        return
    ids = [c.get("card_id") for c in cards if isinstance(c, dict)]
    for c in cards:
        if not isinstance(c, dict):
            continue
        cid = c.get("card_id", "?")
        for field in ("effects", "leftover", "text", "trigger"):
            for s in walk_text(c.get(field)):
                for other in ids:
                    if other and other != cid and other in s:
                        yield bad("R33", cid, f"{field} 直接引用了另一张卡 '{other}'（应改为事件总线）")


@rule("R34", "单卡触发条件复杂度上限：trigger 嵌套 ≤ 3 层", ["data/cards/layer_l.json"])
def r34(ctx: Ctx):
    doc = ctx.get("data/cards/layer_l.json") or {}
    cards = doc.get("cards", doc) if isinstance(doc, dict) else doc
    if not isinstance(cards, list):
        return
    for c in cards:
        if not isinstance(c, dict):
            continue
        d = _depth(c.get("trigger") or {})
        if d > 3:
            yield bad("R34", c.get("card_id", "?"), f"trigger 嵌套 {d} 层 > 3（组合数开始爆炸）")


@rule("R35", "效果与触发只许触碰六组变量，不得引入新命名空间",
      ["data/cards/layer_l.json", "data/mode_profile.json"])
def r35(ctx: Ctx):
    doc = ctx.get("data/cards/layer_l.json") or {}
    cards = doc.get("cards", doc) if isinstance(doc, dict) else doc
    if not isinstance(cards, list):
        return
    for c in cards:
        if not isinstance(c, dict):
            continue
        cid = c.get("card_id", "?")
        for v in ((c.get("trigger") or {}).get("vars") or []):
            name = v.get("name") if isinstance(v, dict) else v
            if name not in VARS:
                yield bad("R35", cid, f"trigger 用了六组之外的变量 '{name}'")
        for eff in c.get("effects") or []:
            for k in (eff.get("vars") or {}):
                if k not in VARS:
                    yield bad("R35", cid, f"效果写入了六组之外的变量 '{k}'（禁止 world.* / global.* 副作用）")


# ================================================================ R36
# v0.6：记忆必须满格记录（降级是读取时算的，不是存储时抹的）

MEM_SLOTS = ("who", "what", "where", "manner", "outcome")


@rule("R36", "记忆必须满格记录：五槽齐全、fidelity 等于 trace 起点、trace 首日等于记录日",
      ["data/npcs/npcs.json"])
def r36(ctx: Ctx):
    npcs = (ctx.get("data/npcs/npcs.json") or {}).get("npcs", []) or []
    for npc in npcs:
        nid = npc.get("npc_id", "?")
        for m in npc.get("memories", []) or []:
            slots = m.get("slots") or {}
            miss = [k for k in MEM_SLOTS if not str(slots.get(k, "")).strip()]
            if miss:
                yield bad("R36", nid,
                          f"记忆 {m.get('source_event')} 缺槽 {miss} —— 只存了残影，精确版将无法渲染")
            trace = m.get("fidelity_trace") or []
            if not trace:
                yield bad("R36", nid, f"记忆 {m.get('source_event')} 没有 fidelity_trace（无法验证衰减）")
                continue
            if m.get("fidelity") != trace[0].get("fidelity"):
                yield bad("R36", nid,
                          f"记录 fidelity={m.get('fidelity')} 与 trace 起点 {trace[0].get('fidelity')} 不一致")
            if trace[0].get("day") != m.get("day"):
                yield warn("R36", nid,
                           f"trace 首日 {trace[0].get('day')} ≠ 记录日 {m.get('day')}")
            if m.get("fidelity") != 3:
                yield bad("R36", nid,
                          f"记录 fidelity 必须为 3（满格），实际 {m.get('fidelity')} —— 降级应在读取时算")


# ================================================================ R37
# v0.6：噪声必须是绝对整数单位（对齐 world_state.add_noise(node_id, base: int)）


@rule("R37", "噪声预算是绝对整数单位：sediment_per_shot / cap 必须为非负整数，且 total ≤ cap",
      ["data/templates/school.json"])
def r37(ctx: Ctx):
    for rel in EXPECTED:
        if not rel.startswith("data/templates/"):
            continue
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        total = 0
        for wname, w in (doc.get("weapon_budget") or {}).items():
            per = w.get("sediment_per_shot", 0)
            rounds = w.get("rounds", 0)
            if not isinstance(per, int) or isinstance(per, bool) or per < 0:
                yield bad("R37", rel, f"{wname}.sediment_per_shot={per!r} 必须是非负整数"
                                        f"（运行时签名是 int，小数会被截成 0 = 不发声）")
                per = 0
            if not isinstance(rounds, int) or isinstance(rounds, bool) or rounds < 0:
                yield bad("R37", rel, f"{wname}.rounds={rounds!r} 必须是非负整数")
                rounds = 0
            total += per * rounds
        cap = (doc.get("noise_budget") or {}).get("cap")
        if not isinstance(cap, int) or isinstance(cap, bool) or cap < 0:
            yield bad("R37", rel, f"noise_budget.cap={cap!r} 必须是非负整数")
        elif total > cap:
            yield bad("R37", rel, f"总沉积 {total} > cap {cap}（枪会把世界提前打崩）")


@rule("R38", "每个模板必须有安静选项（至少一件 sediment_per_shot ≤ 1 的武器）",
      ["data/templates/school.json"])
def r38(ctx: Ctx):
    for rel in EXPECTED:
        if not rel.startswith("data/templates/"):
            continue
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        wb = doc.get("weapon_budget") or {}
        if not wb:
            yield bad("R38", rel, "没有任何武器（玩家无手段可用）")
            continue
        quiet = [k for k, w in wb.items()
                 if isinstance(w.get("sediment_per_shot"), int)
                 and w.get("sediment_per_shot", 99) <= 1]
        if not quiet:
            yield bad("R38", rel, f"没有安静选项（全部 sediment_per_shot > 1）：{list(wb)}")


# ================================================================ R39
# v0.6：效果必须挂在真实的插槽选项上，否则永远不触发


@rule("R39", "effects[].when 必须逐字等于本卡某个 slot 的某个 option",
      ["data/cards/layer_l.json"])
def r39(ctx: Ctx):
    for rel in ("data/cards/layer_l.json", "data/cards/layer_s_school.json"):
        doc = ctx.get(rel)
        if doc is None:
            continue
        cards = doc.get("cards", doc) if isinstance(doc, dict) else doc
        if not isinstance(cards, list):
            continue
        for c in cards:
            if not isinstance(c, dict):
                continue
            cid = c.get("card_id", "?")
            opts: set[str] = set()
            for s in c.get("slots") or []:
                for o in (s.get("options") or []):
                    opts.add(str(o))
            for e in c.get("effects") or []:
                w = e.get("when")
                if w is None:
                    yield bad("R39", cid, "效果没有 when")
                elif str(w) not in opts:
                    yield bad("R39", cid,
                              f"when='{w}' 不对应任何 slot option（该效果永不触发）")


# ================================================================ R40
# v0.6：L2 渲染验收线 —— 模糊不等于可以补细节

# fidelity 档位 -> 该档位允许出现的槽
ALLOWED = {3: ("who", "what", "where", "manner", "outcome"),
           2: ("who", "what", "where"),
           1: ("who",),
           0: ()}


@rule("R40", "L2 渲染：不得出现该 fidelity 档位不允许的槽内容；fid=0 不得出现任何槽值",
      ["data/render_samples.json", "data/npcs/npcs.json"])
def r40(ctx: Ctx):
    doc = ctx.get("data/render_samples.json") or {}
    npcs = (ctx.get("data/npcs/npcs.json") or {}).get("npcs", []) or []
    npc = next((n for n in npcs if n.get("npc_id") == doc.get("source_npc")), None)
    if npc is None:
        yield bad("R40", "data/render_samples.json", "source_npc 在 npcs.json 里不存在")
        return
    mem = next((m for m in (npc.get("memories") or [])
                if m.get("source_event") == doc.get("source_event")), None)
    if mem is None:
        yield bad("R40", "data/render_samples.json", "source_event 在该 NPC 的记忆里不存在")
        return
    slots = {k: str(v) for k, v in (mem.get("slots") or {}).items() if v}
    trace = mem.get("fidelity_trace") or []

    def fid_at(day: int) -> int:
        cur = trace[0].get("fidelity", 3) if trace else mem.get("fidelity", 3)
        for t in trace:
            if t.get("day", 0) <= day:
                cur = t.get("fidelity", cur)
        return cur

    for s in doc.get("samples") or []:
        day = s.get("day")
        text = str(s.get("text", ""))
        real = fid_at(int(day))
        if s.get("expect_fidelity") != real:
            yield bad("R40", f"day {day}", f"expect_fidelity={s.get('expect_fidelity')} 与 trace 算出的 {real} 不一致")
        allowed = ALLOWED.get(real, ())
        for k, v in slots.items():
            if k in allowed:
                continue
            # 槽值里最具辨识度的片段（去掉通用字）
            probe = v
            for stop in ("player", "了", "的"):
                probe = probe.replace(stop, "")
            if len(probe) >= 2 and probe in text:
                yield bad("R40", f"day {day} fid={real}",
                          f"出现了本档不许有的 {k}「{probe}」——那是还没忘的东西")
        if real == 0:
            for k, v in slots.items():
                probe = v.replace("player", "")
                if len(probe) >= 2 and probe in text:
                    yield bad("R40", f"day {day}", f"fid=0 仍出现槽值 {k}「{probe}」")
        for term in doc.get("forbidden_in_render") or []:
            if term in text:
                yield bad("R40", f"day {day}",
                          f"出现了数据里没有的外貌/情绪描写「{term}」——渲染层自己补的事实")

    # 反例自检：doc 里声明的 reject_example 必须真的被上面那套检查拦住，
    # 否则这条规则就是在空转。
    rej = doc.get("reject_example") or {}
    if rej.get("text"):
        rtext = str(rej["text"])
        caught = any(t in rtext for t in (doc.get("forbidden_in_render") or []))
        if not caught:
            for k, v in slots.items():
                probe = v.replace("player", "").replace("了", "").replace("的", "")
                if len(probe) >= 2 and probe in rtext:
                    caught = True
                    break
        if not caught:
            yield bad("R40", "reject_example",
                      "声明的反例没有被任何检查拦住 —— R40 当前形同空转，必须补判据")


# ================================================================ R41
# v0.6：六个教学节拍必须存在、各一次、且相邻两拍之间别让玩家迷路


def _hops(by_id: dict[str, dict], a: str, b: str, limit: int = 8) -> int | None:
    if a == b:
        return 0
    seen = {a}
    frontier = [a]
    for d in range(1, limit + 1):
        nxt = []
        for cur in frontier:
            for v in (by_id.get(cur, {}).get("linked_nodes") or []):
                if v == b:
                    return d
                if v in by_id and v not in seen:
                    seen.add(v)
                    nxt.append(v)
        frontier = nxt
        if not frontier:
            break
    return None


@rule("R41", "六个教学节拍：各出现一次，且相邻两拍之间的最短路径 ≤ 3 跳", ["data/nodes.json"])
def r41(ctx: Ctx):
    nodes = nodes_of(ctx)
    by_id = {n.get("node_id"): n for n in nodes}
    beat: dict[str, str] = {}
    for n in nodes:
        for t in (n.get("tags") or []):
            if isinstance(t, str) and t.startswith("teaching_"):
                k = t.split("_")[-1]
                if k in beat:
                    yield bad("R41", n.get("node_id", "?"), f"{t} 同时出现在 {beat[k]} 和这里")
                beat[k] = n.get("node_id", "?")
    for i in range(1, 7):
        if str(i) not in beat:
            yield bad("R41", "data/nodes.json", f"缺 teaching_{i}（教学节拍断了）")
    for i in range(1, 6):
        a, b = beat.get(str(i)), beat.get(str(i + 1))
        if not a or not b:
            continue
        d = _hops(by_id, a, b)
        if d is None:
            yield bad("R41", f"teaching_{i}", f"{a} 走不到 {b}（下一拍不可达）")
        elif d > 3:
            yield warn("R41", f"teaching_{i}→{i + 1}",
                       f"{a} → {b} 需要 {d} 跳，玩家大概率会迷路")


# ================================================================ R42
# v0.6：把 aux 的「组合测试爆不爆」变成可测的量
#
# 第一版写错了两次，记在这里免得再犯：
#   ① 只按 day 统计「可触发卡数」，忽略节点维度 —— 于是每天都是 12 张，纯噪声。
#      真正该算的是 (day, node) 这一对，因为玩家同一时刻只站在一个节点上。
#   ② 统计「插槽名被几张卡共用」—— 概念就不对。插槽是**卡内私有**的，
#      两张卡都有 choice 不会互相干扰，根本没有全局插槽注册表。
#      这条已删除；aux 的清单假设了一个不存在的全局注册表。


def _cmp(cur: float, op: str, val: float) -> bool:
    return {"<=": cur <= val, ">=": cur >= val, "<": cur < val,
            ">": cur > val, "==": cur == val}.get(op, True)


def _trigger_ok(card: dict, day: int, node: dict | None, nominal: dict[str, float],
                sediment: int = 3) -> bool:
    t = card.get("trigger") or {}
    dw = t.get("day") or {}
    if not (dw.get("min", 0) <= day <= dw.get("max", 30)):
        return False
    for v in t.get("vars") or []:
        if not _cmp(nominal.get(v.get("name"), 0.5), v.get("op", "=="), v.get("value", 0)):
            return False
    if t.get("sediment_min") is not None and sediment < int(t["sediment_min"]):
        return False
    if node is not None:
        want = set(t.get("node_tags_any") or [])
        if want and not (want & set(node.get("tags") or [])):
            return False
        ids = set(t.get("node_ids") or [])
        if ids and node.get("node_id") not in ids:
            return False
    return True


def _acked(cards: list, cid: str) -> bool:
    for c in cards:
        if str(c.get("card_id")) == cid:
            return c.get("day_window_reviewed") is True
    return False


@rule("R42", "可触发组合规模 + 宽窗口卡必须显式签核", ["data/cards/layer_l.json"])
def r42(ctx: Ctx):
    doc = ctx.get("data/cards/layer_l.json") or {}
    cards = doc.get("cards", doc) if isinstance(doc, dict) else doc
    if not isinstance(cards, list) or not cards:
        return
    nodes = nodes_of(ctx)
    nominal = {v: 0.5 for v in VARS}

    total = 0
    per: list[tuple[int, str, int]] = []   # (组合数, id, 天数窗口)
    for c in cards:
        t = c.get("trigger") or {}
        dw = t.get("day") or {}
        width = int(dw.get("max", 30)) - int(dw.get("min", 0)) + 1
        n = 0
        for day in range(0, 31):
            for node in (nodes or [None]):
                if _trigger_ok(c, day, node, nominal):
                    n += 1
        total += n
        per.append((n, str(c.get("card_id")), width))

    # 判据：窗口 ≥25 天的卡，要么是「本来就任何一天都可能发生」（须显式 day_window_reviewed=true），
    # 要么就是条件没在筛选。**规则判断不了哪张是哪种，所以要求人签一次。**
    # 这是第三次改这条规则的口径，前两次都不对：
    #   ① 总组合数 ≤600 —— 对「地点无关卡」不公平，L 层本来就是跨地点的；
    #   ② 单卡窗口 ≥25 直接判坏 —— 夜遇本来就能发生在任何一晚。
    # 现在的写法把「判断」交回给人，规则只负责把没签过的点出来。
    for n, cid, width in sorted(per, reverse=True):
        if width >= 25 and not _acked(cards, cid):
            yield warn("R42", cid,
                       f"触发窗口 {width} 天且未签核 —— 要么收紧，要么加 day_window_reviewed: true")

    # 总量只报不判：它是规模指标，不是好坏指标
    if total > 2000:
        yield warn("R42", "data/cards/layer_l.json",
                   f"可触发组合 {total}（day×node）—— 规模已经大到没法穷举全量回归，"
                   f"回归要靠抽样 + 不变量")


# ================================================================ R43
# v0.6：NPC 卡声明的配件位，必须和它的精灵实际画出来的一致
#
# 在此之前没有任何东西连接「数据里的 npc.accessory_slots」和「manifest 里的精灵」。
# 结果是：NPC 卡说这个老师戴眼镜、精灵画成了面罩，而检查全绿 ——
# 等到丧尸化派生时才发现「熟人认不出」，那时候已经晚了。


@rule("R43", "有精灵的 NPC：manifest 里 accessory_slots 必须与 npcs.json 逐位一致",
      ["data/npcs/npcs.json", "art/asset-manifest.json"])
def r43(ctx: Ctx):
    npcs = {n.get("npc_id"): n for n in ((ctx.get("data/npcs/npcs.json") or {}).get("npcs", []) or [])}
    man = ctx.get("art/asset-manifest.json") or {}
    assets = man.get("assets", []) if isinstance(man, dict) else []
    checked = 0
    for a in assets:
        ref = a.get("npc_ref")
        if not ref:
            continue
        npc = npcs.get(ref)
        if npc is None:
            yield bad("R43", a.get("asset_id", "?"), f"npc_ref='{ref}' 在 npcs.json 里不存在")
            continue
        checked += 1
        want = norm_slots(npc.get("accessory_slots"))
        got = norm_slots(a.get("accessory_slots"))
        if len(want) != len(got):
            yield bad("R43", ref, f"配件位数量不一致：NPC 卡 {len(want)} vs 精灵 {len(got)}")
            continue
        for i, ((ws, wn), (gs, gn)) in enumerate(zip(want, got)):
            if ws != gs:
                yield bad("R43", ref, f"第 {i} 位语义不一致：卡 {ws} vs 精灵 {gs}")
            elif wn != gn:
                yield bad("R43", ref, f"第 {i} 位物件不一致：卡 {wn} vs 精灵 {gn}")
    if npcs and checked == 0:
        yield warn("R43", "art/asset-manifest.json",
                   f"有 {len(npcs)} 个 NPC 但没有任何精灵带 npc_ref —— 数据与美术还没接上")


def run(ctx: Ctx, only: set[str] | None = None) -> list[Finding]:
    out: list[Finding] = []
    for r in RULES:
        if only and r.rid not in only:
            continue
        missing = [x for x in r.requires if not ctx.exists(x)]
        if missing:
            out.append(Finding(r.rid, SKIP, ", ".join(missing), f"缺输入，暂不可判定（{r.title}）"))
            continue
        try:
            out.extend(r.fn(ctx))
        except Exception as exc:  # noqa: BLE001
            out.append(Finding(r.rid, ERROR, r.rid, f"规则内部异常：{type(exc).__name__}: {exc}"))
    return out


def inventory(ctx: Ctx) -> tuple[int, int]:
    present = sum(1 for rel in EXPECTED if ctx.exists(rel))
    total = len(EXPECTED)
    width = max(len(x) for x in EXPECTED)
    for rel, desc in EXPECTED.items():
        mark = "OK  " if ctx.exists(rel) else "MISS"
        print(f"[{mark}] {rel:<{width}}  {desc}")
    print(f"\n输入台账：{present}/{total} 就位")
    return present, total


# ================================================================ R44-R47
# 2026-11-24：D6。新加的四份数据（出行/结局/状态/战利品）此前完全没有规则覆盖，
# 写错了只有跑到游戏里才炸。下面四条把它们纳入同一套校验。

ENDING_CONDITION_KEYS = {
    "day_min", "companions_alive_min", "companions_alive_max", "companions_lost_min",
    "ammo_at_end", "requires_finale", "requires_item_any",
    "trust_min", "trust_max", "reputation_min", "reputation_max",
    "supplies_min", "supplies_max", "control_min", "control_max",
    "knowledge_min", "knowledge_max", "bond_min", "bond_max",
}
STATUS_PER_STAGE_KEYS = {"health_drain_per_hour", "speed_mult", "noise_mult"}
LOOT_EFFECT_KEYS = {
    "supplies", "health", "noise", "equip", "contaminate",
    "damage", "durability", "magazine", "ammo",
}


def _doc_list(doc: Any, key: str) -> list[dict]:
    if not isinstance(doc, dict):
        return []
    rows = doc.get(key)
    if not isinstance(rows, list):
        return []
    return [r for r in rows if isinstance(r, dict)]


@rule("R44", "出行层：5 栋楼 + 唯一安全屋 + 路线端点合法且不重复 + 一天一次")
def r44(ctx: Ctx):
    rel = "data/travel/routes.json"
    doc = ctx.get(rel)
    if not isinstance(doc, dict):
        return
    buildings = _doc_list(doc, "buildings")
    ids = [str(b.get("id", "")) for b in buildings]
    if len(ids) != 5 or len(set(ids)) != 5:
        yield bad("R44", rel, f"必须恰好 5 栋楼且 id 唯一，实际 {ids}")
    safehouses = [str(b.get("id")) for b in buildings if b.get("safehouse")]
    if safehouses != ["school"]:
        yield bad("R44", rel, f"安全屋必须且只能是 school，实际 {safehouses}")
    seen: set[tuple[str, str]] = set()
    for route in _doc_list(doc, "routes"):
        a, b = str(route.get("a", "")), str(route.get("b", ""))
        if a not in ids or b not in ids or a == b:
            yield bad("R44", rel, f"路线端点非法：{a}<->{b}")
            continue
        if (a, b) in seen:
            yield bad("R44", rel, f"路线重复声明：{a}<->{b}")
        seen.add((a, b))
        if int(route.get("cost", 0)) < 1:
            yield bad("R44", rel, f"{a}<->{b} 的 cost 必须 ≥1")
        if int(route.get("fuel", 0)) < 0:
            yield bad("R44", rel, f"{a}<->{b} 的 fuel 不能为负")
        if int(route.get("risk", 0)) < 1:
            yield bad("R44", rel, f"{a}<->{b} 的 risk 必须 ≥1")
    day = doc.get("day") or {}
    if int(day.get("actions_per_day", 0)) < 1:
        yield bad("R44", rel, "actions_per_day 必须 ≥1")
    hour = int(day.get("night_hour", -1))
    if not 0 <= hour <= 23:
        yield bad("R44", rel, f"night_hour 必须在 0..23，实际 {hour}")


@rule("R45", "结局：每模板恰好 4 条 + id/order 唯一 + 未解锁占位 + 条件键合法")
def r45(ctx: Ctx):
    folder = ctx.p("data/endings")
    if not folder.is_dir():
        return
    for path in sorted(folder.glob("*.json")):
        rel = f"data/endings/{path.name}"
        doc = ctx.get(rel)
        if not isinstance(doc, dict):
            continue
        template = str(doc.get("template", ""))
        if template != path.stem:
            yield bad("R45", rel, f"template={template} 与文件名 {path.stem} 不一致")
        rows = _doc_list(doc, "endings")
        if len(rows) != 4:
            yield bad("R45", rel, f"必须恰好 4 个结局，实际 {len(rows)}")
        ids = [str(r.get("id", "")) for r in rows]
        if len(set(ids)) != len(ids):
            yield bad("R45", rel, f"结局 id 重复：{ids}")
        orders = sorted(int(r.get("order", 0)) for r in rows)
        if orders != [1, 2, 3, 4]:
            yield bad("R45", rel, f"order 必须是 1..4，实际 {orders}")
        for row in rows:
            eid = str(row.get("id", ""))
            for field in ("label", "locked_label", "summary", "locked_summary", "grade"):
                if not str(row.get(field, "")).strip():
                    yield bad("R45", rel, f"{eid} 缺少 {field}")
            conditions = row.get("conditions")
            if not isinstance(conditions, dict) or not conditions:
                yield bad("R45", rel, f"{eid} 没有 conditions")
                continue
            for key in conditions:
                if key not in ENDING_CONDITION_KEYS:
                    yield bad("R45", rel, f"{eid} 的条件键 {key} 不被结局判定支持")


@rule("R46", "状态：4 条状态 + 阶段与倍率合法 + 对症药必须真实存在")
def r46(ctx: Ctx):
    rel = "data/systems/status.json"
    doc = ctx.get(rel)
    if not isinstance(doc, dict):
        return
    rows = _doc_list(doc, "statuses")
    if len(rows) != 4:
        yield bad("R46", rel, f"必须恰好 4 条状态，实际 {len(rows)}")
    items = ctx.get("data/loot/items.json") or {}
    known_items = {str(i.get("id", "")) for i in _doc_list(items, "items")}
    for row in rows:
        sid = str(row.get("id", ""))
        if int(row.get("max_stage", 0)) < 1:
            yield bad("R46", rel, f"{sid} 的 max_stage 必须 ≥1")
        per_stage = row.get("per_stage")
        if not isinstance(per_stage, dict):
            yield bad("R46", rel, f"{sid} 缺少 per_stage")
        else:
            for key in STATUS_PER_STAGE_KEYS:
                if key not in per_stage:
                    yield bad("R46", rel, f"{sid} 的 per_stage 缺少 {key}")
            speed = float(per_stage.get("speed_mult", 1.0))
            noise = float(per_stage.get("noise_mult", 1.0))
            if not 0.0 < speed <= 1.0:
                yield bad("R46", rel, f"{sid} 的 speed_mult 必须在 (0,1]，实际 {speed}")
            if noise < 1.0:
                yield bad("R46", rel, f"{sid} 的 noise_mult 必须 ≥1，实际 {noise}")
        cures = row.get("cure_items")
        if cures is not None and not isinstance(cures, list):
            yield bad("R46", rel, f"{sid} 的 cure_items 必须是数组")
        for item_id in (cures or []):
            if known_items and str(item_id) not in known_items:
                yield bad("R46", rel, f"{sid} 的对症药 {item_id} 不在 items.json 里")


@rule("R47", "战利品：容器档位存在 + 每建筑唯一高珍惜 + 池引用真实物品 + 效果键合法")
def r47(ctx: Ctx):
    rel = "data/loot/containers.json"
    doc = ctx.get(rel)
    items_doc = ctx.get("data/loot/items.json")
    if not isinstance(doc, dict):
        return
    items = _doc_list(items_doc, "items")
    item_ids = {str(i.get("id", "")) for i in items}
    tiers = doc.get("tiers") if isinstance(doc.get("tiers"), dict) else {}
    pools = doc.get("pools") if isinstance(doc.get("pools"), dict) else {}
    for tier_id, tier in tiers.items():
        if not isinstance(tier, dict):
            yield bad("R47", rel, f"档位 {tier_id} 不是对象")
            continue
        capacity = tier.get("capacity")
        if not (isinstance(capacity, list) and len(capacity) == 2 and 1 <= int(capacity[0]) <= int(capacity[1])):
            yield bad("R47", rel, f"档位 {tier_id} 的 capacity 必须是 [小,大] 且 ≥1")
        if int(tier.get("search_seconds", -1)) < 0:
            yield bad("R47", rel, f"档位 {tier_id} 的 search_seconds 不能为负")
        for pool_id in tier.get("pools", []):
            if str(pool_id) not in pools:
                yield bad("R47", rel, f"档位 {tier_id} 引用了不存在的池 {pool_id}")
    for pool_id, entries in pools.items():
        if not isinstance(entries, list) or not entries:
            yield bad("R47", rel, f"池 {pool_id} 为空")
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                yield bad("R47", rel, f"池 {pool_id} 里有非对象条目")
                continue
            item_id = str(entry.get("item", ""))
            if item_ids and item_id not in item_ids:
                yield bad("R47", rel, f"池 {pool_id} 引用了不存在的物品 {item_id}")
            if int(entry.get("weight", 0)) < 1:
                yield bad("R47", rel, f"池 {pool_id} 的 {item_id} 权重必须 ≥1")
    treasure_per_building: dict[str, int] = {}
    for row in _doc_list(doc, "containers"):
        cid = str(row.get("id", ""))
        tier_id = str(row.get("tier", ""))
        if tier_id not in tiers:
            yield bad("R47", rel, f"容器 {cid} 的档位 {tier_id} 不存在")
        if tier_id == "treasure":
            building = str(row.get("building", ""))
            treasure_per_building[building] = treasure_per_building.get(building, 0) + 1
        # ②-1：容器可以覆盖自己的搜索时长（秒）。写坏了就是「按下去立刻搜完」或「永远搜不完」。
        if "search_seconds" in row:
            try:
                own = float(row["search_seconds"])
            except (TypeError, ValueError):
                yield bad("R47", rel, f"容器 {cid} 的 search_seconds 不是数字")
                own = -1.0
            if own <= 0.0 or own > 10.0:
                yield bad("R47", rel, f"容器 {cid} 的 search_seconds 必须在 (0, 10] 秒内")
    for building, count in treasure_per_building.items():
        if count != 1:
            yield bad("R47", rel, f"建筑 {building} 有 {count} 个高珍惜容器，必须恰好 1 个")
    for row in items:
        iid = str(row.get("id", ""))
        for forbidden in ("tier", "rarity", "value", "grade", "price"):
            if forbidden in row:
                yield bad("R47", "data/loot/items.json", f"{iid} 的物品详情泄露了 {forbidden}")
        effect = row.get("effect")
        if effect is None:
            continue
        if not isinstance(effect, dict):
            yield bad("R47", "data/loot/items.json", f"{iid} 的 effect 不是对象")
            continue
        for key in effect:
            if key not in LOOT_EFFECT_KEYS:
                yield bad("R47", "data/loot/items.json", f"{iid} 的效果键 {key} 不合法")


@rule("R48", "校园图：区块在画布内 + id 唯一 + 楼有层数/入口 + route 覆盖可玩区块 + 开场拍子固定")
def r48(ctx: Ctx):
    """学校不再是「一间走廊换五套皮」，而是一整张校园图（data/campus/<id>.json）。

    这张图同时是开场旁白的略缩图、敌人与容器的分布表、以及线性叙事的顺序表；
    任何一项写错，玩家走的路就和图上画的不是一回事了，所以全部当硬错误。
    """
    import glob as _glob

    paths = sorted(_glob.glob(str(ctx.root / "data/campus" / "*.json")))
    if not paths:
        yield bad("R48", "data/campus/", "校园图目录为空（至少要有 school.json）")
        return
    required_ids = {
        "main_building", "west_wing", "grandstand", "track_field", "plaza",
        "dorm", "canteen", "corner_building", "gate", "parking",
    }
    for path in paths:
        import json as _json

        rel = f"data/campus/{Path(path).name}"
        try:
            doc = _json.loads(Path(path).read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001 - 报告原始解析失败信息
            yield bad("R48", rel, f"解析失败：{exc}")
            continue
        if not isinstance(doc, dict) or doc.get("schema") != "campus-map.v1":
            yield bad("R48", rel, "schema 必须是 campus-map.v1")
            continue
        canvas = doc.get("canvas")
        if not (isinstance(canvas, list) and len(canvas) == 2 and all(isinstance(v, (int, float)) for v in canvas)):
            yield bad("R48", rel, "canvas 必须是 [宽, 高]")
            canvas = [384, 216]
        width, height = float(canvas[0]), float(canvas[1])
        regions = _doc_list(doc, "regions")
        if len(regions) < len(required_ids):
            yield bad("R48", rel, f"区块只有 {len(regions)} 个，学校至少要 {len(required_ids)} 个")
        seen: set[str] = set()
        for row in regions:
            rid = str(row.get("id", ""))
            if not rid:
                yield bad("R48", rel, "区块缺 id")
                continue
            if rid in seen:
                yield bad("R48", rel, f"区块 id 重复：{rid}")
            seen.add(rid)
            rect = row.get("rect")
            if not (isinstance(rect, list) and len(rect) == 4):
                yield bad("R48", rel, f"{rid} 的 rect 必须是 [x, y, w, h]")
                continue
            x, y, w, h = (float(v) for v in rect)
            if w <= 0 or h <= 0:
                yield bad("R48", rel, f"{rid} 的 rect 宽高必须为正")
            if x < 0 or y < 0 or x + w > width or y + h > height:
                yield bad("R48", rel, f"{rid} 的 rect 出了画布 {width:g}x{height:g}")
            if row.get("kind") == "building":
                if int(row.get("floors", 0)) < 1:
                    yield bad("R48", rel, f"{rid} 是楼但没有层数")
                entrance = row.get("entrance")
                if not (isinstance(entrance, list) and len(entrance) == 2):
                    yield bad("R48", rel, f"{rid} 缺 entrance 点")
                else:
                    ex, ey = float(entrance[0]), float(entrance[1])
                    if not (x - 8 <= ex <= x + w + 8 and y - 8 <= ey <= y + h + 8):
                        yield bad("R48", rel, f"{rid} 的入口不在楼体边缘（{ex:g},{ey:g}）")
        missing = sorted(required_ids - seen)
        if missing:
            yield bad("R48", rel, "学校图缺这些区块：" + "、".join(missing))

        route = doc.get("route")
        if not (isinstance(route, list) and len(route) >= 6):
            yield bad("R48", rel, "route 至少要串起 6 个区块（线性叙事要有路）")
            route = []
        for stop in route:
            if str(stop) not in seen:
                yield bad("R48", rel, f"route 指向不存在的区块：{stop}")
        safehouse = str(doc.get("safehouse", ""))
        if safehouse not in seen:
            yield bad("R48", rel, f"safehouse 不是区块：{safehouse}")
        elif route and str(route[0]) != safehouse:
            yield bad("R48", rel, f"route 必须从安全屋出发，实际是 {route[0]}")

        slots = _doc_list(doc, "enemy_slots")
        if len(slots) < 4:
            yield bad("R48", rel, f"敌人只分布在 {len(slots)} 个区块，太少（要 ≥4）")
        for slot in slots:
            region = str(slot.get("region", ""))
            if region not in seen:
                yield bad("R48", rel, f"敌人挂在未知区块：{region}")
            if int(slot.get("count", 0)) < 1:
                yield bad("R48", rel, f"{region} 的敌人数量必须 ≥1")

        intro = doc.get("intro") if isinstance(doc.get("intro"), dict) else {}
        beats = intro.get("beats") if isinstance(intro.get("beats"), list) else []
        expected = ["bell", "overview", "toilet", "alarm", "zoom", "walkout"]
        if [str(b.get("id", "")) for b in beats] != expected:
            got = "、".join(str(b.get("id", "")) for b in beats)
            yield bad("R48", rel, f"开场拍子必须是 {'→'.join(expected)}，实际 {got}")
        for beat in beats:
            if float(beat.get("seconds", 0)) <= 0:
                yield bad("R48", rel, f"开场拍子 {beat.get('id', '')} 缺时长")
            if not (isinstance(beat.get("lines"), list) and beat.get("lines")):
                yield bad("R48", rel, f"开场拍子 {beat.get('id', '')} 缺旁白")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="残余信号 校验器 R01-R30")
    ap.add_argument("--root", default=".", help="仓库根目录（默认当前目录）")
    ap.add_argument("--inventory", action="store_true", help="只报输入台账")
    ap.add_argument("--json", action="store_true", help="机器可读输出")
    ap.add_argument("--only", default="", help="只跑指定规则，逗号分隔，如 R26,R29")
    args = ap.parse_args(argv)

    ctx = Ctx(Path(args.root).resolve())

    if args.inventory:
        inventory(ctx)
        return 0

    only = {x.strip().upper() for x in args.only.split(",") if x.strip()} or None
    findings = run(ctx, only)

    if args.json:
        print(json.dumps([f.__dict__ for f in findings], ensure_ascii=False, indent=2))
    else:
        buckets: dict[str, list[Finding]] = {ERROR: [], WARN: [], SKIP: []}
        for f in findings:
            buckets[f.level].append(f)
        for level in (ERROR, WARN, SKIP):
            for f in buckets[level]:
                print(f"{level:<5} {f.rule:<4} {f.path}  —  {f.msg}")
        print(
            f"\n共 {len(RULES)} 条规则："
            f"ERROR {len(buckets[ERROR])} · WARN {len(buckets[WARN])} · SKIP {len(buckets[SKIP])}"
        )
        if ctx.load_errors:
            print("\n解析错误：")
            for k, v in ctx.load_errors.items():
                print(f"  {k}: {v}")

    return 1 if any(f.level == ERROR for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
