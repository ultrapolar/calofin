# abcdef.lsp — locate tape-measured points inside a rectangle

`ABCDEF` reads a spreadsheet of points, each located by its taped distance
from the four corners of a rectangle, works out where each point has to be,
and plots it as a survey point the rest of the toolkit can use. Load
`abcdef.lsp` (APPLOAD), type `ABCDEF`, pick the sheet, enter the two
rectangle dimensions, choose a placement method, and pick where corner A
goes.

`ABCDEFVER` prints the loaded version.

## Corner layout

```
      A --------- B          A = top-left      B = top-right
      |           |          C = bottom-left   D = bottom-right
      |           |
      C --------- D
```

**C sits directly below A, and D directly below B** — the same "Z" reading
order as the field sheet. The two dimensions the command asks for are
**A–B** (width across the top) and **A–C** (height down the side). All
geometry is drawn in inches (1 drawing unit = 1 inch).

The four corners are built square to the world axes, and all four angles
are **measured back off the drawn coordinates** before anything is plotted:
a frame that is not a true 90° rectangle stops the run instead of quietly
poisoning every point solved against it.

If a sheet labels the bottom corners the other way round (clockwise, with
C bottom-right), the import notices — the distances only fit the rectangle
under the labelling they were measured with — swaps C and D to match, and
prints a note saying it did so. A sheet written clockwise throughout is
`ALTABCDEF`'s job, not this one's.

## Spreadsheet format

CSV is read natively; `.xlsx/.xls/.xlsm` go through Excel COM automation.
Columns are found by header text, in any order:

```
POINT NAME | DIST FROM A | DIST FROM B | DIST FROM C | DIST FROM D
```

Values are architectural feet-inches (`12'-3 1/2"`, `9'`, `3 1/2"`).
Blank cells mean "not measured".

The parser repairs common scan/transcription noise (and logs every repair
so it can be verified): `O`/`I` for `0`/`1`, smart quotes, `28-7"` (missing
foot mark), `101-10"` (foot mark scanned as a `1`), `20'-7 114"` (`/`
scanned as a `1`), and `34'-4 1 /4` (fraction split by a stray space).

## How many tapes it takes

Two distances fix a point up to a mirror, three fix it outright, and the
fourth is the cross-check. Sheets rarely give four clean ones, so the
leniency is built in:

| Tapes given | What happens |
| --- | --- |
| 4 | fitted on all four; if that fit is poor and leaving **one** out settles the other three, that tape is dropped and the report names it |
| 3 | least-squares fitted, sharing the leftover error across all three |
| 2 | the two circles are crossed exactly and the root **inside** the rectangle is taken (the mirror root sits beyond a rectangle side) |
| 0–1 | skipped, and named on the command line |

What it will **not** do is drop a tape it cannot prove is the bad one.
Three tapes that disagree give no evidence about which of them is wrong —
every pair of three fits perfectly — so a poor 3-tape row keeps all three
and is graded down instead of being made to look exact.

The same caution applies with four. A point sitting near a diagonal of the
rectangle is barely constrained along that diagonal, so a wrong third tape
can drag the answer six inches and still leave a fit of a few hundredths;
dropping the lowest-error tape there would throw out a *good* one. The
giveaway is that the best and second-best triples fit equally well, so a
drop also requires the runner-up to be clearly worse. When it isn't, every
tape is kept and the point is flagged `(tapes disagree, none provably
wrong)`.

## Placement methods

Asked once per run, after the rectangle dimensions:

| Method | What it does |
| --- | --- |
| `Auto` | the rules above — all tapes, minus one that can be proven wrong. The default. |
| `Furthest` | only the two supplied corners furthest apart (the widest base the sheet offers) |
| `Mean` | every 2- and 3-tape subset solved on its own, and the answers averaged |
| `Least` | least-squares over every supplied tape, nothing dropped — what earlier revisions did |

## The report

Printed to the command line **and** written to `<sheet>_ABCDEF_report.txt`
beside the spreadsheet. One line per point:

```
POINT      X         Y      TAPES  USED  FIT     SPREAD  CUT   CONF     err vs A  B  C  D
```

| Column | Meaning |
| --- | --- |
| `TAPES` | how many of the four distances the sheet gave |
| `USED` | which corners actually placed the point (`ABD`, `AD`, …) |
| `FIT` | RMS leftover error against **every** tape the sheet gave |
| `SPREAD` | how far the point moves if any one used tape is dropped |
| `CUT` | the angle the best pair of tapes crosses at, at the point |
| `CONF` | all four of those together, 1–99%, plus a word (HIGH/GOOD/FAIR/WEAK/POOR) |
| `err vs` | signed leftover error against each corner in sheet order |

`FIT` and `CONF` are deliberately different numbers. `FIT` is scored
against every tape, so a dropped bad reading still shows its objection;
`CONF` is scored against the tapes that actually placed the point, so a row
whose bad tape was **found and dropped** reads as what it is — a
well-located point from a sheet with one bad reading in it — instead of
being punished exactly as hard as a row nobody could repair.

Two tapes cross-check nothing, so a 2-tape point is capped well short of
certainty however neatly the circles crossed. A shallow `CUT` costs more
than a large `FIT` does, because it should: near a diagonal, a quarter inch
of tape error walks the answer several inches along the crossing.

A summary follows the table: how many points were placed by 4, 3 and 2
tapes, how many needed a tape dropped, and how many want checking.

## Inside the frame

A point measured from four corners of a rectangle belongs inside it. A
solution that lands outside is pulled back onto the frame and the distance
it had to be pulled is reported — a small snap is rounding, a large one
(over 1") means a tape or a dimension is wrong, and the point is flagged.

## What it draws, and what happens next

Each point is an **`ab_pt` block on layer `POINTS`**, carrying its sheet
label in the `number` attribute — the same survey point a Leica import
(`XFTCONV`) produces. That is what `ABHD`, `CABHD`, `ADAB`, `ABFIND`,
`BPCALLOUT` and `LHD` already read, so this import needs no conversion
step.

The run therefore ends by offering to fit the pool perimeter straight
away: answer `Yes` and the points just plotted are pre-selected and `ABHD`
starts on them. (Loaded on its own rather than as part of the calofin
build, `abcdef.lsp` says so and leaves the points ready instead.)

Nothing else goes on the `POINTS` layer: the rectangle and its corner tags
are on `ABCDEF-FRAME`, and notes on doubtful points on `ABCDEF-WARN`.

## If the points land in the wrong place

**First check the version banner.** The file prints `ABCDEF.lsp vN.N
loaded` when loaded and `ABCDEF vN.N` when the command runs; the current
version is declared at the top of `abcdef.lsp` (`*abcdef-version*`). If the
banner is missing or shows an older number, AutoCAD is running a stale or
edited copy — re-download `abcdef.lsp` and `APPLOAD` it again.

Both field failures so far were exactly this: a copy whose corner block no
longer matched the repo file. The command therefore verifies itself on
every run — it re-measures the A/B/C/D corner variables (four sides and
both diagonals) before drawing and refuses to plot if they don't form the
entered W × H rectangle — and pops an alert when the sheet's distances fit
the rectangle poorly overall.

## Bugs fixed

The failing drawing (`ABCDEFAILSAD.dxf`) plotted A-B-C-D as a
parallelogram with 31°/149° corners. Analysis of that DXF against the
sample sheet (`template.csv`) found three separate problems:

1. **Frame corners were computed wrong** — the drawn frame had
   C = A + (2W, −H) and D = A + (W, −H); the plotted points matched a
   solve against those bogus corners to 0.0001". Corners are now derived
   as `A=(x,y) B=(x+W,y) C=(x,y−H) D=(x+W,y−H)`, the frame polyline is
   drawn in perimeter order by position, and the command **measures** the
   drawn corner angles and prints them instead of asserting 90°.

2. **Corner naming didn't match the field sheet.** The old code assumed
   clockwise A-B-C-D (C bottom-right). Under that layout the sample
   sheet's distances fit with 30–160 **inches** of residual error; with C
   below A and D below B they fit to ≤ 0.08" — pure quarter-inch rounding
   (the mirror pair T/U lands exactly symmetric on the side edges). The
   documented layout is now the "Z" order, and a cross-check solves every
   3+-distance row under both layouts and auto-swaps C/D (with a printed
   note) when a sheet is labelled the other way.

3. **Split fractions parsed wrong.** `34'-4 1 /4` (space inside the
   fraction — 10 cells in the sample sheet) lost the fraction: the `/4`
   token contributed 0, reading 4 1/4" as 5". Broken fraction tokens are
   now re-joined (`1 /4`, `1/ 4`, `1 / 4` → `1/4`) and logged.

4. **`vl-catch-all-apply` was called with one argument** (it takes the
   function *and* its argument list). The view reset at the very end of
   every run therefore raised "too few arguments" and took the end of the
   run down with it — the one thing the catch was there to prevent. Fixed
   in `abcdef.lsp` and in `ALTABCDEF.lsp`, which had inherited it.

## Verification

AutoLISP only runs inside AutoCAD, so two scripts stand in for it.

`verify_abcdef.py` mirrors the parser and solver logic and checks it
against `template.csv` (the real sheet from the failing run):

```
python3 lisp/abcdef/verify_abcdef.py
```

It asserts the parser unit cases above, that all 9 sample points fit the
36'-5 1/4" × 22'-0 1/4" rectangle with RMS < 0.15", the T/U symmetry, and
that the C/D swap detector fires only for a clockwise-labelled sheet.

`tests/test_abcdef.py` runs the **actual LISP** in the repo's AutoLISP VM
(`tests/lispvm.py`) — the whole command, prompts to report — against a
synthetic survey whose true coordinates are known, and checks the tape
arithmetic, the outlier rules, the inside-the-frame guarantee, the ab_pt
output and the ABHD handoff:

```
python3 tests/test_abcdef.py
CALOFIN_LISP_ROOT=shared python3 tests/test_abcdef.py   # the grouped build
```
