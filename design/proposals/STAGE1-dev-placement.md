**Placement**
Use tile coordinates as the top-left of each 32×32 region: `_place_prop(idx, tx, ty)` should place it at `(tx * 16, ty * 16)` with `centered=false`. Resolve `idx` from the final atlas layout; the list order does not establish atlas indices.

| Name | Tile x | Tile y | Mounting type |
|---|---:|---:|---|
| `locker_bank` | 4 | 6 | Wall-backed, flush to floor line |
| `door_broken` | 8 | 6 | Wall inset, flush to floor line |
| `desk_flipped` | 12 | 9 | Floor |
| `window_night` | 15 | 4 | Wall inset |
| `light_dead` | 19 | 3 | Upper wall |
| `wall_clock_stopped` | 4 | 3 | Upper wall |
| `fire_extinguisher` | 22 | 6 | Lower wall |
| `first_aid_cabinet` | 25 | 4 | Wall-mounted |
| `trash_bin` | 19 | 9 | Floor |
| `mop_bucket` | 28 | 9 | Floor |
| `drinking_fountain` | 31 | 6 | Wall-backed, flush to floor line |
| `chair_toppled` | 34 | 9 | Floor |
| `intercom_broken` | 31 | 3 | Upper wall |
| `classroom_plaque` | 8 | 3 | Upper wall, above door |
| `notice_board_torn` | 37 | 4 | Wall-mounted |

The 2×2-tile rectangles are in bounds, do not overlap, and leave the spawn tile `(2, 8)` clear. Floor props start one row below the player's foot line. Check the actual silhouettes during a walk-through to confirm the props don't hide the player or read as blockers.

**Godot Integration Checks**
1. **Scale and anchor:** Check that each region renders at 32×32 world pixels, from the expected top-left, with no inherited scale or half-sprite offset. Check nearest filtering at the native viewport.
2. **Draw order:** Check that the wall and floor render behind props, and that props don't cover the player or playable cues. If Y sorting is enabled, the helper's top-left origin is not a floor-contact sort point; don't rely on it to keep the player readable.
3. **Viewport visibility:** Verify the actual camera bounds at spawn and after walking right. A correct world position doesn't guarantee visibility if camera limits, smoothing, or zoom change the settled view.

**Assertion Plan**
- **References and art:** Assert that the names driving placement match the 15 names above exactly, each once, and that each resolves to its intended, unique 32×32 region in the final atlas and produces a visible `Sprite2D` at the table position. Reject `PROP-01_school.png` as a final source. Check each replacement region for a transparent background, binary alpha, at most 16 semantic `master.gpl` colors, no `c00_void` or `c13`/`c14`/`c15` on visible pixels, and `c31_dead_black` for embedded outlines.
- **Shot coverage:** Capture the opening view at camera center x=192 and a settled right-end view at x=448. Assert the measured horizontal intervals cover `[0, 384)` and `[256, 640)`, and that every prop rectangle is fully inside at least one shot. Check both captures for readability. These two shots cover all corridor columns; to prove coverage of every pixel of the full 640×224 world, use both x views with both vertical intervals `[0, 216)` and `[8, 224)`, since the viewport is 8 pixels shorter than the world.

No files were edited, and the project was not run.