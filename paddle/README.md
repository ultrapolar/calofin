# PADDLE — perimeter pad placer (AutoLISP)

`PADDLE` scans the perimeter of a drawing (a closed polyline) for
concave features that require pads and inserts 24″ × 24″ pad blocks
(`Pad24x24`, from `24inpad.dwg`) to cover the affected areas.

## Pad specification

| Perimeter feature | Pads? |
| --- | --- |
| Concave arc / inside fillet with radius **4′-6″ (54″) or less** — all the way down to a sharp corner | **Yes** — pads spaced every ≤ 24″ along the arc |
| Concave intersection of straight segments (inside corner, e.g. 90°) | **Yes** — one pad nestled into the corner |
| Concave arc with radius **greater than 4′-6″** | No |
| Convex corners and convex arcs | No |

"Concave" is judged from the interior of the closed polyline, so it
works the same whether the perimeter was drawn clockwise or
counter-clockwise, and arcs are read straight from the polyline's
bulge values.

## Usage

1. Load `PADDLE.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `PADDLE`.
3. Select the perimeter polyline(s) — or just press **Enter** and
   PADDLE auto-detects the perimeter as the largest closed polyline
   in the current tab.

PADDLE reports what it found, e.g.:

```
PADDLE: inserted 5 pad(s) on layer "PADS" (2 at inside corners, 3 along concave arcs).
```

Everything inserted in one run is a single undo step.

## Pad placement details

* **Inside corners:** the pad is nestled into the corner — for a 90°
  corner it sits exactly in the corner with its sides against both
  edges.
* **Concave arcs:** pads are distributed evenly along the arc
  (`ceil(arc length / 24″)` of them) with each pad centered 12″
  inside the perimeter so it covers the material band along the arc.
* Pads rotate to follow the perimeter edge. Set `*paddle-align*` to
  `nil` at the top of the lisp if you want every pad inserted at 0°.
* Pads land on layer **PADS** (created if missing).
* Corners flatter than 1° are treated as straight-through (so the
  tangent joints of a fillet don't double-count as corners).

## The Pad24x24 block

PADDLE finds the block in this order:

1. A `Pad24x24` definition already in the drawing.
2. Imported from `24inpad.dwg` (included in this folder) if AutoCAD
   can find it — add this folder to *Options → Files → Support File
   Search Path*, or copy `24inpad.dwg` next to your drawing.
3. As a last resort it creates a plain 24×24 square block so the
   command always works; a message tells you when this happened.

The block's base point doesn't matter — PADDLE measures the block's
extents once per run and centers pads by their true footprint.

## Assumptions / configuration

Drawing units are assumed to be **inches** (architectural). The
constants at the top of `PADDLE.lsp` are easy to change:

```lisp
(setq *paddle-blkname* "Pad24x24") ; pad block name
(setq *paddle-maxrad*  54.0)       ; 4'-6" concave-radius threshold
(setq *paddle-padsize* 24.0)       ; pad size
(setq *paddle-layer*   "PADS")     ; insertion layer
(setq *paddle-align*   T)          ; rotate pads with the perimeter
```

The perimeter must be a **closed LWPOLYLINE** (lines and arc
segments are both fine). Open polylines are skipped with a warning.
