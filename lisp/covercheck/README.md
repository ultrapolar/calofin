# COVERCHECK -- guided dims, arcs & cover-rules QA review (AutoLISP / AutoCAD 2018+)

DIMCHECK's guided, one-at-a-time review -- dimensions, arc ends and
overlapping lines -- with the pool-cover rules layered on in place of
the liner checks: title-block date, feet-and-inches wording, the
Cover Details overlap/spacing against what the outline says they
should be, the "Pool Size Shown" note, the replacement disclaimer, and
PADDLE-rule pad suggestions. Everything ends in a split on-drawing
report: the cover verdicts lead, the mechanical dimension audit reads
alongside.

## What it does

1. **Highlight the drawing.** Everything selected is greyed out so
   only the item under review stands out.
2. **Dimensions, one at a time**, grouped by style (`STANDARD`, `SIDE
   STANDARD`, `STANDARD INCHES`, `CROSS DIMENSIONS`, then the rest),
   left to right, top to bottom. A definition point off the geometry
   is marked twice -- a red X where you drew it, a green + where it
   would move -- and you choose per point with keywords
   `Move` / `Keep` / `Pick` (default `Move`). Then per dimension:
   `Is this dimension correct? [Yes/No/Back/Skip] <Yes>` -- `No`
   recolours it red to fix later, `Back` redoes the previous item,
   `Skip` stops asking (`Undo` is a hidden synonym for Back).
3. **Arcs**, one endpoint at a time, same Move / Keep / Pick choice;
   arcs whose endpoints changed are recoloured magenta.
4. **Overlapping lines**: each collinear pair running on top of each
   other gets `[Merge/Flag/Leave] <Merge>` (`[Flag/Leave] <Flag>` when
   they cannot be merged); end-to-end touching is fine and not
   reported.
5. **Cover checks** -- nothing here rewrites the drawing; every
   disagreement is only SUGGESTED against, in the report:
   - Tech Title block's Date attribute must read today, MM/DD/YYYY.
   - Feet-and-inches: every text stating feet must state inches
     (`5'` flagged; `5'-0"`, `3'-2"`, plain `40"` fine).
   - Every dimension on the `DIMENSION` layer, strays counted and the
     report says to run `CDIM`.
   - Pool outline found on `POOL` (ByLayer properties; exploded shapes
     chained back together), its area and straight/arc split reported.
   - Cover Details block's Overlap (only 12"/15"/18" exist) and
     Spacing (NxN) checked against what the outline demands: more arcs
     than straights -> 18" and 3x3; mostly straight under 1,200 sq ft
     -> 12" and 5x5; 1,200-2,000 -> 15" and 3x3; over 2,000 -> 18" and
     3x3.
   - "Pool Size Shown" demanded with no cover drawn, flagged when a
     cover is drawn; "Pool Size Shown" plus "Spa Size Shown" together
     is an error.
   - Anything on the cover layer that is not a polyline is called out;
     overlap NA forbids a dashed pool outline, a stated overlap
     demands one.
   - A "Replacement Disclaimer" block should be present; COVERCHECK
     asks whether the drawing is a replacement when it cannot tell
     (COVERSCAN just notes the block is not there).
   - **Pads**: the outline is run through PADDLE's concave-feature
     rules at 36" -- inside corners, concave radii of 4'-6" or less,
     10-degree semi-straight pass-over, no overlapping suggestions --
     and every spot with no pad already nearby is circled and
     suggested.
6. **The report** (MTEXT) is placed to the right of the drawing on
   layer `COVERCHECK-REPORT`, findings that need looking over in red
   at full height, everything that checked out smaller. The
   DIMCHECK-style findings go in a separate DIMENSION AUDIT column.

All original colours are restored when the review ends -- except the
red flagged dims, magenta moved arcs and cyan merged/flagged lines,
which stay marked on purpose. The whole run (report included) is one
undo group; a single `U` reverts it. A rerun replaces the previous
report and markers instead of stacking a second copy.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `covercheck.lsp`, and load it
   (add it to the *Startup Suite* to have it every session). The
   shared build (`shared/LAZPASS.lsp`) carries it too.
2. Run one of:

| Command | What it does |
| --- | --- |
| `COVERCHECK` | The full interactive review; fixes what you approve, flags the rest |
| `COVERSCAN` | The same audits, read-only -- reports everything, changes nothing |
| `LITECOVERSCAN` | COVERSCAN minus the dimension/arc/overlap audit -- just the cover rules, for a drawing DIMCHECK already went over |
| `COVERCHECKRESCUE` | Restores every colour COVERCHECK stashed and clears its report and markers -- the way out after a crash |
| `COVERCHECKVER` | Print which build is loaded (`COVERCHECKVERSION`, the pre-standard name, is kept as an alias) |
| `TUTORIALCOVERCHECK` | Builds a practice cover sheet with planted faults and walks the review on it |
| `TUTORIALCOVERCHECKCLEAN` | Erases everything the tutorial built, report and markers included |

## Tunables

The full set sits at the top of `covercheck.lsp`; the ones most worth
knowing:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*cchk-style-order*` | `STANDARD`, `SIDE STANDARD`, `STANDARD INCHES`, `CROSS DIMENSIONS` | Review order of dimension styles |
| `*cchk-dim-layer*` | `"DIMENSION"` | Layer every dimension belongs on |
| `*cchk-title-block*` / `*cchk-date-tag*` | `"Tech Title"` / `"Date"` | Where the sheet date lives |
| `*cchk-pool-layer*` / `*cchk-cover-layer*` | `"POOL"` / `"COVER"` | Outline and drawn-cover layers |
| `*cchk-details-block*` | `"Cover Details"` | Block carrying Overlap and Spacing |
| `*cchk-overlap-vals*` | `12 15 18` | The only overlaps that exist (inches) |
| `*cchk-area-small*` / `*cchk-area-large*` | `1200` / `2000` | Sq-ft breakpoints for the overlap/spacing rule |
| `*cchk-pad-size*` / `*cchk-pad-maxrad*` | `36.0` / `54.0` | Pad size and the largest concave radius needing pads |
| `*cchk-pad-blocks*` / `*cchk-pads-layer*` | `Pad36x36`, `Pad24x24` / `"PADS"` | What counts as an existing pad |
| `*cchk-repl-block*` | `"Replacement Disclaimer"` | Block demanded on replacement drawings |
| `*cchk-ask-all-arc-ends*` | `nil` | `T` = confirm every arc endpoint, even attached ones |

## Notes & limitations

* Requires the Visual LISP engine, which ships with full AutoCAD.
  AutoCAD LT has no LISP engine and cannot run this file.
* Loading `covercheck.lsp` next to `dimcheck.lsp` or `linfincheck.lsp`
  is safe: distinct `cchk:` prefix, `COVERCHECK` xdata tag and
  `COVERCHECK-*` layers mean neither one's rescue touches the other's
  marks.
* The Move/Keep/Pick bracket text spells the choices out
  (`[Move to the green +/Keep at the red X/Pick a spot]`) while the
  keywords are the bare `Move Keep Pick` -- clicking the phrases does
  not send a valid keyword; type `M`, `K` or `P`. A known migration
  item (`STANDARDS.md` section 7.2).
* The pad hunt is a **port** of PADDLE's rules carried inside this
  file (a standalone file cannot call `PADDLE.lsp`); when PADDLE's
  rules change the port must move with them -- the test below is what
  makes that drift loud.
* Object-associative dimensions are warned about before their points
  move, and their report line says so in red.

## Tests

`python3 tests/test_covercheck_pads.py` loads the real
`covercheck.lsp` and `PADDLE.lsp` into one AutoLISP VM session and
runs both pad implementations against the same outlines -- every
suggested pad's position, kind and count must agree, so the ported
rules cannot drift silently. The rest of the tool is covered at load
level by `python3 tests/test_shared.py` (everything loads together,
no name collisions). `CALOFIN_LISP_ROOT=shared` reruns the pads test
against the grouped build.
