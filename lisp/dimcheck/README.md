# DIMCHECK — dims, arcs & overlaps QA review (AutoLISP)

An AutoLISP toolset for full AutoCAD that walks a selection one item
at a time — dimension placement, arc-end attachment, and overlapping
lines — fixing what it can, flagging what it can't, and writing
everything to an on-drawing report. The lean pass, for when you just
want the dims/arcs/overlaps check without going through the rest of
the liner-finish gauntlet.

Want steps and side views, wall height, the liner pattern, and the
title block border checked too? See the sibling `lisp/linfincheck/` —
it shares this file's Move/Keep/Pick review, marker colours and report
machinery, just with more rules layered on top.

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
   the anchor rather than dragged off to the line. Anchors are read
   off the selection before the review starts, so one cannot come and
   go partway through.
   Object-associative dims are called out before their points move.
2. **Arcs**, one endpoint at a time — the same Move / Keep / Pick
   choice for an end not attached to another object's end.
3. **Overlapping lines** (and polyline edges) running on top of each
   other — end-to-end touching is fine and not reported. Merge into
   one / Flag / Leave, per pair.

Every rule is spelled out in the file's own header comment and in
`TUTORIALDIMCHECK` (below) — both are generated from the same
tunables, so they can't drift out of sync with what the code actually
does.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `dimcheck.lsp`, and load it
   (add it to the *Startup Suite* to have it every session).
2. Highlight what you want checked, then run one of:

| Command | What it does |
| --- | --- |
| `DIMCHECK` | The full interactive review. Fixes what you approve, flags what you don't. |
| `DIMSCAN` | The same audits, **read-only** — reports everything, changes nothing. Good as a pre-flight. |
| `DIMCHECKRESCUE` | Restores every colour DIMCHECK stashed and clears its report/markers — the way out after a crash, or to remove the marks once you're done with them. |
| `DIMCHECKVER` | Prints which build is loaded. |
| `TUTORIALDIMCHECK` | Teaches the tool — see below. |

A single `U` undoes an entire `DIMCHECK` run, including the report.

## Tunables

Every value DIMCHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `dimcheck.lsp`, each with a comment
saying what it does, its units, and what raising or lowering it
changes. Edit the value and APPLOAD the file again, or type the `setq`
at the command line to try a value for one session — every knob is read
when the command runs, not when the file loads:

```lisp
(setq *dchk-tol* 0.001)    ; gap that still counts as attached
```

**What counts as attached, and what counts as one spot**

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-tol*` | `1.0e-4` | Gap (drawing units) that still counts as attached. Also the smallest move worth asking about, the shortest overlap worth reporting, and the shortest segment admitted to overlap detection |
| `*dchk-anchor-tol*` | `1.0e-4` | How close two dimension points must be to count as the same spot |
| `*dchk-anchor-min*` | `2` | Dimensions meeting there that make it an anchor; `1` would switch the dimension audit off |
| `*dchk-curve-types*` | `LINE ARC CIRCLE ELLIPSE LWPOLYLINE POLYLINE SPLINE` | Entity types a point or an arc end may attach to |
| `*dchk-ask-all-arc-ends*` | `nil` | `T` = confirm every arc endpoint, even attached ones |

**Overlapping lines**

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-olap-fuzz*` | `1.0e-4` | Sideways offset (drawing units) that still counts as the same line |
| `*dchk-olap-dirtol*` | `0.5` | Degrees: how close two segments' directions must be before they are compared at all |
| `*dchk-olap-types*` | `LINE LWPOLYLINE POLYLINE` | Entity types whose straight segments take part |

**Review order**

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-style-order*` | `STANDARD`, `SIDE STANDARD`, `STANDARD INCHES`, `CROSS DIMENSIONS` | Styles reviewed in this order; anything else follows |
| `*dchk-row-band*` / `*dchk-row-flat*` | `0.05` / `1.0` | How far apart two dimensions may sit vertically and still be one row — a fraction of the selection's height, and the band used when it has none |

**Colours** (ACI numbers; the command line and the report name whichever
colour the knob holds, so a changed colour is described correctly)

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-grey-color*` | `8` | Everything not under review, faded |
| `*dchk-flag-color*` | `1` | Dimensions you answered "No" to, and the report's attention lines |
| `*dchk-arc-color*` | `6` | Arcs whose endpoints were moved |
| `*dchk-olap-color*` | `4` | Merged or flagged overlapping lines |
| `*dchk-orig-color*` / `*dchk-sugg-color*` | `1` / `3` | The X where you drew the point, the + where DIMCHECK would put it |
| `*dchk-point-color*` | `2` | The crosses marking an overlap's two ends |
| `*dchk-constr-color*` / `*dchk-report-color*` | `2` / `3` | The colour each layer is created with (an existing layer keeps its own) |

**The two layers**

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-constr-layer*` | `"DIMCHECK-CONSTRUCTION"` | The XLINE through a moved dimension's original points |
| `*dchk-report-layer*` | `"DIMCHECK-REPORT"` | The report MTEXT |

**How the report is sized and placed**

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-green-scale*` | `0.75` | All-clear text height as a fraction of the attention text |
| `*dchk-report-chars*` / `*dchk-sheet-chars*` | `45.0` / `70.0` | Column width in text heights, for the report and for the tutorial's reference sheet |
| `*dchk-report-wide*` | `0.25` | On a wide, short sheet the reference height is at least this fraction of the width |
| `*dchk-report-lead*` | `1.66` | MTEXT line pitch as a multiple of text height |
| `*dchk-report-hmax*` / `*dchk-report-hmin*` | `30.0` / `200.0` | Divisors clamping the text height: never taller than reference/HMAX, never shorter than reference/HMIN — so a *smaller* number is a *looser* bound |
| `*dchk-report-hfall*` | `2.5` | Height used when the selection has no extents to scale against |
| `*dchk-report-gap*` / `*dchk-zoom-out*` | `0.05` / `0.05` | Gap between drawing and report, and the margin around the closing zoom |
| `*dchk-zoom-margin*` | `0.75` | Empty space around one item when the review zooms to it |
| `*dchk-mark-size*` | `0.02` | Half-size of the X and + markers, as a fraction of the view height |
| `*dchk-attn-words*` | `*FLAGGED*,*SKIPPED*,...` | `wcmatch` pattern deciding which report lines render red and full-size. Reword a report note and its word belongs here too |
| `*dchk-dist-mode*` / `*dchk-dist-prec*` | `2` / `4` | `rtos` mode and places for reported distances. A dimension's own measurement is not formatted here — it follows the drawing's LUNITS/LUPREC |

**Numerical guards** (rarely changed)

| Global | Default | Meaning |
| --- | --- | --- |
| `*dchk-same-pt*` | `1e-8` | Two points closer than this are the same point |
| `*dchk-planar-eps*` | `1e-9` | How far an arc's normal may lean from world +Z before it is skipped |
| `*dchk-flat-eps*` | `1e-12` | Below this a polyline bulge is straight, and three points are too collinear to fit an arc through |

## TUTORIALDIMCHECK

Teaches the tool two ways, because people learn differently. It asks
up front — **List**, **Demo**, or **Both**:

* **List** — every check spelled out at the command line, generated
  live from the tunables. Offers to drop the same list into the
  drawing as an MTEXT reference sheet you can plot or keep on a
  layout.
* **Demo** — draws a small practice drawing in an empty spot you pick,
  with three faults planted in it, and walks you through each one,
  zooming in and explaining what DIMCHECK sees:
  1. two lines overlapping,
  2. a dimension point off the geometry (where the red X / green +
     and Move / Keep / Pick choice get explained),
  3. an arc whose ends attach to nothing.

  It then offers to run `DIMSCAN` for a real report, and to erase the
  practice drawing afterwards.
* **Both** — the list, then the demo.

The whole tutorial runs inside one UNDO group and never touches
existing geometry.

## Tests

```
python3 tests/make_test_dxfs.py     # regenerate the fixture drawings under tests/dxf/
```

`tests/expected.md` records what a `DIMSCAN` report on each fixture
must — and must not — say; `tests/run_tests.bat` + `run_tests.scr`
drive `accoreconsole` over every fixture and write one report per
drawing for diffing.

## Notes & limitations

* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**
* Loading both `dimcheck.lsp` and `linfincheck.lsp` in the same
  session is safe — they use distinct `dchk:`/`lfc:` function
  prefixes, `*dchk-`/`*lfc-` globals, layer names, and xdata tags, so
  neither one's rescue command touches the other's markers.
