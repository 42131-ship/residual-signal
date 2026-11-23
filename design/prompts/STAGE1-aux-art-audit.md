# aux · Stage 1 adversarial art/spec audit

You are the external-review seat (claude-opus-5-5). Review this asset plan against the frozen `design/PIXEL_SPEC.md`; do not author production code or draw assets. Identify omissions that would cause rework, and give hard reject criteria.

Facts:
- 2D side-scrolling post-collapse school corridor, Day 3 blackout; 384x216 viewport; 16px grid; each environmental prop is its own transparent 32x32 PNG.
- Exact roster: locker_bank, door_broken, desk_flipped, window_night, light_dead, wall_clock_stopped, fire_extinguisher, first_aid_cabinet, trash_bin, mop_bucket, drinking_fountain, chair_toppled, intercom_broken, classroom_plaque, notice_board_torn.
- Frozen palette uses semantic colors in `art/palettes/master.gpl`; objects may not use c00_void as opaque fill; c31_dead_black is the only embedded near-black outline; Day 3 props must not use warm c13/c14/c15; no dither, gradient, or semi-alpha; per-frame <=16 colors; 1x three-second silhouette recognition rule.
- Old `PROP-01_school.png` is only a prototype: opaque void background, approximate color roles and an amber window dot. It is excluded from final stage.
- Reference research: The Escapists 2 art director interview supports 32x32 assets, limited tones, iterative dressing, and warns against clutter; CONSCRIPT's dev blog supports environmental storytelling through abandoned belongings and remnants; Replaced's interview supports believable grounded staging and selective cinematic focus.

Return:
1. Top 8 reject conditions, ordered by severity.
2. A minimal verification matrix that catches palette-role errors, alpha, per-sprite counts, placement conflicts, and 1x silhouette failure.
3. One blind spot in the proposed roster.
Do not claim to inspect files or run commands.
