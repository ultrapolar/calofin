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
spot with no block under it can be called out too. Clicking a ringed
point **again un-rings it**: the circle is erased and the point leaves
the callout. A click that snaps to a *different* survey point never
un-rings a neighbour it merely lands close to; only a click with no
survey point under it is read against the rings it sits inside.

## Usage

1. Load `BPCALLOUT.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `BPCALLOUT`.
3. Click each bad point (click a ringed one again to un-ring it);
   **Enter** when done.
4. Place the callout text (or **Enter** for the default spot beside
   the last ring).

The command prints what it did, e.g.:

```
BPCALLOUT: 3 point(s) ringed on layer FGStep;  "Pt.12, Pt.15 and Pt.20 are bad"
```

## Revisions

`BPCALLOUT.lsp` carries the auto-stamped banner
`(setq *bpcallout-version* "v1.8")` that `tools/release_lisp.py`
reads; run it after any change and the dated twin
`releases/BPCALLOUT_MMDDYY_REV18.lsp` regenerates itself. Bump the
banner with every revision.

* **v1.8** — every knob sits in one configuration block at the top of
  the file, each with its explanation, and the layer colour, the
  default text spot and the callout wording joined the ones already
  there. Fixed: a click that snapped to a survey point was still read
  against the existing rings, so a click meant for a point 8″ from a
  ringed one landed inside the 5″ ring and un-ringed the neighbour
  instead — two points under 10″ apart could never both be ringed.
  Only a click with no survey point under it is read against the
  rings now.
* **v1.1** — fixed a fatal bug: `c:BPCALLOUT` declared a local named
  `last`, which in AutoLISP shadows the built-in `last` for the whole
  call, so the run died with `no function definition: LAST` the
  moment it finished picking and went to place the text. The rings
  were already drawn, but the callout never got written. The local is
  now `lastpt`. `tests/lispvm.py` models the shadowing rule now, so
  this class of bug fails in the test suite instead of at the command
  line.
* **v1.0** — first release.

## Tunables

Drawing units are assumed to be **inches** (architectural). Every knob
sits in the tunables block at the top of `BPCALLOUT.lsp`, each with its
explanation beside it; change a value there, or `setq` it after loading
from a startup file:

| Variable | Default | Meaning |
| --- | --- | --- |
| `bp:*layer*` | `"FGStep"` | Layer the rings and the callout land on — created when missing, thawed / unlocked / switched on when unusable |
| `bp:*layer-color*` | `1` | ACI colour a *created* `FGStep` gets (red); an existing layer keeps its own |
| `bp:*radius*` | `5.0` | Ring **radius**; use `2.5` for a 5″ diameter. Also how far an un-ring click reaches on a `Pt.?` ring |
| `bp:*snap*` | `12.0` | A pick within this of a survey point rings that point (the nearest when several qualify); farther away the pick itself is ringed as `Pt.?` |
| `bp:*exact-eps*` | `0.001` | Two ring centres this close are the same spot, so a second click on a ringed point un-rings it |
| `bp:*text-hgt*` | `6.0` | Callout text height |
| `bp:*text-gap*` | `10.0` | Enter at the text prompt tucks the callout this far right of and below the last ring |
| `bp:*pt-prefix*` | `"Pt."` | How a point is named: prefix + number, `Pt.12` |
| `bp:*tail-one*` | `" is bad"` | What follows the name when one point was ringed |
| `bp:*tail-many*` | `" are bad"` | …and when two or more were |
| `bp:*unknown*` | `"?"` | The number given to a ring with no readable point under it |
| `bp:*point-block*` | `"ab_pt"` | Block name whose INSERTs are points wherever they sit |
| `bp:*point-layer*` | `"POINTS"` | Layer whose POINTs and INSERTs are always points |
| `bp:*pt-tag*` | `"number"` | Attribute naming the point; a block without it lends its first numeric attribute |

The last three are the survey-point classifier `LHD` and `CDCALLOUT`
share — change them in all three or the tools disagree. (Before v1.8
they were spelled `*BP-LAYER*`, `*BP-RADIUS*` and so on; a startup file
that sets them needs the file's `bp:` prefix now.)

## Tests

`tests/test_bpcallout.py` loads the real lisp into the repo's
AutoLISP VM and drives `BPCALLOUT` end to end — snapping (and the
nearest of several candidates), the ring layer/radius, the is/are
grammar for one, two and many points, the `Pt.?` fallback, un-ringing
by reclick (and that a click snapping to a neighbour never un-rings),
the point classifier, every knob read at run time, a frozen / locked /
off `FGStep`, the default text spot, UNDO switched off, and Esc at a
click and at the text prompt:

```
python3 tests/test_bpcallout.py
CALOFIN_LISP_ROOT=shared python3 tests/test_bpcallout.py   # grouped build
```
