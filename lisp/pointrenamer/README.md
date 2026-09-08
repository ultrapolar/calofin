# POINTRENAMER -- renumber survey points in perimeter order (AutoLISP / AutoCAD 2018+)

## What it does

A survey comes back numbered in the order the crew shot it, which is no
order at all by the time the pool is drawn.  `POINTRENAMER` reprograms
the numbers so they run round the pool instead:

1. **Highlight the area** (Enter = everything in the tab you are
   looking at -- the same scope the clash warning sweeps).  Points and
   polylines are all it keeps.
2. **The perimeter is found** -- the biggest closed polyline on layer
   `POOL` in the highlight (the shape `ABHD` and `LINGUTTER` leave
   behind), or the only closed polyline there when `POOL` has none.
   Enter takes it; a click on any polyline, circle, line or arc
   overrides it, so a spa ring or an odd layer is one pick away.  A
   click that hits nothing says so rather than quietly falling back on
   what was found, and a perimeter with no length to sweep is refused
   and then stops being offered.
3. **Pick where the count starts.**  The pick is dropped onto the
   nearest spot on the perimeter (and the command says so when it had
   to travel more than a foot).
4. **Say which way round** -- `Clockwise` or `COunterclockwise`,
   meaning on the sheet: the polyline's own winding is measured (bulges
   included) and the sweep runs against its drawn order when it has to.
5. **Say how far off the perimeter still counts as on it** -- the band,
   in feet-and-inches, remembered for the session (6" to start with).
6. **Say what number to start at** (Enter = 1), then confirm the split
   it shows.

Every point on the perimeter or within the band is renumbered
sequentially, sweeping from the picked spot in the chosen direction.
Points the band does not catch -- a spa shot, the equipment pad, a
stray -- **continue the count** after the loop is closed, swept in the
same direction by where each sits against the perimeter, so the
leftovers read round the sheet too.

The old-to-new table is printed so a callout written against the old
numbers can be chased afterwards, points that carry no number at all
(plain `POINT` entities, blocks with no attribute) are counted out loud
and left alone, and a warning names any point block *outside* the
highlight already holding a number in the handed-out range.  A number
that could not be written -- a locked layer is the everyday reason --
is marked `NOT WRITTEN` on its row and counted at the end, so the table
never shows a rename the drawing did not take.  The whole renumber is
one `U`.

What counts as a point is `ABPCHECK`'s definition, unchanged: every
`ab_pt` block wherever it sits and any other block on the `POINTS`
layer, the number living in the `number` attribute -- or, when a block
has no such tag, the first attribute already holding something numeric,
which is exactly where every reader in this toolset looks.  Distance
and position along the perimeter are measured to the run itself, arcs
included, not to its endpoints.

## Install & run

APPLOAD `POINTRENAMER.lsp` (or the dated twin in `releases/`), then:

```
Command: POINTRENAMER
```

`POINTRENAMERVER` prints the loaded version.  In the shared build both
come in with `shared/LAZPASS.lsp`, and the panel button sits on the
Points page.

Every question past the first offers `Back` (`Undo` is its unlisted
synonym); `Back` at the perimeter pick reopens the highlight.

## Tunables

**Every** knob is in the `TUNABLES` block at the top of the file, each
with a comment saying what it does and what moving it costs; past that
block nothing is a bare number.  Edit a line and re-APPLOAD for good,
or `(setq ptr:*band* 3.0)` at the command line for one drawing.

*What counts as a point* -- `ABPCHECK`'s definition, so the two tools
never disagree:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ptr:*pt-layer*` | `"POINTS"` | layer whose blocks count as points |
| `ptr:*pt-block*` | `"ab_pt"` | block name that counts wherever it sits |
| `ptr:*pt-tag*` | `"number"` | the attribute the number lives in |

*What counts as the perimeter:*

| Variable | Default | Meaning |
| --- | --- | --- |
| `ptr:*perim-layer*` | `"POOL"` | layer the perimeter is looked for on |
| `ptr:*filter*` | `POINT,INSERT,LWPOLYLINE,POLYLINE` | what the highlight may keep |
| `ptr:*vertex-skip*` | `16` | heavy-`POLYLINE` vertex flags that are **not** on the drawn curve -- the spline frame.  Curve- and spline-**fit** vertices are the curve the sheet shows, so they are walked; `17` restores the pre-v1.4 walk that dropped them |

*What the questions start at:*

| Variable | Default | Meaning |
| --- | --- | --- |
| `ptr:*band*` | `6.0` | the band; the answer replaces it for the session |
| `ptr:*dir*` | `"Clockwise"` | last direction, replaced the same way |
| `ptr:*first*` | `1` | the number the count is offered at (not carried between runs) |
| `ptr:*sysvars*` | `("CMDECHO")` | saved on the way in, restored however the run ends |

*What the report looks like:*

| Variable | Default | Meaning |
| --- | --- | --- |
| `ptr:*far-pick*` | `12.0` | a start pick further off than this is called out |
| `ptr:*name-width*` | `8` | column the old number is padded to |
| `ptr:*dist-mode*` / `ptr:*dist-prec*` | `4` / `4` | the `rtos` mode and precision every distance is written with -- feet-and-inches to a sixteenth |

*Tolerances* -- `ptr:*exact-eps*`, `ptr:*zero-len*`, `ptr:*bulge-eps*`,
`ptr:*flat-eps*`, `ptr:*tiny-len2*`, `ptr:*whole-eps*`,
`ptr:*start-whisker*`.  Named so
nothing in the code is an unexplained number, not so they can be tuned:
each is a floating-point noise floor, in inches.  The one number left
in the body is the clamp inside the generic tangent helper, which the
grouped build takes from `CALOFIN-LIB` -- a knob there would be read at
one tier and ignored at the other.

## Notes & limitations

* Plain `POINT` entities have nowhere to hold a number, so they are
  counted and left alone rather than silently skipped -- `BPCALLOUT`
  and `ABPCHECK` will keep calling them by reading order.
* A moved copy made by `ABMOVE` (`Pt.17m`) is its own block and gets
  its own new number; the `m` marker does not survive a renumber.
* Splines and ellipses cannot be the perimeter -- the segment math does
  not cover them, and the pick says so instead of guessing.  A heavy
  `POLYLINE` that has been *fitted* is walked along the fitted curve
  (see `ptr:*vertex-skip*`).
* `Enter` at the highlight means the current tab, not every tab: points
  in a layout you are not looking at are left alone, which is also the
  only scope the clash warning can see.
* Two shots on the same spot get consecutive numbers (nothing is
  deduplicated -- every block must end up with a number).
* The renumber rewrites attribute text only: layers, colours, scales
  and positions are untouched.

## Tests

```
python3 tests/test_pointrenamer.py                          # standalone
CALOFIN_LISP_ROOT=shared python3 tests/test_pointrenamer.py # grouped
```

Covers both sweep directions against hand-worked stations, the band
split and the continued count, arcs (a bulged perimeter and a circle
picked by hand), the Back chain, answering `No`, the skip counts, and
the clash warning -- plus the contingencies: a mis-click at the
perimeter pick, a perimeter with no length, a fitted heavy `POLYLINE`
walked both ways round `ptr:*vertex-skip*`, a write that cannot land, a
band that catches nothing, the current-tab scope, what the numeric
prompts refuse, the band edge, and every knob above set to something
else and followed.
