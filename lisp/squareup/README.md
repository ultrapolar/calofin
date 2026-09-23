# SQUAREUP

Turn a drawing until its perimeter's longest run is horizontal.

```
SQUAREUP      highlight the work, pick the perimeter, square the work to it
SQUAREUPVER   print the loaded version
```

A survey does not arrive square. The tape is walked round the pool in
whatever direction the deck allowed, the drone photo is taken from
wherever the operator stood, and what lands in the drawing is a pool
sitting four or five degrees off — close enough to look deliberate, far
enough that every horizontal dimension is a hair long and every
`AUTODIM` run stands its text at an angle. Squaring it up by eye is a
`ROTATE`, a guess at the angle, an undo, and another guess.

SQUAREUP measures the angle instead.

## The two picks

1. **Highlight the work** — everything that has to turn together: the
   outline, the bead track, the survey points, their number labels, the
   notes. Enter takes the whole drawing, which is what a freshly
   imported survey usually is -- the whole of the space being drawn
   in, that is: model space from the Model tab or from inside a
   layout's viewport, so a title block and its viewports on the sheet
   are left out (ROTATE would skip them anyway, and the count would
   say they turned). A selection made before the command was typed is
   used as it stands.
2. **Select the perimeter** — the one outline that says which way is
   along. A single polyline, or the loose lines and arcs a traced
   perimeter comes in as. Only curve types are offered, so a stray
   label or point cannot quietly contribute a corner to the
   measurement.

Then the whole of (1) turns about the middle of (2), by the **smallest**
angle that gets there. Smallest is the point: a wall lying at 176
degrees is put flat by turning 4, not by turning 176 and standing the
drawing on its head.

## Wall or Span

Two things can be "the longest length", and which one is right depends
on the pool, so both are measured and printed before the question is
put — the choice is between two numbers, not two words:

```
SQUAREUP: the longest wall is 40'-0" at +6.00 degrees; the longest span is
  44'-8 5/8" at +32.57 degrees.
What should end up horizontal? [Wall/Span] <Wall>:
```

| Answer | What it measures |
| --- | --- |
| `Wall` | The longest **straight run** of the perimeter — a rectangle pool's long side |
| `Span` | The longest **distance across** it, corner to corner — the only answer a kidney or a freeform pool has |

**A run a trace split into five collinear pieces is one wall, not
five.** A survey perimeter arrives as whatever the tracer clicked, so a
longest-run read off single segments would square a forty-foot pool to
a ten-foot fragment of its own side. Touching pieces that lie along the
same line are folded together first, and the direction each fold is
compared against is the direction of the run **so far** — so a chain
that bows stops being one wall as soon as it has bent `sq:*collinear-deg*`
from where it set off, rather than creeping round a corner one harmless
degree at a time.

**Span is measured over the convex hull.** The widest measurement across
a set of points runs between two hull corners and nowhere else, so a
traced perimeter of three hundred points is measured as its dozen hull
corners instead. Arcs and bulges are sampled into `sq:*arcsegs*` chords
each; an ellipse from its own axes, a spline along its length.

`Wall` is the default and `Span` is the fallback: a perimeter with no
straight run in it is squared to its span and says so, rather than
asking a question with one answer.

When the runner-up wall is as long as the longest one but points
somewhere else, the run says so — squaring to one of them is then a
choice and not a measurement. Two long sides of a rectangle are the same
length *and* the same direction, so that is not reported: either one
gives the same drawing.

## What it does not do

Nothing is scaled, mirrored, moved, drawn or erased, and no layer,
colour or style is touched: the drawing that comes out is the drawing
that went in, turned. The turn is one `ROTATE` inside one undo group, so
a single `U` puts it back.

Two things it refuses to do quietly:

* a drawing already square — under `sq:*square-deg*` off — is left alone
  entirely rather than turned by a millionth of a degree onto the
  drafter's undo stack;
* a perimeter picked from **outside** the highlight would stand still
  while everything else turned round it, so that is asked about before
  anything moves.

## Locked and frozen layers

`ROTATE` skips an object on a locked or frozen layer and says nothing
about it. A run that ignored that would turn the outline and leave the
base plan it was traced over lying at the old angle — half a drawing
squared and half not, which is worse than a drawing that was never
squared at all, because the second is obvious and the first is not.

So both bits are cleared for the length of the turn and put back exactly
as they were, on the failed path too, and the summary says how many
layers were borrowed. (A layer that is merely *off* is not in this: its
objects are invisible but every editing command still works on them.)

## Horizontal means horizontal on the screen

The current UCS's X axis, not the world's. A drafter working under a
rotated UCS means the direction they can see, so the measurement is
taken in the UCS — entity points come out of the drawing in WCS or in
their own OCS, and both are converted on the way in — and `ROTATE` turns
in the same one. `AUNITS`, `ANGBASE` and `ANGDIR` are zeroed for the
call and put back, because `ROTATE` reads its angle through all three
and a drawing set to clockwise angles would otherwise turn the measured
number the wrong way.

## Tunables

Drawing units are assumed to be **inches** (architectural). Every knob
sits in the tunables block at the top of `SQUAREUP.lsp`, each with its
explanation beside it; change a value there, or `setq` it after loading
from a startup file:

| Variable | Default | Meaning |
| --- | --- | --- |
| `sq:*arcsegs*` | `12` | How many chords an arc is measured as when the **span** is worked out. Raise it and a big sweeping arc's widest point is found more exactly; it has no effect on `Wall` |
| `sq:*fuzz*` | `0.02` | How close two points have to be to count as the same one — what decides whether two straight pieces *touch* and so can be one wall. Raise it for a trace whose pieces do not quite meet |
| `sq:*collinear-deg*` | `1.0` | How far two touching pieces may differ in direction, in **degrees**, and still be read as one wall. Measured against the run so far, so a bowing chain cannot creep round a corner |
| `sq:*square-deg*` | `0.01` | Under this many **degrees** out, the drawing is already square and nothing is turned. Not a precision knob — it is what stops a run that would change nothing spending the drafter's undo |
| `sq:*tie-frac*` | `0.02` | How close in length the runner-up wall has to be before the tie is reported. `0` never reports one |
| `sq:*tie-deg*` | `2.0` | …and how far apart in **degrees** the two have to point for that tie to be worth mentioning |
| `sq:*about*` | `'perimeter` | What the drawing turns about: `'perimeter` is the middle of the perimeter's extents, which keeps the pool where it is on screen; `'work` is the middle of everything highlighted |

`sq:*curvetypes*`, `sq:*sysvars*`, `sq:*sysold*` and `sq:*held*` are not
knobs and do not live in that block. The first is the set of entity
types `sq:ent-spans` can actually read — adding a name to it lets one
through that measures as nothing — and the other three are the sysvars
and layer flags a run borrows and gives back.

## Tests

```
python3 tests/test_squareup.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_squareup.py # grouped tier
```
