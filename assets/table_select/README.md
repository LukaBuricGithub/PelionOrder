# Odabir stola — SVG assets

Place the table-selection screen art here. All files must be **SVG** and **flat / flutter_svg-safe**
(no CSS `<style>`, no filters, no `<foreignObject>`, no external refs; transparent background).
See the full brief: `table_asset_spec.md`.

## Files that go in THIS folder
- `table_sprite.svg`  — REQUIRED. One generic top-down table + chairs.
    - Square viewBox, centered, equal transparent padding.
    - Table top = central ~60%, given `fill="currentColor"` (the app tints it per status).
    - Chairs/outlines = fixed neutral hex. No text.

## Walls go in the `walls/` subfolder
See `walls/README.md`.

## Floor
No file — the app uses a flat color.
