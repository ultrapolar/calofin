# PADDLE — perimeter pad placer (AutoLISP)

`PADDLE` scans the perimeter of a drawing for concave features that
require pads and inserts **36″ × 36″** pad blocks (`Pad36x36`)
centered on the affected areas. Pads are always inserted square to
the drawing — parallel to the X and Y axes — and never overlap one
another: where features crowd together, pads sit flush alongside
each other instead.

The perimeter can be a single closed polyline, but PADDLE is generous
about input: loose LINEs and ARCs (or a mix of polylines, lines and
arcs) are chained end-to-end into closed loops automatically, so it
still works when someone forgot to join the outermost perimeter into
a polyline.

## Pad specification

| Perimeter feature | Pads? |
| --- | --- |
| Concave arc / inside fillet with radius **4′-6″ (54″) or less**, bending more than 10° in total — all the way down to a sharp corner | **Yes** — a flush row of pads along the arc |
| Concave intersection of straight segments bending **more than 10°** | **Yes** — one pad centered on the corner |
| Semi-straight geometry — connection points or arcs whose total bend is 10° or less | No |
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

## New users: TUTORIALPADDLE

Type `TUTORIALPADDLE` for a guided tour. It first lists everything
PADDLE checks (perimeter input and chaining, the >10° semi-straight
rule, the 4′-6″ radius rule, the no-collision rule, where pads land).
Then it offers a **live demonstration**: it draws a labelled sample
perimeter that has one of everything — a 2° kink (ignored), convex
corners (ignored), a slot with two inside corners (padded), a concave
4′-0″ radius (padded row) and a concave 6′-0″ radius (too big —
exempt) — and then runs
the real pad-placing pipeline on it step by step, pausing so you can
watch each rule fire. At the end it offers to erase the demo again.

## Revisions

`PADDLE.lsp` carries the auto-stamped banner `(setq *paddle-version*
"v1.2")` that `tools/release_lisp.py` reads; run it after any change
and the dated twin `releases/PADDLE_MMDDYY_REV12.lsp` regenerates
itself. Bump the banner with every revision.

PADDLE reports what it found, e.g.:

```
PADDLE: inserted 5 36" pad(s) on layer "PADS" (2 at inside corners, 3 along concave arcs).
```

Everything inserted in one run is a single undo step.

## Pad placement details

* **Inside corners:** the pad is centered on the corner vertex.
* **Concave arcs:** as few pads as possible, placed where they
  matter most. The first pad is centered on the **middle of the
  radius** — that part is always covered. More pads then march
  outward toward both ends of the arc, each exactly 36″ on center
  from the last, so the row touches edge-to-edge without overlapping
  and stair-steps into a blocky representation of the curve.
  Marching stops when the leftover end of the arc is too short for
  another flush pad — the extreme ends of the radius are allowed to
  stay uncovered. Every pad center sits on the perimeter.
* **No collisions:** pads from neighbouring features (a corner next
  to a curve, two close corners, a narrow notch) are checked against
  each other. A pad on a sharp point is the anchor — its center
  stays exactly on that point, always. The pads along curves do the
  dodging: one that would overlap an already-placed pad slides along
  one axis to sit flush alongside it (exactly 36″ on center), and
  one whose spot is already covered by a neighbour is dropped. The
  command reports how many were merged this way.
* Pads are inserted at 0° — parallel to the X/Y axes. (Set
  `*paddle-align*` to `T` at the top of the lisp if you ever want
  them rotated to follow the perimeter edge instead.)
* Pads land on layer **PADS** (created if missing).
* A feature only counts when its total direction change is **more
  than 10°** (`*paddle-angtol*`) — that applies to connection points
  and to arcs alike. Anything sufficiently close to a straight line —
  segmented walls, slight drafting kinks, shallow sweeping curves,
  the tangent joints of a fillet — is passed over without a pad.

## Loose-geometry chaining

Segment ends are considered connected when they are within
`*paddle-fuzz*` (default 0.05″) of each other, in any order and
regardless of which way each line/arc was drawn. Chains that never
close back on themselves are skipped with a warning — if that
happens, check the perimeter for gaps (or bump `*paddle-fuzz*`).
When several closed loops are selected, each one is processed;
auto-detect (Enter) uses only the largest loop.

`POOLPERIM` (`lisp/poolperim/`) carries a port of this chaining and
uses it the other way round: it takes the largest closed loop as the
perimeter, redraws it as one polyline on `POOL`, erases everything
else bar the dimensions worth keeping, and then runs PADDLE on what
is left. It also closes an almost-closed trace rather than skipping
it. `tests/test_poolperim.py` runs both implementations on the same
geometry, so a change here has to be ported there.

## The pad block

PADDLE finds the pad block (`Pad36x36`) in this order:

1. A definition already in the drawing.
2. Imported from `24inpad.dwg` (included in this folder) if AutoCAD
   can find it — add this folder to *Options → Files → Support File
   Search Path*, or copy `24inpad.dwg` next to your drawing. All
   block definitions in that file are imported at once.
3. As a last resort it creates a plain square block of the right
   size so the command always works; a message tells you when this
   happened.

The block name lives in `*paddle-blkname*` at the top of the lisp,
so pointing PADDLE at a different block is a one-line change.

The block's base point doesn't matter — PADDLE measures the block's
extents once per run and centers pads by their true footprint.

## Assumptions / configuration

Drawing units are assumed to be **inches** (architectural). The
constants at the top of `PADDLE.lsp` are easy to change:

```lisp
(setq *paddle-blkname* "Pad36x36") ; the pad block
(setq *paddle-padsize* 36.0)       ; pads are 36" x 36"
(setq *paddle-maxrad*  54.0)       ; 4'-6" concave-radius threshold
(setq *paddle-layer*   "PADS")     ; insertion layer
(setq *paddle-align*   nil)        ; nil = pads parallel to X/Y axes
(setq *paddle-fuzz*    0.05)       ; gap tolerance when chaining
(setq *paddle-angtol* (/ (* 10.0 pi) 180.0)) ; semi-straight cutoff
```

Supported perimeter geometry: **LWPOLYLINE, 2D POLYLINE, LINE, ARC**
in any combination — the loop just has to close. (3D/mesh polylines
are ignored.)
