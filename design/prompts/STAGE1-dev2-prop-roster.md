# dev2 · Stage 1 environmental roster review

You are the content/schema seat (gpt-6.2-astra). Independently audit whether the exact 15-prop school-corridor roster below tells a coherent evacuation/interruption story without becoming clutter. Do not edit files, do not generate pixels, and do not invent gameplay fields.

Current game: 2D side-scrolling post-collapse survival, school corridor, Day 3 blackout. Native viewport 384x216, world is 40 tiles wide x 14 high, tiles are 16px. Props are individual 32x32 transparent sprites. Player starts at tile (2,8), walks horizontally along floor row 8. Frozen palette: 32 semantic colors in `master.gpl`. Day 3 environmental props may not use warm `c13/c14/c15`; only flashlight and gun muzzle may use those.

Current five assets: locker_bank, door_broken, desk_flipped, window_night, light_dead. Proposed ten additions:
wall_clock_stopped, fire_extinguisher, first_aid_cabinet, trash_bin, mop_bucket, drinking_fountain, chair_toppled, intercom_broken, classroom_plaque, notice_board_torn.

Review for:
- Redundancy and missing high-value school silhouettes (e.g., desks, lockers, safety equipment, wayfinding, ordinary personal belongings).
- A narrative beat for the corridor, communicated through object state/placement rather than added text or gore.
- Whether the prop set is too visually dense for the 384x216 viewport; identify which assets should be sparse or repeated variants rather than unique clutter.
- Return a prioritized checklist of pass/fail criteria. Do not claim any asset was rendered or validated.
