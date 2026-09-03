# LAZSPA -- fill a spa dimension chart in, then draw the spa (AutoLISP / AutoCAD 2018+)

## What it does

What `LAZFORM` is to `POOL`, `LAZSPA` is to `SPA`. `SPA` grew an answer
store -- `spa:*form*`, `spa:run-with-answers`, and the hooks in its ask
helpers (see `lisp/spa/README.md`, "Form answers") -- and until now
nothing in AutoCAD could drive it: the VB palette in `ui/` needs a DLL
`NETLOAD`ed on every machine. `LAZSPA` is the **zero-install** way in.
The dialog is plain DCL written to the temp folder at run time and the
chart is drawn with `vector_image`, so there is no artwork file to ship
and nothing to install.

The chart on screen is the one off the order sheet. Type a number
against a letter and **the letter is replaced by what you typed** --
which is what the letter was standing in for all along. Fill in what
you know, leave the rest blank, press **Insert**: `SPA` runs and asks
only for the gaps.

| In a box | On the wire | What SPA does |
| --- | --- | --- |
| left empty | the key is not sent | asks the question as usual |
| `NA` | `(key . nil)` | takes NA, no prompt |
| `84` or `6'10"` | `(key . 84.0)` | takes the measurement, no prompt |
| a dropdown on `(ask)` | the key is not sent | asks the question as usual |

A typo counts as an empty box on purpose: something that is neither `NA`
nor a distance AutoCAD can read leaves SPA asking, rather than quietly
feeding it a nil that means something else entirely.

**`NA` only travels where SPA has an `NA` to take.** Its measurement
sequences mark each item `REQ` / `SUG` / `NAX`, and `spa:askseqb` stores
a form's nil straight into its answers without validating it -- so a
nil against a `REQ` item (`w`, `b`, `w2`, `b2`) becomes arithmetic on
nil further down the flow, which in AutoLISP is an error and not a
fallback. An `NA` typed against one of those is therefore demoted to an
**empty box**: nothing is sent and SPA asks, which is the same fail-safe
direction a typo takes. `lzs:*naok*` is the per-chart list of keys where
`NA` really is an answer.

## The three charts

A **tab strip** across the top switches them. The keys are SPA's own,
and `tests/test_lazspa.py` checks every one of them against `SPA.LSP`
itself, so a letter pointed at the wrong key fails the suite rather
than silently swallowing what you type.

| Chart | SPA shape | Letters on the picture | Keys |
| --- | --- | --- | --- |
| `Rectangle` | `Rectangle` | W across, L up (corners marked A B C D) | `w` `l` |
| `OCtagon` | `OCtagon` | B S T across, A S1 V up (S2 in the list) | `b` `a` `s2` `tt` `ss` `s1` `vv` |
| `ROund` | `ROund` | B across, A up | `b` `a` |

Watch the spellings: SPA's shape words are `Rectangle`, `OCtagon` and
**`ROund`** -- *not* POOL's `ROUnd`. The wrong one falls through
`spa:fshape`'s member check and, typed by hand, would fall through
`c:SPA`'s dispatch into the rectangle branch and draw the wrong spa
without saying so.

**Rectangle.** SPA's header names its corners *A bottom-left, B
bottom-right, C top-right, D top-left*, and its two overalls are named
for them -- `W` runs A-B across the bottom and `L` runs A-D up the left
end. So `W` is drawn *under* the shape, on the side it is actually
taped, and the four corner letters are marked on the picture, because
the Corners rows below are named after them.

**Octagon.** The letters have to **close** against the overalls, since
`spa:octov` resolves them that way: `S + T + S = B` and
`S1 + V + S1 = A`. The drawing is built to those sums and the test
re-checks them, so a picture that lies about the measurement it names
fails the suite instead of misleading whoever reads it off. `S2`
measures the cut **face**, which runs diagonally; a dimension on this
chart is `h` or `v` and nothing else, so `S2` gets a box in the list and
nothing on the picture -- exactly what LAZFORM's grecian charts do with
their own `S2`, for the same reason.

**Round.** SPA asks **one** question here -- *Overall diameter
[Outofround]* -- and only takes two axes when the answer is the keyword.
`spa:roundflow` reads the store like this:

```lisp
(setq bov (cond ((spa:fhas 'a) "Outofround")
                ((and (spa:fhas 'b) (numberp ...)) bov)   ; the diameter
                (t (spa:askd "Overall diameter" "Outofround" nil nil))))
```

So `A` is only *peeked* at, and its mere **presence** takes the
out-of-round branch; `B` alone is the diameter. That is why the box says
"only if out of round", why the page hint says filling it in makes the
spa out of round, and why an `NA` there is treated as an empty box: an
`NA` would open the out-of-round branch to say nothing at all.

## What every page carries

**Mode**, at the top on its own: `(ask)` / `Watersedge` / `Coversize`,
key `mode`. It is SPA's opening question and it settles the layer, the
linetype and the dimension style everything below is drawn in.

**Corners**, on the Rectangle page only -- SPA asks corner treatments
for no other shape. Four rows A..D, a dropdown of
`(ask)` / `90` / `Radius` / `Diagonal` under `cornera-ty` …
`cornerd-ty`, each with a size box (`cornera-sz` …) that stays greyed
until a sized treatment is picked. A sized treatment with the size left
empty sends the treatment alone and SPA asks for just the number; a size
too big for its walls is rejected by SPA's own cap check and retyped at
the keyboard, because the store has already been consumed.

> **The vocabulary is SPA's, not POOL's.** `90` / `Radius` / `Diagonal`
> are the words on the order sheet's corner legend and in
> `spa:askcorner`'s `initget`. STANDARDS.md 8.1 renames POOL's set to
> `Square / Radius / Cut / NotGiven`, but that is separate, tracked work
> and **SPA has not had it**. A form speaking POOL's words here would
> have every corner answer consumed and thrown away by `spa:askcorner`'s
> member check, and every corner asked at the keyboard as if the box had
> been left empty. (`Square` SPA does accept, as a synonym it normalises
> to `90`; the dropdown offers `90` because that is what the sheet says.)

**The other outline**: `second` (`(ask)`/`Yes`/`No`), `method`
(`(ask)`/`Offset`/`Dims`), `gap` (a box -- how far the cover laps the
water's edge), and the by-dims second overalls, which are keyed **per
shape**:

| Chart | Second overalls |
| --- | --- |
| `Rectangle` | `w2` `l2` |
| `OCtagon` | `b2` `a2` `f2` (the cut face) |
| `ROund` | `b2` `a2` |

**Hinges and cover details**: `autohinge` (`(ask)`/`Yes`/`No`), `grade`
(`(ask)`/`STANDARD`/`THERMOLIGHT`), `taper` (`(ask)` plus `3-2`, `4-2`,
`4-3`, `5-3`, `5-4`, `3-3`, `1-3/8`).

## What the answers grey out

A page offers every question SPA *could* ask, and some of them stop
being questions the moment another one is answered. `lzs:dead` names
those, they are greyed on the live dialog, and **a greyed key is never
sent** -- a form that quietly carries dead answers is harder to reason
about than one that does not.

| Answered | Greyed, and not sent | Because |
| --- | --- | --- |
| `method` = `Dims` | `gap` | the lap is not asked when the outline is measured |
| `method` = `Offset` | the second overalls | they are not asked when it is offset |
| `second` = `No` | `method`, `gap`, the second overalls | `spa:askother2` stops at the Yes/No |
| `grade` = `THERMOLIGHT` | `mode`, `second`, `method`, `gap`, the second overalls, `taper` | see below |
| nothing yet | nothing | `(ask)` settles nothing, so every box stays live |

**Thermo-Light is the big one.** Its water's edge and its cover size are
the *same thing*, so `c:SPA` sets the mode itself (`Coversize`),
`spa:askother` declines to offer the second outline at all, and
`spa:askdetails` forces the taper to `1-3/8`. Mode, the whole cover
block and the taper are therefore dead. **Auto-hinge survives it**: a
Thermo-Light cover is still hinged, only in velcro throughout.

## Install & run

APPLOAD `LAZSPA.lsp` **and** `lisp/spa/SPA.LSP`, or load
`shared/LAZPASS.lsp`, which carries both. `LAZSPA` says so plainly if
SPA is not in the session rather than opening a form whose Insert button
could only fail. `LAZSPAVER` prints the loaded version.

`LAZSPA` also has a button on the LazPanel's **Spa** job page (right
after `SPA`) and on the **Layout** category page.

## Assumptions

- SPA is loaded, and its answer store (`spa:*form*`,
  `spa:run-with-answers`) is the receiving end -- see `lisp/spa/`.
- The system temp folder is writable; the dialog is written there at run
  time and deleted when it closes.
- The chart's keys are SPA's keys. `tests/test_lazspa.py` reads them off
  `SPA.LSP` -- the `askseqb` item lists, the `spa:askkwf` / `spa:askdf` /
  `spa:fhas` call sites, and the corner stems `spa:fckey` builds -- so a
  key SPA does not ask for fails the suite instead of being typed into
  and dropped.

## The state line

Under the form, above `Insert`, one line that says what the sheet is
about to do -- LAZFORM's, with a third thing to say, because **SPA has
two ways of dropping a box unread**:

| | |
| --- | --- |
| `lzs:answer` | anything that is neither `NA` nor a distance becomes *not answered* |
| `lzs:keyanswer` | an `NA` on any key SPA has no NA for is **demoted** to the same thing |

The second is the sharper one: `NA` is a word this very form tells you
to type, and on the wrong box it means nothing at all. Either way the
chart went on showing what was typed -- the chart draws the **string**
-- so the box looked answered and SPA asked for it again with no reason
given.

```
W is not a measurement - type a number, or NA, or clear it.
W cannot be NA - SPA needs a number there.
W and W2 cannot be NA - SPA needs a number in each of them.
```

**`Insert` is greyed for both**, and released the moment either is
fixed. With neither there, the line is the hand-off:

```
Nothing filled yet - SPA will ask for all 5 boxes, plus the base point.
2 of 5 boxes filled - SPA will ask for W2, L2 and the cover lap, plus the base point.
All 5 boxes filled - SPA will ask only for the base point and the block.
```

`lzs:naok` is the authority on where `NA` is a real answer, and it is
the same table SPA's own demotion reads. Both halves count
`lzs:livekeys`, the boxes that are not greyed -- rubbish in a greyed box
is neither complained about nor counted. The test partitions every live
box into sent, still-to-ask, unreadable and NA-demoted and fails if any
lands in two groups or in none, so the line and the alist cannot drift.

## Notes & limitations

- **Two prompts stay at the command line, by design**, and the form says
  so on its own face: the **Spa Cover Details block pick** (an `entsel`
  in the drawing -- the block is *in* the drawing, there is nothing for
  a form to type) and the **spillaway loop**. The insertion base point
  is picked in the drawing too, with the user's own snaps live, so
  `base` is never sent.
- DCL dialogs are modal and not resizable. The form closes when you
  press Insert and SPA takes over at the command line.
- An edit box reports its value when the caret **leaves** it, so the
  picture updates on Tab or on a click elsewhere, not per keystroke.
- The picture is read, not clicked -- see below.
- DCL has no tab tile. A tab is a button that closes the page and
  reopens the next, so the dialog blinks as it switches. `done_dialog`
  reports where the dialog was standing and `new_dialog` takes a
  position back, so it reopens in the same spot -- the blink is
  unavoidable, the wandering is not. Everything typed is keyed, so it
  survives the switch and is still there if you tab back.
- The stroke font and the drawing code are the same idea as LAZFORM's,
  deliberately duplicated: only `CALOFIN-LIB.lsp` may define `cal:`
  symbols, and a shared tool may not define a top-level name another
  shared file defines -- so borrowing `lzf:` names would make LAZSPA
  depend on LAZFORM being loaded, which it never is at the standalone
  tier. Every symbol here is `lzs:`.

## Why the boxes are beside and inside the picture, never on it

DCL packs tiles into rows and columns. There is no absolute positioning,
no overlapping and no z-order, so an edit box cannot sit on an image
tile -- and DCL cannot show a raster at all: an image tile takes vectors
or an AutoCAD slide, nothing else. Those two facts together rule out
"the artwork with text boxes on the letters", which is what the VB.NET
palette in `ui/` does and needs a DLL on every machine to do.

So the chart is **drawn** rather than loaded, and it is **cut into
horizontal bands** at the heights where its across dimensions run; those
rows are real edit boxes wedged between the bands, pushed to their
letters' positions by spacers. The dimensions that run *up* cannot be
wedged -- a box cannot stand sideways in a row -- so they keep boxes in
the side column, labelled with their letters, and what you type there is
drawn onto the chart in the letter's place. Clicking a letter button
puts the caret in that box, selects what is there so your first
keystroke replaces it, and rings that dimension on the drawing.

Positions in a wedge row are in character cells and a box has its own
minimum size, so this is honest about being approximate: a box lands
within a cell or so of its letter, and two that would collide get pushed
apart rather than overlapped. The test checks both ways -- no cut
without a dimension on it, and every wedge box near the letter it
replaces.

**The picture is passive and must stay passive.** It is an `image` tile,
never an `image_button`. A DCL image tile is **not retained** by
AutoCAD: any repaint clears it to its own `color` attribute and
everything the application drew into it is gone, and there is no expose
callback to draw it again. An `image_button` is repainted on mouse-enter
and mouse-leave, so the chart vanishes the first time the cursor crosses
it -- which is how LAZFORM lost its drawing before the button was taken
back out. The same rule is why every dropdown on this form repaints the
chart: a list unrolling over it does the same damage and nothing else
would repair it. The test asserts there is no `image_button` on any
page.

There is no text primitive in DCL either, so the letters and numbers are
stroked out of line segments from a small vector font in this file.

## Adding a shape

Adding a shape is adding data, not code: one entry in `lzs:*charts*`
with an outline, a dimension list and its SPA keys, plus a line in each
of the small tables under it (`lzs:*cuts*`, `lzs:*second*`,
`lzs:*naok*`, `lzs:*hints*`, and `lzs:*corners*` if SPA asks that shape
for corner treatments). Everything is in per-mille of the picture, x and
y, y running **down** -- the same convention an image tile uses, so
nothing is flipped at draw time, and the *bottom* of a spa is the
*larger* y.

```lisp
("Rectangle" "Rectangle" "Rectangle"
 ((150 250 850 250 850 820 150 820 150 250))     ; outline polylines / arcs
 (("W" "w" 150 920 850 920 "h" "W - overall WIDTH across (A-B)")
  ("L" "l"  75 250  75 820 "v" "L - overall LENGTH up (A-D)"))
 nil                                             ; column-only fields
 (("D" 105 210) ("C" 895 210)                    ; letters on the picture
  ("A" 105 860) ("B" 895 860)))
```

An outline element is a flat polyline `x y x y ...` or an arc written
`("A" cx cy rx ry from to)`, angles in degrees, 0 due east, counting
anticlockwise on screen. The arrow, the letter and the typed value all
come off a dimension's two endpoints, so there is no separate position
table that could fall out of step with the drawing.

## Tests

```
python3 tests/test_lazspa.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lazspa.py # grouped tier
```

The drawing is captured and checked rather than assumed: every vector
must land inside the tile in a colour the file declares, and the
value-replaces-letter rule is checked by counting strokes before and
after. The end-to-end cases fill each chart in, press Insert, and assert
the spa it draws is identical **entity for entity** to the one SPA draws
when the same answers are typed at its prompts -- rectangle, octagon,
round, and the out-of-round pair -- with the answered questions never
asked and only the block pick and the base point left over.
