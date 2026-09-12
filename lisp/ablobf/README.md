# ABLOBF -- the line of best fit through points, as a POLYLINE (AutoLISP / AutoCAD 2018+)

[LOBF](../lobf/README.md)'s bigger sibling. LOBF answers a row of points
with **one straight line**; ABLOBF answers them with a **polyline** --
arcs and lines threaded through the points the way
[ABHD](../abhd/README.md) threads a pool perimeter, but **open**.

A wall that bows, a coping run round one end of a pool, a bench, a step
nose: anything the points trace that is not a closed loop and is not
straight.

## What makes it different from ABHD

ABHD fits a **loop**, and a loop needs no ends: it closes on itself, and
the seam is the only joint anyone has to argue about. A run that does
not close has **two ends**, and nothing in a cloud of points says which
they are -- so ABLOBF asks.

Click the point the run starts at and the point it ends at, or type the
survey numbers they already carry. Enter takes the farthest-apart pair,
which is right for a run that does not double back and wrong exactly
when it does. Everything else is ordered **between** those two: a
nearest-neighbour walk from the start, the end forced last, then 2-opt
uncrossing with **both ends pinned** (the closed 2-opt's delta prices a
closing edge an open run does not have).

That is the whole of the difference the operator sees. The fitter
underneath is ABHD's, walked in a straight line instead of round a loop.

## What it does

1. **Asks the settings** -- four questions, the same four ABHD and LHD
   ask, each with `Back` (and `Undo` as its hidden synonym):

   | Step | Question |
   | --- | --- |
   | 1 | How far may the fitted run sit from a survey point? (`<1">`, 2" ceiling) |
   | 2 | What percent of the points may sit **off** the run, but still inside that distance? (`<15>`) |
   | 3 | Limit how many curves the result may use? (`<None>`) |
   | 4 | Any dead-straight stretches, sharp corners, or points to hold **absolutely**? |

   A **held point** can never be fudged: no span ever buries one, so
   every span ends *on* it and the run passes through it exactly, in
   every candidate. It costs nothing from the miss allowance, and the
   tangency rule still applies at its joint -- it is a held point, not a
   corner.

2. **Reads the points** -- ABHD's survey classifier:

   * an `INSERT` of the survey point block (`ab_pt`) on any layer; the
     `number` attribute it carries names it in reports **and** is what
     you can type instead of clicking an end;
   * a plain `POINT` entity on **any** layer -- the selection is
     explicit, so there is nothing to guess at;
   * any other `INSERT` sitting on the `POINTS` layer.

   Nothing else. ABLOBF reads no drawn geometry at all: the order of the
   run comes from the two ends and the walk between them, so a window
   dragged over the whole sheet picks up the survey and leaves what is
   drawn alone.

3. **Asks the two ends** (step 6):

   ```
     Step 6 of 6 - where does the run START, and where does it END?
     Click a point or type the survey number it carries; Enter takes
     the farthest-apart pair.  Everything else is ordered between them.
     (11 of 11 selected point(s) carry a number of their own; the rest
     are numbered in the order they were read.)

     Point the run STARTS at [Number/Back] <Pt.1>:
     Point the run ENDS at [Number/Back] <Pt.10>:
     Run: Pt.1 to Pt.10, through 9 point(s) between them.
   ```

   Naming one point for both ends is refused and re-asked -- a run from a
   point to itself is not a run. A number no selected point carries is
   named and re-asked rather than guessed at. `Back` at the second end
   re-opens the first; `Back` at the first hands the whole selection
   back, because nothing is drawn yet and the classifier rebuilds every
   list it fills.

4. **Fits three candidates** and draws them side by side to pick from --
   ABHD's three, numbered on screen in their own colours:

   | # | Aim |
   | - | --- |
   | 1 | **tight** -- most curves, least error: fitted to 0.01", no miss allowance, no curve cap, and it gives up no point at all |
   | 2 | **as asked** -- your settings exactly |
   | 3 | **few** -- fewest curves that still hold the distance you typed |

   A table under them gives segments, curves, worst deviation, average
   over all points, average over the points that are off, and how many
   each fit could not hold. Click the one you want or type its number;
   `All` keeps the three, `None` keeps nothing, and `Redo` is the
   picker's way back -- it re-opens the omit list, the declarations, the
   **ends**, and the settings.

5. **Keeps what you picked** as an **open** `LWPOLYLINE` on the `POOL`
   layer in ByLayer colour -- ABHD's output layer, so the rest of the
   toolset can read the result -- and writes the hit report: points on
   the run, points off within tolerance, points beyond it, worst
   deviation, how many curves pass exactly through a point, how many sit
   on a foot/half/inch radius, and the largest joint kink.

## Install & run

`APPLOAD` `ABLOBF.lsp` (or add it to your Startup Suite), then type
`ABLOBF`. `ABLOBFVER` prints the loaded version. In the grouped build
the file is already there -- `ABLOBF` is one of the commands
`LAZPASS.lsp` brings in.

A pre-selection is honoured: highlight the points first and step 5 is
skipped.

## Tunables

Every setting is in the one configuration block at the top of
`ABLOBF.lsp`. Edit and re-`APPLOAD`, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads. They are LHD's, which are ABHD's,
minus the two that only a laser scan has (the elevation mode and its
label-pairing distance).

| Knob | Default | What changing it does |
| --- | --- | --- |
| `*ABL-POOL-LAYER*` | `"POOL"` | Layer the kept run ends up on -- ABHD's, so the rest of the toolset can read the result |
| `*ABL-POINT-LAYER*` | `"POINTS"` | Layer whose `POINT`s and `INSERT`s are always points |
| `*ABL-POINT-BLOCK*` | `"ab_pt"` | Block name whose `INSERT`s mark points wherever they sit |
| `*ABL-OUT-LAYER*` | `"ABLOBF-FIT"` | Layer the three candidates are drawn on while you choose |
| `*ABL-MISS-LAYER*` | `"FGStep"` | Layer the "could not hold this point" rings go on |
| `*ABL-MISS-RADIUS*` | `4.0` | Radius of those rings (drawing units) |
| `*ABL-PT-TAG*` | `"number"` | The attribute carrying a point's survey number -- what a report calls it, and what you can type to name an end |
| `*ABL-WALL-LAYER*` | `"POOL-WALLS"` | Layer for the dashed markers of declared stretches, corners and held points |
| `*ABL-TOL-MAX*` | `2.0` | Hard ceiling on the max-distance prompt: past this the run is no longer a trace of the points |
| `*ABL-COMPARE*` | three rows | The three candidates offered, as (name, colour, aim). Drop a row and that candidate is not built |
| `*ABL-TIGHT-TOL*` | `0.01` | The tight candidate's accuracy -- how close "least error" means |
| `*ABL-EXACT-EPS*` | `0.001` | Two points closer than this are one shot |
| `*ABL-FIT-EPS*` | `0.01` | How close an arc must pass to an interior point to count as passing *through* it |
| `*ABL-ON-EPS*` | `0.25` | A point within this of the result is reported as ON it |
| `*ABL-MISS-PCT*` | `0.15` | Share of the points (rounded up) allowed off the run -- the default step 2 offers |
| `*ABL-CORNER-ANG*` | `(/ pi 4.0)` | A point turning more than this is a corner on its own, exempt from the tangency rule |
| `*ABL-NICE-RADII*` | `'(12.0 6.0 1.0)` | Preferred arc-radius tiers: a radius near one of these is snapped to it |
| `*ABL-TANG-TOL*` | `(/ pi 22.5)` | Wiggle room from perfect tangency at a joint |
| `*ABL-TANG-STEPS*` | `'(1.0 1.25 1.5)` | How far the tangency window is widened, in turn, when nothing fits inside it |
| `*ABL-ARC-SLACK*` | `(/ pi 3.0)` | How much further than its own chord a span may turn |
| `*ABL-DROP-PCT*` | `0.10` | Share of the points a span may write off to keep growing |
| `*ABL-DROP-MULT*` | `2.0` | How far past the max distance a written-off point may sit |
| `*ABL-SNAP-EPS*` | `0.02` | How far a nice-radius snap may move the arc |
| `*ABL-CHAIN-FUZZ*` | `1.0e-4` | Endpoint-matching fuzz |
| `*ABL-FLOAT-GAIN*` | `2` | How many more points an arc that floats between the points must cover before it beats one passing exactly through one |
| `*ABL-DROP-GAIN*` | `2` | How many more points of span each written-off point must buy |
| `*ABL-ON-FRAC*` | `0.25` | The on-the-shape threshold, as a fraction of the tolerance |
| `*ABL-ANCHOR-EPS*` | `(* 2.0 *ABL-FIT-EPS*)` | How close an arc must pass to count as anchored on a point |
| `*ABL-CAP-RELAX*` | `1.4` | How far the distance is relaxed per refit when a curve cap cannot be met |
| `*ABL-CAP-TRIES*` | `40` | ...and at most this many refits |
| `*ABL-BULGE-CLAMP*` | `1.373` | The half-angle a tangent-window edge may reach, which keeps U-turn geometry finite |
| `*ABL-STRAIGHT-R*` | `1.0e6` | An arc whose radius reaches this is a straight line and is not snapped to a nice radius |
| `*ABL-TOL*` | `1.0` | The distance step 1 offers; it remembers what you answered, per session |

## Notes & limitations

* **One run per command.** ABLOBF fits a single open run between two
  ends. A survey holding two separate walls is two runs -- fit one, then
  the other.
* **Flat (XY).** Points are read at their `X`/`Y` and the run is a
  world-plane polyline; `Z` is ignored. Selected objects drawn in a
  tilted UCS are counted and warned about.
* **No ordering sketch.** LHD lets you draw a rough guide on the `POOL`
  layer to order its points. ABLOBF does not: its ordering authority is
  the two ends plus the walk between them, and a second authority that
  could disagree with them would only be a way to get a confusing
  answer. If the automatic order is wrong, move an end or `Redo` and
  omit the points that are throwing it.
* **No elevations.** A laser scan carries them and a tape survey does
  not, so the output-height question is LHD's, not this one's. The run
  is drawn at `Z` 0.
* **Closed loops are ABHD's job**, not this one's -- `ABHD`, `CABHD`,
  `ADAB` or `LHD`.
* The grouped twin is generated -- run
  `python3 tools/mirror_shared.py ABLOBF` after editing this file, never
  hand-edit `shared/parts/ABLOBF.lsp`.

## Tests

```
python3 tests/test_ablobf.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_ablobf.py # grouped tier
```

The arc math is already covered by `test_abhd_runtime.py` and
`test_laser_fit.py`; this suite is about the open run. It drives the
whole command over three shapes -- a gentle bow, an L, and a run that
**doubles back** on itself so the farthest-apart pair is provably the
wrong answer -- and checks that picking the ends by hand (clicked, and
by typed survey number) changes which run comes out; that the result is
an open polyline with one more vertex than it has segments, starting on
the first point and ending on the last rather than curving back; that
naming one point for both ends is refused; that `Back` at the second end
re-opens the first and `Back` at the first re-opens the selection; and
the wizard around all of it -- six steps, the pickfirst probe, the undo
bracket, the declare loop and its self-clearing markers.
