# ALTABCDEF — plot measured points into AutoCAD from a spreadsheet

`ALTABCDEF.lsp` is an AutoLISP command for AutoCAD (full AutoCAD — it uses
Excel COM automation, so it does **not** run in LT). It reads a
spreadsheet of points that were each measured off the four corners of a
rectangle and drops them into the drawing at their correct location.

## The setup

The four reference points **A B C D** sit on the corners of a rectangle.
`A` is the **top-left** corner and the rest run **clockwise**:

```
      A --------- B      A = top-left
      |           |      B = top-right
      |           |      C = bottom-right
      D --------- C      D = bottom-left
```

Every point in your sheet is located by how far it is from each corner.
You only need to know two things about the rectangle itself: the width
`A-B` and the height `A-D`. The command asks for both.

## The spreadsheet

One row per point, with a header row containing these columns (order
doesn't matter — the columns are found by their headers):

| POINT NAME | DIST FROM A | DIST FROM B | DIST FROM C | DIST FROM D |
| --- | --- | --- | --- | --- |
| P1 | 4'-2 1/2" | 18'-0" | 20'-7 1/4" | 9'-11" |
| P2 | 12'-3" | 9'-6 3/4" | … | … |

* Distances are architectural **feet-inches**: `12'-3 1/2"`, `0'-6"`,
  `3 1/2"`, `5'-0 3/4"`. The foot/inch marks are optional and the whole
  inches and fraction may be separated by a space or a dash.
* A blank distance cell just means "not measured from that corner" — the
  point is still plotted as long as **at least two** distances are given
  (three or four give a stronger, unambiguous fix — see *Two distances*
  below for what "unambiguous" is doing there).
* `.csv` is read **natively** (no Excel needed, and it avoids Excel silently
  turning entries like `28-11` or `7-0` into dates). `.xlsx`, `.xls` and
  `.xlsm` are read through Excel COM automation. A ready-to-fill
  `template.csv` sits next to this file — **CSV is the recommended format.**

## Cleaning up dirty / OCR'd data

Field numbers that were scanned or re-typed come back badly garbled. Before
anything is parsed, each distance cell is scrubbed deterministically:

| Comes in as | Read as | What happened |
| --- | --- | --- |
| `28-7"` | `28'-7"` | missing foot mark — the dash still separates feet from inches |
| `101-10"` | `10'-10"` | the foot mark `'` was scanned as a `1` |
| `20'-7 114"` | `20'-7 1/4"` | `114` is `1/4` with the `/` scanned as a `1` |
| `1 1'-IO 1/2"` | `11'-10 1/2"` | stray space split the feet; `IO` is `10` (`I`→`1`, `O`→`0`) |
| `201—4` | `20'-4"` | em-dash for the separator **and** foot mark as `1` |
| `34'-4 1 /4"` | `34'-4 1/4"` | the fraction split by a stray space |

The fixes applied:

* **Look-alike characters** — `O`/`o`→`0`, `I`/`l`/`|`→`1`, `_`→`-`, en/em
  dashes and the curly "smart quotes" Word/Excel insert (`’ ′`→`'`, `” ″`→`"`).
* **Missing foot mark** — a bare `28-7` is read as `28'-7"` (the dash marks the
  feet/inch split). A trailing `'` used where a `"` belongs is handled too.
* **Stray spaces in the feet** — `1 1'` or `21 1-` collapse to `11'` / `21'`.
* **A fraction split across a space** — `1 /4`, `1/ 4` and `1 / 4` all
  rejoin to `1/4`. Without this the broken `/4` piece contributes nothing
  and the fraction is silently lost, so `4 1/4"` reads as `5"`. (This was
  `ABCDEF`'s repair and not this file's until now: the same field sheets
  go through both commands, and `20'-7 1 / 4"` used to read here as
  `20'-8"` — four and three-quarter inches long, with nothing to show for
  it.)
* **A `/` scanned as `1` inside a fraction** — a slash-less run of digits like
  `114`, `314` or `1116` is rebuilt into the one valid inch fraction it could
  be (`1/4`, `3/4`, `1/16`). This is unambiguous because the misread keeps the
  same length, so `1116`→`1/16` while `11116`→`11/16`.
* **A foot mark `'` scanned as a `1`** — `101-10` could be `10'-10"` or `101'`;
  the tool uses the rectangle you entered to decide. Any reading longer than
  the rectangle's diagonal is impossible, so when the feet end in a `1` and the
  value blows past the diagonal, that `1` was the apostrophe and is dropped
  (`101-10`→`10'-10"`). Values that are still impossible after that are marked
  unreadable rather than guessed at.

Every cell that had to be cleaned (or that couldn't be read at all) is listed
on the command line **before** the points are plotted, showing the raw text
and how it was interpreted (e.g. `* P11 / FROM A: "101-10"" -> 10'-10"`), so
you can eyeball the repairs. Obvious fixes (a stray letter, a missing foot
mark) are applied quietly; only the judgement calls are reported.

> This cleanup was tuned against a real 23-point field sheet: 21 of 23 points
> reconstructed to within the ¼" rounding limit, and the 2 that didn't were
> genuinely broken in the source (a distance typed as just `3/4"`, and an
> ambiguous `20'-1 1"`) — exactly the outliers the fit-error report flags.

## Sharing the rounding error

The distances are rounded to the nearest **quarter inch**, so no single
one is exact — four rounded circles almost never meet at one point. Rather
than trust two distances and let the other two absorb all the slop, the
command does a **least-squares fit**: it finds the point whose distances
to the corners best match *all* the given measurements at once, so the
leftover error is spread evenly across them.

For each plotted point the routine reports a **fit error (RMS)** — the
size of that shared leftover error. For clean quarter-inch data it's
usually well under `0.10"`. A noticeably larger value flags a bad reading
(a typo, a mislabelled column, or a genuinely bad measurement).

## Two distances, and the mirror

Three or more distances fix a point outright and are least-squares
fitted. **Two** are crossed exactly instead, as circles, and the root
nearest the middle of the frame is taken.

That matters more than it sounds. Two circles meet twice, either side of
the line joining the corners they came from:

* from two **adjacent** corners that line is a side of the rectangle, so
  one root is inside the frame and the other is not — the frame picks the
  answer;
* from two **opposite** corners it is a diagonal: both roots are inside,
  both fit the two distances to the same hundredth, and the sheet
  genuinely does not say which of the two the point is. That row is
  plotted and **named on the command line**, because a survey import must
  not guess silently. A third distance from any corner settles it.

Least-squares cannot do this job. On the diagonal both residual gradients
point the same way, so the normal matrix is singular and the iteration
stops where it started — and where it starts is the middle of the frame.
Before this was fixed, a two-distance row from opposite corners plotted
**at the centre of the rectangle**, with tens of inches of fit error and
nothing but the RMS column to say so.

## Usage

1. Load the lisp: *Manage ▸ Load Application* (`APPLOAD`), pick
   `ALTABCDEF.lsp`. (Add it to your Startup Suite to load it every session.)
2. Type **`ALTABCDEF`** and press Enter.
3. Pick the spreadsheet in the file dialog.
4. Enter the **A-B** width and the **A-D** height when prompted (e.g.
   `20'-6"`).
5. Pick the insertion point for corner **A** (or press Enter for `0,0`).

The command draws:

* the **rectangle** A-B-C-D with the corners labelled (layer
  `ALTABCDEF-FRAME`),
* a **point node + circle marker** at each computed location (layer
  `ALTABCDEF-POINTS`), and
* the **point name** beside each one (layer `ALTABCDEF-LABELS`),

then prints a results table with each point's coordinates, how many
distances were used, and its fit error.

The **frame is always a true rectangle** — `A-B` is drawn horizontal and
`A-D` vertical, and it is built square to the world axes even if your
current UCS is rotated.

Both halves of that are now **checked rather than claimed**. Before
anything is drawn the four corner coordinates are measured against the
`A-B` and `A-D` you entered — all four sides and both diagonals — and a
mismatch aborts the run with an alert instead of plotting every point
against a frame that is not the one you asked for. Afterwards the four
corner angles are measured off the drawn coordinates and printed as
measured. (They used to be printed as the constant `90.00 deg`, which is
a claim about the source rather than about your drawing; `ABCDEF` learned
the difference the hard way, twice, when a stale copy of it drew a
parallelogram and said it had not.)

When it's finished the command resets the view to plan (top) and zooms to
the drawing, because a flat rectangle looks like a *parallelogram* in a
tilted 3D view — if yours looked skewed, the view was orbited off plan,
not the geometry. (This only changes the view, never the geometry; type
`PLAN` or orbit back any time.)

## Units

Everything is created in **inches** — one drawing unit = one inch. Set
your drawing's units to Architectural (or Decimal inches) to read the
coordinates back out in feet-inches.

## Compatibility

Written and kept to **AutoCAD 2018-safe AutoLISP** (full AutoCAD, not LT).
Only long-standing `vl`/`vlax` and core functions are used — nothing added
after 2018. The smart-quote cleanup probes `chr`/`ascii` at runtime and only
applies when they round-trip Unicode cleanly (they do on 2018); on any build
that can't, the step is skipped rather than risking a bad substitution, so
the rest of the tool is unaffected. Should work unchanged on 2018 through the
current release.

## Tunables

Every threshold, layer name, colour, size and tolerance is a named
`(setq altabcdef:*name* ...)` in one **tunables block** at the top of
`ALTABCDEF.lsp`, between the version banner and the first `defun`, each
with a sentence saying what changing it does. Nothing below that block
carries a bare number.

Edit the file and `APPLOAD` it again, or `(setq altabcdef:*name* value)`
at the command line for one session. Distances are in inches.

The layer names are this command's own on purpose: `ABCDEF` plots onto the
shared `POINTS` layer as `ab_pt` blocks that `ABHD` and the other fitters
read, while this one draws plain markers, so pointing it at `POINTS` would
leave entities there that those tools would try to fit a pool through.

`tests/test_tunables.py` checks this table against the file itself -- every
knob present, with the default it really has -- and
`tests/test_altabcdef.py` asserts each one is live.

### What it draws

| Knob | Default | What changing it does |
| --- | --- | --- |
| `altabcdef:*frame-layer*` | `"ALTABCDEF-FRAME"` | the rectangle and its corner letters |
| `altabcdef:*frame-color*` | `1` | ...the colour it is created with (an existing layer keeps its own) |
| `altabcdef:*point-layer*` | `"ALTABCDEF-POINTS"` | the point node and its marker circle |
| `altabcdef:*point-color*` | `2` | ...the colour it is created with |
| `altabcdef:*label-layer*` | `"ALTABCDEF-LABELS"` | the point names |
| `altabcdef:*label-color*` | `3` | ...the colour it is created with |
| `altabcdef:*text-div*` | `120.0` | text height is the longer rectangle side divided by this |
| `altabcdef:*text-min*` | `0.5` | ...but never under this many inches |
| `altabcdef:*marker-scale*` | `0.4` | marker circle radius, in text heights |
| `altabcdef:*label-off*` | `1.4` | how far up and right of a point its name sits, in marker radii |
| `altabcdef:*tag-scale*` | `1.4` | corner letters are this many text heights tall |
| `altabcdef:*tag-gap*` | `1.0` | how far a corner letter sits out from its corner, in text heights |
| `altabcdef:*tag-drop*` | `1.6` | ...how far below a bottom corner, which has to clear the letter height |

### The sheet

| Knob | Default | What changing it does |
| --- | --- | --- |
| `altabcdef:*file-types*` | `"xlsx;xls;xlsm;csv"` | what the file dialog offers |
| `altabcdef:*hdr-dist*` | `'("FROM A" "FROM B" "FROM C" "FROM D")` | header words naming the distance columns, in corner order A B C D |
| `altabcdef:*hdr-name*` | `'("NAME" "POINT" "LABEL")` | ...and the point-name column; the first header matching any of them wins |
| `altabcdef:*min-tapes*` | `2` | how many distances a row needs before it is plotted at all |

### Reading dirty values

| Knob | Default | What changing it does |
| --- | --- | --- |
| `altabcdef:*apos-over*` | `1.05` | a mark-less reading over this many times the diagonal had its foot mark scanned as a digit |
| `altabcdef:*impossible*` | `1.1` | ...and one still over this many times the diagonal is left blank as unreadable |
| `altabcdef:*fractions*` | `'(2 4 8 16 32)` | the denominators an inch fraction may have; one not listed is never invented |
| `altabcdef:*log-denom*` | `32` | the correction log rounds to 1/this of an inch |

### Numerical

| Knob | Default | What changing it does |
| --- | --- | --- |
| `altabcdef:*fuzz*` | `1e-9` | two lengths closer than this are the same length |
| `altabcdef:*solve-iters*` | `60` | most Gauss-Newton steps the fit will take (three or more distances) |
| `altabcdef:*solve-step*` | `1e-7` | ...and the step size under which it is done |
| `altabcdef:*solve-singular*` | `1e-12` | a normal-matrix determinant under this means the distances do not constrain the point |
| `altabcdef:*seed-singular*` | `1e-9` | ...the same for the linear seed |
| `altabcdef:*frame-tol*` | `0.001` | inches a side or diagonal may be out before the corner self-check aborts the run |
| `altabcdef:*mirror-min*` | `1.0` | how far the mirror answer must sit from the one taken to count as a real second possibility |

## Tests

```
python3 tests/test_altabcdef.py
CALOFIN_LISP_ROOT=shared python3 tests/test_altabcdef.py   # grouped build
```

The whole command is driven in the repo's AutoLISP VM
(`tests/lispvm.py`) against surveys whose true coordinates are known:
the arithmetic under the clockwise corner order, the mirror pair, the
parser (asserted case for case against `ABCDEF`'s, since both read the
same handwriting), the command's own CSV reader, the frame it draws,
`Back` at every question, a cancelled dialog, a sheet with nothing
usable in it, a frozen or locked output layer, `UNDO` switched off, an
Esc mid-run, the corner self-check, and every tunable.

## Notes & limitations

* **CSV files need only AutoCAD** — they are parsed natively. Only `.xlsx` /
  `.xls` / `.xlsm` require desktop AutoCAD with Microsoft Excel installed (read
  through Excel COM automation, which won't run in AutoCAD LT). If a spreadsheet
  won't load, export it to CSV and use that.
* Points are placed relative to corner A using the A-B and A-D dimensions
  you enter; the sheet's distances are never assumed to agree with those
  dimensions, only with each other.
* A point given fewer than two distances is skipped and listed in the
  report.
* Two distances from **opposite** corners fit two points equally well;
  the row is plotted and named, and only a third distance can say which
  is right (see *Two distances, and the mirror*).
* `ABCDEF` is the sister command for a sheet whose bottom corners are
  labelled the other way round, and it is the one that has grown the
  confidence report, the tape-dropping rules and the C/D detector. The
  two conventions are not interchangeable — that is why they are two
  commands.
