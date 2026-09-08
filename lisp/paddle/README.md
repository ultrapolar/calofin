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
| Concave intersection of straight segments bending **more than 30°** | **Yes** — one pad centered on the corner |
| Semi-straight geometry — a connection point bending 30° or less, or an arc whose total bend is 10° or less | No |
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
   Highlighting the perimeter *before* step 2 skips this prompt: a
   pickfirst selection is taken as-is.

## New users: TUTORIALPADDLE

Type `TUTORIALPADDLE` for a guided tour. It first lists everything
PADDLE checks (perimeter input and chaining, the >30° corner rule and
the >10° arc rule, the 4′-6″ radius rule, the no-collision rule, where
pads land). Then it offers a **live demonstration**: it draws a
labelled sample perimeter that has one of everything — a 2° kink
(ignored), convex corners (ignored), a slot with two inside corners
(padded), a concave 4′-0″ radius (padded row) and a concave 6′-0″
radius (too big — exempt) — and then runs the real pad-placing
pipeline on it step by step, pausing so you can watch each rule fire. At the end it offers to erase the demo again.

## Revisions

`PADDLE.lsp` carries the auto-stamped banner `(setq *paddle-version*
"v1.5")` that `tools/release_lisp.py` reads; run it after any change
and the dated twin `releases/PADDLE_MMDDYY_REV15.lsp` regenerates
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
* A feature only counts when its total direction change clears its
  tolerance, and a corner is judged harder than a curve: a connection
  point has to bend **more than 30°** (`*paddle-cornertol*`) to be an
  inside corner, while an arc is a feature once its total bend is
  **more than 10°** (`*paddle-arctol*`). Anything sufficiently close
  to a straight line — segmented walls, slight drafting kinks,
  shallow sweeping curves, the tangent joints of a fillet — is passed
  over without a pad.

A **pickfirst** selection is taken as-is: highlight the perimeter
before typing `PADDLE` and it never asks. `LINGUTTER` hands its
freshly drawn perimeter over that way, which matters because
auto-detect reads the *whole* drawing for its largest closed loop and
would otherwise be as happy with a title block border.

## Loose-geometry chaining

Segment ends are considered connected when they are within
`*paddle-fuzz*` (default 0.05″) of each other, in any order and
regardless of which way each line/arc was drawn. Chains that never
close back on themselves are skipped with a warning — if that
happens, check the perimeter for gaps (or bump `*paddle-fuzz*`).
When several closed loops are selected, each one is processed;
auto-detect (Enter) uses only the largest loop.

`LINGUTTER` (`lisp/lingutter/`) does not chain at all. It walks the
**outer face** of the highlighted geometry — hardest right turn at every
node — so interior geometry is never stepped onto and an outline with a
gap in it fails loudly rather than being replaced by whatever else
happened to close. It redraws that exterior as one polyline on `POOL`,
erases everything else it was shown bar the dimensions worth keeping,
and hands the polyline to PADDLE as a pickfirst selection. It does share
this file's segment readers (`paddle--ent-segs` and friends), ported
under `lg:`, and `tests/test_lingutter.py` runs both on the same
geometry so those cannot drift.

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

| Knob | Default | What it does |
| --- | --- | --- |
| `*paddle-blkname*` | `"Pad36x36"` | Block inserted at every pad spot. `24inpad.dwg` ships `Pad36x36` and `Pad24x24`; if you switch, set `*paddle-padsize*` to match |
| `*paddle-padsize*` | `36.0` | Edge of the pad in drawing units. Sets the pitch of the flush rows along arcs, the collision distance in the dodge pass, the fallback square block, and the wording of every message that quotes it |
| `*paddle-blkfile*` | `"24inpad.dwg"` | The dwg the block definitions are imported from when the drawing lacks them (found via the support path) |
| `*paddle-layer*` | `"PADS"` | Layer pads land on. Created when missing; thawed, unlocked and turned on when not |
| `*paddle-layer-color*` | `7` | Colour index the layer is created with. An existing layer keeps its own |
| `*paddle-align*` | `nil` | `nil` = pads parallel to the X/Y axes; `T` = rotated to follow the perimeter edge |
| `*paddle-maxrad*` | `54.0` | Largest concave radius (4′-6″) that still needs pads |
| `*paddle-cornertol*` | 30° | A joint has to bend **more than** this, into the pool, to be a sharp inside corner. Edit the `30.0` in its line; the rest converts to radians |
| `*paddle-arctol*` | 10° | A concave arc has to bend **more than** this in total to be a feature. Judged separately from corners on purpose |
| `*paddle-fuzz*` | `0.05` | Largest gap that still counts as touching when chaining loose lines and arcs; shorter segments are dropped as slivers |
| `*paddle-demo-layer*` / `*paddle-demo-color*` | `"PADDLE-DEMO"` / `3` | Where `TUTORIALPADDLE` draws its sample perimeter, and in what colour |

Nothing below the settings block is meant to be edited to change
behaviour.

Supported perimeter geometry: **LWPOLYLINE, 2D POLYLINE, LINE, ARC**
in any combination — the loop just has to close. (3D/mesh polylines
are ignored.)
