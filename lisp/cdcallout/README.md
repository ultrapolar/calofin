# CDCALLOUT — cross-dimension Pt.## to Pt.## (AutoLISP)

`CDCALLOUT` is the dimensioning sister of `BPCALLOUT`. Instead of
clicking points, you **name** them: type the FROM point number and
the TO point number — and an aligned dimension is drawn between
those two survey points, the dimension line placed automatically
**right inbetween**, on the tie itself (CDCREATE's convention;
nudge `cdo:*offset*` to push it off). Nothing is ever clicked.

**Every tie is its own pair.** A drawn dimension returns to the FROM
prompt, so the next tie names both of its own points; **Enter** at the
TO prompt skips that one and re-asks FROM, **Enter** at the FROM
prompt finishes. Nothing carries over between runs.

v1.7 chained instead — the last TO point anchored the next tie, so a
run round the pool cost one number each, and the chain's end was
remembered for the session. That is not what cross dims are: they are
whichever two points the drafter wants tied, in whatever order the
sheet needs them, and guessing the next FROM was wrong more often than
it was convenient.

Every dimension lands the way `CDCREATE` and `POOL` make cross dims:

* dimension style **CROSS DIMENSIONS**,
* layer **DIMENSION** (created if the drawing lacks it),
* ByLayer — any per-entity colour / linetype / lineweight override is
  stripped.

The whole run is **one undo group**: a single `U` takes every
dimension away. (With UNDO switched off in the drawing no group is
opened — or closed — and the run still works.) The dimension style,
current layer, `OSMODE` and `CMDECHO` in force before the command are
restored afterwards — on a clean finish, an error, or Esc.

## Typing point numbers

Numbers are matched against the `number` attribute on the survey
point blocks: an `ab_pt` INSERT on any layer, or any other INSERT on
the **POINTS** layer. That is `BPCALLOUT`'s and `LHD`'s classifier
minus its third kind — a plain POINT entity carries no attribute, so
it has no number to be asked for by, and a block whose number cannot
be read is left out for the same reason. Type them the way they read
in the drawing — all of these name the same point:

```
35    Pt.35    pt35    PT.35    #35    035    35.0
```

Only the dot right after `Pt` is treated as a prefix — a point
genuinely named `40.5` keeps its decimal and is typed `40.5` (or
`Pt.40.5`).

A number that names no point in the drawing is reported and the
prompt re-asks — **nothing is drawn from a typo**. Enter at the TO
prompt cancels just that round; naming the same point twice is
caught too.

## A number the drawing carries twice

A sheet can hold **two surveys** — two pools in one yard, or two field
sheets merged — and each numbers its points from 1, so `1` names two
different places. A tie to the wrong one runs across the drawing and
measures nothing anybody taped, so it is not guessed at.

Every point carrying the number is **ringed** on screen
(`cdo:*pick-radius*`, 9", in `cdo:*pick-color*`, cyan) on a throwaway
layer of its own, `CDCALLOUT-PICK`, labelled `P1`, `P2`, … in drawing
order:

```
  2 points are numbered "7" - each one is ringed and labelled on screen.
   tag   from Pt.1
   ----  ------------
   P1    8'-4"
   P2    20'-0"

  Which Pt.7 is meant - click it, or type its label [Back] <Enter = none>:
```

The column beside each label is what tells them apart. At the **TO**
prompt it is how long the dimension choosing that one would draw — the
number the drafter has on the sheet in front of them; at the **FROM**
prompt, where there is no other end yet, it is where each one sits.

Click the one you want, or type its label. `Back` re-asks the number
itself; `Enter` takes none and draws nothing. The rings go as soon as
the question is answered — and on Esc, which is the one way out that
never reaches the erase, the layer is swept by the error handler.

A number only **one** point carries is taken exactly as it always was:
nothing is ringed, nothing is asked, nothing is printed.

The sister tools `ABFIND`, `ABMOVE` and `ABPCREATE` answer the same
question by **AB line** — they measure from the stakes, so which pair
of stakes is the thing to settle. `CDCALLOUT` ties whichever two points
you name and measures from neither, so here it is simply *which point*.

## Going back a step

The shared Back convention (see the root README) applies:

* `B`, `BACK`, `U` or `UNDO` (any case) at the **TO** prompt re-asks
  FROM;
* Back at the **FROM** prompt — offered as `[Back]` once something is
  drawn — **un-draws the last dimension** (`Stepping back one
  dimension.`, or `Already at the first dimension.` when there is
  nothing left to remove).

## Usage

1. Load `CDCALLOUT.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `CDCALLOUT`.
3. `From point number:` — type it (e.g. `35`).
4. `To point number:` — type it (e.g. `40`). The dimension draws
   immediately, its line right inbetween the two points, and the
   prompt goes back to `From point number:` for the next pair.
5. Press **Enter** at the TO prompt to skip a tie you have changed
   your mind about; press **Enter** at the FROM prompt when done.

Each tie reports what it drew, and the run ends with a summary:

```
  Pt.35 - Pt.40 dimensioned (10'-0").
CDCALLOUT: 3 cross dimensions created on layer DIMENSION in style CROSS DIMENSIONS.
```

## The missing-style rule (CDCREATE's, kept)

A missing **CROSS DIMENSIONS** style is **not** invented: the dims
are drawn in whatever style is current and the routine says so, so a
drawing started from the wrong template is obvious instead of
silently producing wrong-looking dims. They still land on the
DIMENSION layer.

## Revisions

`CDCALLOUT.lsp` carries the auto-stamped banner
`(setq *cdcallout-version* "v1.10")` that `tools/release_lisp.py`
reads; run it after any change and the dated twin
`releases/CDCALLOUT_MMDDYY_REV110.lsp` regenerates itself. Bump the
banner with every revision.

* **v1.10** — a number the drawing carries **twice** is asked about
  instead of silently taking the first match: every point that carries
  it is ringed and labelled `P1`, `P2`, … and the table says how long
  the dimension each one would draw is (at TO) or where it sits (at
  FROM). Click one or type its label; Back re-asks the number, Enter
  takes none. A number only one point carries is untouched by any of it.
* **v1.9** — every knob sits in one configuration block at the top of
  the file, each with its explanation; the layer colour and the
  same-spot tolerance joined the ones already there, and the three
  point-classifier knobs took the file's `cdo:` prefix. Fixed: with
  UNDO switched off in the drawing the run closed an undo group it had
  never opened.
* **v1.2** — the dimension line is placed automatically, right
  inbetween the two points (`cdo:*offset*` pushes it off,
  CDCREATE-style); the pick prompt is gone.
* **v1.1** — the shared Back convention: Back at TO/pick re-asks the
  previous question, Back at FROM un-draws the last dimension. A
  mis-typed TO number now re-asks TO instead of restarting the round.
* **v1.0** — first release.

## Tunables

Every knob sits in the tunables block at the top of
`CDCALLOUT.lsp`, each with its explanation beside it; change a value
there, or `setq` it after loading from a startup file:

| Variable | Default | Meaning |
| --- | --- | --- |
| `cdo:*style*` | `"CROSS DIMENSIONS"` | Dimension style the dims are drawn in — never invented; a missing one is reported and the current style used |
| `cdo:*layer*` | `"DIMENSION"` | Layer the dims land on, ByLayer — created when missing, thawed / unlocked / switched on when unusable |
| `cdo:*layer-color*` | `7` | ACI colour a *created* `DIMENSION` layer gets; an existing layer keeps its own |
| `cdo:*offset*` | `0.0` | How far the dimension line is pushed off the tie, drawing units; `0.0` = right inbetween, positive = to the left of the FROM→TO direction |
| `cdo:*exact-eps*` | `0.001` | Two points closer than this sit on the same spot; the tie is refused |
| `cdo:*point-block*` | `"ab_pt"` | Block name whose INSERTs are points wherever they sit |
| `cdo:*point-layer*` | `"POINTS"` | Layer whose INSERTs are always points |
| `cdo:*pt-tag*` | `"number"` | Attribute naming the point; a block without it lends its first numeric attribute |
| `cdo:*pick-layer*` | `"CDCALLOUT-PICK"` | Throwaway layer the rings round a doubled number go on — never `POINTS`, where every other tool would count them as survey points |
| `cdo:*pick-color*` | `4` | Colour of that layer and of the rings on it: cyan, so a ring reads as a question |
| `cdo:*pick-radius*` | `9.0` | Radius of one of those rings, drawing units |
| `cdo:*pick-hgt*` | `5.0` | Height of the `P1` / `P2` label beside it |
| `cdo:*pick-prefix*` | `"P"` | What those labels are called |
| `cdo:*prec*` | `4` | `rtos` precision for the distances printed in that table; 4 = 1/16" |

`cdo:*point-block*`, `cdo:*point-layer*` and `cdo:*pt-tag*` are the
survey-point classifier `BPCALLOUT` and `LHD` share — change them in all three or the tools disagree. (Before v1.9
they were spelled `*CDO-POINT-BLOCK*`, `*CDO-POINT-LAYER*` and
`*CDO-PT-TAG*`; a startup file that sets them needs the new names.)

Requires the Visual LISP engine (full AutoCAD; LT cannot run this).

## Tests

`tests/test_cdcallout.py` loads the real lisp into the repo's
AutoLISP VM and drives `CDCALLOUT` end to end — the style/layer/
ByLayer fixup, the automatic inbetween placement (and the offset
tunable), state restoration, the rinse-repeat loop, every number
spelling, decimal point names, unknown numbers, a doubled number
(ringed, labelled, picked by label and by click, at both prompts, with
Back, Enter and a stray label), cancelled rounds, Back, the
missing-style rule, a frozen / locked / off
`DIMENSION` layer and its colour knob, the point classifier, the
same-spot tolerance, UNDO switched off, and Esc mid-run through the
handler:

```
python3 tests/test_cdcallout.py
CALOFIN_LISP_ROOT=shared python3 tests/test_cdcallout.py   # grouped build
```
