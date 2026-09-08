# LINFINCHECK — the full liner-finish drawing QA (AutoLISP)

An AutoLISP toolset for full AutoCAD that walks a highlighted title
block one item at a time — dimensions, arcs, overlapping lines, steps
and their side views, the Tech Title's wall height, the liner pattern,
and the title block border — fixing what it can, flagging what it
can't, and writing everything to an on-drawing report.

Just want the dimension/arc/overlap pass without the rest of the
liner-finish gauntlet? See the sibling `lisp/dimcheck/` — it shares
this file's Move/Keep/Pick review, marker colours and report machinery
for exactly those three checks, standalone.

## What it checks

1. **Dimensions**, one at a time, grouped by dimension style
   (`STANDARD` → `SIDE STANDARD` → `STANDARD INCHES` →
   `CROSS DIMENSIONS` → anything else), then left to right, top to
   bottom inside each group. A definition point off the geometry gets
   a Move (onto the nearest object) / Keep (exactly where you drew it)
   / Pick (your own spot) choice, both candidates marked on screen.
   A point **two or more dimensions measure to** is an **anchor** and
   is never questioned, geometry under it or not: dimensioning twice
   to the same spot — the pair of dims pinning down a hypotenuse
   corner is the everyday case — is how you say that spot is the
   object. A stray point nearer an anchor than any line is offered
   the anchor rather than dragged off to the line.
   Object-associative dims are called out before their points move.
2. **Arcs**, one endpoint at a time — the same Move / Keep / Pick
   choice for an end not attached to another object's end.
3. **Overlapping lines** (and polyline edges) running on top of each
   other — end-to-end touching is fine and not reported. Merge into
   one / Flag / Leave, per pair.
4. **Steps, benches and side views** — 3+ (or, for a bench, 2+)
   parallel lines stacked under 18" apart. A side view is detected
   automatically when two such patterns sit at right angles and march
   along like a profile. Requires a `Step Attachment` block; a
   `Bead Step Attachment` additionally requires geometry on the
   `Bead Track` layer near each plan-view pattern. A generic
   attachment block still listing every option (`Bead` / `Flaps` /
   `Rod Pockets` / `No Attachment`) means nobody picked one — fine
   only if a "to be secured?" note asks the customer.
5. **Wall height** — the `Tech Title` block's `WallHt` is read
   whether or not steps are drawn, understands `40''`, `3'-4''`,
   `3' 4 1/2''`, `40.5`, several values at once, `Varies`, and `?`
   (fine only with a "Wall height" note asking the customer), and
   flags a lone `0''` as nonsensical. A side-view height dimension
   that disagrees is marked red automatically.
6. **Date** — the `Tech Title` block's `Date` attribute is read
   whether or not steps are drawn, and must read **today** as
   `MM/DD/YYYY` (e.g. `05/01/2024`). Missing, blank, the wrong format,
   an out-of-range month/day or an old date is **rewritten to today
   in that same form**, keeping any `Date =` label in front of it, and
   the report says in red what it found and what it set. A date built
   into the block definition instead of an attribute is shared by
   every insert of that block, so that one is reported and left alone.
   `LINFINSCAN` says NEEDS UPDATING and writes nothing.
7. **Liner Material** — a pattern field reading "Not Supplied" or
   `#ERROR` has **that phrase** wiped out of it and keeps the rest:
   `Pattern: Not Supplied` → `Pattern:`, `Blue Granite - Not Supplied`
   → `Blue Granite`. A field that held nothing else comes back blank,
   and a real pattern name is never touched. A Fiberglass Step in the
   drawing means the liner must *not* carry a Step, otherwise drawn
   steps mean it must.
8. **Title block border** — the outer drawing on the `border` layer
   must be 58'-8" × 45'-3 5/8" or a scaled-**up** multiple; smaller is
   flagged as "should not be SCALED DOWN for Liners".

Every rule, and the exact numbers behind it, is spelled out in the
file's own header comment and in `TUTORIALLINFINCHECK` (below) — both
are generated from the same tunables, so they can't drift out of sync
with what the code actually does.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `linfincheck.lsp`, and load it
   (add it to the *Startup Suite* to have it every session).
2. Highlight the title block — the whole thing, so the border and the
   Tech Title are included — then run one of:

| Command | What it does |
| --- | --- |
| `LINFINCHECK` | The full interactive review. Fixes what you approve, flags what you don't. |
| `LINFINSCAN` | The same audits, **read-only** — reports everything, changes nothing. Good as a pre-flight. |
| `LITELINFINSCAN` | The scan minus the `DIMCHECK`-style pass (dimensions, arcs, overlapping lines) — for a drawing `DIMCHECK` already went over, when only the liner-finish rules are wanted. It keeps the dimension-layer verdict (which tells you to run `CDIM`) and the feet-and-inches check. |
| `LINFINCHECKRESCUE` | Restores every colour LINFINCHECK stashed and clears its report/markers — the way out after a crash, or to remove the marks once you're done with them. |
| `LINFINCHECKVER` | Prints which build is loaded. |
| `TUTORIALLINFINCHECK` | Teaches the tool — see below. |

A single `U` undoes an entire `LINFINCHECK` run, including the report.

## Tunables

Every value LINFINCHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `linfincheck.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**The liner rules: steps**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-step-maxgap*` / `*lfc-step-minlines*` / `*lfc-bench-minlines*` / `*lfc-step-angtol*` | `18.0` / `3` / `2` / `1.0` | Treads are found as stacked parallel lines. MAXGAP is the widest spacing that still reads as one flight (raise it for a drawing with deeper treads); MINLINES is how many stacked lines make a staircase in plan; BENCH-MINLINES the same in the side view, where a bench profile is only two treads deep; ANGTOL how far from parallel two treads may sit (drawing units; lines; degrees) |
| `*lfc-bead-layer*` / `*lfc-bead-dist*` | `"Bead Track"` / `18.0` | Bead track: the layer it belongs on, and how close to the plan-view steps it has to run before it counts as tracking them (drawing units) |
| `*lfc-attach-options*` / `*lfc-secured-phrase*` | `'("Bead" "Flaps" "Rod Pockets" "No Attachment"` / `"to be secured"` | The generic Step Attachment block lists every option with a box; if ALL of them are still showing, nobody picked one, and the drawing must carry the question note instead |
| `*lfc-fgstep-words*` | `'("Fiberglass Step" "FG Step")` | A fiberglass step shows up under any of these names |

**The liner rules: the title block**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-title-block*` / `*lfc-wallht-tag*` / `*lfc-date-tag*` | `"Tech Title"` / `"WallHt"` / `"Date"` | The title block holding the wall height and the sheet date, and the two attribute tags inside it. Spaces in the block name are optional when it is searched for |
| `*lfc-height-tol*` | `0.25` | The step height and WallHt may differ by this much before the report says to check the wall height (drawing units) |
| `*lfc-min-wallht*` | `1.0` | ...and a WallHt below this is NONSENSICAL rather than merely wrong (0" walls do not exist) (drawing units) |
| `*lfc-ask-phrase*` | `"Wall height"` | The question text expected in the drawing when WallHt reads "?" |
| `*lfc-badwords*` | `'("NOT" "ERROR")` | A liner pattern field carrying one of these words was never really filled in ("Not Supplied", "#ERROR") -- LINFINCHECK takes that phrase, and only that phrase, back out. Matching is case-blind on whole words |

**The liner rules: the drawing border**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-border-layer*` / `*lfc-border-w*` / `*lfc-border-h*` / `*lfc-border-tol*` | `"border"` / `704.0` / `543.625` / `0.005` | The title block border is nominally 58'-8" x 45'-3 5/8", or a scaled-UP whole multiple of it, on this layer. TOL is the slack allowed on both the scale factor and the aspect ratio (58'-8"     in drawing units; 45'-3 5/8" in drawing units; 0.5%, as a fraction) |
| `*lfc-block-depth*` | `3` | How many levels of nested block to search when looking for a name or a piece of text. Raising it finds text buried deeper, at the cost of a slower sweep (levels) |

**What counts as attached, and what counts as one spot**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-tol*` | `1.0e-4` | A dimension point or an arc end within this distance of an object is ATTACHED and is not questioned. It has three more jobs: the smallest move worth asking about, the shortest overlap worth reporting, and the shortest segment admitted to overlap detection. Raising it asks fewer questions on all four counts (drawing units) |
| `*lfc-anchor-tol*` | `1.0e-4` | How close two dimension points must be to count as the same spot (drawing units) |
| `*lfc-anchor-min*` | `2` | ...and how many dimensions must meet there to make it an ANCHOR: a point left as drawn, geometry under it or not (the pair of dims pinning a hypotenuse corner is the everyday case). 1 would make every point an anchor and switch the dimension audit off (dimensions meeting at one spot) |
| `*lfc-curve-types*` | `'("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"` | Entity types a dimension point or an arc end may attach to. Each must be a curve AutoCAD can measure to (vlax-curve-*) |
| `*lfc-ask-all-arc-ends*` | `nil` | T = confirm EVERY arc endpoint, even ones already attached |

**Overlapping lines**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-olap-fuzz*` | `1.0e-4` | How far apart two parallel lines may sit and still be called the same line. Raising it calls more near-misses an overlap (drawing units, sideways offset) |
| `*lfc-olap-dirtol*` | `0.5` | Two segments are only tested for overlap when their directions are within this of each other. It is a bucketing shortcut, not a rule: keep it comfortably wider than the angle *lfc-olap-fuzz* implies over a segment's length, or a genuine overlap is never compared (degrees) |
| `*lfc-olap-types*` | `'("LINE" "LWPOLYLINE" "POLYLINE")` | Entity types whose straight segments take part in overlap detection. Arcs, circles and splines have no straight run to overlap, which is why this is a shorter list than *lfc-curve-types* |

**Review order**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-style-order*` | `'("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"` | Dimension styles are reviewed in this order; styles not listed come afterwards ("whatever else is left"), still left-to-right. Matching is by exact name, case-blind |
| `*lfc-dim-layer*` / `*lfc-dimfix-cmd*` | `"DIMENSION"` / `"CDIM"` | Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what the report tells you to run |
| `*lfc-row-band*` / `*lfc-row-flat*` | `0.05` / `1.0` | Within a style, dimensions are reviewed row by row. Two dimensions count as the same ROW when their midpoints are within this fraction of the selection's height. Raise it and a whole sheet becomes one row (pure left-to-right); lower it and near-level dims split apart (fraction of the selection's height; ...and the band for a selection with no height) |

**Colours**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-grey-color*` / `*lfc-flag-color*` / `*lfc-arc-color*` / `*lfc-olap-color*` / `*lfc-orig-color*` / `*lfc-sugg-color*` / `*lfc-point-color*` | `8` / `1` / `6` / `4` / `1` / `3` / `2` | ACI: everything not under review, faded (grey); ACI: what you answered "No" to (red); ACI: arcs whose endpoints were moved (magenta); ACI: merged or flagged overlapping lines (cyan); ACI: the X marking where you drew the point (red); ACI: the + marking where LINFINCHECK would put it (green); ACI: the crosses marking an overlap's two ends (yellow) |

**The two layers**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-constr-layer*` / `*lfc-constr-color*` / `*lfc-report-layer*` / `*lfc-report-color*` | `"LINFINCHECK-CONSTRUCTION"` / `2` / `"LINFINCHECK-REPORT"` / `3` | The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are created on first use; the colour applies only then, so a layer already in the drawing keeps its own (ACI (yellow); ACI (green)) |

**How the report is sized and placed**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-green-scale*` | `0.75` | All-clear lines are written at this fraction of the height the red attention lines get, so problems stand out. 1.0 = same size |
| `*lfc-report-chars*` / `*lfc-sheet-chars*` | `45.0` / `70.0` | Report column width, in text heights, and the width of the tutorial's reference sheet, which is prose rather than a column of findings and so runs wider |
| `*lfc-report-wide*` | `0.25` | The report is scaled to the drawing: its text height is chosen so the whole report is about as tall as the drawing. On a wide, short sheet that would give a tiny report, so the reference height is at least this fraction of the drawing's WIDTH |
| `*lfc-report-lead*` | `1.66` | MTEXT line pitch as a multiple of text height, used to turn a line count into a height. AutoCAD's default single spacing is 1.66 |
| `*lfc-report-hmax*` / `*lfc-report-hmin*` | `30.0` / `200.0` | ...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both are DIVISORS, so a smaller number is a looser bound |
| `*lfc-report-hfall*` | `2.5` | The height used when the selection has no extents to scale against (DIMTXT x DIMSCALE is tried first), and the default offered for the tutorial's reference sheet (drawing units) |
| `*lfc-report-gap*` / `*lfc-zoom-out*` | `0.05` / `0.05` | Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around the closing zoom |
| `*lfc-zoom-margin*` | `0.75` | Empty space around ONE item when the review zooms to it, as a fraction of its size |
| `*lfc-mark-size*` | `0.02` | Half-size of the X and + markers drawn while you answer, as a fraction of the current view height -- so they stay the same size on screen however far you are zoomed in (fraction of VIEWSIZE) |
| `*lfc-attn-words*` | `"*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO SIDE VIEW*,*NO 'STEP*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*NOT ATTACHED*,*OVERLAP*,*CHECK THE WALL HEIGHT*,*FIBERGLASS STEP*,*ASSOCIATIVE*,*DISAGREE*,*SCALED DOWN*,*STRETCHED*,*NO BORDER*,*WIPED*,*NEEDS WIPING*,*NONSENSICAL*,*EXPECTED MM/DD/YYYY*,*NO INCHES*,*NOT TODAY*,*NEEDS UPDATING*,*UPDATED TO*"` | A report line is rendered red and full-size when it matches this pattern (wcmatch, case-blind; comma separates alternatives). These are the words the report's own notes use for something that needs looking at -- reword a note and its word belongs here too, or the line quietly stops being red |
| `*lfc-dist-mode*` / `*lfc-dist-prec*` | `2` / `4` | Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engineering, 4 architectural (feet-inches); prec is decimal places (for mode 4: the inch is split 2^prec ways). The dimension's own MEASUREMENT is not formatted here -- it follows the drawing's LUNITS/LUPREC, which is what the drafter reads on the sheet (rtos mode; decimal places) |

**Numerical guards (rarely changed)**

| Global | Default | Meaning |
| --- | --- | --- |
| `*lfc-same-pt*` | `1e-8` | Two points closer than this are the SAME point: no construction line is drawn through them, no joining line between an X and a +, and an arc is never re-fitted onto its own other end (drawing units) |
| `*lfc-planar-eps*` | `1e-9` | How far an arc's extrusion normal (DXF 210) may lean from world +Z and still be audited; beyond it the arc is skipped rather than re-fitted in the wrong plane (dimensionless (normal components)) |
| `*lfc-flat-eps*` | `1e-12` | Below this a polyline bulge is treated as straight, so the edge joins overlap detection, and three points are too collinear to fit an arc through |

## TUTORIALLINFINCHECK

Teaches the tool two ways, because people learn differently. It asks
up front — **List**, **Demo**, or **Both**:

* **List** — every check spelled out at the command line, generated
  live from the tunables so it always quotes the real tread spacing,
  layer names and border size. Offers to drop the same list into the
  drawing as an MTEXT reference sheet you can plot or keep on a
  layout.
* **Demo** — draws a small practice drawing in an empty spot you pick,
  with four faults planted in it, and walks you through each one,
  zooming in and explaining what LINFINCHECK sees:
  1. two lines overlapping,
  2. a dimension point off the geometry (where the red X / green +
     and Move / Keep / Pick choice get explained),
  3. a step side view with its overall-height dimension,
  4. an arc whose ends attach to nothing.

  It then offers to run `LINFINSCAN` for a real report, and to erase
  the practice drawing afterwards.
* **Both** — the list, then the demo.

The whole tutorial runs inside one UNDO group and never touches
existing geometry.

## Tests

```
python3 tests/make_test_dxfs.py     # regenerate the fixture drawings under tests/dxf/
```

`tests/expected.md` records what a `LINFINSCAN` report on each fixture
must — and must not — say; `tests/run_tests.bat` + `run_tests.scr`
drive `accoreconsole` over every fixture and write one report per
drawing for diffing. See `tests/expected.md`'s own notes for which
pairs of fixtures guard which regressions (a step side view drawn as
one polyline vs. as separate lines, a plain rectangle that must never
read as a side view, and so on).

## Notes & limitations

* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**
* The step/side-view/border/wall-height rules assume 1 drawing unit
  = 1 inch; running on a metric drawing needs the relevant tunables
  (`*lfc-step-maxgap*`, `*lfc-bead-dist*`, `*lfc-border-w*`,
  `*lfc-border-h*`) rescaled at the top of the file.
* Loading both `linfincheck.lsp` and `dimcheck.lsp` in the same
  session is safe — they use distinct `lfc:`/`dchk:` function
  prefixes, `*lfc-`/`*dchk-` globals, layer names, and xdata tags, so
  neither one's rescue command touches the other's markers.
