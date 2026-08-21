# OASIS — Continuous-tangent pool from an X/Y envelope

An AutoLISP routine for full AutoCAD that draws an **oasis** pool: arcs
and nothing else, no corners and at most one straight run. It is a ring
of **bulges** — circles pinned to the envelope — with a **joiner**
between each consecutive pair, and a joiner is either a smaller
**reverse** arc curving back in, or, when both bulges are tangent to the
same bound, the **straight run** of that bound between them. Every joint
is smooth: the outline changes direction without ever changing tangent,
which is why the whole thing can be given as a handful of radii and two
overall dimensions.

Four families come out of that, and the first question is which:

| | Bulges | The top | The bottom |
| --- | --- | --- | --- |
| **Center** | left, right, top — centred | reverse arcs either side | reverse arc |
| **TopRight** | left, right, top — in the corner | reverse arcs either side | reverse arc |
| **Cloud** | left, right | one reverse arc | flat run or reverse arc |
| **Kidney** | left, right, top-center | **seams** — see below | reverse arc |

The kidney brings the one joint the other families don't have: its two
side circles sit **inside** the big top circle, touching it from within.
At an internal tangency both arcs meet the touch point at the same angle,
so the outline hands straight over with nothing drawn between — a
**seam**. That is why a kidney is four arcs from three bulges and a
single reverse arc.

The two families that come two ways get a second question of their own,
asked straight after. A cloud's bottom is **Straight** — the flat run of
the Y-min bound — or **Rounded**. A kidney is **True** — the top-center
radius is given, and the two *equal* sides are **derived** from having to
touch it — or **Asymmetric** — the two *unequal* sides are given, and the
**top circle is derived**: tangent to the top bound and touching both
sides from outside them, its centre landing wherever those three contacts
put it (leaning toward the bigger side). The pair of answers together
names one of six rings.

Nothing downstream of the solver knows which shape it is looking at — it
reads the ring. The four differ only in how many bulges there are, where
the last one is pinned, and whether the bottom joiner has a radius.

## Simple or complex

Whichever shape it is, the next question is how much of the outline you
want to say. **Simple** is the shape as described above and is the
default, so a plain pool is one Enter longer than it used to be and
nothing else. **Complex** opens two things a real drawing sometimes has
and the plain flow cannot express:

* **A straight run in place of any joiner.** Answer a joiner question
  `Line` instead of a radius and the outline runs dead straight between
  the two bulges' tangent points — their common external tangent. It is
  not a special case bolted onto the ring: a straight run *is* the
  reverse arc with an infinite radius, and grows out of it continuously
  (ten times the radius, a tenth of the gap). The joint stays smooth at
  both ends, because a tangent line meets each circle square to its own
  radius. Answer every joiner `Line` and an oasis comes out as three
  bulges and three straight runs.
* **A hump off centre.** A Center pool's top bulge sits across the
  middle of X; complex asks how far off it is, signed, **left
  negative**. The bulge is still tangent to the Y-max bound — only its
  X moves — so the shape stays a Center pool with the hump where the
  drawing has it.

Two answers are refused, because there is no pool on the other side of
them: an offset that puts the hump's centre off either end of the
envelope, and one that carries the hump far enough across to swallow
the left bulge — a nesting no tangent radius can bridge, exactly as the
centred one is refused. Reaching *past* a bound is not refused: that is
an ordinary trimmed hump, and the extents report names it.

One thing complex can do that simple never could is touch a bulge at a
single point: two runs either side of a bulge that shares a tangent line
with both its neighbours meet it in the same place. The bulge is then a
point on the outline rather than an arc of it. Nothing is drawn for it —
an arc whose two angles are equal is a whole circle to AutoCAD, which is
not what a pinched bulge means — and the report says which bulge it was.

A simple shape's one straight run lies along a bound with both its
bulges tangent to that bound, so nothing can reach it. A complex one's
runs slant across the pool, so the self-crossing test checks them like
anything else: segment against circle and segment against segment,
exact rather than sampled.

## What it does

1. Asks **which of the four shapes** it is — everything else follows
   from that — and then whether it is **simple or complex**.
2. Asks **where it goes** — the pool is drawn as it is answered.
3. Asks for the **absolute X and Y bounds** — the envelope the pool
   touches on all four sides and crosses on none.
4. Asks the **bulge radii** it needs — three on an oasis, one on a
   cloud.
5. Asks the **joiner radii** that connect them — three on an oasis, two
   on a rounded cloud, one on a straight-bottom cloud.
6. Draws the finished pool, its dimensions, and a **check drawing**
   beside it.

So an oasis asks eleven questions and the clouds ask nine and eight — a
complex Center adds a twelfth for the hump's offset. The middle ones are
named for the shape, because "top-right" means the joiner on one shape
and the bulge itself on another:

| Shape | Bulges asked | Joiners asked |
| --- | --- | --- |
| Center | Left, Top, Right | Top-left, Top-right, Bottom-center |
| TopRight | Left, **Top-right**, Right | Top-left, **Right-side**, Bottom-center |
| Cloud, straight | Right | Top |
| Cloud, rounded | Right | Top, Bottom |
| Kidney, true | **Top-center** (sides derive) | Bottom-center |
| Kidney, asymmetric | Left, Right (top derives) | Bottom-center |

On a complex run every joiner in the right-hand column takes `Line` as
well as a radius, and a complex **Center** gains one more question after
the top bulge: how far off centre the hump is.

A derived circle is never asked about and never reads `?` — its label
shows the computed value from the very first question, re-solving as
each real answer lands. On a true kidney the top radius has a hard
minimum the re-ask names — `Y/2 + X²/8Y`, the circle through the two
bottom corners, where the matching sides shrink to nothing.

A true kidney is also the one shape the **envelope alone** can rule out,
and for the same reason: sides that are derived rather than given. They
always come out less than Y across together, growing towards exactly
that as the top circle grows, so they fit inside X only while **Y is
less than X**. No top radius rescues a Y that is not — on a square
envelope the two sides meet dead centre whatever radius they are derived
from — so the Y question is where it is caught, while the number that
caused it is still the one being asked for. (An asymmetric kidney takes
any envelope; its sides are given.)

### Answering it, with the pool on screen

Before every question the preview is redrawn, with three things
overlapping on purpose:

* the **outline, solid**, on the `POOL` layer — what will actually be
  drawn;
* behind it the **circle each arc is cut from, dashed**, on
  `POOL-GUIDE` — the construction the radius being asked for belongs
  to;
* a **label on every circle**: its radius once given, **`?`** until
  then.

The circle the question is about — its arc, its dashed circle and its
label — is drawn **red**, so there is never a doubt about which radius
is wanted.

A radius that has not been answered yet still needs a value for any of
this to be drawable, so the preview fills the gaps with **the
proportions an oasis usually comes in**: a side bulge reaching three
quarters of the way across the short bound, the top bulge half way
across the long one. On a 40'×20' that starts you at 7'-6" side bulges
and a 10'-0" top, against the 8'/9' and 11' of the drawing this tool was
written from — near enough that the first question is already looking at
a familiar shape rather than something to look past. Every one of those
invented values carries a `?`, and the shape re-solves the instant a
real number replaces one.

The preview is scaffolding: it is erased when the last answer is in,
and again if the run is cancelled with Esc.

### What is left on the drawing

* the **six arcs** on the `POOL` layer;
* the **overall X and Y and a radius on each of the six arcs** — eight
  dimensions on the `DIMENSION` layer, in the drawing's ordinary
  **`Standard`** style. This is not asked about; a pool is always
  dimensioned;
* a **check drawing** clear to the right, dimensioned the way a layout
  is *checked* rather than the way it is built — see below. Its
  eighteen are the ones in the **`CROSS DIMENSIONS`** style, since that
  is what they are.

Both layers are the same (`DIMENSION`); only the styles differ.

The envelope box itself is construction: dashed on the check drawing,
where the corners are being measured to, and not drawn at all on the
pool.

### The check drawing

A second copy of the pool, off to the right, with the envelope box
dashed and a small circle on each of the six centres. Two families of
cross dimensions:

| Dims | What they tie |
| --- | --- |
| 12 | each circle centre to the **two envelope corners nearest it** |
| 6 | each circle centre to **the next one round the ring** |
| 3 | each **bulge** centre to the next bulge, across whatever sits between |

(Those counts are a `Center` or `TopRight` pool's 21. A rounded cloud
draws 13 and a straight-bottom one 9, having fewer centres; a kidney
draws 13 — and a pair that is both a ring neighbour and a bulge
neighbour is only dimensioned once.) On a kidney the two seam ties read
the **difference** of the radii rather than the sum, because those
circles touch from inside — either way, a wrong radius shows as a tie
that disagrees with the order sheet.

Between them those pin all six centres against the box and against one
another, so a transcription slip in any single radius shows up as a
dimension that does not agree with the order sheet. The
ring ties have a second use: neighbouring circles are externally
tangent by construction, so **each of those must read exactly the two
radii added together** — 8'-0" + 5'-0" = 13'-0" where
the left bulge meets the bottom-center tangent, and so on round the
six. Anything else means the outline is not tangent-continuous. The
bulge ties are the lobe-to-lobe measurements a pool is actually read by,
which the ring ties never give because they stop at each reverse arc in
between.

### Where the circles come from

The X and Y are absolute, and that alone pins all three bulges:

| Bulge | Touches | Centre |
| --- | --- | --- |
| left, **Center / TopRight** | the X-min and Y-min bounds | `(rL, rL)` |
| left, **the two clouds** | the X-min, Y-min **and** Y-max bounds | `(Y/2, Y/2)` |
| right | the X-max and Y-min bounds | `(X - rR, rR)` |
| top, **Center** | the Y-max bound, centred across X | `(X/2, Y - rT)` |
| top, **TopRight** | the Y-max **and** the X-max bounds | `(X - rT, Y - rT)` |
| top-center, **True kidney** | the Y-max bound, centred | `(X/2, Y - rT)` |
| top-center, **Asymmetric** | the Y-max bound **and** both sides, from inside | derived |

A cloud's left bulge is tangent to **three** bounds at once, and three
tangencies leave nothing free: its radius *is* half the Y bound. So it
is never asked for — it appears in the preview with its value already on
it while everything else still reads `?`.

So the bottom edge of the envelope is held by the two side bulges
together — each dips down to it — the left edge by the left bulge, the
top edge by the top bulge, and the right edge by the right bulge alone
on a centre-bulge pool or by the right bulge *and* the corner bulge on a
top-right one. On a centre-bulge pool the top bulge has one degree of
freedom left and it is spent centring it (see [Tunables](#tunables));
the corner bulge has none — two tangencies pin it.

Each tangent radius is then the circle of that radius sitting
**externally tangent to both** of its neighbouring bulges. Two such
circles exist, one either side of the line joining the two bulge
centres; the one **outside** the pool is the one wanted, and its near
side becomes the reverse curve. Naming the bulges counter-clockwise —
left, right, top — makes that choice mechanical, because a
counter-clockwise ring keeps its inside on the left and so outside is
always the right-hand solution.

Read counter-clockwise, the finished pool is

```
left -> bottom-center -> right -> top-right -> top -> top-left -> left
```

and every arc's two ends are the tangent points it shares with its
neighbours. Nothing is trimmed and nothing is fitted: the six arcs are
computed closed and drawn closed.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `OASIS.lsp`. Add it to the *Startup Suite* to have it in every
   drawing.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `OASIS` | Draw a continuous-tangent pool |
   | `OASISVER` | Print the version |

### The questions

```
Which shape is it? [Center/TopRight/CLoud/Kidney] <Center>:
Simple or complex? [Simple/Complex/Back] <Simple>:
Insertion base point <0,0> [Back]:
X - overall left-to-right bounds [Back]:
Y - overall front-to-back bounds [Back]:
Left bulge radius [Back]:
Top bulge radius [Back]:
Right bulge radius [Back]:
Top-left tangent radius [Back]:
Top-right tangent radius [Back]:
Bottom-center tangent radius [Back]:
```

(A **TopRight** pool asks the same eleven, with `Top-right bulge radius`
in place of `Top bulge radius` and `Right-side tangent radius` in place
of `Top-right tangent radius`. A **CLoud** asks `Cloud bottom?
[Straight/Rounded/Back] <Straight>:` second, and then drops the left and
top bulges and the two extra joiners — see the table above.)

Answer **Complex** and the three tangent questions read `[Line/Back]`
instead, and a Center pool gains one more straight after the top bulge:

```
Top bulge off center, left negative [Back] <0>:
```

`CLoud` takes two capitals because `Center` already has the `C`; the
routine normalizes it back to `Cloud` at the ask site, so nothing else
ever sees that spelling.

Every measurement is required — Enter, zero and a negative are all
refused — and every question after the first offers `Back` (`Undo` is
accepted too, unlisted) to step up one and re-answer, the base-point
pick included, right back to the shape itself. Backing up re-checks
everything after the answer you changed, and redraws the preview from
it.

Measurements are read with `getdist`, so they are typed in the
drawing's own units (`8'` in an architectural drawing, or picked as two
points on screen).

The worked example the routine was written from is a 40'-0" × 20'-0"
pool with 8'/11'/9' bulges and 6'/3'/5' tangent radii:

```
Which shape is it? [...] <Center>: Center
Insertion base point <0,0> [Back]: (pick)
X - overall left-to-right bounds [Back]: 40'
Y - overall front-to-back bounds [Back]: 20'
Left bulge radius [Back]: 8'
Top bulge radius [Back]: 11'
Right bulge radius [Back]: 9'
Top-left tangent radius [Back]: 6'
Top-right tangent radius [Back]: 3'
Bottom-center tangent radius [Back]: 5'
```

and the top-right one it was extended for is a 36'-11" × 28'-8" with
9'/8'/9' bulges and 8'/8'/10' tangents:

```
Which shape is it? [...] <Center>: T
Insertion base point <0,0> [Back]: (pick)
X - overall left-to-right bounds [Back]: 36'11
Y - overall front-to-back bounds [Back]: 28'8
Left bulge radius [Back]: 9'
Top-right bulge radius [Back]: 8'
Right bulge radius [Back]: 9'
Top-left tangent radius [Back]: 8'
Right-side tangent radius [Back]: 8'
Bottom-center tangent radius [Back]: 10'
```

and a straight-bottom cloud is a 30'-0" × 20'-0" with a 7' right bulge
and a 6' top — four numbers, because three bounds already pin the left
bulge at 10'-0":

```
Which shape is it? [...] <Center>: CL
Cloud bottom? [Straight/Rounded/Back] <Straight>: Straight
Insertion base point <0,0> [Back]: (pick)
X - overall left-to-right bounds [Back]: 30'
Y - overall front-to-back bounds [Back]: 20'
Right bulge radius [Back]: 7'
Top tangent radius [Back]: 6'
```

and a true kidney is your 388 × 214 drawing in just four numbers — the
sides derive themselves at 95.9167:

```
Which shape is it? [...] <Center>: K
Kidney type? [True/Asymmetric/Back] <True>: True
Insertion base point <0,0> [Back]: (pick)
X - overall left-to-right bounds [Back]: 388
Y - overall front-to-back bounds [Back]: 214
Top-center radius [Back]: 27'
Bottom-center tangent radius [Back]: 4'
```

## Tunables

`setq` these after loading (in a startup file, say) when a drawing
needs different names:

| Variable | Default | Meaning |
| --- | --- | --- |
| `oasis:*poollayer*` | `"POOL"` | Layer the six arcs are drawn on |
| `oasis:*poolcolor*` | `4` | Colour it is created with |
| `oasis:*dimlayer*` | `"DIMENSION"` | Layer every dimension goes on |
| `oasis:*dimcolor*` | `2` | Colour it is created with |
| `oasis:*guidelayer*` | `"POOL-GUIDE"` | Layer the dashed circles, the box and the `?` labels go on |
| `oasis:*guidecolor*` | `8` | Colour it is created with |
| `oasis:*hicolor*` | `1` (red) | Colour the circle being asked about is drawn in |
| `oasis:*dimstyle*` | `"Standard"` | Style the pool's own eight dims are drawn in |
| `oasis:*crossstyle*` | `"CROSS DIMENSIONS"` | Style the check drawing's eighteen are drawn in |
| `oasis:*startside*` | `0.75` | How far across the short bound a side bulge reaches before its radius is given |
| `oasis:*starttop*` | `0.5` | How far across the long bound the top bulge reaches before its radius is given |
| `oasis:*checkgap*` | `4.0` | How far right the check drawing sits, as a multiple of the dimension stand-off |
| `oasis:*topfrac*` | `0.5` | Where a **Center** pool's top bulge sits across the X bound, as a fraction of it |
| `oasis:*fuzz*` | `1.0e-6` | Slack for "same point / same length" tests, drawing units |

The dimension stand-off is not a tunable: it is `max(12, longer side /
18)`, the same rule `POOL` uses, so an oasis dimensioned beside a
rectangle reads at the same offset.

## What it refuses, and what it only reports

Three things make the shape **impossible** rather than merely unusual,
and each is caught at the question that causes it rather than after all
eight answers are in — the question simply comes back, with the reason:

* **a bulge that does not fit the envelope.** A side bulge is tangent to
  the bottom edge *and* to its own side, so it is twice its radius both
  ways: more than half the Y bound and it breaks out through the top,
  more than half the X bound and it breaks out through the far side.
  The **top right** corner bulge is checked the same way, for the same
  reason; the **centre** one is not, because it is trimmed away long
  before it reaches anything.
* **one bulge circle wholly inside another.** No tangent radius of any
  size can bridge that pair: raising the radius grows both circles'
  reach by exactly the same amount, so they stay nested forever.
* **a tangent radius too short to span its two bulges.** Below a
  minimum the two circles it would have to touch never meet. The
  routine names the smallest radius that will.

A fourth refusal is not about the radii at all: a **UCS tilted out of
the world plan** is turned away before the first question, because an
`ARC` in a tilted plane needs an extrusion of its own and a flat plan
pool has no business being drawn in one. Set the UCS back to World — or
to any plan UCS — and run it again.

Anything merely unusual is **drawn and reported**, not refused. Two
things are measured on the finished outline and named if they are
wrong:

* **whether it stays inside the envelope.** Each bound that is broken
  is named, with how far past it the outline reaches **and which arc
  takes it there** — because the radius behind an overrun is not
  reliably the one you would guess. A long shallow envelope with an
  oversized bottom-center tangent, for instance, reports the
  *top-right* arc hanging below the bottom bound and the
  *bottom-center* arc reaching above the top one, while every bulge
  fits the envelope perfectly well on its own.
* **whether the outline runs through itself.** Radii wildly out of
  proportion with each other can send one arc clean through another
  even though all six exist and close up — a 10'×10' pool with 6"
  side bulges and a 5' top, say, has its bottom-center arc sweeping up
  through both top tangent arcs. The pairs that cross are named. The
  test is exact rather than sampled: two circles meet in at most two
  points, and a crossing is one of those points lying inside both
  arcs' sweeps, so it is nine pairs and eighteen points to check, not
  a curve to walk.

Both are drawn anyway, so the problem is on the screen where it can be
seen — and the whole run is one undo group, so a single `U` takes it
away.

## Notes & limitations

* **Drawing units are the drawing's own.** Nothing here assumes inches;
  the arcs are built from the numbers `getdist` returns.
* **The pool is laid out in the current UCS**, so it follows the way you
  are working and the dimensions read the X and Y you typed. An `ARC`
  is the one entity that cannot follow — its centre is stored in world
  coordinates and its angles are measured from the world X axis — so
  both are carried across on the way out. The base point keeps its own
  elevation. A tilted UCS is refused (above).
* **A missing dimension style is not invented.** Those dims are
  drawn in whatever style is current and the routine says so once, so a
  drawing started from the wrong template is obvious instead of quietly
  producing wrong-looking dims. Create the style — or start from the
  standard template — and run it again. The style in force before the
  command is restored afterwards.
* **The preview is one undo group with everything else**, so a single
  `U` after the run takes the pool, the check drawing and all their
  dimensions away together. Esc part-way through the questions erases
  the preview too — no half-answered pool is left behind.
* The dashed guide linetype is **built by the routine** (`OASISDASH`,
  scaled to the pool) rather than loaded from `acad.lin`, because a
  failed load falls back to continuous silently, which is how dashes
  vanish. Its per-entity scale cancels the drawing's `LTSCALE`, so it
  reads the same whatever the host drawing is set to.
* The six arcs are **plain `ARC` entities**, not a polyline. Join them
  with `PEDIT` if a closed polyline is wanted — the endpoints coincide
  exactly, so the join is clean.
* `POOL` and `DIMENSION` are **created** when the drawing lacks them,
  and when either already exists but is frozen, locked or switched off,
  it is thawed, unlocked and turned back on — and the routine says so.
  Without that, a successful run onto a switched-off layer looks like
  the command did nothing.
* The radius dimensions are placed at each arc's **midpoint**, dragged
  clear of the water: outward from the centre on a bulge, and *towards*
  the centre on a reverse arc, whose own centre is itself outside the
  pool. They are drawn in whatever dimension style is current.
* The whole run is **one undo group**, so a single `U` takes the entire
  pool away. `OSMODE`, `CMDECHO` and `CLAYER` are restored afterwards
  whether the run finishes, errors, or is cancelled with Esc — and the
  base point is picked with the user's own object snaps still live,
  before snaps drop for the drawing work.
* The view is **not** zoomed; the pool is drawn at the base point that
  was picked and the report says what was drawn.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  **AutoCAD LT has no LISP engine and cannot run this file.**

## Tests

`python3 tests/test_oasis.py` loads the real `OASIS.lsp` into the repo's
AutoLISP VM (`tests/lispvm.py`) and drives `c:OASIS` with scripted
answers — 81 of them. The reference case is checked against the drawing OASIS was
written from — a 40'-0" × 20'-0" oasis with 8'/11'/9' bulges and
6'/3'/5' tangent radii — and all six arcs must land on that drawing's
six arcs to 1e-6". The rest cover closure and tangent continuity at
every joint, the outline filling the envelope exactly, the layers and
the eight dimensions, the base point, `Back`, each of the three refusals
re-asking, zero/negative/Enter being rejected, the undo group, the
sysvar restore, and a frozen-locked-off `POOL` layer being revived.
Three more drive the self-crossing test directly: the reference outline
is simple, a deliberately out-of-proportion one is caught and its
crossing pairs named, and the six tangent joints — where neighbouring
arcs touch by construction — are not miscounted as crossings. Four more
cover the frames and the bounds: a bulge too wide for `X` is re-asked,
an overrun names the arc that causes it, a rotated UCS puts the arc
centres and angles into world while the dimension points stay in the
UCS, and a tilted UCS is refused before a single question is asked.
(The VM's own `trans` is the identity, so those last two swap in a real
one for the length of the test.)

Nine more cover what this file added last: the preview appears only once
both bounds are known and then carries six arcs, six dashed circles and
the box at every radius question; the questioned circle's arc, circle and
label are all red and all the right one; unanswered radii read `?` while
answered ones read their value; every preview entity is erased when the
run finishes; the check drawing lands clear to the right as a true copy;
its twelve corner ties really do go to the two nearest corners of each
centre; its six centre ties each read the two radii added together; the
pool's dims come out in `Standard` and the check drawing's in
`CROSS DIMENSIONS` with the previous style put back; and a drawing
without a style still gets its pool. A tenth pins the starting
proportions: the side bulges span three quarters of `Y`, the top bulge
half of `X`, the bulges really are the bigger circles, and all six read
`?`.

Eight more are the **TopRight** shape: the shape is the first
question and offers no `Back` while the base-point pick after it does;
the corner variant reproduces its own reference drawing arc for arc; it
fills a 36'-11" × 28'-8" envelope and touches the right bound twice; its
outline is still closed, tangent-continuous and simple; the two shapes
name their six arcs apart; it asks for a top-right bulge and a
right-side tangent rather than a top bulge and a top-right tangent; a
corner bulge too big for the envelope is re-asked while a centred one of
the same size is not; and its preview starts from the short bound
because a corner bulge has to fit both ways.

And seven are the two **cloud** shapes: each reproduces its own reference
drawing arc for arc; both fill a 30'-0" × 20'-0" envelope exactly; the
flat run really is the general external tangent landing on the Y-min
bound rather than a special case bolted on; they ask eight and nine
questions with no left-bulge question among them; the flat run is
dimensioned by its length rather than by a radius it has not got; and
their preview draws no circle and no `?` behind that run while showing
the pinned left bulge's value from the very first question. Two more
cover the shape being asked in two parts — the bottom question decides
whether a bottom radius is asked for at all, and `Back` from it lands on
the shape and rebuilds every question after it — and one covers the
bulge-to-bulge ties in the check drawing.

Twelve are the two **kidney** shapes: the true kidney reproduces its
customer drawing arc for arc, with the sides deriving at 95.9167; the
seams hand over at the exact internal tangency with nothing drawn
between; it fills its envelope simply; the asymmetric one derives its
top circle to the same tangencies; each asks its own questions (8 and
9); a top radius under the named minimum is re-asked; the one degenerate
side pair (both exactly half of Y — a cloud, not a kidney) is caught and
re-asked; the derived circles label themselves with values, never `?`;
the check drawing's seam ties read `R − r` where external ties read
`r₁ + r₂`; `Back` walks the kidney's own step list up to the shape
question itself; a Y at or over X is re-asked rather than carried into a
shape that cannot close; and every one of the 1,010 envelopes the
questions admit draws a ring from its starting provisionals, so the
first preview is never an empty box.

Ten cover **complex** runs: Simple is the default and leaves a plain run
alone, while Complex puts `[Line/…]` on every joiner question and adds
the hump's offset; `Line` draws the common external tangent, square to
both bulges and exactly the tangent length long; growing a reverse
radius by ten closes the gap to that run by ten, which is what "the same
joiner with an infinite radius" means; the hump moves by exactly the
offset given, left negative, and still fills the envelope; an offset off
the envelope or one that swallows the left bulge is re-asked; all four
families take a run; a bulge pinched to a point by the runs either side
of it is left out of the drawing and named in the report; a run is
tested for crossings exactly, segment against circle and segment against
segment; a run already answered is still the element picked out in red
when it is re-asked; and `Back` walks the two new questions like any
other.

The preview ones wrap `getdist` to photograph the drawing at the moment
each question is put — it is erased before the next one, so there is no
other way to see it.

`CALOFIN_LISP_ROOT=shared python3 tests/test_oasis.py` reruns the whole
file against the grouped build in `shared/`, as a parity check.
