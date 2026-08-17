# Authoring Reference Standard Drawings

Each DWG file in the standards folder represents one standard. **The file name
is the standard's name**: `pacific.dwg` produces suggestions like
"MATCH PACIFIC". Everything lives in **model space**, drawn in **inches**
(architectural units — the same units your production drawings use).

## 1. The nominal outline (required)

Draw the standard's exact nominal shape as **one closed polyline** (PLINE with
arcs for the rounded corners, or use FILLET on a polyline) on layer
**`STD-NOMINAL`**.

- If you skip the layer, the plugin falls back to the largest closed polyline
  that is not on the TOLERANCE layer — but use the layer; it's unambiguous.
- Use polylines and arcs only. Do **not** use SPLINE or ELLIPSE for corners —
  those are unsupported and the file will be skipped with a warning.
- A plain circle standard is fine: draw a CIRCLE on `STD-NOMINAL`.

## 2. Tolerances (optional — three ways, in priority order)

### a) Tolerance envelope geometry (most control)

On layer **`TOLERANCE`**, draw the MIN and MAX acceptable outlines:

1. `OFFSET` the nominal outline **inward** by the allowed shrink.
2. `OFFSET` the nominal outline **outward** by the allowed growth.
3. Move both results to layer `TOLERANCE`.

**Rules that make this work:**
- Create them with OFFSET so the vertex/element count matches the nominal
  exactly. Do not add, delete, or move vertices afterward.
- The plugin tells MIN from MAX by area (smaller = MIN).
- A **single** outline on TOLERANCE is treated as a symmetric band (its
  deviation from nominal is applied to both sides).
- If the element counts don't match the nominal, the file still works — the
  plugin warns and falls back to (b) or (c).

For a circle standard, draw one or two tolerance CIRCLEs instead.

### b) TOL= text (simplest)

Put a TEXT or MTEXT on layer `TOLERANCE` reading, for example:

    TOL=0.5 ATOL=2

- `TOL=` — uniform length **and** radius tolerance, ± inches.
- `ATOL=` — angle tolerance, ± degrees (optional).

### c) Nothing

Global defaults apply (configure in `src/acady-config.lsp`):
length ±1/4", radius ±6", angle ±2°.

> Note: the fuzzy "POSSIBLE ..." suggestions (Tier 2) always allow at least
> the global tolerances, so an 8'-6" standard corner flags candidate radii
> anywhere in the 8'-0"–9'-0" range even if the drawn envelope is tighter.
> The drawn envelope governs the strict full-shape MATCH verdict.

## 3. What's ignored

Dimensions, notes, title blocks, hatches, and anything on other layers are
ignored. Keep them if they help humans read the file.

## 4. After editing a standard

Just save. The plugin caches parsed standards (`acady-cache.dat` in the
standards folder) and re-parses a file automatically when its timestamp or
size changes. Use the dialog's **Rescan Standards** button to force a full
rebuild.

## 5. Converting the shipped test fixtures

The repo ships `test/dxf/pacific.dxf` and `test/dxf/atlantic.dxf`. ObjectDBX
reads DWG only, so one-time per fixture: OPEN the DXF in AutoCAD → `SAVEAS` →
DWG → into your standards folder.
