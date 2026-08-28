# CABHD -- fit a pool perimeter through part of a survey (AutoLISP / AutoCAD 2018+)

ABHD's perimeter half, for a survey that runs past the pool: after the
selection it asks how far up the point numbers the pool edge runs, and
everything past that answer is left out of the perimeter entirely. It
ends with the kept perimeter and its hit report -- no pool bottom, and
it never asks. For the floor, run `ABHD` or `ADAB` (see
`lisp/abhd/README.md`).

## What it does

CABHD is ABHD rule for rule -- same fitter, same guarantees -- with
one rule added and one half left out:

* **Added: the point cutoff.** A survey run rarely stops where the
  pool edge does: the edge shots come first and the steps, benches,
  deck and depth shots carry on in the same numbering. Step 8 asks
  `Include points up to [Pick/All] <All>` -- type the LAST point
  number that belongs to the pool edge, or `Pick` that point in the
  drawing and CABHD reads its number off the block. Enter (or `All`)
  keeps every point, which is ABHD's behaviour. Everything past the
  cutoff is out ENTIRELY: not ordered into the loop, not fitted, not
  counted against the miss allowance, and never reported as a point
  the line failed to hold.
* **Left out: the pool bottom.** No shallow/deep breaks, no hopper, no
  slope lines. The command ends at the kept perimeter.

Everything else is ABHD's: eight questions (max distance from a point,
percent of points allowed off, curve cap, declared straight walls,
sharp corners, held points, the selection, then the cutoff), two modes
picked from the selection (guided when POOL geometry is included,
points-only otherwise), arcs from survey point to survey point meeting
within 8 degrees of tangent, no arc curving further than the points it
covers actually turn (plus `*CAB-ARC-SLACK*`, 60 degrees), up to
`*CAB-DROP-PCT*` (10%) of the points given up on where one is plainly
off -- past `*CAB-DROP-MULT*` (2x) the distance you typed -- and
holding it would break the shape, nice radii (whole feet, half feet,
whole inches), and **three candidate fits** drawn at once -- most
curves / as asked / fewest curves -- chosen with
`[1/2/3/All/None/Redo]` or by clicking an outline. `Redo` refits
without leaving the command: omit points by clicking them, move the
cutoff either way, and edit walls, corners and holds with
`[Add/Remove/Keep] <Keep>` loops.

The kept fit is a single closed LWPOLYLINE: candidates preview on
`POOL-FIT`, the keeper moves onto `POOL`. Points the fit could not
hold are ringed on `FGStep` and listed worst first by their `ab_pt`
numbers.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `CABHD.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Draw or import the survey (POINT entities on layer `POINTS`, or
   `ab_pt` block inserts on any layer -- the block's `number`
   attribute is what the cutoff reads), then run:

| Command | What it does |
| --- | --- |
| `CABHD` | Fit the perimeter, and only the perimeter |
| `CABHDVER` | Print the loaded version |

## Tunables

All at the top of `CABHD.lsp`; the key ones:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*CAB-POOL-LAYER*` | `"POOL"` | Layer of the (optional) drawn perimeter guide |
| `*CAB-POINT-LAYER*` | `"POINTS"` | Layer of plain survey POINTs |
| `*CAB-POINT-BLOCK*` | `"ab_pt"` | Block whose inserts count as survey points |
| `*CAB-PT-TAG*` | `"number"` | Attribute tag carrying the point number |
| `*CAB-OUT-LAYER*` | `"POOL-FIT"` | Layer the candidate fits preview on |
| `*CAB-MISS-LAYER*` | `"FGStep"` | Layer for the missed-point rings and list |
| `*CAB-WALL-LAYER*` | `"POOL-WALLS"` | Layer for declared-wall markers |
| `*CAB-TOL-MAX*` | `2.0` | Hard ceiling on the max-distance prompt (2") |
| `*CAB-MISS-PCT*` | `0.15` | Standard share of points allowed off (rounded up) |
| `*CAB-ON-EPS*` | `0.25` | Within this of the result counts as ON it |
| `*CAB-CORNER-ANG*` | 45 deg | Turning more than this is a sharp corner |
| `*CAB-TANG-TOL*` | 8 deg | Tangency window at every arc joint |
| `*CAB-NICE-RADII*` | `(12.0 6.0 1.0)` | Radius snap increments: feet, half feet, inches |
| `*CAB-TIGHT-TOL*` | `0.01` | What the "tight" candidate fits to |

## Notes & limitations

* The point number is read as the first run of digits in the label:
  `17`, `P17` and `17A` all read as seventeen. A point whose label
  holds no digit falls back to its place in the selection, and CABHD
  says so before asking. A cutoff that would starve the fit is refused
  and re-asked.
* A straight wall, sharp corner or held point declared on a point the
  cutoff drops is dropped with it and said so -- never quietly snapped
  onto some other point. The miss allowance is a share of the points
  the cutoff KEPT.
* Everything is fitted on the 2D plane; Z coordinates are ignored.
* A candidate can come out too degenerate for AutoCAD to accept
  (likeliest the tight fit on a survey read whole); the table marks it
  `would not draw`, Enter defaults to one that did, and only when none
  draws is the run a dead end -- it then says which cutoff to try.
* Everything CABHD draws to help you decide -- markers, candidate
  outlines, labels -- is stamped as its own and sweeps itself when the
  command ends, Esc included. ABHD's stamped work is left alone and
  never read back as guide geometry. On `FGStep` only its own stamped
  objects are ever erased.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  AutoCAD LT has no LISP engine and cannot run this file.

## Tests

`python3 tests/test_cabhd.py` drives the whole of `c:CABHD` in the
repo's AutoLISP VM against a 30-point survey whose last 12 points are
a step run: the fit must use the first 18 and ignore the 12 -- in the
loop, the report and the miss allowance -- the cutoff is moved both
ways at a Redo, and the absence of any pool-bottom prompt is checked
both at runtime and structurally.
`CALOFIN_LISP_ROOT=shared python3 tests/test_cabhd.py` reruns it
against the grouped build. The fitter maths itself is pinned by
`tests/test_pool_fit.py` (shared with ABHD).
