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

| Chart | POOL shape | Letters on the picture | Also in the column |
| --- | --- | --- | --- |
| `Rectangle` | Rectangle | B A H G F E M L K | 4 corners, `cmode` + 4 cross dims, Sport chain |
| `Oval` | Oval | B T A H G F E W M L K | `cmode` + 4 cross dims, Sport chain, T check |
| `ROman` | ROman | B T A S S1 V H G F E W M L K | 4 corners, 2 cross dims, Sport chain |
| `Grecian` | Grecian (6-sided hopper) | B S T S1 A V H G W L1 M L K F E | 2 collective corner rows, `gcross` + 2 cross dims, Sport chain |
| `GRSquare` | Grecian (square hopper) | B S T S1 A V H G M L K F E | 2 collective corner rows, `gcross` + 2 cross dims, Sport chain |
| `L` | L | B B1 B2 A A1 A2 H G F E M L K | 2 corner rows, 9 diagonals, `mirror` |
| `ROUnd` | ROUnd | B A W (H G F E M L K in the list) | Sport chain, T check |
| `OCtagon` | OCtagon | B S T A S1 V H G F E M L K (S2 in the list) | 2 collective corner rows, `gcross` + 2 cross dims, Sport chain |

Under the picture each sheet carries the boxes that have no place on a
plan view -- the depths, the radii, the check dimensions, the **Sport
chain**, the **cross dims** and the **corner** rows -- and the switches
that decide which of them POOL will actually ask for.

## What is live on the page

**One decision, applied twice.** A page does not ask for every box on
it, and the form used to offer them all anyway -- type a `C` against a
Normal hopper and POOL never asks for it, so the number went nowhere
and nothing said so. Three things on the page decide, not one:

| Control | What it decides |
| --- | --- |
| **Bottom type** | which plan and depth letters that bottom's own routine asks for |
| **In-square toggle** | whether there are cross dims at all, and whether the second overalls (`bo`, `ri`) are asked |
| **Cross-dim mode** | how many of the `x0…x3` boxes map to a tape |

`lzf:dead` puts the three together and names the dead keys once.
`lzf:btgrey` greys exactly that set and `lzf:form` drops exactly that
set -- one function, two callers -- so the page cannot grey a box and
then send what is in it, or send a box it has greyed. The test suite
asserts that identity directly, over a table of page states.

### By bottom type

| Bottom | Greyed |
| --- | --- |
| Standard Hopper (`Normal`) | C, D, C2 -- it draws no side view at all |
| `Sport` | H, F, E, C2 |
| `Wedge` | G, E, C2 |
| `SLope` | G, C2 |
| `MOdflat` | E, C2 |
| `SHallow` | nothing -- it is the only style that asks C2 |

and, on **every bottom that is not a Sport**, the Sport chain
E2, F2, F1, E1.

That table is not kept here in code: `lzf:btskip` reads POOL's own
`pool:btmspec` -- `(ask-G ask-E has-profile ask-C2 slack)` -- so the
form cannot drift from the command it feeds. LAZFORM already refuses to
open without POOL loaded, so it is always there to ask.

**Sport is the exception, and not a small one.** `btmspec`'s
has-profile flag reads nil for Sport, which would say "no C or D" --
but that flag is only ever consulted inside `pool:hopnormal`, and a
Sport never goes near it. Sport has its own path, which *does* ask C
and D, and which asks a different plan chain entirely: **E2 F2 G F1 E1
M L K**, not H G F E. So on a Sport the chart's H, F and E are greyed:
they are not what POOL will ask for, and a number typed into one would
be read by nothing. Only G, M, L and K carry over from the drawn chain.

**Sport's own letters now have boxes.** `E2`, `F2`, `F1` and `E1` sit
in the column on every sheet whose flow can reach a Sport bottom --
Rectangle, Oval, Roman, both Grecians, Octagon and Round -- labelled
with POOL's own prompts (`E2 - left end shallow flat`, and so on).
They are column boxes because a sport bottom's chain runs along a pool
these charts draw with a hopper in it: there is nowhere on the picture
for them to sit. Pick any other bottom and they grey out again.

### By the in-square toggle

Tick **in-square** and every cross dim and diagonal on the page goes
dead, along with the mode dropdown above them and the out-of-square
second overalls `bo` and `ri`. POOL builds true to the side
measurements there and never asks for a tape across the corners, so a
number typed into one would be read by nothing.

Every chart carries C, D and C2 rows. Four of the original six never had
them, so on a Roman, an Oval or either Grecian the depths always fell
through to the command line whatever you did.

**The L family has no bottom type.** POOL draws the standard hopper on
an L and offers no choice, so the popup is greyed on that page and
`btype` is never sent from it -- and the page is greyed against
`Normal`, which is the bottom those flows really draw.

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

## Cross dims

A cross dim is a tape run corner to corner, and it is the one
measurement with no place at all on a chart drawn square: it runs
diagonally, and a dimension here is horizontal or vertical and nothing
else. So they are all column boxes, in a section of their own.

**How many of them POOL asks for is a question in its own right**, and
that question is the dropdown at the head of the section:

| Chart | Dropdown | What each choice means |
| --- | --- | --- |
| `Rectangle`, `Oval` | `cmode` -- Corner / Middle / Ends | Corner and Middle tape two diagonals (`x0 x1`), Ends tapes four (`x0…x3`) |
| `Grecian`, `GRSquare`, `OCtagon` | `gcross` -- Simple / Center / Complex | Simple tapes the two body diagonals (`x0 x1`); **Center and Complex tape 14 and 18**, far more than a sheet has boxes for, so the dropdown answers the gate and those diagonals are typed at the command line |
| `ROman` | none | it always asks the same two, `A-C` and `B-D` |
| `L` | none | it always asks the same nine: `A-C B-D C-E D-F A-E B-F A-D B-E C-F` |

The `xN` boxes are labelled neutrally -- `Cross dim 1` … `Cross dim 4`
-- on purpose: which diagonal each one is depends on the mode, and
POOL's own prompt spells it out when it asks. Leave the dropdown on
`(ask)` and every box under it is dead and none of them travels: the
mapping from box to tape is undefined until the mode is, so a number
typed into one would be attached to the wrong diagonal.

The Grecian pages say the Center/Complex rule on the page itself, in a
line under the form, because a form that silently drops 14 numbers
would be worse than one that never offered the boxes.

## Corners

**Corners** get their own section on every chart whose POOL flow asks
for treatments in these terms -- Rectangle, Roman, both Grecians,
Octagon and True L. Each row is a dropdown -- `(ask)`, `Square`,
`Radius`, `Cut`, `NotGiven` -- with a size box that stays greyed until
a sized treatment is picked. `(ask)` is the dropdown's version of an
empty box: POOL asks that corner at the command line as always. A
sized treatment with the size left empty sends the treatment alone and
POOL asks for just the number; a size its walls cannot fit is rejected
by POOL's own cap check and retyped at the keyboard.

**In square and out of square are different questions**, and that is
why a row names the POOL stems it answers in each state rather than
one fixed name:

| Chart | Rows | In square | Out of square |
| --- | --- | --- | --- |
| `Rectangle`, `ROman` | Corner A … Corner D | POOL asks once, so corner A's row speaks for all four (`corners`) and B–D are ignored | one question each: `cornera` … `cornerd` |
| `Grecian`, `GRSquare`, `OCtagon` | Body corners (all four), End-tip corners (LT LB RT RB) | POOL asks exactly those two: `bodycorners`, `endcorners` | POOL asks all eight individually, so each row **fans out** to its four -- body to `cornera…cornerd`, end-tip to `cornerlt cornerlb cornerrt cornerrb` -- carrying one treatment and one size to each |
| `L` | Outer corners (all five), Reverse corner E | `outercorners`, `innercorner` | the same two |

**The gate travels with them.** On the L, Lazy L, Grecian, GRSquare,
Octagon and Roman flows POOL puts a yes/no in front of the corner
questions -- *"Anything to record about the corners (radius / cut / not
given)?"* -- and answers No by default. So picking any corner row on
one of those sheets sends `(crec . "Yes")` automatically; the
treatments would be read by nothing otherwise. Leave every row on
`(ask)` and nothing is sent and POOL asks the gate as it always did.
The rectangle and the oval have no such gate and never get one.

Anything a sheet carries that has no place on the plan view gets a box
and no letter: the depths `C` and `D` (read off a section), the radii
`R1 R2 R3`, the check dimensions `S2`, `X` and the oval's `T`, the
out-of-square second overalls, the Sport chain, and Roman's right-hand
`S`/`S1`/`V` for when the two ends are not identical. Those boxes pack
**two to a row** wherever the pair of labels still fits across -- a
sheet with a dozen of them stacked one per row makes a dialog taller
than the screen, and a DCL dialog taller than the screen does not open
at all. Below them: the in-square toggle, the bottom type, and any
keyword question the sheet carries (the L's `mirror`).

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

Everything else the sheet needs is a row in a table beside it, keyed by
the chart's name, so a new shape never means new code:

| Table | What it carries |
| --- | --- |
| `lzf:*cuts*` | the heights where the drawing is cut for a wedge row |
| `lzf:*cross*` | the cross dims / diagonals, as `(key label)` |
| `lzf:*picks*` | the keyword dropdowns, as `(key label section (choice …))` -- section `"cross"` ties it to the cross dims, `"run"` puts it with the toggle |
| `lzf:*corners*` | the corner rows, as `(stem label (in-square stem …) (out-of-square stem …))` |
| `lzf:*crosslive*` | how many cross boxes each mode word maps |
| `lzf:*crecharts*` | the shapes whose corner questions sit behind a yes/no gate |
| `lzf:*nobtype*` | the shapes POOL asks no bottom type on |
| `lzf:*hints*` | a second line under the form, when a page has something of its own to explain |

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
  `lzf:*charts*`. The tables around it are ready for it: `LAzyl`
  already sits in `lzf:*nobtype*` and `lzf:*crecharts*`, so a chart
  added under that name inherits the greyed bottom popup and the
  corner gate without a line of code.
- The `Grecian` charts answer three questions on your behalf, because
  their letters only exist on one path through POOL: the perimeter
  input method (`Overall`), the hopper type, and -- on the six-sided
  chart -- that its corners were taped by `Letters`. Those are the
  chart's `gates`.
- A chart's letters assume the bottom type it was drawn for. `W`, `R3`
  and `L1` exist only on a Normal bottom; pick another and POOL asks a
  different set, so those boxes go unread.
- **Height is the failure mode to watch.** A DCL dialog taller than the
  screen does not open, and nothing in this file can measure a screen:
  DCL reports a tile's size only once the dialog is already up, which
  is too late to lay it out. That is why the column boxes pack two to a
  row (`lzf:*rowbudget*` caps how wide a pair may get before it takes
  two rows instead) and why a new section is weighed against the
  tallest page before it is added.
- The Grecian `Center` and `Complex` cross-dim modes are answered here
  and measured at the command line: 14 and 18 diagonals apiece is more
  than any sheet has room for. The dropdown still earns its place --
  answering the gate from the form is what keeps the rest of the sheet
  from being re-asked.
- The insertion base point is still picked at the command line.

## `LAZTXT` -- the pool drawn out of tiles, boxes inside it

The probe below killed *character* art, but it showed the half that
works, and `LAZTXT` is that half built out.

DCL has something better than dashes for an outline: a `boxed_row` or
`boxed_column` draws a **real etched border**. The widget draws it, so
it is straight by construction and cannot shear whatever the font is
doing. Nest one inside another and you have a pool with a hopper in
it; put the edit boxes inside those clusters and the fields are *in*
the drawing rather than beside it.

The Rectangle reads down the page the way the sheet does: `B` across
the top, then the pool body with `Overall` (`A`) on the left and the
`Hopper` (`M L K`) nested inside it, then the `H G F E` chain, then
the column-only fields. Insert hands POOL the same alist `LAZFORM`
sends -- it is the same form wearing different clothes, not a second
contract.

**What it buys:** every tile in it is *retained*. DCL does not retain
an `image` tile -- a repaint clears it and there is no expose callback
-- which is the standing hazard behind the chart having vanished on
people. Nothing in this view can vanish. The test asserts there is no
`image` tile in it at all.

**What it costs:** the outline is a rectangle whatever the pool is. A
boxed cluster cannot be round, cut-cornered or L-shaped, so this is a
schematic of *where the numbers sit*, not a picture of the pool. That
is why it is a second view rather than a replacement, and why it is
built for the Rectangle first.

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

### Section 5: the one question still open

Sections 1-4 tested `text` tiles, and a text tile is proportional. A
**`list_box` is a different control**, and if it happens to be
fixed-pitch the pool can be drawn in characters after all. So section 5
puts the same twelve-character ruler in a list box, and under it the
pool exactly as it is drawn on paper -- outline, hopper, the four
slopes, and the `H G F E` chain reading straight through the middle.

If those bars line up, that picture is buildable: retained like any
control, never wiped by a repaint, and the *real shape* rather than the
rectangle `LAZTXT` has to stand in with. The cost would be that a list
box holds text and nothing else, so the fields would sit beside the
drawing rather than in it -- the opposite trade from `LAZTXT`.

If they do not line up, that is the end of it, and the vector chart
stays the only way to see the pool.

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
after. The end-to-end cases fill the chart in, press Insert, and assert
the pool it draws is identical -- entity for entity -- to the one POOL
draws when the same answers are typed at the prompts: an out-of-square
rectangle with its cross dims off the sheet, a Sport rectangle with its
whole E2-F2-G-F1-E1-M-L-K chain off the sheet, and a Grecian's two
collective corner rows both in square and fanned out to the eight
corners POOL asks for out of it.

Two audits keep the form honest about POOL rather than about itself:

- **Every chart key is a key POOL asks for**, read off `POOL.LSP`'s own
  item lists. The cross-dim keys are *built* at run time -- `(read
  (strcat "x" (itoa k)))` walking `pool:crosstemplate` or
  `pool:grecmode` -- so the audit extracts that construction and reads
  the templates for how far `k` counts, rather than whitelisting the
  strings. Corner rows are checked the same way, against
  `pool:fckey`'s own roster.
- **The greying and the sending are one decision.** For a table of page
  states -- chart, in-square, bottom type, cross-dim mode -- the set
  `lzf:dead` computes must equal the set `lzf:form` drops, exactly. A
  box greyed on screen whose contents travel anyway, or a live box
  quietly dropped, fails the suite.
