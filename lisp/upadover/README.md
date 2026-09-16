# UPADOVER -- the perimeter covered with pads, from one point round to another (AutoLISP / AutoCAD 2018+)

`PADDLE` reads the perimeter and pads the **features** it finds -- an
inside corner, a tight concave arc -- and leaves the wall between them
bare, because that is where a pad earns its place. Some stretches are
not like that: from this point round to that one the wall is carried
wholesale, and what the drafter wants is the whole stretch under pads,
laid end to end, with nothing missed and nothing doubled.

That is `UPADOVER`. Click the perimeter, say where the pads start and
where they end -- click the spots, or type the survey points' numbers
the way `ABHD` and `PERPMARK` take them -- and the run comes back
covered. Or click a line or a polyline that already **is** the stretch
that needs pads, answer **`Whole`**, and all of it is covered without
an end being named at all.

It is `PADDLE`'s sibling on the pad side (same block, same layer, same
36") and `PERPMARK`'s on the question side (the same wall reader, the
same names for a point, the same one-click way of settling a direction
nothing else can).

## What it does

1. **Click the perimeter, or the line or polyline to pad.** A polyline
   (arc segments included), a line, an arc, a circle -- and anything
   else AutoCAD can measure along, which is read through `vlax-curve-*`
   instead. An entity that is neither is named and the question is put
   again. The run says what it got and how long it is.
2. **Where the pads start**, and **where they end** -- or **`Whole`**,
   which pads all of it and skips both (below). Either end is a
   click anywhere on the wall **or** a survey point's number: `17`,
   `Pt.17`, `pt 17`, `#17` and `017` all name the same point, and a
   click landing within `upad:*snap*` of one **is** that point and is
   named like one in the report. A pick that sits off the wall is
   projected onto it and the run says how far it had to come. The two
   ends have to be different places; a second pick on the first one's
   spot is refused where it stands.
3. **Which way round** -- only when it is a real question (below).
4. The pads go in, in one undo group, and the run reports what it did.

## Which way round, and when it is asked

Two ends cut a closed perimeter into two stretches and the run is one
of them. The **shorter** one is what somebody means by "from here to
there" almost every time, so that is what is taken -- and both lengths
are reported, so a wrong guess is visible rather than silent:

```
UPADOVER: the shorter way round, 20'-0" against 40'-0" the other way.
```

Almost every time is not every time. On a long thin pool the two ways
round come out near enough the same, and then the shorter one is a coin
toss wearing a decision's clothes. So when the two are within
`upad:*evenpct*` of each other -- 30% by default -- the question is put
instead:

```
UPADOVER: the two ways round are 30'-0" and 30'-0" - near enough the
same that which one you mean is yours to say.
Click a spot the run passes through [Back]:
```

One click, and the stretch carrying it is the stretch that gets the
pads. It is the same answer `PERPMARK` asks for in the same words when
its own marks cannot settle a direction.

An **open** perimeter has one stretch between any two points, so it is
never asked.

## Padding the whole of it

Often the stretch that needs pads is already drawn: a line down a wall,
a polyline round a bay. Answering **`Whole`** at the first question
pads that curve end to end -- the second question is never put, and on
a closed perimeter the run goes all the way round and back to where it
started:

```
Select the perimeter, or the line or polyline to pad: (pick)
UPADOVER: an open run, 20'-0" long.  Whole at the next question pads all of it.
Where the pads start - click it, or type a point number [Whole/Back]: Whole
UPADOVER: 8 36" pad(s) on layer "PADS", covering the whole 20'-0" of it, end to end.
```

It is the same cover as a two-point run, laid by the same walk: the
first pad is centred on the curve's own start point, and the far end is
carried past in the usual way.

## How the pads are laid

A pad goes down wherever the run comes out from under the pads already
there, and it goes down **one pad across** from the pad it came out of,
along the axis it came out through. Two pads offset by exactly their own
width on one axis meet on that line and cannot lie over each other
whatever the other axis does -- so the other axis is left free, and
**follows the wall**.

That freedom is the whole of it. The first version laid the pads on a
fixed grid, which is simple to prove and expensive to build: the pads
stair-step whatever the wall is doing, and sit up to half a pad off it.
On the drafter's own comparison drawing the same run came out as:

| laid | pads |
| --- | --- |
| on a grid (v1.1) | 18 |
| by hand, as wanted | 14 |
| across the wall (v1.2) | **12** |

and the first eight of the twelve land within an inch or two of where
the hand-laid ones were put.

How far one pad reaches is measured the same way it is laid: the run is
followed from where it came out for as long as it stays inside the new
pad's strip **and** the band it sweeps across that strip still fits
inside one pad. The pad is then centred on that band -- held so it
covers the point the run crossed the seam at, which is what keeps the
seam closed, and so it shares at least `upad:*mincontact*` of an edge
with its neighbour rather than touching at a corner. What it actually
covers is then walked again rather than assumed, so a pad pulled off the
middle of its band by those two holds cannot leave a tail behind it.

A run at exactly 45 degrees is the shape that makes the last point
matter: with no minimum contact the pads step corner to corner, which is
a joint with no width and a break in everything but topology.

The ends are **carried past, not stopped at**: the first pad is centred
ON the start point, so the cover begins half a pad before it, and the
last pad runs past the far end rather than stopping on it. Erring past
the point is the safe direction.

Pads are square to the drawing, always. A rotated pad could not meet the
next one along a straight edge, and those edges are what hold the cover
together.

## What it cannot pad, and says so

One thing stops a cover, and it is reported rather than papered over: a
run that comes back **within a pad's width of itself**. A slot narrower
than a pad, or a whole loop closing back on its own first pad, has
stretches where every pad that would cover them lies over one already
down. Those are left bare, measured, and named:

```
UPADOVER: 2'-5" of the run is left bare - a pad there would lie over one
already down, where the loop closes back on itself.
```

Everything else reports the other way round -- that the wall is under
pads end to end. The run checks that for itself before it says it: the
cover is walked against the run it was laid for rather than taken on
trust.

## Install & run

`APPLOAD` `UPADOVER.lsp` (or the whole build, `shared/LAZPASS.lsp`),
then type `UPADOVER`. `UPADOVERVER` prints the loaded version.

The pad block resolves the way `PADDLE`'s does: a definition already in
the drawing wins, otherwise every definition in `24inpad.dwg`
(`lisp/paddle/`) is imported if AutoCAD can find it -- put that folder
on *Options -> Files -> Support File Search Path*, or drop the dwg
beside the drawing -- and failing both, a plain square block of the
right size is created and the run says so.

## Tunables

At the top of the file, between the version banner and the first
`defun`.

| Knob | Default | What changing it does |
| --- | --- | --- |
| `upad:*blkname*` | `"Pad36x36"` | The block inserted at every pad spot. `24inpad.dwg` ships `Pad36x36` and `Pad24x24`; switching it means switching `upad:*padsize*` with it |
| `upad:*padsize*` | `36.0` | The edge of the pad, and so the step from one pad to the next. A block that is not this size leaves gaps between pads or laps them |
| `upad:*blkfile*` | `"24inpad.dwg"` | The dwg the definitions are imported from when the drawing lacks them |
| `upad:*layer*` | `"PADS"` | Where the pads land -- `PADDLE`'s layer, so a drawing padded by both has them in one place. Created when missing; thawed, unlocked and switched on when not |
| `upad:*layercolor*` | `7` | The ACI that layer is CREATED with. An existing layer keeps its own |
| `upad:*evenpct*` | `0.70` | How near the two ways round have to be before the shorter one stops being an answer and the question is put instead. `0.70` is "within 30% of each other"; raise it to be asked less often and guessed at more, `1.0` to be asked every time there is a choice |
| `upad:*mincontact*` | `6.0` | How much of their shared edge two neighbouring pads must have in common. Every pad is laid exactly one pad across from the one the run came out of, so the two always meet on that line; this is how much of the line they must actually share. `0` lets them meet at a corner, which is what a run at exactly 45 degrees does if nothing stops it. `6` costs nothing on any shape tried; raising it holds neighbours closer together and buys the odd extra pad on a diagonal |
| `upad:*samples*` | `48` | How finely the run is walked, in samples per pad width. It is the resolution the cover is worked out at: raising it can only ever find another cell the wall clips, at the price of a longer walk. Below about 8 a run could cross a corner of a cell between two samples and miss it |
| `upad:*snap*` | `12.0` | How close a CLICK has to land to a survey point to pick it rather than the place it landed. A typed number never uses it -- a name is exact. `12.0` is what `PERPMARK`, `BPCALLOUT` and `ABFIND` snap at |
| `upad:*onwall*` | `0.25` | How far off the perimeter a pick may sit before the run says where it landed. A quarter inch is drafting noise; more than that is worth a line, because a pick projected across the pool is how the wrong stretch gets padded quietly |
| `upad:*fuzz*` | `1e-6` | How far apart along the wall two ends have to be to be two places at all |
| `upad:*point-block*` | `"ab_pt"` | The block whose INSERTs are survey points wherever they sit. Shared with `PERPMARK`, `BPCALLOUT`, `CDCALLOUT`, `ABFIND` and `LHD` -- change it in all of them or the tools disagree about what the drawing holds |
| `upad:*point-layer*` | `"POINTS"` | The layer whose POINTs and INSERTs are survey points whatever block they are |
| `upad:*pt-tag*` | `"number"` | The attribute tag that names a point. A block without it lends its first attribute that reads as a number instead |
| `upad:*unknown*` | `"?"` | What a point with no readable number is called. It can still be clicked; only a number can be typed |
| `upad:*pt-prefix*` | `"Pt."` | How a point is named in the prompts and the report |

## Notes & limitations

- **The cover is worked out at a resolution, not symbolically.** The
  run is sampled every `upad:*padsize*` / `upad:*samples*` -- three
  quarters of an inch on a 36" pad -- and the walk works off those
  samples. The seam between two pads is the exception: where the run
  crosses from one to the next is worked out between the samples either
  side of it, because a seam is where a fraction of an inch of wall
  would otherwise slip out. A feature narrower than a sample step is
  the one thing the walk could still step over; raise
  `upad:*samples*` if you have one.
- **One curve, not a chained outline.** The perimeter is the entity you
  click. `PADDLE` chains loose lines and arcs into a loop because it
  scans a whole drawing; here the wall is the thing you pointed at, and
  a perimeter that is still in pieces should be joined (`PEDIT`, or
  `LINGUTTER`, which draws one) before it is padded stretch by stretch.
- **The pads follow the wall but are not centred on it.** Each one is
  centred on the band of wall it covers, which on a curve or round a
  corner leaves it a few inches off. A row of pads each centred exactly
  on the perimeter is `PADDLE`'s shape, and it is the right one for
  padding features rather than covering a run.
- **A run that comes back within a pad's width of itself cannot be
  covered whole.** A slot narrower than 36" and the closing seam of a
  whole loop both hit it. The run says how much it left, in feet and
  inches; nothing is quietly doubled up or quietly missed.
- Everything one run inserts is a single undo step. Esc at any prompt
  closes the undo group and puts `CMDECHO` back; `OSMODE` is never
  touched, so the drafter's snaps are exactly as they left them.

## Tests

```
python3 tests/test_upadover.py
CALOFIN_LISP_ROOT=shared python3 tests/test_upadover.py
```

Runtime tests: the real file is loaded into `tests/lispvm.py` and
`c:UPADOVER` is driven from a script. The three halves of the promise --
no two pads overlapping, all of them one block joined edge to edge (a
pair meeting at a corner is not joined, which is the break the bridging
pads exist to stop), and no point of the run left bare -- are asserted
as facts about the pads that landed, on a straight wall, a run round a
90-degree corner, a wall at 45 degrees (where the bridging pads are), a
half circle, a circle, and a notch the run doubles back through. The
rest drives the questions: the five spellings of a point number, a
click that snaps to a point and one that does not, a pick projected
onto the wall, the shorter way round taken without asking and the even
one asked about with one click, `Whole` on a line, on a polyline with
an arc in it and on a closed perimeter (where it comes back round to
its own start without doubling a pad), Back at each step, and Esc --
which draws nothing, leaves no undo group open and hands every system
variable back.
