# calofin — Blender DXF add-ons & AutoCAD LISP tools

Two independent Blender add-ons (Blender 4.2+ including 5.0) for
working between Blender and CAD, plus AutoCAD AutoLISP tools for
drone-photo tracing work:

| Tool | Folder | What it does |
| --- | --- | --- |
| Export UV Layout to DXF (AutoCAD) | `uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `dxf_cloud_mesher/` | Automatically builds meshes from imported DXF point-cloud objects |
| Drone survey LISPs (AutoCAD) | `drone_height_lisp/` | Corrects the scale of off-deck features traced from rectified drone photos, and computes the drone height from the photo's GPS + an online ground-elevation lookup |

## Installation (either Blender add-on)

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

# 3. Drone survey LISPs (AutoCAD)

Two AutoLISP files in `drone_height_lisp/` for tracing pools from
rectified near-nadir drone photos. Load them with `APPLOAD` (add both to
the *Startup Suite* so they load in every drawing). Windows AutoCAD
only — they use ActiveX (`ADODB.Stream` for binary file reads,
`MSXML2.XMLHTTP` for the elevation web request).

### DroneDistortion.lsp

Corrects the scale of features that are **not at deck level** after a
photo has been rectified to deck scale: a raised spa is closer to the
camera and traces too big, a sunken catch basin traces too small. For a
feature at signed height *z* above the deck and a drone height *H*, the
tool scales the traced geometry by `(H − z) / H`.

Commands: `DDFIX` (select a feature, enter its height, apply the
correction), `DDSET` (set/remember *H*), `DDALT` (read
`RelativeAltitude` out of the original DJI image), `DDCAL` (back-solve
*H* from a feature of known true size), `DDINFO` (show settings).
*H* is stored per drawing and survives save/reopen.

### DroneHeightGPS.lsp

Companion tool that replaces the "just assume 100 ft" guess for the
drone height. Nobody logs the height in the field, but the drone logs
its GPS position in the photo automatically, so:

1. `DDGPS` opens a file picker (starts on `H:`, remembers the last
   folder) for the original drone image — PNG, JPG/JPEG or TIFF.
2. It reads latitude/longitude, `AbsoluteAltitude` and
   `RelativeAltitude` straight out of the file, whatever the container:
   DJI's XMP text packet first (JPEG APP1 or PNG iTXt; attribute or
   element serialisation; both the `GpsLongitude` and DJI's misspelt
   `GpsLongtitude` tags), falling back to the binary EXIF GPS block
   (JPEG `Exif` APP1, PNG `eXIf` chunk, or a bare TIFF header — either
   byte order). The first 256 KB are scanned, then the last 256 KB if
   needed, since PNG writers may park metadata after the image data.
3. It asks a free online elevation service for the ground elevation at
   that coordinate — USGS EPQS (3DEP bare earth, answers in feet), then
   OpenTopoData NED10m, then Open-Elevation SRTM as fallbacks; no API
   keys. If all fail (no internet) it lets you type a known site
   elevation instead.
4. The drone height above grade is the delta:
   `H = AbsoluteAltitude − ground elevation`, cross-checked against the
   barometric `RelativeAltitude` (the difference between the two methods
   is the take-off-point offset — or the GPS error, and the command says
   which value looks trustworthy). Pick which one to save; *H* goes into
   the same per-drawing store `DDFIX` reads, so it immediately becomes
   the default there.

`DDELEV` prints the ground elevation at a typed latitude/longitude —
useful as a connectivity test.

Accuracy note: consumer-drone GPS altitude is good to roughly 10–30 ft,
so the computed *H* is an estimate — but a visible, cross-checked one
instead of a blind guess, and the scale correction only changes by
~z/H² per foot of *H* error. For a hard number, `DDCAL` back-solves *H*
from one feature of known true size.

---

## Development

Both add-ons keep their geometry logic in `bpy`-free modules
(`uv_layout_dxf/uv_layout.py`, `dxf_cloud_mesher/cloud_mesh.py`), so
they are unit-testable outside Blender:

```
python3 tests/test_addon.py               # UV layout exporter
python3 tests/test_cloud_mesher.py        # point cloud mesher
python3 tests/test_drone_height_lisp.py   # drone LISP: lint + parser checks
```

The drone-LISP test lints `DroneHeightGPS.lsp` (paren/string balance)
and exercises a line-for-line Python transliteration of its byte-level
parsers against synthetic DJI-style images — JPEG, PNG and bare TIFF:
the XMP route (JPEG APP1 and PNG iTXt, attribute and element forms,
DJI's `GpsLongtitude` misspelling), the binary EXIF GPS block (JPEG
APP1, PNG `eXIf` chunk with decoy anchors in the image data, both byte
orders), metadata parked past the 256 KB front window (tail-window
recovery), signed-byte and truncated-file inputs, and the JSON number
extraction for each elevation service's response shape.

The exporter tests mock the bmesh structures and validate the emitted
DXF with [ezdxf](https://ezdxf.mozman.at/) when installed. The mesher
tests exercise boundary building, interior-point detection, Delaunay
triangulation (a pure-Python Bowyer-Watson fallback mirrors Blender's
built-in `mathutils.geometry.delaunay_2d_cdt`), and the
height/lowest-object classification rules.

## License

GPL-3.0-or-later (as required for Blender add-ons).
