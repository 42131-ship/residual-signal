#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 NPC 的配件位从代码同步进 npcs.json（R43 的另一半）

为什么是「从代码同步到数据」而不是「两边各写一份」：
    配件位有两个消费者 —— 精灵构造器（画什么）和 NPC 状态卡（认人靠什么）。
    两份手写必然漂移。R43 只能事后抓，抓完还得人来补。
    所以让 char_build.NPC_KINDS 当唯一真源，这个脚本把它写进数据。

用法：
    python tools/sync_npc_slots.py           # 同步
    python tools/sync_npc_slots.py --check   # 只报差异，不写
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import char_build as CB  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
NPCS = ROOT / "data" / "npcs" / "npcs.json"

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)

    doc = json.loads(NPCS.read_text(encoding="utf-8"))
    changed = 0
    for npc in doc.get("npcs", []):
        nid = npc.get("npc_id")
        if nid not in CB.NPC_KINDS:
            continue
        _, names = CB.NPC_KINDS[nid]
        want = CB.slots_of(names)
        if npc.get("accessory_slots") == want:
            print(f"[ok]  {nid}")
            continue
        old = npc.get("accessory_slots")
        print(f"[{'diff' if args.check else 'fix'}] {nid}")
        print(f"      旧: {json.dumps(old, ensure_ascii=False)}")
        print(f"      新: {json.dumps(want, ensure_ascii=False)}")
        npc["accessory_slots"] = want
        changed += 1

    if args.check:
        print(f"\n{changed} 个不一致")
        return 1 if changed else 0
    NPCS.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n同步 {changed} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
