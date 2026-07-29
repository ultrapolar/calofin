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
* Each arc is grown point by point for as long as one in-window arc
  can hold every covered point within the tolerance (and the miss
  allowance) — the longest arc that fits the most points wins.
* A point that turns more than `*PF-CORNER-ANG*` (**45°**) is a
  **sharp corner** — an intentional kink where the tangent rule is
  waived. So a shape given as just its corner points (a triangle, a
  rectangle, any polygon) keeps its corners. Sample real tight curves
  with at least ~3 points per quarter turn so they stay under the
  threshold.
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
  found** (a closed loop bottoms out around 2–3 arcs), never the
  full-size fit.

All thresholds are constants at the top of `abhd.lsp`
(`*PF-MISS-PCT*`, `*PF-ON-EPS*` — default 0.25, a quarter of the
default tolerance — `*PF-CORNER-ANG*`, `*PF-NICE-RADII*`,
`*PF-TANG-TOL*`), as are the layer names (`*PF-POOL-LAYER*`,
`*PF-POINT-LAYER*`, `*PF-OUT-LAYER*`). The defaults were calibrated
against a real hand-drawn as-built trace (55 `ab_pt` points, 37×16 ft
pool, ~20″ point spacing): with them the automatic fit stays within
about an inch of the hand trace everywhere while using fewer arcs
(20 vs 23).

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
