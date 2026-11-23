# dev · Stage 1 corridor prop placement/code audit

You are the coding seat (gpt-6.2-sol). Audit the proposed 15-prop scene placement and return implementation-ready advice. Do not edit files. Do not invent IDs or fields; use only the exact names/geometry below.

Project facts:
- Godot 4.7, native viewport 384x216, world tile grid 16px, corridor width 40 tiles (640px).
- `game/scenes/corridor.gd` uses a `Sprite2D` atlas helper `_place_prop(idx, tx, ty)` with a 32x32 region and `centered=false`; current camera starts at world x=192 and shows world x=0..384. Its player walks right and camera starts following after x exceeds roughly 128.
- Corridor wall occupies tile rows 3..6, base row 7, floor rows 8..11, lower black rows 12..13. Player foot y=128 (row 8).
- Current assets in `PROP-01_school.png`: locker_bank, door_broken, desk_flipped, window_night, light_dead. This atlas uses opaque background, contains a warm pixel in window, and was generated from approximate RGB rather than semantic roles; it must not be reused as a final asset.
- Frozen art constraints: only master.gpl semantic colors; no c00_void on objects; c31_dead_black is the permitted embedded outline; per asset <=16 colors; no semi-transparent edge pixels; 16px grid; Day 3 environment props contain no c13/c14/c15 warm colors. Sprite canvas 32x32, transparent background. Density must not obscure the player or playable affordances.

Exact proposed 15 names:
1 locker_bank
2 door_broken
3 desk_flipped
4 window_night
5 light_dead
6 wall_clock_stopped
7 fire_extinguisher
8 first_aid_cabinet
9 trash_bin
10 mop_bucket
11 drinking_fountain
12 chair_toppled
13 intercom_broken
14 classroom_plaque
15 notice_board_torn

Return:
1. A placement table (name, tile x, tile y, mounting type) across the 40x14 world, avoiding the player's spawn at x=2/y=8 and major overlaps. Use x/y integers only.
2. Three likely Godot integration mistakes to test for (sorting, viewport visibility, scale/anchor, or draw order).
3. A concise assertion plan that can prove all 15 assets are referenced and at least two camera shots cover all world sections.
Do not claim you ran the project.
