#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""人眼签核：把 draft 资产移进 approved（R21 的正门）

这是唯一一个「规则不能替代」的动作。R14 只查技术合规 —— 一张解剖畸形的
角色图可以完美通过像素门禁。R21 问的是另一件事：**有没有人真的看过。**

用法：
    python tools/sign_assets.py --reviewer YG --ids chr_student_idle_r_00 tl_corridor_full_20
    python tools/sign_assets.py --reviewer YG --ids <id> --note "blockout，仅验证流程"
    python tools/sign_assets.py --list      # 看哪些还在 draft
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "art" / "asset-manifest.json"

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reviewer", default="YG")
    ap.add_argument("--ids", nargs="*", default=[])
    ap.add_argument("--note", default="")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)

    man = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assets = man["assets"]

    if args.list:
        for a in assets:
            print(f"{a['status']:<9} {a['asset_id']:<34} {a.get('category','')}")
        print(f"\n共 {len(assets)} 条，approved {sum(1 for a in assets if a['status'] == 'approved')}")
        return 0

    if not args.ids:
        print("没给 --ids")
        return 2

    by_id = {a["asset_id"]: a for a in assets}
    today = time.strftime("%Y-%m-%d")
    signed, missing = [], []
    for aid in args.ids:
        a = by_id.get(aid)
        if a is None:
            missing.append(aid)
            continue
        a["status"] = "approved"
        a["reviewer"] = args.reviewer
        a["approved_at"] = today
        if args.note:
            a["review_note"] = args.note
        signed.append(aid)
        print(f"[签名] {aid}  {a.get('category')}  reviewer={args.reviewer}  {today}")

    if missing:
        print(f"[找不到] {missing}")
    MANIFEST.write_text(json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n签了 {len(signed)} 条；approved 共 {sum(1 for a in assets if a['status'] == 'approved')} 条")
    if args.note:
        print(f"备注：{args.note}")
    return 0 if signed else 1


if __name__ == "__main__":
    sys.exit(main())
