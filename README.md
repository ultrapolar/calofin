# calofin — Blender DXF add-ons

Three independent Blender add-ons (Blender 4.2+ including 5.0) for
working between Blender and CAD:

| Add-on | Folder | What it does |
| --- | --- | --- |
| Export UV Layout to DXF (AutoCAD) | `uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `dxf_cloud_mesher/` | Automatically builds meshes from imported DXF point-cloud objects |
| Export CAD Mesh to DXF (Layered) | `cad_mesh_dxf/` | Exports mesh edges as a layered AutoCAD DXF split by material into FLOOR/WALL/STEPS objects, with edge markings routed to WIRE/BASELINE/SLICE/PERIMETER layers |

## Installation (any add-on)

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

# 3. Export CAD Mesh to DXF (Layered)

Exports mesh edges as an **AutoCAD-compatible DXF** (R12 / AC1009)
formatted for a layer-based CAD design process: the mesh is split by
material into separate CAD objects, and every edge lands on a fixed
layer according to its Blender edge marking.

### Objects from materials

Faces are grouped by their material name (case-insensitive substring
match, first hit in this order wins):

| Material name contains | Export group |
| --- | --- |
| `floor` | `FLOOR` |
| `wall` | `WALL` |
| `step` | `STEPS` |

Each group is written as a DXF **BLOCK** with a single **INSERT**, so
it arrives in AutoCAD as one selectable object named `FLOOR`, `WALL`
or `STEPS`. Any other material becomes its own block named after the
material (a warning lists them on export), and faces with no material
go to an `UNGROUPED` block — nothing is silently dropped. An edge
shared between two groups (e.g. where a wall meets the floor) is
written into both objects. Untick **Group as Objects (Blocks)** to
write plain lines on the marking layers with no object grouping.

### Layers from edge markings

| DXF layer | Blender marking | How to mark |
| --- | --- | --- |
| `PERIMETER` | Sharp | *Edge menu → Mark Sharp* |
| `SLICE` | Freestyle | *Edge menu → Mark Freestyle Edge* |
| `BASELINE` | Seam | *Edge menu → Mark Seam* |
| `WIRE` | (none) | every unmarked edge |

When an edge carries several markings the highest layer in the table
wins (sharp beats Freestyle beats seam). All four layers are always
present in the exported drawing, even when empty, so the layer set is
stable across exports.

### Usage

1. Assign materials named *floor*, *wall* and *steps* (or containing
   those words) to the corresponding faces.
2. In Edit Mode, mark the edges: *Mark Sharp* for the perimeter,
   *Mark Freestyle Edge* for slices, *Mark Seam* for baselines;
   everything left unmarked exports as wireframe.
3. Select the object(s) and run *File → Export → CAD Mesh (.dxf)*.

| Option | Default | Meaning |
| --- | --- | --- |
| Selected Objects Only | on | Export the selected mesh objects (all scene meshes when off) |
| Apply Modifiers | on | Export the evaluated mesh instead of the raw mesh data |
| Group as Objects (Blocks) | on | One BLOCK + INSERT per group instead of loose lines |
| Unit | Inches | Real-world unit of one DXF unit (scene unit scale is applied) |

Geometry is exported in world space as 3D `LINE` entities, so the
drawing keeps real elevations; coordinates are converted from
Blender's meters to the chosen unit.

---

## Development

All add-ons keep their geometry logic in `bpy`-free modules
(`uv_layout_dxf/uv_layout.py`, `dxf_cloud_mesher/cloud_mesh.py`,
`cad_mesh_dxf/mesh_layers.py`), so they are unit-testable outside
Blender:

```
python3 tests/test_addon.py          # UV layout exporter
python3 tests/test_cloud_mesher.py   # point cloud mesher
python3 tests/test_cad_mesh.py       # layered CAD mesh exporter
```

The exporter tests mock the bmesh structures and validate the emitted
DXF with [ezdxf](https://ezdxf.mozman.at/) when installed. The mesher
tests exercise boundary building, interior-point detection, Delaunay
triangulation (a pure-Python Bowyer-Watson fallback mirrors Blender's
built-in `mathutils.geometry.delaunay_2d_cdt`), and the
height/lowest-object classification rules. The CAD mesh tests cover
the marking→layer precedence, material-to-group mapping and the
block/insert DXF structure (also ezdxf-validated when available).

## License

GPL-3.0-or-later (as required for Blender add-ons).
