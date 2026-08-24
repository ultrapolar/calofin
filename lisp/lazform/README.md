# LAZFORM -- fill a dimension chart in, then draw the pool (AutoLISP / AutoCAD 2018+)

## What it does

`LAZFORM` puts the chart on screen the way it looks on paper -- the pool
outline, the hopper, and the dimension chain with its letters -- next to
a box for every letter. Type a number against a letter and **the letter
is replaced by what you typed**, which is what the letter was standing
in for all along. Click anywhere on the picture and the box for the
nearest dimension takes the caret, so you can work off the drawing
rather than down the list.

Fill in what you know, leave the rest blank, press **Insert**: `POOL`
runs and asks only for the gaps.

| In a box | On the wire | What POOL does |
| --- | --- | --- |
| left empty | the key is not sent | asks the question as usual |
| `NA` | `(key . nil)` | takes NA, no prompt |
| `12'6"` or `150` | `(key . 150.0)` | takes the measurement, no prompt |

A typo counts as an empty box on purpose: something that is neither `NA`
nor a distance AutoCAD can read leaves POOL asking, rather than quietly
feeding it a nil that means something else entirely.

The Rectangle chart carries `B A H G F E M L K`, plus boxes for the two
out-of-square overalls and for `C` and `D` -- the depths are read off a
section, not off this view, so they get a box and no place on the
picture. Below the boxes: an in-square toggle and the bottom type.

## Install & run

APPLOAD `LAZFORM.lsp` **and** `lisp/pool/POOL.LSP`, or load
`shared/LAZPASS.lsp`, which carries both. `LAZFORM` says so plainly if
POOL is not in the session rather than opening a form whose Insert
button could only fail. `LAZFORMVER` prints the loaded version.

## Why the boxes are beside the picture and not on it

DCL packs tiles into rows and columns. There is no absolute
positioning and no overlapping, so an edit box cannot sit on an image
tile -- and DCL cannot show a raster at all: an image tile takes
vectors or an AutoCAD slide, nothing else. Those two facts together
rule out "the artwork with text boxes on the letters", which is what
the VB.NET palette in `ui/` does and needs a DLL on every machine to do.

So the chart is **drawn** rather than loaded, from a table of lines; the
numbers appear on it as they are typed; and clicking it moves the caret.
Between them those recover most of what a box sitting on the artwork
would have given, with nothing to install.

There is no text primitive in DCL either, so the letters and numbers are
stroked out of line segments from a small vector font in this file.

## Adding a shape

Adding a shape is adding data, not code: one entry in `lzf:*charts*`
with an outline, a dimension list and its POOL keys. Everything is in
per-mille of the picture, x and y, y running down -- the same convention
an image tile uses, so nothing is flipped at draw time.

```lisp
("rectangle" "Rectangle" "Rectangle"
 ((100 300 900 300 900 860 100 860 100 300)   ; outline polylines
  ...)
 (("B" "tp" 100 175 900 175 "h" "overall across, top side")
  ...)                                        ; letter key x1 y1 x2 y2 side label
 (("c" "C - wall height (shallow depth)")))   ; column-only fields
```

The arrow, the letter and the typed value all come off the dimension's
two endpoints, so there is no separate position table that could fall
out of step with the drawing.

## Assumptions

- POOL is loaded, and its answer store (`pool:*form*`,
  `pool:run-with-answers`) is the receiving end -- see `lisp/pool/`.
- The system temp folder is writable; the dialog is written there at run
  time and deleted when it closes.
- The chart's keys are POOL's keys. `tests/test_lazform.py` checks every
  one of them against the item lists in `POOL.LSP`, so a key POOL does
  not ask for fails the suite instead of being typed into and dropped.

## Notes & limitations

- DCL dialogs are modal and not resizable. The form closes when you
  press Insert and POOL takes over at the command line.
- An edit box reports its value when the caret **leaves** it, so the
  picture updates on Tab or on a click elsewhere, not per keystroke.
- Only the Rectangle chart exists so far. The other POOL shapes are
  data waiting to be written.
- The insertion base point is still picked at the command line.

## Tests

```
python3 tests/test_lazform.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lazform.py # grouped tier
```

The drawing is captured and checked rather than assumed: every vector
must land inside the tile in a colour the file declares, and the
value-replaces-letter rule is checked by counting strokes before and
after. The end-to-end case fills the chart in, presses Insert, and
asserts the pool it draws is identical -- entity for entity -- to the
one POOL draws when the same answers are typed at the prompts.
