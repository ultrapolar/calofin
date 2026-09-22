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
  drawing (click it, or type its number the way `PERPMARK` takes one)
  and CABHD reads its number off the block. Enter (or `All`)
  keeps every point, which is ABHD's behaviour. Everything past the
  cutoff is out ENTIRELY: not ordered into the loop, not fitted, not
  counted against the miss allowance, and never reported as a point
  the line failed to hold.
* **Added: leaving points out, up front.** With the survey selected
  and the cutoff run, **step 9** asks which of the pool's OWN shots
  the fit should not chase -- the one on the coping, the double-shot,
  the rod held crooked. Every pick toggles, so naming a ringed one
  again puts it back, and `Enter` takes none of them. This is not the
  cutoff: the cutoff draws one line across the whole survey and
  everything past it stops being a pool-edge shot at all; this picks
  out strays one at a time, and each one it takes is still **measured
  against the fit you keep**, ringed on `FGStep` beside the points the
  fit missed and listed with how far off it landed -- that number is
  what says whether leaving it out was right. Under the list goes one
  line naming every bad point, `- Pt.12, Pt.15 and Pt.20 are bad.`, in
  `BPCALLOUT`'s wording, so a sheet reads the same sentence whichever
  tool wrote it. A `Redo` asks again.
* **Left out: the pool bottom.** No shallow/deep breaks, no hopper, no
  slope lines. The command ends at the kept perimeter.

Points numbered with an **`m`** are out too, and out before the cutoff
is even asked -- ABFIND writes `17m` when it copies Pt.17 to a
position it *deduced* from two tape readings, so nobody stood there.
The cutoff and the omit list both keep a point and decide about it; a
moved point is not in the survey to be decided about.

Everything else is ABHD's: nine questions (max distance from a point,
percent of points allowed off, curve cap, declared straight walls,
sharp corners, held points, the selection, the cutoff, then the points
to leave out), two modes
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
without leaving the command: leave more points out by clicking them,
move the cutoff either way, and edit walls, corners and holds with
`[Add/Remove/Keep] <Keep>` loops.

The kept fit is a single closed LWPOLYLINE: candidates preview on
`POOL-FIT`, the keeper moves onto `POOL`. Points the fit could not
hold -- and the points you left out, tagged `(left out)` -- are ringed
on `FGStep` and listed worst first by their `ab_pt` numbers, with one
line under them naming them all:

```
POINTS OFF THE LINE (4)
Pt.8    off by 1-7/8"
Pt.7    off by 1-5/16"
Pt.51   off by 1-1/16"
Pt.23   off by 4-1/2"   (left out)
- Pt.8, Pt.7, Pt.51 and Pt.23 are bad.
```

What the **cutoff** dropped is in none of that: a bench shot is not a
bad pool-edge shot.

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
| `*CAB-MOVED-MARK*` | `"M"` | A number carrying this letter is a *moved* point (ABFIND's `17m`) and is left out of the fit entirely |
| `*CAB-SNAP*` | `12.0` | How close a **click** has to land to a survey point to name it -- at a wall end, a corner, a held point, the cutoff's `Pick`, an omit. A typed number never uses it. The radius `BPCALLOUT`, `ABFIND` and `PERPMARK` share |
| `*CAB-OUT-LAYER*` | `"POOL-FIT"` | Layer the candidate fits preview on |
| `*CAB-MISS-LAYER*` | `"FGStep"` | Layer for the missed-point rings and list |
| `*CAB-BAD-PREFIX*` | `"- "` | What the one line naming every bad point leads with -- ABFIND's note prefix, so a sheet's notes read as one column |
| `*CAB-BAD-ONE*` / `*CAB-BAD-MANY*` | `" is bad."` / `" are bad."` | Its tail, by count: `- Pt.12 is bad.` / `- Pt.12, Pt.15 and Pt.20 are bad.` -- BPCALLOUT's wording |
| `*CAB-OMIT-TAIL*` | `"   (left out)"` | What marks a left-out point's row apart from one the fit tried to hold and missed |
| `*CAB-WALL-LAYER*` | `"POOL-WALLS"` | Layer for declared-wall markers |
| `*CAB-TOL-MAX*` | `2.0` | Hard ceiling on the max-distance prompt (2") |
| `*CAB-MISS-PCT*` | `0.20` | Recommended share of points allowed off (rounded up) |
| `*CAB-ARC-DIV*` | `3.0` | The recommended curve cap: one curve per this many kept points, rounded to nearest, never below 1 |
| `*CAB-ON-EPS*` | `0.25` | Within this of the result counts as ON it |
| `*CAB-CORNER-ANG*` | 45 deg | Turning more than this is a sharp corner |
| `*CAB-TANG-TOL*` | 8 deg | Tangency window at every arc joint |
| `*CAB-NICE-RADII*` | `(12.0 6.0 1.0)` | Radius snap increments: feet, half feet, inches |
| `*CAB-TIGHT-TOL*` | `0.01` | What the "tight" candidate fits to |

Its **fitter knobs are shared with ABHD**: the span fitter is ABHD's,
carried over word for word, so every tuning constant it reads exists
under all three prefixes (`*PF-`, `*LH-`, `*CAB-`) -- the tangency
window and its stretch steps, the arc slack, the give-up budget and
what a written-off point must buy, the curve cap's relaxing refits,
the bulge clamp -- at the same value, with one deliberate exception.
`tests/test_laser_fit.py` and `tests/test_cabhd.py` compare that
fitter code for code against `abhd.lsp`, so a knob moved in one file
has to move in all three.

The exception is **`*-MISS-PCT*`**, which is not really a fitter knob
but the share the command *recommends* at its own prompt, and the two
surveys are not the same survey. `*PF-` and `*CAB-` offer **20%**,
because an AB survey of a built shell measures that way; `*LH-` stays
at **15%**, because a laser scan is a finer instrument than a tape and
a rod. The fitter reads whichever its own command was given, through
`pf:misspct` / `cab:misspct` / `lh:misspct`, so the shared code is
still identical.

## Notes & limitations

* The point number is read as the first run of digits in the label:
  `17`, `P17` and `17A` all read as seventeen. A point whose label
  holds no digit falls back to its place in the selection, and CABHD
  says so before asking. A cutoff that would starve the fit is refused
  and re-asked.
* Every question about a survey point -- a wall end, a corner, a held
  point, the cutoff's `Pick`, a point to omit -- **names** one, the
  way `PERPMARK` does: click the point, or type its number (`17`,
  `Pt.17`, `#17` and `017` are the same point). A click has to land
  within `*CAB-SNAP*` of a point; a click on nothing, a number nothing
  carries and a number two points share are re-asked where they
  stand, never snapped to whatever was nearest.
* A straight wall, sharp corner or held point is declared before the
  selection and matched to the fit afterwards by the point's own
  identity. One declared on a point the cutoff drops, or that was
  never selected, is named and dropped with the reason -- `(Pt.24
  sits past the cutoff - the hold declared on it is dropped)` -- never
  quietly snapped onto some other point. The miss allowance is a share
  of the points the cutoff KEPT.
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
