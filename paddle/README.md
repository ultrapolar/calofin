# PADDLE — perimeter pad placer (AutoLISP)

`PADDLE` scans the perimeter of a drawing for concave features that
require pads and inserts 24″ × 24″ pad blocks (`Pad24x24`, from
`24inpad.dwg`) centered on the affected areas.

The perimeter can be a single closed polyline, but PADDLE is generous
about input: loose LINEs and ARCs (or a mix of polylines, lines and
arcs) are chained end-to-end into closed loops automatically, so it
still works when someone forgot to join the outermost perimeter into
a polyline.

## Pad specification

| Perimeter feature | Pads? |
| --- | --- |
| Concave arc / inside fillet with radius **4′-6″ (54″) or less** — all the way down to a sharp corner | **Yes** — pads spaced every ≤ 24″ along the arc |
| Concave intersection of straight segments (inside corner, e.g. 90°) | **Yes** — one pad centered on the corner |
| Concave arc with radius **greater than 4′-6″** | No |
| Convex corners and convex arcs | No |

"Concave" is judged from the interior of the closed loop, so it
works the same whether the perimeter was drawn clockwise or
counter-clockwise, and arc geometry is read straight from polyline
bulges or ARC entities.

## Usage

1. Load `PADDLE.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `PADDLE`.
3. Select the perimeter geometry (polylines, lines, arcs — any mix)
   — or just press **Enter** and PADDLE auto-detects the perimeter
   as the largest closed loop it can find in the current tab.

PADDLE reports what it found, e.g.:

```
PADDLE: inserted 5 pad(s) on layer "PADS" (2 at inside corners, 3 along concave arcs).
```

Everything inserted in one run is a single undo step.

## Pad placement details

* **Inside corners:** the pad is centered on the corner vertex.
* **Concave arcs:** pads are distributed evenly along the arc
  (`ceil(arc length / 24″)` of them), each centered on the arc
  itself.
* Pads rotate to follow the perimeter edge. Set `*paddle-align*` to
  `nil` at the top of the lisp if you want every pad inserted at 0°.
* Pads land on layer **PADS** (created if missing).
* Corners flatter than 1° are treated as straight-through (so the
  tangent joints of a fillet don't double-count as corners).

## Loose-geometry chaining

Segment ends are considered connected when they are within
`*paddle-fuzz*` (default 0.05″) of each other, in any order and
regardless of which way each line/arc was drawn. Chains that never
close back on themselves are skipped with a warning — if that
happens, check the perimeter for gaps (or bump `*paddle-fuzz*`).
When several closed loops are selected, each one is processed;
auto-detect (Enter) uses only the largest loop.

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
(setq *paddle-fuzz*    0.05)       ; gap tolerance when chaining
```

Supported perimeter geometry: **LWPOLYLINE, 2D POLYLINE, LINE, ARC**
in any combination — the loop just has to close. (3D/mesh polylines
are ignored.)
