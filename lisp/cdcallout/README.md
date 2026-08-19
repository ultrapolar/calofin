# CDCALLOUT — cross-dimension Pt.## to Pt.## (AutoLISP)

`CDCALLOUT` is the dimensioning sister of `BPCALLOUT`. Instead of
clicking points, you **name** them: type the FROM point number and
the TO point number — and an aligned dimension is drawn between
those two survey points, the dimension line placed automatically
**right inbetween**, on the tie itself (CDCREATE's convention;
nudge `cdo:*offset*` to push it off). Nothing is ever clicked. It
keeps asking for the next pair until you press **Enter**.

Every dimension lands the way `CDCREATE` and `POOL` make cross dims:

* dimension style **CROSS DIMENSIONS**,
* layer **DIMENSION** (created if the drawing lacks it),
* ByLayer — any per-entity colour / linetype / lineweight override is
  stripped.

The whole run is **one undo group**: a single `U` takes every
dimension away. The dimension style, current layer, `OSMODE` and
`CMDECHO` in force before the command are restored afterwards — on a
clean finish, an error, or Esc.

## Typing point numbers

Numbers are matched against the `number` attribute on the survey
point blocks (the same classifier `BPCALLOUT` and `LHD` use: an
`ab_pt` INSERT on any layer, or any other INSERT on the **POINTS**
layer). Type them the way they read in the drawing — all of these
name the same point:

```
35    Pt.35    pt35    PT.35    #35    035    35.0
```

Only the dot right after `Pt` is treated as a prefix — a point
genuinely named `40.5` keeps its decimal and is typed `40.5` (or
`Pt.40.5`).

A number that names no point in the drawing is reported and the
prompt re-asks — **nothing is drawn from a typo**. Enter at the TO
prompt cancels just that round; naming the same point twice is
caught too. When a drawing carries a duplicate number, the first
match wins.

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
   immediately, its line right inbetween the two points.
5. Rinse and repeat from 3; press **Enter** at the FROM prompt when
   done.

Each round reports what it drew, and the run ends with a summary:

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
`(setq *cdcallout-version* "v1.2")` that `tools/release_lisp.py`
reads; run it after any change and the dated twin
`releases/CDCALLOUT_MMDDYY_REV12.lsp` regenerates itself. Bump the
banner with every revision.

* **v1.2** — the dimension line is placed automatically, right
  inbetween the two points (`cdo:*offset*` pushes it off,
  CDCREATE-style); the pick prompt is gone.
* **v1.1** — the shared Back convention: Back at TO/pick re-asks the
  previous question, Back at FROM un-draws the last dimension. A
  mis-typed TO number now re-asks TO instead of restarting the round.
* **v1.0** — first release.

## Assumptions / configuration

The constants at the top of `CDCALLOUT.lsp` are easy to change:

```lisp
(setq cdo:*style*       "CROSS DIMENSIONS") ; dimension style
(setq cdo:*layer*       "DIMENSION")        ; layer dims land on
(setq cdo:*offset*      0.0)                ; push the dim line off the
                                            ; tie; 0.0 = right inbetween
(setq *CDO-POINT-BLOCK* "ab_pt")            ; the survey point block
(setq *CDO-POINT-LAYER* "POINTS")           ; layer whose INSERTs count
(setq *CDO-PT-TAG*      "number")           ; attribute naming the point
```

Requires the Visual LISP engine (full AutoCAD; LT cannot run this).

## Tests

`tests/test_cdcallout.py` loads the real lisp into the repo's
AutoLISP VM and drives `CDCALLOUT` end to end — the style/layer/
ByLayer fixup, the automatic inbetween placement (and the offset
tunable), state restoration, the rinse-repeat loop, every number
spelling, decimal point names, unknown numbers, cancelled rounds,
Back and the missing-style rule:

```
python3 tests/test_cdcallout.py
```
