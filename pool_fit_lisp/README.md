# POOLFIT — AutoLISP pool-perimeter fitter (AutoCAD 2018+)

Rebuilds a hand-drawn pool perimeter as a single smooth closed
polyline (lines + arcs only) that passes through as many surveyed
points as possible.

## Setup expected in the drawing

| Layer | Contents |
| --- | --- |
| `POOL` | The drawn perimeter: one closed polyline, **or** the same shape exploded into `LINE`s and `ARC`s |
| `POINTS` | `POINT` entities surveyed on the real pool edge |

Layer names can be changed at the top of `poolfit.lsp`
(`*PF-POOL-LAYER*`, `*PF-POINT-LAYER*`, `*PF-OUT-LAYER*`).

## Usage

1. `APPLOAD` → pick `poolfit.lsp` (or drag it into the drawing).
2. Type `POOLFIT`.
3. Accept or change the tolerance (default `1.0` drawing unit — one
   inch in an inch-based drawing; the value is remembered for the
   session).
4. Window-select the area containing the perimeter and the points.

A new closed `LWPOLYLINE` is created on layer `POOL-FIT` (green,
created if missing). The original geometry is left untouched, so the
result is easy to compare and the command can be re-run with a
different tolerance.

## What it does

* **Chains** exploded `LINE`/`ARC` segments back into one closed loop
  (closed `LWPOLYLINE`s and old-style `POLYLINE`s are read directly).
  It aborts with a message if the loop has a gap or doesn't close.
* **Snaps vertices**: every vertex of the perimeter moves to the
  nearest surveyed point within tolerance, so corners land *exactly on*
  points whenever one is close enough (each point is used at most
  once).
* **Re-fits arcs**: for each curved segment, the surveyed points lying
  within tolerance of it are collected, the exact circular arc through
  the two (snapped) endpoints and each such point is computed, and the
  new bulge is their average — a circular fit constrained through both
  endpoints, so the loop stays closed and smooth.
* **Trusts straight walls**: segments the user drew straight stay
  straight; only their endpoints snap. Where the user decided a wall
  exists, the fitted perimeter keeps it.
* **Reports** how many points the new perimeter passes through exactly,
  how many fall within tolerance, and how many it missed (points that
  disagree with the drawn shape by more than the tolerance are not
  chased — the drawn shape wins).

## Notes & limitations

* Everything is fitted in plan (XY); Z values are ignored.
* Splined or fit-smoothed heavy polylines are not supported — use a
  plain polyline (or explode to lines/arcs) for the perimeter.
* Survey points must be `POINT` entities; if yours are blocks, use
  a quick `PDMODE`-visible conversion (or explode the blocks' point)
  first.
