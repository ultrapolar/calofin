# CDCREATE — Cross dimensions from highlighted lines

An AutoLISP routine for full AutoCAD that turns every highlighted line
into a cross dimension: an aligned dimension measuring the line end to
end, in the **`CROSS DIMENSIONS`** dimension style, on the
**`DIMENSION`** layer.

## What it does

1. **Highlight the lines** — either select them *before* typing the
   command (a pickfirst selection is taken as-is) or window/crossing-
   select them at the `Highlight the lines to cross-dimension:` prompt.
2. Every `LINE` in the selection gets an **aligned dimension** along it,
   from endpoint to endpoint, with the dimension line sitting **on the
   line itself** — the usual look for a cross-dim tie drawn across a
   pool.
3. The text is slid along that dimension line to about **80% of the way
   toward the right-hand end** instead of sitting centred — the
   **bottom** end on a line standing near vertical, where "right-hand"
   would be a coin toss. Whichever way round the line happens to have
   been drawn, the text lands on the same end.
4. Each new dimension is put in the `CROSS DIMENSIONS` dimension style
   and on the `DIMENSION` layer, **ByLayer**: any per-entity colour,
   linetype or lineweight override the command left behind is stripped,
   so the dims look exactly like the cross dims `POOL` draws.
5. **The line each dimension was made from is erased** — the tie
   measurement is left as a dimension and nothing else. Only lines that
   really did get a dimension go; the report says how many, and off
   which layers (normally `POOL` or `POINTS`). Set `cdc:*erase*` to
   `nil` to keep them.

The whole run is one undo group, so a single `U` puts the lines back and
takes the dimensions away. The dimension style, current layer,
`CMDECHO` and `OSMODE` in force before the command are restored
afterwards, whether the run finishes, errors, or is cancelled with Esc.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `CDCREATE.lsp`. Add it to the *Startup Suite* to have it in
   every drawing.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `CDCREATE` | Dimension the highlighted lines as cross dims |
   | `CDCREATEVER` | Print the version |

## Tunables

`setq` these after loading (in a startup file, say) when a drawing needs
different names:

| Variable | Default | Meaning |
| --- | --- | --- |
| `cdc:*style*` | `"CROSS DIMENSIONS"` | Dimension style the new dims get |
| `cdc:*layer*` | `"DIMENSION"` | Layer the new dims are created on |
| `cdc:*offset*` | `0.0` | How far the dimension line is pushed perpendicular to the line it measures, in drawing units. `0.0` puts it on the line |
| `cdc:*erase*` | `T` | Erase each line once its dimension is drawn. `nil` keeps the lines |
| `cdc:*textpos*` | `0.8` | Where the text sits along the dimension: `0.0` the far end, `0.5` centred (no text move at all), `1.0` the right/bottom end |
| `cdc:*vertang*` | `15.0` | How near vertical, in degrees, a line has to stand before its text goes to the bottom end rather than the right-hand one |

## Notes & limitations

* **Only `LINE` entities are dimensioned.** Anything else in the
  selection — polylines, arcs, text, blocks — is counted and reported,
  not dimensioned. Explode a polyline first if its segments need cross
  dims.
* The text is moved with `DIMTEDIT`, along the dimension line, so the
  dimension line itself does not shift whatever `DIMTMOVE` is set to.
  The dimension is flagged as having a user-defined text position, which
  is what stops the text springing back to the middle.
* Erasing the line cannot disturb its dimension: the extension-line
  points are picked as plain coordinates (`_non`, with osnaps off), so
  the dimension is not associated with the line and keeps its
  measurement once the line is gone.
* Zero-length lines are skipped; there is nothing to measure — and a
  skipped line is never erased, only a line that got its dimension is.
* The `DIMENSION` layer is **created** when the drawing lacks it
  (colour 7, continuous) — and when it is already there but frozen,
  locked or switched off, it is thawed, unlocked and switched back on,
  with a line saying so. A run onto a frozen layer would otherwise look
  like the command did nothing.
* A missing `CROSS DIMENSIONS` style is **not** invented. The dims are
  drawn in whatever style is current and the routine says so, so a
  drawing started from the wrong template is obvious instead of quietly
  producing wrong-looking dims. Create the style — or start from the
  standard template — and run it again.
* `DIMLAYER` (which forces dimensions onto a layer of its own,
  regardless of the current layer) does not get the last word: each new
  dimension is pulled back onto `DIMENSION` after it is drawn.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**

## Tests

`python3 tests/test_cdcreate.py` loads the real `CDCREATE.lsp` into the
repo's AutoLISP VM (`tests/lispvm.py`) and drives `c:CDCREATE` with
scripted selections — pickfirst and prompted, mixed selections, an empty
drawing, a drawing with no `CROSS DIMENSIONS` style, a hostile
`DIMLAYER`, a non-zero offset, ties drawn on `POOL` and `POINTS`,
`cdc:*erase*` switched off, a frozen/locked/off `DIMENSION` layer, and
the text-end rule on flat, steep, near-vertical and either-way-round
lines. `CALOFIN_LISP_ROOT=shared python3 tests/test_cdcreate.py` runs
the same suite against the grouped build.
