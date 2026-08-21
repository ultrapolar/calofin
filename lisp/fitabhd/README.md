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
* **The pool may be out of square** -- and by default it is assumed to
  be. An AB pool is *built*, not drawn: almost none come out true, and
  holding a rectangle perfectly square just pushes that error into the
  points. Answer `Outofsquare` at step 5 (POOL's own question, in
  POOL's own words) and each wall may **swing a little to answer its
  own points**, so the survey is respected as far as the type allows.
  A wall's swing is kept only where the points prove it -- at least an
  inch of drift end to end (`fit:*oos-min*`) and a clear improvement
  on that wall's own points -- so **a pool that really is square still
  comes out square**. A swing past `fit:*oos-max*` (5°) is refused
  outright: that is not an out-of-square rectangle, it is a different
  shape, and the report says so rather than quietly absorbing it.
  `Insquare` holds the template exactly and shows you the error
  instead. On a Grecian the four cut corners are not free walls: each
  **bisects its own corner** and all four keep one shared face,
  however far the axis walls have swung. The arc-ended types are not
  asked (swinging their side walls would take the end caps with them).
* **Straight walls may be bowed.** "Straight" is a drafting
  convention, not a site measurement: a gunite wall shot dead straight
  on the order sheet is very often a very long radius on the ground.
  Answer `Yes` at step 5 and every wall is refitted as a constant
  offset plus a shallow bow, and the report gives each bowed wall its
  depth and the radius it implies (`Wall A-B bowed 3" out (R 205'-4")`).
  **A bow never moves a corner** -- it vanishes at both ends of its
  wall by construction, so every dimension taken between corners, and
  the whole hopper flow, are untouched. A bow is kept only where the
  points prove one: at least an inch deep (below that is drafting
  noise), no deeper than a wall can bow and still be a wall
  (`fit:*bow-max*` / `fit:*bow-max-frac*`), on a wall shot at least
  `fit:*bow-pts-min*` times, and beating the straight wall on that
  wall's own points by a clear margin. A wall that really is straight
  stays straight. Roman and Oval side walls bow too; their arc ends
  are left alone, and a Round pool is never asked.
* **An arc that caved in becomes a run of arcs.** A drawn end is one
  clean radius; a built one very often is not, because a gunite shell
  slumps a little as it cures. An end (or a Round pool's whole
  outline) that a single radius cannot hold **within the distance you
  typed at step 3** is rebuilt as a polyline of arcs, and the report
  names it -- `End A is a run of 2 arcs  R 7'-2 1/2" / 6'-9 1/4"`.
  No question is asked: the tolerance you already typed *is* the
  control, and raising it gives the single clean radius back.
  * **Every joint sits on a survey point**, so the run is continuous
    by construction and each joint is a real measurement rather than
    an invented one.
  * Extra arcs have to earn their place: the run keeps the **fewest
    that hold the points**, each one required to beat its predecessor
    by a clear margin (`fit:*arc-max*` caps it, `fit:*arc-pts-min*`
    keeps an arc from being fitted to two stray shots). An end that
    really is one radius stays one arc.
  * A *symmetric* cave-in is still a circle -- the single arc just
    takes a smaller radius, and no chain appears. This is for the ends
    that slumped to **one side**, which no circle can follow.
  * A chain changes the shape of the end, never the pool's
    dimensions: it runs after everything else is settled, so the
    width, body length and hopper are exactly what they were.
* **Nice dimensions**: each headline dimension -- length, width,
  corner radius, cut face, body length -- is snapped to the first
  friendly increment (whole feet, half feet, inches, half inches) the
  points can live with. **The points outrank pretty numbers**: a pool
  measured at 380" stays 380", it does not become 32'. Two rules
  decide, and they are deliberately different:
  * a **design dimension** may spend the allowance answered at step 4
    -- a snap is kept when it pushes no more than that share of the
    points further off, and never pushes one past the distance that
    was not already beyond it. So the same 383" survey stays 383" at
    the standard 15% and rounds to 32'-0" at 40%: **your call, not the
    program's**;
  * a **measured feature** -- a corner radius, a cut face, an end
    radius -- spends no allowance at all and may only grow the worst
    deviation by a tenth of an inch. An 8" as-built corner is reported
    as 8".

The six questions:

1. the **pool type**;
2. the **corner treatment** (for Rectangle / L / Lazy L, and for the
   Grecian's cut-corner vertices -- the arc-ended and round templates
   keep theirs square);
3. the **max distance** a point may sit from the fitted outline
   (capped at 2", remembered per session);
4. the **percent of points allowed beyond** that distance (standard
   15%) -- the slack that buys whole-foot dimensions;
5. whether the pool is **in-square or out of square** (default
   `Outofsquare`; not asked for the arc-ended or round types);
6. whether the **straight walls may be bowed** (skipped for a Round
   pool, which has none);
7. the **selection**.

Survey points are read exactly as ABHD reads them: `ab_pt` block
inserts on any layer, or `POINT` entities (and other blocks) on the
`POINTS` layer. Every prompt after the first offers `Back` (`Undo`
works too), and each step back re-opens the previous question with
what you already answered as its default.

## Redo -- when the fit came out wrong

The fit is not take-it-or-leave-it:

```
  Keep this fit, or Redo it? [Keep/Redo/Erase] <Keep>:
```

`Redo` throws the preview away and refits **without leaving the
command or re-selecting the points**. First it offers to leave points
out -- pick each one (mis-shots, duplicates, a shot that plainly
dragged a wall) and it gets a dashed red ring; **the pick is a
toggle**, so clicking a ringed point puts it back in. Then all five
settings are asked again with your last answers as the defaults, so
changing just the tolerance is `Redo`, `Enter`×2, a number,
`Enter`×2. Redo as many times as it takes. `Erase` throws the
preview away and leaves the drawing untouched.

The report calls out the case Redo exists for: when more points sit
beyond the distance than the percentage allows, it says so in capitals
and names the ways out -- a looser distance, a bigger percentage,
leaving the strays out, or the survey simply not being that type of
pool.

The fitted outline previews on `POOL-FIT` with a report -- the fitted
dimensions in feet-and-inches, the pool's rotation, points on the
outline / off within tolerance / beyond it, the strays ringed on
`FGStep` and named worst-first by their `number` attribute. When the
pool came out **out of square** the report drops the two headline
dimensions in favour of what an as-built actually needs: **every side
by name, both diagonals** (POOL's cross dims, which are what pin an
out-of-square shape down) and how far off square the worst wall came
out.

```
  Side A-B          32'-4 5/8"
  Side B-C          16'-0 1/8"
  Side C-D          31'-8 3/8"
  Side D-A          16'-0"
  Diagonal A-C      35'-6"
  Diagonal B-D      36'-1 1/2"
  Out of square by  2.13 deg at the worst wall
```
 Keep it
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
both-ends evidence margin (`fit:*both-edge*`), the standard share of
points allowed off (`fit:*miss-pct*`), what counts as a bow at all
(`fit:*bow-min*`, `fit:*bow-max*`, `fit:*bow-max-frac*`,
`fit:*bow-pts-min*`), how far out of square a wall may go
(`fit:*oos-max*`, `fit:*oos-min*`), how far an arc may be broken up
(`fit:*arc-max*`, `fit:*arc-pts-min*`) and the K/L/M offset
(`fit:*dim-off*`). `tests/test_fitabhd.py` checks this file and the
mirror agree on the ones that shape the fit.

## Notes & limitations

* Everything is fitted on the 2D plane (XY); Z values are ignored.
* The type list is deliberately the *typical* pools: Octagon rides the
  Grecian template (same eight corners); mixed-end ("mutt") and
  freeform/kidney shapes are what ABHD is for.
* Out of square is a *swing*, not a bend: each wall stays a straight
  line, it just no longer sits at exactly 0/45/90 degrees to its
  neighbours. A wall that is genuinely curved is what the bow question
  is for; a pool whose walls need more than 5 degrees of swing is not
  the type it was declared as.
* Out of square is not offered for Roman, Oval or Round: swinging an
  arc-ended body's side walls would take its end caps with them. Those
  types still get the bow refinement and the arc-chain rebuild, and a
  genuinely out-of-square one is ABHD's job.
* An arc chain is reported, not snapped: each arc's radius is whatever
  the shell made it. The nominal single-arc radius is still what the
  end dimension reports.
* A Lazy L's bend is nominally 45 degrees -- that is the point of
  declaring the type -- and `Outofsquare` lets it swing up to 5 degrees
  off that. A pool bent much further will show up in the report as
  points beyond tolerance; trace it with ABHD.
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
* A bowed wall's corner easing is computed on the wall's chord, so a
  filleted corner on a bowed wall is tangent to the chord rather than
  to the arc. At realistic bows (an inch or two over thirty feet) the
  difference is far inside the fit tolerance.
* Bows are reported, not snapped: a wall's radius is whatever the
  ground made it, so it is printed as measured rather than rounded to
  a friendly number.
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
