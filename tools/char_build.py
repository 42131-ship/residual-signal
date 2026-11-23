#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""人物资产构造器：角色身体轮廓 + 语义配件 + 感染派生。

教师沿用共用的参数化身体。学生使用独立的侧身轮廓，以便在原生 32px 画布中
将可见高度控制在 24px；NPC 学生复用该轮廓，但配件仍由语义槽统一绘制。
感染姿势只改变肤色、腿部姿态与少数伤痕，不替换母体配件。
"""

from __future__ import annotations

import json
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixelpipe import named_map  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PAL = ROOT / "art" / "palettes" / "master.gpl"
OUT_DIR = ROOT / "art" / "generated_candidates" / "characters"
PREV = ROOT / "design" / "previews"
S = 32

# 唯一的身体参数表。改这里就是改所有人。
BODY = {
    "student": dict(head_top=7, head_h=7, torso_x=(11, 20), torso_y=(14, 21),
                    leg_y=22, shoe_w=4, arm_y=(15, 21), profile="student"),
    "teacher": dict(head_top=1, head_h=8, torso_x=(11, 20), torso_y=(9, 21),
                    leg_y=22, shoe_w=4, arm_y=(10, 21)),
}

# 配件位：每个角色只允许从这里挑，不允许临时加东西
ACCESSORY = {
    "student": ["badge", "backpack", "strap"],
    "teacher": ["glasses", "lanyard", "papers"],
}

# 语义标签：R25 靠它判断「派生体的第 i 位还是不是同一件装备」。
# 没有语义，母体 #2=书包、派生 #2=断臂，集合相等也会被放过。
ACCESSORY_SPEC = {
    "badge": {"semantic": "torso_front", "name": "badge"},
    "backpack": {"semantic": "back_torso", "name": "backpack"},
    "strap": {"semantic": "chest_diagonal", "name": "strap"},
    "glasses": {"semantic": "face", "name": "glasses"},
    "lanyard": {"semantic": "neck", "name": "lanyard"},
    "papers": {"semantic": "arm_front", "name": "papers"},
    # C6 新增：8 个 NPC 里另外五个人的配件
    "visor": {"semantic": "head", "name": "visor"},
    "apron": {"semantic": "torso_front", "name": "apron"},
    "towel": {"semantic": "neck", "name": "towel"},
    "toolbag": {"semantic": "back_torso", "name": "toolbag"},
    "goggles": {"semantic": "neck", "name": "goggles"},
    "script": {"semantic": "arm_front", "name": "script"},
}

# npc_id -> (身体比例, 配件顺序)。顺序必须与 data/npcs/npcs.json 的 accessory_slots 一致，
# 由 R43 机械校验 —— 声明与画出对不上，熟人丧尸化就认不出人。
NPC_KINDS = {
    "npc_wei": ("teacher", ["visor", "badge"]),
    "npc_tan": ("teacher", ["apron", "towel"]),
    "npc_xu": ("student", ["strap", "badge"]),
    "npc_he": ("student", ["toolbag", "goggles"]),
    "npc_mo": ("teacher", ["lanyard", "script"]),
}


def slots_of(names: list[str]) -> list[dict]:
    """母体与派生共用同一个列表 —— 语义一致是构造出来的，不是校验出来的。"""
    return [{"id": i, **ACCESSORY_SPEC[n]} for i, n in enumerate(names)]


def split_kind(kind: str) -> tuple[str, bool]:
    marker = "_infected"
    if marker not in kind:
        return kind, False
    return kind.split(marker, 1)[0], True


def draw_head(d, P, b, skin, skin_lit, hair, eye, tilt=0):
    x0 = (S - 6) // 2 + tilt
    y0 = b["head_top"]
    h = b["head_h"]
    if b.get("profile") == "student":
        d.polygon([
            (x0 + 1, y0), (x0 + 5, y0), (x0 + 6, y0 + 2),
            (x0 + 6, y0 + h - 3), (x0 + 4, y0 + h - 1),
            (x0 + 1, y0 + h - 1), (x0, y0 + h - 3), (x0, y0 + 2),
        ], fill=skin)
        d.polygon([(x0 + 4, y0 + 2), (x0 + 5, y0 + 3),
                   (x0 + 5, y0 + h - 3), (x0 + 4, y0 + h - 2)], fill=skin_lit)
        d.polygon([
            (x0 - 1, y0 + 2), (x0 + 1, y0), (x0 + 5, y0),
            (x0 + 7, y0 + 2), (x0 + 6, y0 + 3), (x0 + 3, y0 + 2),
            (x0 + 1, y0 + 4), (x0, y0 + 7), (x0 - 1, y0 + 6),
        ], fill=hair)
        ey = y0 + 5
        d.point((x0 + 4, ey - 1), fill=P["c01_shadow"])
        d.point((x0 + 5, ey), fill=eye)
        d.point((x0 + 6, y0 + 7), fill=skin_lit)
        neck_x = x0 + 3
        d.rectangle([neck_x, y0 + h - 1, neck_x + 1, y0 + h], fill=skin_lit)
        return x0, y0, ey

    d.rectangle([x0, y0, x0 + 5, y0 + h - 1], fill=skin)
    d.rectangle([x0 + 4, y0 + 2, x0 + 5, y0 + h - 2], fill=skin_lit)
    d.rectangle([x0, y0, x0 + 5, y0 + 1], fill=hair)
    d.rectangle([x0 - 1, y0 + 1, x0, y0 + 2], fill=hair)
    ey = y0 + h // 2
    d.point((x0 + 1, ey), fill=eye)
    d.point((x0 + 4, ey), fill=eye)
    d.rectangle([(S - 2) // 2, y0 + h, (S - 2) // 2 + 1, y0 + h], fill=skin_lit)
    return x0, y0, ey


def draw_accessory(d, P, name, b, head_x, head_y, eye_y, infected):
    tx0, tx1 = b["torso_x"]
    ty0, ty1 = b["torso_y"]
    if name == "badge":
        d.rectangle([tx1 - 2, ty0 + 3, tx1 - 1, ty0 + 4], fill=P["c22_grey_lit"])
    elif name == "backpack":
        # 压住躯干左缘 1px → 读成「背着」而不是「旁边有个包」
        d.rectangle([tx0 - 4, ty0 + 2, tx0, ty0 + 8], fill=P["c25_leather"])
        d.line([tx0 - 4, ty0 + 2, tx0, ty0 + 2], fill=P["c24_cloth_lit"])
        d.line([tx0 - 4, ty0 + 8, tx0, ty0 + 8], fill=P["c31_dead_black"])
    elif name == "strap":
        if b.get("profile") == "student":
            for point in [(12, 15), (13, 16), (14, 17), (15, 18), (16, 19), (17, 20)]:
                d.point(point, fill=P["c25_leather"])
        else:
            for i in range(8):
                d.point((tx0 + 1 + i, ty0 + 1 + i), fill=P["c25_leather"])
    elif name == "glasses":
        d.point((head_x, eye_y), fill=P["c31_dead_black"])
        d.point((head_x + 1, eye_y), fill=P["c31_dead_black"])
        d.point((head_x + 4, eye_y), fill=P["c31_dead_black"])
        d.point((head_x + 5, eye_y), fill=P["c31_dead_black"])
        d.point((head_x + 2, eye_y), fill=P["c22_grey_lit"])   # 鼻梁
    elif name == "lanyard":
        cx = head_x + 2
        for y in range(head_y + b["head_h"], ty0 + 7):
            d.point((cx, y), fill=P["c22_grey_lit"])
        d.rectangle([cx - 1, ty0 + 7, cx + 1, ty0 + 9], fill=P["c22_grey_lit"])
        d.point((cx, ty0 + 8), fill=P["c21_grey"])
    elif name == "papers":
        d.rectangle([tx1 - 4, ty0 + 3, tx1 + 1, ty0 + 5], fill=P["c10_coldhigh"])
        d.line([tx1 - 4, ty0 + 4, tx1 + 1, ty0 + 4], fill=P["c21_grey"])
    elif name == "visor":
        d.rectangle([head_x, head_y - 1, head_x + 5, head_y], fill=P["c21_grey"])
        d.point((head_x + 5, head_y + 1), fill=P["c02_dark"])
    elif name == "apron":
        d.rectangle([tx0 + 1, ty0 + 2, tx1 - 1, ty1 - 1], fill=P["c24_cloth_lit"])
        d.line([tx0 + 1, ty0 + 2, tx0 + 1, ty1 - 1], fill=P["c21_grey"])
        d.line([tx1 - 1, ty0 + 2, tx1 - 1, ty1 - 1], fill=P["c21_grey"])
    elif name == "towel":
        d.rectangle([head_x, head_y + b["head_h"], head_x + 4, head_y + b["head_h"]], fill=P["c22_grey_lit"])
        d.point((head_x + 1, head_y + b["head_h"] + 1), fill=P["c22_grey_lit"])
    elif name == "toolbag":
        d.rectangle([tx0 - 4, ty0 + 3, tx0, ty0 + 9], fill=P["c17_rust"])
        d.line([tx0 - 4, ty0 + 3, tx0, ty0 + 3], fill=P["c18_rust_lit"])
        d.point((tx0 - 3, ty0 + 6), fill=P["c25_leather"])
    elif name == "goggles":
        if b.get("profile") == "student":
            strap_y = ty0 - 1
            d.line([(head_x + 1, head_y + b["head_h"] - 1), (head_x + 1, strap_y)], fill=P["c25_leather"])
            d.line([(head_x + 5, head_y + b["head_h"] - 1), (head_x + 5, strap_y)], fill=P["c25_leather"])
            d.rectangle([head_x + 1, ty0, head_x + 2, ty0 + 1], fill=P["c21_grey"])
            d.rectangle([head_x + 4, ty0, head_x + 5, ty0 + 1], fill=P["c21_grey"])
        else:
            d.point((head_x + 1, eye_y - 2), fill=P["c21_grey"])
            d.point((head_x + 4, eye_y - 2), fill=P["c21_grey"])
            d.line([head_x, eye_y - 3, head_x + 5, eye_y - 3], fill=P["c02_dark"])
    elif name == "script":
        d.rectangle([tx1 - 4, ty0 + 4, tx1 + 1, ty0 + 6], fill=P["c10_coldhigh"])
        d.line([tx1 - 3, ty0 + 5, tx1, ty0 + 5], fill=P["c21_grey"])
    if infected and name == "badge":
        d.point((tx1 - 2, ty0 + 5), fill=P["c19_dried"])       # 胸牌下的疙瘩


def build_student(P, pose, infected, names, skin, skin_lit, hair, eye):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark = P["c02_dark"]
    cloth = P["c23_cloth"]

    # 背后侧轮廓，随后由躯干压住内侧边缘。
    if "backpack" in names:
        d.polygon([(8, 16), (11, 15), (13, 17), (13, 23), (10, 25), (8, 23)], fill=P["c25_leather"])
        d.line([(8, 17), (10, 16), (12, 17)], fill=P["c24_cloth_lit"])
        d.point((9, 22), fill=P["c31_dead_black"])
    elif "toolbag" in names:
        draw_accessory(d, P, "toolbag", BODY["student"], 0, 0, 0, infected)

    # 两条分开的裤腿、袜口与鞋底，让脚步线固定在 y=30。
    d.polygon([(12, 21), (15, 21), (15, 27), (14, 29), (11, 29), (12, 27)], fill=dark)
    if infected:
        knee_y = 25 + pose % 3
        d.polygon([(17, 21), (20, 21), (20, knee_y), (19, 29), (16, 29), (17, 26)], fill=dark)
    else:
        d.polygon([(17, 21), (20, 21), (20, 28), (19, 29), (16, 29), (17, 27)], fill=dark)
    d.line([(12, 28), (14, 28)], fill=P["c21_grey"])
    d.line([(17, 28), (19, 28)], fill=P["c21_grey"])
    d.polygon([(10, 29), (14, 29), (14, 30), (10, 30)], fill=P["c01_shadow"])
    d.polygon([(17, 29), (21, 29), (22, 30), (17, 30)], fill=P["c01_shadow"])

    # 校服躯干：肩窄、腰收，前襟和衣摆分成可读色块。
    d.polygon([(12, 14), (14, 13), (18, 13), (20, 15), (21, 21),
               (19, 23), (12, 22), (10, 20), (11, 16)], fill=cloth)
    d.polygon([(12, 14), (14, 13), (18, 13), (19, 15), (14, 16)], fill=P["c24_cloth_lit"])
    d.line([(15, 15), (15, 21)], fill=P["c25_leather"])
    d.point((15, 17), fill=P["c22_grey_lit"])
    d.line([(12, 22), (19, 23)], fill=P["c01_shadow"])

    # 近侧手臂与手；袖口和手部各一档，减少躯干/四肢粘连。
    d.polygon([(19, 15), (21, 15), (23, 18), (22, 22), (20, 22), (20, 19)], fill=dark)
    d.line([(21, 21), (22, 21)], fill=skin_lit)
    d.polygon([(10, 16), (12, 15), (12, 20), (11, 22), (9, 21)], fill=dark)

    head_x, head_y, eye_y = draw_head(
        d, P, BODY["student"], skin, skin_lit, hair, eye,
        tilt=(pose % 2) if infected else 0,
    )

    # 母体配件位继续由统一语义绘制器负责，NPC 学生也保留工具包/护目镜。
    for name in names:
        if name not in ("backpack", "toolbag"):
            draw_accessory(d, P, name, BODY["student"], head_x, head_y, eye_y, infected)
    return img


def validate_sprite(kind: str, img: Image.Image, P: dict, names: list[str], *, pose: int = 0) -> None:
    if img.size != (S, S):
        raise ValueError(f"{kind}: expected {S}x{S}, got {img.size}")
    rgba = img.convert("RGBA")
    # A 32×32 image has at most S*S distinct RGBA tuples.
    samples = rgba.getcolors(maxcolors=S * S)
    if any(pixel[3] not in (0, 255) for _, pixel in samples):
        raise ValueError(f"{kind}: semi-transparent pixels are not allowed")
    colors = {pixel[:3] for _, pixel in samples if pixel[3] == 255}
    if not 1 <= len(colors) <= 16 or not colors.issubset(set(P.values())):
        raise ValueError(f"{kind}: invalid palette budget ({len(colors)} colors)")
    core, _infected = split_kind(kind)
    base = NPC_KINDS.get(core, ("teacher" if core.startswith("teacher") else "student", []))[0]
    px = rgba.load()
    if base == "student":
        bounds = rgba.getchannel("A").getbbox()
        if bounds is None or (bounds[1], bounds[3]) != (7, 31):
            raise ValueError(f"{kind}: student silhouette must be 24px high and end at row 30: {bounds}")
        runs = "".join("1" if px[x, 30][3] == 255 else "0" for x in range(S)).split("0")
        spans = [len(run) for run in runs if run]
        if len(spans) != 2 or min(spans) < 4:
            raise ValueError(f"{kind}: expected two separated shoes on row 30, got widths {spans}")

    # Check distinct landmarks, not shared colors anywhere in a broad region.
    b = BODY[base]
    tx0, tx1 = b["torso_x"]
    ty0, _ = b["torso_y"]
    badge_y = ty0 + (3 if base == "student" else 3)
    probes = {"badge": [(x, y, "c22_grey_lit") for x in (tx1 - 2, tx1 - 1)
                        for y in (badge_y, badge_y + 1)]}
    if base == "student":
        head_x = (S - 6) // 2 + (pose % 2 if kind.endswith("_infected") else 0)
        probes.update({
            "backpack": [(8, 17, "c24_cloth_lit"), (8, 18, "c25_leather"), (9, 22, "c31_dead_black")],
            "strap": [(12, 15, "c25_leather"), (14, 17, "c25_leather"), (16, 19, "c25_leather")],
            "toolbag": [(tx0 - 4, ty0 + 3, "c18_rust_lit"), (tx0 - 4, ty0 + 5, "c17_rust")],
            "goggles": [(head_x + dx, ty0 + dy, "c21_grey") for dx in (1, 2, 4, 5) for dy in (0, 1)],
        })
    for name in names:
        for x, y, color in probes.get(name, []):
            if px[x, y] != (*P[color], 255):
                raise ValueError(f"{kind}: declared accessory {name!r} is missing its {color} pixel at {(x, y)}")


def build(kind: str, P: dict, pose: int = 0, slot_names: list[str] | None = None) -> Image.Image:
    core, infected = split_kind(kind)
    if core in NPC_KINDS:
        base, names = NPC_KINDS[core]
    else:
        base = "teacher" if core.startswith("teacher") else "student"
        names = ACCESSORY[base]
    names = slot_names or names
    b = BODY[base]

    skin = P["c28_pallid"] if infected else P["c26_skin"]
    skin_lit = P["c29_pallid_lit"] if infected else P["c27_skin_lit"]
    cloth = P["c23_cloth"]
    dark = P["c02_dark"]
    hair = P["c01_shadow"]
    eye = P["c31_dead_black"]

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if base == "student":
        return build_student(P, pose, infected, names, skin, skin_lit, hair, eye)
    tx0, tx1 = b["torso_x"]
    ty0, ty1 = b["torso_y"]
    ly = b["leg_y"]

    # 1) 腿：感染后一条拖，膝盖软；pose 决定膝盖塌到哪
    d.rectangle([tx0 + 1, ly, tx0 + 3, 29], fill=dark)
    if infected:
        knee = 27 - (pose % 3)
        d.polygon([(tx1 - 3, ly), (tx1 - 1, ly), (tx1, knee), (tx1 - 2, 29)], fill=dark)
    else:
        d.rectangle([tx1 - 3, ly, tx1 - 1, 29], fill=dark)
    # 2) 鞋
    d.rectangle([tx0, 30, tx0 + b["shoe_w"] - 1, 30], fill=P["c01_shadow"])
    d.rectangle([tx1 - b["shoe_w"] + 1, 30, tx1, 30], fill=P["c01_shadow"])

    # 3) 配件后半层（背在身上的）
    for name in names:
        if name in ("backpack", "toolbag"):
            draw_accessory(d, P, name, b, 0, 0, 0, infected)

    # 4) 躯干（压住书包左缘）
    d.rectangle([tx0, ty0, tx1, ty1], fill=cloth)
    d.line([tx0, ty0, tx1, ty0], fill=P["c24_cloth_lit"])

    # 5) 手臂：用更暗的色，与躯干隔开
    ay0, ay1 = b["arm_y"]
    d.rectangle([tx0 - 2, ay0, tx0 - 1, ay1 if not infected else ay1 + 1], fill=dark)
    d.rectangle([tx1 + 1, ay0, tx1 + 2, ay1 if not infected else ay1 + 2], fill=dark)

    # 6) 头
    head_x, head_y, eye_y = draw_head(d, P, b, skin, skin_lit, hair, eye,
                                      tilt=(1 + pose) if infected else 0)

    # 7) 配件前半层
    for name in names:
        if name not in ("backpack", "toolbag"):
            draw_accessory(d, P, name, b, head_x, head_y, eye_y, infected)

    return img


def main() -> int:
    P = named_map(PAL)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREV.mkdir(parents=True, exist_ok=True)
    kinds = ["student", "teacher", "student_infected", "teacher_infected"]
    imgs = []
    cand: dict = {"schema": "characters.candidates.v1", "assets": []}

    def emit(kind: str, pose: int, npc_ref: str | None = None) -> None:
        core, infected = split_kind(kind)
        if core in NPC_KINDS:
            base, names = NPC_KINDS[core]
        else:
            base = "teacher" if core.startswith("teacher") else "student"
            names = ACCESSORY[base]
        suffix = f"_p{pose}" if pose else ""
        # 派生体的母体是「同名但没感染」的那一具
        mother = f"chr_{core}_idle_r_00" if infected else None
        aid = f"chr_{kind}{suffix}_idle_r_00"
        im = build(kind, P, pose)
        validate_sprite(kind, im, P, names, pose=pose)
        path = OUT_DIR / f"SPR-{kind}{suffix}_32.png"
        im.save(path)
        imgs.append(im)
        cand["assets"].append({
            "asset_id": aid,
            "category": "zombie_variant" if infected else "character",
            "source": "authoritative",
            "status": "draft",
            "output_path": str(path.relative_to(ROOT)).replace("\\", "/"),
            "grid": [S, S],
            "directions": ["r"],
            "accessory_slots": slots_of(names),
            "derived_from": mother,
            "npc_ref": core if core in NPC_KINDS else None,
        })

    # ① 活着的母体：学生 / 老师 / 5 个 NPC
    for m in ["student", "teacher", *NPC_KINDS.keys()]:
        emit(m, 0)
    # 丧尸化母体/NPC 共用 pose 0–2；玩家与教师保留清单中已有的 pose 3。
    for m in ["student", "teacher", *NPC_KINDS.keys()]:
        for p in (0, 1, 2):
            emit(f"{m}_infected", p)
    emit("student_infected", 3)
    emit("teacher_infected", 3)

    student_review = Image.new("RGBA", (S * 5, S + 12), (3, 5, 10, 255))
    review_frames = [
        ("SPR-student_32.png", "student"),
        ("SPR-student_infected_32.png", "infected"),
        ("SPR-student_infected_p1_32.png", "infected p1"),
        ("SPR-student_infected_p2_32.png", "infected p2"),
        ("SPR-student_infected_p3_32.png", "infected p3"),
    ]
    review_draw = ImageDraw.Draw(student_review)
    for index, (filename, label) in enumerate(review_frames):
        sprite = Image.open(OUT_DIR / filename).convert("RGBA")
        cell_x = index * S
        student_review.alpha_composite(sprite, (cell_x, 12))
        review_draw.text((cell_x + 1, 1), label, fill=P["c10_coldhigh"])
    student_review.convert("RGB").resize((S * 5 * 4, (S + 12) * 4), Image.NEAREST).save(
        PREV / "CHAR_stage2_student_x4.png")

    gap = 8
    W = len(imgs) * S + gap * (len(imgs) - 1)
    sheet = Image.new("RGBA", (W, S), (3, 5, 10, 255))
    for i, im in enumerate(imgs):
        sheet.alpha_composite(im, (i * (S + gap), 0))
    sheet.convert("RGB").resize((W * 6, S * 6), Image.NEAREST).save(PREV / "CHAR_built32_x6.png")
    print(PREV / "CHAR_built32_x6.png", (W * 6, S * 6))

    (OUT_DIR / "characters.candidates.json").write_text(
        json.dumps(cand, ensure_ascii=False, indent=2), encoding="utf-8")
    print(OUT_DIR / "characters.candidates.json", f"{len(cand['assets'])} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
