# ABHD — AutoLISP pool-perimeter fitter (AutoCAD 2018+)

Builds a single **smooth** closed polyline of **long, overarching
arcs** through points surveyed on a pool edge — guided by a hand-drawn
perimeter, by a rough connect-the-dots sketch, or from the points
alone — using as **few curves as possible**, each with a **friendly
radius** (whole feet, half feet, or whole inches) whenever one fits.
Every arc runs **from survey point to survey point** and meets its
neighbour **within 8° of tangent**, so the outline reads as smooth
while the points stay in charge. Up to 15% of the points (rounded up)
are allowed to sit about an inch off the result, and you can cap the
number of curves outright.

Two commands ship in the one file: **`ABHD`** runs the whole fit (and
offers the pool bottom at the end), and **`ADAB`** runs just the
pool-bottom flow over a perimeter that already exists — see
[ADAB](#adab--the-bottom-on-its-own).

## Setup expected in the drawing

| Layer | Contents |
| --- | --- |
| `POOL` | *(optional)* The drawn perimeter: one closed polyline or the same shape exploded into `LINE`s and `ARC`s — **or** a rough lines-only sketch that just connects the points in order |
| `POINTS` | The survey points on the real pool edge — either plain `POINT` entities on this layer, **or** `ab_pt` block insertions (the block's insertion point is used as the point) |

## Three modes, picked automatically from what you select

| Selection contains | Mode | Behaviour |
| --- | --- | --- |
| POOL geometry **with arcs** + points | **Guided** | The drawn shape is trusted and re-fitted through the points (vertices snap, arcs re-fit/subdivide, straight walls stay straight) |
| POOL geometry that is **lines only** + points | **Ordering sketch** | The sketch is treated as connect-the-dots: it only tells the program the *order* of the points; the actual shape is built from the points themselves |
| **Points only** (no POOL geometry) | **Points-only** | The program orders the points into a closed loop itself (nearest-neighbour tour + 2-opt uncrossing) and builds the shape from them |

## The miss allowance — fewer curves instead of exactness

The fitted perimeter does **not** have to thread every point exactly.
A share of the points — **asked at step 2, standard 15%**
(`*PF-MISS-PCT*`), **rounded up** to the nearest whole point — may sit
off the result by up to the max distance (default `1.0` drawing unit —
about an inch); every other point stays *on* it. That slack is spent
where it buys the most — longer spans, fewer segments, fewer curves.

"On it" means within `*PF-ON-EPS*` (**0.25**) or a quarter of the
tolerance, whichever is larger — the threshold scales so that raising
the tolerance genuinely loosens the fit. No single span may spend more
than its own fair share of the allowance either, so one greedy arc
cannot use up the whole budget and leave the rest of the loop with
none.

In the ordering-sketch and points-only modes the loop is covered by
long, overarching arcs that sit **on the points** and meet each other
**near-tangent** — no straight lines:

* Every span runs **from survey point to survey point**, and each arc
  is chosen so its **middle also passes exactly through one of its
  interior points** — a true **3-point arc** — whenever such an arc
  holds the span. Arcs that float *between* the points are a last
  resort: one must cover at least 2 more points than the best exact
  arc to be chosen, keeping floaters the rare exception (about 1 arc
  in 10), not the rule.
* At every joint the new arc must start within `*PF-TANG-TOL*`
  (**8°**) of the previous arc's end tangent — close enough to look
  smooth, loose enough that the points stay in charge. The closing
  seam of the loop is held to the same window (when the first pass
  closes worse, the fit is re-run once with the arrival tangent
  seeded into the first span).
* **Smoothness outranks the exact-arc rule.** When nothing fits
  inside the window, the window is stretched by small steps
  (`*PF-TANG-STEPS*`, 1× → 1.25× → 1.5×) rather than abandoned, and
  if even the widest step finds nothing the fit falls back to a
  one-point stub that continues the previous tangent exactly. Dropping
  the window outright — what an earlier version did — let a joint kink
  **23.8°**, three times the limit; it is now capped near 12°.
* Each arc is grown point by point for as long as one in-window arc
  can hold every covered point within the tolerance (and the miss
  allowance) — the longest arc that fits the most points wins.
* A point that turns more than `*PF-CORNER-ANG*` (**45°**) is a
  **sharp corner** — an intentional kink where the tangent rule is
  waived. So a shape given as just its corner points (a triangle, a
  rectangle, any polygon) keeps its corners. Sample real tight curves
  with at least ~3 points per quarter turn so they stay under the
  threshold. **You can declare corners yourself** at step 5 for the
  gentler ones the 45° test misses — see below.
* The only places a straight segment can appear are between two sharp
  corners with no points in between (where a curve would be pure
  invention) and where the surveyed points run dead straight.

## Nice radii — feet, half feet, inches

Before a free-fit ("weird") radius is accepted, each arc's radius is
snapped to the first friendly increment that still holds every one of
its points: **whole feet** first, then **half feet**, then **whole
inches** (`*PF-NICE-RADII*`, drawing units are inches — e.g. `24` =
2′-0″ before `23.71`). **The points outrank pretty radii**: a snap may
move covered points at most `*PF-SNAP-EPS*` (default **0.02**) beyond
where they already sat, may never pull an arc off its anchor point,
must stay inside the 8° tangent window, and never moves the arc's
endpoints. In practice roughly two-thirds of the arcs still land on
nice radii — the snaps that survive are the ones that cost nothing.

## The curve cap

The command asks for a **maximum number of curves** (`None` =
unlimited; the answer is remembered for the session). When a fit needs
more curves than allowed, the whole loop is **refitted with a
progressively relaxed tolerance** until the cap holds — the tangent
windows stay in force, so capped results stay as smooth as the cap
allows (a very tight cap may need more than 8° at a joint to close
the loop; the hit report shows the cost). The cap **wins over the
tolerance** and **binds in every mode**:

* In guided mode, if the drawn perimeter needs more curves than the
  cap, the command falls back to fitting from the points — the drawn
  shape still sets their order — and says so.
* If the cap is unreachably small, you get the **fewest-curves fit
  found**, never the full-size fit. A closed loop cannot go below
  **2 segments**, so that is the floor.

All thresholds are constants at the top of `abhd.lsp`
(`*PF-MISS-PCT*`, `*PF-ON-EPS*`, `*PF-SNAP-EPS*`, `*PF-CORNER-ANG*`,
`*PF-NICE-RADII*`, `*PF-TANG-TOL*`), as are the layer names
(`*PF-POOL-LAYER*`, `*PF-POINT-LAYER*`, `*PF-OUT-LAYER*`). The
defaults were calibrated against a real hand-drawn as-built trace
(55 `ab_pt` points, 37×16 ft pool, ~20″ point spacing). On that
survey the automatic fit uses **19 arcs where the hand trace used
23**, stays within about an inch of it everywhere, puts **9 of 10
arcs through a survey point**, and lands **three-quarters of its
radii on whole feet, half feet or inches** (the hand trace: 1 of 23).

## Usage

1. `APPLOAD` → pick `abhd.lsp` (or drag it into the drawing).
2. Type `ABHD`. It asks six plainly-worded questions:

```
ABHD - fit a pool perimeter through the surveyed points.

  Step 1 of 6 - how far may the fitted line sit from a survey point?
  Type a distance in drawing units (1 = one inch, 2 at most), or
  pick two points in the drawing to measure one.
  Smaller = hugs the points.  Bigger = smoother, with fewer curves.
  Maximum distance from a point <1.000>:

  Step 2 of 6 - what percent of the points may sit OFF the line
  (off, but still within the distance above)?
  Press Enter for the standard 15 percent.
  Percent of points allowed off <15>:

  Step 3 of 6 - limit how many curves the result may use?
  Type a whole number, or None for no limit.
  Maximum curves <None>:

  Step 4 of 6 - does the pool edge have any dead-straight walls?
  If Yes you will pick the two end points of each (snap to the
  survey points); a dashed line marks each declared wall.
  Any straight lines? [Yes/No] <No>:

  Step 5 of 6 - are there any sharp corners the fit must not round off?
  Obvious ones are found automatically; declare the gentler ones here.
  If Yes you will pick each corner point (snap to the survey points).
  Any sharp corners? [Yes/No] <No>:

  Step 6 of 6 - select the survey points (POINTS layer or ab_pt
  blocks) and, if you have one, the POOL perimeter or ordering sketch.
  Select objects:
```

The max distance is capped at **2 inches** — anything looser is no
longer a trace of the points, so a bigger entry is pulled back to 2
with a note. Distance and curve cap are remembered for the session;
the percentage resets to the standard 15% each run (`Enter` keeps it).
So a repeat run is just `ABHD` + `Enter` × 5 + select.

### Declaring straight walls

Real pools often have one truly straight wall in an otherwise curvy
shape. Answer `y`/`Yes` at step 4, then click the wall's two end
points (use osnap to land on the survey points — each pick snaps to
the nearest one anyway). A **dashed marker line** appears immediately
on layer `POOL-WALLS` so you can see what you declared. `Enter` at
"Another straight line?" moves on; `Yes` lets you pick more walls.

Declared walls are law: each comes out of the fit as a dead-straight
`LINE` between exactly those two survey points, arcs never swallow or
cross them, and the arc after a wall leaves it near-tangent. Points
along the wall that disagree with it are flagged like any other
unheld point. (In guided mode your drawn straight segments are already
kept, so declared walls only steer the points-built fits.)

The dashed markers are scaffolding, not results: **ABHD erases them
itself** when the command finishes — including when you cancel with
`ESC` or the run stops on an error. If an older run was interrupted
before it could tidy up, the next run sweeps the leftovers and says
so.

### Declaring sharp corners

The fitter finds obvious corners itself — any point where the survey
turns more than `*PF-CORNER-ANG*` (45°). A gentler bend can still be a
real corner on site, and the smoothness rule would round it off. Answer
`y`/`Yes` at step 5 and pick those points; each gets a dashed ring, and
`Enter` finishes the list.

At a declared corner the **tangency rule is waived**: the fit breaks
there, arcs never run through it, and the two sides are free to meet at
any angle. Like the wall markers, the rings clear themselves when the
command ends.

## Pick the one that looks right

You do not have to guess the tolerance. ABHD draws **three candidate
fits at once**, in different colours, **numbers each one on screen**
in its own colour beside the shape, and shows what each costs:

```
Three candidate fits are now drawn on layer POOL-FIT,
each numbered on screen in its own colour:

   #  segs  curves  worst off  avg all  avg off  not held
   -  ----  ------  ---------  -------  -------  --------
   1  20    20      0.49       0.07     0.34     0         tighter - hugs the points
   2  19    19      0.87       0.12     0.55     0         as asked
   3  16    16      1.88       0.24     0.61     3         looser - fewer curves

  "not held" = points further than 1.000 from that fit.
  "avg all" averages every point; "avg off" averages only the points
  that are off the line (further than 0.250 from it).

  Click the outline you want to keep, or type its number.
  Keep which fit - click one, or [1/2/3/All/None] <2>:
```

**`worst off`** is one bad point; **`avg all`** averages every point,
so the ones sitting on the line count as the zeros they are; **`avg
off`** averages only the points that actually strayed. Read together
they separate "one point is off" from "everything drifted": above,
fit 3's worst more than doubles but its strays still average close to
fit 2's, so the extra error is concentrated rather than general.

The red `1`, yellow `2` and cyan `3` stack down the right-hand side of
the pool, each in the same colour as its outline — and **each figure
is repeated in the drawing beside its number**, so the whole choice
can be made on screen without reading the command line:

```
1   20 segs    20 curves    0 not held    tighter - hugs the points
    worst 0.49    avg all 0.07    avg off 0.34
2   19 segs    19 curves    0 not held    as asked
    worst 0.87    avg all 0.12    avg off 0.55
3   16 segs    16 curves    3 not held    looser - fewer curves
    worst 1.88    avg all 0.24    avg off 0.61
```

**Just click the outline you want** — press `Enter` at the keyword
prompt and ABHD asks you to pick one on screen; clicking either the
outline or its number label keeps that fit. Typing `1`, `2` or `3`
works just as well. The other two are erased, the number labels are
cleaned up, and the keeper reverts to the layer colour. `All` keeps
all three (labels included) to compare later; `None` erases everything
and leaves the drawing untouched. `Enter` at both prompts keeps **2**,
the fit at exactly the distance you typed.

The three tolerances are ½×, 1× and 2× what you asked for; change the
spread by editing `*PF-COMPARE*` at the top of `abhd.lsp`.

Keeping a single fit also unlocks the pool-bottom flow — see
[The pool bottom (hopper)](#the-pool-bottom-hopper) below (`All` and
`None` skip it).

## Points it could not hold

Every point further than your distance from the kept fit is **ringed
with a 4″ radius circle on layer `FGStep`**, and the whole set is
**listed beside the pool, worst first**, using the point numbers from
your `ab_pt` blocks:

```
POINTS OFF THE LINE (3)
Pt.8    off by 1-7/8"
Pt.7    off by 1-5/16"
Pt.51   off by 1-1/16"
```

So you can work down the list instead of hunting for circles, and
decide per point whether it is a bad shot, a duplicate, or a real
feature that needs a tighter distance. The same list prints at the
command line.

The numbers come from the `number` attribute on each point block
(`*PF-PT-TAG*`); points without one are numbered in selection order.
The circle radius is `*PF-MISS-RADIUS*` and the layer is
`*PF-MISS-LAYER*`, both at the top of `abhd.lsp`.

**`FGStep` is likely a layer you already use, so ABHD never clears
it wholesale.** Everything it draws there is stamped as its own, and
only stamped objects are removed when the next run replaces them —
your own geometry on that layer is left alone.

If a point is beyond tolerance in **all three** candidates, ABHD says
so before you choose — that one is almost certainly a mis-shot, a
duplicate, or a corner that needs more points around it, and no
tolerance setting will rescue it.

The kept fit is a closed `LWPOLYLINE` on layer `POOL-FIT` (green,
created if missing; if the layer exists but is off, frozen or locked
it is restored so the result is actually visible). Your original
geometry is never touched.

### What the report tells you

```
ABHD: 19 segments (0 lines + 19 curves) written to layer POOL-FIT.
  Points on the perimeter:      46
  Points off within tolerance:   9  (allowance 9)
  Points beyond tolerance:       0
  Worst point deviation:        0.870
  Average off, all points:      0.124
  Average off, off points only: 0.553  (9 point(s))
  Curves through a point:       16 of 19
  Curves on foot/half/inch radii:14 of 19
  Largest joint kink:           8.0 deg  (limit 8.0)
```

*Curves through a point* is the one to watch: it counts arcs whose
middle lands on a survey point rather than floating between them.
*Largest joint kink* ignores intentional sharp corners; if any joint
needed more than the tangent limit to close the loop, that is called
out separately. The command also warns when the result **crosses
itself** (almost always a wrong automatic point order — draw an
ordering sketch), and when earlier fits are still sitting on the
`POOL-FIT` layer.

## The pool bottom (hopper)

Once you keep one of the perimeters, ABHD offers to draw the floor
too:

```
  Add the bottom of the pool (breaks and hopper)? [Yes/No] <No>:
```

`Enter` skips it and the command finishes per usual. Answer `y`/`Yes`
and you pick four points (use osnap to land on the survey points —
each pick snaps to the nearest one anyway):

1. the two ends of the **SHALLOW BREAK** — where the flat shallow
   floor starts sloping down, then
2. the two ends of the **DEEP BREAK** — where the slope levels out
   into the hopper.

The **hopper** — the flat deep-end floor — lies beyond the deep
break, away from the shallow end. Its **back is found for you**: a
ray is cast from the middle of the deep break line, perpendicular to
it, away from the shallow break, and the survey point closest to that
ray marks the back of the hopper (the command names it, e.g.
`Back of the hopper: Pt.32`).

Then three offsets, **each named by its survey point number** so
there is never a doubt which side is being asked about, each
defaulting to the previous entry:

```
  What is the deep end offset at Pt.12? <18.00>:
  What is the deep end offset at Pt.7? <18.00>:
  What is the offset at the back of the hopper (Pt.32)? <18.00>:
```

Type plain inches (`42`) or feet-and-inches (`3'6`) — **how you type
it picks the dimension style** on the dims that are not anchored to a
break point (the back of the hopper and any slope waypoints):
feet-and-inches goes on **`SIDE DIMENSION`**, plain inches on
**`STANDARD INCHES`** (`*PF-DIM-FTIN*` / `*PF-DIM-IN*`; if a style is
missing from the drawing the current style is used and a note says
so). The two deep-break dims stay in the drawing's current dimension
style.

The perimeter beyond the deep break is **offset inward** by those
amounts — exactly your `Pt.12` offset at `Pt.12`, exactly the back
offset at the back, exactly the `Pt.7` offset at the other end,
**blending gradually over arc length in between** when they differ.

Each **slope line** — from a hopper end up to the shallow break point
on its own side — is then asked about separately, again by point
number:

```
  Slope line from the offset at Pt.12 [Straight/Guided/Points] <Straight>:
  Slope line from the offset at Pt.7 [Straight/Guided/Points] <Straight>:
```

`Straight` (the default) is a clean straight run to the shallow break
point. `Guided` follows the pool's own curve instead: the line runs
along the perimeter with its inward offset **easing from the hopper
offset at the deep break down to nothing at the shallow break**, so
it lands on the shallow break point having gently followed the wall
in. Sides are paired by walking the perimeter away from the hopper,
so the two lines never cross, and the answers can be mixed freely.

`Points` takes control of the line where you want it: pick survey
points along that side, between the two breaks, and give each an
offset — **measured square off the wall** (perpendicular, along the
perimeter's inward normal at that point):

```
  Point on the Pt.12 side (Enter when done):
  What is the offset at Pt.23? <18.00>:
```

The line is pinned to exactly those offsets at those points and runs
**guided in between** — from the hopper offset at the deep break,
through each picked point's offset, easing to nothing at the shallow
break — so a few points steer it and the pool's own curve carries it
the rest of the way. Each pick gets a dashed confirmation ring
(scaffolding, cleared when the command ends), and **every waypoint
offset is dimensioned** just like the three hopper offsets. A pick
that isn't on that side of the pool, or that lands on a break point,
is called out and ignored; picking no points at all just gives the
plain guided line.

Everything is drawn **solid** on layer `POOL-BOTTOM` (blue, created
if needed): the shallow break line, the deep break line, the hopper
outline (an open polyline sampled every 6″ — `*PF-BOTTOM-STEP*`), the
two slope lines, and an **aligned dimension on each of the three
offsets**, measured automatically in the drawing's current dimension
style. The first offset becomes the session default (`*PF-HOP-OFF*`,
18″ out of the box).

`ESC` or a cancelled pick anywhere in the flow leaves nothing behind
— the bottom only stays once it is complete. If no survey point lies
beyond the deep break, ABHD asks whether the two break lines were
swapped and adds nothing.

### ADAB — the bottom on its own

When the perimeter already exists — fitted by `ABHD` on an earlier
day, or drawn by hand — **`ADAB`** runs just the bottom flow over it:

1. Select the **perimeter**: one closed polyline, or the exploded
   `LINE`s/`ARC`s that form one. Layer does not matter; ABHD's own
   markers, miss rings and an earlier bottom in the selection are
   recognised and ignored. **The survey points do not need to be
   selected** — with none in the selection, every `ab_pt` block and
   `POINTS`-layer point in the drawing is gathered and only the ones
   **sitting on the loop** (within `*PF-PICKUP-EPS*`, 3″) are used,
   so depth shots and deck points nearby stay out of it, and the
   command says how many it picked up. Points you *do* select are
   trimmed by the same on-the-loop rule (with a note when strays are
   set aside) — select them explicitly only when they live on unusual
   layers.
2. The pieces are chained into a closed loop (the same check `ABHD`
   uses — a gap is reported with its location), and the flow goes
   straight to the shallow-break picks: breaks, back point, offsets,
   slope lines and dimensions, exactly as above — just without the
   "Add the bottom?" question, since running `ADAB` *is* the answer.

Everything else behaves identically: the same prompts by point
number, the same straight/guided/points slope lines, the same
dimension-style rules, and the same clean-up on `ESC`.

## Checking it still works

Run **`python3 tests/test_pool_fit.py`** from the repository root. It
is a Python mirror of the same geometry and fitting logic, so the
algorithm can be regression tested outside AutoCAD, and it also parses
`abhd.lsp` to verify the parentheses balance, that no function is
called undefined or defined-but-unused, and that the tuning constants
in both files still agree.

## Troubleshooting

| What you see | What it means |
| --- | --- |
| "gap in the POOL perimeter — could not close the loop" | The drawn perimeter has a break, or pieces of it were not selected. Zoom in on the ends, or select the whole shape. |
| "SPLINE/ELLIPSE object(s) … were ignored" | Those curve types cannot be read. Explode or convert them to polylines/arcs first. |
| "No survey points found" | The points are not `POINT` entities on `POINTS`, nor `ab_pt` blocks. Check the layer name and the block name at the top of `abhd.lsp`. |
| "the result crosses itself" | The automatic ordering went the wrong way around a narrow waist. Draw a rough **lines-only** loop on `POOL` through the points in the right order and select it too. |
| "not drawn in the world plane" | Geometry was drawn in a tilted UCS. Set UCS to World and flatten it; the fit is 2D. |
| Nothing appears | The report says how many segments were written. If the layer was off/frozen/locked, ABHD restores it and says so; if the drawing is read-only it says that instead. |
| Red 4″ circles and a "POINTS OFF THE LINE" list | The points the kept fit could not hold, on layer `FGStep`. Work down the list; the next run replaces them. Only ABHD's own objects on that layer are ever erased. |
| Grey dashed lines left behind | Straight-wall markers from a run that was interrupted before it could tidy up. The next `ABHD` sweeps them and says so. |
| Three coloured outlines left behind | You answered `All` at the choose prompt. Erase the two you don't want, or re-run and pick one. |
| It feels slow | Three fits are built, and ordering is O(n²); above ~150 points the command warns and takes a while. An ordering sketch skips the expensive search entirely. |

## What the guided mode does

* **Chains** exploded `LINE`/`ARC` segments back into one closed loop
  (closed `LWPOLYLINE`s and old-style `POLYLINE`s are read directly).
  It aborts with a message if the loop has a gap or doesn't close.
* **Snaps vertices**: every vertex of the perimeter moves to the
  nearest surveyed point within tolerance, so corners land *exactly on*
  points whenever one is close enough (each point is used at most
  once).
* **Re-fits arcs**: for each curved segment, the surveyed points lying
  within tolerance of it are collected and a single replacement arc is
  tried first (the best of the exact 3-point arcs through the two
  snapped endpoints and the points, plus their average — a circular
  fit constrained through both endpoints), with its radius snapped to
  a nice increment (feet / half feet / inches) when one still holds
  the points.
* **Keeps one arc when it's close enough**: if the single arc holds
  every point within the tolerance and the 15% miss allowance can
  absorb the off ones, that one arc is kept — fewer curves beats
  exactness.
* **Splits arcs only as a last resort**: otherwise the segment is
  subdivided into a chain of arcs that passes **exactly through every
  point**, with each new arc starting tangent to the previous one, so
  the subdivided run stays smooth (G1-continuous) and the loop stays
  closed.
* **Trusts straight walls**: segments the user drew straight stay
  straight; only their endpoints snap. Where the user decided a wall
  exists, the fitted perimeter keeps it.
* **Reports** the segment mix (lines + curves), how many points sit on
  the new perimeter, how many used the miss allowance (off by up to
  the tolerance), and how many it missed entirely (points that
  disagree with the drawn shape by more than the tolerance are not
  chased — the drawn shape wins).

## Notes & limitations

* Everything is fitted purely on the 2D plane (XY); Z values are
  ignored on read and the output polyline is flat.
* Splined or fit-smoothed heavy polylines are not supported — use a
  plain polyline (or explode to lines/arcs) for the perimeter.
* Survey points may be plain `POINT` entities on the `POINTS` layer or
  `ab_pt` block insertions (any layer). Block references are read
  non-destructively — their insertion point is used as the point
  location, so nothing is exploded and your blocks stay intact. Change
  the block name at the top of `abhd.lsp` (`*PF-POINT-BLOCK*`). If a
  block's marker geometry is offset from its insertion base, tell me
  and I'll add copy-and-explode extraction instead.
