#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给 data/loot/items.json 的消耗品/医疗/武器补上机器可读的 effect 字段。

effect 约定（游戏侧只认这些）：
  supplies : float  使用后物资变化（消耗品）
  health   : float  使用后体力/伤势变化（医疗）
  noise    : int    使用后产生的噪声等级（会吸引注意）
  equip    : "melee" | "firearm"  装备武器（不消耗）
contaminate : true  使用会带来风险（暂时只记录，供后续状态系统）
无 effect 的物品 = 现在用不上（可以丢）。

只加 effect，不动 description/usage；稀有度/价值仍然不进这张表。

用法: python tools/apply_item_effects.py
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ITEMS = ROOT / "data" / "loot" / "items.json"

EFFECTS: dict[str, dict] = {
    # 食物与饮水（supplies）
    "bottled_water": {"supplies": 0.08},
    "canned_food": {"supplies": 0.10},
    "biscuits": {"supplies": 0.06},
    "instant_noodles": {"supplies": 0.09},
    "chocolate": {"supplies": 0.04},
    "expired_milk": {"supplies": 0.03, "contaminate": True},
    "dog_food": {"supplies": 0.05},
    "beer": {"supplies": 0.02},
    "liquor": {"supplies": 0.01, "contaminate": True},
    "energy_drink": {"supplies": 0.05},
    "coffee": {"supplies": 0.02},
    "gum": {"supplies": 0.01},
    "candy": {"supplies": 0.02},
    # 医疗（health）
    "bandage": {"health": 0.10},
    "painkillers": {"health": 0.05, "contaminate": True},
    "antibiotics": {"health": 0.20},
    "alcohol_wipes": {"health": 0.05},
    "disinfectant": {"health": 0.05},
    "iodine": {"health": 0.08},
    "burn_cream": {"health": 0.06},
    "cold_pack": {"health": 0.04},
    "hot_pack": {"health": 0.02},
    "vitamins": {"health": 0.03},
    "splint": {"health": 0.10},
    "tourniquet": {"health": 0.15, "contaminate": True},
    "first_aid_kit": {"health": 0.35},
    "iv_bag": {"health": 0.20},
    "syringe": {"health": 0.05, "contaminate": True},
    "sleeping_pills": {"health": 0.02, "contaminate": True},
    # 制造噪声（noise）
    "whistle": {"noise": 2},
    "flare": {"noise": 2},
    "firecracker": {"noise": 3},
    # 武器（equip，不消耗）
    "crowbar": {"equip": "melee"},
    "kitchen_knife": {"equip": "melee"},
    "scissors": {"equip": "melee"},
    "screwdriver": {"equip": "melee"},
    "hammer": {"equip": "melee"},
    "box_cutter": {"equip": "melee"},
    "dildo_bat": {"equip": "melee"},
    "pistol": {"equip": "firearm"},
    "rifle": {"equip": "firearm"},
}


def main() -> int:
    data = json.loads(ITEMS.read_text(encoding="utf-8"))
    applied = 0
    for entry in data.get("items", []):
        effect = EFFECTS.get(entry["id"])
        if effect is None:
            entry.pop("effect", None)
            continue
        entry["effect"] = effect
        applied += 1
    ITEMS.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{ITEMS}  effect {applied} 件 / 共 {len(data.get('items', []))} 件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
