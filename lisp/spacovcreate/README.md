# SPACOVCREATE -- the cover for a spa that is already drawn (AutoLISP / AutoCAD 2018+)

| | |
| --- | --- |
| Command | `SPACOVCREATE` |
| Version | `SPACOVCREATEVER` |
| File | `lisp/spacovcreate/SPACOVCREATE.lsp` (standalone, APPLOADs alone) |
| Grouped twin | `shared/parts/SPACOVCREATE.lsp` -- generated, see `tools/mirror_shared.py` |
| Draws on | `COVER` (outline and hinges), `TEXT` (hinge labels), `SPA-NOTES` (the report) |
| Tests | `tests/test_spacovcreate.py` |

## What it does

`SPA` draws a spa from its measurements. This draws the **cover** for a
spa that is already on the sheet -- somebody else's drawing, a DXF off a
survey, an outline traced from a photo -- where there are no
measurements to type, only geometry to point at.

Three questions and it is done.

### 1. Select the spa

```
Select the geometry that is the spa:
```

Whatever you pick is the spa. It can be

* one closed `LWPOLYLINE` (what `SPA` itself draws),
* a `CIRCLE` or an `ELLIPSE` (what `SPA` draws for a round spa),
* or a handful of loose `LINE`s, `ARC`s and polylines that meet end to
  end, in any order and either way round.

They are chained into loops and **the biggest loop is the spa**, so a
bench line or a spillway picked up by a careless window is a smaller
loop and is left alone. The command says how many loops it found and
which one it took:

```
2 closed outlines in the selection; the biggest is the spa (41.7 sq ft).
```

A run that never closes is ignored and named for it in the report. A
highlight made *before* the command was typed is taken as the answer, so
the usual pick-then-type habit works.

### 2. How far the cover laps

```
Cover offset past the spa <6.00> [Back]:
```

The cover is always the larger of the two, so the offset always goes
**outward**. Enter takes 6", the same lap `SPA` offers between a water's
edge and a cover size (`spa:*gapdflt*`); change one and change the other
or the two tools will draw different covers for one spa.

### 3. What taper

```
Select the block that gives the taper [Type/Skip/Back] <Skip>:
```

Three ways to answer, and the third is the one that matters:

* **Click the Spa Cover Details block** and its `GRADE` and `TAPER`
  tags are read (`Taper: 4-2 Flat` and `4-2` are the same answer -- the
  value is matched as a substring, so a tag nobody trimmed still
  reads). A block of some other name is read anyway, and says so.
* **`Type`** and type the taper: `3-2`, `4-2`, `4-3`, `5-3`, `5-4`,
  `3-3` or `1-3/8`.
* **`Skip`, or just Enter** -- and a **Standard 4-2 is assumed**, the
  cover is hinged to it, and the report carries

  ```
  TAPER NOT GIVEN - STD 4-2 ASSUMED
  ```

  in red, beside the drawing, along with a red `GRADE / TAPER` row. An
  assumption nobody can see on the sheet is the one that gets built.

Back at the taper re-opens the offset; Back at the offset re-opens the
selection. The selection itself offers no Back -- there is nothing in
front of it.

## The offset keeps the arcs

A cover is not a tessellated approximation of a cover.

The outline is held the way an `LWPOLYLINE` holds it -- a list of
`(point . bulge)` vertices -- and the offset moves **only the vertex**,
out along the bisector of the two directions meeting there, by
`d*(n1+n2)/(1+n1.n2)`. Every bulge is left exactly as it was, and that
is not an approximation: the offset of a circular arc is a circular arc
**on the same centre sweeping the same angle**, and the bulge is a
function of the angle alone.

So a 100 x 60 spa with a radius-12 corner, offset 6, comes out as a
112 x 72 cover whose corner is still on `(88,12)` at radius 18. A circle
comes out as a `CIRCLE`. The mitre is exact for two straight walls and
exact again where an arc runs tangent into a wall, which is every corner
`SPA` draws.

What comes out is **one closed `LWPOLYLINE`** (or one `CIRCLE`): it
picks in a single click, encloses an area, and can be dimensioned,
hatched, offset again or handed to `STOCKCOVER`, `PADDLE` or `AUTOBEAD`.

An `ELLIPSE` is the one shape with no exact answer -- the curve parallel
to an ellipse is not an ellipse -- so it is offset as a polyline and the
report says so rather than quietly drawing a lie.

A `SPLINE` is **not read at all**, for the same reason turned up to
eleven: it has no exact offset and no bulge to keep, so a cover built
from one would come back as a polygon of one. It is let through the
selection filter anyway, purely so the run can *say* that is what
happened -- dropped at the filter, a traced outline that is all spline
would just report "nothing closes" and leave you guessing. Explode it,
or `PEDIT` it to a polyline, and run again.

## The hinges

The same shop data `SPA` works to, read off tables copied from it value
for value (`tests/test_spacovcreate.py` compares the two row by row, so
the copy cannot drift into a second set of numbers nobody reconciles):

* the **grade and taper** pick a foam sheet;
* the sheet gives the **foam width** (the widest a piece may be, so the
  furthest two hinges may sit apart) and the **foam length** (the
  longest a hinge may run);
* the taper says which **piece counts** are acceptable.

A taper carrying more than one sheet -- Standard 4-2 comes in a 48 x 96
and a 49-1/2 x 102 -- has every sheet solved and **scored** on what it
satisfies: the foam width (4), the foam length (2), an acceptable piece
count (1), and only then fewest pieces. The width weighs most because a
piece wider than the sheet cannot be cut at all, where a hinge over the
foam length is a cover that gets made and then flagged. Piece counts
from the fewest that fit up to three past it are tried, so a count the
taper refuses is stepped over rather than shipped.

Fold and velcro then follow the **Hinge Arrangement Chart** -- `SPA`'s
`spa:hingetypes`, unchanged:

```
2  H              5  H V V H          8  H V H V H V H
3  H V            6  H V H V H        9  H V H V V H V H
4  H V H          7  H V H V V H
```

The pieces fold up in pairs from both ends: a fold hinge inside each
pair, velcro between bundles, an odd count leaving one flat piece at or
beside the centre. Fold hinges are dashed (`DASHED2`, scaled so the dash
plots 5" whatever the drawing's `LTSCALE`) and labelled `Hinge`; velcro
hinges are ByLayer and labelled `Velcro Hinge`. A Thermo-Light is velcro
throughout.

Hardware called for by the **longest** hinge -- velcro hinges, double C
channel, hold down kit -- is reported in cyan as advice, not as a
failure.

### Which way the hinges run

`SPA` turns the spa until its long overall runs west to east and then
runs the hinges north-south. Nothing here can be turned -- the geometry
is already drawn, at whatever angle the sheet has it -- so the rule is
read the other way round: **the hinges divide the longer of the cover's
two overalls**, which is the same layout `SPA` would reach, arrived at
without moving anybody's drawing. A cover wider than it is tall gets
upright hinges; a taller one gets flat hinges, with the labels reading
along them. The report says which way it went.

## The report

A three-column table on `SPA-NOTES`, beside the cover, with its
lettering scaled from the size of the cover: what was measured, the
limit it is measured against, and what it came out at. Every number the
hinge maths produces is a number with a ceiling over it; a row with no
ceiling prints a dash there rather than a nought.

```
SPA COVER REPORT
ITEM                  LIMIT     ACTUAL
SPA OUTLINE           -         1 object, 4 vertices
COVER OFFSET          -         6.00
COVER ACROSS          -         112.00
COVER UP              -         72.00
GRADE / TAPER         -         STD 4-2            <- red when assumed
PIECES (STD 4-2)      -         3
FOAM WIDTH MAX        49.50     37.33
FOAM LENGTH MAX       102.00    72.00
HINGES RUN            -         UP (dividing across)
HINGE 1 (FOLD)        -         37.33
HINGE 2 (VELCRO)      -         74.67

TAPER NOT GIVEN - STD 4-2 ASSUMED                  <- red
VELCRO HINGES: no - hinge 72.0 not over 120        <- cyan
```

Anything out of spec is **drawn anyway and flagged in red**, because a
drafter who can see the problem can fix it and one who cannot, cannot:

| Flag | What happened |
| --- | --- |
| `TAPER NOT GIVEN - STD 4-2 ASSUMED` | nobody gave a taper |
| `HINGE n EXCEEDS THE FOAM LENGTH (a > b)` | the cover is taller than the sheet is long |
| `A PIECE IS WIDER THAN THE FOAM SHEET (a > b)` | no piece count reached the width |
| `n PIECES NOT ACCEPTABLE FOR STD 4-2` | the count the geometry forced is not on the sheet |
| `GRADE/TAPER x y NOT ON THE FOAM SHEET - 48/96 ASSUMED` | neither the pair nor its Standard row exists |
| `n SELECTED RUNS NEVER CLOSED - IGNORED` | part of the selection was not a loop |
| `ELLIPSE OFFSET AS A POLYLINE ...` | the one shape with no exact offset |
| `n SPLINES NOT READ - EXPLODE OR FIT TO A POLYLINE` | a spline was selected; nothing was built from it |
| `WALL n IS SHORTER THAN THE OFFSET - COVER CROSSES ITSELF` | the offset swallowed a wall |
| `INWARD ARC AT CORNER n IS SMALLER THAN THE OFFSET` | a concave arc the offset ate |
| `CORNER n IS TOO SHARP TO OFFSET CLEANLY - CLAMPED` | a mitre past `scv:*miterlim*` |

## Install & run

APPLOAD `SPACOVCREATE.lsp` on its own, or load the whole build from
`shared/LAZPASS.lsp`. `SPACOVCREATE` runs it; `SPACOVCREATEVER` prints
the loaded version. The run is one `UNDO` group, so one `U` rolls the
whole cover back.

On the panel it sits on the **Spa** page (beside `SPA` and `LAZSPA`) and
on the **Layout** category page, captioned *Spa cover from the spa*. In
a session that has not loaded it, **the button is greyed** on both
surfaces -- `LAZPANEL` greys it from `lzp:loaded`, the VB palette from
`calofin:*commands*` -- and on the Find page it is listed with
`(not loaded)` against it rather than offered and then refused. It
searches by caption as well as by name, so typing *cover* finds it.

## Tunables

Every knob is in the tunables block at the top of the file and nowhere
else. Edit and re-APPLOAD, or type the `setq` at the command line for
one session -- every knob is read when the command runs, not when the
file loads.

| Knob | Default | What moves when you change it |
| --- | --- | --- |
| `scv:*offset-dflt*` | `6.0` | the lap Enter takes at question 2 |
| `scv:*filter*` | curves only | what the selection is allowed to hand the command |
| `scv:*taper-dflt*` | `"4-2"` | the taper assumed when nobody gives one |
| `scv:*grade-dflt*` | `"STANDARD"` | the grade assumed with it |
| `scv:*block-name*` | `"SPA COVER DETAILS"` | the block name it expects (a different one is read anyway, with a note) |
| `scv:*grade-tag*` / `scv:*taper-tag*` | `"GRADE"` / `"TAPER"` | the two attribute tags read off it |
| `scv:*chain-tol*` | `0.05` | how far apart two ends may be and still be one end |
| `scv:*arcstep*` | `5.0` | degrees per segment when an arc has to be *measured* (never when it is drawn) |
| `scv:*miterlim*` | `4.0` | how far a corner may stretch, in multiples of the offset, before the spike is clamped |
| `scv:*fuzz*` | `1.0e-6` | what counts as zero |
| `scv:*lay-cover*` / `scv:*col-cover*` | `COVER` / 6 | where the outline and the hinges go |
| `scv:*lay-text*` / `scv:*col-text*` | `TEXT` / 7 | where the hinge labels go |
| `scv:*lay-report*` / `scv:*col-report*` | `SPA-NOTES` / 3 | where the report goes |
| `scv:*col-bad*` / `scv:*col-advice*` | 1 / 4 | the red flag and the cyan recommendation |
| `scv:*hdashname*` / `*hdashpat*` / `*hdashmult*` | `DASHED2` | the fold hinge's linetype and its plotted dash length |
| `scv:*hingetxth*` / `*hingetxw*` / `*hingestyle*` / `*hingetxoff*` | 5.0 / 60.0 / `Attributes` / 0.6 | the hinge labels |
| `scv:*th-min*` / `scv:*th-div*` | 1.0 / 40.0 | how big the report's lettering comes out |
| `scv:*rep-gap*` / `*rep-row*` / `*rep-title*` / `*rep-note*` / `*rep-adv*` / `*rep-c1*` / `*rep-c2*` / `*rep-w*` | see the file | where the report's columns and rows sit |
| `scv:*foamtab*` / `*foamdflt*` / `*foamdpc*` / `*thermotaper*` | SPA's | the foam sheet the hinges are solved on |
| `scv:*hardtab*` / `*hardnames*` | SPA's | the hardware the longest hinge calls for |
| `scv:*hinge-min*` / `scv:*hinge-try*` | 2 / 3 | the fewest pieces a cover is ever cut into, and how many counts past the minimum are tried |

**The foam and hardware tables are a copy of `SPA`'s on purpose** -- a
standalone file has to load alone, and `SPA` is not loaded when this one
is. A change to the shop's foam sheet is therefore a change to **both**,
and `tests/test_spacovcreate.py` compares the two table by table so the
copy cannot quietly drift.

## Notes & limitations

* **No spillaways.** A spillway is a no-go zone that `SPA` dodges by
  turning the spa, and turning is not on the table here -- the geometry
  is already drawn. Measure the spa and run `SPA` when a spillway has to
  be dodged.
* **The outward offset of a concave corner can cross itself.** Every
  offset that does is flagged (`WALL n IS SHORTER THAN THE OFFSET`,
  `INWARD ARC AT CORNER n ...`) and drawn as it came out, rather than
  silently repaired into something nobody asked for.
* **A chord is measured lowest crossing to highest**, so a hinge across
  a notched cover measures the whole run the foam has to cover, not the
  two bits either side of the notch. `SPA` measures the same way.
* **The offset is asked for in whatever `getdist` takes** -- inches,
  `6'10"`, or two clicks in the drawing. It does not take `SPA`'s
  millimetre spelling; that is `SPA`'s own extension.
* The spa outline itself is never moved, changed or erased.

## Tests

```
python3 tests/test_spacovcreate.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_spacovcreate.py # grouped tier
```

Structural checks (sysvars saved and restored, knobs in the tunables
block, the four LAZDIAG call sites, the `releases/` twin), parity checks
against `SPA`'s tables and chart, geometry checks where every answer is
one that can be worked out by hand, and runtime checks driving the whole
command: the three answers, Back between them, the assumed 4-2 in red,
the hinge layout and its labels, a tall cover hinged the other way,
loose walls chained out of order, two loops, and everything it flags.
