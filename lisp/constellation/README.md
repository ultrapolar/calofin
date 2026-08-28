# CONSTELLATION — Points placed from the dims between them (AutoLISP / AutoCAD 2018+)

A site sheet that gives distances **between** points and never says where
any of them is. A tape run corner to corner, corner to skimmer, skimmer
to light — fourteen numbers and no origin.

Every other calofin importer wants coordinates. `XYPLOT` is handed an X
and a Y and only has to draw them; `ABCDEF` is handed offsets off a
known baseline. CONSTELLATION is handed only the web of distances and
has to work the positions out.

## What it does

1. **Asks for the space.** A rectangle of known X and Y that the points
   have to sit in — the yard, the deck, the envelope the pool has to
   land inside. It is asked first because it also sets the **scale** of
   the first guess: without it the solver has no idea whether this is a
   12-foot spa or a 60-foot pool. The base point is the rectangle's
   lower-left corner.
2. **Asks how many points**, labelled `A`, `B`, `C` … up to `Z`.
3. **Draws the starting layout**, before a single dim is asked for: the
   points evenly spaced round the oval inscribed in the space, running
   **clockwise from the top left**. Nothing about it is a measurement —
   it is the legend, so you can see which letter is which before naming
   a pair. It is erased again the moment the real positions are known.
4. **Takes the cross dims.** Every pair — `A-B`, `A-C`, `A-D` … — is on
   offer and **none is compulsory**. A field sheet almost never carries
   all of them; the point is to let you enter the ones it does carry, in
   whatever order they are written down.

   | At the pair prompt | What it does |
   | --- | --- |
   | Enter | takes the pair shown — the first still blank, so Enter over and over walks the whole chart in order |
   | `A-C` | jumps straight to that pair (`AC`, `a c` and `C-A` read the same) |
   | `D` | done, no more dims |
   | `B` | blanks the dim just given, and offers that pair again |

   What **is** required is two dims on every point, and a chain of dims
   that reaches all of them. Answering `D` short of that is refused by
   name, not solved into a plausible-looking wrong answer.
5. **Takes the arcs.** If a run of points lies on one radius, say so.
   Cross dims say how far apart things are and nothing about how the
   wall between them curves, so a radius end can be measured perfectly
   and still come out as a flat chord. See **Arcs** below.
6. **Solves, then draws**: an `ab_pt` survey point per letter on
   `POINTS`, one aligned dimension per dim given on `DIMENSION`, the
   space rectangle, and — if you say yes — the outline through the
   points in label order, bending round any arc you declared.
7. **Asks whether it looks right.** A number typed wrong is the
   ordinary case, not an exception: you cannot tell 24'-6" was meant to
   be 24'-9" from the chart, but you can tell at a glance from the
   drawing. So the drawing *is* the check. Answer `No` and it asks
   whether the **Dims**, the **Arcs** or **Both** need changing,
   reopens them, takes the corrected value — a pair or a run given
   again keeps the second answer — takes the wrong drawing away and
   puts the right one down. Round again as many times as it takes.

## Arcs

A run of points that lies on one radius. Name it **clockwise**, the way
the letters were handed out:

| Typed | Reads as |
| --- | --- |
| `A-C` | from A clockwise to C, so A, B, C |
| `ABC` | the same run, spelled out |
| `AC` | the same again — separators are ignored |
| `Z-B` | wraps round the end: Z, A, B, **not** B all the way back to Z |

Two letters are a *from* and a *to* with the run between them filled in;
three or more are taken as named. That is the whole reason the order is
asked for clockwise — `B-D` and `D-B` are different runs, and the
letters say which.

**To the solver an arc is just another point.** Its centre joins the
layout as an extra, unlabelled point with a dim of `R` to every point on
the arc — which is exactly the shape the sweep already knows how to
settle, so nothing special had to be built for it. The centre is never
drawn and never steers the fit: it is left out of the bounding box and
the clockwise test, because a shallow radius puts its centre further out
than the pool is long.

**It really does constrain.** Six dims on five points is one short of
pinning them down, and the three points on the radius end settle at
R139.6 — wrong, with every dim given still exact. Declare the arc and
they land on R150.0000. That case is `test_an_arc_pins_what_dims_alone_leave_loose`.

**Three points or more settle their own centre.** A circle of known R
through three points has exactly one centre, so the solver finds it
wherever it starts. Two points leave *two* centres, mirror images across
the chord, and nothing in the distances chooses between them — so a
two-point run is asked `Does A-B bow out from the shape?` and nothing
else is.

The arc also **shapes the outline**: the segments it covers are drawn as
real arcs (polyline bulges), not chords. A run named out of ring order
still constrains the solve — it is the same circle — but there is no
outline segment for it to bend, so it bends none.

The whole run is one undo group, and nothing permanent is drawn until it
finishes: a run backed out of or cancelled leaves the drawing exactly as
it found it.

## What the solver does

The dims are almost never exactly consistent. A tape reads a sixteenth
long; a corner is measured to the coping instead of the wall. So there
is usually **no** layout that satisfies all of them, and the honest
answer is the one that misses by as little as possible.

It is found in two stages, because the two halves of the job want
different tools.

**Stage 1, sweeps — finding the right answer.** Weighted stress
majorization (the Guttman transform). One sweep moves every point to the
average of where each dim touching it wants it to be — dim `A-C` of 168
wants `A` to sit 168 from wherever `C` currently is, along the line the
two currently make. Averaging is what makes a sweep safe: the total
error can never rise, so a sweep can be trusted from any start at all.

`POOL`'s `pool:relaxn` sweeps its constraints one at a time instead,
each pulling its two points a share of the way. That is right for a quad
with six constraints on four points. It is wrong here: a 26-point job
carries up to 325 dims and a point can be in 25 of them, so a sequential
sweep spends its time undoing what the previous constraint just did.

**Stage 2, Levenberg–Marquardt — finding it exactly.** What sweeps are
bad at is the last few decimal places. They converge linearly, at a rate
set by how loosely the chart ties the points together, and a chart that
is only just rigid — a ring with a couple of diagonals, which is a very
ordinary field sheet — can need many thousands of them.

Stopping at a fixed sweep count looks like it works. Every dim comes
back close, and the report blames the tape whose dim came back least
close. **That is the worst failure this command could have**, because it
sends someone out to re-measure a tape that was right. Measured, on
ring-plus-two-diagonals charts: 400 sweeps left a given dim `0.19"` out
on data that has an exact answer, and getting it to a thousandth took
**14,440**.

So the same problem is then written as what it is — least squares over
the residuals `(distance drawn) − (distance given)` — and finished by
damped Gauss–Newton. Each residual touches only the four numbers that
are its two points' x and y, and its slope in each is just the unit
vector along the line, so the normal equations are cheap to build and
the step is a linear solve. Near the answer that doubles the number of
correct digits every iteration where a sweep adds a fixed small fraction
of one: those fourteen thousand sweeps become **seven iterations**.

The damping is not optional. A constellation is free to slide and to
spin, so three directions change nothing at all and the undamped normal
equations are singular no matter how good the dims are. It also keeps
the step honest far from the answer — a step that does not reduce the
total miss is thrown away and retried with more damping — so stage 2 can
never leave the fit worse than the sweeps did.

`test_a_barely_rigid_chart_still_holds_every_dim` is the regression: the
exact chart that used to come back `0.19"` out now comes back exact.

The report then prints, per dim, what was given, what the drawing came
out at, and the difference — and **stars** any that missed by more than
`cst:*flag*`.

### Which dim is the wrong one

Least squares **spreads** a bad tape. One dim read three inches long
does not come out three inches wrong: the fit gives a little on every
dim that touches those two points, so ten dims each end up a bit out and
the report stars all ten and names none. That is the arithmetic working
correctly and the answer being no use.

So when something is starred, the worst dim is left out and the chart is
solved again. If everything else then comes into line, that one dim was
carrying the error by itself and the report says so by name:

```
  ** The starred dims cannot all be true at once.  The
  ** layout misses them by as little as anything can.
  ** Leave A-C out and every other dim settles to within 0.0002,
  ** so A-C is the one to re-measure - the rest are only wrong
  ** because the fit shared its error out among them.
  ** Nothing was dropped: the layout drawn still honours every dim given.
```

`ABCDEF` makes the same argument about dropping its fourth tape. The
test is only run when there is something to explain **and** something to
spare: below the flag nothing is wrong, and a chart with no redundancy
has no second opinion to offer — drop a dim there and the error simply
moves somewhere else, so nothing is named. **This is exactly what the
optional extra pairs buy you**: a chart with only enough dims to pin the
shape down absorbs a bad tape silently, because there is nothing left
over to disagree with it.

Nothing is ever dropped from the drawing — the layout on the sheet
honours every dim the operator gave.

### Two things distances cannot settle

**Which way round.** A constellation and its mirror image satisfy
exactly the same distances. You were shown `A`, `B`, `C` running
clockwise, so the mirror that reads clockwise is the one drawn.

**Which way up.** Distances are rotation-blind too. The result is turned
to sit inside the space — and among the angles that fit, to land as near
as it can to the oval you were shown, so the letters stay roughly where
the preview put them. It is then centred in the rectangle.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `CONSTELLATION.lsp`. Add it to the *Startup Suite* to have it in
   every drawing.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `CONSTELLATION` | Place labelled points from the dims between them |
   | `CONSTELLATIONVER` | Print the version |

The points it draws are the same `ab_pt` blocks on `POINTS` that
`ABCDEF` and `XYPLOT` import, so `ABHD`, `CABHD`, `ABFIND`, `LHD` and
`BPCALLOUT` read the result untouched — run `ABHD` next to fit a pool
perimeter through it.

## Tunables

`setq` these after loading (in a startup file, say) when a drawing works
at a different size:

| Variable | Default | Meaning |
| --- | --- | --- |
| `cst:*minpts*` / `cst:*maxpts*` | `3` / `26` | Points allowed. Three is the floor — two points share one dim and neither then has the two a placement needs. Twenty-six is the ceiling because the labels are single letters |
| `cst:*defcount*` | `4` | What Enter takes at the count prompt |
| `cst:*sweeps*` | `120` | Cap on stage-1 sweeps. They only have to reach the right *basin* now, which takes a few dozen; stage 2 finishes the fit |
| `cst:*tol*` | `1.0e-6` | Movement per sweep, in drawing units, below which stage 1 stops early |
| `cst:*lm-iters*` / `cst:*lm-tries*` | `40` / `8` | Stage-2 iterations, and the damping retries inside one of them |
| `cst:*lm-lam*` / `cst:*lm-lammin*` | `1.0e-3` / `1.0e-12` | Starting damping, and the floor it may fall to |
| `cst:*lm-done*` | `1.0e-14` | Sum of squared misses below which there is nothing left to gain (about a ten-millionth of an inch, RMS) |
| `cst:*squash*` / `cst:*shake*` | `0.35` / `0.30` | The second and third starting layouts — the oval flattened, and the oval scattered. A stress minimum is *local*, and a constellation that starts folded can stay folded, so the oval is not the only thing tried. With arcs declared each start is run twice more, once with the arcs in from the beginning and once with the dims settled alone first, because neither order wins every job; the closest of all of them is kept |
| `cst:*rot-coarse*` | `360` | Steps in the whole-circle turn-to-fit sweep |
| `cst:*rot-fine*` / `cst:*rot-passes*` | `40` / `3` | The refining passes after it, each sampling one grid spacing either side of the last winner |
| `cst:*flag*` | `0.25` | A dim missing by more than this is starred. At a sixteenth of an inch nobody re-measures; at a quarter something is wrong with the sheet |
| `cst:*texth*` / `cst:*dotr*` / `cst:*dimoff*` | `0.025` / `0.008` / `0.060` | Label height, preview marker radius and perimeter-dim stand-off, as shares of the smaller side of the space |
| `cst:*space-layer*` | `"CONSTELLATION-SPACE"` | The rectangle asked for |
| `cst:*guide-layer*` | `"CONSTELLATION-GUIDE"` | The starting oval — erased on the way out |
| `cst:*outline-layer*` | `"CONSTELLATION"` | The ring through `A B C` … |
| `cst:*dim-layer*` / `cst:*point-layer*` | `"DIMENSION"` / `"POINTS"` | As `AUTODIM` and `XYPLOT` use them |

## Notes & limitations

* **The space is a rectangle.** A yard that is not one has to be
  bounded by the smallest rectangle that holds it, and the result
  checked by eye. Nothing here fits an arbitrary boundary.
* **The space is not a hard constraint**, it is the scale and the
  frame. If the dims describe something bigger than the rectangle, the
  constellation is drawn centred and overhanging, and the report says by
  how much — the dims are measurements and the rectangle is a stated
  envelope, so the measurements win and the disagreement gets said out
  loud.
* **A bare-minimum chart cannot catch a bad tape.** With exactly
  enough dims to pin the shape down, any single reading can be
  satisfied exactly, so a mis-read comes back with a clean report — and
  a wrong drawing. It takes redundant dims to notice, which is why
  every pair is on offer even though none is required.
* **A fit can still land on the wrong layout, and it says so rather
  than guessing.** Stage 1 finds *an* answer and stage 2 makes it
  exact, but "an answer" is a local one: a sparse chart with arcs on it
  can have a second layout that satisfies almost everything. Six
  starting layouts are tried and the closest kept, which in a
  192-shape random sweep left about 2% of arc jobs on a wrong local
  answer — none of them dim-only jobs. The symptom is a large worst
  miss that no single dim explains, and the report says exactly that
  rather than blaming a tape. More cross dims are the remedy, and they
  are the remedy for genuinely disagreeing readings too, which is why
  one sentence covers both.
* **Two dims per point is the minimum, not a guarantee of rigidity.**
  Two dims fix a point against two others up to a reflection; a shape
  whose dims are that sparse can have more than one solution and this
  command draws one of them. The more cross dims the sheet carries, the
  less that matters — which is why every pair is on offer. An arc is
  another way to buy the same rigidity.
* **An arc on a chart with slack in it is met, not tested.** Ask for a
  radius the shape has room to bend to and it bends to it, reporting no
  miss — the same redundancy argument as a bad tape on a bare-minimum
  chart. An arc is starred only when the dims leave no room to satisfy
  it.
* **Arcs count toward connectivity but not toward the two-dim rule.**
  Points on one arc really are tied together, through the shared
  centre, so the arc bridges them for the cut-off check. But an arc
  alone never pins a point — it slides along the radius — so it does
  not count as one of the two dims a point needs, and the chart is
  asked before the arcs are.
* **A dim of zero is refused.** Two points at the same place are one
  point; `REQ` entry rejects zero and negatives outright.
* **Dims are weighted equally.** A tape reading is a tape reading;
  there is nothing on a field sheet that says one is better than
  another, so nothing here pretends there is.
* **The dimensions measure the drawn geometry**, with no text
  override — so a dimension that disagrees with its own line in the
  report is a point the dims could not place where the tape said,
  showing up on the sheet rather than only in a log nobody keeps.
* **A crossing outline is reported, not corrected.** The letters go out
  clockwise, so a ring that crosses itself means the dims put the points
  in a different order than the sheet named them — usually two letters
  swapped. Fixing that is a decision about the sheet, not about the
  geometry.
* **A 26-point run is the slow case.** Up to 325 dims pull on 26 points
  and three starts are tried, so a full chart can take a few seconds.
  A pool-sized job — four to eight points — is instant.

## Tests

```
python3 tests/test_constellation.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_constellation.py # grouped tier
```

Drives the whole command in the AutoLISP VM: that a shape which really
exists comes back from its distances, that a partial chart still pins it
down, that handedness comes out clockwise and the fit lands inside the
space, that a point with one dim and a group dimensioned only to itself
are both refused **by name**, that dims which cannot all be true are
starred rather than absorbed and the one bad tape among them is named
rather than smeared, that an arc pins what the dims leave loose and
bends the outline where it should, that `No` at the end reopens the
questions and redraws over nothing, and that the preview leaves nothing
behind.
