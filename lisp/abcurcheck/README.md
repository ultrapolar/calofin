# ABCURCHECK -- grade how continuous a drawn pool perimeter is (AutoLISP / AutoCAD 2018+)

A fork of [ABHD](../abhd/)'s geometry reader, pointed the other way.
ABHD **builds** a smooth perimeter through surveyed points; ABCURCHECK
**measures** one that already exists and says how continuous it is --
as a word a drafter can act on, not a pile of numbers.

## What it does

Select a closed perimeter -- one `LWPOLYLINE` / `POLYLINE`, or the same
shape exploded into `LINE`s and `ARC`s (a `CIRCLE` counts, for a round
spa). Exploded geometry is walked back into a ring nearest-end first;
unlike ABHD's chainer this never bails on a gap, because measuring the
gap *is* the job.

Continuity is a ladder, and each rung catches a different kind of bad
drawing.

### G0 -- does it close?

Endpoint gaps between segments, zero-length segments, segments drawn
twice, and chords that cross. A trace exploded and rejoined by hand is
riddled with sub-1/16" gaps that look perfect on screen and break every
tool downstream. Any of these caps the grade at **Broken**.

The signed turning total is reported alongside: a simple closed loop
turns exactly 360 degrees, kinks included, so a total that is not 360
means the outline doubles back on itself whether or not two chords
happen to cross.

### G1 -- tangent breaks

At every joint, the signed angle between the arriving tangent and the
leaving one. The bands are ABHD's own constants, so the two commands
agree on what "smooth" means:

| Turn | Band | Reading |
| --- | --- | --- |
| <= `acc:*tangent-eps*` (0.5 deg) | tangent | clean |
| <= `acc:*kink-tol*` (8 deg) | soft break | reads smooth |
| <= `acc:*corner-ang*` (45 deg) | **visible kink** | **the problem** |
| > `acc:*corner-ang*` | corner | meant, if declared |

That 8--45 band is the whole point of the command: too big to look
smooth, too small to read as an intentional corner. It is the kink a
fabricator finds in the bead and nobody meant to draw.

### Noise -- the metrics that catch a *traced* perimeter

A traced outline is tangent everywhere and still wrong, so three
measures run past the joints:

* **micro-segments** -- how many segments are shorter than
  `acc:*micro-len*` (3"), and what share of the perimeter sits in them;
* **inflections** -- how many times the curvature changes sign;
* **turning excess** -- for any simple closed loop the *signed* turning
  is exactly 360 degrees, while the *absolute* turning (every arc sweep
  and every kink added up regardless of direction) is at least that,
  and equal only for a convex shape. So

  ```
  excess = (total absolute turning / 360 deg) - 1
  ```

  is one scale-free number folding kinks and wiggle together: 0 for an
  oval, a few tenths for a kidney's concave run, well over 1 for a
  noisy trace.

## Declared discontinuities

The user picks the breaks that are *meant* to be there -- a step
corner, a spa dam wall, a beach entry. One pick does three jobs:

* it snaps to the nearest joint within `acc:*snap-dist*` and takes that
  joint out of the grade, listing it separately with its measured
  angle, so a 90 degree corner stops dragging the score down;
* a pick that lands nowhere near a joint is reported the other way
  round -- *declared here, but the geometry is continuous*;
* everything left over is the real output: the **undeclared**
  discontinuities, which is the list to go and fix.

Declarations are dashed green rings on `POOL-CONT`, stamped as this
command's own, so a second run remembers what the first was told.
`Add` / `Remove` / `Keep` edits them.

## The verdict

Two numbers, on purpose:

* the **grade** -- `Broken`, `Rough`, `Fair` or `Smooth` -- is set by
  the single worst thing found and names it, because a drafter has to
  know why. A weighted blend would be easier to compute and impossible
  to argue with, which is the wrong way round for a drawing check.
* the **index** (0--100) is a weighted blend of integrity, tangency and
  noise. It settles nothing on its own and exists to compare two
  candidate perimeters against each other.

## The curvature comb

The qualitative answer in a form nobody needs a table to read: a tooth
at every sample, its length proportional to curvature and its side set
by which way the curve turns, with the tips strung into one envelope on
`POOL-COMB`. Every tangent break is a step in that envelope, every
noisy stretch a fuzzy one, and every inflection a crossing.

Lines and arcs are never truly curvature-continuous, so the steps at a
line-to-arc joint are expected -- the comb shows their *size*, which is
the part that matters.

## Install & run

`APPLOAD` `ABCURCHECK.lsp` (or the dated twin in [`releases/`](../../releases/)),
then:

| Command | What it does |
| --- | --- |
| `ABCURCHECK` | measure a perimeter, mark it, report |
| `ABCURCHECKSCAN` | the same measurement, nothing drawn |
| `ABCURCHECKRESCUE` | erase the marks (`Marks`), or the declarations too (`All`) |
| `ABCURCHECKVER` | print the loaded version |

Findings are ringed on `POOL-CONT` -- red for a gap or a visible kink,
yellow for an undeclared corner -- and labelled with the measured
angle. Only what fails is marked: a ring on all 47 joints of a normal
polyline says nothing, and a drawing nobody can read is a check nobody
runs.

## Tunables

Every threshold is a global at the top of the file.

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*tangent-eps*` | `0.5` | deg -- at or under this a joint is tangent |
| `acc:*kink-tol*` | `8.0` | deg -- ABHD's `*PF-TANG-TOL*` |
| `acc:*corner-ang*` | `45.0` | deg -- ABHD's `*PF-CORNER-ANG*` |
| `acc:*micro-len*` | `3.0` | shorter than this is a micro-segment |
| `acc:*micro-share*` | `0.10` | micro share that costs the whole noise score |
| `acc:*close-tol*` | `5.0` | deg the signed turning may sit off 360 |
| `acc:*snap-dist*` | `6.0` | how near a declaration pick must land to a joint |
| `acc:*fuzz*` | `1.0e-4` | closer than this and two ends are the same point |
| `acc:*cross-max*` | `300` | segments above which the crossing scan stands down |
| `acc:*comb-step*` | `12.0` | one comb tooth per foot of run |
| `acc:*comb-max*` | `24.0` | tooth length at the tightest curvature in the loop |
| `acc:*excess-free*` | `0.35` | turning excess a freeform pool is owed... |
| `acc:*excess-cap*` | `1.00` | ...and where the noise score reaches zero |
| `acc:*w-integrity*` / `*w-tangency*` / `*w-noise*` | `40` / `35` / `25` | index weights |
| `acc:*mark-layer*` / `*comb-layer*` | `POOL-CONT` / `POOL-COMB` | output layers |

The two excess bounds and the micro share are the values most worth
recalibrating against real drawings; the tangent bands are ABHD's and
should move only if ABHD's do (`tests/test_abcurcheck.py` fails if they
part company).

## Notes & limitations

* **Curvature jumps are drawn, not scored.** A polyline of lines and
  arcs can never be curvature-continuous, so grading it on that would
  fail every honest drawing. The comb shows the jumps; the grade
  ignores them.
* **Crossings are tested on segment chords**, so a bulged pair that
  overlaps only through its arcs is caught by the signed-turning total
  instead of by name. The scan is quadratic and stands down above
  `acc:*cross-max*` segments -- the report says when it did, rather
  than reporting "no crossings" from a scan that never ran.
* **A two-vertex closed polyline is a valid perimeter here**, where
  ABHD wants three: a round spa is drawn as two bulged vertices, and
  dropping its closing span would turn the smoothest shape in the
  drawing into a 180 degree kink.
* Everything is measured on the 2D plane; Z is ignored.

## Tests

```
python3 tests/test_abcurcheck.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_abcurcheck.py # grouped tier
```

The shapes are chosen so the answer is known in closed form -- a circle
split into two arcs whose second bulge is `tan((90-t)/2)` kinks by
exactly `t` degrees at both joints, which is what lets the band edges
be tested to the degree.
