# DRONE -- one-pass cleanup of a pool + spa drone trace (AutoLISP / AutoCAD 2018+)

Applies five standardizing fixes to a traced drone drawing in one
command: point-label text onto the office style, the pool's and spa's
survey points onto `POINTS`, the spa outline onto `POOL`, the anchor
points recoloured, and every label rotated to read west to east.

For a drawing with no spa -- or one whose `SPA` layer must be left
alone -- use the sibling `TYDRN` (`lisp/tydrn/`), which is this
routine minus the two spa steps.

## What it does

1. **TEXT** -- every highlighted (pre-selected) text entity is
   switched to style `ROMANC` at height 4.5, with color, linetype and
   lineweight forced to BYLAYER. If nothing is highlighted you are
   prompted to select text; Enter at that prompt processes ALL text in
   the drawing.
2. **POOL / SPA POINTS** -- every POINT entity on layer `POOL` or
   layer `SPA` (anywhere in the drawing) is moved to layer `POINTS`,
   everything BYLAYER (`POINTS` is magenta, so they show pink). The
   pool's points and the spa's share the one layer.
3. **SPA PERIMETER** -- the spa outline (lines, arcs, circles,
   ellipses, polylines and splines on layer `SPA`) is moved to layer
   `POOL` and forced BYLAYER, so pool and spa perimeters share the
   layer and the moved geometry picks up `POOL`'s own appearance.
   Points are swept off `SPA` by step 2 first, so only the outline is
   left to move.
4. **ANCHOR POINTS** -- every POINT on layer `ANCHORS` is given an
   explicit magenta (ACI 6) color -- the same pink as the points --
   but stays on `ANCHORS`.
5. **ORIENT** -- the processed text is rotated flat so it reads west
   to east, right side up (absolute angle 0). Each text pivots about
   its own insertion point -- the labels share that point in space
   with the POINT they belong to -- so every label stays anchored to
   its point.

The `ROMANC` text style and the `POINTS` and `POOL` layers are created
if missing. Locked layers among those touched are unlocked for the
run and re-locked afterwards (on error too). The whole run is one undo
mark, and a done-line reports the counts.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `drone.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Optionally pre-select the label text, then:

| Command | What it does |
| --- | --- |
| `DRONE` | Run all five fixes in one pass |

## Tunables

At the top of `drone.lsp`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `*drone-text-style*` | `"ROMANC"` | Style the text is switched to (created from the font below) |
| `*drone-text-font*` | `"romanc.shx"` | Font file for that style |
| `*drone-text-height*` | `4.5` | Text height applied |
| `*drone-pt-layers*` | `("POOL" "SPA")` | Layers whose POINTs move |
| `*drone-dest-layer*` | `"POINTS"` | Where those POINTs go |
| `*drone-perim-src*` | `("SPA")` | Layers whose outline geometry moves |
| `*drone-perim-layer*` | `"POOL"` | Where the outline goes |
| `*drone-perim-types*` | `LINE,ARC,CIRCLE,ELLIPSE,LWPOLYLINE,POLYLINE,SPLINE` | What counts as outline geometry |
| `*drone-perim-color*` | `4` (cyan) | Color the POOL layer is created with |
| `*drone-anch-layer*` | `"ANCHORS"` | Layer of the anchor POINTs |
| `*drone-pink*` | `6` (magenta) | Color for anchors and the POINTS layer |
| `*drone-orient-angle*` | `0.0` | Absolute text angle in degrees; set to `nil` to only flip upside-down text instead ("Most readable") |

## Notes & limitations

* Only single-line `TEXT` entities are restyled -- MTEXT, attributes
  and dimension text are left alone.
* Steps 2-4 sweep the whole drawing (`ssget "_X"`), not just a
  selection -- only the TEXT step is scoped by what you highlight.
* Rotating about the insertion point assumes each label was placed on
  its survey point; a label whose insertion point sits elsewhere
  swings about that spot instead.
* Requires the Visual LISP engine (ActiveX is used throughout), which
  ships with full AutoCAD. AutoCAD LT cannot run this file.

## Tests

No dedicated test drives DRONE yet. `python3 tests/test_shared.py`
loads it (with everything else) into the repo's AutoLISP VM, so a
file that no longer parses, or that collides with another tool's
names, fails there.
