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
   whether or not steps are drawn, and must be a real calendar date as
   `MM/DD/YYYY` (e.g. `05/01/2024`). Missing, blank, the wrong format,
   or an out-of-range month/day is flagged in red with what's wrong.
7. **Liner Material** — a pattern field reading "Not Supplied" or
   `#ERROR` is wiped back to blank (the label stays, the value goes);
   a Fiberglass Step in the drawing means the liner must *not* carry
   a Step, otherwise drawn steps mean it must.
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
| `LITELINFINSCAN` | The scan minus the `DIMCHECK`-style pass (dimensions, arcs, overlapping lines) — for a drawing `DIMCHECK` already went over, when only the liner-finish rules are wanted. |
| `LINFINCHECKRESCUE` | Restores every colour LINFINCHECK stashed and clears its report/markers — the way out after a crash, or to remove the marks once you're done with them. |
| `LINFINCHECKVER` | Prints which build is loaded. |
| `TUTORIALLINFINCHECK` | Teaches the tool — see below. |

A single `U` undoes an entire `LINFINCHECK` run, including the report.

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
