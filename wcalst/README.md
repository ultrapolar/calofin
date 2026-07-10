# WCALST — straighten a curved ladder band (AutoCAD 2018+ AutoLISP)

`WCALST` flattens a drawing of a curved, constant-width "ladder" band —
two long curved sides connected by many short rungs — into a straight
strip, the way a curved trim/cap/waistband piece is developed for
cutting out of straight stock.

You pick which of the two long sides must come out straight. Because
the other side then carries too much or too little material, the
command relieves it automatically with:

* **Darts** — V-shaped cutouts, where the unrolled band would overlap
  itself (the band curved *away* from the straightened side).
* **Inserts** — straight slits, where the unrolled band opens a gap
  (the band curved *towards* the straightened side). A small tapered
  sliver — the material to be added — is drawn detached below the band
  under each slit.

The number of darts + inserts is deliberately conservative: the needed
correction is accumulated along the band and only released once it
reaches a minimum useful width, and the total is capped (default
**20**, prompt lets you change it per run).

## Usage

1. `APPLOAD` → select `wcalst.lsp` (or drag-drop it into the drawing).
2. Command: **`WCALST`**
3. *Select the band of lines* — window-select the whole ladder
   (`LINE`s, `LWPOLYLINE`s and old-style `POLYLINE`s are all accepted;
   nothing in the selection is modified).
4. *Click the long side to STRAIGHTEN* — click directly on one of the
   two long sides.
5. *Maximum darts + inserts <20>* — Enter to accept.

The developed band is drawn **below the lowest point of the
selection**, and the command reports the developed length, band width
and how many darts/inserts were placed. One `U` undoes the whole
output.

## What is drawn, and where

| Item | Layer |
| --- | --- |
| Straightened side (one straight line) + band end lines | `AIR-B` (red, created if missing) |
| Opposite side, unrolled (slightly wavy polyline) | same layer as the source lines |
| Dart V-cutouts, insert slits, insert slivers | `AIR-B` |
| Reference marks carried along (see below) | their own source layer |
| Band-height dimension at each end | `DIMENSION` (created if missing) |

### Reference marks

Anything in the selection that sits on a **different layer** than the
band structure itself — datum crosses, given points, existing cut
marks — is carried into the developed band: each endpoint is mapped
through the same development as the band, so the mark lands at the
correct position on the flattened strip (marks further than about 1.75×
the band width from the straightened side are dropped as unrelated).

Darts and insert slits stop at 42 % of the local band depth below the
straightened edge, so a solid hinge of material always remains along
the straight side (matches shop practice for this kind of piece).

## How it works

1. Every selected entity is exploded (in memory) into 2-point
   segments; endpoints are merged into nodes.
2. From the segment you clicked, the long side is traced through the
   node graph by always continuing into the *straightest* connecting
   segment (rungs leave a node roughly perpendicular, so they are never
   taken; tracing stops when only sharp turns remain).
3. Segments that leave the traced chain at more than 45° and end off
   the chain are the rungs; the median rung length is the band width.
4. The chosen side is laid out dead straight at its true arc length.
   Every point of the opposite side is carried rigidly with the chain
   segment it belongs to (the band is never stretched).
5. At every bend of the chosen side the opposite side over- or
   under-shoots by `turn-angle × width`. That error is accumulated
   rung by rung; each time it exceeds the release threshold
   `max(4 % of width, total-error / max-features)` a dart (overlap) or
   insert (gap) is emitted at that rung and the accumulator resets.
   Bends smaller than the threshold stay as the gentle waviness of the
   unrolled side.

## Limitations

* The band must be an open strip (not a closed ring). Plain ladder
  rungs, diagonal bracing and full triangulated (mesh-style) strips
  all work — connectors are told apart from the long sides by
  direction, so the sides just need to be traceable as the
  "straightest" path through the network.
* Arcs/circles are not accepted — the band must be drawn from straight
  segments (as ladder bands produced by field measurement normally
  are). Curved sides made of many short segments are exactly what the
  tool expects.
* If the two ends of the band are joined to other geometry included in
  the selection, tracing may run past the band end; select just the
  ladder for best results.
