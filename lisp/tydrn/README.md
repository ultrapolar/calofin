# TYDRN -- pool-only cleanup of a drone trace (AutoLISP / AutoCAD 2018+)

Applies the standardizing fixes to a traced drone drawing in one
command: point-label text onto the office style, the pool's survey
points onto `POINTS`, the anchor points recoloured, and every label
rotated to read west to east.

TYDRN is the sibling of `DRONE` (`lisp/drone/`) minus the two spa
steps: it does not sweep POINTs off layer `SPA` and it does not move
a spa outline onto `POOL` -- layer `SPA` is never touched at all. Use
TYDRN on a pool-only trace, or when whatever sits on `SPA` must stay
put; use `DRONE` for a pool + spa job.

## What it does

1. **TEXT** -- every highlighted (pre-selected) text entity is
   switched to style `ROMANC` at height 4.5, with color, linetype and
   lineweight forced to BYLAYER. If nothing is highlighted you are
   prompted to select text; Enter at that prompt processes ALL text in
   the drawing.
2. **POOL POINTS** -- every POINT entity on layer `POOL` (anywhere in
   the drawing) is moved to layer `POINTS`, everything BYLAYER
   (`POINTS` is magenta, so they show pink).
3. **ANCHOR POINTS** -- every POINT on layer `ANCHORS` is given an
   explicit magenta (ACI 6) color -- the same pink as the points --
   but stays on `ANCHORS`.
4. **ORIENT** -- the processed text is rotated flat so it reads west
   to east, right side up (absolute angle 0). Each text pivots about
   its own insertion point -- the labels share that point in space
   with the POINT they belong to -- so every label stays anchored to
   its point.

The `ROMANC` text style and the `POINTS` layer are created if missing.
Locked layers among those touched are unlocked for the run and
re-locked afterwards (on error too). The whole run is one undo mark,
and a done-line reports the counts.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `tydrn.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Optionally pre-select the label text, then:

| Command | What it does |
| --- | --- |
| `TYDRN` | Run the fixes in one pass |

## Tunables

At the top of `tydrn.lsp`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*tydrn-text-style*` | `"ROMANC"` | Style the text is switched to (created from the font below) |
| `*tydrn-text-font*` | `"romanc.shx"` | Font file for that style |
| `*tydrn-text-height*` | `4.5` | Text height applied |
| `*tydrn-pool-layer*` | `"POOL"` | Layer whose POINTs move |
| `*tydrn-dest-layer*` | `"POINTS"` | Where those POINTs go |
| `*tydrn-anch-layer*` | `"ANCHORS"` | Layer of the anchor POINTs |
| `*tydrn-pink*` | `6` (magenta) | Color for anchors and the POINTS layer |
| `*tydrn-orient-angle*` | `0.0` | Absolute text angle in degrees; set to `nil` to only flip upside-down text instead ("Most readable") |

## Notes & limitations

* Only single-line `TEXT` entities are restyled -- MTEXT, attributes
  and dimension text are left alone.
* Steps 2 and 3 sweep the whole drawing (`ssget "_X"`), not just a
  selection -- only the TEXT step is scoped by what you highlight.
* Rotating about the insertion point assumes each label was placed on
  its survey point; a label whose insertion point sits elsewhere
  swings about that spot instead.
* Loading TYDRN and DRONE together is safe -- separate `tydrn:` /
  `drone:` namespaces -- and the shared build carries both.
* Requires the Visual LISP engine (ActiveX is used throughout), which
  ships with full AutoCAD. AutoCAD LT cannot run this file.

## Tests

No dedicated test drives TYDRN yet. `python3 tests/test_shared.py`
loads it (with everything else) into the repo's AutoLISP VM, so a
file that no longer parses, or that collides with another tool's
names, fails there.
