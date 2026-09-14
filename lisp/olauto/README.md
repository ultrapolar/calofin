# OLAUTO -- overlay two pool perimeters at the least error (AutoLISP / AutoCAD 2018+)

A pool gets measured twice: once when the liner now in it was made --
that outline is the **original**, drawn as the bead track the liner
hooks into -- and once just now, giving the **new** perimeter. The two
drawings never arrive in the same place on the sheet and never at the
same angle, so before anyone can say whether the new measurement agrees
with the pool that already exists, one has to be laid over the other.

*How* it is laid over is the whole question. Slide it one way and the
deep end lines up while the steps are out by three inches; slide it back
and the fault moves to the other end. Done by eye, the answer depends on
who did the sliding. OLAUTO finds the one position -- the one rotation
and the one translation -- where the total disagreement is as small as
it can be made, and dimensions what is left.

What is left is the news. A perfect overlay with a 3" gap at the shallow
end is not a bad overlay: it is a pool that is 3" out of shape there,
and a liner cut to the new perimeter will fight the track at that spot.

## What it does

1. **Select the first perimeter**, then **the second**. Either can be
   one `LWPOLYLINE` / `POLYLINE`, or the same shape exploded into
   `LINE`s and `ARC`s (a `CIRCLE` counts, for a round spa). Exploded
   geometry is walked back into a ring nearest-end first, the same
   reader [ABCURCHECK](../abcurcheck/) and [ABHD](../abhd/) use, so a
   perimeter reads the same in all three.
2. **Say which one is the NEW perimeter.** The layers answer this before
   it is asked: a selection already sitting on `POOL` is the new one and
   one on `Bead Track` is the original, so the question comes up with
   the answer in the angle brackets and Enter takes it.
3. **Say which one should move.** The other stays exactly where it is.
   The default is `New`, because the original is the pool that exists
   and the rest of the sheet is drawn around it.
4. OLAUTO fits, moves that one perimeter, puts the new onto `POOL` and
   the original onto `Bead Track`, and draws the dimensions.

Back at the move question re-asks which one is new; Back at *that* one
re-opens both selections, because nothing has been drawn yet and a
selection cannot be armed with `initget`, so Back cannot be typed at
one. Re-selecting throws away everything the first pass worked out, so
the second starts clean.

### The fit is RIGID -- it never scales

The fit may turn and slide a perimeter and nothing else. This is the
single most important thing about the command. A fit allowed to stretch
one outline onto the other would absorb the one error nobody can afford
to miss -- a pool measured 2% long -- into the fit itself and report a
clean overlay. So a size difference stays a size difference and comes
out in the dimensions, where somebody sees it.

`tests/test_olauto.py` pins this with a circle of radius 60 laid over
one of radius 50: the answer has to be 10 everywhere, not zero.

### How the best overlay is found

Two stages, because neither works alone.

**1. Phase search.** Both perimeters are walked out into the same number
of points spaced evenly *by arc length*. Two outlines of one pool then
correspond point for point, up to where the walk started and which way
round it went. Every starting offset and both directions are tried; for
each, the best rotation and translation follow in closed form (the 2-D
Kabsch solution), so a whole candidate costs one pass and nothing
iterates. Because the two point sets and their centroids do not change
as the offset slides, scoring a candidate reduces to one running sum.

**2. ICP polish.** From that pose, every point is re-matched to the
nearest *place* on the other curve rather than to its opposite number,
the transform is re-solved, and it repeats until nothing moves.

Stage 1 is there because stage 2 alone is a local search and a pool is
nearly symmetric. Started at the wrong angle, plain ICP settles happily
into a fit five times worse and reports it as the answer -- measured, on
the drawing this command was written from: starting rotations of 90 to
270 degrees converged to an RMS error of 20 to 48 against the right
answer's 1.36. Started from the phase search it lands on the same fit
from any angle the two drawings happen to arrive at, which is the
property that makes the result worth putting a dimension on.

The polish looks for each point's match only among the spans within
`ola:*icp-win*` of that point's own index. That window sits on the index
rather than chasing the last match because the correspondence never
slides more than a sample or two from where the phase search put it
(measured: one sample, on the reference drawing). It is what keeps the
polish affordable -- the whole pass walks one pointer down a doubled
copy of the fixed walk, with no indexing and no re-walking.

### What gets dimensioned

The error is measured at `ola:*devpts*` points along the **original** --
the one that did not move, so the dimensions hang off geometry that is
still exactly where the drawing put it -- and against the real arcs of
the new perimeter rather than a chord standing in for them.

The worst spots are then taken greedily: the biggest error anywhere,
then the biggest that is still `ola:*peak-gap*` of the perimeter clear
of it, and so on up to `ola:*dimcount*`. The separation is what makes
four dimensions describe four problems; without it, one long bad stretch
takes every slot and the other three faults on the pool go undrawn.

Two floors keep noise out. A spot under `ola:*peak-min*` outright is not
worth the ink, and neither is one under `ola:*peak-share*` of the worst
error found -- a fit always leaves a little residue spread around the
perimeter, and without that second floor a pool with one real 3" fault
gets that fault dimensioned and then three more dimensions reading
1/16", which says "four problems" about a pool that has one.

Each is one aligned dimension between the point on the original and the
nearest point on the new perimeter, on layer `DIMENSION` in the
`STANDARD INCHES` style, with the text dragged clear along the line the
two points make -- the gap being measured is an inch or two on a
forty-foot pool, so the text cannot live where the dimension line is and
still be read. The dimension line itself stays on the geometry, so a
reading can be traced back to the two points it came from.

The run finishes by reporting the fit as three numbers -- worst, average
and RMS -- so two candidate measurements of the same pool can be
compared on something other than an opinion.

## Install & run

APPLOAD `OLAUTO.lsp` (or load the whole build with
`shared/LAZPASS.lsp`), then type `OLAUTO`.

| Command | What it does |
| --- | --- |
| `OLAUTO` | overlay two perimeters and dimension the worst error |
| `OLAUTOVER` | print the loaded version |

## Tunables

Every knob is read when the command runs, not when the file loads, so
`(setq ola:*dimcount* 6)` at the command line changes the next run.

| Knob | Default | What moves when you change it |
| --- | --- | --- |
| `ola:*new-layer*` | `"POOL"` | where the new perimeter is put on the way out |
| `ola:*og-layer*` | `"Bead Track"` | ...and the original |
| `ola:*dim-layer*` | `"DIMENSION"` | the layer the error dimensions land on |
| `ola:*new-color*` | `3` | ACI used only if `POOL` has to be created |
| `ola:*og-color*` | `1` | ...only if `Bead Track` has to be created |
| `ola:*dim-color*` | `7` | ...only if `DIMENSION` has to be created |
| `ola:*dim-style*` | `"STANDARD INCHES"` | the dimension style; a drawing without it keeps its own and is told so |
| `ola:*dimcount*` | `4` | how many of the worst spots get a dimension |
| `ola:*peak-gap*` | `0.07` | how far apart two dimensions must be, as a fraction of the perimeter -- raise it to spread them |
| `ola:*peak-min*` | `0.0625` | an error under this (1/16") is not dimensioned at all |
| `ola:*peak-share*` | `0.10` | nor is one this much smaller than the worst error found; `0.0` lets `ola:*peak-min*` alone decide |
| `ola:*text-push*` | `0.045` | how far the dimension text is dragged clear, as a fraction of the perimeter's bounding-box diagonal |
| `ola:*fitpts*` | `96` | samples per perimeter for the fit; the phase search costs this **squared**, so it is the one knob worth money. 48 is enough for a spa |
| `ola:*devpts*` | `240` | samples along the original where the error is measured; higher finds a narrow spike a coarser walk steps over |
| `ola:*icp-win*` | `6` | how far along the curve the polish may look for a better match. Widening costs time and buys nothing; under about 3 can pin the fit before it has settled |
| `ola:*fit-tol*` | `0.001` | the polish stops when no point moved further than this |
| `ola:*fit-max*` | `60` | ...or after this many passes, whichever comes first |
| `ola:*fuzz*` | `1.0e-4` | closer than this and two ends are the same point (ABHD's `*PF-CHAIN-FUZZ*`); it also decides whether a chain came out closed |

## Notes & limitations

* **Rigid only, by design.** See above -- this is a feature and the
  tests enforce it.
* **Both perimeters must be the same shape**, near enough that walking
  them by arc length lines them up. Two outlines of one pool are; a pool
  and a spa are not, and the command will still produce its least-error
  answer for them, which will be meaningless. The reported RMS is the
  number to sanity-check that with.
* **The fit is sampled, so it has a floor.** The polish matches points
  against the chords between samples, not against the arcs, so the pose
  it settles on can sit a fraction of a chord's sagitta off the true
  best. Two outlines walked from corresponding starting points come out
  exact; ones that do not -- the same shape drawn the other way round,
  say -- leave a residue of that order. Measured on a 616" test
  perimeter at the default 96 samples: 0.065", about a hundredth of a
  percent, against the 20-to-40-unit error a fit with no direction
  search would have reported. Raising `ola:*fitpts*` shrinks it
  quadratically if a job ever needs it to.
* **Open perimeters work**, and are fitted end to end with no cyclic
  search -- a bead track that stops at the steps is still a perimeter to
  overlay. Both have to be open, or both closed, for the cyclic half of
  the phase search to be in play.
* The perimeter is moved by rewriting its entities with `entmod` rather
  than driving `MOVE` and `ROTATE`. Two commands would round the
  geometry twice through the command line and leave the result depending
  on snaps and on the current UCS. A rigid transform leaves a bulge
  alone -- a bulge is a shape, not a position -- so only points and arc
  angles move.
* Only the five curve types the selection filter admits
  (`LWPOLYLINE`, `POLYLINE`, `LINE`, `ARC`, `CIRCLE`) are read and
  moved. A perimeter drawn as a `SPLINE` or an `ELLIPSE` is not picked
  up, and geometry inside a block is not reached.
* Everything is read and written in WCS, 2-D. A perimeter drawn on a
  tilted UCS or with a non-`(0,0,1)` extrusion is outside what this
  reads, as it is for the rest of the tree's geometry tools.
* **The fit takes a moment.** The polish is the cost -- on the order of
  forty passes over the sampled perimeter -- and it is the reason
  `ola:*fitpts*` is worth knowing about if you run this on spas.

## Tests

```
python3 tests/test_olauto.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_olauto.py # grouped tier
```

The shapes are chosen so the right answer is known in closed form: two
equal circles have exactly one best overlay and zero error at it,
whatever pose they start from; a circle of radius R over one of radius
R+D is D away at every point; a rectangle carries its own corners, so a
recovered rotation can be checked to the degree; and a shape with two
bumps has two known peaks, which is what the separation rule has to find
instead of dimensioning the bigger one twice.
