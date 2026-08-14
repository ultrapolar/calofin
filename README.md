# calofin — Blender DXF add-ons and AutoCAD step routines

Two independent Blender add-ons (Blender 4.2+ including 5.0) for
working between Blender and CAD:

| Add-on | Folder | What it does |
| --- | --- | --- |
| Export UV Layout to DXF (AutoCAD) | `uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `dxf_cloud_mesher/` | Automatically builds meshes from imported DXF point-cloud objects |

Plus three standalone AutoLISP commands for pool step layout in AutoCAD
2018 — `CORNERSTP.lsp`, `HEMISTEP.lsp` and `NORMIESTEP.lsp`
([section 3](#3-autocad-step-routines-autolisp)).

## Installation (either add-on)

Grab/clone this repository, then for the add-on you want (`uv_layout_dxf`
or `dxf_cloud_mesher`) either:

* **As an extension (Blender 4.2+):** zip the folder's *contents*
  (`cd uv_layout_dxf && zip -r ../uv_layout_dxf-1.0.0.zip .`) and in
  Blender go to *Edit → Preferences → Get Extensions → ⌄ (top-right)
  → Install from Disk…* and pick the zip.
* **As a legacy add-on:** zip the folder itself
  (`zip -r uv_layout_dxf.zip uv_layout_dxf`) and use *Edit →
  Preferences → Add-ons → Install…*, then enable the add-on.

---

# 1. Export UV Layout to DXF (AutoCAD)

Exports the UV layout of the active mesh object as an **AutoCAD-
compatible DXF** (R12 / AC1009) file, aimed at flat-pattern work:
leather, upholstery, sheet metal, CNC/laser cutting.

### Mirroring & rotation fixing
Unwrapped islands often end up flipped or arbitrarily rotated in UV
space. On export the add-on re-orients them to match the 3D viewport:

* **Mirroring** is detected from normal data: Blender face loops run
  counter-clockwise when viewed from the front (normal side) of a face,
  so an island whose UV winding is clockwise is mirrored relative to the
  3D surface. Such islands are un-mirrored.
* **Rotation** is fixed by comparing the positions of shared edges
  between islands. A *base island* is chosen per connected group of
  islands — only islands that share edges with exactly **one** other
  island qualify (islands sharing edges with two or more other islands
  are excluded from the candidate pool; the largest qualifying island
  wins). Every other island is then rotated, spreading outward from the
  base island, so each shared seam edge points the same way as it does
  in its already-oriented neighbour — the way the pieces would fold
  together in 3D.

Because re-orientation rotates islands in place (about their centroid),
pieces *can* end up overlapping in the drawing. Enable **Re-pack
Islands** to lay them out in non-overlapping rows instead.

### Perimeter-only export
Only the boundary of each UV island is written — one closed `POLYLINE`
per boundary loop. Interior lines (the mesh topology inside the
perimeter) are never exported. Interior *holes* in an island are real
cut lines and are included by default; untick **Include Holes** to
export strictly the outermost perimeter of each island.

### Auto scaling from a Freestyle edge
Mark one edge as a Freestyle edge (*Edit Mode → select an edge → Edge
menu → Mark Freestyle Edge*) to use it as the scale reference. On
export, the add-on measures that edge's real 3D length (world space,
object scale and scene unit scale included) and its length in the UV
layout. If they differ, the derived scale factor is applied to the
whole DXF, so the drawing comes out at real-world size in the unit you
pick (millimeters by default). If several edges are marked, a
length-weighted average is used. If none is marked, the **Manual
Scale** factor is used instead and a warning is shown.

### Usage

1. Unwrap your object and lay out its UVs as usual.
2. In Edit Mode, select one edge whose real length you trust and mark
   it: *Edge menu → Mark Freestyle Edge*.
3. Select the object and run *File → Export → UV Layout (.dxf)* (also
   available in the UV editor under *UV → Export UV Layout to DXF*).
4. Adjust the options in the file browser sidebar and export.

| Option | Default | Meaning |
| --- | --- | --- |
| Fix Mirroring & Rotation | on | Un-mirror flipped islands and rotate all islands about the base island so seams line up |
| Re-pack Islands | off | Re-arrange islands into rows so nothing overlaps (discards original layout positions) |
| Include Holes | on | Export interior boundary loops (holes) as well as the outer perimeter |
| Scale From Freestyle Edge | on | Derive the export scale from the Freestyle-marked reference edge |
| Unit | Millimeters | Real-world unit of one DXF unit when Freestyle scaling is active |
| Manual Scale | 1.0 | Plain UV→DXF multiplier used when no Freestyle reference is available |
| Layer Per Island | off | One DXF layer per island (`ISLAND_001`, …) instead of a single `UVLAYOUT` layer |
| Move to Origin | on | Shift the layout so its lower-left corner is at the DXF origin |

### Output format

DXF R12 (AC1009) with classic closed `POLYLINE`/`VERTEX` entities — the
most widely readable DXF flavour: every AutoCAD release since 1992,
LibreCAD, QCAD, Inkscape, and most laser/CNC toolchains open it
directly.

### Notes & limitations

* Exports the **active object** only; join meshes first if you need
  several objects in one drawing.
* Modifiers are not applied; the exported layout is the mesh's actual
  UV map (what you see in the UV editor).
* Islands connected in a closed ring (every island touching two or
  more others) have no natural base island; the largest island of the
  ring is used as the base instead.

---

# 2. DXF Point Cloud Mesher

Imported DXFs often arrive broken up into many objects containing
nothing but vertices. This add-on analyses those objects and
automatically fills the ones that qualify with faces.

### Which objects get filled

* Objects whose points vary by no more than **Max Height Variation**
  on the Z axis (default **4 inches**, world space) are filled — flat
  pads, slabs, footprints.
* An object exceeding the tolerance is *still* filled when it is the
  **lowest object** of the group (its lowest point is below every other
  object's): that one is treated as the ground.
* Everything else is skipped and listed in the system console.

### How objects get filled

Triangulation is avoided: the add-on builds the boundary of the point
cloud (its 2D outline, keeping points that sit exactly on boundary
segments as corners) and creates **one n-gon face**. Only when that
face would overlap vertices lying *inside* it does the add-on switch to
a Delaunay **triangulation** of all the points, so every vertex becomes
part of the surface — for ground clouds this produces a standard TIN
(triangulated irregular network). Original Z values are always kept.

Note: because a raw point cloud carries no ordering information, a
concave outline cannot be distinguished from interior points; such
objects are triangulated (their reflex corners lie inside the cloud's
convex boundary).

### Usage

1. Import your DXF (point clouds arrive as vertex-only mesh objects).
2. Run *Object menu → Fill DXF Point Clouds*, or use the button in the
   3D Viewport sidebar (N) under the **DXF Cloud** tab.
3. Tune the options in the redo panel (bottom-left) if needed:

| Option | Default | Meaning |
| --- | --- | --- |
| Max Height Variation | 4″ (0.1016 m) | Z tolerance below which an object counts as flat and fillable |
| Always Fill Lowest Object | on | Treat the lowest object as ground and fill it even beyond the tolerance |
| Selected Objects Only | off | Restrict the analysis to the current selection instead of the whole scene |

Only vertex-only meshes (no edges, no faces, at least 3 vertices) are
touched; every other object is ignored. A per-object breakdown (filled
as n-gon / filled as TIN / skipped and why) is printed to the system
console.

---

# 3. AutoCAD step routines (AutoLISP)

Three standalone AutoLISP commands for laying out pool steps, written for
**AutoCAD 2018** (plain AutoLISP plus ActiveX for dimension styles — no
VLX or .NET). They are independent of the Blender add-ons above.

| File | Command | What it draws |
| --- | --- | --- |
| `CORNERSTP.lsp` | `CORNERSTP` | Parallel corner steps fanning out of a pool corner |
| `HEMISTEP.lsp` | `HEMISTEP` | Hemisphere steps that act as chords inside a circle |
| `NORMIESTEP.lsp` | `NORMIESTEP` | Plain straight steps, every one the same width |

Load either with `APPLOAD` (or drag the file into the drawing window).
Each command is a single undo step.

### CORNERSTP

Select the two walls of the corner — LINEs or straight segments of a
polyline — optionally including a chamfer diagonal or a fillet arc. If
more than two straight walls are selected you are asked to pick the two
you mean. Then choose the draw direction:

* **Inside out** — steps are built from the corner outward. For each
  step you give a tread depth and a step width.
* **Outside in** — you give the width of the furthest step, which is
  bounded to the walls and so places itself; each following step asks
  for a depth (walking back toward the corner) and a width.

Tread depths are always held exactly. A step width within the tolerance
of the wall opening is trimmed to the walls; any other width is held and
the step breaks away from the walls, centred so it runs equally past (or
equally short of) both walls. Riser lines close the step sides wherever
the walls do not already.

At any tread-depth prompt: **Enter** finishes, **Undo** removes the step
just drawn (lines and dimensions), **Same** repeats the previous depth.

### HEMISTEP

What you select decides how the measuring axis is found:

* **Line only** — steps are centred on the line's midpoint, run parallel
  to it, and march perpendicular away from it in a direction you pick.
  After the steps, one last depth places the crown and the hemisphere
  boundary is drawn as a polyline of arc segments through every step end.
* **Curve + line** — the line is the axis: depths start where it meets
  the curve and run into it; widths sit perpendicular to the line.
* **Curve only** — depths start at the middle of the curve and run into
  it; widths sit along the tangent there. With a single arc the middle
  is found for you; on a composite curve you pick the point to measure
  from.

A curve may be an **ARC**, a **CIRCLE**, or a **POLYLINE** — including a
hemisphere built from several arc segments, and including a boundary this
command drew earlier. Each step is measured against whichever part of the
curve it actually lands on, using the opening nearest the axis on each
side, so a distant wall elsewhere in the drawing cannot widen it.

Line mode starts by asking the width of the step **at the wall** — the top
of the run. No chord is drawn there (the wall already is one), but it is
dimensioned and it anchors both ends of the boundary curve. The curve
modes skip it, since the width at the start is set by the curve itself.

From there both modes run **depth then width**, repeating, with every
depth measured from the previous step edge — never a running total.
**Enter** at a depth prompt finishes; **Undo** removes the step just drawn
and **Same** repeats the previous depth. **Enter** at a width prompt fits
that step to the curve in the curve modes, or repeats the previous width
in line mode. In the curve modes a width within the tolerance of the
curve's opening snaps to the curve; any other width is held and breaks the
curve equally at both ends.

The hemisphere is then rebuilt as one polyline of arc segments through
every step end. In line mode it runs from the wall, around a crown set by
one last depth, and back to the wall, with the arc across the crown fitted
as a single arc so the apex has no kink. In the curve modes it runs from
the deepest step around the first one and back, and the segment spanning
the first step carries the selected curve's own bulge — so a first step
sitting on the curve reproduces that curve exactly, and a wider one still
follows its curvature instead of spiking in to the point where the axis
met the curve.

All three commands read distances architectural-style regardless of the
drawing's units setting: a bare number is drawing units (inches in an
inch-based drawing) and feet-inch entry like `1'4` (= 16") always works.
Each prints its version on load and at command start, so a stale copy
still loaded from an earlier APPLOAD is easy to spot.

### NORMIESTEP

The plain one: every step is the same width. What you select decides where
the run sits.

* **One line** — the steps are **centred** on it. You pick which side they
  go, give the width once, then the depths.
* **Two lines forming a corner** — the steps sit against the corner. You
  are asked which of the two lines the steps run **off of**; the treads run
  parallel to that one and butt against the other, so each tread starts on
  the side line and runs out by the width. Works on a skewed corner too —
  the depths stay square to the line you picked.
* **A U** (three lines, or a 3-segment polyline) — the perimeter is already
  drawn, so the treads are just filled in: parallel to the base of the U
  and trimmed to its two arms. No width is asked for, since the arms give
  it, and the run stops once a tread would fall past the base.

Depths are asked one per step, each measured from the previous tread.
**Enter** finishes, **Undo** removes the step just drawn, and **Same**
repeats the previous depth — which is what most plain runs want. The
stringer lines down the sides are drawn for the one-line and corner modes;
the U already has them.

### Dimensions

All three commands offer `Dimension the steps? [Yes/No]`. Depths are chained
along the measuring axis; widths span each step edge and nest outward so
wider steps sit further out. Two dimension styles are used and must
already exist in the drawing (otherwise the current style is used and a
note is printed):

| Setting | Default | Used for |
| --- | --- | --- |
| `*cs-depth-dimstyle*` | `"STANDARD INCHES"` | tread/step depths |
| `*cs-width-dimstyle*` | `"SIDE STANDARD"` | step widths |
| `*cs-width-tol*` | `nil` (auto: 1/8" via `INSUNITS`) | width tolerance |
| `*cs-dim-layer*` | `nil` (current layer) | layer for dimensions |

Set any of these before running the command to override. Dimension size
follows `DIMSCALE`, or the annotation scale for annotative styles.

### Assumptions and warnings

Geometry is read in plan view. All three commands warn when the current UCS is
not parallel to the World XY plane, when a selected line is not flat, and
when the current layer is off/frozen/locked. CORNERSTP additionally warns
when the two walls are nearly parallel and when a wall had to be extended
past its drawn end to meet a step. Dimensions are placed through the
current UCS, so a rotated UCS still annotates correctly, and arcs are read
through their own curve geometry so mirrored arcs behave.

---

## Development

Both add-ons keep their geometry logic in `bpy`-free modules
(`uv_layout_dxf/uv_layout.py`, `dxf_cloud_mesher/cloud_mesh.py`), so
they are unit-testable outside Blender:

```
python3 tests/test_addon.py                  # UV layout exporter
python3 tests/test_cloud_mesher.py           # point cloud mesher
python3 tests/test_cornerstp_geometry.py     # AutoLISP step geometry
```

The exporter tests mock the bmesh structures and validate the emitted
DXF with [ezdxf](https://ezdxf.mozman.at/) when installed. The mesher
tests exercise boundary building, interior-point detection, Delaunay
triangulation (a pure-Python Bowyer-Watson fallback mirrors Blender's
built-in `mathutils.geometry.delaunay_2d_cdt`), and the
height/lowest-object classification rules.

The AutoLISP routines cannot run outside AutoCAD, so
`tests/test_cornerstp_geometry.py` mirrors their geometry helpers in
Python and asserts the invariants the drawings rely on: tread depths held
exactly, held widths centred on the wall opening, outermost steps landing
wall-to-wall, polyline bulge/arc conversions round-tripping, and the
dimension chain/nesting rules.

## License

GPL-3.0-or-later (as required for Blender add-ons).
