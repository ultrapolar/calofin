# BPCALLOUT — bad-point callout (AutoLISP)

`BPCALLOUT` rings every point you say is bad and writes one sentence
naming them all. Click as many points as you wish, press **Enter**,
place the text — done.

Each click:

1. **Snaps to the survey point** nearest the pick (within 12″), so a
   sloppy click still rings the point itself, dead center.
2. **Draws a 5″ circle** about that point on the **FGStep** layer —
   the same layer LHD puts its miss rings on. The layer is created
   (or switched on, thawed and unlocked) if it has to be.
3. **Reads what the point is called** from the drawing itself: the
   `number` attribute on the point block, the name the rest of the
   toolset reports as `Pt.17`.

After the last click, one TEXT goes wherever you put it:

| Points clicked | Callout written |
| --- | --- |
| one | `Pt.12 is bad` |
| two | `Pt.12 and Pt.15 are bad` |
| three or more | `Pt.12, Pt.15 and Pt.20 are bad` |

…for as many points as were clicked — commas between all but the
last pair, `and` before the last. Pressing **Enter** at the text
prompt tucks the callout just beside the last ring instead.

## What counts as a point

The same classifier LHD uses:

* an `ab_pt` INSERT on **any** layer — its `number` attribute names
  the point (when the block carries no `number` tag, the first
  attribute that reads as a number is taken instead);
* any other INSERT sitting on the **POINTS** layer;
* a plain POINT entity on the **POINTS** layer (no name to read —
  reported as `Pt.?`).

A click that lands farther than 12″ from every survey point is still
ringed — exactly where you clicked — and reported as `Pt.?`, so a bad
spot with no block under it can be called out too. Clicking the same
point twice is skipped with a note, never ringed twice.

## Usage

1. Load `BPCALLOUT.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `BPCALLOUT`.
3. Click each bad point; **Enter** when done.
4. Place the callout text (or **Enter** for the default spot beside
   the last ring).

The command prints what it did, e.g.:

```
BPCALLOUT: 3 point(s) ringed on layer FGStep;  "Pt.12, Pt.15 and Pt.20 are bad"
```

## Revisions

`BPCALLOUT.lsp` carries the auto-stamped banner
`(setq *bpcallout-version* "v1.0")` that `tools/release_lisp.py`
reads; run it after any change and the dated twin
`releases/BPCALLOUT_MMDDYY_REV10.lsp` regenerates itself. Bump the
banner with every revision.

## Assumptions / configuration

Drawing units are assumed to be **inches** (architectural). The
constants at the top of `BPCALLOUT.lsp` are easy to change:

```lisp
(setq *BP-LAYER*       "FGStep")  ; rings + callout text land here
(setq *BP-RADIUS*      5.0)       ; ring RADIUS; use 2.5 for a 5" dia.
(setq *BP-SNAP*        12.0)      ; pick-to-point snap distance
(setq *BP-TEXT-HGT*    6.0)       ; callout text height
(setq *BP-POINT-BLOCK* "ab_pt")   ; the survey point block
(setq *BP-POINT-LAYER* "POINTS")  ; layer whose POINTs/INSERTs count
(setq *BP-PT-TAG*      "number")  ; attribute naming the point
```

## Tests

`tests/test_bpcallout.py` loads the real lisp into the repo's
AutoLISP VM and drives `BPCALLOUT` end to end — snapping, the ring
layer/radius, the is/are grammar for one, two and many points, the
`Pt.?` fallback, duplicate-click skipping and the default text spot:

```
python3 tests/test_bpcallout.py
```
