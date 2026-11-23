#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 effects[].when 对到真实的插槽选项上（R39）

为什么要有这张显式映射表，而不是让模型改：
    这是「结构保持型改写」——只能动一个字段、别的一个字都不许改。
    模型交过两次：一次空结果，一次会顺手把 slots 也改了。
    这类活必须人（或显式表）来定，改完由 R39 机械验证。

映射规则：把描述句对到同卡里语义最近的 option 原文。
新增条目只需在下面加一行，然后重跑本脚本。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (文件, card_id, 旧 when) -> 新 when（必须逐字等于某个 slot option）
MAPPING: dict[tuple[str, str, str], str] = {
    ("layer_l", "l_night_encounter", "停下并给出所求"): "停下",
    ("layer_l", "l_night_encounter", "不停下"): "继续走",
    ("layer_l", "l_checkpoint_rumor", "相信并转向"): "相信传闻",
    ("layer_l", "l_checkpoint_rumor", "停下查证"): "先查证",
    ("layer_s_school", "school_transmission_office_breach", "触发"): "重新锁门",
}

FILES = {"layer_l": "data/cards/layer_l.json", "layer_s_school": "data/cards/layer_s_school.json"}


def main() -> int:
    changed = 0
    for key, new_when in MAPPING.items():
        tag, cid, old_when = key
        p = ROOT / FILES[tag]
        doc = json.loads(p.read_text(encoding="utf-8"))
        hit = False
        for c in doc.get("cards", []):
            if c.get("card_id") != cid:
                continue
            opts = {str(o) for s in c.get("slots") or [] for o in (s.get("options") or [])}
            if new_when not in opts:
                print(f"[SKIP] {cid}: '{new_when}' 不是该卡的 option，先不加")
                continue
            for e in c.get("effects") or []:
                if e.get("when") == old_when:
                    e["when"] = new_when
                    hit = True
                    changed += 1
                    print(f"[OK]   {cid}: '{old_when}' -> '{new_when}'")
        if hit:
            p.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n改了 {changed} 条效果")
    return 0


if __name__ == "__main__":
    sys.exit(main())
