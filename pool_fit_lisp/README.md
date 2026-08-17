# ABHD — AutoLISP pool-perimeter fitter (AutoCAD 2018+)

Builds a single smooth closed polyline (lines + arcs only) through
points surveyed on a pool edge — guided by a hand-drawn perimeter,
by a rough connect-the-dots sketch, or from the points alone.

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

In the ordering-sketch and points-only modes the polyline passes
**exactly through every point**: each point gets a tangent from the
circle through it and its two neighbours, and consecutive points are
joined by a line, a single arc, or a G1 (tangent-continuous) biarc.
Straight geometry is preferred over arcs so the result isn't cluttered
with unnecessary curves:

* A point that turns more than `*PF-CORNER-ANG*` (**22.5°**) is treated
  as a **sharp corner** — straight lines meet at it. So a shape given
  as just its corner points (a triangle, a rectangle, any polygon)
  comes out as plain `LINE` segments, not arcs.
* A span whose ends run within `*PF-STRAIGHT-ANG*` (**3°**) of its
  chord becomes a straight `LINE`, so gently wandering or slightly
  noisy straight runs don't turn into a string of tiny arcs.
* Only genuinely curved stretches — points that turn gradually, each by
  less than the corner angle — are rendered as smooth arcs.

Both thresholds are constants at the top of `abhd.lsp`: lower
`*PF-CORNER-ANG*` (or raise `*PF-STRAIGHT-ANG*`) for even fewer arcs
and more straight lines; raise `*PF-CORNER-ANG*` for smoother, rounder
curves. Sample real curves densely enough that each point turns by less
than the corner angle and they stay smooth.

Layer names can be changed at the top of `abhd.lsp`
(`*PF-POOL-LAYER*`, `*PF-POINT-LAYER*`, `*PF-OUT-LAYER*`).

## Usage

1. `APPLOAD` → pick `abhd.lsp` (or drag it into the drawing).
2. Type `ABHD`.
3. Accept or change the tolerance (default `1.0` drawing unit — one
   inch in an inch-based drawing; the value is remembered for the
   session). It is used by the guided mode and for the hit report.
4. Window-select the area: points plus (optionally) the perimeter or
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
  tried first (the average of the exact 3-point arcs through the two
  snapped endpoints and each point — a circular fit constrained through
  both endpoints).
* **Splits arcs when needed**: if that single arc still misses any of
  its points by more than `*PF-FIT-EPS*` (default 0.01), the segment is
  subdivided into a chain of arcs that passes **exactly through every
  point**, with each new arc starting tangent to the previous one, so
  the subdivided run stays perfectly smooth (G1-continuous) and the
  loop stays closed.
* **Trusts straight walls**: segments the user drew straight stay
  straight; only their endpoints snap. Where the user decided a wall
  exists, the fitted perimeter keeps it.
* **Reports** how many points the new perimeter passes through exactly,
  how many fall within tolerance, and how many it missed (points that
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
