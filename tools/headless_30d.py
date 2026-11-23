#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""无头 30 天全量回放（数据层语义镜像）

为什么要有这个东西：
    `validate.py` 的 43 条规则是**静态**的 —— 它只能查「字段对不对」。
    它查不出「第 17 天，一个 fidelity=1 的 NPC 用两跳传闻触发某张卡之后，
    世界变量会不会越界」。那类问题只能跑起来才知道。

它不是什么：
    **它不是 GDScript 的替代品。** 这是 Python 镜像，验的是**数据语义自洽**，
    不是 Godot 运行时。GDScript 仍未编译（P1 卡在没装 Godot）。
    镜像和真实现会漂移 —— 所以它只断言「不变量」，不比对逐帧数值。

跑法：
    python tools/headless_30d.py            # 一次固定种子
    python tools/headless_30d.py --seeds 5  # 五个种子
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VARS = ("trust", "reputation", "supplies", "control", "knowledge", "time")
ALLOWED = {3: ("who", "what", "where", "manner", "outcome"),
           2: ("who", "what", "where"),
           1: ("who",),
           0: ()}

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def J(rel: str):
    p = ROOT / rel
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


class World:
    def __init__(self, cal, nodes, cards, npcs):
        self.cal = cal
        self.nodes = {n["node_id"]: n for n in nodes}
        self.node_list = nodes
        self.cards = sorted(cards, key=lambda c: c["card_id"])
        self.npcs = npcs
        self.day = 0
        self.hour = 8
        self.vars = {v: 0.5 for v in VARS}
        self.sediment: dict[str, int] = {n["node_id"]: 0 for n in nodes}
        self.fired: list[str] = []
        self.last_fired: dict[str, int] = {}
        self.covered: set[tuple[str, str]] = set()
        self.l0: list[dict] = []
        self.violations: list[str] = []

    # ---- 日历
    def cal_at(self, day: int) -> dict:
        frames = self.cal["keyframes"]
        cur = frames[0]
        for f in frames:
            if f["day"] <= day:
                cur = f
        return cur

    def sens(self, night: bool) -> float:
        f = self.cal_at(self.day)
        s = float(f.get("noise_sensitivity", 0.5))
        return s * 1.5 if night else s

    # ---- 变量
    def add_var(self, name: str, delta: float) -> None:
        if name not in VARS:
            self.violations.append(f"写入六组之外的变量 {name}")
            return
        old = self.vars[name]
        self.vars[name] = max(0.0, min(1.0, old + delta))
        if not (0.0 <= self.vars[name] <= 1.0):
            self.violations.append(f"{name} 越界 {self.vars[name]}")

    # ---- 时间
    def spend(self, hours: int) -> None:
        if hours <= 0:
            self.violations.append(f"spend_time({hours}) 非法")
            return
        self.hour += hours
        while self.hour >= 24:
            self.hour -= 24
            self.day += 1
            self.vars["time"] = min(1.0, self.day / 30.0)
            if self.day > 30:
                self.violations.append("世界日越过收束日 30")

    # ---- 噪声
    def noise(self, node_id: str, base: int, night: bool = False) -> dict:
        delta = max(1, int(round(base * self.sens(night))))
        self.sediment[node_id] = self.sediment.get(node_id, 0) + delta
        out = {"self": delta, "neighbors": {}}
        for nb in self.nodes[node_id].get("linked_nodes") or []:
            if nb in self.sediment:
                d2 = max(1, delta // 2)
                self.sediment[nb] += d2
                out["neighbors"][nb] = d2
        return out

    # ---- 卡
    def eligible(self, node_id: str) -> list[dict]:
        node = self.nodes[node_id]
        out = []
        for c in self.cards:
            cid = str(c.get("card_id"))
            # returns_after_days 之前从没被实现过 —— 标着「只发生一次」的卡会天天触发
            ret = c.get("returns_after_days")
            if cid in self.last_fired:
                if ret == 0:
                    continue
                if ret is not None and self.day - self.last_fired[cid] < int(ret):
                    continue
            t = c.get("trigger") or {}
            dw = t.get("day") or {}
            if not (dw.get("min", 0) <= self.day <= dw.get("max", 30)):
                continue
            ok = True
            for v in t.get("vars") or []:
                cur = self.vars.get(v.get("name"), 0.0)
                op, val = v.get("op"), v.get("value", 0)
                if not {"<=": cur <= val, ">=": cur >= val, "<": cur < val,
                        ">": cur > val, "==": cur == val}.get(op, True):
                    ok = False
                    break
            if not ok:
                continue
            if t.get("sediment_min") is not None and self.sediment[node_id] < int(t["sediment_min"]):
                continue
            want = set(t.get("node_tags_any") or [])
            if want and not (want & set(node.get("tags") or [])):
                continue
            ids = set(t.get("node_ids") or [])
            if ids and node_id not in ids:
                continue
            if t.get("requires_npc_alive") and not any(n.get("alive") for n in self.npcs):
                continue
            out.append(c)
        return out

    def fire(self, card: dict, policy: str) -> list[dict]:
        """policy: "first" / "last" —— 玩家会做选择，不会随机选。
        随机选会让大部分 effect 永远不执行，那样跑出来的世界是死的。"""
        bind = {}
        for s in card.get("slots") or []:
            opts = s.get("options") or []
            if opts:
                bind[str(s.get("slot"))] = str(opts[0] if policy == "first" else opts[-1])
        entries = []
        for e in card.get("effects") or []:
            if str(e.get("when")) not in bind.values():
                continue
            for k, v in (e.get("vars") or {}).items():
                self.add_var(k, float(v))
            entries.append({"event_id": e.get("evidence"), "card_id": card.get("card_id"),
                            "day": self.day, "bind": dict(bind)})
        self.l0.extend(entries)
        self.fired.append(str(card.get("card_id")))
        self.last_fired[str(card.get("card_id"))] = self.day
        # 覆盖统计：这张卡的哪些 when 真的被走到了
        for e in card.get("effects") or []:
            if str(e.get("when")) in bind.values():
                self.covered.add((str(card.get("card_id")), str(e.get("when"))))
        return entries


# ---------------------------------------------------------------- 记忆渲染


def fidelity_at(mem: dict, day: int) -> int:
    trace = mem.get("fidelity_trace") or []
    cur = trace[0].get("fidelity", 3) if trace else mem.get("fidelity", 3)
    for t in trace:
        if t.get("day", 0) <= day:
            cur = t.get("fidelity", cur)
    return cur


def render(mem: dict, day: int) -> str:
    f = fidelity_at(mem, day)
    s = mem.get("slots") or {}
    if f == 3:
        return f"{s.get('who','有人')}{s.get('manner','')}{s.get('what','')}，{s.get('where','')}，{s.get('outcome','')}"
    if f == 2:
        return f"{s.get('who','有人')}在{s.get('where','')}{s.get('what','')}"
    if f == 1:
        return f"{s.get('who','有人')}给过东西"
    return "有人帮过我" if float(mem.get("affect", 0)) >= 0 else "有人拿走过什么"


# ---------------------------------------------------------------- 一局


def run_one(seed: int, cal, nodes, cards, npcs, verbose: bool, policy: str = "first") -> list[str]:
    rng = random.Random(seed)
    w = World(cal, nodes, cards, npcs)
    axis = sorted([n for n in nodes if n.get("role") == "axis"], key=lambda n: n["axis_x"])
    pos = 0
    peak_sed = 0
    guard = 0

    # 跑到世界收束日：一次循环 11 小时，所以 30 天要跑 ~65 个循环
    while w.day < 30 and guard < 200:
        guard += 1
        w.spend(1)
        pos = min(len(axis) - 1, pos + rng.choice([0, 1]))
        node = axis[pos]["node_id"]
        w.spend(2)
        w.noise(node, rng.randint(1, 3), night=w.hour >= 19)
        cands = w.eligible(node)
        if cands:
            w.fire(cands[0], policy)
        w.spend(8)
        peak_sed = max(peak_sed, max(w.sediment.values()))

    # ---- 不变量
    for v, val in w.vars.items():
        if not (0.0 <= val <= 1.0):
            w.violations.append(f"终局 {v}={val} 越界")
    if any(x < 0 for x in w.sediment.values()):
        w.violations.append("出现负沉积（沉积只增不减）")
    l0_ok = all("event_id" in e and e["event_id"] for e in w.l0)
    if not l0_ok:
        w.violations.append("有 L0 条目缺 event_id")
    if w.day < 30:
        w.violations.append(f"30 个循环后世界只到 Day {w.day}，时间推进没起作用")

    # 记忆渲染不得越档
    for npc in npcs:
        for mem in npc.get("memories") or []:
            for day in range(0, 31, 3):
                txt = render(mem, day)
                f = fidelity_at(mem, day)
                allowed = ALLOWED.get(f, ())
                for k, val in (mem.get("slots") or {}).items():
                    if k in allowed:
                        continue
                    probe = str(val).replace("player", "").replace("了", "")
                    if len(probe) >= 2 and probe in txt:
                        w.violations.append(
                            f"{npc['npc_id']} Day {day} fid={f} 渲染里漏出了 {k}「{probe}」")

    if verbose:
        print(f"  seed={seed} policy={policy}  ended Day {w.day} hour {w.hour}  "
              f"卡触发 {len(w.fired)} 次 / {len(set(w.fired))} 张不同  "
              f"L0 {len(w.l0)} 条  沉积峰值 {peak_sed}")
        print(f"          vars: " + " ".join(f"{k}={v:.2f}" for k, v in w.vars.items()))
    return w.violations


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=1)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    cal = J("data/world_calendar.json")
    nodes_doc = J("data/nodes.json")
    nodes = nodes_doc.get("nodes", nodes_doc) if isinstance(nodes_doc, dict) else nodes_doc
    cards_doc = J("data/cards/layer_l.json")
    cards = cards_doc.get("cards", cards_doc) if isinstance(cards_doc, dict) else cards_doc
    npcs_doc = J("data/npcs/npcs.json")
    npcs = (npcs_doc or {}).get("npcs", [])

    if not (cal and nodes and cards):
        print("缺数据：world_calendar / nodes / cards")
        return 2

    print(f"数据：{len(nodes)} 节点 / {len(cards)} 张 L 卡 / {len(npcs)} 个 NPC")
    total = []
    covered: set[tuple[str, str]] = set()
    fired_cards: set[str] = set()
    for i in range(args.seeds):
        for policy in ("first", "last"):
            v = run_one(1000 + i, cal, nodes, cards, npcs, verbose=not args.quiet, policy=policy)
            total.extend(v)

    # 效果覆盖：跑两遍（first/last）都没走到的 when，说明这条效果在真玩时也很难出现
    w = World(cal, nodes, cards, npcs)
    all_effects = {(str(c.get("card_id")), str(e.get("when")))
                   for c in cards for e in (c.get("effects") or [])}
    for i in range(args.seeds):
        for policy in ("first", "last"):
            rng = random.Random(1000 + i)
            ww = World(cal, nodes, cards, npcs)
            axis = sorted([n for n in nodes if n.get("role") == "axis"], key=lambda n: n["axis_x"])
            pos = 0
            guard = 0
            while ww.day < 30 and guard < 200:
                guard += 1
                ww.spend(1)
                pos = min(len(axis) - 1, pos + rng.choice([0, 1]))
                node = axis[pos]["node_id"]
                ww.spend(2)
                ww.noise(node, rng.randint(1, 3), night=ww.hour >= 19)
                cands = ww.eligible(node)
                if cands:
                    ww.fire(cands[0], policy)
                ww.spend(8)
            covered |= ww.covered
            fired_cards |= set(ww.fired)

    if total:
        print(f"\n不变量违反 {len(total)} 条：")
        for x in total[:20]:
            print(f"  ✗ {x}")
        return 1
    print(f"\n不变量全部成立（{args.seeds} 个种子 × 2 种选择策略 × 到 Day 30）")
    print(f"卡覆盖：{len(fired_cards)}/{len(cards)} 张被触发过")
    miss_card = [c.get("card_id") for c in cards if str(c.get("card_id")) not in fired_cards]
    if miss_card:
        print(f"  从未触发：{miss_card}")
    miss_fx = sorted(all_effects - covered)
    print(f"效果覆盖：{len(covered)}/{len(all_effects)}")
    if miss_fx:
        print(f"  从未走到的 when：{miss_fx[:8]}")
    print("注意：这是 Python 镜像，验的是数据语义自洽，不是 GDScript 能编译。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
