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
   A point **two or more dimensions measure to** is an **anchor** and
   is never questioned, geometry under it or not: dimensioning twice
   to the same spot — the pair of dims pinning down a hypotenuse
   corner is the everyday case — is how you say that spot is the
   object. A stray point nearer an anchor than any line is offered
   the anchor rather than dragged off to the line.
3. **Arcs**, one endpoint at a time, same Move / Keep / Pick choice;
   arcs whose endpoints changed are recoloured magenta.
4. **Overlapping lines**: each collinear pair running on top of each
   other gets `[Merge/Flag/Leave] <Merge>` (`[Flag/Leave] <Flag>` when
   they cannot be merged); end-to-end touching is fine and not
   reported.
5. **Cover checks** -- apart from the date, nothing here rewrites the
   drawing; every other disagreement is only SUGGESTED against, in the
   report:
   - Tech Title block's Date attribute must read today, MM/DD/YYYY.
     A wrong one is **rewritten to today** in that same form, keeping
     any `Date =` label in front of it, and the report says what was
     found and what was set. `COVERSCAN` says NEEDS UPDATING and
     writes nothing.
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
     rules at 36" -- inside corners bending more than 30 degrees,
     concave radii of 4'-6" or less bending more than 10 degrees in
     total, no overlapping suggestions -- and every spot with no pad
     already nearby is circled and suggested.
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

Every value COVERCHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `covercheck.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**The cover rules: what is drawn, and where**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-pool-layer*` | `"POOL"` | The pool outline and, when one is drawn, the cover. Both are read for their ByLayer properties, so these are layer names the shop's template already uses |
| `*cchk-cover-layer*` | `"COVER"` | The pool outline and, when one is drawn, the cover. Both are read for their ByLayer properties, so these are layer names the shop's template already uses |
| `*cchk-pool-note*` | `"Pool Size Shown"` | When no cover is drawn the sheet has to say which size IS shown. Both notes together is an error -- a sheet shows one or the other |
| `*cchk-spa-note*` | `"Spa Size Shown"` | When no cover is drawn the sheet has to say which size IS shown. Both notes together is an error -- a sheet shows one or the other |
| `*cchk-details-block*` | `"Cover Details"` | The block carrying Overlap and Spacing, the block a replacement drawing has to carry, and the linetype names that read as dashed |
| `*cchk-repl-block*` | `"Replacement Disclaimer"` | The block carrying Overlap and Spacing, the block a replacement drawing has to carry, and the linetype names that read as dashed |
| `*cchk-dashed-pat*` | `"*DASH*,*HIDDEN*"` | The block carrying Overlap and Spacing, the block a replacement drawing has to carry, and the linetype names that read as dashed (wcmatch, case-blind) |

**The cover rules: overlap and spacing**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-overlap-vals*` | `'(12.0 15.0 18.0)` | The only overlaps that exist, in inches. A drawing carrying anything else is wrong, not merely unusual |
| `*cchk-area-small*` | `1200.0` | Water area decides which: under SMALL -> 12" overlap and 5x5 spacing, over LARGE -> 18" and 3x3, between the two -> 15" and 4x4. Move the breakpoints and the whole rule moves with them (square feet) |
| `*cchk-area-large*` | `2000.0` | Water area decides which: under SMALL -> 12" overlap and 5x5 spacing, over LARGE -> 18" and 3x3, between the two -> 15" and 4x4. Move the breakpoints and the whole rule moves with them (square feet) |

**The cover rules: pads**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-pad-size*` | `36.0` | Pads are suggested at this size (PADDLE's big pad), and these block names, on this layer, count as a pad that is already there (drawing units) |
| `*cchk-pad-blocks*` | `'("Pad36x36" "Pad24x24")` | Pads are suggested at this size (PADDLE's big pad), and these block names, on this layer, count as a pad that is already there |
| `*cchk-pads-layer*` | `"PADS"` | Pads are suggested at this size (PADDLE's big pad), and these block names, on this layer, count as a pad that is already there |
| `*cchk-pad-near*` | `18.0` | A pad centre within this of a spot (Chebyshev distance -- the pad is a square) already covers it, so no second pad is suggested (drawing units) |
| `*cchk-pad-maxrad*` | `54.0` | The largest concave radius that still needs pads: a gentler curve than 4'-6" does not pull the cover in hard enough to want one (drawing units) |
| `*cchk-pad-cornertol*` | `(/ (* 30.0 pi) 180.0)` | A joint bending less than CORNERTOL is semi-straight rather than an inside corner; a whole arc bending less than ARCTOL is semi-straight too. Both are PADDLE's, and tests/test_covercheck_pads.py fails if the two tools part company -- change them together (30 degrees, in radians) |
| `*cchk-pad-arctol*` | `(/ (* 10.0 pi) 180.0)` | A joint bending less than CORNERTOL is semi-straight rather than an inside corner; a whole arc bending less than ARCTOL is semi-straight too. Both are PADDLE's, and tests/test_covercheck_pads.py fails if the two tools part company -- change them together (10 degrees, in radians) |
| `*cchk-chain-fuzz*` | `0.05` | The widest gap that still chains two ends of an exploded outline into one loop. Raising it closes sloppier outlines and can chain two separate runs together (drawing units) |

**The sheet's title block**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-title-block*` | `"Tech Title"` | The title block and the attribute in it carrying the date; the date must read today, written MM/DD/YYYY. Spaces in the block name are optional when it is searched for |
| `*cchk-date-tag*` | `"Date"` | The title block and the attribute in it carrying the date; the date must read today, written MM/DD/YYYY. Spaces in the block name are optional when it is searched for |
| `*cchk-block-depth*` | `3` | How many levels of nested block to search when looking for a name or a piece of text. Raising it finds text buried deeper, at the cost of a slower sweep (levels) |
| `*cchk-tut-layer*` | `"TUTORIAL-COVERCHECK-DEMO"` | The layer TUTORIALCOVERCHECK draws its non-pool demo geometry on |

**What counts as attached, and what counts as one spot**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-tol*` | `1.0e-4` | A dimension point or an arc end within this distance of an object is ATTACHED and is not questioned. It has three more jobs: the smallest move worth asking about, the shortest overlap worth reporting, and the shortest segment admitted to overlap detection. Raising it asks fewer questions on all four counts (drawing units) |
| `*cchk-anchor-tol*` | `1.0e-4` | How close two dimension points must be to count as the same spot (drawing units) |
| `*cchk-anchor-min*` | `2` | ...and how many dimensions must meet there to make it an ANCHOR: a point left as drawn, geometry under it or not (the pair of dims pinning a hypotenuse corner is the everyday case). 1 would make every point an anchor and switch the dimension audit off (dimensions meeting at one spot) |
| `*cchk-curve-types*` | `'("LINE" "ARC" "CIRCLE" "ELLIPSE" "LWPOLYLINE" "POLYLINE" "SPLINE"` | Entity types a dimension point or an arc end may attach to. Each must be a curve AutoCAD can measure to (vlax-curve-*) |
| `*cchk-ask-all-arc-ends*` | `nil` | T = confirm EVERY arc endpoint, even ones already attached |

**Overlapping lines**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-olap-fuzz*` | `1.0e-4` | How far apart two parallel lines may sit and still be called the same line. Raising it calls more near-misses an overlap (drawing units, sideways offset) |
| `*cchk-olap-dirtol*` | `0.5` | Two segments are only tested for overlap when their directions are within this of each other. It is a bucketing shortcut, not a rule: keep it comfortably wider than the angle *cchk-olap-fuzz* implies over a segment's length, or a genuine overlap is never compared (degrees) |
| `*cchk-olap-types*` | `'("LINE" "LWPOLYLINE" "POLYLINE")` | Entity types whose straight segments take part in overlap detection. Arcs, circles and splines have no straight run to overlap, which is why this is a shorter list than *cchk-curve-types* |

**Review order**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-style-order*` | `'("STANDARD" "SIDE STANDARD" "STANDARD INCHES" "CROSS DIMENSIONS"` | Dimension styles are reviewed in this order; styles not listed come afterwards ("whatever else is left"), still left-to-right. Matching is by exact name, case-blind |
| `*cchk-dim-layer*` | `"DIMENSION"` | Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what the report tells you to run |
| `*cchk-dimfix-cmd*` | `"CDIM"` | Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what the report tells you to run |
| `*cchk-row-band*` | `0.05` | Within a style, dimensions are reviewed row by row. Two dimensions count as the same ROW when their midpoints are within this fraction of the selection's height. Raise it and a whole sheet becomes one row (pure left-to-right); lower it and near-level dims split apart (fraction of the selection's height) |
| `*cchk-row-flat*` | `1.0` | Within a style, dimensions are reviewed row by row. Two dimensions count as the same ROW when their midpoints are within this fraction of the selection's height. Raise it and a whole sheet becomes one row (pure left-to-right); lower it and near-level dims split apart (...and the band for a selection with no height) |

**Colours**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-grey-color*` | `8` | ACI: everything not under review, faded (grey) |
| `*cchk-flag-color*` | `1` | ACI: what you answered "No" to (red) |
| `*cchk-arc-color*` | `6` | ACI: arcs whose endpoints were moved (magenta) |
| `*cchk-olap-color*` | `4` | ACI: merged or flagged overlapping lines (cyan) |
| `*cchk-orig-color*` | `1` | ACI: the X marking where you drew the point (red) |
| `*cchk-sugg-color*` | `3` | ACI: the + marking where COVERCHECK would put it (green) |
| `*cchk-point-color*` | `2` | ACI: the crosses marking an overlap's two ends (yellow) |

**The two layers**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-constr-layer*` | `"COVERCHECK-CONSTRUCTION"` | The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are created on first use; the colour applies only then, so a layer already in the drawing keeps its own |
| `*cchk-constr-color*` | `2` | The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are created on first use; the colour applies only then, so a layer already in the drawing keeps its own (ACI (yellow)) |
| `*cchk-report-layer*` | `"COVERCHECK-REPORT"` | The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are created on first use; the colour applies only then, so a layer already in the drawing keeps its own |
| `*cchk-report-color*` | `3` | The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are created on first use; the colour applies only then, so a layer already in the drawing keeps its own (ACI (green)) |

**How the report is sized and placed**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-green-scale*` | `0.75` | All-clear lines are written at this fraction of the height the red attention lines get, so problems stand out. 1.0 = same size |
| `*cchk-report-chars*` | `45.0` | Report column width, in text heights |
| `*cchk-report-wide*` | `0.25` | The report is scaled to the drawing: its text height is chosen so the whole report is about as tall as the drawing. On a wide, short sheet that would give a tiny report, so the reference height is at least this fraction of the drawing's WIDTH |
| `*cchk-report-lead*` | `1.66` | MTEXT line pitch as a multiple of text height, used to turn a line count into a height. AutoCAD's default single spacing is 1.66 |
| `*cchk-report-hmax*` | `30.0` | ...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both are DIVISORS, so a smaller number is a looser bound |
| `*cchk-report-hmin*` | `200.0` | ...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both are DIVISORS, so a smaller number is a looser bound |
| `*cchk-report-hfall*` | `2.5` | The height used when the selection has no extents to scale against (DIMTXT x DIMSCALE is tried first) (drawing units) |
| `*cchk-report-gap*` | `0.05` | Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around the closing zoom |
| `*cchk-zoom-out*` | `0.05` | Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around the closing zoom |
| `*cchk-zoom-margin*` | `0.75` | Empty space around ONE item when the review zooms to it, as a fraction of its size |
| `*cchk-mark-size*` | `0.02` | Half-size of the X and + markers drawn while you answer, as a fraction of the current view height -- so they stay the same size on screen however far you are zoomed in (fraction of VIEWSIZE) |
| `*cchk-attn-words*` | `"*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*NOT ATTACHED*,*OVERLAP*,*ASSOCIATIVE*,*DISAGREE*,*SUGGEST*,*BLANK*,*UNREADABLE*,*NOT A POLYLINE*,*LOOK AT*,*NO DASHED*,*AMBIGUOUS*,*ONLY ONE SIZE*,*NO INCHES*,*NOT TODAY*,*EXPECTED MM/DD/YYYY*,*NEEDS UPDATING*,*UPDATED TO*"` | A report line is rendered red and full-size when it matches this pattern (wcmatch, case-blind; comma separates alternatives). These are the words the report's own notes use for something that needs looking at -- reword a note and its word belongs here too, or the line quietly stops being red |
| `*cchk-dist-mode*` | `2` | Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engineering, 4 architectural (feet-inches); prec is decimal places (for mode 4: the inch is split 2^prec ways). The dimension's own MEASUREMENT is not formatted here -- it follows the drawing's LUNITS/LUPREC, which is what the drafter reads on the sheet (rtos mode) |
| `*cchk-dist-prec*` | `4` | Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engineering, 4 architectural (feet-inches); prec is decimal places (for mode 4: the inch is split 2^prec ways). The dimension's own MEASUREMENT is not formatted here -- it follows the drawing's LUNITS/LUPREC, which is what the drafter reads on the sheet (decimal places) |

**Numerical guards (rarely changed)**

| Global | Default | Meaning |
| --- | --- | --- |
| `*cchk-same-pt*` | `1e-8` | Two points closer than this are the SAME point: no construction line is drawn through them, no joining line between an X and a +, and an arc is never re-fitted onto its own other end (drawing units) |
| `*cchk-planar-eps*` | `1e-9` | How far an arc's extrusion normal (DXF 210) may lean from world +Z and still be audited; beyond it the arc is skipped rather than re-fitted in the wrong plane (dimensionless (normal components)) |
| `*cchk-flat-eps*` | `1e-12` | Below this a polyline bulge is treated as straight, so the edge joins overlap detection, and three points are too collinear to fit an arc through |
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
