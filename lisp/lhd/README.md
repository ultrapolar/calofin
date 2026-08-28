# LHD - fit a top-down outline through laser-scanned points

The laser-point sibling of [ABHD](../abhd/). ABHD fits a pool
perimeter through `ab_pt` survey blocks; **LHD** fits the same kind of
arcs-on-the-points outline through the points a laser scan of an
uneven surface leaves in the drawing - and it can fit an **open** run
as well as a closed one.

```
Command:  LHD
Load:     (load "lhd.lsp")
```

## What it does

1. Asks the same numbers as ABHD: max distance from a point (step 1),
   percent of points allowed off (step 2), curve cap (step 3).
2. Asks whether the result should be a **Closed** outline or an
   **Open** polyline (step 4, remembered per session).
3. Lets you declare dead-straight stretches, sharp corners, and
   **held points** (step 5, one combined loop).  A held point is an
   absolute position - a control shot, a tie-in - that can never be
   fudged: it is never buried inside a span, so every span ends ON it
   and the line passes through it exactly, in all three candidates,
   with no cost to the miss allowance.  The tangency window still
   applies at its joint (it is not a corner), holds are editable on a
   Redo, and the report warns loudly if a declared stretch overruled
   one.
4. Reads the selection (step 6), orders the points, and draws the
   three candidate fits - tight / as asked / few - to pick from,
   with Redo, point omission, and stretch/corner editing, exactly
   as in ABHD.

The fit is a **flat top-down projection**: every coordinate is
flattened to the XY plane before anything is fitted. When the points
carry elevations, those set the single height the finished polyline
is drawn at - LHD asks whether that should be the **Top**most point,
the **Bottom**most, the **Average** of all of them, or **Zero**
(remembered per session). With no elevations anywhere, the outline
lands at height 0 and the question is skipped.

## What counts as a laser point

The classifier is deliberately looser than ABHD's, because scan
exports land in many shapes:

| In the drawing | Counts as | Elevation from |
| --- | --- | --- |
| INSERT of the `ab_pt` block, any layer | a point | its insertion Z, when nonzero |
| plain `POINT` entity, **any layer** | a point | its Z, when nonzero |
| any other INSERT on layer `POINTS` | a point | its insertion Z, when nonzero |
| numeric `TEXT` within 6" of a point | that point's elevation label | its value (decimal or feet-inches) |

Point names for the miss report come from the block's `number`
attribute; a block with no `number` falls back to its first attribute
whose value reads as a number, and unnamed points get selection-order
indices. A point's own Z outranks a nearby elevation text.

## Closed vs open

**Closed** is ABHD's loop engine unchanged: nearest-neighbour tour +
2-opt, arcs grown span by span inside the 8-degree tangent window,
the closing seam held smooth, nice radii preferred.

Both modes carry ABHD's two guards against a shaky scan coming back
as a string of loops: **no arc sweeps further than the run of points
it covers actually turns** (plus `*LH-ARC-SLACK*`, 60 degrees), and a
**run of one-point stubs no longer feeds itself** - one stub carries
the previous tangent on exactly, but a second straight after it keeps
only what the tangent window allows and gives the rest up as a kink,
so a mismatch decays instead of doubling at every stub. On a
60-point scan with half an inch of scatter that is the difference
between 60 hairpins of 4-inch radius and 38 arcs no tighter than
18 inches.

The fit may also **give up on** up to `*LH-DROP-PCT*` (10%) of the
points - left further off than the distance you typed, counted "not
held" and ringed - but only where one is plainly off (past
`*LH-DROP-MULT*`, 2x that distance), only where the span stopped
growing, and only when each point given up buys at least two more
points of span. Held points, declared corners and stretch points are
never given up, and the tight candidate gives up none at all.

**Open** drops the loop. The two ends of the run are the
farthest-apart pair of points (or two points you pick on a Redo -
"Pick the two END points"), the 2-opt keeps both ends fixed, and the
fitter walks the path once: the first span starts free, the last
simply ends at the final point, and one long arc may legally cover
the whole run. There is no seam, so no seam re-run and no closing
tangent window.

A rough **ordering sketch** on layer `POOL` (lines/arcs/polylines)
overrides the automatic order in either mode, and unlike ABHD's it
does not have to close - an open sketch orders an open run.

## Where things land

* Candidates preview on layer `LHD-FIT`; the kept fit moves to layer
  `POOL` in ByLayer colour, like ABHD's, so the rest of the toolset
  can read it.  (Note for mixed drawings: LHD stamps its output with
  its own `LHD` xdata, and skips both `LHD`- and `ABHD`-stamped
  geometry when reading a sketch - but ABHD only skips `ABHD` stamps,
  so an LHD outline left on `POOL` is readable by ABHD as guide
  geometry.  That is by design; erase or move it first if unwanted.)
* Points the kept fit could not hold are ringed on `FGStep` and
  listed beside the shape, worst first - only LHD's own stamped
  objects are ever erased there.
* Declared-stretch and corner markers go on `POOL-WALLS`, dashed, and
  clear themselves when the command ends.

## Version banner and releases

`lhd.lsp` carries the auto-stamped banner `(setq *lh-version* "v1.1")`
that `tools/release_lisp.py` reads; run it after any change and the
dated twin `releases/lhd_MMDDYY_REV11.lsp` regenerates itself. Bump
the banner with every revision.

## Tests

```
python3 tests/test_laser_fit.py    # mirror of the open-path machinery
python3 tools/check_lisp.py  lisp/lhd/lhd.lsp
python3 tools/check_scope.py lisp/lhd/lhd.lsp
```

The closed engine is ABHD's, exercised end to end by
`tests/test_pool_fit.py`; `test_laser_fit.py` covers what is new here
(fixed-end ordering, the linear-index span walker, open vertex lists,
open self-cross, the output-height pick) plus the structural checks
on the `.lsp` file itself.
