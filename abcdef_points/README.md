# ABCDEF — plot measured points into AutoCAD from a spreadsheet

`ABCDEF.lsp` is an AutoLISP command for AutoCAD (full AutoCAD — it uses
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
  (three or four give a stronger, unambiguous fix).
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

The fixes applied:

* **Look-alike characters** — `O`/`o`→`0`, `I`/`l`/`|`→`1`, `_`→`-`, en/em
  dashes and the curly "smart quotes" Word/Excel insert (`’ ′`→`'`, `” ″`→`"`).
* **Missing foot mark** — a bare `28-7` is read as `28'-7"` (the dash marks the
  feet/inch split). A trailing `'` used where a `"` belongs is handled too.
* **Stray spaces in the feet** — `1 1'` or `21 1-` collapse to `11'` / `21'`.
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

## Usage

1. Load the lisp: *Manage ▸ Load Application* (`APPLOAD`), pick
   `ABCDEF.lsp`. (Add it to your Startup Suite to load it every session.)
2. Type **`ABCDEF`** and press Enter.
3. Pick the spreadsheet in the file dialog.
4. Enter the **A-B** width and the **A-D** height when prompted (e.g.
   `20'-6"`).
5. Pick the insertion point for corner **A** (or press Enter for `0,0`).

The command draws:

* the **rectangle** A-B-C-D with the corners labelled (layer
  `ABCDEF-FRAME`),
* a **point node + circle marker** at each computed location (layer
  `ABCDEF-POINTS`), and
* the **point name** beside each one (layer `ABCDEF-LABELS`),

then prints a results table with each point's coordinates, how many
distances were used, and its fit error.

The **frame is always a true rectangle** — `A-B` is drawn horizontal and
`A-D` vertical, so every corner is exactly 90°, and it is built square to the
world axes even if your current UCS is rotated. When it's finished the command
resets the view to plan (top) and zooms to the drawing, because a flat
rectangle looks like a *parallelogram* in a tilted 3D view — if yours looked
skewed, the view was orbited off plan, not the geometry. (This only changes
the view, never the geometry; type `PLAN` or orbit back any time.)

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
