# ABHD — AutoLISP pool-perimeter fitter (AutoCAD 2018+)

Builds a single **smooth** closed polyline of **long, overarching,
tangent-continuous arcs** through points surveyed on a pool edge —
guided by a hand-drawn perimeter, by a rough connect-the-dots sketch,
or from the points alone — using as **few curves as possible**, each
with a **friendly radius** (whole feet, half feet, or whole inches)
whenever one fits. Every arc starts tangent to the previous one, so
the outline has no kinks. Up to 15% of the points (rounded up) are
allowed to sit about an inch off the result, and you can cap the
number of curves outright.

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
Up to `*PF-MISS-PCT*` (**15%**) of the points, **rounded up** to the
nearest whole point, may sit off the result by up to the tolerance
(default `1.0` drawing unit — about an inch); every other point stays
on it (within `*PF-ON-EPS*`, default **0.25**). That slack is spent
where it buys the most — longer spans, fewer segments, fewer curves.

In the ordering-sketch and points-only modes the loop is covered by a
**tangent chain** of long, overarching arcs — **smooth everywhere, no
straight lines**:

* Every arc starts exactly where the previous one ended, **with its
  tangent**, so consecutive arcs are always tangent to each other
  (G1-continuous) and the perimeter has no kinks. A fully smooth loop
  is sealed with a G1 **biarc**, so even the closing seam is tangent-
  continuous.
* Each arc is grown point by point for as long as one tangent arc can
  hold every covered point within the tolerance (and the miss
  allowance) — the longest arc that fits the most points wins. Among
  the arcs that fit, the fitter prefers one whose **exit tangent stays
  aimed along the data** (`*PF-TANG-W*`), which is what lets the next
  arc reach far too.
* Because tangency pins each arc down, the joints between arcs are
  allowed to float off the survey points; the points still govern the
  fit through the tolerance and the allowance.
* A point that turns more than `*PF-CORNER-ANG*` (**45°**) is a
  **sharp corner** — an intentional kink. Corners are hit **exactly**;
  the chain restarts on each side of them, so a shape given as just
  its corner points (a triangle, a rectangle, any polygon) keeps its
  corners. Sample real tight curves with at least ~3 points per
  quarter turn so they stay under the threshold.
* The only places a straight segment can appear are between two sharp
  corners with no points in between (where a curve would be pure
  invention) and where the surveyed points run dead straight along
  the chain's own tangent.

## Nice radii — feet, half feet, inches

Before a free-fit ("weird") radius is accepted, each arc's radius is
snapped to the first friendly increment that still holds every one of
its points: **whole feet** first, then **half feet**, then **whole
inches** (`*PF-NICE-RADII*`, drawing units are inches — e.g. `24` =
2′-0″ before `23.71`). Snapping never moves the arc's start or breaks
its tangency — only the radius ahead changes — and a snap that would
throw the exit tangent off aim is rejected. The seam arcs that seal a
smooth loop and the stitches that land exactly on corners get their
radii dictated by the closure geometry, so those few can stay "weird".

## The curve cap

The command asks for a **maximum number of curves** (`None` =
unlimited; the answer is remembered for the session). When a fit needs
more curves than allowed, the whole loop is **refitted with a
progressively relaxed tolerance** until the cap holds — merging arcs
would break their tangency, so the chain is rebuilt instead and the
result stays smooth at any cap. The cap **wins over the tolerance**;
whatever error it forces is visible in the hit report. In guided mode
the drawn walls are trusted, so the cap is reported rather than
enforced there.

All thresholds are constants at the top of `abhd.lsp`
(`*PF-MISS-PCT*`, `*PF-ON-EPS*` — default 0.5, half the default
tolerance — `*PF-CORNER-ANG*`, `*PF-NICE-RADII*`, `*PF-TANG-W*`), as
are the layer names (`*PF-POOL-LAYER*`, `*PF-POINT-LAYER*`,
`*PF-OUT-LAYER*`).

## Usage

1. `APPLOAD` → pick `abhd.lsp` (or drag it into the drawing).
2. Type `ABHD`.
3. Accept or change the tolerance (default `1.0` drawing unit — one
   inch in an inch-based drawing; the value is remembered for the
   session). Points may sit up to this far off the result, within the
   15% allowance.
4. Accept or change the max number of curves (`Enter` keeps the
   current setting, `None` removes the cap).
5. Window-select the area: points plus (optionally) the perimeter or
   ordering sketch — what you include picks the mode.

A new closed `LWPOLYLINE` is created on layer `POOL-FIT` (green,
created if missing). The original geometry is left untouched, so the
result is easy to compare and the command can be re-run with a
different tolerance.

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
