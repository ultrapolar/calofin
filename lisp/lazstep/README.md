# LAZSTEP -- say how many steps, then fill the drawing in (AutoLISP / AutoCAD 2018+)

## What it does

`LAZSTEP` is a two-page form for the three pool-step routines. Page one
asks which routine this is -- `CORNERSTP`, `HEMISTEP` or `NORMIESTEP` --
**how many steps**, and the handful of questions that routine asks once
for the whole run. Page two is **a drawing generated from that count**:
three steps draw three treads, eight draw eight, and every dimension the
count implies is on the picture with a box against it. Fill in what you
know, leave the rest blank, press **Insert**: the routine runs and asks
only for the gaps.

Nothing here is a stored picture. `lzt:chart` builds the chart from the
type and the number, and everything downstream -- the DCL, the band
cuts, the drawing engine, the answers -- reads it as data.

**Why the count is the interesting field.** At the command line the step
count is never a question: the tread loop repeats "Step N - step tread
&lt;Enter = done&gt;" until you press Enter, so the number of steps is
emergent and you find out what the sheet needs one prompt at a time. A
form has the number as a field, so the three stores give it a key of its
own -- `(steps . N)` -- and the loop stops itself after N steps instead
of waiting for an Enter nobody typed. That is what lets a form of N rows
drive a run of N steps.

## Page one, per type

Every type: the step count, `dims`, `profile` and `bead`.

| Type | Asked once |
| --- | --- |
| `CORNERSTP` | `direction` (Inside / Outside), `measure` (Middle / True), `treadmode` (Parallel / True / Equidistant), `outerwidth`, `bench` (Yes / No), `benchoffset`, `benchstep` |
| `HEMISTEP` | `wallwidth`, `crown`, `boundary` (Yes / No) |
| `NORMIESTEP` | `width` (one width for the whole run), `treat` (Square / Radius / Cut / NotGiven), `treat-sz`, `cutgiven` (Offset / Cut) |

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
| `treat-sz` | `treat` is `Radius` or `Cut` -- only a sized treatment takes a size |
| `cutgiven` | `treat` is `Cut` |
| every depth box | `profile` is not `No` -- a run with no side view asks no depths |

**`measure` and `treadmode` are always offered on a corner run.**
`CORNERSTP` asks them only when the selection turns up a corner diagonal
or fillet, which is a fact about the drawing and not about the form, so
they are offered and the hint says they are ignored on a plain corner.
An answer the live prompt does not list falls through to the prompt
anyway.

The count must be a **whole number from 1 to 8**. Anything else is
refused on page one with a message rather than opening a page for it.

## Page two: the drawing, built for the count

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

`NORMIESTEP`'s single `width` appears on **both** pages. It is one
answer shown twice: type it wherever you meet it first.

Changing the count on page one and coming back regenerates the drawing
for the new number and keeps what was typed for the steps that still
exist -- and what was typed for the ones that went away is still in the
store if you go back up again.

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
them there as always. `LAZSTEP` says so in the hint on both pages.

## Install & run

APPLOAD `LAZSTEP.lsp` **and** the step routines it fills in --
`lisp/cornerstp/CORNERSTP.lsp`, `HEMISTEP.lsp`, `NORMIESTEP.lsp` -- or
load `shared/LAZPASS.lsp`, which carries all four. With none of the
three in the session `LAZSTEP` says so plainly and names them, rather
than opening a form whose Insert button could only fail; with only some
of them loaded it opens on one that is there and greys the tabs for the
ones that are not. `LAZSTEPVER` prints the loaded version.

## Tunables

| Global | Default | What it sets |
| --- | --- | --- |
| `lzt:*max-steps*` | `8` | the step-count ceiling |
| `lzt:*one-row*` | `4` | treads that fit one row of boxes before the chain staggers onto two |
| `lzt:*chart-w*` / `lzt:*chart-h*` | `58` / `20` | the chart column, in character cells |
| `lzt:*wedge-ed*` | `5` | a tread box's `edit_width` |
| `lzt:*col-line*` ... `lzt:*col-hi*` | `-16 -15 8 30 5` | outline, background, dimension, typed value, focus ring |

## The state lines

One on each page, and each holds its own button back.

**Page one** has boxes with two different readers, which is what makes
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
3 steps - Next builds the drawing to fill in.
```

`Next >` is greyed for all but the last. The count's two refusals are
the ones `lzt:count-ok` has always printed to the command line; they are
on the page now, live, while the number is being typed -- **and
`lzt:countwhy` is the one function both read**, so the live warning and
the refusal at the gate cannot come to different conclusions.

**Page two** is the hand-off, named by the letters the drawing shows:

```
Nothing filled yet - CORNERSTP will ask for all 10 boxes, plus the picks.
1 of 10 boxes filled - CORNERSTP will ask for T2, T3, W1 and 6 more, plus the picks.
T2 is not a measurement - type a number, or NA, or clear it.
All 10 boxes filled - CORNERSTP will ask only for the picks in the drawing.
```

Both pages count only what is live: a question `lzt:skip` names is not
asked at all, so rubbish in one is neither complained about nor counted.
The test partitions every live box into sent, still-to-ask and
unreadable and fails if any lands in two groups or in none, so a line
and the alist it describes cannot drift apart.

## Notes & limitations

- **DCL height is the hard failure mode.** A dialog taller than the
  screen does not open at all, and nothing here can measure a screen. N
  rows of boxes grow page two linearly, so the count is capped at
  **eight** and the depth boxes are packed **two to a row**. A larger
  number is refused with a message on page one. Nine steps or more is a
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
- The DCL file is **rewritten every time a page is opened**, unlike
  `LAZFORM`'s, because page two depends on the count -- N rows of boxes
  cannot be a static dialog. It is written to the temp folder and
  deleted when the page closes, so there is still nothing to install.
- DCL has no tab tile. A tab and the Back button are ordinary buttons
  that close the page and reopen the next, so the dialog blinks as it
  switches. `done_dialog` reports where it was standing and `new_dialog`
  takes a position back, so it reopens in the same spot -- the blink is
  unavoidable, the wandering is not.
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
