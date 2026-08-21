# OASIS — Continuous-tangent pool from an X/Y envelope

An AutoLISP routine for full AutoCAD that draws an **oasis** pool: six
arcs and nothing else — no straight runs, no corners. Three bulge
outward, one off the left of the pool, one off the right and one off the
top; between each neighbouring pair a smaller **reverse** arc curves
back in, so the perimeter changes direction without ever changing
tangent.

They come two ways, and the first question is which:

| | The third bulge | Touches |
| --- | --- | --- |
| **centre bulge** | across the top, centred | the top bound |
| **top right bulge** | tucked into the top-right corner | the top **and** the right bound |

That is the **only** difference. Same six arcs, same ring, same solver,
same checks — only where the third bulge's centre lands, and the names
the arcs go by because of it. On a top-right pool the right-hand bound
is touched twice, once by each of the two right-hand bulges, with a
reverse curve dipping in between them.

```
                   top bulge
                 ___________
     top-left  ,'           `.  top-right
     tangent  /               \  tangent
             |                 |
 left bulge  |                 |  right bulge
              \      ___      /
               `.__,'   `.__,'
                bottom-center tangent
```

That is what *continuous tangent* buys: every joint in the outline is
smooth, so the whole shape can be given as two overall dimensions and
six radii — which is exactly what OASIS asks for.

## What it does

1. Asks **which of the two shapes** it is — everything else follows from
   that.
2. Asks **where it goes** — the pool is drawn as it is answered.
3. Asks for the **absolute X and Y bounds** — the envelope the pool
   touches on all four sides and crosses on none.
4. Asks the three **bulge radii**, left, top, then right.
5. Asks the three **tangent radii** that join them, top-left, then the
   one on the right, then bottom-center.
6. Draws the finished pool, its dimensions, and a **check drawing**
   beside it.

The middle four questions are named for the shape: a centre-bulge pool
asks for a *Top bulge* and a *Top-right tangent*, a top-right one for a
*Top-right bulge* and a *Right-side tangent* — because "top-right" means
the tangent arc on one and the bulge itself on the other.

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

Between them those pin all six centres against the box and against one
another, so a transcription slip in any single radius shows up as a
dimension that does not agree with the order sheet. The
centre-to-centre ties have a second use: neighbouring circles are
externally tangent by construction, so **each of those must read
exactly the two radii added together** — 8'-0" + 5'-0" = 13'-0" where
the left bulge meets the bottom-center tangent, and so on round the
six. Anything else means the outline is not tangent-continuous.

### Where the circles come from

The X and Y are absolute, and that alone pins all three bulges:

| Bulge | Touches | Centre |
| --- | --- | --- |
| left | the X-min and Y-min bounds | `(rL, rL)` |
| right | the X-max and Y-min bounds | `(X - rR, rR)` |
| top, **centre bulge** | the Y-max bound, centred across X | `(X/2, Y - rT)` |
| top, **top right bulge** | the Y-max **and** the X-max bounds | `(X - rT, Y - rT)` |

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
Where is the top bulge? [Center/TopRight] <Center>:
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

(A **top right bulge** pool asks the same ten, with `Top-right bulge
radius` in place of `Top bulge radius` and `Right-side tangent radius`
in place of `Top-right tangent radius`.)

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
Where is the top bulge? [Center/TopRight] <Center>: Center
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
Where is the top bulge? [Center/TopRight] <Center>: T
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
| `oasis:*topfrac*` | `0.5` | Where the top bulge sits across the X bound, as a fraction of it. `0.5` centres it, which is what every oasis on file wants |
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
answers — 51 of them. The reference case is checked against the drawing OASIS was
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

Eight more are the **top right bulge** variant: the shape is the first
question and offers no `Back` while the base-point pick after it does;
the corner variant reproduces its own reference drawing arc for arc; it
fills a 36'-11" × 28'-8" envelope and touches the right bound twice; its
outline is still closed, tangent-continuous and simple; the two shapes
name their six arcs apart; it asks for a top-right bulge and a
right-side tangent rather than a top bulge and a top-right tangent; a
corner bulge too big for the envelope is re-asked while a centred one of
the same size is not; and its preview starts from the short bound
because a corner bulge has to fit both ways. The preview
ones wrap `getdist` to photograph the drawing at the moment each question
is put — it is erased before the next one, so there is no other way to
see it.

`CALOFIN_LISP_ROOT=shared python3 tests/test_oasis.py` reruns the whole
file against the grouped build in `shared/`, as a parity check.
