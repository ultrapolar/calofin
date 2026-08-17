# DIMCONTEND — Continue a dimension to the end of the drawing

An AutoLISP routine for full AutoCAD that continues an existing
linear/aligned dimension across a highlighted part of the drawing,
holding every property of the dimension you start from.

## What it does

1. **Select the dimension to continue** — pick one existing *linear*
   or *aligned* dimension. This is the *seed*: its dimension style,
   layer, text, arrowheads, precision, orientation and travel direction
   are all inherited by the new dimensions.
2. **Highlight the drawing** — window/crossing-select the geometry you
   want dimensioned.
3. The routine gathers the feature points of that geometry (line and
   polyline vertices, arc/spline/ellipse endpoints, points, circle
   centres), keeps the ones that lie **beyond the seed's far extension
   line** along the seed's measurement axis, and chains **continued
   dimensions** from the seed out to the last point — the end of the
   drawing — in a straight line.

Because the chain is built with AutoCAD's own `DIMCONTINUE` anchored on
the seed, each new dimension shares an extension line with the previous
one and matches the seed exactly — no property copying to get wrong.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application`
   (`APPLOAD`) → pick `dim_continue.lsp`. Add it to the *Startup Suite*
   to have it available in every drawing.
2. Type the command:

   | Command | Alias |
   | --- | --- |
   | `DIMCONTEND` | `DCE` |

3. Follow the two prompts (select seed dimension, then highlight the
   drawing).

## Notes & limitations

* **Seed type:** only DXF dimension type 0 (rotated / horizontal /
  vertical) or 1 (aligned) can be continued. Angular, radial, diameter
  and ordinate dimensions are rejected.
* **Direction:** the continuation follows the seed's own direction
  (from its first extension line toward its second and beyond), so a
  seed drawn right-to-left continues leftward. Points that fall short of
  the seed's far extension line are ignored.
* **Measurement axis:** taken from the seed — the rotation angle for a
  rotated dimension, or the line through its two extension-line origins
  for an aligned dimension — so continuation works for rotated layouts.
* Duplicate points that project to the same position on the axis are
  collapsed, so overlapping geometry does not create zero-length
  dimensions.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**
