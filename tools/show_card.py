#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""看一张卡（或一个 NPC）的关键字段，省得每次都去翻大 JSON

用法：
    python tools/show_card.py --file data/cards/layer_l.json --key cards --id l_lock_them_out
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--id", required=False, dest="want")
    ap.add_argument("--field", default="trigger")
    args = ap.parse_args(argv)

    doc = json.loads(Path(args.file).read_text(encoding="utf-8"))
    arr = doc.get(args.key, doc) if isinstance(doc, dict) else doc
    for item in arr:
        if args.want and item.get("card_id") != args.want and item.get("npc_id") != args.want:
            continue
        ident = item.get("card_id") or item.get("npc_id")
        print(f"## {ident}")
        print(json.dumps(item.get(args.field), ensure_ascii=False, indent=2))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
