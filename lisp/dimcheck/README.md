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
