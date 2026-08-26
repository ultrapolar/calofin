# LAZFORM -- fill a dimension chart in, then draw the pool (AutoLISP / AutoCAD 2018+)

## What it does

`LAZFORM` puts the chart on screen the way it looks on paper -- and the
horizontal dimension rows of that chart **are rows of real textboxes**:
the drawing is cut into bands at the heights where B, T, S, W and the
H-G-F-E chain run, and those rows carry edit boxes pushed to their
letters' positions. You type where the chart says the measurement
lives. The vertical dimensions (A, M, L, K, S1, V) cannot stand in a
row, so they keep boxes in the side column, labelled with their
letters, and what you type there is drawn onto the chart in the
letter's place.

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

A **tab strip** across the top switches charts. Eight are drawn, on two rows -- eight keys on one line run about 94 character cells against a budget of 90, which is a dialog that does not open, so they wrap:

| Chart | POOL shape | Letters on the picture |
| --- | --- | --- |
| `Rectangle` | Rectangle | B A H G F E M L K |
| `Oval` | Oval | B T A H G F E W M L K |
| `ROman` | ROman | B T A S S1 V H G F E W M L K |
| `Grecian` | Grecian (6-sided hopper) | B S T S1 A V H G W L1 M L K F E |
| `GRSquare` | Grecian (square hopper) | B S T S1 A V H G M L K F E |
| `L` | L | B B1 B2 A A1 A2 H G F E M L K |
| `ROUnd` | ROUnd | B A W (H G F E M L K in the list) |
| `OCtagon` | OCtagon | B S T A S1 V H G F E M L K (S2 in the list) |

**The bottom type decides which boxes are live.** A style does not ask
for every letter on the sheet, and the form used to offer them all
anyway -- type a `C` against a Normal hopper and POOL never asks for
it, so the number went nowhere and nothing said so. Picking a bottom
now greys what that bottom will never reach, and a greyed value is not
sent to POOL either.

| Bottom | Greyed |
| --- | --- |
| Standard Hopper (`Normal`) | C, D, C2 -- it draws no side view at all |
| `Sport` | H, F, E, C2 |
| `Wedge` | G, E, C2 |
| `SLope` | G, C2 |
| `MOdflat` | E, C2 |
| `SHallow` | nothing -- it is the only style that asks C2 |

That table is not kept here in code: `lzf:btskip` reads POOL's own
`pool:btmspec` -- `(ask-G ask-E has-profile ask-C2 slack)` -- so the
form cannot drift from the command it feeds. LAZFORM already refuses to
open without POOL loaded, so it is always there to ask.

**Sport is the exception, and not a small one.** `btmspec`'s
has-profile flag reads nil for Sport, which would say "no C or D" --
but that flag is only ever consulted inside `pool:hopnormal`, and a
Sport never goes near it. Sport has its own path, which *does* ask C
and D, and which asks a different plan chain entirely: **E2 F2 G F1 E1
M K**, not H G F E. So on a Sport the chart's H, F and E are greyed:
they are not what POOL will ask for, and a number typed into one would
be read by nothing. Only G, M and K carry over from the drawn chain.
Sport's own letters have no boxes yet -- that is the open gap on this
sheet.

Every chart carries C, D and C2 rows. Four of the original six never had
them, so on a Roman, an Oval or either Grecian the depths always fell
through to the command line whatever you did.

**Round** is the newest sheet, and the one that behaves differently.
POOL's `ROUnd` flow asks two overalls -- `B` across and `A` up, both
through the middle -- then hands the bottom to the *same* routine the
oval uses, so the hopper letters are the oval's (`H G F E`, `W`,
`M L K`) while the plan pair is not (`b` and `a`, where an oval answers
`tot`, `tp` and `le`). Tick **in-square** and POOL asks one diameter,
keyed `b`, so `B` is the box that matters.

Two things about it are worth knowing:

- **`M L K` run through the centre, and they have to.** POOL resolves
  that chain against the overall width, so `M+L+K` must equal `A` --
  and on a circle the only vertical that is a full diameter is the one
  through the middle. The first draft measured them at the hopper's
  own x and the chain-closure test caught it: 460 against an `A` of
  500.
- **`H G F E` are answered in the list, not on the drawing.** A wedge
  box is its letter plus ten cells, so four of them need 44 of the
  chart's 52 -- and a round pool spans about 31. On the rectangle that
  chain runs the full width and just fits; on a circle it cannot, and
  forcing it puts boxes nowhere near the letters they belong to. Every
  dimension is still enterable; only the position of four boxes
  differs.

**Corners** get their own section on the Rectangle and True L charts:
a dropdown per corner -- `(ask)`, `Square`, `Radius`, `Cut`,
`NotGiven` -- with a size box that stays greyed until a sized
treatment is picked. `(ask)` is the dropdown's version of an empty
box: POOL asks that corner at the command line as always. A sized
treatment with the size left empty sends the treatment alone and POOL
asks for just the number; a size its walls cannot fit is rejected by
POOL's own cap check and retyped at the keyboard. In-square is the one
wrinkle: an in-square rectangle asks ONE question for all four
corners, so when that toggle is on, corner A's row speaks for all four
and the other three are ignored. The True L's rows are its two real
questions -- the outer corners as a set, and the reverse corner E,
which until now could not be answered from a form at all. Roman and
the Grecians spell their corners as letter dimensions (S, S1, S2, X)
that are already on the chart.

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

Why bands and not the drawing as one background with boxes floated on
it: DCL has no z-order at all -- no tile may overlap any other tile, so
there is no "behind" to put a drawing in. Cutting the chart where its
dimension rows run is the closest the language comes, and it is honest
about two costs: the bands are separated by strips of dialog
background, and box positions are in character cells, so a box lands
within a cell or so of its letter and chains pack shoulder to
shoulder.

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

## Could the chart be drawn in characters? (`LAZASCII`) -- ANSWERED: no

**Run on AutoCAD 2018+, and the answer is no.** The dialog font is
proportional: `WWWWWWWWWWWW` came out roughly three times the width of
`iiiiiiiiiiii` for the same twelve characters, so the right-hand bars
were nowhere near a column and the pool drawn in characters sheared
apart line by line, exactly as feared. Character art in a DCL dialog
is not on.

Two useful things came out of it anyway:

- **Leading spaces DO survive.** The three indented bars made a clean
  staircase, so DCL is not trimming them. That was the other way this
  could have died, and it did not -- it just does not help while the
  font is proportional.
- **Section 4 lined up perfectly.** A row built from `text` tiles with
  explicit widths and an `edit_box` between them renders straight in a
  proportional font, because the alignment comes from tile widths
  rather than glyphs. `B` and `A` sat exactly above one another.

That last point is the important one, and it is **what the wedge rows
already do**: the boxes on this form are positioned by spacer widths,
not by counting characters. So the answer to "could we draw the pool in
ASCII and put the boxes in it" is that the boxes-in-the-line half
already works and the ASCII half never will. Switching would have cost
the outline drawing and bought nothing.

The retention worry that motivated the question stands -- DCL does not
retain an `image` tile, and a `text` tile it does -- but the passive
tile has held up in practice, and a chart with no picture on it is a
poor trade for a hazard that has not recurred.

`LAZASCII` stays in the file. It is cheap, and the answer is a property
of the AutoCAD build rather than of this code, so it is worth being
able to re-ask on another machine or another release.

### What it shows

Drawing the pool in **text** rather than vectors would win something
real, and it is worth being clear about what. DCL does not *retain* an
image tile: anything that repaints the dialog clears the picture and
there is no expose callback to draw it again. That is the structural
reason the chart has vanished on people -- the passive `image` tile
holds up in practice, but nothing in DCL promises it will. A `text`
tile is retained by the dialog manager like any other control, so a
chart drawn in characters could not vanish at all. The boxes could
also sit *in* the drawing rather than beside it.

It turns on one thing this repo cannot answer for itself: **is the DCL
dialog font fixed-pitch?** Character art needs every glyph the same
width. DCL gives no way to choose a font, and its widths are quoted in
"character cells" that are an average rather than a guarantee -- so
this is a property of the AutoCAD build, not of the code.

`LAZASCII` asks AutoCAD instead of guessing. It opens a dialog with
four sections:

1. **Fixed-pitch test** -- five lines of twelve characters each
   (`iiii…`, `WWWW…`, digits, dashes, spaces) between bars. If the
   right-hand bars form one straight column the font is fixed-pitch
   and character art is on.
2. **Leading spaces** -- three bars indented 0, 4 and 8 spaces. A
   staircase means DCL keeps the indent; three bars in one column
   means it trims them and art is impossible whatever the font.
3. **The pool in characters** -- what a chart would look like.
4. **A box in the dimension line** -- the fallback that works either
   way, where alignment comes from tile *widths* rather than glyphs.

Run it and read off which sections lined up. Section 4 is the answer
if 1 or 2 fail: it costs the fine detail of the outline but puts the
edit box in the line, and it cannot vanish.

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
