# VSCONV -- a VS survey export converted onto the shop layers (AutoLISP / AutoCAD 2018+)

A VS trace arrives on the exporter's own numbered layers, and the
office draws on `POOL` / `POINTS` / `DIMENSION`. `VSCONV` is that
rename, in one pass: the layer move, everything forced BYLAYER, and the
dimensions taken off the exporter's dimension style **and its
overrides**.

It is the sibling of `DRONE` and `TYDRN` (`lisp/drone/`, `lisp/tydrn/`)
-- the same one-pass cleanup, written for the export that arrives on
foreign layers rather than for the trace that arrives with labels on it.

## What it does

1. **LAYERS** -- every object on a source layer moves to the layer
   `*vsconv-map*` pairs it with, with color, linetype and lineweight
   forced to BYLAYER so the moved geometry takes the destination
   layer's own appearance instead of carrying the export's:

   | From | To | What it is |
   | --- | --- | --- |
   | `1 Perimeter` | `POOL` | the outline |
   | `2 Coping` | `POOL` | the coping band |
   | `3 Features` | `POOL` | steps, benches, the skimmer |
   | `3.1 Anchors` | `POINTS` | the survey points (`POINTS` is magenta, so they show pink) |
   | `4 Dimensions` | `DIMENSION` | the export's dimensions |

   Three source layers landing on `POOL` is the point of the table
   rather than a flaw in it: perimeter, coping and features are one
   drawing to this office and three to the exporter.

2. **DIMENSIONS** -- every dimension that came over is put on the shop
   dimension style (`STANDARD`) **and has its style overrides
   removed**. Both halves matter. The export writes the text height,
   the arrow size and the decimal places into each dimension as an
   `ACAD`/`DSTYLE` xdata block, and an override outranks the style it
   sits on -- so a dimension merely renamed to `STANDARD` would still
   draw itself in the export's 2.5-unit text. Strip the block and the
   style is finally the thing that decides.

The destination layers are created if missing (and un-frozen,
un-locked and switched back on when they are there but unusable).
Locked layers among those touched are unlocked for the run and
re-locked afterwards, on the error path too. The whole run is one undo
mark, and a done line reports what moved, per source layer.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `VSCONV.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Optionally highlight the import, then:

| Command | What it does |
| --- | --- |
| `VSCONV` | Convert the highlighted import; Enter at the prompt takes every VS layer in the drawing |
| `VSCONVVER` | Print the loaded version |

Scope is what you highlight. Press Enter at the selection prompt and
it takes every object on a source layer, drawing-wide. Either way only
the layers in the table are touched, so a sheet that already carries
converted work cannot be converted twice, and a drawing with none of
those layers is reported as such rather than prompting for a selection
it has no use for.

## Tunables

At the top of `VSCONV.lsp`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*vsconv-map*` | the five pairs above | source layer -> destination layer. **The conversion is this table** -- an export that names its layers differently is retuned here and nothing else in the file changes |
| `*vsconv-colors*` | `POOL` 4, `POINTS` 6, `DIMENSION` 141 | the color a destination layer is *created* with |
| `*vsconv-default-color*` | `7` | for a destination the table above does not name |
| `*vsconv-dim-style*` | `"STANDARD"` | the style the dimensions land in |
| `*vsconv-dim-xdata*` | `"ACAD"` | the application whose style overrides go with the rename; `nil` leaves the overrides on |

## Notes & limitations

* `*vsconv-map*` holds exact layer names, not patterns. They go into
  an `ssget` layer filter, which reads them as `wcmatch` patterns, so a
  name carrying one of `,` `*` `?` `#` `@` `~` `[` `]` or a backquote
  would select layers the rest of the file then does not know what to
  do with.
* A drawing whose color, linetype or lineweight was set per object on
  purpose loses that in the move -- BYLAYER is the whole point of the
  conversion, and the export sets none of the three.
* If the drawing has no `*vsconv-dim-style*` dimension style, the
  dimensions still move layer but keep the export's style and its
  overrides, and the run says so once rather than once per dimension.
* The emptied source layers are left in the drawing and named in the
  done line rather than purged, so one `U` backs the whole run out.
  `PURGE` them when you are satisfied with the result.
* Objects inside block definitions are not converted -- only what is
  in model or paper space.
* There is no text step: a VS export carries no point labels. A drone
  trace that *does* arrive labelled is `DRONE`'s or `TYDRN`'s job.
* Requires the Visual LISP engine (ActiveX is used throughout), which
  ships with full AutoCAD. AutoCAD LT cannot run this file.

## Tests

`python3 tests/test_vsconv.py` runs VSCONV in the repo's AutoLISP VM
over an export built the way one arrives -- the five numbered layers,
one of them locked, dimensions carrying both the export's style and its
`DSTYLE` overrides, and a title-block TEXT that is none of its business.
It checks the move, the BYLAYER forcing, that the overrides go with the
style rename, that a highlight scopes the run, that a drawing with none
of those layers is reported rather than prompted over, the
missing-dimension-style path, and the two cut-short paths (an error
mid-run and an Esc at the prompt) that reach the command's own
`*error*` -- which has to put the lock back and close the mark.
`CALOFIN_LISP_ROOT=shared` reruns it against the grouped twin.
`python3 tests/test_shared.py` still loads it with everything else, so a
name collision fails there.
