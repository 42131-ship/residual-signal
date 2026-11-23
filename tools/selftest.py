#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验器自测：造一个「故意违规」的迷你仓库，断言每条规则都能开火。

一个永远返回 SKIP 的校验器是没被验证过的校验器。这个脚本的作用是：
    python tools/selftest.py     → 全绿才算 R01-R30 真的能抓东西

它同时是 CI 的守门测试：以后改规则，先跑这个。
"""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import validate as V  # noqa: E402

FIXTURE: dict[str, object] = {
    # ---- 日历：故意让 loot 在 day 12 上跳 0.4（R10 应开火）
    "data/world_calendar.json": {
        "end_day": 30,
        "keyframes": [
            {"day": 0, "loot": 1.0, "noise_sensitivity": 0.2},
            {"day": 4, "loot": 0.5, "noise_sensitivity": 0.4},
            {"day": 12, "loot": 0.9, "noise_sensitivity": 0.9},
        ],
    },
    "data/lexicon.json": {
        "node_names": [
            "school_corridor_a",
            "school_corridor_b",
            "school_corridor_c",
            "school_f1_guard",
            "school_f2_broadcast",
        ],
        "template_exclusive_names": ["广播室", "食堂冷库"],
        "tags": ["spawn", "power_node"],
        "loot_tables": ["food"],
        "noise_events": ["door_creak_02"],
        "proper_nouns": [],
    },
    # ---- 节点：axis 0,1,3（缺口→R02）；sediment=2（R07）；
    #      power_node 灯是 on（R09）；纵深层旁路 a 与 c（R30）；缺 background_key（R24）
    "data/nodes.json": {
        "template": "school",
        "nodes": [
            {
                "node_id": "school_corridor_a", "axis_x": 0, "depth_layer": 0, "segment": "a",
                "lockable": False, "sediment": 0, "loot_table": "food", "light": "on",
                "linked_nodes": ["school_corridor_b", "school_f2_broadcast"],
                "tags": ["spawn"], "background_key": "bg_corridor",
                "parallax_layers": [{"ratio": 1}],
            },
            {
                "node_id": "school_corridor_b", "axis_x": 1, "depth_layer": 0, "segment": "b",
                "lockable": False, "sediment": 2, "loot_table": "food", "light": "on",
                "linked_nodes": ["school_corridor_a", "school_corridor_c", "school_f1_guard"],
                "tags": [], "background_key": "bg_corridor",
            },
            {
                "node_id": "school_corridor_c", "axis_x": 3, "depth_layer": 0, "segment": "c",
                "lockable": False, "sediment": 0, "loot_table": "food", "light": "on",
                "linked_nodes": ["school_corridor_b", "school_f2_broadcast"],
                "tags": ["power_node"], "background_key": "bg_corridor",
                "noise_events": ["door_creak_02"],
            },
            {
                "node_id": "school_f1_guard", "axis_x": 1, "depth_layer": 1, "segment": "b",
                "lockable": True, "sediment": 0, "loot_table": "food", "light": "off",
                "linked_nodes": ["school_corridor_b"], "tags": [], "background_key": "bg_room",
            },
            {
                "node_id": "school_f2_broadcast", "axis_x": 0, "depth_layer": 1, "segment": "b",
                "lockable": False, "sediment": 0, "loot_table": "food", "light": "off",
                "linked_nodes": ["school_corridor_a", "school_corridor_c"], "tags": [],
            },
        ],
    },
    # ---- 模板：entry_days 含 20（R27）；噪声超 cap（R28）；无 safehouse_failure（R29）；
    #      私改 timeline（R18）
    "data/templates/school.json": {
        "template_id": "school",
        "entry_days": [0, 20],
        "weapon_budget": {"pistol": {"rounds": 10, "sediment_per_shot": 3}},
        "noise_budget": {"cap": 10},
        "timeline": "改了就炸",
    },
    # ---- 无尽 profile 留了存档（R17）
    "data/mode_profile.json": {
        "story": {"timeline": "finite(30)", "budget": {"cards_max": 12}},
        "endless": {"save": "auto", "carry": "story_save", "load_menu": True},
    },
    # ---- L 层卡出现模板专名（R26）
    "data/cards/layer_l.json": {
        "layer": "L",
        "cards": [
            {"card_id": "l_night_meet", "text": {"body": "你听见广播室那边有动静。"}},
            {"card_id": "l_knock", "text": {"body": "有人敲门，敲了三下。"}},
            {
                # R33：正文引用了另一张卡的 card_id；R35：效果写了六组之外的变量
                "card_id": "l_bad_deps",
                "text": {"body": "接着 l_night_meet 那件事往下走。"},
                "trigger": {"vars": [{"name": "world_state", "op": ">", "value": 0}]},
                "effects": [{"when": "总是", "vars": {"global.flag": 1}, "evidence": "evt_x"}],
            },
        ],
    },
    "data/cards/layer_s_school.json": {"layer": "S", "cards": []},
    # ---- 美术：grid 32（R14）；武器层缺 socket_muzzle（R15）；视差 1.5（R24）
    "art/asset-manifest.json": {
        "assets": [
            {
                "asset_id": "chr_student_a_walk_r_02", "category": "character",
                "grid": [16, 16], "source": "generated", "status": "approved",
                "output_path": "art/approved/chr_student_a_walk_r_02.png",
                "reviewer": None, "approved_at": None,
                "accessory_slots": [{"id": 0, "semantic": "back_torso", "name": "backpack"}],
            },
            {
                "asset_id": "wpn_pistol_fire", "category": "weapon_layer",
                "grid": [16, 16], "source": "authoritative", "status": "approved",
                "tags": [{"name": "attack", "one_shot": True, "loop": True, "repeat": "2",
                          "frames": [{"ms": 0}]}],
                "trim": True,
            },
            {
                # 派生体换了装备语义：母体 #0 是书包，它变成断臂 → R25 必须开火
                "asset_id": "zom_student_z", "category": "zombie_variant",
                "grid": [16, 16], "source": "authoritative", "status": "draft",
                "output_path": "art/approved/chr_student_a_walk_r_02.png",
                "derived_from": "chr_student_a_walk_r_02",
                "accessory_slots": [{"id": 0, "semantic": "arm", "name": "arm"}],
            },
        ]
    },
    # ---- 音频：music 类目 + direction_cue 缺 elevation（R32 双开火）
    "data/audio/sounds.json": {
        "policy": {"max_events": 24},
        "events": [
            {"event": "music.ambient", "asset_key": "x1", "category": "music", "status": "planned"},
            {"event": "noise.glass", "asset_key": "x2", "category": "direction_cue",
             "pan": True, "distance_tier": "near", "status": "planned"},
        ],
    },
    # ---- AI 台账：已签核但无 reviewer（R20）
    "AI_LEDGER.json": {
        "entries": [{"asset_id": "chr_student_a_walk_r_02", "model": "PixelLab", "provider": "PixelLab",
                     "input_assets": [], "reviewer": "", "approved_at": "2026-11-22", "date": "2026-11-22"}]
    },
    # ---- 漂移被设成硬门禁（R22）
    "pipeline.json": {"steps": [{"name": "style-drift-check", "gate": "hard"}]},
    # ---- 字体缺授权字段（R23）
    "THIRD_PARTY_LICENSES.json": {
        "fonts": [{"name": "Vonwaon", "license": "CC0-1.0", "source": "", "author": "", "notice_path": ""}]
    },
    "art/palettes/master.gpl": "GIMP Palette\nName: master\nColumns: 16\n#\n13 17 20\tbg\n224 138 60\taccent\n",
}

EXPECTED_ERRORS = {
    "R02", "R07", "R09", "R10", "R14", "R15", "R17", "R18", "R20",
    "R22", "R23", "R24", "R25", "R26", "R27", "R28", "R29", "R30", "R32",
    "R33", "R35",
}


def build(root: Path) -> None:
    for rel, payload in FIXTURE.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(payload, str):
            p.write_text(payload, encoding="utf-8")
        else:
            p.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (root / "art/approved").mkdir(parents=True, exist_ok=True)
    (root / "art/approved/chr_student_a_walk_r_02.png").write_bytes(
        b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + (32).to_bytes(4, "big") + (32).to_bytes(4, "big")
    )


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="residual_selftest_"))
    try:
        build(tmp)
        ctx = V.Ctx(tmp)
        findings = V.run(ctx, only=EXPECTED_ERRORS)
        fired = {f.rule for f in findings if f.level == V.ERROR}
        missed = sorted(EXPECTED_ERRORS - fired)
        extra_skips = [f for f in findings if f.level == V.SKIP]

        for rid in sorted(EXPECTED_ERRORS):
            hit = [f for f in findings if f.rule == rid and f.level == V.ERROR]
            mark = "PASS" if hit else "FAIL"
            detail = hit[0].msg if hit else "规则没有开火"
            print(f"[{mark}] {rid}  {detail}")

        if extra_skips:
            print(f"\n注意：{len(extra_skips)} 条规则因夹具缺输入被跳过（不算失败）")
        print(f"\n{'全部通过' if not missed else '未开火：' + ', '.join(missed)}")
        return 0 if not missed else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
