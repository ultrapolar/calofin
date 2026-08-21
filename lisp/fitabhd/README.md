# FITABHD -- fit a TYPED pool template through surveyed points (AutoLISP / AutoCAD 2018+)

The typed sibling of [ABHD](../abhd/). ABHD traces whatever shape the
survey points make; **FITABHD** is told what kind of typical pool was
surveyed -- **Rectangle, Grecian, Roman, Oval, L, Lazy L or Round**
(POOL's own shape vocabulary) -- and *fits that type* to the points.
The name says it: it **fit**s the survey **to** the pool types ABHD
would otherwise have to discover arc by arc.

```
Command:  FITABHD      (FITABHDVER prints the loaded version)
Load:     APPLOAD -> FITABHD.lsp
```

## What it does

Knowing the type does half the work:

* **Wall directions come from the template, never from the points.** A
  rectangle's walls come out dead parallel and square; a Lazy L's bend
  walls sit at exactly 45 degrees. The survey only says *where* each
  wall is (an iterative nearest-wall fit), never what it is.
* **The rotation is found automatically** -- every survey edge votes,
  folded so parallel and perpendicular walls reinforce each other --
  and every placement the type allows is tried: four rotations for the
  arc-ended types, mirrored too for the chiral L shapes, eight
  rotations for the Lazy L. The placement that hugs the points best
  wins; one whose template collapsed (a wall fitted backwards) is
  thrown out however well it scores.
* **Corner treatments use the standard question**
  (`Square/Radius/Cut/NotGiven`) and the *size* is never asked: one
  shared fillet radius (or cut face) is measured from the points, over
  every corner that turns hard enough to measure (60 degrees or more --
  a Lazy L bend's own 45-degree kink cannot be told from its walls). A
  Rectangle with `Cut` corners rides the same eight-wall template as a
  Grecian. `NotGiven` draws square, per the standard.
* **A Grecian's cut corners may be eased.** The nominal drawing is
  sharp, but an as-built very often rounds the eight vertices where
  the cuts meet the walls. The corner question covers the Grecian too
  (subject: *the cut corners*, default `Radius`): answer `Radius` (or
  `Cut`) and one shared easing is measured over all eight 45-degree
  corners, with the corner zone sized to that gentler turn. The easing
  is kept only when it beats the sharp outline on the corner points by
  a clear margin and comes out at least 1" -- noise never invents a
  radius on a genuinely sharp pool, and a sharp answer on a rounded
  pool simply shows up as points beyond tolerance. The report prints
  it as `Corner easing radius` (or notes `none measurable - drawn
  sharp`).
* **Roman and Oval ends are found, not declared**: square-end and
  arc-end placements (one end and both ends) all compete, and a
  both-ends fit must beat a single-ended one by a clear margin --
  extra freedom is not evidence. A Roman end reports its bulge (S) and
  stubs (S1) the way POOL draws them.
* **Nice dimensions**: each headline dimension -- length, width,
  corner radius, cut face, body length -- is snapped to the first
  friendly increment (whole feet, half feet, inches, half inches) the
  points can live with; the snapped outline must stay within the run
  tolerance. **The points outrank pretty numbers**: a pool measured at
  380" stays 380", it does not become 32'.

The four questions: the pool type, the corner treatment (for
Rectangle / L / Lazy L, and for the Grecian's cut-corner vertices --
the arc-ended and round templates keep theirs square), the max
distance a point may sit from the fitted outline (capped at 2",
remembered per session), and the selection. Survey points are read
exactly as ABHD reads them: `ab_pt` block inserts on any layer, or
`POINT` entities (and other blocks) on the `POINTS` layer. Every
prompt after the first offers `Back` (`Undo` works too).

The fitted outline previews on `POOL-FIT` with a report -- the fitted
dimensions in feet-and-inches, the pool's rotation, points on the
outline / off within tolerance / beyond it, the strays ringed on
`FGStep` and named worst-first by their `number` attribute. Keep it
and it moves to the `POOL` layer in ByLayer colour, like ABHD's.
Only FITABHD's own stamped objects are ever erased from `FGStep` or
`POOL-FIT`; your geometry there is never touched.

## The pool bottom -- standard hoppers only

Where ABHD's bottom flow traces surveyed break points and offers
guided curves, FITABHD **assumes a standard hopper** and generates the
bottom square to the pool's own frame:

1. Pick a point at the **deep end** (on an L or Lazy L this picks
   which leg the hopper lives in -- the angled leg included; the
   bottom is drawn in that leg's own frame).
2. Type where the **deep break** and **shallow break** fall (distance
   from the deep end wall; feet-and-inches like `8'6` or plain inches),
   and the hopper's **side** and **back offsets** (default 18").
3. Drawn on `POOL`: the deep break as the classic three collinear
   pieces (`DASHED2` stubs from each wall, solid run between the
   hopper corners), the hopper as the offset rectangle, dead-straight
   slope lines to the shallow break's wall ends, the shallow break
   across the leg, the **K/L/M dimension string** a foot off the deep
   break on the shallow side, and one dimension on the back offset.

A **Round** pool gets a concentric hopper ring at the offset asked,
with a radius dimension.

Anything fancier than a standard hopper -- guided slopes, waypoint
offsets, surveyed break ends -- is [ABHD/ADAB](../abhd/)'s job: keep
the FITABHD perimeter and run `ADAB` over it.

## Tunables

All at the top of `FITABHD.lsp`: layers (`fit:*pool-layer*`,
`fit:*point-layer*`, `fit:*out-layer*`, `fit:*miss-layer*`), the point
block and tag (`fit:*point-block*`, `fit:*pt-tag*`), the tolerance
ceiling (`fit:*tol-max*`, 2"), the snapping increments
(`fit:*nice-dims*`, feet / half feet / inches / half inches), the
corner-zone sizing (`fit:*corner-zone*`, `fit:*zone-pad*`,
`fit:*rad-turn-min*`), the fit depth (`fit:*icp-iters*`), the
both-ends evidence margin (`fit:*both-edge*`) and the K/L/M offset
(`fit:*dim-off*`). `tests/test_fitabhd.py` checks this file and the
mirror agree on the ones that shape the fit.

## Notes & limitations

* Everything is fitted on the 2D plane (XY); Z values are ignored.
* The type list is deliberately the *typical* pools: Octagon rides the
  Grecian template (same eight corners); mixed-end ("mutt") and
  freeform/kidney shapes are what ABHD is for.
* A Lazy L's bend is held at exactly 45 degrees -- that is the point
  of declaring the type. A pool bent at some other angle will show up
  in the report as points beyond tolerance; trace it with ABHD.
* The corner radius / cut face is *shared* across the corners (that is
  what "typical" means on an order sheet). Corners that genuinely
  differ will show as strays.
* Snapping treats measured *features* (corner radius, cut face, roman
  end radius) more strictly than whole dimensions: a feature snap may
  grow the worst deviation by at most a tenth of an inch, so an 8"
  as-built corner is reported as 8", never rounded up to a foot just
  because the tolerance would absorb it.
* A Rectangle whose corners are `Cut` keeps those cut vertices sharp
  (one treatment per run); a cut-and-also-rounded corner is beyond the
  template.
* At least 6 survey points are needed (3 for Round); corner radii can
  only be measured if the corner arcs were actually shot -- a corner
  with no points on the arc fits whatever the walls allow.
* Bottom dimensions use the current dimension style (ABHD's
  feet-vs-inches style switching is not carried here).

## Tests

```
python3 tests/test_fitabhd.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_fitabhd.py # grouped tier
python3 tools/check_lisp.py  lisp/fitabhd/FITABHD.lsp
python3 tools/check_scope.py lisp/fitabhd/FITABHD.lsp
```

`test_fitabhd.py` is a faithful Python mirror of the whole engine
(same algorithm, same constants, same function names), run over
synthetic production-shaped surveys -- and it also loads the real
`FITABHD.lsp` into `tests/lispvm.py` and runs the fitting engine
end-to-end, asserting the LISP and the mirror agree to floating-point
noise on every headline dimension. The structural checks hold the
file to the repo conventions (balanced parens, no dead or undefined
functions, the canonical Treatment keywords, the version banner and
its dated twin in `releases/`).
