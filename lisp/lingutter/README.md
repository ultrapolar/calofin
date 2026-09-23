# LINGUTTER — Gut a highlighted area to its perimeter, then pad it

An AutoLISP routine for AutoCAD 2018+ that reduces **the area you
highlight** to three things — the **outermost perimeter** in it, redrawn
as one closed polyline on the **`POOL`** layer; the **dimensions worth
keeping**; and the pads **`PADDLE`** puts on it — and erases everything
else it was shown.

An as-built sheet carries far more than the next station needs: the
hopper and its slope lines, steps, survey points and their labels, the
notes. LINGUTTER guts one pool back in a single pass, straight through
— it does not ask first.

> **It works only inside the highlight.** Window the pool — before
> typing the command or at its prompt — and everything below happens to
> that selection and nothing else. What you did not highlight is not
> traced from, not counted and not erased, so a second pool, the title
> block and the rest of the sheet are all safe from it. A crossing
> window takes in whatever it touches, so a dimension half inside the
> highlight is in the sweep and one wholly outside it is not: the
> highlight is the whole of the rule.

## What it does

1. **Walks the exterior and draws its own perimeter over it.** It does
   *not* look for a closed loop and hope one of them is the pool —
   that assumption is what used to fail, and what used to hand over a
   hopper. Instead every `LINE`, `ARC`, `LWPOLYLINE` and `POLYLINE`
   **in the highlight** becomes an edge of a graph, ends closer
   together than a snap tolerance count as one point, and the **outer
   face** is walked, always taking the hardest available **right**
   turn. That rule is what keeps it outside. Interior geometry — the
   hopper, the steps, a bottom break, a tie line — is never stepped
   onto, because reaching it always needs a left turn. Loose lines and
   arcs are as good an input as a drawn polyline, and arcs keep their
   bulge.

   Three things fall out of it, and they are the three ways the old
   guess got it wrong:

   * **an outline with a gap in it encloses nothing** once its spurs
     are pruned, so it fails loudly instead of quietly handing over
     whatever else did close;
   * **a hopper that closed while the outline did not can never win**,
     because it does not span the highlight (see the ladder below);
   * **a stray tick hanging off the outline is pruned.** The true outer
     face really does run up it and back; left in, `PADDLE` would read
     it as a 180° inside corner and pad it.

   Four more things the walk reads that are not lines on the outline,
   and every one of them is a step or a bench a pool really has:

   * **a T is a junction.** A drafter does not break the wall where a
     tanning ledge meets it: the wall is one line the full height of
     the pool and the ledge's two sides run up to the **middle** of
     it. Every segment is split where another one's **end** lands on
     it, at the same tolerance, before the graph is built. Only ends —
     two lines that merely *cross* mid-span still are not a junction,
     which costs nothing on a CAD outline and keeps the walk exact.
   * **a block reference is geometry.** A fiberglass step is not drawn
     line by line: it is an `FG_STEP` reference bolted to a wall, and
     its three sides **are** the perimeter where it sits. A reference
     contributes its definition's own geometry, carried onto the
     insertion point — rotation, scale and mirror included, nesting
     followed — and is then swept like anything else, because the new
     perimeter replaces the step's lines the way it replaces the
     pool's. `lg:*skipblocks*` is what keeps the two families that sit
     *on* a pool rather than bounding it out of the trace: `PADDLE`'s
     own pads (centred **on** a corner, half of each outside the loop,
     so a pool gutted twice would trace round its own pads) and the
     drain blocks.
   * **which face, not where to start.** Which face a walk traces is
     decided entirely by the dart it starts on, and that used to be a
     guess: the shallowest edge at each piece's lowest *node*. One arc
     leaving that node and dipping below it is enough to make the
     guess wrong, and a walk going the other way round hugs the
     **inside** — one turn tighter at every node, which is exactly
     what "the hardest right turn" asks for. So nothing is guessed:
     every face is walked and the one enclosing the most area wins,
     which is the outer boundary of its piece and, across pieces, the
     pool rather than the stray line beside it. It costs no more work
     — each edge is still travelled once each way.
   * **a run of one curve is one edge.** Splitting at a T puts a node
     in the middle of a wall, and a step outline running past a
     stepped corner comes back as seven pieces of one circle. A run of
     consecutive edges that is one straight line, or one arc about one
     centre, is welded back into a single edge, so what the drafter
     gets is the outline they drew rather than a polyline carrying a
     vertex for every tread that touched it — and `PADDLE` is not
     offered a string of 180° corners to pad.
2. **The snap ladder.** `lg:*snaps*` is tried in order — `0.05`, then
   `6.0`, then `24.0` drawing units — and the first rung whose exterior
   spans at least `lg:*cover*` (80%) of what you highlighted, both ways,
   is the answer. A rung is only climbed when the one below could not
   produce one, and the report always names the rung that worked, since
   snapping *moves* a corner by up to that tolerance.

   Covering too little is a **warning, never a veto**. Highlight two
   pools and it traces the bigger one and says so; highlight a pool
   next to a long stray line and the same warning fires through no
   fault of the pool. Answering either with a convex hull would be
   worse than answering with the pool and a word of caution.

   When **no** exterior can be walked at any rung it still draws a
   perimeter: the **convex hull** of everything highlighted. That is
   reported as the wrap it is — a hull has no concave features, so
   `PADDLE` will find nothing to pad. Close the outline and run it
   again.
3. **Redraws it as one object.** The perimeter is written back as a
   single **closed `LWPOLYLINE`** on the `POOL` layer, arcs carried as
   bulges, **ByLayer** — no per-entity colour, linetype or lineweight —
   so the result is one polyline whatever went in: one polyline, or
   fifty loose lines and arcs.
4. **Keeps three kinds of dimension**, and nothing else highlighted
   survives:

   | Kept | Rule |
   | --- | --- |
   | any **radius or diameter** dimension | **of the perimeter** — regardless of its style, by any of the three shapes below. A corner radius under a foot lands in `STANDARD INCHES` like any other short measurement, and that call-out is not the thing to erase |
   | `CROSS DIM*` — matches `CROSS DIM`, `CROSS DIMENSIONS` and `CROSS DIMENSIONS 0.5` | only when **"Keep CROSS DIMENSIONS?"** is answered Yes, and only when it reads as a **genuine cross measurement of this pool** (below) |
   | `STANDARD*`, `SIDE STANDARD*`, `ALT STANDARD*` | **only when it dimensions the perimeter** — every one of its attachment points within `lg:*ontol*` of the loop, **and** the two of them not a partial read along one single edge |

   A dimension's *attachment* points are DXF 13 and 14, the two measured
   points of a linear, aligned, ordinate or angular dim. Group 11 (the
   text) and 16 (an angular dim's arc) *place* the dimension rather than
   attach it, and are not tested.

   **A radius or diameter dim carries no 13/14 at all**, and group 10 is
   **not** where its arrow lands: for a radius dim group 10 is the arc's
   **centre** and group 15 is the point on the curve. (A diameter dim's
   10 and 15 are the two ends of a diameter, both on the curve.) Reading
   10 as the attachment point is why every corner-radius call-out on
   every pool with a radius drawn on it used to be erased: the centre of
   a 24" corner sits 24" inside the loop. So a radial dim is kept when
   **any** of three things is true, and they are three real shapes on
   these sheets:

   * its **point on the curve** is within `lg:*ontol*` of the loop — an
     arc the walk traced, with the arrow landing inside the swept part
     of it;
   * it **names an arc of the loop** — same centre, same radius, both
     within `lg:*ontol*`. This is the one that matters most, because a
     leader is routinely dragged round to where it reads well and its
     arrow then lands on the same circle but *past the end* of the
     drawn arc;
   * its **centre sits on a vertex** of the loop — `R3 typ.` on a
     corner that is drawn sharp and is meant to be filleted. A vertex,
     not merely somewhere along an edge: the centre of a tread arc
     inside a radius-cornered step sits exactly **on** the step outline
     that runs past it, and that is an interior call-out, not a
     perimeter one.

   *Every* attachment point has to pass its rule, not just one: a dim
   running from the pool edge in to the hopper is measuring the hopper,
   and a cross dim with one end nowhere near this pool is not this
   pool's to keep.

   **A "genuine cross measurement"** is judged by shape, not just
   location. Both attachment points first have to belong to the pool at
   all — inside the traced perimeter, or on it — and from there a
   `CROSS DIM*` dimension is kept when *either*:

   * it spans at least `lg:*crossspan*` (80% by default) of the
     perimeter's own width or height — **"goes full X"** or **"goes
     full Y"** — corner to corner, side to side through the middle,
     however it is drawn, *or*
   * its two points sit at two of the perimeter's own **vertices** —
     **the start of one side to the end of it**, corner to corner along
     one whole edge, however short that edge is (a short notch side
     would otherwise never reach `lg:*crossspan*` on its own).

   Whichever of those two ways it qualifies, a dimension is **never**
   kept when both of its points sit on the SAME single perimeter edge
   and are not that edge's own two endpoints — the start of a line to
   some random point in the middle of that *same* line. That shape is
   read as a fraction of one side, not the pool, and is dropped even
   when it happens to span more than `lg:*crossspan*` on its own (a
   long enough side could otherwise make a partial reading look like it
   spans the pool by accident). A small `CROSS DIM*` dimension sitting
   entirely inside the pool, touching nothing and spanning neither a
   corner-to-corner run nor most of the pool, gets no exemption either
   — it goes with the rest, the same as a stray one that answers to a
   different pool in the same highlight.

   `LINGUTTER` asks **"Keep CROSS DIMENSIONS?"** once, before it reports
   what it found. Answered No, every `CROSS DIM*` dimension gets no
   exemption regardless of its shape, and is judged like any other
   style not in `lg:*perimstyles*` — dropped, and counted in the report
   like everything else. The radius/diameter rule above does not go
   through this question at all: a radius dim on the perimeter is kept
   either way.
5. **Erases everything else it was shown** — text, blocks, points,
   hatches, the geometry the perimeter was traced from, and dimensions
   in any other style. `VIEWPORT` entities are never erased, and a layer
   named in `lg:*keeplayers*` is spared even inside the highlight.
6. **Hands the new perimeter to `PADDLE`**, and PADDLE pads its
   concave features without asking anything. *Handed, not hunted:*
   PADDLE's own auto-detect reads the **whole** drawing for its largest
   closed loop, which after a scoped gut may well be a title block
   border rather than the pool. The polyline goes over in the global
   `*calofin-handoff*`, which PADDLE reads before its pickfirst probe
   and clears -- not as a pickfirst set, which `ssget "_I"` reads only
   with `PICKFIRST` at 1: a drafter who works at 0 used to get PADDLE's
   perimeter prompt instead, where Enter auto-detects the very border
   the handoff exists to avoid.

Before erasing anything it prints exactly what it found in the
highlight — how many
vertices the perimeter has and how far round it is, how many dimensions
are kept under each rule, and **how many are dropped, counted by
reason** — then erases it, without asking first. Nothing disappears
silently: a `STANDARD INCHES` dim sitting on the perimeter is reported
as `3 x STANDARD INCHES - style not kept`, not quietly deleted.

The whole run is one undo group, so a single `U` puts the drawing back.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `LINGUTTER.lsp`. Add it to the *Startup Suite* to have it in
   every drawing. Load `PADDLE.lsp` too, or step 5 is skipped with a
   note.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `LINGUTTER` | trace the perimeter, erase the rest, run `PADDLE` |
   | `LINGUTTERSCAN` | print the same report and stop — nothing in the drawing is changed |
   | `LINGUTTERVER` | print the loaded version |

   Highlight the area **before** typing either command and that
   selection is taken as-is; otherwise both ask:

   ```
   Highlight the area to gut:
   ```

   There is no "the whole drawing" answer. LINGUTTER erases what it
   sweeps, so it sweeps only what you showed it — highlight nothing and
   it says so and stops.

   Then, whenever something was highlighted, both commands ask once:

   ```
   Keep CROSS DIMENSIONS? [Yes/No] <Yes>:
   ```

   Answered Yes, a `CROSS DIM*` dimension inside the perimeter or
   connected to it survives; answered No, it gets no exemption and is
   judged like any other style. This is the only question either
   command asks — it is not a confirmation to erase, which neither
   command ever asks for.

**Run `LINGUTTERSCAN` first on a sheet you care about.** LINGUTTER does
not confirm before it erases, so this is the one chance to see what it
would keep and drop beforehand: did it find the right loop, and is it
about to drop a dimension you wanted?

## Tunables

`setq` them after loading — in a startup file, say — when a drawing
needs different names.

| Tunable | Default | Meaning |
| --- | --- | --- |
| `lg:*poollayer*` | `"POOL"` | layer the perimeter is drawn on |
| `lg:*poolcolor*` | `4` (cyan) | its colour, when the layer has to be created |
| `lg:*anystyles*` | `("CROSS DIM*")` | dim styles kept when "Keep CROSS DIMENSIONS?" is Yes and the dim reads as a genuine cross measurement of the pool, as wildcard patterns matched against the style name |
| `lg:*perimstyles*` | `("STANDARD*" "SIDE STANDARD*" "ALT STANDARD*")` | dim styles kept only when they dimension the perimeter — on it, and not a part of one side |
| `lg:*keeplayers*` | `nil` | layers left alone entirely |
| `lg:*skiplayers*` | `("DEFPOINTS" "DIMENSION")` | layers the perimeter is never traced from, inside a block reference as well as out |
| `lg:*skipblocks*` | `("PAD*" "DRAIN*")` | block **names** the perimeter is never traced from, as wildcard patterns — what sits *on* a pool rather than bounding it |
| `lg:*ontol*` | `1.0` | how far a dim's attachment point may sit off the perimeter and still count as on it |
| `lg:*snaps*` | `(0.05 6.0 24.0)` | the snap ladder: how far apart two ends may be and still count as one point, tried tightest first |
| `lg:*cover*` | `0.8` | how much of the highlight's extent a traced exterior must span before it is believed |
| `lg:*crossspan*` | `0.8` | how much of the perimeter's own bounding box a kept `lg:*anystyles*` dim must span, in X or Y, to count as a full cross measurement rather than a small local one |
| `lg:*runpaddle*` | `T` | `nil` to stop after the gut |

The style lists are wildcards, so `lg:*anystyles*` catches a drawing
whose style is spelled `CROSS DIM` and one spelled `CROSS DIMENSIONS`;
case is folded, because `wcmatch` does not.

They all live in one block at the top of `LINGUTTER.lsp`, above the
first `defun`, each with its explanation on the line — nothing settable
is anywhere else in the file, and nothing in that block is working
state. `tests/test_lingutter.py` checks that, so it stays true.

**The ladder's order is not yours to get right.** `lg:ladder` sorts
`lg:*snaps*` tightest-first and drops anything that is not a tolerance
above zero, because the walk climbs it a rung at a time and calls the
first rung *"nothing had to be moved"*. Typed loosest-first, an
unsorted ladder would heal a 24" gap and report that nothing moved —
the one thing this tool promises never to be quiet about. Set to
nothing usable, it means no snapping at all rather than no walk at all,
so an outline drawn closed still traces.

## Notes & limitations

* **`lg:*perimstyles*` covers the whole `STANDARD` family**, by
  wildcard. A perimeter side or a 1" corner chamfer that `AUTODIM` put
  in `STANDARD INCHES` is kept; so is the `STANDARD-1` that AutoCAD
  renames `STANDARD` to when a paste brings in a second definition, and
  so are the half- and double-scale variants (`SIDE STANDARD 0.5`,
  `STANDARD(2X)`). What stops that from keeping a **step's** dimensions
  is the partial-read half of the rule, not the style list: a step built
  against a pool wall has its risers and treads dimensioned *along* that
  wall, so both ends of a 16" tread dim sit exactly on the perimeter.
  "The start of one side to the end of it" is a side dimension; "two
  points partway along one side" is a reading of something lying against
  it, and it goes with the step. Narrow the list to `("STANDARD" "SIDE
  STANDARD")` for the old behaviour — either way the report counts every
  dropped dimension and says which of the two it failed.
* **"Keep CROSS DIMENSIONS?" answered No** drops every `lg:*anystyles*`
  dimension like any other style not in `lg:*perimstyles*` — counted in
  the report, not silently.
* **A `lg:*anystyles*` dim is judged by shape, not just location.** A
  small one entirely inside the pool, touching nothing, is kept no more
  than a stray one outside it is — `lg:*crossspan*` and vertex-to-vertex
  are what a genuine cross measurement has to satisfy. "The start of
  one edge to a random point along that SAME edge" satisfies neither
  one on purpose, even when it spans most of the pool by accident.
* The perimeter is **always redrawn**, even when it was already one
  closed polyline on `POOL`, so the result is the same object whatever
  went in. An *associative* dimension attached to the old geometry
  loses its association; its measurement and definition points do not
  move, because the new polyline runs through the same points.
* A **locked** layer is unlocked for the erase and locked again
  afterwards — `entdel` refuses an entity on a locked layer, and a run
  that skipped this would quietly leave half the drawing behind. A
  **frozen or switched-off** layer is not thawed — you cannot highlight
  what you cannot see, so it stays out of the sweep entirely.
* An **ordinate** dimension is judged by 13 and 14 like any other,
  and its 14 is the end of its leader out in space -- so an
  ordinate dim will normally be dropped whatever style it is in.
  None of the sheets these tools draw uses them.
* LINGUTTER stops with nothing erased only when the highlight holds no
  drawable geometry at all. Short of that there is always an answer — a
  walked exterior, or failing that a hull — and the report says which
  and at what tolerance.
* **Snapping moves a corner**, by up to the rung that healed the gap.
  A 6" rung can shift a corner 6". That is the price of closing an
  outline that was not closed, and the report names the rung so it is
  never a surprise.
* The walk uses **endpoint connectivity only** — it does not compute
  crossings. An **end** landing in the middle of another segment *is* a
  junction and splits it (a T: a ledge meeting an unbroken wall), but
  two lines that **cross** mid-span without sharing an endpoint are
  not. CAD outlines meet at endpoints, so this costs nothing in
  practice and keeps the walk fast and exact. One consequence worth
  knowing: a pad block dropped onto a corner only crosses the walls,
  so even with `lg:*skipblocks*` emptied it forms its own piece rather
  than joining the pool's outline — and loses on area.
* **A block reference is traced from and then swept**, like the lines it
  replaces. `lg:*skipblocks*` is the list of names that are not outline:
  `PADDLE`'s pads sit centred on a corner with half of each one outside
  the loop, so a pool gutted a second time would trace round its own
  pads. A reference scaled **unevenly** turns its arcs into ellipses,
  which a bulge cannot hold: those arcs are read as their chords, and
  that is the one place the reading is approximate. A mirrored one is
  exact — the bulge changes sign with the turn.
* **Welding a run** never moves the outline: a run only welds when the
  edges are one curve to within a millionth of an inch, which is the
  float noise of the split that made them, not a drafting tolerance. A
  run the whole way round is never welded, because a full circle has no
  bulge to carry it.
* `PADDLE` lives in its own file. When this session has not loaded it,
  the gut still happens and LINGUTTER says so instead of dying on an
  undefined function. `tools/check_lisp.py` lists `c:PADDLE` under
  *undefined fns* for the same reason — it is a deliberate reference out
  of the file, guarded at the call site.
* `lg:arcdata`, `lg:area`, `lg:lwverts`, `lg:plverts`, `lg:vts->segs`
  and `lg:ent-segs` are **a port of PADDLE's** `paddle--arcdata`,
  `--area`, `--lwverts`, `--plverts`, `--vts->segs` and `--ent-segs`.
  A standalone file cannot call into another one, so the copies are
  pinned by a parity test rather than by good intentions (below).
  PADDLE's `--chain` is **not** ported: chaining segments end to end
  finds *a* loop, which is exactly the guess this tool exists to stop
  making. The outer-face walk reads those segments instead.
* The whole run is **one undo group**, so a single `U` puts the drawing
  back — in a drawing that is recording undo. With undo control off
  there is no group to open, so the gut still happens but a `U` will
  not take it back in one step. The command opens no group it cannot
  close either way.
* `CLAYER`, `CMDECHO` and `OSMODE` in force before the command are
  restored afterwards, whether the run finishes, errors, or is cancelled
  with Esc — and before `PADDLE` starts, so it runs from the user's own
  settings rather than this command's zeroed `OSMODE`.

## Tests

`python3 tests/test_lingutter.py` loads the real `LINGUTTER.lsp` into
the repo's AutoLISP VM (`tests/lispvm.py`) and runs it against drawings
built entity by entity: a pool with a hopper inside it, an arc corner
that has to survive as a bulge, traces with a 3" gap and a 24" one,
dimensions in all four styles on and off the perimeter, a radius dim, a
dim with only one end on the edge, a viewport, `lg:*keeplayers*`, and
the whole command end to end — the redrawn polyline, the six surviving
dimensions, the undo group, the restored `OSMODE`, that it erases
without asking, and `LINGUTTERSCAN` changing nothing.

The four things the walk reads besides lines on the outline have
sections of their own, each built as the thing it stands for: a tanning
ledge meeting an **unbroken** wall mid-span (and the wall split exactly
where it meets it, not before or after); a bottom break wall-to-wall
whose two split points come back **out** again, and an arc split by a
tie line coming back as **one** bulge; a bench drawn as an arc bulging
out **over** the pool's own top edge, where the perimeter has to take
the arc and not the chord, with a tie line up to it that is still
interior; and a step as an `FG_STEP` block reference, plain and rotated,
with a `Pad36x36` reference proving `lg:*skipblocks*` keeps a pad out
and that emptying the knob is what changes that.

A radius or diameter dim on the perimeter in a style that is neither
`lg:*anystyles*` nor `lg:*perimstyles*` (`STANDARD INCHES`, the one
`AUTODIM` actually uses under a foot) is its own section, and a short
side of an L-shaped perimeter proves the same rule holds corner to
corner regardless of style there too. So are the three shapes of a
radial dim written the way AutoCAD writes one, with group 10 as the
**centre**: the arrow landing on a traced arc, the arrow dragged round
**past** the arc's end so that only the centre-and-radius match can
keep it, `R3 typ.` on a corner drawn sharp, and — the false positive the
vertex test has to avoid — an interior arc whose centre lands on the
perimeter, which is not a perimeter call-out.

"Keep CROSS DIMENSIONS?" is its own section as well: answered Yes, a
cross dim corner to corner, one running side to side through the
middle of each side (still "goes full Y"), a short perimeter edge kept
on its two vertices alone (under `lg:*crossspan*` on its own), a small
one entirely inside touching nothing, one from a corner to a random
point along that SAME side (dropped even though it spans most of the
width), and a stray one touching neither are all told apart; answered
No, every one of them loses its exemption and is named by the answer
in the drop tally, while the radius/diameter rule is shown not to care
which way that question goes.

The scoping has a section of its own: a pool beside a *bigger* closed
rectangle with its own clutter — a title block border is exactly this
shape of problem — highlighting only the pool, and checking that every
object outside the highlight is still standing, that the perimeter is
the pool's and not the bigger loop, and that handed the whole drawing
instead it *would* have taken the bigger loop. Then that `PADDLE` is
handed exactly the one new polyline, so it never auto-detects past the
highlight.

It also loads `PADDLE.lsp` alongside and runs both chaining
implementations on the same geometry, so the port cannot drift: when
PADDLE's chaining changes, port the change into `LINGUTTER.lsp` and the
test goes green again.

`CALOFIN_LISP_ROOT=shared python3 tests/test_lingutter.py` runs the same
suite against the grouped build.
