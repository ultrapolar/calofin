# calofin — Blender ↔ CAD tooling

Two independent Blender add-ons (Blender 4.2+ including 5.0) for working
between Blender and CAD, plus one standalone AutoCAD routine:

| Tool | Folder | What it does |
| --- | --- | --- |
| Export UV Layout to DXF (AutoCAD) | `uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `dxf_cloud_mesher/` | Automatically builds meshes from imported DXF point-cloud objects |
| PERPPTS (AutoLISP, not a Blender add-on) | `perp_points.lsp` | Divides a line into points, offsets them perpendicular by typed lengths, joins them with a polyline and dimensions each offset — repeatable on the polyline it creates |

## Installation (Blender add-ons)

The AutoCAD routine is loaded differently — see
[PERPPTS](#3-perppts--perpendicular-offset-points-autocad) below.

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

## Development

Both add-ons keep their geometry logic in `bpy`-free modules
(`uv_layout_dxf/uv_layout.py`, `dxf_cloud_mesher/cloud_mesh.py`), so
they are unit-testable outside Blender:

```
python3 tests/test_addon.py          # UV layout exporter
python3 tests/test_cloud_mesher.py   # point cloud mesher
python3 tests/test_perp_points.py    # PERPPTS AutoLISP routine
```

The exporter tests mock the bmesh structures and validate the emitted
DXF with [ezdxf](https://ezdxf.mozman.at/) when installed. The mesher
tests exercise boundary building, interior-point detection, Delaunay
triangulation (a pure-Python Bowyer-Watson fallback mirrors Blender's
built-in `mathutils.geometry.delaunay_2d_cdt`), and the
height/lowest-object classification rules. The PERPPTS tests read
`perp_points.lsp` itself to check the properties that make it safe to
run — balanced parentheses, no variables leaking into the global
namespace, and every system variable it changes being saved and
restored — then exercise a reference port of its arc-length sampling
helpers.

---

# 3. PERPPTS — perpendicular offset points (AutoCAD)

`perp_points.lsp` is a standalone **AutoLISP** routine for AutoCAD 2018+
(not a Blender add-on). Load it with *APPLOAD* — or drag the file into
the drawing window — and run the `PERPPTS` command.

It divides a line into equally-spaced points, offsets each one
perpendicular to the line by a length you type, joins the offset points
with a polyline, and dimensions each offset back to the line.

### Repeating

After a polyline is built, PERPPTS offers to repeat on it. Each round
asks for a fresh point count and spaces that many points **by arc
length** along the polyline from the previous round. The offset
direction is fixed once from your initial direction click, so every
round offsets to the same side and — importantly — every dimension stays
perpendicular to the **original line**, never to the jagged polyline the
points now sit on. Repeat as many times as you like.

### Usage

1. Run `PERPPTS` and select a line (a polyline is also accepted, so work
   from an earlier session can be resumed).
2. Click one side of the line. The nearer end becomes START (fixing the
   order lengths are entered in) and the side you clicked is the side
   offsets go toward. A red arrow marks the START end for the rest of
   the command.
3. Enter the number of points (at least 2).
4. Enter a length for each point, START → FINISH. Press **Enter** to
   reuse the previous length, or type **U** to step back and re-enter
   the previous point.
5. Answer the repeat prompt to run another round on the new polyline.
6. Pick the dimension style — **STANDARD INCHES** or **SIDE STANDARD**.
   All dimensions are then drawn at once.

### Layers & properties

The offset polylines are drawn with the same **layer, colour, linetype,
lineweight and linetype scale** as the object they were offset from, so
each new polyline reads as the same kind of object as the line it came
from. (Any property the source does not set explicitly is BYLAYER,
which is inherited as BYLAYER.)

Dimensions go on the **`DIMENSIONS`** layer, created if the drawing does
not already have it. They use the dimension style you pick at the end —
`STANDARD INCHES` or `SIDE STANDARD` — when that style exists in the
drawing; if it does not, the current style is used and a note is printed
rather than failing. Whatever the drawing's current dimension style was
is restored when the command ends.

### Robustness

* The whole run is a single UNDO group — one `U` reverses everything,
  however many rounds were done.
* Esc or an error at any prompt restores every system variable the
  command changed (`OSMODE`, `CMDECHO`, `PDMODE`, `CLAYER`, the `CE*`
  creation defaults and the current dimension style), erases the
  temporary guide markers and closes the UNDO group.
* Bad input re-prompts rather than aborting: a missed pick, a wrong
  object type, or a point count below 2 all just ask again. Zero and
  negative lengths are rejected, so a dimension is never degenerate and
  an offset can never silently flip to the wrong side.
* A direction click landing on the line itself is rejected, since
  "which side" would be ambiguous; object snap is suppressed for that
  click so it cannot be pulled onto the line.
* A point count above 100 asks for confirmation, so a mistyped number
  cannot spawn thousands of dimensions.
* All geometry is handled in the current UCS, so the command behaves
  correctly in a rotated or shifted UCS.

## License

GPL-3.0-or-later (as required for Blender add-ons).
