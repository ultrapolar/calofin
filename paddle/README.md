# PADDLE — perimeter pad placer (AutoLISP)

`PADDLE` scans the perimeter of a drawing for concave features that
require pads and inserts pad blocks centered on the affected areas.
Two pad sizes are available at the prompt: the standard **24″ × 24″**
pad (`Pad24x24`) and a bigger **3′ × 3′** pad (`Pad36x36`) for bigger
locations. Pads are always inserted square to the drawing — parallel
to the X and Y axes.

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
3. Pick the pad size — `24` (default) or `36` for bigger locations.
4. Select the perimeter geometry (polylines, lines, arcs — any mix)
   — or just press **Enter** and PADDLE auto-detects the perimeter
   as the largest closed loop it can find in the current tab.

PADDLE reports what it found, e.g.:

```
PADDLE: inserted 5 pad(s) on layer "PADS" (2 at inside corners, 3 along concave arcs).
```

Everything inserted in one run is a single undo step.

## Pad placement details

* **Inside corners:** the pad is centered on the corner vertex.
* **Concave arcs:** as few pads as possible, placed where they
  matter most. The first pad is centered on the **middle of the
  radius** — that part is always covered. More pads then march
  outward toward both ends of the arc, each exactly one pad-size on
  center from the last (36″ o.c. for the 3′ pad, 24″ o.c. for the
  2′), so the row touches edge-to-edge without overlapping and
  stair-steps into a blocky representation of the curve. Marching
  stops when the leftover end of the arc is too short for another
  flush pad — the extreme ends of the radius are allowed to stay
  uncovered. Every pad center sits on the perimeter.
* Pads are inserted at 0° — parallel to the X/Y axes. (Set
  `*paddle-align*` to `T` at the top of the lisp if you ever want
  them rotated to follow the perimeter edge instead.)
* Pads land on layer **PADS** (created if missing).
* A connection point only counts as a corner when the direction
  changes by **more than 10°** (`*paddle-angtol*`). Anything
  sufficiently close to a straight line — segmented walls, slight
  drafting kinks, the tangent joints of a fillet — is passed over
  without a pad.

## Loose-geometry chaining

Segment ends are considered connected when they are within
`*paddle-fuzz*` (default 0.05″) of each other, in any order and
regardless of which way each line/arc was drawn. Chains that never
close back on themselves are skipped with a warning — if that
happens, check the perimeter for gaps (or bump `*paddle-fuzz*`).
When several closed loops are selected, each one is processed;
auto-detect (Enter) uses only the largest loop.

## The pad blocks

PADDLE finds the chosen pad block (`Pad24x24` or `Pad36x36`) in this
order:

1. A definition already in the drawing.
2. Imported from `24inpad.dwg` (included in this folder) if AutoCAD
   can find it — add this folder to *Options → Files → Support File
   Search Path*, or copy `24inpad.dwg` next to your drawing. All
   block definitions in that file are imported at once.
3. As a last resort it creates a plain square block of the right
   size so the command always works; a message tells you when this
   happened.

The size → block-name mapping lives in `*paddle-sizes*` at the top
of the lisp, so pointing a size at a different block (or adding a
third size) is a one-line change.

The block's base point doesn't matter — PADDLE measures the block's
extents once per run and centers pads by their true footprint.

## Assumptions / configuration

Drawing units are assumed to be **inches** (architectural). The
constants at the top of `PADDLE.lsp` are easy to change:

```lisp
(setq *paddle-sizes* '((24 . "Pad24x24")   ; available pad sizes
                       (36 . "Pad36x36")))
(setq *paddle-maxrad* 54.0)        ; 4'-6" concave-radius threshold
(setq *paddle-layer*  "PADS")      ; insertion layer
(setq *paddle-align*  nil)         ; nil = pads parallel to X/Y axes
(setq *paddle-fuzz*   0.05)        ; gap tolerance when chaining
(setq *paddle-angtol* (/ (* 10.0 pi) 180.0)) ; min corner deviation
```

Supported perimeter geometry: **LWPOLYLINE, 2D POLYLINE, LINE, ARC**
in any combination — the loop just has to close. (3D/mesh polylines
are ignored.)
