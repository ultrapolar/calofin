# calofin — Blender add-ons

Blender add-ons (Blender 4.2+ including 5.0) for working between
Blender and CAD:

| Tool | Folder | What it does |
| --- | --- | --- |
| **Merlin Import/Export** | `merlin_import_export/` | Single package: imports AutoCAD DXFs (one object per layer, auto parent/scale/position) and exports mesh edges as a layered CAD DXF (FLOOR/WALL/STEPS objects by material), behind one *File → Merlin Import/Export* UI |
| Export UV Layout to DXF (AutoCAD) | `uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `dxf_cloud_mesher/` | Automatically builds meshes from imported DXF point-cloud objects (not part of the Merlin package yet) |

## Installation (any add-on)

Grab/clone this repository, then for the add-on you want
(`merlin_import_export`, `uv_layout_dxf` or `dxf_cloud_mesher`) either:

* **As an extension (Blender 4.2+):** zip the folder's *contents*
  (`cd uv_layout_dxf && zip -r ../uv_layout_dxf-1.0.0.zip .`) and in
  Blender go to *Edit → Preferences → Get Extensions → ⌄ (top-right)
  → Install from Disk…* and pick the zip.
* **As a legacy add-on:** zip the folder itself
  (`zip -r uv_layout_dxf.zip uv_layout_dxf`) and use *Edit →
  Preferences → Add-ons → Install…*, then enable the add-on.

Merlin's export half is the layered CAD mesh exporter, bundled inside
the package under the `merlin.` operator namespace so it can be enabled
alongside the standalone "Export CAD Mesh to DXF (Layered)" add-on
without clashing.

---

# Merlin Import/Export

One package bundling the Merlin CAD round-trip. **File → Merlin
Import/Export** (bottom of the File menu) opens a dialog with two
buttons:

* **Import** — imports an AutoCAD DXF (see below).
* **Export** — exports mesh edges as a **layered CAD DXF**: faces are
  split by material into FLOOR / WALL / STEPS objects and every edge is
  routed onto a WIRES / BASELINE / SLICE / PERIMETER layer by its
  Blender marking (greyed out until there's a mesh object in the
  scene). This is the "Export CAD Mesh to DXF (Layered)" add-on.

Both operators are also available directly under the regular menus:
*File → Import → Merlin AutoCAD DXF (.dxf)* and *File → Export →
Merlin CAD Mesh (.dxf)*. (Blender only lets add-ons append to the
end of the File menu, so the Merlin entry sits at the bottom rather
than immediately below Import/Export.)

### What the importer does

1. Reads an **ASCII DXF** (AutoCAD R12 and newer). Supported entities:
   `POINT`, `LINE`, `LWPOLYLINE` (incl. bulge arcs), `POLYLINE`
   (2D/3D, polyface and polygon meshes), `3DFACE`, `SOLID`, `CIRCLE`,
   `ARC`, `ELLIPSE`, `SPLINE` (sampled). Text, dimensions, hatches and
   block inserts are skipped and reported.
2. Creates **one mesh object per DXF layer** (named after the layer),
   grouped in a new collection named after the file.
3. The object with the **most points** becomes the **parent** of the
   other imported objects.
4. The parent's **origin is set to its centre of mass** and **snapped
   to the world origin** — the rest of the drawing keeps its position
   relative to the parent.
5. The parent is **scaled by 0.0254** (AutoCAD inches → Blender
   meters); children inherit the scale through the parenting.

| Option | Default | Meaning |
| --- | --- | --- |
| Parent to Largest Object | on | Parent every imported object to the one with the most points |
| Snap to World Origin | on | Origin of the parent to its centre of mass, snapped to the world origin |
| Scale | 0.0254 | Object scale applied to the parent (children inherit); 0.0254 = inches → meters |
| Curve Resolution | 32 | Straight segments per full circle when sampling arcs/circles/ellipses/splines/bulges |

Binary DXF files are rejected with a message — re-save as ASCII DXF
in AutoCAD (`SAVEAS` → DXF). The point-cloud *dewrangling* step (the
DXF Point Cloud Mesher below) is intentionally **not** part of this
package yet; run it separately after importing if needed.

### What the exporter does

The Export button runs the layered CAD mesh exporter (the standalone
"Export CAD Mesh to DXF (Layered)" add-on, repackaged here under the
Merlin operator namespace):

* Faces are split by **material** into export objects — materials named
  *floor* / *wall* / *step* map to **FLOOR / WALL / STEPS**; any other
  material becomes its own object named after it, and faces without a
  material go to **UNGROUPED** (nothing is silently dropped). Each
  object is written as a DXF BLOCK + INSERT so it arrives in AutoCAD as
  a single selectable object.
* Every edge is routed onto a fixed **layer** by its Blender marking,
  strongest wins: **PERIMETER** (Mark Sharp) › **SLICE** (Mark
  Freestyle Edge) › **BASELINE** (Mark Seam) › **WIRES** (unmarked). An
  edge shared between two objects (e.g. where a wall meets the floor)
  is written into both.

| Option | Default | Meaning |
| --- | --- | --- |
| Selected Objects Only | on | Export only selected mesh objects (falls back to the active object) instead of the whole scene |
| Apply Modifiers | on | Export the evaluated mesh (modifiers applied) rather than the raw mesh |
| Group as Objects (Blocks) | on | Write each group as a BLOCK + INSERT (one AutoCAD object); off writes plain lines on the marking layers only |
| Unit | Inches | Real-world unit of one DXF unit (scene unit scale is taken into account) |

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

# 3. Mesh Dewrangler

Turns *wrangled* meshes — dense triangle soup from 3D scans,
photogrammetry, imports, booleans or bad exports — into clean,
simplified geometry that looks like it was modelled by hand. One
operator runs the whole pipeline, and a single **Detail Preservation**
slider decides how much of the original detail survives.

### The pipeline

1. **Dewrangle (cleanup).** Duplicate vertices are welded (threshold
   automatically scaled to 0.01 % of the mesh's bounding-box diagonal),
   degenerate faces/edges are dissolved, loose wire edges and isolated
   vertices are deleted, small holes are filled, and all face normals
   are recalculated to point consistently outside.
2. **Denoise.** Surface jitter is ironed out with volume-preserving
   **Taubin smoothing** (a positive smoothing step followed by a
   slightly larger negative one), so the mesh gets smoother without the
   deflation plain Laplacian smoothing causes. Boundary vertices of
   open meshes are locked by default so the outline doesn't creep
   inwards.
3. **Simplify.** A quadric edge-collapse decimation reduces the
   triangle count, then a **planar dissolve** merges near-coplanar
   triangles into the clean quads and n-gons a human would have
   modelled.

### The preservation slider

Every simplification strength hangs off the one slider:

| Preservation | Smoothing passes | Triangles kept | Planar dissolve |
| --- | --- | --- | --- |
| 100 % | 0 (cleanup only) | 100 % | off |
| 75 % | 2 | ~32 % | 3.75° |
| 50 % | 5 | 10 % | 7.5° |
| 25 % | 8 | ~3 % | 11.25° |
| 0 % | 10 | 1 % | 15° |

The triangle ratio decays exponentially, so the slider feels linear:
every half of the slider is roughly one order of magnitude of
reduction. At **100 %** the operator is a pure repair tool — weld,
fix, fill, recalculate — and geometry detail is untouched.

### Usage

1. Select one or more mesh objects (works on multi-selections).
2. Run *Object menu → Dewrangle & Simplify Mesh*, or use the button in
   the 3D Viewport sidebar (N) under the **Dewrangle** tab.
3. Drag **Detail Preservation** in the redo panel (bottom-left) until
   the result looks right — the operator re-runs live.

| Option | Default | Meaning |
| --- | --- | --- |
| Detail Preservation | 50 % | How much original detail survives; 100 % = cleanup only |
| Weld Duplicates | on | Merge vertices closer than the weld distance |
| Auto Weld Distance | on | Derive the threshold from the mesh size (0.01 % of bbox diagonal) |
| Weld Distance | 0.0001 m | Manual threshold used when auto is off |
| Delete Loose Geometry | on | Remove wire edges and unattached vertices |
| Fill Small Holes | on | Close boundary loops up to the hole size limit |
| Hole Size Limit | 8 | Biggest hole (sides) that gets filled; 0 = every hole |
| Recalculate Normals | on | Make normals point consistently outside |
| Denoise (Smooth) | on | Taubin-smooth surface jitter before simplifying |
| Preserve Boundary | on | Lock boundary vertices of open meshes while denoising |
| Collapse Decimate | on | Reduce triangle count by quadric edge collapse |
| Planar Dissolve | on | Merge coplanar triangles into quads/n-gons |

A per-object before/after breakdown (verts / faces) is printed to the
system console, and the header bar reports the total face reduction.

### Notes & limitations

* Works on the mesh data directly (modifiers are neither applied nor
  considered), and UV/vertex-color data on collapsed geometry is
  discarded by decimation — run it before unwrapping/texturing.
* Aggressive settings on closed organic shapes can produce slivers;
  raise the preservation, or disable **Collapse Decimate** and let the
  planar dissolve do the simplifying on hard-surface/terrain meshes.

---

## Development

The add-ons keep their geometry logic in `bpy`-free modules
(`uv_layout_dxf/uv_layout.py`, `dxf_cloud_mesher/cloud_mesh.py`,
`merlin_import_export/dxf_reader.py`, `merlin_import_export/
mesh_layers.py`), so they are unit-testable outside Blender:

```
python3 tests/test_addon.py          # UV layout exporter
python3 tests/test_cloud_mesher.py   # point cloud mesher
python3 tests/test_dxf_reader.py     # Merlin DXF importer parser
python3 tests/test_mesh_layers.py    # Merlin CAD mesh exporter
```

The exporter tests mock the bmesh structures and validate the emitted
DXF with [ezdxf](https://ezdxf.mozman.at/) when installed. The mesher
tests exercise boundary building, interior-point detection, Delaunay
triangulation (a pure-Python Bowyer-Watson fallback mirrors Blender's
built-in `mathutils.geometry.delaunay_2d_cdt`), and the
height/lowest-object classification rules. The dewrangler tests cover
the preservation-slider mapping, the size-relative weld threshold and
the Taubin smoother (noise reduction, boundary locking and
volume preservation vs. plain Laplacian).

The AutoLISP routines cannot run outside AutoCAD, so
`tests/test_cornerstp_geometry.py` mirrors their geometry helpers in
Python and asserts the invariants the drawings rely on: tread depths held
exactly, held widths centred on the wall opening, outermost steps landing
wall-to-wall, polyline bulge/arc conversions round-tripping, and the
dimension chain/nesting rules.

## License

GPL-3.0-or-later (as required for Blender add-ons).
