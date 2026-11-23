#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 nodes.json 打成一张 ASCII 拓扑图

存在的理由（DEC-20261123-D1 的附加条件）：选了「不引入地图编辑器」之后，
最大的代价是**看不见布局**。改一个坐标要改 JSON → 跑脚本 → 起游戏。

这张图把它压回「一眼能看」。它不是编辑器，是**只读**的 —— 一旦它能写
nodes.json，它就变成第二个权威，C 方案的前提当场消失。

用法：
    python tools/nodes_map.py
    python tools/nodes_map.py --template school
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

MARK = {
    "axis": "══",
    "shelter": "🔒",   # lockable
    "clue": "？",
    "audio": "♪",
    "power": "⚡",
    "noise": "▲",
    "room": "▢",
    "teach": "①",
}


def tag_of(n: dict) -> str:
    tags = set(n.get("tags") or [])
    if n.get("lockable"):
        return "🔒"
    for k, t in (("teaching", None),):
        pass
    for t in tags:
        if t.startswith("teaching_"):
            return t.replace("teaching_", "")[-1] + " "
    if "audio_source" in tags:
        return "♪ "
    if "power_node" in tags:
        return "⚡"
    if "noise_sink" in tags:
        return "▲ "
    if "clue_endpoint" in tags:
        return "？ "
    return "▢ " if n.get("role") == "room" else "══"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=str(ROOT / "data" / "nodes.json"))
    args = ap.parse_args(argv)

    doc = json.loads(Path(args.file).read_text(encoding="utf-8"))
    nodes = doc.get("nodes", doc) if isinstance(doc, dict) else doc

    depths = sorted({n.get("depth_layer", 0) for n in nodes}, reverse=True)
    xs = sorted({n.get("axis_x", 0) for n in nodes})

    print(f"《残余信号》节点拓扑 · {len(nodes)} 个节点 · 主轴 x={xs[0]}..{xs[-1]}")
    print(f"图例：══ 主轴  ▢ 房间  🔒 安全屋  ♪ 音频源  ⚡ 配电  ▲ 噪声汇  ？线索端点  ①–⑥ 教学节拍")
    print()

    cell_w = 12
    header = "depth".ljust(8) + "".join(f"x={x}".center(cell_w) for x in xs)
    print(header)
    print("─" * len(header))

    for d in depths:
        row = f"{d:+d}".ljust(8)
        for x in xs:
            here = [n for n in nodes if n.get("depth_layer") == d and n.get("axis_x") == x]
            if not here:
                row += "·".center(cell_w)
                continue
            marks = "".join(tag_of(n) for n in here)
            order = sorted(here, key=lambda n: (n.get("role") != "axis", n.get("node_id", "")))
            short = ",".join(order[i].get("node_id", "")[7:][:5] for i in range(len(order)))
            row += (marks.strip() + " " + short)[:cell_w].ljust(cell_w)
        print(row)

    print()
    print("链接（只列房间 → 主轴，主轴之间的链省略）：")
    for n in sorted(nodes, key=lambda n: n.get("node_id", "")):
        if n.get("role") != "room":
            continue
        links = [x for x in (n.get("linked_nodes") or [])]
        print(f"  {n.get('node_id'):<26} → {', '.join(links)}")

    axis = [n for n in nodes if n.get("role") == "axis"]
    print(f"\n主轴 {len(axis)} 段 · 房间 {len(nodes) - len(axis)} 间 · "
          f"安全屋 {sum(1 for n in nodes if n.get('lockable'))} 个 · "
          f"教学节拍 {sum(1 for n in nodes if any(str(t).startswith('teaching_') for t in (n.get('tags') or [])))} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
