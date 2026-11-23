#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把一批新条目合并进已有数据文件（按 id 去重）

常驻队列里「扩充内容」会反复发生：卡从 8 到 12，NPC 从 3 到 8。
每次都手写合并脚本既慢又容易覆盖掉旧数据，所以固化成一个工具。

用法：
    python tools/append_batch.py --batch design/prompts/_cards4.json --target data/cards/layer_l.json \
        --key cards --id card_id
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="合并一批条目")
    ap.add_argument("--batch", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--key", required=True, help="数组所在的键，如 cards / npcs")
    ap.add_argument("--id", required=True, dest="id_field", help="唯一键，如 card_id / npc_id")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    batch = json.loads(Path(args.batch).read_text(encoding="utf-8"))
    new = batch.get(args.key) if isinstance(batch, dict) else batch
    if not isinstance(new, list):
        print(f"批次里没有数组 '{args.key}'")
        return 1

    tpath = Path(args.target)
    target = json.loads(tpath.read_text(encoding="utf-8"))
    if isinstance(target, list):
        target = {args.key: target}
    arr = target.setdefault(args.key, [])

    have = {str(x.get(args.id_field)) for x in arr if isinstance(x, dict)}
    added, skipped = [], []
    for item in new:
        if not isinstance(item, dict):
            continue
        key = str(item.get(args.id_field))
        if key in have:
            skipped.append(key)
            continue
        arr.append(item)
        have.add(key)
        added.append(key)

    print(f"新增 {len(added)}：{added}")
    if skipped:
        print(f"跳过（已存在）{len(skipped)}：{skipped}")
    if args.dry_run:
        print("(dry-run，未写入)")
        return 0
    tpath.write_text(json.dumps(target, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"写入 {tpath}，共 {len(arr)} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
