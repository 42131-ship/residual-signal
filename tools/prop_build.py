#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build 15 semantic-palette school props as separate transparent 32x32 PNGs.

The 16px value is the world grid, not an object-size limit. Each prop is authored
at native 32x32 with a center pivot; scene placement remains on the 16px grid.
The previous opaque `PROP-01_school.png` is deliberately not consumed here.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Callable

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from pixelpipe import named_map

ROOT = Path(__file__).resolve().parent.parent
PAL_PATH = ROOT / "art/palettes/master.gpl"
OUT_DIR = ROOT / "art/generated_candidates/props/stage1"
PREVIEW = ROOT / "design/previews/PROPS-02_contact.png"
INDEX = OUT_DIR / "props.json"
CANDIDATES = OUT_DIR / "props.candidates.json"
SIZE = 32
WORLD_TILES = (40, 14)
TILE_SIZE = 16
SCENE = ROOT / "game/scenes/corridor_props.tscn"
BANNED_COLORS = ("c00_void", "c13_warm_dim", "c14_warm", "c15_warm_high", "c28_pallid", "c29_pallid_lit", "c30_white")
# Grid positions address the top-left of each 32px canvas. The runtime adds
# the center pivot, so tiling and centered transforms describe the same frame.
PLACEMENTS = {
    "locker_bank": (4, 6),
    "door_broken": (14, 6),
    "desk_flipped": (11, 9),
    "window_night": (17, 4),
    "light_dead": (20, 3),
    "wall_clock_stopped": (4, 3),
    "fire_extinguisher": (22, 6),
    "first_aid_cabinet": (25, 4),
    "trash_bin": (23, 9),
    "mop_bucket": (29, 9),
    "drinking_fountain": (32, 5),
    "chair_toppled": (17, 9),
    "intercom_broken": (31, 3),
    "classroom_plaque": (12, 4),
    "notice_board_torn": (33, 3),
}

for stream in (sys.stdout, sys.stderr):
    try:
        stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except (AttributeError, OSError, ValueError):
        pass

ROLE_NAMES = {
    "outline": "c31_dead_black",
    "shadow": "c01_shadow",
    "dark": "c02_dark",
    "wall": "c03_wall",
    "floor": "c04_floor",
    "lit": "c05_lit",
    "top": "c06_top",
    "edge": "c07_edge",
    "grey": "c21_grey",
    "grey_lit": "c22_grey_lit",
    "rust": "c17_rust",
    "rust_lit": "c18_rust_lit",
    "cloth": "c23_cloth",
    "cloth_lit": "c24_cloth_lit",
    "leather": "c25_leather",
}


def make_props(C: dict[str, tuple[int, int, int]]) -> list[tuple[str, str, Callable[[ImageDraw.ImageDraw], None]]]:
    props: list[tuple[str, str, Callable[[ImageDraw.ImageDraw], None]]] = []

    def add(name: str, mount: str, draw: Callable[[ImageDraw.ImageDraw], None]) -> None:
        props.append((name, mount, draw))

    def box(d, xy, color):
        d.rectangle(xy, fill=C[color])

    # 01. Two-door locker bank: front face, visible right return, vents and feet.
    def locker(d):
        d.polygon([(2, 3), (26, 3), (30, 6), (30, 29), (5, 29), (2, 26)], fill=C["dark"])
        d.polygon([(3, 4), (25, 4), (28, 6), (28, 27), (5, 27), (3, 25)], fill=C["wall"])
        d.polygon([(26, 4), (29, 6), (29, 27), (28, 27), (28, 6)], fill=C["dark"])
        box(d, [5, 6, 15, 25], "lit")
        box(d, [16, 6, 26, 25], "floor")
        d.line([(15, 6), (15, 25)], fill=C["dark"])
        d.line([(4, 6), (26, 6)], fill=C["top"])
        for x in (7, 10, 13, 18, 21, 24):
            d.line([(x, 9), (x, 13)], fill=C["dark"])
        box(d, [12, 16, 13, 19], "grey")
        box(d, [23, 16, 24, 19], "grey")
        d.line([(6, 15), (9, 15)], fill=C["grey_lit"])
        d.point((20, 8), fill=C["top"])
        d.point((6, 24), fill=C["shadow"])
        d.line([(6, 22), (10, 22)], fill=C["wall"])
        d.line([(17, 22), (21, 22)], fill=C["dark"])
        d.line([(7, 28), (8, 30)], fill=C["dark"])
        d.line([(24, 28), (25, 30)], fill=C["dark"])
    add("locker_bank", "floor_wall", locker)

    # 02. Open classroom door: a three-sided jamb stays visible while the
    # leaf is swung toward the viewer, with hinges, handle, and threshold.
    def door(d):
        box(d, [3, 1, 28, 5], "dark")
        box(d, [3, 1, 6, 29], "dark")
        box(d, [25, 1, 28, 29], "dark")
        d.line([(5, 2), (26, 2)], fill=C["edge"], width=2)
        d.line([(6, 5), (24, 5)], fill=C["top"])
        d.line([(5, 6), (5, 27)], fill=C["wall"])
        d.line([(26, 6), (26, 27)], fill=C["wall"])
        d.polygon([(8, 7), (15, 6), (19, 25), (12, 29), (8, 26)], fill=C["dark"])
        d.polygon([(10, 8), (14, 7), (17, 24), (13, 26), (10, 24)], fill=C["wall"])
        d.line([(10, 9), (14, 8)], fill=C["top"])
        d.point((16, 12), fill=C["grey"])
        d.point((18, 13), fill=C["edge"])
        d.line([(12, 13), (11, 17), (13, 20), (12, 23)], fill=C["edge"])
        box(d, [15, 16, 17, 19], "grey_lit")
        d.point((16, 17), fill=C["dark"])
        box(d, [6, 10, 7, 12], "grey")
        box(d, [6, 21, 7, 23], "grey")
        d.line([(5, 29), (27, 29)], fill=C["edge"], width=2)
        d.line([(8, 27), (19, 25)], fill=C["rust_lit"])
        d.polygon([(7, 28), (12, 26), (14, 28), (9, 30)], fill=C["rust"])
    add("door_broken", "wall_floor", door)

    # 03. Upside-down student desk: unmistakable rectangular top, drawer
    # opening, and two broad legs pointing upward from the fallen frame.
    def desk(d):
        d.polygon([(3, 20), (25, 15), (30, 18), (29, 24), (7, 30), (2, 27)], fill=C["dark"])
        d.polygon([(5, 20), (24, 17), (28, 19), (27, 22), (8, 27), (4, 25)], fill=C["leather"])
        d.line([(5, 20), (24, 17), (28, 19)], fill=C["rust_lit"], width=2)
        d.line([(8, 26), (27, 21)], fill=C["shadow"])
        d.line([(17, 20), (19, 19)], fill=C["grey_lit"])
        d.point((23, 20), fill=C["top"])
        d.polygon([(10, 21), (22, 19), (24, 21), (12, 24)], fill=C["rust"])
        d.line([(12, 22), (21, 20)], fill=C["cloth_lit"])
        d.polygon([(8, 18), (5, 5), (9, 4), (13, 17)], fill=C["dark"])
        d.polygon([(9, 17), (7, 7), (9, 6), (11, 17)], fill=C["top"])
        d.polygon([(20, 16), (22, 3), (26, 3), (25, 15)], fill=C["dark"])
        d.polygon([(22, 14), (23, 5), (25, 5), (24, 14)], fill=C["edge"])
        d.line([(5, 5), (9, 4)], fill=C["grey"], width=2)
        d.line([(22, 3), (26, 3)], fill=C["grey"], width=2)
        d.line([(2, 27), (7, 30), (29, 24)], fill=C["rust_lit"])
    add("desk_flipped", "floor", desk)

    # 04. Intact frame and mullions around a view into an unlit schoolyard.
    def window(d):
        box(d, [2, 3, 29, 27], "dark")
        box(d, [4, 5, 27, 24], "top")
        for pane in ((6, 7, 14, 13), (17, 7, 25, 13), (6, 16, 14, 22), (17, 16, 25, 22)):
            box(d, pane, "shadow")
        d.line([(4, 5), (27, 5)], fill=C["edge"])
        d.line([(6, 15), (25, 15)], fill=C["edge"])
        d.line([(6, 24), (27, 24)], fill=C["edge"])
        d.line([(6, 20), (10, 17), (13, 19), (14, 19)], fill=C["wall"])
        d.line([(17, 21), (22, 18), (25, 18)], fill=C["wall"])
        d.line([(20, 8), (22, 10), (21, 12)], fill=C["edge"])
        d.point((20, 9), fill=C["dark"])
        d.line([(7, 10), (9, 8)], fill=C["lit"])
        d.line([(3, 27), (28, 27)], fill=C["shadow"])
    add("window_night", "wall", window)

    # 05. Dead fluorescent tube: two ceiling anchors, two end caps, and a
    # broken glass tube hanging from the right side.
    def light(d):
        box(d, [4, 1, 8, 4], "dark")
        box(d, [23, 1, 27, 4], "dark")
        d.line([(6, 4), (6, 8)], fill=C["edge"], width=2)
        d.line([(25, 4), (25, 8)], fill=C["edge"], width=2)
        box(d, [2, 8, 29, 12], "dark")
        d.line([(4, 9), (27, 9)], fill=C["edge"], width=2)
        box(d, [5, 10, 8, 13], "grey")
        box(d, [23, 10, 27, 13], "grey")
        d.line([(8, 11), (17, 11)], fill=C["top"], width=2)
        d.line([(18, 12), (23, 12)], fill=C["edge"], width=2)
        d.line([(17, 11), (19, 14), (18, 18), (20, 21)], fill=C["dark"], width=2)
        d.line([(18, 18), (20, 21)], fill=C["rust_lit"])
        d.point((21, 23), fill=C["grey_lit"])
        d.point((19, 24), fill=C["grey"])
        d.line([(18, 11), (17, 14)], fill=C["grey_lit"])
        d.point((17, 14), fill=C["grey"])
    add("light_dead", "ceiling", light)

    # 06. Stopped wall clock with chipped bezel and visible hands.
    def clock(d):
        d.polygon([(7, 2), (24, 2), (29, 7), (29, 24), (24, 29), (7, 29), (2, 24), (2, 7)], fill=C["dark"])
        d.ellipse([5, 5, 26, 26], fill=C["grey"])
        d.ellipse([7, 7, 24, 24], fill=C["floor"])
        d.ellipse([9, 9, 22, 22], outline=C["grey_lit"])
        for x, y in [(15, 10), (21, 15), (15, 21), (10, 15)]:
            d.point((x, y), fill=C["grey_lit"])
        d.line([(15, 16), (15, 11)], fill=C["grey_lit"], width=2)
        d.line([(15, 16), (20, 19)], fill=C["grey"])
        d.point((15, 16), fill=C["grey_lit"])
        d.line([(7, 4), (10, 3)], fill=C["wall"])
        d.point((15, 7), fill=C["dark"])
        d.point((15, 23), fill=C["dark"])
        d.point((8, 16), fill=C["dark"])
    add("wall_clock_stopped", "wall", clock)

    # 07. Wall fire extinguisher: cylinder, neck, squeeze handle, gauge and
    # hose are kept as separate cues at native size.
    def extinguisher(d):
        d.rounded_rectangle([6, 11, 18, 30], radius=4, fill=C["dark"])
        d.rounded_rectangle([8, 12, 16, 28], radius=3, fill=C["rust"])
        d.line([(10, 14), (10, 26)], fill=C["rust_lit"], width=2)
        d.line([(14, 14), (14, 27)], fill=C["rust_lit"])
        box(d, [9, 19, 15, 22], "cloth_lit")
        d.line([(10, 20), (14, 20)], fill=C["dark"])
        box(d, [10, 7, 15, 11], "dark")
        box(d, [11, 7, 14, 9], "edge")
        d.line([(10, 7), (8, 4), (18, 4)], fill=C["grey"], width=2)
        d.line([(13, 6), (19, 6)], fill=C["grey_lit"], width=2)
        d.ellipse([15, 7, 20, 12], fill=C["grey_lit"], outline=C["dark"])
        d.line([(17, 9), (19, 8)], fill=C["dark"])
        d.line([(18, 10), (24, 10), (27, 14), (27, 24), (24, 27), (21, 25)], fill=C["dark"], width=2)
        d.line([(22, 11), (25, 14), (25, 22)], fill=C["edge"])
        d.polygon([(20, 17), (24, 17), (23, 21), (20, 21)], fill=C["grey"])
        d.point((18, 9), fill=C["rust"])
        d.line([(9, 24), (11, 23)], fill=C["rust"])
    add("fire_extinguisher", "wall", extinguisher)

    # 08. First-aid cabinet, cold cross is a static mark, not a light source.
    def first_aid(d):
        d.polygon([(5, 3), (25, 3), (29, 6), (29, 28), (6, 28), (3, 25), (3, 6)], fill=C["dark"])
        d.polygon([(6, 5), (24, 5), (27, 7), (27, 26), (6, 26)], fill=C["edge"])
        d.line([(7, 7), (24, 7)], fill=C["grey"])
        d.line([(16, 10), (16, 18)], fill=C["grey_lit"], width=2)
        d.line([(12, 14), (20, 14)], fill=C["grey_lit"], width=2)
        d.rectangle([22, 19, 24, 22], fill=C["dark"])
        d.line([(9, 20), (12, 20)], fill=C["grey"])
        d.point((10, 19), fill=C["grey_lit"])
        d.line([(4, 6), (4, 24)], fill=C["wall"])
    add("first_aid_cabinet", "wall", first_aid)

    # 09. Waste bin, dented rim, paper protruding from top.
    def trash_bin(d):
        d.polygon([(5, 9), (27, 9), (24, 30), (8, 30)], fill=C["dark"])
        d.polygon([(7, 12), (25, 12), (22, 28), (10, 28)], fill=C["wall"])
        d.polygon([(5, 8), (25, 7), (29, 10), (27, 13), (6, 13), (3, 11)], fill=C["edge"])
        d.line([(7, 10), (25, 9)], fill=C["shadow"], width=2)
        d.line([(8, 15), (24, 15)], fill=C["dark"])
        d.line([(9, 21), (23, 20)], fill=C["top"])
        d.line([(11, 26), (21, 25)], fill=C["shadow"])
        d.polygon([(11, 9), (12, 5), (16, 6), (18, 9)], fill=C["cloth_lit"])
        d.point((13, 6), fill=C["grey"])
    add("trash_bin", "floor", trash_bin)

    # 10. Mop bucket: broad rim, wringer basket, handle socket, and a long
    # mop head that clearly enters the bucket rather than floating beside it.
    def mop_bucket(d):
        d.line([(7, 2), (11, 17), (15, 21)], fill=C["dark"], width=2)
        d.line([(8, 3), (12, 16)], fill=C["rust_lit"], width=2)
        d.polygon([(14, 19), (22, 18), (25, 23), (18, 27), (12, 24)], fill=C["dark"])
        d.rectangle([16, 20, 21, 22], fill=C["grey"])
        d.line([(16, 21), (21, 20)], fill=C["cloth_lit"])
        d.line([(12, 23), (16, 25)], fill=C["rust_lit"])
        d.polygon([(3, 15), (27, 15), (24, 30), (6, 30)], fill=C["dark"])
        d.polygon([(5, 18), (25, 18), (22, 28), (8, 28)], fill=C["wall"])
        d.line([(5, 17), (25, 17)], fill=C["grey_lit"], width=2)
        d.line([(7, 20), (23, 20)], fill=C["edge"])
        d.line([(9, 26), (21, 26)], fill=C["shadow"])
        d.line([(11, 17), (11, 22)], fill=C["dark"])
        d.line([(15, 17), (15, 22)], fill=C["dark"])
        d.line([(19, 17), (19, 22)], fill=C["dark"])
    add("mop_bucket", "floor", mop_bucket)

    # 11. Wall drinking fountain: the raised arched tap, falling drop,
    # recessed bowl, and broad mounting plate stay distinct in grayscale.
    def fountain(d):
        d.polygon([(8, 5), (23, 5), (26, 8), (26, 13), (22, 16), (7, 15), (5, 12)], fill=C["dark"])
        d.polygon([(9, 7), (22, 7), (24, 9), (24, 12), (21, 14), (9, 13), (7, 11)], fill=C["wall"])
        d.polygon([(13, 16), (13, 10), (15, 7), (21, 7), (24, 10), (24, 15), (21, 15), (21, 11), (19, 9), (16, 9), (15, 11), (15, 16)], fill=C["grey"])
        d.line([(16, 8), (20, 8), (22, 10), (22, 14)], fill=C["grey_lit"], width=2)
        d.rectangle([20, 14, 22, 16], fill=C["grey_lit"])
        d.rectangle([16, 17, 18, 19], fill=C["grey_lit"])
        d.polygon([(3, 18), (25, 18), (29, 21), (26, 26), (9, 27), (4, 24)], fill=C["dark"])
        d.polygon([(5, 19), (24, 19), (27, 21), (24, 23), (10, 24), (6, 22)], fill=C["top"])
        d.polygon([(8, 21), (23, 21), (21, 23), (11, 24), (8, 23)], fill=C["shadow"])
        d.line([(5, 19), (24, 19), (27, 21)], fill=C["grey_lit"], width=2)
        d.point((17, 17), fill=C["dark"])
        d.point((18, 16), fill=C["grey"])
        d.line([(21, 20), (23, 20)], fill=C["grey_lit"])
        d.polygon([(9, 26), (25, 25), (23, 28), (11, 29)], fill=C["edge"])
        d.line([(11, 27), (21, 26)], fill=C["dark"], width=2)
    add("drinking_fountain", "wall", fountain)

    # 12. Toppled chair: a rectangular slatted back joins a broad seat;
    # four thick rails project from separate corners and remain readable gray.
    def chair(d):
        d.polygon([(5, 4), (12, 2), (18, 14), (11, 18), (6, 11)], fill=C["dark"])
        d.polygon([(7, 6), (11, 5), (15, 13), (11, 15), (8, 10)], fill=C["cloth_lit"])
        d.line([(9, 7), (12, 13)], fill=C["dark"], width=2)
        d.polygon([(10, 15), (19, 12), (27, 16), (18, 21), (10, 19)], fill=C["dark"])
        d.polygon([(12, 15), (19, 14), (24, 16), (18, 18), (12, 18)], fill=C["cloth_lit"])
        d.line([(12, 15), (19, 14), (24, 16)], fill=C["top"], width=2)
        d.polygon([(10, 18), (13, 19), (10, 29), (7, 29)], fill=C["dark"])
        d.polygon([(16, 20), (19, 20), (20, 29), (17, 29)], fill=C["dark"])
        d.polygon([(20, 14), (22, 13), (29, 8), (30, 11), (24, 17)], fill=C["dark"])
        d.polygon([(22, 18), (24, 17), (30, 21), (28, 24)], fill=C["dark"])
        d.line([(7, 29), (10, 29)], fill=C["edge"], width=2)
        d.line([(17, 29), (20, 29)], fill=C["edge"], width=2)
        d.point((12, 16), fill=C["dark"])
        d.point((13, 17), fill=C["edge"])
    add("chair_toppled", "floor", chair)

    # 13. Broken wall intercom: speaker grille, call button, handset hook,
    # and one cable are separated into readable blocks.
    def intercom(d):
        d.polygon([(7, 3), (25, 3), (28, 6), (28, 22), (24, 25), (8, 25), (5, 22), (5, 6)], fill=C["dark"])
        d.polygon([(9, 5), (23, 5), (26, 7), (26, 20), (23, 22), (9, 22), (7, 20), (7, 7)], fill=C["edge"])
        box(d, [10, 7, 23, 14], "shadow")
        for y in (8, 10, 12):
            d.line([(11, y), (22, y)], fill=C["grey"])
        d.line([(12, 8), (12, 13)], fill=C["grey_lit"])
        d.ellipse([10, 16, 15, 21], fill=C["dark"])
        d.ellipse([12, 18, 14, 20], fill=C["grey_lit"])
        d.rectangle([18, 17, 23, 20], fill=C["wall"])
        d.line([(19, 17), (22, 17)], fill=C["top"])
        d.line([(24, 21), (24, 25), (21, 27), (24, 29)], fill=C["dark"], width=2)
        d.line([(24, 25), (21, 27), (24, 29)], fill=C["rust_lit"])
        d.point((14, 10), fill=C["shadow"])
        d.point((25, 26), fill=C["grey_lit"])
    add("intercom_broken", "wall", intercom)

    # 14. The room number is a three-character bitmap aligned to the wall.
    def plaque(d):
        box(d, [2, 8, 29, 24], "dark")
        box(d, [4, 10, 27, 21], "floor")
        d.line([(3, 9), (28, 9)], fill=C["edge"])
        d.line([(4, 22), (27, 22)], fill=C["shadow"])
        for y, row in enumerate(("11110     01110", "00001     10001", "00001     10001", "01110 111 11111", "00001     10001", "00001     10001", "11110     10001")):
            for x, mark in enumerate(row):
                if mark == "1":
                    d.point((8 + x, 12 + y), fill=C["grey_lit"])
        d.point((5, 15), fill=C["grey"])
        d.point((26, 15), fill=C["grey"])
        d.line([(8, 20), (23, 20)], fill=C["shadow"])
        d.point((10, 19), fill=C["grey"])
        d.point((21, 19), fill=C["grey"])
    add("classroom_plaque", "wall", plaque)

    # 15. Torn notice board, curled paper corners and abandoned pin holes.
    def notice_board(d):
        d.polygon([(1, 4), (27, 2), (30, 6), (29, 27), (4, 30), (1, 26)], fill=C["dark"])
        d.polygon([(3, 6), (26, 4), (28, 7), (27, 25), (5, 27), (3, 24)], fill=C["leather"])
        d.line([(5, 8), (25, 6)], fill=C["rust"])
        d.polygon([(5, 10), (16, 9), (17, 20), (13, 18), (11, 22), (6, 20)], fill=C["cloth_lit"])
        d.line([(7, 12), (14, 11)], fill=C["grey"])
        d.line([(7, 15), (14, 14)], fill=C["grey"])
        d.point((8, 18), fill=C["grey"])
        d.line([(9, 18), (14, 17)], fill=C["rust"])
        d.polygon([(19, 11), (26, 10), (24, 21), (21, 18), (18, 20)], fill=C["floor"])
        d.line([(20, 13), (24, 12)], fill=C["edge"])
        d.point((5, 8), fill=C["grey_lit"])
        d.point((25, 9), fill=C["grey_lit"])
        d.line([(4, 29), (28, 27)], fill=C["shadow"])
    add("notice_board_torn", "wall", notice_board)

    return props


def check_layout(props) -> None:
    names = [name for name, _, _ in props]
    if len(names) != 15 or len(names) != len(set(names)) or set(names) != set(PLACEMENTS):
        raise SystemExit("expected 15 unique props matching the placement table")
    occupied: dict[tuple[int, int], str] = {}
    span = SIZE // TILE_SIZE
    for name, mount, _ in props:
        left, top = PLACEMENTS[name]
        if (mount == "floor" and not 9 <= top <= 10) or (mount != "floor" and not 3 <= top <= 6):
            raise SystemExit(f"{name}: tile y={top} does not match mount {mount}")
        for x in range(left, left + span):
            for y in range(top, top + span):
                if not (0 <= x < WORLD_TILES[0] and 0 <= y < WORLD_TILES[1]):
                    raise SystemExit(f"{name}: tile {(x, y)} outside corridor")
                if (x, y) in occupied:
                    raise SystemExit(f"{name}: tile {(x, y)} occupied by {occupied[x, y]}")
                occupied[x, y] = name


def write_scene(records) -> None:
    lines = [f"[gd_scene load_steps={len(records) + 1} format=3]", ""]
    for record in records:
        resource_id = record["index"] + 1
        lines.append(f'[ext_resource type="Texture2D" path="res://{record["output_path"]}" id="{resource_id}"]')
    lines.extend(("", '[node name="Props" type="Node2D"]'))
    for record in records:
        resource_id = record["index"] + 1
        x, y = record["tile_position"]
        pivot_x, pivot_y = record["pivot"]
        center_x, center_y = x * TILE_SIZE + pivot_x, y * TILE_SIZE + pivot_y
        lines.extend((
            "", f'[node name="{record["name"]}" type="Sprite2D" parent="."]',
            f"position = Vector2({center_x}, {center_y})", f'texture = ExtResource("{resource_id}")',
        ))
    SCENE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    palette = named_map(PAL_PATH)
    color_map: dict[str, tuple[int, int, int]] = {}
    for role, palette_name in ROLE_NAMES.items():
        if palette_name not in palette:
            raise SystemExit(f"palette role {role} missing from master.gpl: {palette_name}")
        color_map[role] = palette[palette_name]
    palette_colors = set(palette.values())
    banned = {palette[name] for name in BANNED_COLORS}

    props = make_props(color_map)
    check_layout(props)
    records = []
    rendered: list[Image.Image] = []
    for index, (name, mount, draw) in enumerate(props, 1):
        image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        draw(ImageDraw.Draw(image))
        alpha = image.getchannel("A")
        bounds = alpha.getbbox()
        if not bounds or not (1 <= bounds[0] < bounds[2] < SIZE and 1 <= bounds[1] < bounds[3] < SIZE):
            raise SystemExit(f"{name}: silhouette needs one pixel of room for its outline")

        outline_rgb = color_map["outline"]
        opaque_outline = (*outline_rgb, 255)
        contour = ImageChops.subtract(alpha.filter(ImageFilter.MaxFilter(3)), alpha)
        outline_layer = Image.new("RGBA", (SIZE, SIZE), (*outline_rgb, 0))
        outline_layer.putalpha(contour)
        image = Image.alpha_composite(image, outline_layer)
        counts = {pixel: count for count, pixel in image.getcolors(SIZE * SIZE)}
        used = {pixel[:3] for pixel in counts if pixel[3] == 255}
        if not used <= palette_colors or used & banned:
            raise SystemExit(f"{name}: non-palette or reserved role used")
        if len(used) > 16:
            raise SystemExit(f"{name}: {len(used)} colors exceeds 16")
        if any(pixel[3] not in (0, 255) for pixel in counts):
            raise SystemExit(f"{name}: semi-transparent edge found")
        outline_pixels = counts.get(opaque_outline, 0)
        if not outline_pixels or outline_pixels != contour.histogram()[255]:
            raise SystemExit(f"{name}: c31 must appear only in the one-pixel contour")
        if any(image.getpixel(corner)[3] != 0 for corner in ((0, 0), (SIZE - 1, 0), (0, SIZE - 1), (SIZE - 1, SIZE - 1))):
            raise SystemExit(f"{name}: transparent canvas corners required")

        filename = f"PROP-02_{index:02d}_{name}.png"
        rendered.append(image)
        asset_id = f"prop_school_{name}"
        records.append({
            "index": index - 1,
            "name": name,
            "filename": filename,
            "output_path": f"art/generated_candidates/props/stage1/{filename}",
            "asset_id": asset_id,
            "category": "prop_icon",
            "source": "authoritative",
            "status": "draft",
            "size": [SIZE, SIZE],
            "pivot": [SIZE // 2, SIZE // 2],
            "mount": mount,
            "tile_position": list(PLACEMENTS[name]),
            "colors": len(used),
            "palette_roles": sorted(role for role, rgb in color_map.items() if rgb in used),
            "c31_contour_pixels": outline_pixels,
            "day3_warm_pixels": 0,
        })

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    for record, image in zip(records, rendered):
        image.save(OUT_DIR / record["filename"])
    write_scene(records)

    gap = 12
    scale = 5
    cell_width = SIZE * scale
    label_height = 22
    columns = 5
    rows = (len(rendered) + columns - 1) // columns
    contact = Image.new("RGB", (columns * cell_width + (columns + 1) * gap, rows * (cell_width + label_height) + (rows + 1) * gap), (17, 26, 38))
    label_draw = ImageDraw.Draw(contact)
    for index, (record, image) in enumerate(zip(records, rendered)):
        x = gap + (index % columns) * (cell_width + gap)
        y = gap + (index // columns) * (cell_width + label_height + gap)
        enlarged = image.resize((cell_width, cell_width), Image.Resampling.NEAREST)
        contact.paste(enlarged.convert("RGB"), (x, y), enlarged.getchannel("A"))
        label_draw.text((x, y + cell_width + 3), record["name"], fill=(191, 196, 195))
    contact.save(PREVIEW)
    INDEX.write_text(json.dumps({"schema": "school-props-stage1.v1", "assets": records}, ensure_ascii=False, indent=2), encoding="utf-8")
    intake_records = [{k: record[k] for k in ("asset_id", "category", "source", "status", "output_path")} for record in records]
    CANDIDATES.write_text(json.dumps({"schema": "school-props-candidates.v1", "assets": intake_records}, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"built={len(records)} contact={PREVIEW}")
    for record in records:
        print(f"{record['index']:02d} {record['name']:<24} colors={record['colors']} warm={record['day3_warm_pixels']} {record['filename']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

