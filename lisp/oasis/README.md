# OASIS — Continuous-tangent pool from an X/Y envelope

An AutoLISP routine for full AutoCAD that draws an **oasis** pool: six
arcs and nothing else — no straight runs, no corners. Three bulge
outward, one off the left of the pool, one off the top and one off the
right; between each neighbouring pair a smaller **reverse** arc curves
back in, so the perimeter changes direction without ever changing
tangent.

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

1. Asks for the **absolute X and Y bounds** — the envelope the pool
   touches on all four sides and crosses on none.
2. Asks the three **bulge radii**, left, top, then right.
3. Asks the three **tangent radii** that join them, top-left,
   top-right, then bottom-center.
4. Asks whether to dimension the result, and where to put it.
5. Draws the six arcs on the **`POOL`** layer and, unless dimensioning
   was declined, the overall X and Y plus a radius dimension on each of
   the six arcs on the **`DIMENSION`** layer.

The envelope box itself is construction geometry and is **not** drawn.

### Where the circles come from

The X and Y are absolute, and that alone pins all three bulges:

| Bulge | Touches | Centre |
| --- | --- | --- |
| left | the X-min and Y-min bounds | `(rL, rL)` |
| right | the X-max and Y-min bounds | `(X - rR, rR)` |
| top | the Y-max bound, centred across X | `(X/2, Y - rT)` |

So the bottom edge of the envelope is held by the two side bulges
together — each dips down to it — the left and right edges by their own
bulge, and the top edge by the top bulge. The only freedom left is
where the top bulge sits along X, and that is spent centring it (see
[Tunables](#tunables)).

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
X - overall left-to-right bounds:
Y - overall front-to-back bounds [Back]:
Left bulge radius [Back]:
Top bulge radius [Back]:
Right bulge radius [Back]:
Top-left tangent radius [Back]:
Top-right tangent radius [Back]:
Bottom-center tangent radius [Back]:
Dimension the pool? [Yes/No/Back] <Yes>:
Insertion base point <0,0>:
```

Every measurement is required — Enter, zero and a negative are all
refused — and every question after the first offers `Back` (`Undo` is
accepted too, unlisted) to step up one and re-answer, right through the
dimension question. Backing up re-checks everything after the answer you
changed. The base point pick at the end is the one prompt with no
`Back`: nothing has been drawn yet, so Esc there costs nothing.

Measurements are read with `getdist`, so they are typed in the
drawing's own units (`8'` in an architectural drawing, or picked as two
points on screen).

The worked example the routine was written from is a 40'-0" × 20'-0"
pool with 8'/11'/9' bulges and 6'/3'/5' tangent radii:

```
X - overall left-to-right bounds: 40'
Y - overall front-to-back bounds [Back]: 20'
Left bulge radius [Back]: 8'
Top bulge radius [Back]: 11'
Right bulge radius [Back]: 9'
Top-left tangent radius [Back]: 6'
Top-right tangent radius [Back]: 3'
Bottom-center tangent radius [Back]: 5'
```

## Tunables

`setq` these after loading (in a startup file, say) when a drawing
needs different names:

| Variable | Default | Meaning |
| --- | --- | --- |
| `oasis:*poollayer*` | `"POOL"` | Layer the six arcs are drawn on |
| `oasis:*poolcolor*` | `4` | Colour it is created with |
| `oasis:*dimlayer*` | `"DIMENSION"` | Layer the dimensions go on |
| `oasis:*dimcolor*` | `2` | Colour it is created with |
| `oasis:*topfrac*` | `0.5` | Where the top bulge sits across the X bound, as a fraction of it. `0.5` centres it, which is what every oasis on file wants |
| `oasis:*fuzz*` | `1.0e-6` | Slack for "same point / same length" tests, drawing units |

The dimension stand-off is not a tunable: it is `max(12, longer side /
18)`, the same rule `POOL` uses, so an oasis dimensioned beside a
rectangle reads at the same offset.

## What it refuses, and what it only reports

Three things make the shape **impossible** rather than merely unusual,
and each is caught at the question that causes it rather than after all
eight answers are in — the question simply comes back, with the reason:

* **a side bulge that does not fit the envelope.** It is tangent to the
  bottom edge *and* to its own side, so it is twice its radius both
  ways: more than half the Y bound and it breaks out through the top,
  more than half the X bound and it breaks out through the far side.
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
answers. The reference case is checked against the drawing OASIS was
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

`CALOFIN_LISP_ROOT=shared python3 tests/test_oasis.py` reruns the whole
file against the grouped build in `shared/`, as a parity check.
