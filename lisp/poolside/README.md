# POOLSIDE -- the pool side view on its own (AutoLISP / AutoCAD 2018+)

## What it does

Draws the **longitudinal section** of a pool -- the side POV -- from the
floor dimensions alone.

`POOL` already draws this section, but only as a by-product of a full
as-built plan: the shape, the perimeter, the corner treatments and, out
of square, the cross dims all have to be answered before it ever asks a
depth, and for a `Normal` hopper no section appears at all. When the
side view *is* the job -- a section to hang under someone else's plan, a
depth study, a floor chain being checked against the order sheet --
`POOLSIDE` asks for the floor dimensions and draws it.

The letters are POOL's, unchanged, so a field sheet transcribes straight
across:

| Letter | What it is |
| --- | --- |
| `B` | overall length, wall to wall |
| `C` | wall height -- the shallow depth |
| `D` | deep end depth |
| `C2` | depth where the shallow floor meets the break (`SHallow` only) |

and the run chain, left to right, which always adds up to `B`:

| Bottom type | Runs | The floor |
| --- | --- | --- |
| `Normal` | `H G F E` | slope down, hopper pad, slope up, shallow flat |
| `SHallow` | `H G F E` | the same, but the shallow floor slopes from `C2` at the break up to `C` at the wall |
| `SLope` | `H F E` | no pad -- a deep line at `H`, then up to a break and flat |
| `Wedge` | `H F` | a deep line at `H`, floor rising all the way to the far wall |
| `MOdflat` | `H G F` | one flat pad, sloping up to both walls, no shallow flat |
| `Sport` | `E2 F2 G F1 E1` | symmetric: a shallow flat at each end, a deep flat between the slopes |

```
   C  --.___                    ___.--  C          <- waterline
         |   \__            ____/    |
         |      \__________/         |
    |-H--|---G---|----F----|----E----|
```

Answering `G` as `0` collapses the pad on the spot: a `Normal` becomes a
slope bottom, a `Sport` becomes a V bottom. Nothing else has to change.

**Answers it works out for you.** Any run may be answered `NA` and is
read back off `B` -- two `NA`s split the remainder evenly. When every run
*is* given but they miss `B`, the pad (`G`, or `F` where the style has no
pad) absorbs the difference, so the walls stay where the overall put
them. A run that resolves *negative* -- the field sheet disagreeing with
itself -- is floored to a positive length, the deficit comes out of the
largest other run, both dimensions are drawn **red** and a note goes
under the section. This is `POOL`'s own resolver (`pool:chainfix` /
`pool:chainval`), ported, so the two tools agree on the same sheet.

**While you type.** A gray nominal section is on screen from the moment
`B` is answered, with a lettered tie per question and the tie being asked
for lit up **red**, so the letters mean something before the pool exists.
It deletes itself once the answers are in. Every question after the first
offers `Back`, which re-asks the previous one -- and `Back` walks the
depths as well as the runs, so a mistyped `C` steps back into `E` rather
than costing you the run.

**What is drawn:** the waterline, a wall of height `C` at each end and
the floor between them on layer `POOL`; the overall `B` above, the run
chain on one baseline below and `C` / `D` / `C2` where they fall, all on
`DIMENSION`; any adjustment notes on `POOL-NOTES`. Those are `POOL`'s own
three layers, so a `POOLSIDE` section drops under a `POOL` plan without a
layer to reconcile.

## Install & run

APPLOAD `POOLSIDE.lsp` (or the dated twin in `releases/`), then:

```
POOLSIDE      draw the side view from the floor dimensions
POOLSIDEVER   print the loaded version
```

In the grouped build it arrives with everything else -- APPLOAD
`shared/LAZPASS.lsp`.

The run, in order: bottom type, insertion base point (the **top left** of
the section -- the waterline at the left wall), `B`, the run chain, the
depths, then whether the deep end goes on the right. Distances may be
typed as `8'6"`, `8'-6-1/2"` or `8'6.5` as well as plain inches --
`POOLSIDE` switches the drawing to architectural units while it asks and
puts your setting back.

## Tunables

| Global | Default | What it does |
| --- | --- | --- |
| `psd:*smalldim*` | `24.0` | runs under this are dimensioned in the small-dim style |
| `psd:*smallstyle*` | `"STANDARD INCHES"` | that style, when the drawing has one; otherwise the current style, said once |
| `psd:*pv-col*` / `psd:*pvx-col*` / `psd:*hi-col*` | `8` / `7` / `1` | guide outline, guide tie, and the highlight on the tie being asked |

The nominal guide is drawn at `0.09 * B` for `C` and `0.20 * B` for `D`
(about 3'6" and 8' on a 40' pool) with the run proportions of
`psd:nominal` -- it is a picture of the letters, never a suggestion, and
nothing it shows survives into the drawing.

## Notes & limitations

* **The section only.** No plan, no perimeter, no corner treatments, no
  cross dims, no report table. Draw those with `POOL`.
* **Depths are checked, runs are resolved.** `D` must be deeper than `C`
  and `C2` must land between them; either failing re-asks that question.
  The runs are never rejected -- they are resolved against `B` and
  flagged, per above.
* The floor is drawn as individual lines, the way `POOL` draws its
  section, not as one closed polyline -- so the section has no area and
  cannot be hatched without boundary work first.
* Mirroring (deep end on the right) flips the section and its run
  dimensions end for end. The letters keep their meaning: `H` is still
  the wall-to-deep-end run, it is simply on the other side.
* A `SHallow` bottom whose `C2` is answered equal to `C` draws the same
  floor a `Normal` does. That is arithmetic, not a bug.
* Not to be confused with `AUTODIMSIDEPOV` (`lisp/autodim/`), which
  dimensions a flight of **steps** already drawn in side view.
  `POOLSIDE` draws the pool's own section and dimensions it as it goes;
  the two do not overlap.

## Tests

```
python3 tests/test_poolside.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_poolside.py # grouped tier
```

Both tiers drive `c:POOLSIDE` end to end in the AutoLISP VM: one run per
bottom type, the `NA` / slack / negative-run paths, `G = 0` on a hopper
and on a Sport, the mirror, the two depth range checks, `Back`, the
small-dim style switch, and that the user's `OSMODE` and `LUNITS` come
back.
