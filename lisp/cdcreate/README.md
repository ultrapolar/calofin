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
3. Each new dimension is put in the `CROSS DIMENSIONS` dimension style
   and on the `DIMENSION` layer, **ByLayer**: any per-entity colour,
   linetype or lineweight override the command left behind is stripped,
   so the dims look exactly like the cross dims `POOL` draws.
4. The lines themselves are left alone — a cross-dim tie normally stays
   in the drawing under its dimension. Erase them yourself if they were
   only construction geometry.

The dimension style, current layer, `CMDECHO` and `OSMODE` in force
before the command are restored afterwards, whether the run finishes,
errors, or is cancelled with Esc.

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

## Notes & limitations

* **Only `LINE` entities are dimensioned.** Anything else in the
  selection — polylines, arcs, text, blocks — is counted and reported,
  not dimensioned. Explode a polyline first if its segments need cross
  dims.
* Zero-length lines are skipped; there is nothing to measure.
* The `DIMENSION` layer is **created** when the drawing lacks it
  (colour 7, continuous).
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
`DIMLAYER`, and a non-zero offset.
