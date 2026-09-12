# LOBF -- the line of best fit through a row of survey points (AutoLISP / AutoCAD 2018+)

Highlight points that are all **meant** to be on one straight line -- a
wall shot at eight stations, a row of deck anchors, the edge of a coping
run -- and LOBF draws the construction line (an `XLINE`) that best
answers them.

It draws **three**, because "best" is a choice, and the choice is about
**where the error goes**. All three appear at once, each in its own
colour and numbered on screen; you keep the one you want and the others
go.

## What it does

1. **Reads the points.** Every `POINT` entity in the selection, every
   `ab_pt` block wherever it sits, and any other block dropped on the
   `POINTS` layer. A point block's own surveyed number (its `number`
   attribute) is what LOBF calls it, so a finding reads `Pt. 17` and
   means point 17 on the survey; a point with no number of its own is
   numbered in the order it was read. Two points closer together than
   `lobf:*exact-eps*` are one shot -- a double-shot does not get two
   votes in the fit.

   The selection filter admits points and blocks only, so a window
   dragged across the whole sheet picks up the survey and leaves the
   drawn geometry behind instead of making you pick each point.

2. **Builds three fits.**

   | # | Fit | What it does with the error |
   | - | --- | --- |
   | 1 | **every point** | Least squares on the **perpendicular** distances -- total least squares. The line with the least total error, every point pulling on it. The textbook line of best fit, and the honest answer when the points really are all equally good. |
   | 2 | **one set aside** | The same fit with a single point left out. Every point is tried as the one to drop, and the drop that leaves the **rest** tightest wins. The error stops being shared: it piles onto one point, which is what you want to see when one shot is bad. That point is ringed and named, so it can be re-measured instead of quietly averaged into the wall. |
   | 3 | **tightest band** | The least-**max** (Chebyshev) fit: the narrowest band that still holds every point, with the line down its middle. Nobody is further off than they have to be, and the half-band is the number to quote. |

   Fit 1 is perpendicular least squares rather than the `y`-on-`x`
   regression a spreadsheet would give you, because a construction line
   does not know which axis you called `x`: a wall running north-south
   fits exactly as well as one running east-west. Fit 3 tries only the
   edges of the points' convex hull, because the narrowest band through
   a point set is always flush with one of them.

3. **Says which one Enter takes, and why.** Fit 2 is the default when
   the point it set aside is *drastically* worse than the rest --
   `lobf:*drastic*` times the worst of the points it kept (4x), and at
   least `lobf:*drastic-floor*` off in its own right (1/2"). Both halves
   have to hold: without the ratio a fit that merely dropped its worst
   point would always win, and without the floor a survey where
   everything is inside a sixty-fourth would still have one point "four
   times the rest" and get it blamed for noise.

   When no point stands out that way there is no outlier to isolate, and
   fit 1 -- the balanced one -- is the default instead. Either way the
   command line prints the numbers that decided it:

   ```
      6 point(s) fitted.  3 candidate line(s) are drawn on layer LOBF-PREVIEW:

      #  fit                   worst off     avg off       held    bearing    colour
      -  --------------------  ------------  ------------  ------  ---------  ------
      1  every point           0'-5"         0'-1 21/32"   6       0.00 deg   green
      2  Pt. 7 set aside       0'-0"         0'-0"         5       0.00 deg   yellow
      3  tightest band         0'-3"         0'-3"         6       0.00 deg   magenta

     "worst off" and "avg off" are perpendicular distances, measured only over
     the points each fit HELD - fit 2 holds one fewer, which is the whole point of it.

     Fit 2 sets Pt. 7 aside: it is 0'-6" off that line, against 0'-0" for the worst of the 5 it held.
     That is the outlier this tool looks for, so fit 2 is what Enter takes.
   ```

   That is the run the tests use: five points on `y=0` at 40" centres and
   one 6" up over the middle. Fit 1 splits the difference and lands at
   `y=1`, fit 3 centres the 0-to-6 band and lands at `y=3` with all six
   exactly 3" out, and fit 2 drops the high one and sits exactly on the
   five that agree.

   `worst off` and `avg off` are perpendicular distances measured only
   over the points each fit **held** -- fit 2 holds one fewer, which is
   the whole point of it.

4. **Lets you choose.** `Keep which fit - click one, or
   [1/2/3/All/None/Redo] <2>:` -- the repo's standard multi-fit picker.
   Click the line you want or type its number; `All` keeps the three as
   previewed, `None` leaves the drawing as it was, and `Redo` is this
   prompt's way back -- it clears the trio and asks for the points
   again.

5. **Keeps what you picked.** The losers are erased. The line you kept
   moves from `LOBF-PREVIEW` onto `LOBF` and is drawn `ByLayer` (the
   preview colours mean "this is candidate 2", and once there is one
   line left they mean nothing). If the fit you kept is one that ignores
   a point, the ring round that point stays, on `LOBF-IGNORED` -- that
   is the finding, not the furniture.

### Telling three near-identical lines apart

Three fits through one row of points sit nearly on top of each other,
and colour alone is not enough at drawing scale. So each candidate's
number is drawn out past the end of the run on a **stalk** -- a short
line from the fit's own XLINE out to its label, one stalk-length per
candidate, so the three numbers stack instead of overprinting and no
label can be read against the wrong line. The stalks and numbers are
preview furniture: they are erased with the losers when you keep a
single fit, and kept (with a note saying so) when you keep `All`.

### When the points are not a line

If fit 1's worst point is further off the line than `lobf:*blob-ratio*`
of the run's own length, LOBF says so before you pick:

```
  CAUTION: the worst point is 55% of the run's own length off the line.
  These points may not be one straight line at all - check the selection
  before you keep anything.
```

It is a caution, not a refusal -- LOBF cannot know your drawing -- but a
line drawn through a blob is a wrong answer that looks like a right one,
and the whole assumption behind the command is that the points belong to
one line.

## Install & run

`APPLOAD` `LOBF.lsp` (or add it to your Startup Suite), then type
`LOBF`. `LOBFVER` prints the loaded version. In the grouped build the
file is already there -- `LOBF` is one of the commands `LAZPASS.lsp`
brings in.

A pre-selection is honoured: highlight the points first and `LOBF` takes
them without asking. Otherwise it asks, and Enter at that prompt takes
every point in the drawing.

## Tunables

Every setting is in the one block at the top of `LOBF.lsp`, between the
version banner and the first `defun`. Edit and re-`APPLOAD`, or type the
`setq` at the command line to try a value for one session -- every knob
is read when the command runs, not when the file loads.

| Knob | Default | What changing it does |
| --- | --- | --- |
| `lobf:*pt-layer*` | `"POINTS"` | Layer holding the survey points. Only matters for bare `POINT` entities and for blocks of some other name -- an `ab_pt` block counts as a point wherever it sits |
| `lobf:*pt-block*` | `"ab_pt"` | Block name whose `INSERT`s mark points |
| `lobf:*pt-tag*` | `"number"` | The attribute carrying a point block's surveyed number |
| `lobf:*filter*` | `'((0 . "POINT,INSERT"))` | What the highlight is allowed to hand the command. A type dropped from here is never seen at all; adding line types would let a window pick up geometry LOBF has nothing to say about |
| `lobf:*exact-eps*` | `1.0e-6` | Two points closer together than this are one shot, not two votes in the fit (drawing units) |
| `lobf:*drastic*` | `4.0` | **The rule that picks the default.** Fit 2 is offered only when the point it set aside is this many times the worst of the ones it kept. Lower it and LOBF reaches for the outlier fit more readily; raise it and it wants a more obvious bad shot before it will single one out |
| `lobf:*drastic-floor*` | `0.5` | ...and at least this far off in its own right (drawing units). Without a floor, a survey where every point is within a sixty-fourth would still have a "worst" one four times the rest, and calling that an outlier is reading noise. Raise it to make LOBF slower to blame a point |
| `lobf:*default-fit*` | `"1"` | Which fit Enter takes when no point stands out that way -- there is then no outlier to isolate, so the balanced fit is the answer. Set it to `"3"` to have Enter take the tightest band instead |
| `lobf:*blob-ratio*` | `0.2` | When fit 1's worst point is further off than this fraction of the run's own length, LOBF warns that the points may not be one line. Raise it to quieten the warning |
| `lobf:*layer*` | `"LOBF"` | The layer the construction line you keep is moved to |
| `lobf:*color*` | `4` | Its colour (ACI, cyan) -- applied when the layer is created, so a layer already in the drawing keeps its own |
| `lobf:*preview-layer*` | `"LOBF-PREVIEW"` | The three candidates, their stalks and their numbers while you choose |
| `lobf:*preview-color*` | `8` | The preview layer's colour (ACI, grey). Each candidate carries its own colour, so this is only what the layer itself is created as |
| `lobf:*ign-layer*` | `"LOBF-IGNORED"` | The ring round a point a kept fit ignores. Its own layer, so it can be frozen or erased without touching the line |
| `lobf:*ign-color*` | `1` | Its colour (ACI, red) |
| `lobf:*appid*` | `"LOBF"` | The xdata stamp every object LOBF draws carries. Renaming it orphans earlier runs |
| `lobf:*fit-colors*` | `'(3 2 6)` | The colour each candidate is previewed in, fit 1 first (ACI: green, yellow, magenta). The printed table names them, so changing this changes the table too |
| `lobf:*label-div*` | `40.0` | Label text height, as a divisor of the run the points cover -- a bigger number is smaller text |
| `lobf:*label-gap*` | `0.08` | How far past the last point the labels stand, as a fraction of the run |
| `lobf:*label-stalk*` | `1.6` | How far a number sits off its own line, in text heights, multiplied by the fit's number so the three stack instead of overprinting |
| `lobf:*ring-scale*` | `1.2` | Radius of the ring round a set-aside point, in text heights |
| `lobf:*dist-mode*` | `4` | Distances go through `(rtos d mode prec)`: mode 4 is architectural (feet-inches), so 1.875 reads `0'-1 7/8"` |
| `lobf:*dist-prec*` | `5` | How many ways the inch is split, as a power of two. 5 = thirty-seconds, because the errors this tool reports are small ones and sixteenths round too many of them to the same string to compare |
| `lobf:*ang-prec*` | `2` | Decimal places on the bearing printed after each fit, so two fits that read the same to the thirty-second can still be told apart |
| `lobf:*tiny*` | `1.0e-10` | Anything smaller is zero: the guard on a degenerate fit, on a zero-length direction, and on the cross products the hull walk turns on |

## Notes & limitations

* **Two points make exactly one line**, so the picker is skipped and the
  line is simply drawn -- three identical candidates and a choice
  between them would be theatre.
* **Fewer than two points, or every point on one spot**, and there is
  nothing to fit. LOBF says which rather than drawing a line along the X
  axis and letting you find out later.
* **Flat (XY).** Points are read at their `X`/`Y` and the fit is a
  world-plane line; Z is ignored.
* **A perfectly symmetric cloud has no best direction.** Four points on
  the corners of a square fit every direction equally well, and fit 1
  returns the X axis because something has to come back. It is not
  silent about it: a cloud like that is well past `lobf:*blob-ratio*`,
  so the caution above fires before you pick.
* **It fits, it does not judge.** The caution above is the only opinion
  LOBF has about whether your points belong to one line. Whether a point
  it set aside is a bad shot or a real feature of the wall is yours to
  decide -- which is exactly why fit 2 is offered rather than applied.
* **One line per run.** LOBF does not split a selection into two walls
  and fit each; highlight one run at a time.
* **It only ever draws a straight line.** Points that trace a curve get
  the straight line that best answers them, which is a true answer to
  the wrong question. [ABLOBF](../ablobf/README.md) is the same idea as
  a POLYLINE: arcs and lines threaded through the points, open, between
  two ends you pick.
* The grouped twin is generated -- run
  `python3 tools/mirror_shared.py LOBF` after editing this file, never
  hand-edit `shared/parts/LOBF.lsp`.

## Tests

```
python3 tests/test_lobf.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lobf.py # grouped tier
```

Puts points where the answer is known by hand -- five on a line with one
6" above the middle, where fit 1 lands at `y=1`, fit 2 at `y=0` with the
stray 6" off, and fit 3 at `y=3` with all six exactly 3" out -- and
checks each of the three lands there. Then the rule that picks the
default (a drastic outlier, an evenly shared bow, and a 1/16" "outlier"
that the floor refuses to blame), the whole command end to end through
every answer the picker takes, clicking a line instead of typing its
number, and the edges: two points, one point, a triple shot on one spot,
and a blob that earns the caution.
