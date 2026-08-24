# LAZFORM -- fill a dimension chart in, then draw the pool (AutoLISP / AutoCAD 2018+)

## What it does

`LAZFORM` puts the chart on screen the way it looks on paper -- the pool
outline, the hopper, and the dimension chain with its letters -- next to
a box for every letter. Type a number against a letter and **the letter
is replaced by what you typed**, which is what the letter was standing
in for all along. Every box is labelled with its own letter, so the list
and the picture read as one thing.

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

A **tab strip** across the top switches charts. Six are drawn:

| Chart | POOL shape | Letters on the picture |
| --- | --- | --- |
| `Rectangle` | Rectangle | B A H G F E M L K |
| `Oval` | Oval | B T A H G F E W M L K |
| `ROman` | ROman | B T A S S1 V H G F E W M L K |
| `Grecian` | Grecian (6-sided hopper) | B S T S1 A V H G W L1 M L K F E |
| `GRSquare` | Grecian (square hopper) | B S T S1 A V H G M L K F E |
| `L` | L | B B1 B2 A A1 A2 H G F E M L K |

Anything a sheet carries that has no place on the plan view gets a box
and no letter: the depths `C` and `D` (read off a section), the radii
`R1 R2 R3`, the check dimensions `S2` and `X`, the out-of-square second
overalls, and Roman's right-hand `S`/`S1`/`V` for when the two ends are
not identical. Below the boxes: an in-square toggle and the bottom type.

**The same letter is not the same measurement on every sheet.** A
rectangle's `B` is the side length (`tp`); an oval's `B` is the
tip-to-tip total (`tot`) and it is the *side* that becomes `T`. The
mapping is per chart, and `tests/test_lazform.py` checks every key
against POOL's own question lists, so a letter pointed at the wrong key
fails the suite rather than silently swallowing what you type.

Clicking a dimension's **letter button** puts the caret in that box,
selects what is already there so your first keystroke replaces it, and
rings that dimension on the drawing. It sits against the box it fills,
which is as close to clicking the drawing itself as DCL allows -- see
below for why the drawing cannot take the click.

Switching tabs keeps everything you have typed (the answers are keyed,
so they survive and are still there if you tab back) and reopens the
dialog where you dragged it rather than back in the middle of the
screen.

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

So the chart is **drawn** rather than loaded, from a table of lines, and
the numbers appear on it as they are typed -- which recovers most of
what a box sitting on the artwork would have given, with nothing to
install.

An earlier version also let you click the picture to jump to a box, via
an `image_button`. That had to go, and the reason is worth writing down
because it will catch anyone who tries it again: **a DCL image tile is
not retained by AutoCAD.** Any repaint clears it to the tile's own
`color` attribute and everything the application drew into it is gone,
and there is no expose callback to redraw from. An `image_button` is
repainted on mouse-enter and mouse-leave, so the chart vanished the
first time the cursor crossed it. A plain `image` tile is passive: no
highlight, no repaint, nothing to vanish. The same rule is why the
chart is redrawn after the bottom-type list and the in-square toggle as
well as after every edit box -- a list unrolling over it does the same
damage, and nothing else would repair it.

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
- The picture is read, not clicked -- see above.
- DCL has no tab tile. A tab is a button that closes the page and
  reopens the next, so the dialog blinks as it switches. `done_dialog`
  reports where the dialog was standing and `new_dialog` takes a
  position back, so it reopens in the same spot -- the blink is
  unavoidable, the wandering is not.
- Lazy L is not here yet. Its sheet carries eight perimeter letters
  (`B B1 V V1 T T1 A A1`) where POOL asks for six side lengths, and
  four `Y` letters where POOL asks for eight named diagonals, so the
  mapping cannot be settled from the code alone -- see the note in
  `lzf:*charts*`.
- The `Grecian` charts answer three questions on your behalf, because
  their letters only exist on one path through POOL: the perimeter
  input method (`Overall`), the hopper type, and -- on the six-sided
  chart -- that its corners were taped by `Letters`. Those are the
  chart's `gates`.
- A chart's letters assume the bottom type it was drawn for. `W`, `R3`
  and `L1` exist only on a Normal bottom; pick another and POOL asks a
  different set, so those boxes go unread.
- The "Reverse Corner" the True L sheet names is a corner treatment,
  not a measurement, so it has no box -- POOL asks for it directly.
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
