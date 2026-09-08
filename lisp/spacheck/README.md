# SPACHECK — audit a finished spa drawing (AutoLISP / AutoCAD 2018+)

Holds a spa sheet against the rules `SPA.LSP` builds to. Every audit is
derived from what SPA actually draws, so **a drawing SPA produced passes
and a hand-edited one shows exactly where it drifted** — which also makes
it a check on drawings that never came from SPA at all.

Highlight the spa drawing **together with its `Spa Cover Details`
block**: the block supplies the grade and taper, and without them the
hinge section has nothing to measure against.

Built from the same bones as `covercheck`, `linfincheck` and `dimcheck` —
the Move/Keep/Pick style review, the stashed-colour markers, the
on-drawing MTEXT report — with the spa rules in place of the liner ones.

## What it checks

1. **The Spa Cover Details block.** One must be in the selection, with a
   readable `TAPER` tag. `GRADE` may be absent — Standard is assumed,
   exactly as SPA assumes it. A Thermo-Light block claiming any taper
   but `1-3/8` is called out.
2. **The cover outline.** Exactly one, on `COVER`, and a single **closed
   bounded entity** — one LWPOLYLINE, or a CIRCLE/ELLIPSE for a round
   spa. Loose lines and arcs are the old pre-bounded output and are
   reported as such.
3. **The water's edge outline.** Optional; a sheet may show one outline
   only. When present it must also be one closed entity, on `POOL`, and
   it must lie **inside** the cover — the cover is always the larger.
4. **The dimension layer.** Every dimension must sit on `DIMENSION`.
   Any that do not are counted, the layers they landed on are named,
   and the report tells you to run **`CDIM`** to move them. This is
   the one dimension check `LITESPACHECKSCAN` keeps.
5. **The dimensions.** Each one for its layer (`DIMENSION`), its style
   (`STANDARD INCHES` for the cover's, `STANDARD INCHES 0.5` for the
   water's edge's) and agreement with its own definition points. Then
   the roster: both overalls present, carrying their `Cover Size` /
   `Water's Edge` note, and **reading the outline's true size**; an
   `Overlap` dimension whenever both outlines are drawn, reading the
   true lap; and the overall standoffs at SPA's 2 ft above / 3 ft left.
6. **The hinges** — the LINEs on `COVER` (the outline is a polyline, so
   the two never confuse) — against the block's grade and taper: a piece
   count the taper allows, no piece wider than the foam sheet, no hinge
   longer than it, the fold/velcro arrangement matching the **Hinge
   Arrangement Chart** for that piece count, and a label on `TEXT`
   against every hinge. Hardware called for by the longest hinge —
   velcro hinges, double C channel, hold down kit — comes out as advice.
7. **Feet and inches.** Every text box — TEXT, MTEXT and the `ATTRIB`
   values on blocks — must state its inches wherever it states feet.
   `5'` is flagged; `5'-0"`, `3'-2"` and a plain `40"` are fine. A feet
   mark is an apostrophe **straight after a digit**, so `Water's Edge`
   is prose and never flagged. `LITESPACHECKSCAN` keeps this one.
8. **The Tech Title date.** The `Date` attribute of the `Tech Title`
   block must read **today**, written `MM/DD/YYYY` — a sheet going out
   under an old date is the mistake this catches. Wrong format, an
   impossible day (`02/30`), a blank, and a stale-but-valid date are
   all reported. The block is looked for in the selection and then
   across the drawing; with none in reach the report says the date was
   not checked rather than flagging it. `LITESPACHECKSCAN` keeps this.
9. **The title block.** Everything on the `border` layer is measured
   together, so a frame drawn as one polyline and one drawn as four
   lines both measure the same. **A spa title block is exactly 0.6× the
   liner block**: the liner nominal is 704 × 543.625, so the spa nominal
   is **422.4 × 326.175**. Anything else is reported with the factor it
   actually came out at, and a border out of proportion is reported
   separately as `STRETCHED`.

The report is an MTEXT placed to the right of the drawing and sized to
scale with it: problems in **red** at full size, advice in **cyan**,
all-clear in green at 75%.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `SPACHECK.lsp`, and load it (add
   it to the *Startup Suite* to have it every session).
2. Highlight the drawing and its details block, then run one of:

| Command | What it does |
| --- | --- |
| `SPACHECK` | The audits, then a walk of everything they flagged — one item at a time, zoomed to each, colouring the ones you confirm are wrong. |
| `SPACHECKSCAN` | The identical audits, **read-only** — writes the report and nothing else. Good as a pre-flight. |
| `LITESPACHECKSCAN` | The scan minus the per-dimension audit (layer, style, span agreement) — for a drawing `DIMCHECK` already went over, when only the spa rules are wanted. It keeps the dimension-layer verdict (which tells you to run `CDIM`) and the feet-and-inches check. |
| `SPACHECKRESCUE` | Puts back every colour SPACHECK stashed and removes the report — the way out after a crash, or once you're done with the marks. |
| `SPACHECKVER` | Prints the loaded version and the title-block size it is checking for. |
| `TUTORIALSPACHECK` | Teaches the tool — see below. |

Pressing Enter at the selection prompt takes the whole drawing. A single
`U` undoes an entire `SPACHECK` run, including the report.

## TUTORIALSPACHECK

Asks up front — **Checks**, **Demo**, or **Both**:

* **Checks** — every audit spelled out at the command line, generated
  live from the tunables below, so the list cannot drift from what the
  code does.
* **Demo** — draws a small practice spa in an empty spot you pick, with
  **three faults planted in it**, and walks you through each one, zoomed
  in and explained:
  1. an overall dimension reading 80 across a cover that is really 84,
  2. a hinge with no label,
  3. a title block left at the liner size instead of 0.6× it.

  It then offers to run `SPACHECKSCAN` for a real report — which names
  those three and nothing else — and to erase the practice drawing
  afterwards.
* **Both** — the checklist, then the demo.

The demo runs inside one UNDO group and never touches existing geometry.

## Tunables

Every value SPACHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `SPACHECK.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**Layers**

| Global | Default | Meaning |
| --- | --- | --- |
| `spachk:*lay-cover*` | `"COVER"` | Layers SPA draws on -- the audit is only as right as these are (the cover outline and the hinges) |
| `spachk:*lay-water*` | `"POOL"` | Layers SPA draws on -- the audit is only as right as these are (the water's edge outline) |
| `spachk:*lay-dim*` | `"DIMENSION"` | Layers SPA draws on -- the audit is only as right as these are (every dimension) |
| `spachk:*lay-text*` | `"TEXT"` | Layers SPA draws on -- the audit is only as right as these are (the hinge labels) |
| `spachk:*lay-notes*` | `"SPA-NOTES"` | Layers SPA draws on -- the audit is only as right as these are (corner letters, mode note, report) |
| `spachk:*dimfix-cmd*` | `"CDIM"` | CDIM is the command that moves stray dimensions onto *lay-dim*, and is what the report tells you to run when it finds any |
| `spachk:*techtitle-block*` | `"Tech Title"` | The sheet's title block, and the attribute in it carrying the date. This is the Tech Title BLOCK, not the drawn border section 7 checks (spaces optional in the name) |
| `spachk:*date-tag*` | `"Date"` | The sheet's title block, and the attribute in it carrying the date. This is the Tech Title BLOCK, not the drawn border section 7 checks |
| `spachk:*ds-cover*` | `"STANDARD INCHES"` | Dimension styles, one per outline (SPA's spa:*ds-cover* / *ds-water*) |
| `spachk:*ds-water*` | `"STANDARD INCHES 0.5"` | Dimension styles, one per outline (SPA's spa:*ds-cover* / *ds-water*) |
| `spachk:*sfx-cover*` | `"Cover Size"` | The notes SPA stacks under an overall's measurement |
| `spachk:*sfx-water*` | `"Water's Edge"` | The notes SPA stacks under an overall's measurement |
| `spachk:*sfx-lap*` | `"Overlap"` | The notes SPA stacks under an overall's measurement |
| `spachk:*topoff*` | `24.0` | SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a dimension line may sit from them before it is worth reporting (2 ft: cover -> the TOP overall dim) |
| `spachk:*dimoff*` | `36.0` | SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a dimension line may sit from them before it is worth reporting (3 ft: cover -> the LEFT overall dim) |
| `spachk:*off-tol*` | `2.0` | SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a dimension line may sit from them before it is worth reporting (inches of slack on either standoff) |
| `spachk:*details-block*` | `"Spa Cover Details"` | The block SPA reads the grade and taper out of |
| `spachk:*liner-w*` | `704.0` | TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc-border-h*); a spa sheet's title block is exactly this fraction of it (58'-8"     in drawing units) |
| `spachk:*liner-h*` | `543.625` | TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc-border-h*); a spa sheet's title block is exactly this fraction of it (45'-3 5/8" in drawing units) |
| `spachk:*title-frac*` | `0.6` | TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc-border-h*); a spa sheet's title block is exactly this fraction of it (spa title block = 0.6 x the liner) |
| `spachk:*border-layer*` | `"border"` | TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc-border-h*); a spa sheet's title block is exactly this fraction of it |
| `spachk:*border-tol*` | `0.005` | TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc-border-h*); a spa sheet's title block is exactly this fraction of it (0.5% slack on the factor and the aspect) |
| `spachk:*meas-tol*` | `0.0625` | How close a dimension's measurement must be to the geometry it spans, and how close a definition point must sit to the outline (1/16" -- a fractional dim rounds) |
| `spachk:*pt-tol*` | `1.0e-4` | How close a dimension's measurement must be to the geometry it spans, and how close a definition point must sit to the outline |

**Marking and report colours**

| Global | Default | Meaning |
| --- | --- | --- |
| `spachk:*grey-color*` | `8` | ACI: reserved for fading, unused today |
| `spachk:*flag-color*` | `1` | ACI: what you confirmed is wrong (red) |
| `spachk:*advice-color*` | `4` | ACI: advice, not a failure (cyan) |
| `spachk:*green-scale*` | `0.75` | all-clear text height vs the red |
| `spachk:*report-layer*` | `"SPACHECK-REPORT"` | The layer the report MTEXT goes on, created on first use; the colour applies only then, so a layer already in the drawing keeps its own |
| `spachk:*report-color*` | `3` | The layer the report MTEXT goes on, created on first use; the colour applies only then, so a layer already in the drawing keeps its own (ACI (green)) |
| `spachk:*report-chars*` | `48.0` | The layer the report MTEXT goes on, created on first use; the colour applies only then, so a layer already in the drawing keeps its own (report column width, in text heights) |
| `spachk:*zoom-margin*` | `0.75` | The layer the report MTEXT goes on, created on first use; the colour applies only then, so a layer already in the drawing keeps its own (empty space around a zoomed item) |
| `spachk:*hallow-max*` | `5` | A piece count this high or higher is the table's top row ("5 = 5+") (pieces) |

**Reading the drawing**

| Global | Default | Meaning |
| --- | --- | --- |
| `spachk:*grade-tag*` | `"GRADE"` | The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as SUBSTRINGS of the upper-cased value, first match winning, so "Ultra FRP" reads as ULTRA; a value matching nothing takes the default grade. Every canonical name here must appear in *foamtab* and *hardtab* above, or the audit has a grade it can recognise but not measure against |
| `spachk:*taper-tag*` | `"TAPER"` | The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as SUBSTRINGS of the upper-cased value, first match winning, so "Ultra FRP" reads as ULTRA; a value matching nothing takes the default grade. Every canonical name here must appear in *foamtab* and *hardtab* above, or the audit has a grade it can recognise but not measure against |
| `spachk:*grade-words*` | `'(("ECON"   . "ECONOMY"` | The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as SUBSTRINGS of the upper-cased value, first match winning, so "Ultra FRP" reads as ULTRA; a value matching nothing takes the default grade. Every canonical name here must appear in *foamtab* and *hardtab* above, or the audit has a grade it can recognise but not measure against |
| `spachk:*grade-default*` | `"STANDARD"` | The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as SUBSTRINGS of the upper-cased value, first match winning, so "Ultra FRP" reads as ULTRA; a value matching nothing takes the default grade. Every canonical name here must appear in *foamtab* and *hardtab* above, or the audit has a grade it can recognise but not measure against (the grade a value matching nothing takes) |
| `spachk:*taper-words*` | `'(("3-2" . "3-2") ("4-2" . "4-2") ("4-3" . "4-3"` | ...and the taper vocabulary, matched the same way; an unrecognised taper measures against no foam row at all rather than the wrong one |
| `spachk:*grade-short*` | `'(("ECONOMY" . "ECO") ("STANDARD" . "STD"` | The short grade names the report prints, keyed by the canonical name |
| `spachk:*outline-types*` | `'("LWPOLYLINE" "POLYLINE" "CIRCLE" "ELLIPSE")` | Entity types, by the job each does in the audit: what may be an outline at all, which of those are closed by their nature rather than by a flag, and what counts as loose (unbounded) output -- which on the cover layer is also what a hinge is drawn as |
| `spachk:*closed-types*` | `'("CIRCLE" "ELLIPSE")` | Entity types, by the job each does in the audit: what may be an outline at all, which of those are closed by their nature rather than by a flag, and what counts as loose (unbounded) output -- which on the cover layer is also what a hinge is drawn as |
| `spachk:*loose-types*` | `'("LINE" "ARC")` | Entity types, by the job each does in the audit: what may be an outline at all, which of those are closed by their nature rather than by a flag, and what counts as loose (unbounded) output -- which on the cover layer is also what a hinge is drawn as |
| `spachk:*linear-types*` | `'(0 1)` | Dimension subtypes whose span can be measured, by the low three bits of DXF group 70: 0 = rotated, 1 = aligned |
| `spachk:*velcro-word*` | `"Velcro"` | The word SPA labels a Velcro hinge with. The arrangement audit finds those labels by it, so it has to be the word SPA writes |

**How the report is sized and placed**

| Global | Default | Meaning |
| --- | --- | --- |
| `spachk:*report-wide*` | `0.25` | The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width |
| `spachk:*report-lead*` | `1.66` | The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width |
| `spachk:*report-hmax*` | `30.0` | The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width |
| `spachk:*report-hmin*` | `200.0` | The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width |
| `spachk:*report-hfall*` | `2.5` | The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width (drawing units) |
| `spachk:*report-gap*` | `0.05` | The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short sheet the reference height is at least this fraction of the width. LEAD: MTEXT line pitch as a multiple of text height. HMAX/HMIN: divisors clamping the height -- never taller than reference/HMAX, never shorter than reference/HMIN, so a smaller number is a looser bound. HFALL: the height used when there is nothing to scale against. GAP: space between drawing and report, as a fraction of the drawing's width |
| `spachk:*col-gap*` | `2.0` | Gap between the main sheet and the DIMENSION AUDIT column beside it, in text heights |
| `spachk:*title-scale*` | `1.5` | The title is written this many times the base height, and a section heading gets this much blank line above it. Both are used twice: once to draw, once to guess how many lines the sheet will run to -- HEAD is the allowance for the title, date, verdict and legend, and HDG-LINES for a heading plus its gap |
| `spachk:*hdg-gap*` | `0.4` | The title is written this many times the base height, and a section heading gets this much blank line above it. Both are used twice: once to draw, once to guess how many lines the sheet will run to -- HEAD is the allowance for the title, date, verdict and legend, and HDG-LINES for a heading plus its gap |
| `spachk:*head-lines*` | `4.5` | The title is written this many times the base height, and a section heading gets this much blank line above it. Both are used twice: once to draw, once to guess how many lines the sheet will run to -- HEAD is the allowance for the title, date, verdict and legend, and HDG-LINES for a heading plus its gap |
| `spachk:*hdg-lines*` | `1.4` | The title is written this many times the base height, and a section heading gets this much blank line above it. Both are used twice: once to draw, once to guess how many lines the sheet will run to -- HEAD is the allowance for the title, date, verdict and legend, and HDG-LINES for a heading plus its gap |
| `spachk:*dim-head*` | `2.5` | The title is written this many times the base height, and a section heading gets this much blank line above it. Both are used twice: once to draw, once to guess how many lines the sheet will run to -- HEAD is the allowance for the title, date, verdict and legend, and HDG-LINES for a heading plus its gap (the same allowance for the audit column) |
| `spachk:*row-indent*` | `"  "` | Findings are indented under their heading by this string |

**The date the sheet must carry**

| Global | Default | Meaning |
| --- | --- | --- |
| `spachk:*date-sep*` | `"/"` | The sheet's date is written and read in this order, with this separator: change both together, and remember the audit rewrites a wrong date into this form |
| `spachk:*date-order*` | `'(month day year)` | The sheet's date is written and read in this order, with this separator: change both together, and remember the audit rewrites a wrong date into this form |

**Numerical guards (rarely changed)**

| Global | Default | Meaning |
| --- | --- | --- |
| `spachk:*tiny*` | `1.0e-6` | A border edge shorter than this has no measurable size, and a bounding box smaller than this has nothing to scale a report to (drawing units) |
| `spachk:*foam-slack*` | `0.01` | How close a foam sheet's dimension must come to the table's before it counts as that sheet -- foam is cut to the inch, so this is slack for a drawing's rounding, not a tolerance on the foam (drawing units) |

These carry a table or a list rather than a single value, so they are named here rather than tabled with a default:

- `spachk:*foamtab*` -- Foam sheets, copied from SPA (spa:*foamtab*) so the audit measures against the same rules the drawing was built to: (grade taper ((foamWidth . foamLength) ...) (piece counts, 5 = 5+))
- `spachk:*hardtab*` -- Hardware called for by the LONGEST hinge, per grade: (grade velcro doubleC holddown), each (OVER n) | (ALWAYS) | (NEVER) | (REQUEST)
## Assumptions

* The drawing is in **inches**, as SPA draws it.
* Hinges are LINEs on `COVER`; the outline is a closed polyline. A
  drawing that puts hinges on another layer will report none.
* "Exactly 0.6×" means within `*border-tol*` — 0.5% either way — so a
  border drawn to 422.4 × 326.175 passes and one at the liner size does
  not. Tighten it to 0.0 to demand the number to the last decimal.
* The roster is the set of dimensions **SPA emits**. A sheet that
  legitimately carries more is not penalised for them; one that carries
  fewer is.

## Notes & limitations

* Requires the Visual LISP engine (bounding boxes), which ships with
  full AutoCAD. **AutoCAD LT has no LISP engine and cannot run this.**
* Loading `SPACHECK.lsp` beside `covercheck.lsp`, `dimcheck.lsp` or
  `linfincheck.lsp` is safe: distinct `spachk:` prefix, `SPACHECK-REPORT`
  layer and `SPACHECK` xdata tag, so no rescue command touches another's
  markers.
* It reports; apart from the colours you confirm in the walk, it does
  **not** repair. Fixing a wrong overall is a job for the person who
  knows which number is right.
* The grouped twin is generated — run `python3 tools/mirror_shared.py
  SPACHECK` after changing this file, never hand-edit
  `shared/parts/SPACHECK.lsp`.

## Tests

```
python3 tests/test_spacheck.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_spacheck.py # grouped tier
```

The tests run the **real** `SPA.LSP` in `tests/lispvm.py` to build a
drawing, then run the **real** `SPACHECK` over that same drawing and
read its report — so a drawing SPA produced must come back clean, and a
drawing damaged in a specific way must come back naming that damage.
Both tools reading one `Spa Cover Details` block is what keeps their two
copies of the foam and hinge charts honest.
