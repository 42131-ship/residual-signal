#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把模型交的 NPC 批次归一成 canonical 形状

模型交的形状经常不对，但内容是对的。硬退回去重生成，既浪费又可能更差。
所以：**工具负责归一化，规则负责验。** 归一化不了的才退回。

已见的四种偏差（都在这处理）：
  ① accessories:[{semantic,item}]      → accessory_slots:[{id,semantic,name}]
  ② 缺 kind / via / hops / last_recalled_day / provenance_lock  → 补默认值
  ③ memory 被拆成两个对象（一个只有 slots，一个只有 fidelity） → 合并
  ④ 末尾挂着 </|json> 之类的垃圾                                     → 剥掉

用法：
    python tools/normalize_npcs.py --batch design/prompts/_npcs4.json --out data/npcs/_npcs4_clean.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass


def load_tolerant(text: str) -> dict:
    """模型常在 JSON 前后挂东西：前缀一句「我先核对…」、尾部一个 `</|json>`。
    raw_decode 只能处理尾部；前缀得先切掉。"""
    text = text.strip()
    # 切掉第一个 { 之前的任何文字（模型爱先汇报一遍思路）
    brace = text.find("{")
    if brace > 0:
        prefix = text[:brace].strip()
        if prefix:
            print(f"[宽容] 丢弃前缀 {len(prefix)} 字：{prefix[:40]!r}", file=sys.stderr)
        text = text[brace:]
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        try:
            obj, end = json.JSONDecoder().raw_decode(text)
            print(f"[宽容] 尾部有 {len(text) - end} 个多余字符，已忽略", file=sys.stderr)
            return obj
        except json.JSONDecodeError:
            pass
        # 括号不平衡时，截到最后一个人物之前并补闭合 —— 能救几个算几个
        cut = text.rfind('{"npc_id"', 0, exc.pos)
        if cut > 0:
            salvaged = text[:cut].rstrip().rstrip(",") + "]}" if '"npcs":[' in text[:cut] else None
            if salvaged:
                try:
                    obj = json.loads(salvaged)
                    print(f"[抢救] 第 {exc.pos} 字符处括号不平衡，丢弃最后一个对象后解析成功",
                          file=sys.stderr)
                    return obj
                except json.JSONDecodeError:
                    pass
        raise


def norm_slots(raw) -> list[dict]:
    out = []
    for i, s in enumerate(raw or []):
        if not isinstance(s, dict):
            continue
        out.append({
            "id": i,
            "semantic": s.get("semantic"),
            "name": s.get("name") or s.get("item") or s.get("slot"),
        })
    return out


def merge_memories(mems: list) -> list[dict]:
    """把「只有 slots」和「只有 fidelity」的碎片合并成一条。"""
    merged: list[dict] = []
    pending: dict | None = None
    for m in mems or []:
        if not isinstance(m, dict):
            continue
        if "slots" in m:
            if pending:
                merged.append(pending)
            pending = dict(m)
        elif pending is not None and "fidelity" in m:
            pending.update({k: v for k, v in m.items() if k not in pending})
        else:
            merged.append(dict(m))
    if pending:
        merged.append(pending)
    return merged


def norm_npc(n: dict) -> dict:
    mems = []
    for m in merge_memories(n.get("memories") or []):
        m.setdefault("kind", "direct")
        m.setdefault("via", None)
        m.setdefault("provenance_lock", True)
        m.setdefault("affect", 0.0)
        m.setdefault("last_recalled_day", m.get("day", 0))
        if "hops" in m and m["hops"] is None:
            m.pop("hops")
        mems.append(m)
    return {
        "npc_id": n.get("npc_id"),
        "display_role": n.get("display_role"),
        "scope": n.get("scope", "shared"),
        "role_slot": n.get("role_slot"),
        "accessory_slots": norm_slots(n.get("accessory_slots") or n.get("accessories")),
        "affinity": float(n.get("affinity", 0.0)),
        "alive": bool(n.get("alive", True)),
        "infected": bool(n.get("infected", False)),
        "grief": float(n.get("grief", 0.0)),
        "memories": mems,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    doc = load_tolerant(Path(args.batch).read_text(encoding="utf-8"))
    npcs = doc.get("npcs", doc) if isinstance(doc, dict) else doc
    out = {"npcs": [norm_npc(n) for n in npcs if isinstance(n, dict)]}
    Path(args.out).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    for n in out["npcs"]:
        print(f"{n['npc_id']:<10} {n['scope']:<7} slots={len(n['accessory_slots'])} "
              f"mem={len(n['memories'])} "
              f"fid={[m.get('fidelity') for m in n['memories']]}")
    print(f"\n归一 {len(out['npcs'])} 个 → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
