#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""收紧过宽的触发条件（R42）

问题：几张卡的 trigger 只写「day 1–30 + 某个变量 > 0」，在标称状态下等于**不筛选**，
      任何一天任何节点都可能触发。R42 把它量化成「可触发组合 = 480」，正好是
      30 天 × 16 节点的全开。

做法：显式表，一张卡一条，写清「它该在哪种节点 / 什么时段 / 需要谁在场」。
      这是设计判断，不该由启发式或模型代劳。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CARDS = ROOT / "data" / "cards" / "layer_l.json"

# card_id -> 要覆盖的 trigger 片段
TIGHTEN: dict[str, dict] = {
    # 门外有人在拍门 —— 只可能发生在有门的地方
    "l_lock_them_out": {
        "day": {"min": 2, "max": 30},
        "vars": [{"name": "supplies", "op": "<=", "value": 0.7}],
        "node_tags_any": ["shelter", "clue_possible"],
        "sediment_min": 0,
    },
    # 同行的人受伤了 —— 必须真有人跟着你
    "l_wounded_companion": {
        "day": {"min": 3, "max": 22},
        "vars": [{"name": "trust", "op": ">=", "value": 0.2}],
        "sediment_min": 1,
        "requires_npc_alive": True,
    },
    # 有人把旧事记错了 —— 得先有「旧」，还得有人还记得
    "l_memory_slip": {
        "day": {"min": 10, "max": 30},
        "vars": [{"name": "knowledge", "op": ">=", "value": 0.3}],
        "sediment_min": 1,
        "requires_npc_alive": True,
    },
    # 断电后第一夜 —— 名字就写死了时间
    "l_first_dark_night": {
        "day": {"min": 3, "max": 4},
        "vars": [{"name": "supplies", "op": "<=", "value": 0.7}],
        "node_tags_any": ["shelter"],
        "sediment_min": 0,
    },
    # 检查站传闻 —— Day 14 检查站撤走，之后没人再传
    "l_checkpoint_rumor": {
        "day": {"min": 1, "max": 14},
        "vars": [{"name": "knowledge", "op": ">=", "value": 0.2}],
        "node_tags_any": ["clue_possible", "clue_endpoint"],
        "sediment_min": 0,
    },
    # 尸群过境 —— Day 0 还没有尸群，Day 5 起街上才成群
    "l_horde_passing": {
        "day": {"min": 5, "max": 30},
        "vars": [{"name": "supplies", "op": "<=", "value": 0.8}],
        "sediment_min": 2,
    },
    # 水源争夺 —— Day 3 才停水
    "l_water_quarrel": {
        "day": {"min": 3, "max": 30},
        "vars": [{"name": "supplies", "op": "<=", "value": 0.6}],
        "node_tags_any": ["shelter", "clue_possible"],
        "sediment_min": 0,
    },
}

# 本来就该「任何一天都可能发生」的卡：显式签核，而不是硬改窄
ACK_WIDE_WINDOW = [
    "l_night_encounter",     # 夜遇 —— 哪一晚都可能有人从阴影里出来
    "l_knock_three_times",   # 敲门 —— 不挑日子
    "l_search_noise",        # 搜刮噪音 —— 只要你翻东西就会响
    "l_someone_lied",        # 有人撒谎 —— 不挑日子
    "l_stranger_trade",      # 换东西 —— 不挑日子
    "l_lock_them_out",       # 门外拍门 —— 任何一晚都可能有
    "l_horde_passing",       # 尸群过境 —— Day 5 起任何一天都可能，沉积决定它在哪
    "l_water_quarrel",       # 水源争夺 —— 停水后任何一天，只要有两个人
]


def main() -> int:
    doc = json.loads(CARDS.read_text(encoding="utf-8"))
    n = 0
    for c in doc.get("cards", []):
        cid = c.get("card_id")
        if cid in TIGHTEN:
            old = json.dumps(c.get("trigger"), ensure_ascii=False)
            c["trigger"] = TIGHTEN[cid]
            print(f"[OK] {cid}\n     旧: {old}\n     新: {json.dumps(c['trigger'], ensure_ascii=False)}")
            n += 1
        elif cid not in TIGHTEN and cid in {"l_stranger_trade"}:
            print(f"[--] {cid} 未在表内，保持原样")
        if cid in ACK_WIDE_WINDOW:
            c["day_window_reviewed"] = True
            print(f"[ACK] {cid} 标记为「本来就任何一天都可能发生」")
    CARDS.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n收紧 {n} 张，签核 {len(ACK_WIDE_WINDOW)} 张")
    return 0


if __name__ == "__main__":
    sys.exit(main())
