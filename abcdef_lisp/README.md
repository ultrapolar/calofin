# ABCDEF.lsp — plot tape-measured points inside a rectangle

`ABCDEF` is an AutoCAD command that reads a spreadsheet of points, each
located by its taped distance from the four corners of a rectangle, and
plots them. Load `abcdef.lsp` (APPLOAD), type `ABCDEF`, pick the sheet,
enter the two rectangle dimensions, and pick where corner A goes.

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

If a sheet labels the bottom corners the other way round (clockwise, with
C bottom-right), the import notices — the distances only fit the rectangle
under the labelling they were measured with — swaps C and D to match, and
prints a note saying it did so.

## Spreadsheet format

CSV is read natively; `.xlsx/.xls/.xlsm` go through Excel COM automation.
Columns are found by header text, in any order:

```
POINT NAME | DIST FROM A | DIST FROM B | DIST FROM C | DIST FROM D
```

Values are architectural feet-inches (`12'-3 1/2"`, `9'`, `3 1/2"`).
Blank cells mean "not measured"; a point needs at least 2 distances
(3–4 give a unique, error-averaged fix). Because taped values are rounded
to the nearest 1/4", each point is solved by least squares so the rounding
error is spread across all its distances; the leftover RMS error is
reported per point, and anything worse than 0.25" is flagged `**CHECK`.

The parser also repairs common scan/transcription noise (and logs every
repair so it can be verified): `O`/`I` for `0`/`1`, smart quotes,
`28-7"` (missing foot mark), `101-10"` (foot mark scanned as a `1`),
`20'-7 114"` (`/` scanned as `1`), and `34'-4 1 /4` (fraction split by a
stray space).

## Bugs fixed in this revision

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

## Verification

AutoLISP only runs inside AutoCAD, so `verify_abcdef.py` mirrors the
parser and solver logic line-for-line and checks it against
`template.csv` (the real sheet from the failing run):

```
python3 verify_abcdef.py
```

It asserts the parser unit cases above, that all 9 sample points fit the
36'-5 1/4" × 22'-0 1/4" rectangle with RMS < 0.15", the T/U symmetry, and
that the C/D swap detector fires only for a clockwise-labelled sheet.
