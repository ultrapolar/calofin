# POOLPERIM — Perimeter only, then pads

An AutoLISP routine for AutoCAD 2018+ that reduces a finished drawing to
three things — the **outermost perimeter**, redrawn as one closed
polyline on the **`POOL`** layer; the **dimensions worth keeping**; and
the pads **`PADDLE`** puts on it — and erases everything else.

An as-built sheet carries far more than the next station needs: the
hopper and its slope lines, steps, survey points and their labels, the
title block, the notes. POOLPERIM strips it back in one pass, and asks
before it does.

## What it does

1. **Traces the perimeter.** Every `LINE`, `ARC`, `LWPOLYLINE` and
   `POLYLINE` in the current tab is broken into segments and chained
   end to end into closed loops — the same chaining `PADDLE` uses, so
   loose lines and arcs are as good an input as a drawn polyline. The
   loop enclosing the **largest area** is the outermost one, and that
   is the perimeter. A trace that never quite closed is shut with a
   straight segment when its two ends finished within `pp:*gap*` of
   each other, and the run says how big a gap it closed.
2. **Redraws it as one object.** The perimeter is written back as a
   single **closed `LWPOLYLINE`** on the `POOL` layer, arcs carried as
   bulges, **ByLayer** — no per-entity colour, linetype or lineweight —
   so the result is one polyline whatever went in: one polyline, or
   fifty loose lines and arcs.
3. **Keeps two kinds of dimension**, and nothing else survives:

   | Kept | Rule |
   | --- | --- |
   | `CROSS DIM*` — matches both `CROSS DIM` and this repo's `CROSS DIMENSIONS` | **wherever it sits.** A cross dim spans the pool, so most of it is nowhere near the edge |
   | `STANDARD`, `SIDE STANDARD` | **only on the perimeter** — every one of its attachment points within `pp:*ontol*` of the loop |

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
4. **Erases everything else** — text, blocks, points, hatches, the title
   block, the geometry the perimeter was traced from, and dimensions in
   any other style. `VIEWPORT` entities are never erased, and a layer
   named in `pp:*keeplayers*` is spared outright.
5. **Runs `PADDLE`**, which pads the concave features of the one loop
   now left. Press Enter at PADDLE's selection prompt to let it take
   that loop.

Before erasing anything it prints exactly what it found — how many
vertices the perimeter has and how far round it is, how many dimensions
are kept under each rule, and **how many are dropped, counted by
reason** — then asks, defaulting to `No`. Nothing disappears silently:
a `STANDARD INCHES` dim sitting on the perimeter is reported as
`3 x STANDARD INCHES - style not kept`, not quietly deleted.

The whole run is one undo group, so a single `U` puts the drawing back.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `POOLPERIM.lsp`. Add it to the *Startup Suite* to have it in
   every drawing. Load `PADDLE.lsp` too, or step 5 is skipped with a
   note.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `POOLPERIM` | trace the perimeter, erase the rest, run `PADDLE` |
   | `POOLPERIMSCAN` | print the same report and stop — nothing in the drawing is changed |
   | `POOLPERIMVER` | print the loaded version |

   Both commands open with

   ```
   Select the geometry to trace the perimeter from (Enter = the whole drawing):
   ```

   Enter reads the whole tab, which is the usual answer. Select
   geometry instead to trace the perimeter from part of the drawing —
   the *keep* rules still sweep the whole tab.

**Run `POOLPERIMSCAN` first on a sheet you care about.** It answers the
one question worth knowing in advance: did it find the right loop, and
is it about to drop a dimension you wanted?

## Tunables

`setq` them after loading — in a startup file, say — when a drawing
needs different names.

| Tunable | Default | Meaning |
| --- | --- | --- |
| `pp:*poollayer*` | `"POOL"` | layer the perimeter is drawn on |
| `pp:*poolcolor*` | `4` (cyan) | its colour, when the layer has to be created |
| `pp:*anystyles*` | `("CROSS DIM*")` | dim styles kept wherever they sit, as wildcard patterns matched against the style name |
| `pp:*perimstyles*` | `("STANDARD" "SIDE STANDARD")` | dim styles kept only on the perimeter |
| `pp:*keeplayers*` | `nil` | layers left alone entirely |
| `pp:*skiplayers*` | `("DEFPOINTS" "DIMENSION")` | layers the perimeter is never traced from |
| `pp:*ontol*` | `1.0` | how far a dim's attachment point may sit off the perimeter and still count as on it |
| `pp:*fuzz*` | `0.05` | largest gap between two segment ends that still chains them |
| `pp:*gap*` | `6.0` | largest end-to-end gap POOLPERIM will close |
| `pp:*runpaddle*` | `T` | `nil` to stop after the strip |

The style lists are wildcards, so `pp:*anystyles*` catches a drawing
whose style is spelled `CROSS DIM` and one spelled `CROSS DIMENSIONS`;
case is folded, because `wcmatch` does not.

## Notes & limitations

* **`STANDARD INCHES` is deliberately not in `pp:*perimstyles*`.** The
  two styles kept on the perimeter are `STANDARD` and `SIDE STANDARD`.
  A perimeter side under 12" that `AUTODIM` put in `STANDARD INCHES`
  therefore goes with the rest — reported by style, never silently. Add
  the style to `pp:*perimstyles*` to keep those too.
* The perimeter is **always redrawn**, even when it was already one
  closed polyline on `POOL`, so the result is the same object whatever
  went in. An *associative* dimension attached to the old geometry
  loses its association; its measurement and definition points do not
  move, because the new polyline runs through the same points.
* Only the **current tab** is read and changed. Another layout is
  untouched.
* A **locked** layer is unlocked for the erase and locked again
  afterwards — `entdel` refuses an entity on a locked layer, and a run
  that skipped this would quietly leave half the drawing behind. A
  **frozen or switched-off** layer is not thawed: what POOLPERIM cannot
  see it does not trace from, though `ssget "_X"` still reaches it to
  erase.
* An **ordinate** dimension is judged by 13 and 14 like any other,
  and its 14 is the end of its leader out in space -- so an
  ordinate dim will normally be dropped whatever style it is in.
  None of the sheets these tools draw uses them.
* When **nothing closes** — no loop, and no open trace finishing within
  `pp:*gap*` of its own start — POOLPERIM reports it and stops. Nothing
  is erased, because it does not know what the perimeter is. Check for
  gaps, or select the perimeter geometry yourself.
* `PADDLE` lives in its own file. When this session has not loaded it,
  the strip still happens and POOLPERIM says so instead of dying on an
  undefined function. `tools/check_lisp.py` lists `c:PADDLE` under
  *undefined fns* for the same reason — it is a deliberate reference out
  of the file, guarded at the call site.
* `pp:arcdata`, `pp:area`, `pp:ent-segs` and `pp:chain` are **a port of
  PADDLE's** `paddle--arcdata`, `--area`, `--ent-segs` and `--chain`.
  A standalone file cannot call into another one, so the copies are
  pinned by a parity test rather than by good intentions (below).
  `pp:chain` differs in one deliberate way: PADDLE counts the open
  chains and throws them away, POOLPERIM keeps them, because a perimeter
  drawn with one missed snap is still the perimeter.
* `CLAYER`, `CMDECHO` and `OSMODE` in force before the command are
  restored afterwards, whether the run finishes, errors, or is cancelled
  with Esc — and before `PADDLE` starts, so it runs from the user's own
  settings rather than this command's zeroed `OSMODE`.

## Tests

`python3 tests/test_poolperim.py` loads the real `POOLPERIM.lsp` into
the repo's AutoLISP VM (`tests/lispvm.py`) and runs it against drawings
built entity by entity: a pool with a hopper inside it, an arc corner
that has to survive as a bulge, traces with a 3" gap and a 24" one,
dimensions in all four styles on and off the perimeter, a radius dim, a
dim with only one end on the edge, a viewport, another layout,
`pp:*keeplayers*`, and the whole command end to end — the redrawn
polyline, the five surviving dimensions, the undo group, the restored
`OSMODE`, the handover to a stubbed `PADDLE`, `No` meaning no, and
`POOLPERIMSCAN` changing nothing.

It also loads `PADDLE.lsp` alongside and runs both chaining
implementations on the same geometry, so the port cannot drift: when
PADDLE's chaining changes, port the change into `POOLPERIM.lsp` and the
test goes green again.

`CALOFIN_LISP_ROOT=shared python3 tests/test_poolperim.py` runs the same
suite against the grouped build.
