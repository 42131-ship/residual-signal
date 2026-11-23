#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 data/loot/*.json 生成 design/LOOT.md（唯一真源是 JSON，文档不手抄物品表）。

用法: python tools/build_loot_doc.py
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ITEMS = ROOT / "data" / "loot" / "items.json"
CONTAINERS = ROOT / "data" / "loot" / "containers.json"
OUT = ROOT / "design" / "LOOT.md"

CATEGORY_LABELS = {
    "food": "食物饮水",
    "medical": "医疗",
    "tool": "工具",
    "weapon": "武器",
    "utility": "杂项用品",
    "intel": "线索情报",
    "junk": "垃圾 / 恶趣味",
}

HEADER = """# 物资与容器系统 · v1

> 真源：`data/loot/items.json`（玩家可见物品详情）+ `data/loot/containers.json`（容器档位、分池、随机规则）。
> 本文件由 `python tools/build_loot_doc.py` 生成，改数据后重跑，不要手改表格。

## 一、剧情模式规则（2026-11-23 拍板）

1. **容器搜过一次就永久为空**：不管过多少世界日都不刷新。用掉的物资永远没了，所以每一次「用不用、什么时候用」都会引发连锁反应。
2. **每栋建筑只有一个高珍惜容器**：学校 = 急救柜（校医上锁柜）。枪械等最高价值物品只会出现在这里。
3. **容器越珍贵，装的东西越多、开启越慢**：件数按档位区间随机；具体物品按档位分池随机。
4. **数量和种类都不固定**：同一天同一个柜子，每次开出来的件数与物品都不同（确定性随机，见下）。
5. **玩家可见的物品详情不写价值/稀有度**：`items.json` 只有名称、类别、作用、使用方式；物品值不值钱、属于哪一档，只能靠玩家自己判断。

## 二、容器珍惜度表

| 档位 | 容量（随机区间） | 开启时间 | 抽取池 | 保底 |
|---|---|---|---|---|"""

POOLS_NOTE = """
> 容量 = 档位 `capacity` 区间内均匀随机；`search_seconds` 是该档容器的开启时间，
> 档位越高开得越慢、容量越大。物品稀有度只体现在「它属于哪个抽取池」，
> 不存在 `items.json` 里——玩家看不到。
"""

CONTAINER_NOTE = """
每个建筑只允许一个 `treasure` 容器（`LootService` 加载时会校验；多过一个直接拒绝加载）。
学校的另一个容器（储物柜）是最低档，只会出日用品。
"""

POOL_RARITY = {
    "household": "常见：水、饼干、电池、打火机、纸笔等，能活但没惊喜",
    "junk": "低价值：食物残渣、恶趣味道具、垃圾，偶尔能恶心人",
    "medical": "标准：绷带、消毒、止痛药，伤口处理主力",
    "tools": "标准：胶带、螺丝刀、绳子、撬棍、菜刀等工具",
    "valuable": "较高：抗生素、急救包、地图、钥匙、供电设备",
    "firearm": "最高：枪械与子弹，只出现在高珍惜容器",
    "high_value": "最高保底池：枪械/信号棒/鞭炮/关键药品，高珍惜容器保底一件",
}

FOOTER = """
## 六、随机与回放

- 随机种子 = `hash(容器 id | 世界日 | 盐 | 档位)`，同一组输入永远得到同一批物资，方便回放与测试。
- 剧情模式不按世界日刷新，所以「世界日」只影响同一容器在不同天的假设场景（测试用），实际游戏里搜过就是搜过。
- 门禁：`game/tests/loot.gd` 验证剧情模式不刷新、容量随机、枪械只在高珍惜容器、确定性；
  `game/tests/corridor_loot.gd` 验证面板流程与「已经搜过一次 / 剧情模式不会刷新」文案。

## 七、使用效果（背包已接）

物品的 `effect` 字段是机器可读效果（`tools/apply_item_effects.py` 写入）：

| 字段 | 含义 |
|---|---|
| `supplies` | 使用后物资变化（0..1） |
| `health` | 使用后体力/伤势变化（0..1） |
| `noise` | 使用后产生的噪声等级 |
| `equip` | `melee` / `firearm`，装备武器（不消耗） |
| `contaminate` | 使用有风险（当前只记录，等状态系统） |

- 背包容量 10；`Tab` 打开，`W/S` 选择，`E` 使用，`Q` 丢弃，`Tab/Esc/V` 关闭。
- 没有 `effect` 的物品就是「现在用不上」：使用只提示、不消耗。
- 武器目前只做「装备 + 左键挥击（占位，无敌人）」，耐久/弹匣/命中判定还没接。

## 八、还没接的东西（下一轮）

1. **角色状态细化**：伤口/流血/感染/中毒/成瘾等状态还没有，effect 里的 `contaminate` 先只记录。
2. **搜索耗时**：`search_seconds` 目前只是数据，还没有「按住 E 搜索 N 秒」的交互。
3. **战斗**：左键只是挥击占位，没有敌人、命中、耐久、弹匣。
4. **`data/loot/items.json` / `containers.json` 还没进 validate.py 的规则与输入台账**。
"""


def _effect_text(effect: dict) -> str:
    if not effect:
        return "—"
    parts: list[str] = []
    if "supplies" in effect:
        parts.append(f"物资 {float(effect['supplies']) * 100:+.0f}%")
    if "health" in effect:
        parts.append(f"体力 {float(effect['health']) * 100:+.0f}%")
    if "noise" in effect:
        parts.append(f"噪声 +{int(effect['noise'])}")
    if "equip" in effect:
        parts.append("装备·" + ("近战" if effect["equip"] == "melee" else "枪械"))
    if effect.get("contaminate"):
        parts.append("有风险")
    return "、".join(parts) if parts else "—"


def load() -> tuple[dict, dict]:
    items = json.loads(ITEMS.read_text(encoding="utf-8"))
    containers = json.loads(CONTAINERS.read_text(encoding="utf-8"))
    return items, containers


def build() -> str:
    items, containers = load()
    lines: list[str] = [HEADER]
    tiers = containers.get("tiers", {})
    for tier_id, tier in tiers.items():
        pools = "、".join(tier.get("pools", []))
        guaranteed = str(tier.get("guaranteed", "") or "—")
        capacity = tier.get("capacity", [1, 1])
        lines.append(
            f"| {tier.get('label', tier_id)} (`{tier_id}`) | {capacity[0]}–{capacity[1]} 件 | "
            f"{tier.get('search_seconds', 0)} 秒 | {pools} | {guaranteed} |"
        )
    lines.append(POOLS_NOTE)

    lines.append("\n## 三、容器实例表\n")
    lines.append("| 容器 | 建筑 | 房间 | 档位 | 说明 |")
    lines.append("|---|---|---|---|---|")
    for container in containers.get("containers", []):
        tier_id = container.get("tier", "")
        note = container.get("note", "")
        lines.append(
            f"| {container.get('label', '')} (`{container.get('id', '')}`) | "
            f"{container.get('building', '')} | {container.get('room', '-')} | "
            f"{tiers.get(tier_id, {}).get('label', tier_id)} | {note} |"
        )
    lines.append(CONTAINER_NOTE)

    pools = containers.get("pools", {})
    item_names = {entry["id"]: entry["name"] for entry in items.get("items", [])}
    lines.append("\n## 四、抽取池（内部稀有度表，玩家不可见）\n")
    lines.append("| 池 | 意图 | 物品数 | 例子 |")
    lines.append("|---|---|---|---|")
    for pool_id, entries in pools.items():
        names = [item_names.get(entry.get("item", ""), "?") for entry in entries[:6]]
        lines.append(
            f"| `{pool_id}` | {POOL_RARITY.get(pool_id, '')} | {len(entries)} | {'、'.join(names)}… |"
        )

    lines.append("\n## 五、物品详情表（玩家可见，不含价值/稀有度）\n")
    by_category: dict[str, list[dict]] = {}
    for entry in items.get("items", []):
        by_category.setdefault(entry.get("category", "junk"), []).append(entry)
    for category in ["food", "medical", "tool", "weapon", "utility", "intel", "junk"]:
        entries = by_category.get(category, [])
        if not entries:
            continue
        lines.append(f"### {CATEGORY_LABELS.get(category, category)}（{len(entries)} 件）\n")
        lines.append("| 物品 | 作用 | 使用方式 | 效果 |")
        lines.append("|---|---|---|---|")
        for entry in entries:
            lines.append(
                f"| {entry.get('name', '')} | {entry.get('description', '')} | "
                f"{entry.get('usage', '')} | {_effect_text(entry.get('effect', {}))} |"
            )
        lines.append("")

    lines.append(FOOTER)
    return "\n".join(lines)


def main() -> int:
    OUT.write_text(build(), encoding="utf-8")
    items = json.loads(ITEMS.read_text(encoding="utf-8"))["items"]
    print(f"{OUT}  物品 {len(items)} 件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
