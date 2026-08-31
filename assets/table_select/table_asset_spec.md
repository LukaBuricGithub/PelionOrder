# SVG asset brief — "Odabir stola" (table-selection) screen, Pelion Order (Flutter app)

You are generating **static SVG art** for a Flutter screen. The screen is a top-down, flat, architectural floor-plan look: grey tables with chairs on a plain floor, inside a walled room. Deliver **SVG only**. The app draws all text and status colors at runtime — do NOT put text or status colors in the SVGs.

## KEY LAYOUT REQUIREMENTS (these drive the whole asset design — read first)
- **Dynamic column count.** The number of tables per row is chosen at runtime by a user setting: **small = 4 per row, medium = 3 per row, large = 2 per row.** The SAME table sprite is reused at every column count. → This is WHY the sprite must be a **square** with equal padding: it has to tile cleanly into a grid of any column count and any cell size (from ~50 px wide up to ~200 px).
- **Variable table count + vertical scrolling.** A venue may have few or MANY tables. The grid **scrolls vertically** when there are more tables than fit on screen. → This is WHY the walls are a **fixed nine-slice bezel with a transparent center**: the frame stays put on screen while the floor + tables scroll inside it. The frame must NOT try to enclose a fixed number of tables.
- **One sprite, one frame, any layout.** Do not design for a specific table count or a specific grid (e.g. the "12 tables" mock is just an example). Assets must work for 3 tables or 60, in 2/3/4 columns, on phones and tablets.

## Golden rules (apply to EVERY file)
- **Flat SVG, flutter_svg-safe:** NO `<style>`/CSS, NO filters (`feGaussianBlur`, `feDropShadow`), NO `<foreignObject>`, NO external fonts or images. Allowed: `<path>`, `<rect>`, `<circle>`, `<g>`, and gradients inside `<defs>`. Bake any shadow as a soft semi-transparent shape.
- **Transparent background** — no opaque full-canvas fill rectangle.
- **Self-contained** — one file per asset, no external references. Optimize/minify.

---

## COMPONENT 1 — Table sprite  (REQUIRED)
A single generic top-down table with chairs. One file only (no seat-count variants — there is no seat data).

- **File:** `table_sprite.svg`
- **Canvas:** SQUARE `viewBox`, e.g. `0 0 240 240`. Square is mandatory.
- **Composition:** table centered, chairs in the outer margin, EQUAL transparent padding on all four sides.
- **Table top:** ONE rounded-square shape occupying the **central ~60%** (20% inset on each side). On a 240 canvas that is `x=48 y=48 width=144 height=144 rx=18`.
- **Tinting (critical):** give ONLY the table-top shape `fill="currentColor"`. The app recolors just the table top per status. EVERYTHING else uses fixed neutral hex colors.
- **Chairs / outlines:** fixed neutral hex (your choice). Suggested: chairs fill `#E6E9ED`, stroke `#D3D8DE`.
- **Text:** NONE. The app draws the number/name/count on the table top.
- **Strokes:** in user units so they scale with the sprite (note it if you instead want constant hairlines via `vector-effect="non-scaling-stroke"`).
- **Legibility:** must read cleanly from ~50 px (small tiles) up to ~200 px (large tiles). Keep detail density moderate.

---

## COMPONENT 2 — Nine-slice wall frame
The room walls are a FIXED bezel; the table grid scrolls inside them. A single stretched frame would distort, so deliver it nine-sliced. Deliver 8 files:

- `corner_tl.svg`, `corner_tr.svg`, `corner_bl.svg`, `corner_br.svg` — square, ~`64×64` dp. ALL ornament (rounded corners, columns, door jambs) lives in the corners. Never stretched.
- `edge_top.svg`, `edge_bottom.svg` — horizontal strips that TILE seamlessly left↔right. Fixed height = wall thickness (~`22` dp). Plain straight wall (no ornament).
- `edge_left.svg`, `edge_right.svg` — vertical strips that TILE seamlessly up↕down. Fixed width = wall thickness (~`22` dp). Plain straight wall.
- **Center:** transparent (floor + tables show through).
- **Join rule:** edge thickness MUST equal the corner's arm thickness (~22 dp) so seams line up. Ornament only in corners; edges stay tileable.

**Fallback (if 8 aligned pieces is too hard):** instead deliver ONE `frame_full.svg` that is a UNIFORM-thickness rounded border (detail only near the corners) designed to be stretched to the screen — a uniform border shows no visible distortion.

---

## COMPONENT 3 — Floor
No asset. The app fills a flat color (defaults `#F4F6F8` light / `#10151C` dark). Only provide a preferred hex if you have one.

---

## How the app uses the assets (design to this; you do NOT build it)
- **Grid columns** from a size setting: small = 4/row, medium = 3/row, large = 2/row. Cells are SQUARE, so the square sprite fits exactly.
- **Scrolling:** more tables than fit → vertical scroll. The floor scrolls; the wall frame stays fixed.
- **Portrait-locked**, everything device-scaled (bigger tablets → proportionally bigger tables + text).
- **Status → table-top color** (applied by the app via `currentColor`; the sprite's table top must look good tinted from pale grey to saturated):
  - Slobodan (free) = light grey `#D8DEE4`
  - Zauzet / occupied by another waiter = `#D46A5A`
  - Vaš / yours = `#4A78B4`
  - Nije poslano / unsent = `#E0A94A`
- **Text on the table top** (drawn by the app, centered in the 60% zone): table **number** (large/hero), **naziv/name** (one line, auto-fit then "…"), **item count** ("N stavke").
  - large & medium: number + naziv + item count.
  - small (4/row): naziv is DROPPED (top too small) → number + item count only.

## Deliverables checklist
1. `table_sprite.svg` — REQUIRED (unblocks the whole build on its own).
2. Wall frame — either the 8 nine-slice pieces OR the `frame_full.svg` uniform-border fallback.
3. Floor color hex (optional; defaults given).
4. Every file passes the flat-SVG check (no CSS/filters/foreignObject/external refs) and renders identically in flutter_svg.
