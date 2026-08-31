# POINTRENAMER -- renumber survey points in perimeter order (AutoLISP / AutoCAD 2018+)

## What it does

A survey comes back numbered in the order the crew shot it, which is no
order at all by the time the pool is drawn.  `POINTRENAMER` reprograms
the numbers so they run round the pool instead:

1. **Highlight the area** (Enter = the whole drawing).  Points and
   polylines are all it keeps.
2. **The perimeter is found** -- the biggest closed polyline on layer
   `POOL` in the highlight (the shape `ABHD` and `LINGUTTER` leave
   behind), or the only closed polyline there when `POOL` has none.
   Enter takes it; a click on any polyline, circle, line or arc
   overrides it, so a spa ring or an odd layer is one pick away.
3. **Pick where the count starts.**  The pick is dropped onto the
   nearest spot on the perimeter (and the command says so when it had
   to travel more than a foot).
4. **Say which way round** -- `Clockwise` or `COunterclockwise`,
   meaning on the sheet: the polyline's own winding is measured (bulges
   included) and the sweep runs against its drawn order when it has to.
5. **Say how far off the perimeter still counts as on it** -- the band,
   in inches, remembered for the session (6" to start with).
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
highlight already holding a number in the handed-out range.  The whole
renumber is one `U`.

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

At the top of the file:

| Variable | Default | Meaning |
| --- | --- | --- |
| `ptr:*pt-layer*` | `"POINTS"` | layer whose blocks count as points |
| `ptr:*pt-block*` | `"ab_pt"` | block name that counts wherever it sits |
| `ptr:*pt-tag*` | `"number"` | the attribute the number lives in |
| `ptr:*perim-layer*` | `"POOL"` | layer the perimeter is looked for on |
| `ptr:*band*` | `6.0` | the band, remembered per session |
| `ptr:*dir*` | `"Clockwise"` | last direction, offered as the default |

## Notes & limitations

* Plain `POINT` entities have nowhere to hold a number, so they are
  counted and left alone rather than silently skipped -- `BPCALLOUT`
  and `ABPCHECK` will keep calling them by reading order.
* A moved copy made by `ABMOVE` (`Pt.17m`) is its own block and gets
  its own new number; the `m` marker does not survive a renumber.
* Splines and ellipses cannot be the perimeter -- the segment math does
  not cover them, and the pick says so instead of guessing.
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
the clash warning.
