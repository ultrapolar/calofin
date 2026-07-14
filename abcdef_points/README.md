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
* `.xlsx`, `.xls`, `.xlsm` and `.csv` all work (`.csv` is opened through
  Excel as well). A ready-to-fill `template.csv` sits next to this file.

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

## Units

Everything is created in **inches** — one drawing unit = one inch. Set
your drawing's units to Architectural (or Decimal inches) to read the
coordinates back out in feet-inches.

## Notes & limitations

* Requires desktop AutoCAD with Microsoft Excel installed (the sheet is
  read through Excel COM automation). It won't run in AutoCAD LT.
* Points are placed relative to corner A using the A-B and A-D dimensions
  you enter; the sheet's distances are never assumed to agree with those
  dimensions, only with each other.
* A point given fewer than two distances is skipped and listed in the
  report.
