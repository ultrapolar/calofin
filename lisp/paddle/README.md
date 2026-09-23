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
a polyline — or to close it. Geometry that would be a perimeter
except for a gap is recognised as one, arrowed at the open joint and
offered the zero fillet that closes it (see **The gap in a perimeter
that nearly closes** below).

## Pad specification

| Perimeter feature | Pads? |
| --- | --- |
| Concave arc / inside fillet with radius **4′-0″ (48″) or less**, bending more than 10° in total — all the way down to a sharp corner | **Yes** — a flush row of pads along the arc |
| Concave intersection of straight segments bending **more than 30°** | **Yes** — one pad centered on the corner |
| Semi-straight geometry — a connection point bending 30° or less, or an arc whose total bend is 10° or less | No |
| Concave arc with radius **greater than 4′-0″** | No |
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
   as the largest closed loop it can find in the space you are drawing
   in -- model space from inside a layout's viewport, not the sheet.
   Highlighting the perimeter *before* step 2 skips this prompt: a
   pickfirst selection is taken as-is.
4. If what you gave it closes except for a gap, PADDLE draws an arrow
   at every open joint and asks whether to close it with a zero
   fillet before it pads anything — **The gap in a perimeter that
   nearly closes**, below.

## New users: TUTORIALPADDLE

Type `TUTORIALPADDLE` for a guided tour. It first lists everything
PADDLE checks (perimeter input, chaining and the gap it offers to
fillet, the >30° corner rule and the >10° arc rule, the 4′-0″ radius
rule, the no-collision rule, where pads land). Then it offers a **live demonstration**: it draws a
labelled sample perimeter that has one of everything — a 2° kink
(ignored), convex corners (ignored), a slot with two inside corners
(padded), a concave 4′-0″ radius (padded row) and a concave 6′-0″
radius (too big — exempt) — and then runs the real pad-placing
pipeline on it step by step, pausing so you can watch each rule fire. At the end it offers to erase the demo again.
The demo is built from the spot you pick, in whatever UCS is current
(Enter is that UCS's origin, the `0,0` the prompt names), square to
World like the pads it draws, and the view is zoomed to frame all of it.

## Revisions

`PADDLE.lsp` carries the auto-stamped banner `(setq *paddle-version*
"v1.15")` that `tools/release_lisp.py` reads; run it after any change
and the dated twin `releases/PADDLE_MMDDYY_REV115.lsp` regenerates
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
before typing `PADDLE` and it never asks. `LINGUTTER`, `AUTODIM` and
`TYLERDRONESUITE` hand over the perimeter they already hold, which
matters because auto-detect reads the *whole* drawing for its largest
closed loop and would otherwise be as happy with a title block border.
They hand it through the global `*calofin-handoff*` -- `("PADDLE"
<selection>)`, read before the pickfirst probe and cleared at the read
and by PADDLE's error handler -- rather than as a pickfirst set, which
needs `PICKFIRST` at 1: switching it on round the call left a drafter
who works at 0 at 1 whenever PADDLE was Esc'd, because an Esc inside
PADDLE runs only PADDLE's own handler.

## The gap in a perimeter that nearly closes

A drawing says "closed perimeter" long before it is one: two walls
that overshoot each other by an inch, a polyline that stops a hair
short of its own start, a fillet somebody erased and never redrew.
PADDLE used to report that as `ignored 1 open chain(s)` and stop,
which is true and no help.

It now reads what is left over after chaining. Each open chain has two
loose ends; ends within `*paddle-gapmax*` (36″, one pad) of each other
are paired off closest-first, and the pairing is walked — across a
gap, along the chain waiting on the other side, out of its far end,
across the next gap. **When the walk arrives back where it started,
the geometry was one closed perimeter with holes punched in it**, and
PADDLE says so instead of calling it loose lines. One chain with one
gap is the everyday case; two chains and two gaps walk the same way.

For every hole it draws an **arrow** — one closed polyline, tip on the
gap, tail out on the side away from the inside of the loop — and then
asks, one gap at a time, quoting how wide it is and where:

```
PADDLE: this reads as one closed perimeter with 1 gap(s) in it, not as
loose geometry. Arrow(s) drawn on layer "PADDLE-GAP" at the open joint(s).
  gap 1 of 1: 6" wide, at 0.00,3.00
Close the gap the arrow points at with a zero fillet? [Yes/No] <Yes>:
```

* **Two ends that already cross are not asked about.** When each loose
  end has run on past the other — a wall drawn long past the curve it
  meets, two walls overshooting one corner — the perimeter is already
  there at the crossing. PADDLE trims each stub back to it (a line's
  end, an arc's end angle, an open polyline's end vertex and bulge),
  says `the two ends already cross`, and carries on. Only a stub no
  longer than `*paddle-gapmax*` is trimmed unasked, and only across two
  different lines, arcs or lightweight polylines. Anything else gets
  the question below.
* **Yes** runs `FILLET` at radius 0 on the two entities — so an
  overshoot is trimmed back and a shortfall is run on, exactly as a
  drafter would do it by hand. Each pick lands nine tenths of the way
  in from its loose end, up by the end still attached to the rest of
  the perimeter: `FILLET` keeps the side it was picked on, and a pick
  in the middle of a wall run more than half its own length past its
  neighbour would keep the overshoot and trim the perimeter. PADDLE
  then **reads the drawing again**: the perimeter that closed is the
  one it pads, and the arrow comes away with the gap.
* **No** leaves the arrow where it is and pads nothing — there is no
  closed perimeter yet. Fix it however you like and run PADDLE again;
  the next run clears the arrow if the gap has gone.
* **Esc** is No for every gap not yet answered. All the arrows go in
  before the first question for exactly that reason: what is on screen
  is the whole picture, not just the part that got as far as being
  asked about.

The arrows, the fillets and the pads are one undo step.

What a fillet did is **read back off the drawing, never assumed**.
`FILLET` refuses a pair whose ends never cross (parallel walls,
however far they run on), and PADDLE names that gap and leaves its
arrow standing rather than reporting a perimeter it has not got.

Two limits worth knowing:

* **Both ends on one entity** — the polyline somebody drew round the
  pool and never closed — is never handed to `FILLET`. Two picks on
  one polyline is not a joint to it: it joins those two segments and
  throws away everything between them, which here is the perimeter.
  An open LWPOLYLINE straight at both ends is joined **in place**
  instead, and the question is the same one: Yes moves its first
  vertex to where the two end segments cross, drops the last vertex
  and sets the closed flag — which is what the zero fillet would have
  left, done as an edit. Anything else on one entity (an arc at
  either end, a heavy 2D `POLYLINE`, two ends that never cross) is
  marked and named: close it yourself (`PEDIT` > `Close`, or pull the
  two ends together) and run PADDLE again.
* **A gap has to be the perimeter.** What it would close has to
  enclose more area than any loop that did close, or PADDLE leaves it
  alone: a drafter who already has a closed perimeter is not asked
  about a stray pair of lines lying beside it. A gap wider than
  `*paddle-gapmax*` is not a drafting gap either — that is a missing
  wall — and gets the plain `ignored N open chain(s)` report it always
  got.

The arrows are PADDLE's own marks: **every run clears layer
`PADDLE-GAP` and re-marks whatever is still open**, so an arrow never
outlives the gap it pointed at, and a run never reads its own marks
back as geometry. Put nothing else on that layer.

## Loose-geometry chaining

Segment ends are considered connected when they are within
`*paddle-fuzz*` (default 0.05″) of each other, in any order and
regardless of which way each line/arc was drawn. Chains that never
close back on themselves are skipped with a warning — unless they
nearly make a perimeter between them, which is the arrow-and-fillet
pass above. If one is skipped, check it for gaps (or bump
`*paddle-fuzz*`).
When several closed loops are selected, each one is processed;
auto-detect (Enter) uses only the largest loop.

The walk grows at **both** ends of a chain. Growing forward only would
split a perimeter with one gap in it into two open chains whenever the
walk started in the middle of it — the half ahead of the starting
segment runs into the gap, the half behind it runs into the segment
already taken — and two chains meeting at a point that is not a gap is
not what the drawing says.

`LINGUTTER` (`lisp/lingutter/`) does not chain at all. It walks the
**outer face** of the highlighted geometry — hardest right turn at every
node — so interior geometry is never stepped onto and an outline with a
gap in it fails loudly rather than being replaced by whatever else
happened to close. It redraws that exterior as one polyline on `POOL`,
erases everything else it was shown bar the dimensions worth keeping,
and hands the polyline to PADDLE through `*calofin-handoff*`. It does share
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
| `*paddle-maxrad*` | `48.0` | Largest concave radius (4′-0″) that still needs pads |
| `*paddle-cornertol*` | 30° | A joint has to bend **more than** this, into the pool, to be a sharp inside corner. Edit the `30.0` in its line; the rest converts to radians |
| `*paddle-arctol*` | 10° | A concave arc has to bend **more than** this in total to be a feature. Judged separately from corners on purpose |
| `*paddle-fuzz*` | `0.05` | Largest gap that still counts as touching when chaining loose lines and arcs; shorter segments are dropped as slivers |
| `*paddle-gapmax*` | `36.0` | Furthest apart two loose ends may be and still read as a drafting gap — one to arrow and offer a zero fillet for. Wider than this is a missing wall. One pad wide: a hole a pad would fall through is not a gap |
| `*paddle-gap-layer*` / `*paddle-gap-color*` | `"PADDLE-GAP"` / `1` | Where the gap arrows are drawn, and in what colour. A plain ACI number rather than `'auto` on purpose: red reads against any background a drafter can set, which is the one thing a mark saying "it is open HERE" has to do |
| `*paddle-arrow*` | `36.0` | Length of a gap arrow, tail to tip; its head is a third of that |
| `*paddle-demo-layer*` / `*paddle-demo-color*` | `"PADDLE-DEMO"` / `3` | Where `TUTORIALPADDLE` draws its sample perimeter, and in what colour |

Nothing below the settings block is meant to be edited to change
behaviour.

Supported perimeter geometry: **LWPOLYLINE, 2D POLYLINE, LINE, ARC**
in any combination — the loop just has to close. (3D/mesh polylines
are ignored.)
