# LAZSTEP -- type the step count and the drawing follows it (AutoLISP / AutoCAD 2018+)

## What it does

`LAZSTEP` is a **one-page** form for the three pool-step routines. The
drawing stands on the left and everything asked about it in the column
beside it: which routine this is -- `CORNERSTP`, `HEMISTEP` or
`NORMIESTEP` -- **how many steps**, the handful of questions that
routine asks once for the whole run, and a box against every dimension
the count implies. Fill in what you know, leave the rest blank, press
**Insert**: the routine runs and asks only for the gaps.

**Type the count and the picture follows it.** Three steps draw three
treads, eight draw eight, and the boxes come with them: put 5 in the
count and there are five tread boxes, five width boxes and six depth
boxes to fill in, no more and no fewer. Until a count is given the
picture is a **nominal** one (`lzt:*steps-nominal*`) and every dimension
box on it is greyed, because a box that has no step to belong to is not
a box anybody should be typing into.

Nothing here is a stored picture. `lzt:chart` builds the chart from the
type and the number, and everything downstream -- the DCL, the band
cuts, the drawing engine, the answers -- reads it as data.

**It used to be two pages**, the count on the first and the drawing on
the second, so the picture the count describes was the one thing you
could not see while typing it, and changing a 5 to a 6 meant Back,
retype, Next. DCL cannot add a tile to a dialog that is already up, so
a new count still closes the page and reopens it; what changed is that
it reopens as *itself*, in the same place, with everything typed still
in it -- so the count reads as a field that redraws rather than as a
page boundary. A count that matches the drawing already on screen
rebuilds nothing at all and simply brings its boxes alive.

**Why the count is the interesting field.** At the command line the step
count is never a question: the tread loop repeats "Step N - step tread
&lt;Enter = done&gt;" until you press Enter, so the number of steps is
emergent and you find out what the sheet needs one prompt at a time. A
form has the number as a field, so the three stores give it a key of its
own -- `(steps . N)` -- and the loop stops itself after N steps instead
of waiting for an Enter nobody typed. That is what lets a form of N rows
drive a run of N steps.

## The run block, per type

Every type: the step count, `dims`, `profile`, and the **three beading
questions** -- `bead` (beading required at all), `beadsides` (All /
Some / None along the step side walls) and `beadnums` (the step numbers
`Some` asks for, typed as `1 3 5`). Beading was one form-answerable
question followed by two live prompts *after* the drawing was finished;
all three come off the sheet now. The side to bead **toward** stays a
pick in the drawing.

| Type | Asked once |
| --- | --- |
| `CORNERSTP` | `direction` (Inside / Outside), `measure` (Middle / True), `treadmode` (Parallel / True / Equidistant), `outerwidth`, `bench` (Yes / No), `benchoffset`, `benchstep` |
| `HEMISTEP` | `wallwidth`, `crown`, `boundary` (Yes / No) |
| `NORMIESTEP` | `treat` (Square / Radius / Cut / NotGiven), `treat-sz`, `cutgiven` (Offset / Cut). Its one `width` is a dimension on the drawing -- the letter `W` -- so the drawing carries its box |

A dropdown's first entry is `(ask)` -- the form's version of an empty
box, and the only honest default, since every one of these prompts
offers a keyboard default of its own.

**What is greyed, and why.** A question a run will never reach is
greyed, and a greyed answer does not travel: a number sitting in the
store unread is harder to reason about than one that was never sent.

| Greyed | Unless |
| --- | --- |
| `outerwidth` | `direction` is `Outside` -- only outside in places the outermost step by width |
| `bench`, `benchoffset`, `benchstep` | `direction` is not `Outside` -- a bench is an inside-out feature |
| `benchoffset`, `benchstep` | `bench` is `Yes` |
| `measure` | `direction` is not `Outside` |
| `beadsides`, `beadnums` | `bead` is `No` -- nothing is asked about side walls on a run that is not being beaded |
| `beadnums` | `beadsides` is `Some` |
| `treat-sz` | `treat` is `Radius` or `Cut` -- only a sized treatment takes a size |
| `cutgiven` | `treat` is `Cut` |
| every depth box | `profile` is not `No` -- a run with no side view asks no depths |
| **every dimension box** | a step count has been given -- until one is, the picture is nominal and nothing on it is a question this run will reach |

**`measure` and `treadmode` are always offered on a corner run.**
`CORNERSTP` asks them only when the selection turns up a corner diagonal
or fillet, which is a fact about the drawing and not about the form, so
they are offered and the hint says they are ignored on a plain corner.
An answer the live prompt does not list falls through to the prompt
anyway.

The count must be a **whole number from 1 to 8**. Anything else leaves
the drawing where it was, says why on the line under the picture, and
greys `Insert` -- it never builds a page for a number that might not
fit on the screen.

## The drawing, built for the count

The plan view on top, the side profile below it, one per-mille
coordinate space and one drawing engine.

| Type | Plan | Keyed |
| --- | --- | --- |
| `CORNERSTP` | two walls meeting at a corner with N tread lines fanning out of it; tread I dimensioned along the bisector | `tread1..treadN`, `width1..widthN` |
| `HEMISTEP` | a curve with N chords across it; tread I between chord I-1 and chord I | `tread1..treadN`, `width1..widthN` |
| `NORMIESTEP` | a straight run of N constant-width treads; **one** width for the whole run | `tread1..treadN`, `width` |

The **side profile** is drawn for all three, because all three draw it
the same way: the flight in elevation reading down and to the left from
the picked top of the first tread, N risers and N treads, with **N+1
depth dimensions** -- `depth1..depthN` against each drop and
`depthafter` against the drop after the last tread. That chain is the
part that is hardest to hold in your head at the command line, and it is
exactly what the routines ask for.

Every dimension carries its **letter** -- `T1`, `W1`, `D1`, `DA` --
until a number is typed against it, and then the number replaces the
letter on the picture, which is what the letter was standing in for all
along.

`NORMIESTEP`'s single `width` is a dimension on the drawing -- the
letter `W`, standing off the run it measures -- and its box is in the
column with the rest. It used to appear on both pages, because the count
and the drawing were separate and you could meet either first; on one
page that is two tiles with one key, which is not a dialog DCL will
open.

Changing the count regenerates the drawing for the new number and keeps
what was typed for the steps that still exist -- and what was typed for
the ones that went away is still in the store if the number goes back
up.

## What travels, and what does not

| In a box | On the wire | What the routine does |
| --- | --- | --- |
| left empty | the key is not sent | asks the question as usual |
| `NA` | `(key . nil)` | takes what Enter means there |
| `2'6"` or `24` | `(key . 24.0)` | takes the measurement, no prompt |

`NA` means **fit to the walls** or **fit to the curve** in a step width,
**none** in `wallwidth` and `crown`, and **the same as the drop above**
in a depth. A typo counts as an empty box on purpose: something that is
neither `NA` nor a distance AutoCAD can read leaves the routine asking
rather than quietly feeding it a nil that means something else entirely.
A dropdown left on `(ask)` sends nothing at all.

**A tread is the one exception.** `nil` at a tread prompt is what *ends*
the run, so an `NA` tread would stop the flight short of the very count
the drawing was built for. `NA` in a tread box counts as an empty box
instead.

**The selections and the point picks never come off the form.** The two
walls, the curve or base line, the side to draw toward, the side
profile's top-of-tread pick and the bead direction all stay in the
drawing, where your own snaps are live -- the three routines ask for
them there as always. `LAZSTEP` says so in the hint under the picture.

## Install & run

APPLOAD `LAZSTEP.lsp` **and** the step routines it fills in --
`lisp/cornerstp/CORNERSTP.lsp`, `HEMISTEP.lsp`, `NORMIESTEP.lsp` -- or
load `shared/LAZPASS.lsp`, which carries all four. With none of the
three in the session `LAZSTEP` says so plainly and names them, rather
than opening a form whose Insert button could only fail; with only some
of them loaded it opens on one that is there and greys the tabs for the
ones that are not. `LAZSTEPVER` prints the loaded version.

## Tunables

Every one is a plain literal in the **tunables block at the top of
`LAZSTEP.lsp`**. The frame numbers are in PER-MILLE of the picture, x
and y with y down -- an image tile's own convention, so the only
conversion at draw time is a multiply.

**The VB palette's step sheets are generated from `lzt:chart` for every
count up to the ceiling**, so a change to any frame number below is a
`python3 tools/gen_ui_charts.py` away from being carried there too.

**Not tunable here, deliberately:** the stroke font and the image
tile's colours -- the grouped build takes `CALOFIN-LIB.lsp`'s instead.

| Global | Default | What it sets |
| --- | --- | --- |
| `lzt:*plan-x0*` | `100` | the wall, or the corner -- where the plan starts |
| `lzt:*plan-x1*` | `860` | the far end of the run |
| `lzt:*plan-yc*` | `180` | the run's centre line |
| `lzt:*plan-hh*` | `120` | half the plan's opening at the far end |
| `lzt:*width-x*` | `930` | where a whole-run width dimension stands |
| `lzt:*chord-x1*` | `860` | the last chord across a hemi curve |
| `lzt:*curve-rx*` | `840` | ...whose crown sits beyond it, at `x0 +` this |
| `lzt:*tread-y0*` | `385` | the tread dimension row |
| `lzt:*tread-y1*` | `445` | ...and the second one, when the count needs it |
| `lzt:*one-row*` | `4` | treads that fit one row of boxes before the chain staggers onto two |
| `lzt:*prof-x*` | `860` | top of the flight, x, in the side profile |
| `lzt:*prof-y*` | `540` | and its y -- the profile hangs from here |
| `lzt:*prof-w*` | `760` | the flight's whole run... |
| `lzt:*prof-h*` | `450` | ...and its whole drop |
| `lzt:*prof-gap*` | `40` | how far a depth dimension stands off its step |
| `lzt:*max-steps*` | `8` | the step-count ceiling. DCL will not scroll and a dialog taller than the screen does not open at all; eight fits a laptop, nine does not reliably. **The VB palette offers exactly the counts a sheet was generated for, up to this number** |
| `lzt:*steps-nominal*` | `3` | what the picture shows before a count is typed. The box opens empty -- the form invents no answers and `steps` is one that travels -- but a page with no drawing on it is a page with nothing to read, so the nominal chart stands in with every box on it greyed |
| `lzt:*colbudget*` | `34` | how tall the answer column may get, in lines of generated DCL, before it splits in two. The page is as tall as its longest column; tune it against `tools/check_dcl.py` |
| `lzt:*hint-w*` | `96` | how wide the hint and the two state lines are, in character cells. Wider than the boxes they sit under, because a sentence that does not fit on one line is another row of the page's height |
| `lzt:*chart-w*` | `58` | the chart column's width, in character cells |
| `lzt:*chart-h*` | `20` | its total height in rows, spread over the bands |
| `lzt:*wedge-ed*` | `5` | a tread box's `edit_width` where it is wedged into the drawing |
| `lzt:*poskey*` | `"LazStep_Pos"` | where the dialog remembers its position between restarts (the AutoCAD profile) |
| `lzt:*recallkey*` | `"HKEY_CURRENT_USER\\Software\\Calofin\\LazStep"` | where a sheet's last accepted answers are kept for Recall -- one value per routine AND count (`CORNERSTP-3`), because a three-step sheet recalled onto a five-step drawing would put numbers against treads they were never measured on. **The VB palette reads the same key and slot** |

## The state lines

Two of them, stacked under the picture, and **`Insert` is held back by
either**: a page with one button cannot have two opinions about it.

**The run line** has boxes with two different readers, which is what makes
it worth saying out loud: a measurement goes through `lzt:answer`, and
the step count and the bench step through `lzt:int`. `3.5` is the case
that separates them -- a perfectly good measurement, and not a step
number at all -- so `lzt:answer` would take it and `lzt:int` is what
actually reads it.

```
How many steps?  A whole number from 1 to 8, please.
8 steps is the ceiling - a taller dialog will not open.  Run the rest by hand.
Bench ends on step number: "3.5" is not a whole number.
Bench offset off the wall: "wide" is not a measurement.
3 steps - the drawing and its boxes are built for that many.
```

`Insert` is greyed for all but the last. The count's two refusals are
the ones `lzt:count-ok` has always printed to the command line; they are
on the page now, live, while the number is being typed -- **and
`lzt:countwhy` is the one function all three readers use** (the live
warning, the redraw and the refusal at the gate), so they cannot come
to different conclusions.

**The hand-off line** is named by the letters the drawing shows:

```
Type a step count and the boxes come alive - one per tread, one per width, one per drop.
Nothing filled yet - CORNERSTP will ask for all 10 boxes, plus the picks.
1 of 10 boxes filled - CORNERSTP will ask for T2, T3, W1 and 6 more, plus the picks.
T2 is not a measurement - type a number, or NA, or clear it.
All 10 boxes filled - CORNERSTP will ask only for the picks in the drawing.
```

Both lines count only what is live: a question `lzt:skip` names is not
asked at all, so rubbish in one is neither complained about nor counted.
The test partitions every live box into sent, still-to-ask and
unreadable and fails if any lands in two groups or in none, so a line
and the alist it describes cannot drift apart.

## Recall last, and what a box takes

Two small things the form used to leave you to work out.

**`Recall last`** puts the answers from the last accepted sheet for
*this chart* back into the boxes. A sheet you have just drawn is very
often the shape of the next one -- the same pool from a different
survey, or the same one corrected -- and re-typing fourteen numbers to
change two is the kind of work a form is supposed to remove.

It fills the **empty** boxes only. That is what makes it safe to press:
it can never overwrite a number you have just typed, and pressing it
twice does nothing the first press did not.

It is a **button and never a default**. Pre-filling a sheet on open
would put the last pool's numbers on this pool, and a wrong number that
looks answered is worse than an empty box -- the state line would call
the sheet finished and the routine would never ask. When this chart has
nothing stored the button is simply greyed, which is the whole of the
"nothing happened" case: no message needed, and when it does fill, the
state line moves on its own to say how much.

A sheet is stored as one string, `key=typed;key=typed`, under its own
value name in the registry. A value carrying `;` or `=` would read back
as two pairs or the wrong pair, so it is **dropped rather than
written** -- nothing a box legitimately holds contains either, so this
guards the impossible; losing one entry beats a whole sheet that reads
back scrambled.

**What a box takes** is now on the form: *"A box takes 24, or a
feet-and-inches spelling - both read."* `distof` has always read the
architectural spellings and nothing on screen said so, which left a
drafter with a tape in feet and inches guessing. The inch mark is
spelled rather than shown on purpose -- a bare `"` would end the DCL
string it sits in, and these files write their own `.dcl`.


`LAZSTEP`'s slot carries the **count**: `CORNERSTP-3`, not `CORNERSTP`.
A drawing is built for N steps, so a three-step sheet coming back on a
five-step one would put numbers against treads they were never measured
on.

## Notes & limitations

- **DCL height is the hard failure mode.** A dialog taller than the
  screen does not open at all, and nothing here can measure a screen. N
  rows of boxes grow the page linearly, so the count is capped at
  **eight**, the depth boxes are packed **two to a row**, and the answer
  column **splits in two** once it is taller than `lzt:*colbudget*` --
  the page is as tall as its longest column. A larger number is refused
  with a message on the line under the picture. Nine steps or more is a
  run for the command line.
- **The tread chain staggers past four steps.** A tread box is its
  letter plus nine cells, so eight of them on one line run about 96
  character cells against a chart of 58 -- and DCL will not scroll a
  dialog wider than the screen. Past four treads the chain is drawn on
  two levels, odd steps on the upper row and even on the lower, the way
  a tight dimension chain is drawn on paper.
- **The drawing is redrawn every time a box is left**, because a DCL
  image tile is not retained by AutoCAD: any repaint clears it to its
  own colour attribute and there is no expose callback to draw it again.
  For the same reason the chart is a passive `image` tile and must stay
  one -- an `image_button` repaints on mouse-enter and mouse-leave, so
  the picture would vanish the first time the cursor crossed it.
- **The boxes cannot sit on the picture, so the picture is cut around
  them.** DCL packs tiles into rows and columns: no absolute
  positioning, no overlapping, no z-order. The chart is cut into bands
  at the heights where its horizontal dimension rows run and those rows
  are real edit boxes wedged between the bands, pushed to their letters'
  positions by spacers. Positions are in character cells, so a box lands
  within a cell or so of its letter. The widths and the depths run the
  other way and a box cannot stand sideways in a row, so they keep boxes
  in the side column and their values are drawn onto the chart in the
  letter's place.
- **A tread box holds five characters.** `24` and `2'6"` fit; a long
  architectural spelling scrolls inside the box. The side-column boxes
  are wider.
- The DCL file is **rewritten every time the page is opened**, unlike
  `LAZFORM`'s, because it depends on the count -- N rows of boxes cannot
  be a static dialog. It is written to the temp folder and deleted when
  the page closes, so there is still nothing to install.
- DCL has no tab tile. A tab is an ordinary button that closes the page
  and reopens the next, and a **count that moves** does the same, so the
  dialog blinks as it rebuilds. `done_dialog` reports where it was
  standing and `new_dialog` takes a position back, so it reopens in the
  same spot -- the blink is unavoidable, the wandering is not. A count
  that matches the drawing already on screen does not rebuild at all.
- An edit box reports its value when the caret **leaves** it, so the
  picture updates on Tab or on a click elsewhere, not per keystroke.
- The plan view is a schematic of where the numbers go, not a survey of
  your pool: the fan opens at a fixed angle and the curve is a fixed
  half-ellipse whatever the real geometry is. The numbers you type are
  what the routine uses.
- `bead` is offered on all three, but the routines only ask about
  beading when `AUTOBEAD` is loaded; without it the answer goes unread.

## Tests

```
python3 tests/test_lazstep.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lazstep.py # grouped tier
```

The chart is checked at **every count from 1 to 8**: keys unique,
coordinates in bounds, dimensions axis-consistent and labelled, exactly
N treads and N+1 depths, and every cut landing on a real dimension row.
Every key the form can send is grepped out of `CORNERSTP.lsp`,
`HEMISTEP.lsp` and `NORMIESTEP.lsp`, so a key nothing reads fails the
suite rather than being typed into and dropped. The drawing is captured
and checked rather than assumed -- every vector inside the tile, in a
colour the file declares -- and the end-to-end cases fill the form in
for a three-step run of each type, press Insert, and assert the geometry
is identical entity for entity to the same run answered at the prompts,
with no tread or depth prompt shown at all.
