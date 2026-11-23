#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把模板的噪声预算规范成绝对整数单位

背景：`world_state.add_noise(node_id, base: int)` 收 int。
数据里若写 0.02，运行时截断成 0 —— 撬棍等于不发声，而且没人会发现。

规则（显式映射，不按名字猜）：
    响器（手枪 / 步枪 / 霰弹枪 / 猎枪）= 3
    静器（撬棍 / 消防斧 / 手术剪）= 1
    cap = ceil(total / 0.6)，落在 R28 的 70% 告警线以内

用法：python tools/normalize_weapons.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "data" / "templates"

LOUD = {"手枪", "步枪", "霰弹枪", "猎枪"}
QUIET = {"撬棍", "消防斧", "手术剪", "撬棒", "军刺"}
# 没有安静选项的模板，补一件
ENSURE_QUIET = {
    "gas_station": {"撬棍": {"rounds": 6}},
    # 军人不可能只有一把枪：没有安静手段的模板等于逼玩家只会开火
    "military_base": {"军刺": {"rounds": 10}},
}


def main() -> int:
    bad = 0
    for p in sorted(TEMPLATES.glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        wb = d.setdefault("weapon_budget", {})
        name = d.get("template_id", p.stem)
        for extra, spec in (ENSURE_QUIET.get(name) or {}).items():
            if extra not in wb:
                wb[extra] = dict(spec)
        total = 0
        for k, w in wb.items():
            if k in LOUD:
                per = 3
            elif k in QUIET:
                per = 1
            else:
                print(f"  !! {name}/{k} 不在映射表里，按安静处理（请人工确认）")
                per = 1
                bad += 1
            r = int(w.get("rounds", 0) or 0)
            w["rounds"] = r
            w["sediment_per_shot"] = per
            total += per * r
        cap = max(2, math.ceil(total / 0.6)) if total else 2
        d.setdefault("noise_budget", {})["cap"] = cap
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
        detail = ", ".join(f"{k}({v['rounds']}×{v['sediment_per_shot']})" for k, v in wb.items())
        print(f"{name:14s} total={total:3d} cap={cap:3d} util={total / cap:4.0%}  {detail}")
    print(f"\n未识别武器 {bad} 个")
    return 0


if __name__ == "__main__":
    sys.exit(main())
