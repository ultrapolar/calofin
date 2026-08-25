# LINGUTTER — Gut a highlighted area to its perimeter, then pad it

An AutoLISP routine for AutoCAD 2018+ that reduces **the area you
highlight** to three things — the **outermost perimeter** in it, redrawn
as one closed polyline on the **`POOL`** layer; the **dimensions worth
keeping**; and the pads **`PADDLE`** puts on it — and erases everything
else it was shown.

An as-built sheet carries far more than the next station needs: the
hopper and its slope lines, steps, survey points and their labels, the
notes. LINGUTTER guts one pool back in a single pass, and asks before it
does.

> **It works only inside the highlight.** Window the pool — before
> typing the command or at its prompt — and everything below happens to
> that selection and nothing else. What you did not highlight is not
> traced from, not counted and not erased, so a second pool, the title
> block and the rest of the sheet are all safe from it. A crossing
> window takes in whatever it touches, so a dimension half inside the
> highlight is in the sweep and one wholly outside it is not: the
> highlight is the whole of the rule.

## What it does

1. **Traces the perimeter.** Every `LINE`, `ARC`, `LWPOLYLINE` and
   `POLYLINE` **in the highlight** is broken into segments and chained
   end to end into closed loops — the same chaining `PADDLE` uses, so
   loose lines and arcs are as good an input as a drawn polyline. The
   loop enclosing the **largest area** is the outermost one, and that
   is the perimeter. A trace that never quite closed is shut with a
   straight segment when its two ends finished within `lg:*gap*` of
   each other, and the run says how big a gap it closed.
2. **Redraws it as one object.** The perimeter is written back as a
   single **closed `LWPOLYLINE`** on the `POOL` layer, arcs carried as
   bulges, **ByLayer** — no per-entity colour, linetype or lineweight —
   so the result is one polyline whatever went in: one polyline, or
   fifty loose lines and arcs.
3. **Keeps two kinds of dimension**, and nothing else highlighted
   survives:

   | Kept | Rule |
   | --- | --- |
   | `CROSS DIM*` — matches both `CROSS DIM` and this repo's `CROSS DIMENSIONS` | **wherever it sits.** A cross dim spans the pool, so most of it is nowhere near the edge |
   | `STANDARD`, `SIDE STANDARD` | **only on the perimeter** — every one of its attachment points within `lg:*ontol*` of the loop |

   A dimension's *attachment* points are DXF 13 and 14, the two measured
   points of a linear, aligned, ordinate or angular dim. A radius or
   diameter dim carries neither and hangs off group 10, where its arrow
   lands on the curve. Group 11 (the text) and 15/16 (an angular dim's
   second leg, a radius dim's centre) *place* the dimension rather than
   attach it, and are not tested — a radius dim on a 3" fillet would
   otherwise be judged by a centre point 3" inside the pool.

   *Every* attachment point has to be on the perimeter, not just one: a
   dim running from the pool edge in to the hopper is measuring the
   hopper.
4. **Erases everything else it was shown** — text, blocks, points,
   hatches, the geometry the perimeter was traced from, and dimensions
   in any other style. `VIEWPORT` entities are never erased, and a layer
   named in `lg:*keeplayers*` is spared even inside the highlight.
5. **Hands the new perimeter to `PADDLE`** as a pickfirst selection, and
   PADDLE pads its concave features without asking anything. *Handed,
   not hunted:* PADDLE's own auto-detect reads the **whole** drawing for
   its largest closed loop, which after a scoped gut may well be a title
   block border rather than the pool. (This is why `PADDLE` v1.3 takes a
   pickfirst selection as-is.)

Before erasing anything it prints exactly what it found in the
highlight — how many
vertices the perimeter has and how far round it is, how many dimensions
are kept under each rule, and **how many are dropped, counted by
reason** — then asks, defaulting to `No`. Nothing disappears silently:
a `STANDARD INCHES` dim sitting on the perimeter is reported as
`3 x STANDARD INCHES - style not kept`, not quietly deleted.

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

**Run `LINGUTTERSCAN` first on a sheet you care about.** It answers the
one question worth knowing in advance: did it find the right loop, and
is it about to drop a dimension you wanted?

## Tunables

`setq` them after loading — in a startup file, say — when a drawing
needs different names.

| Tunable | Default | Meaning |
| --- | --- | --- |
| `lg:*poollayer*` | `"POOL"` | layer the perimeter is drawn on |
| `lg:*poolcolor*` | `4` (cyan) | its colour, when the layer has to be created |
| `lg:*anystyles*` | `("CROSS DIM*")` | dim styles kept wherever they sit, as wildcard patterns matched against the style name |
| `lg:*perimstyles*` | `("STANDARD" "SIDE STANDARD")` | dim styles kept only on the perimeter |
| `lg:*keeplayers*` | `nil` | layers left alone entirely |
| `lg:*skiplayers*` | `("DEFPOINTS" "DIMENSION")` | layers the perimeter is never traced from |
| `lg:*ontol*` | `1.0` | how far a dim's attachment point may sit off the perimeter and still count as on it |
| `lg:*fuzz*` | `0.05` | largest gap between two segment ends that still chains them |
| `lg:*gap*` | `6.0` | largest end-to-end gap LINGUTTER will close |
| `lg:*runpaddle*` | `T` | `nil` to stop after the gut |

The style lists are wildcards, so `lg:*anystyles*` catches a drawing
whose style is spelled `CROSS DIM` and one spelled `CROSS DIMENSIONS`;
case is folded, because `wcmatch` does not.

## Notes & limitations

* **`STANDARD INCHES` is deliberately not in `lg:*perimstyles*`.** The
  two styles kept on the perimeter are `STANDARD` and `SIDE STANDARD`.
  A perimeter side under 12" that `AUTODIM` put in `STANDARD INCHES`
  therefore goes with the rest — reported by style, never silently. Add
  the style to `lg:*perimstyles*` to keep those too.
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
* When **nothing in the highlight closes** — no loop, and no open trace finishing within
  `lg:*gap*` of its own start — LINGUTTER reports it and stops. Nothing
  is erased, because it does not know what the perimeter is. Check for
  gaps, or highlight the whole outline.
* `PADDLE` lives in its own file. When this session has not loaded it,
  the gut still happens and LINGUTTER says so instead of dying on an
  undefined function. `tools/check_lisp.py` lists `c:PADDLE` under
  *undefined fns* for the same reason — it is a deliberate reference out
  of the file, guarded at the call site.
* `lg:arcdata`, `lg:area`, `lg:ent-segs` and `lg:chain` are **a port of
  PADDLE's** `paddle--arcdata`, `--area`, `--ent-segs` and `--chain`.
  A standalone file cannot call into another one, so the copies are
  pinned by a parity test rather than by good intentions (below).
  `lg:chain` differs in one deliberate way: PADDLE counts the open
  chains and throws them away, LINGUTTER keeps them, because a perimeter
  drawn with one missed snap is still the perimeter.
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
the whole command end to end — the redrawn polyline, the five surviving
dimensions, the undo group, the restored `OSMODE`, `No` meaning no, and
`LINGUTTERSCAN` changing nothing.

The scoping has a section of its own: a pool beside a *bigger* closed
rectangle with its own clutter — a title block border is exactly this
shape of problem — highlighting only the pool, and checking that every
object outside the highlight is still standing, that the perimeter is
the pool's and not the bigger loop, and that handed the whole drawing
instead it *would* have taken the bigger loop. Then that `PADDLE`'s
pickfirst probe finds exactly the one new polyline, so it never
auto-detects past the highlight.

It also loads `PADDLE.lsp` alongside and runs both chaining
implementations on the same geometry, so the port cannot drift: when
PADDLE's chaining changes, port the change into `LINGUTTER.lsp` and the
test goes green again.

`CALOFIN_LISP_ROOT=shared python3 tests/test_lingutter.py` runs the same
suite against the grouped build.
