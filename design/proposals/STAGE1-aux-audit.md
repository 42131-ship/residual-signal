# Stage 1 Audit: Asset Plan vs. PIXEL_SPEC.md

## 1. Top 8 Reject Conditions (by severity)

1. **c00_void used as opaque fill in any prop** — Immediate corruption of transparency layering. c00_void is reserved for true transparency only; any solid region must use c31_dead_black or semantic colors.

2. **Day 3 prop using warm palette (c13/c14/c15)** — Temporal ruleset violation. Day 3 is blackout context; warm tones belong to Day 1/2 only. No amber, no warmth.

3. **Per-frame color count >16** — Hard transport constraint. Palette overflow breaks the 16-color-per-sprite budget and violates the master.gpl semantic allocation.

4. **1x three-second silhouette test failure** — Functional reject. If a prop cannot be identified as its intended object type within three seconds at 1x scale in pure black silhouette, it fails the clarity baseline.

5. **Semi-transparent alpha (0 < alpha < 255)** — No dither, no gradient, no semi-alpha rule. Only binary transparency (0 or 255). Anti-aliasing or soft edges violate the hard-edge constraint.

6. **c31_dead_black used for anything except embedded outline** — Semantic misuse. c31 is the near-black outline color; interior fills, shadows, or large regions must use semantic palette roles (c21–c24 for neutral/metal, etc.).

7. **Non-transparent 32x32 PNG (opaque background baked in)** — Layering failure. Each prop must be a standalone transparent asset for flexible placement over corridor base tiles. Opaque backgrounds replicate the prototype mistake.

8. **Dither, gradient, or smooth tone transitions present** — Style violation. Flat semantic fills only. Any interpolation between palette entries breaks the hard-edge post-collapse aesthetic.

---

## 2. Minimal Verification Matrix

| Check | Method | Pass Criterion |
|-------|--------|----------------|
| **Palette role** | Sample 5 random interior pixels per prop | No c00_void in opaque regions; no c13/c14/c15 in any Day 3 prop; c31_dead_black only in 1px outlines |
| **Alpha binary** | Scan alpha channel histogram | Only values 0 and 255 present; no intermediate alpha values |
| **Per-sprite color count** | Unique color tally per PNG | ≤16 distinct RGBA values per asset |
| **Transparency** | Corner pixel inspection | All four corners are c00_void (fully transparent); no opaque background |
| **1x silhouette** | Flatten to black at 32x32, 3-second timed ID | External reviewer correctly names object type within 3s |
| **Placement conflict** | Overlay all 15 props on 16px grid at typical spacing | No two props obscure each other's key recognition feature when placed 32–48px apart |
| **Outline consistency** | Measure outline stroke width | c31_dead_black outlines are exactly 1px; no thicker or doubled lines |
| **No interpolation** | Edge pixel sampling | All color transitions are hard boundaries; no mid-tone pixels between semantic colors |

---

## 3. One Blind Spot in Proposed Roster

**Absence of a narrative anchor prop with legible text or recognizable institutional branding.**

The 15-prop roster includes environmental dressing (furniture, utilities, damaged infrastructure) but lacks a single item that clearly establishes *what kind of school this was* or *when it fell*. 

- `classroom_plaque` and `notice_board_torn` are mentioned but not specified for content. If these carry illegible scribbles or generic geometry, they become redundant clutter rather than environmental storytelling anchors.
- CONSCRIPT's dev blog and Replaced's interview both emphasize *selective cinematic focus* and *abandoned belongings that tell a story*. A single prop with a date, school name fragment, or recognizable warning sign (in Japanese characters, stylized but readable at 1x) would ground the corridor in its collapse context.

**Risk:** Without this anchor, the corridor reads as "generic abandoned building" rather than "post-collapse school, Day 3 blackout." The roster dresses the space but does not *place* it in the game's temporal and narrative reality.

**Mitigation check:** Confirm that either `classroom_plaque` or `notice_board_torn` carries a legible, setting-specific detail (e.g., "3-A" classroom marker, evacuation route fragment, or date stamp) that survives 1x silhouette recognition as *text-bearing object*, not just *rectangle on wall*.