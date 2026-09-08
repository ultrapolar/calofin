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

Every value ABCURCHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `ABCURCHECK.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**Where the marks go**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*mark-layer*` / `acc:*comb-layer*` / `acc:*mark-color*` / `acc:*comb-color*` / `acc:*gap-color*` / `acc:*corner-color*` / `acc:*decl-color*` | `"POOL-CONT"` / `"POOL-COMB"` / `3` / `4` / `1` / `2` / `3` | findings and declarations go here; the curvature comb goes here; ACI: the marks layer (green); ACI: the comb layer (cyan); ACI: a gap, or the kink band (red); ACI: an undeclared corner (yellow); ACI: a declared break (green) |
| `acc:*appid*` | `"ABCURCHECK"` | Everything ABCURCHECK draws carries xdata under this name, so a rescue erases only its own work off a layer the drawing may already be using. Renaming it orphans what earlier runs left behind -- including the declarations a later run is supposed to remember |
| `acc:*dash-name*` / `acc:*dash-on*` / `acc:*dash-off*` | `"DASHED"` / `12.0` / `6.0` | The dashed linetype declarations are ringed with, and its pattern: dash, gap, and the total the two must add up to. It is created at pool scale so the dashes read on a 40-foot perimeter (drawing units of dash; ...and of gap) |

**G0: is the loop closed at all**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*fuzz*` | `1.0e-4` | Closer than this and two ends are the same point -- ABHD's *PF-CHAIN-FUZZ*. Raising it forgives sloppier joins; a gap over it is a finding in its own right and the worst thing the grade can carry (drawing units) |
| `acc:*close-tol*` | `5.0` | The signed turning of a simple closed loop is 360 degrees. This is how far off that the total may sit before the loop is called self-crossing (degrees) |
| `acc:*cross-max*` | `300` | The crossing scan compares every segment with every other, so it is skipped above this many segments -- and the report says it was skipped rather than pretending it ran (segments) |

**G1: how sharply a joint may turn**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*tangent-eps*` | `0.5` | At or under this a joint is TANGENT -- the two sides run on into each other and there is nothing to report (degrees) |
| `acc:*kink-tol*` / `acc:*corner-ang*` | `8.0` / `45.0` | The most a joint may turn and still read as smooth, and the angle over which it stops being a kink and becomes a corner. Both are ABHD's (*PF-TANG-TOL* and *PF-CORNER-ANG*): the 8-45 band is the one a fabricator finds in the bead, which is why it leads the grade. Move them only when ABHD's move -- the test fails if they part (degrees) |

**Noise: what a traced outline leaves behind**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*micro-len*` | `3.0` | A segment shorter than this is a micro-segment, the signature of an outline traced by hand rather than drawn (drawing units) |
| `acc:*micro-share*` | `0.10` | The share of the perimeter sitting in micro-segments that costs the whole noise score. Lower it and a lightly traced outline is punished harder (fraction of the perimeter) |
| `acc:*excess-free*` / `acc:*excess-cap*` | `0.35` / `1.00` | A freeform pool turns more than 360 degrees in total because it weaves; FREE is the excess it is owed before the noise score starts to fall, and CAP is where that score reaches zero. These two are the values most worth recalibrating against real drawings (turns beyond one full turn; ...and where it reaches zero) |

**The 0-100 index**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*w-integrity*` / `acc:*w-tangency*` / `acc:*w-noise*` | `40.0` / `35.0` / `25.0` | What each half of the check is worth. The three are summed and printed as the denominator, so they need not add to 100 -- but the grade word is set by the single worst thing found, not by the index, and these weights do not move it (G0: gaps, doubles, crossings; the kink and corner bands; micro share and turning excess) |

**Picking and marking**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*snap-dist*` | `6.0` | How near a pick must land to a joint to declare it -- or, on Remove, to drop the declaration nearest the pick (drawing units) |
| `acc:*mark-radius*` | `4.0` | Radius of the rings drawn round a finding or a declaration (drawing units) |

**The curvature comb**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*comb-step*` / `acc:*comb-max*` | `12.0` / `24.0` | One comb tooth per this much run, and the length of the tooth at the tightest curvature in the loop -- every other tooth is scaled against that one, so the comb is a picture of relative curvature (drawing units per tooth; drawing units at the tightest bend) |

**The finding labels**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*label-min*` / `acc:*label-div*` | `4.0` / `200.0` | Label text is sized against the perimeter, so it reads the same on a 20-foot spa and a 60-foot pool: perimeter/DIV, but never under MIN (drawing units; perimeter divided by this) |

**Numerical guards (rarely changed)**

| Global | Default | Meaning |
| --- | --- | --- |
| `acc:*flat-curv*` / `acc:*flat-tooth*` | `1.0e-12` / `1.0e-6` | A curvature below this is straight, so the comb is not drawn at all; a tooth shorter than this is not drawn either (1/drawing units; drawing units) |
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
