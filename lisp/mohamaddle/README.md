# MOHAMADDLE — perimeter pad placer with a size choice (AutoLISP)

`MOHAMADDLE` is `PADDLE` with one difference: it asks which pad size
to place before it scans anything. Everything else — the feature
rules, the chaining of loose geometry, the no-overlap dodge pass, the
block-resolution fallback — is `PADDLE`'s own engine, ported under its
own name because every `lisp/` tool has to load and work alone.

## Usage

1. Load `MOHAMADDLE.lsp` (`APPLOAD`, or drag it into the drawing).
2. Type `MOHAMADDLE`.
3. Answer **Pad size (inches)? [24/36] <36>:** — pick `24` or `36`.
   The prompt remembers whatever you picked last and offers that as
   the default next time, for the rest of the drawing session. A
   default the size table does not offer -- a `*mohamaddle-defaultkw*`
   retuned to `"48"`, or a size dropped from `*mohamaddle-sizes*` -- is
   matched to a listed size ignoring case, else falls back to `36`,
   else to the first size listed, rather than being handed back on
   Enter to fail.
4. Select the perimeter geometry (polylines, lines, arcs — any mix)
   — or just press **Enter** and MOHAMADDLE auto-detects the perimeter
   as the largest closed loop it can find in the space you are drawing
   in -- model space from inside a layout's viewport, not the sheet.
   Highlighting the perimeter *before* step 2 skips this prompt: a
   pickfirst selection is taken as-is.
5. If what you gave it closes except for a gap, MOHAMADDLE draws an
   arrow at every open joint and asks whether to close it with a zero
   fillet before it pads anything — below.

This is the size prompt itself; it has nothing in front of it to step
back to, so it does not offer `Back`.

## Pad specification

Identical to `PADDLE`'s (see `lisp/paddle/README.md` for the full
table): a concave arc of radius 4′-0″ or less, bending more than 10°,
gets a flush row of pads; a concave corner bending more than 30° gets
one pad on the vertex; convex geometry and gentler bends get nothing.
"Concave" is judged from the interior of the closed loop either way it
was drawn.

## The gap in a perimeter that nearly closes

`PADDLE`'s gap pass came over with the rest of the engine and works
exactly as it does there — `lisp/paddle/README.md` has the full
description, and the rules live in one place in prose even though the
code is a second copy. In short: geometry that chains into a perimeter
except for a drafting gap is recognised as one, an arrow goes in at
every open joint, and each gap is offered a zero-radius `FILLET`
(`Close the gap the arrow points at with a zero fillet? [Yes/No]
<Yes>:`). Yes closes it and the run carries on into the perimeter that
leaves; No leaves the arrow standing. A gap whose two ends are on one
open polyline is joined in place instead of being handed to `FILLET`.

The question comes **after** the size pick and before any pad goes in,
and the arrows land on layer `PADDLE-GAP` — `PADDLE`'s own, shared
deliberately, the way the two tools already share `PADS`. They mark
the same thing in the same drawing, so whichever of them runs next
clears the marks and re-marks whatever is still open.

## Pad sizes

`*mohamaddle-sizes*` at the top of the lisp lists what the prompt
offers — each entry is `(KEYWORD BLOCKNAME SIZE-IN-INCHES)`:

| Keyword | Block | Size |
| --- | --- | --- |
| `24` | `Pad24x24` | 24″ × 24″ |
| `36` | `Pad36x36` | 36″ × 36″ |

Both block definitions ship in `24inpad.dwg` (`lisp/paddle/`), the
same file `PADDLE` imports from. Add a third `(KEYWORD BLOCKNAME
SIZE)` entry to the list to offer a third size — nothing else about
the picker needs to change, but the block itself has to exist in the
drawing, be importable from `*mohamaddle-blkfile*`, or fall back to a
plain square the way the other two do.

## The pad block

Resolution order, same as `PADDLE`:

1. A definition already in the drawing.
2. Imported from `24inpad.dwg` (`lisp/paddle/24inpad.dwg`) if AutoCAD
   can find it — add that folder to *Options → Files → Support File
   Search Path*, or copy the dwg next to your drawing.
3. As a last resort a plain square block of the right size is
   created; a message tells you when this happened.

The block's base point doesn't matter — MOHAMADDLE measures the
block's extents once per run and centers pads by their true footprint.

## Assumptions / configuration

Drawing units are assumed to be **inches** (architectural).

| Knob | Default | What it does |
| --- | --- | --- |
| `*mohamaddle-sizes*` | `(("24" "Pad24x24" 24.0) ("36" "Pad36x36" 36.0))` | The size choices offered at the prompt |
| `*mohamaddle-defaultkw*` | `"36"` | Which size the prompt defaults to the first time it is asked in a session; updated after every run |
| `*mohamaddle-blkfile*` | `"24inpad.dwg"` | The dwg the block definitions are imported from when the drawing lacks them |
| `*mohamaddle-layer*` | `"PADS"` | Layer pads land on. Created when missing; thawed, unlocked and turned on when not |
| `*mohamaddle-layer-color*` | `7` | Colour index the layer is created with. An existing layer keeps its own |
| `*mohamaddle-align*` | `nil` | `nil` = pads parallel to the X/Y axes; `T` = rotated to follow the perimeter edge |
| `*mohamaddle-maxrad*` | `48.0` | Largest concave radius (4′-0″) that still needs pads, whichever size was picked |
| `*mohamaddle-cornertol*` | 30° | A joint has to bend **more than** this, into the pool, to be a sharp inside corner |
| `*mohamaddle-arctol*` | 10° | A concave arc has to bend **more than** this in total to be a feature |
| `*mohamaddle-fuzz*` | `0.05` | Largest gap that still counts as touching when chaining loose lines and arcs |
| `*mohamaddle-gapmax*` | `36.0` | Furthest apart two loose ends may be and still read as a drafting gap to arrow and offer a fillet for. Wider than this is a missing wall |
| `*mohamaddle-gap-layer*` / `*mohamaddle-gap-color*` | `"PADDLE-GAP"` / `1` | Where the gap arrows are drawn, and in what colour. `PADDLE`'s layer on purpose — the two tools mark the same thing, and each clears and re-marks it |
| `*mohamaddle-arrow*` | `36.0` | Length of a gap arrow, tail to tip |

Supported perimeter geometry: **LWPOLYLINE, 2D POLYLINE, LINE, ARC**
in any combination — the loop just has to close. (3D/mesh polylines
are ignored.)

## Tests

```
python3 tests/test_mohamaddle.py
CALOFIN_LISP_ROOT=shared python3 tests/test_mohamaddle.py
```
