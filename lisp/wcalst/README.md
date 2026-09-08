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

Sizing rules:

* **Darts are at most 4" wide on the bottom line** (`wc:*dart-cap*`) —
  a larger correction is split into several ≤ 4" darts at consecutive
  rungs.
* **Insert slivers are 1" wide at the top** (`wc:*sliver-top*`), the
  gap width at the bottom, and their sides are about 1" longer than
  the slit they go into (`wc:*sliver-extra*` — extra to trim on
  fitting).
* The release threshold auto-refines (never exceeding the feature cap)
  until the after-cuts residual — bottom line as drawn, minus dart
  widths, plus insert gaps, versus the original bottom line — is
  **under 1 %** (`wc:*target*`). If the cap is too low to get there,
  the summary flags `** OVER TARGET **`; allow more darts+inserts and
  rerun.

Every number above is a named tunable at the top of `wcalst.lsp`; see
[Tunables](#tunables).

## Usage

1. `APPLOAD` → select `wcalst.lsp` (or drag-drop it into the drawing).
2. Command: **`WCALST`**
3. *Select the band of lines* — window-select the whole ladder
   (`LINE`s, `LWPOLYLINE`s and old-style `POLYLINE`s are all accepted;
   nothing in the selection is modified).
4. *Click the long side to STRAIGHTEN* — click directly on one of the
   two long sides.
5. *Maximum darts + inserts [Back] <20>* — Enter to accept. The
   default is `wc:*maxfeat*`.
6. *Tile height along the straightened edge [Back] <none>* — height (in
   drawing units/inches) of the tile that will sit along the
   straightened edge. Darts and inserts then only come up the width to
   `width − (tile height + 1")`, i.e. they stop 1" clear of the tile
   (`wc:*tile-clear*`). Enter skips the rule and uses the default stop
   line (42 % of the local band depth below the straightened edge,
   `wc:*apex-f*`); a negative answer is read as Enter. Where the band
   is locally too shallow to hold that clearance, the apex is held at
   20 % of the local depth below the straightened edge
   (`wc:*apex-min-f*`) rather than being pushed through it.
7. *Window the STAIR section(s) if any (Enter = none)* — window-select
   the part of the band that wraps around stairs (Enter if there are
   none). That section is developed as one rigid piece, so every tread
   length and riser rise is kept exactly; see
   [Stair sections](#stair-sections).

**Two developed drawings** are placed below the lowest point of the
selection, one under the other, each labelled and with its own summary:

* **TARGET <1%** — the release threshold is refined and large
  corrections split into several ≤ 4" darts until the after-cuts
  residual is under 1 %.
* **MINIMUM DARTS+INSERTS** — one conservative pass, fewest cuts;
  its summary flags `** OVER TARGET **` when the residual exceeds 1 %.

The command reports both variants' counts and residuals. One `U`
undoes the whole output.

Sharp local detail on the non-straightened side — steps of roughly 90°
that rise temporarily and come back — is preserved: every outline
vertex of the band (outline segments are the ones drawn once; mesh
interiors always appear twice) is developed and included in the bottom
line, so notches and steps come through square instead of being
rounded off.

### Stair sections

After the tile-height prompt, WCALST asks *Window the STAIR section(s)
if any* (Enter = none). A windowed section is developed as **one rigid
piece**: the whole outline path is rotated by the chord of the
straightened side across the section and anchored where the section
begins. Treads come out level with their exact lengths, every riser
keeps its exact rise, and matching steps up/down stay equal — the
bottom line wraps the stairs with zero length distortion (validated
segment-by-segment against a hand-drawn example). Several separate
stair sections can be windowed in one selection.

**Darts are not placed inside a windowed stair section** — the stairs
are laid out rigidly and their darts are meant to be added by hand
afterward, so WCALST leaves that region alone (inserts are still
placed). Because the skipped darts no longer take up their share of the
excess, the AFTER CUTS residual for a run with stairs will usually read
`** OVER TARGET **`; that is expected and accounts for the by-hand work
still to do.

To the right of the finished band a four-line summary is written
(layer `DIMENSION`), each value in drawing units and architectural
feet-inches:

```
TOP LINE:      1286.01  (107'-2")   <- straightened side, as drawn
BOTTOM BEFORE: 1271.04  (105'-11")  <- opposite side along the original curve
BOTTOM AFTER:  1294.74  (107'-10")  <- opposite side as drawn, flattened
DELTA:         23.70  (1.86% long)
AFTER CUTS:    -4.24  (0.33%)  [target <1%]
```

The delta is how far the flattened bottom line is off from its original
length — the amount the darts (long) or inserts (short) have to absorb
when the piece is fitted. AFTER CUTS is the residual once every dart
closes and every insert is filled; the command aims it under 1 % of the
original bottom length and flags it when the feature cap prevents that.

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
straightened edge (`wc:*apex-f*`), so a solid hinge of material always
remains along the straight side (matches shop practice for this kind
of piece).

## Tunables

Every number the routine works to is a named global in one commented
block at the top of `wcalst.lsp` — layers and their creation colours,
the angles the tracing works to, what still counts as a band, the cut
sizes, where the two drawings land, and how the figures are written.
Each carries a one-line note saying what it does and what moving it
costs, so retuning is done there rather than by hunting through the
body. `setq` any of them after loading (from a startup file, say) and
the next run uses the new value.

The ones most worth knowing:

| Global | Default | What it sets |
| --- | --- | --- |
| `wc:*cut-layer*` / `wc:*cut-color*` | `"AIR-B"` / 1 | where the straight edge, band ends, dart legs, slits and slivers are drawn (the colour only if the layer has to be created) |
| `wc:*dim-layer*` / `wc:*dim-color*` | `"DIMENSION"` / 3 | end height dims, the variant labels and the summary |
| `wc:*maxfeat*` | 20 | default answer to the darts+inserts cap |
| `wc:*dart-cap*` | 4.0 | widest mouth one dart may open |
| `wc:*target*` | 0.01 | the residual the refining variant aims under, and what `** OVER TARGET **` is measured against |
| `wc:*tile-clear*` | 1.0 | how far a cut clears the tile, and the far edge |
| `wc:*apex-f*` / `wc:*apex-min-f*` | 0.42 / 0.20 | where a cut stops with no tile height given, and the closest it may ever come to the straightened edge |
| `wc:*trace-turn*` | 1.0472 (60°) | sharpest turn the trace of a long side will follow |
| `wc:*rung-turn*` | 0.7854 (45°) | how steeply a segment must leave the chain to be a rung |
| `wc:*near-f*` | 1.75 | how far off the chain (× band width) a point may sit and still belong to this band |
| `wc:*drop-f*` / `wc:*stack-f*` | 1.5 / 5.0 | where the first drawing lands below the selection, and the second below it |

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

* The band is meant to be an open strip. A closed ring is handled
  rather than refused: the trace stops at the node it set out from, so
  the ring develops as itself, cut open at the segment you clicked.
  Plain ladder rungs, diagonal bracing and full triangulated
  (mesh-style) strips all work — connectors are told apart from the
  long sides by direction, so the sides just need to be traceable as
  the "straightest" path through the network.
* A line that touches one of the long sides and runs off across it —
  a datum line, a cut mark — crosses the chain as steeply as a rung
  does. Only those leaving on the same side as the majority are taken
  as rungs, so a mark on the far side of the chain from the band no
  longer moves the measured width. A mark that touches the band is
  treated as part of it and is not carried into the developed strip;
  keep reference marks clear of the two long sides.
* Arcs/circles are not accepted — the band must be drawn from straight
  segments (as ladder bands produced by field measurement normally
  are). Curved sides made of many short segments are exactly what the
  tool expects.
* If the two ends of the band are joined to other geometry included in
  the selection, tracing may run past the band end; select just the
  ladder for best results.
