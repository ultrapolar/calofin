# calofin — Blender DXF add-ons & AutoCAD LISP tools

Two independent Blender add-ons (Blender 4.2+ including 5.0) for
working between Blender and CAD, plus AutoCAD AutoLISP tools for
drone-photo tracing work:

| Tool | Folder | What it does |
| --- | --- | --- |
| Export UV Layout to DXF (AutoCAD) | `uv_layout_dxf/` | Exports UV island outlines as an AutoCAD-compatible DXF with orientation fixing and Freestyle-edge auto scaling |
| DXF Point Cloud Mesher | `dxf_cloud_mesher/` | Automatically builds meshes from imported DXF point-cloud objects |
| Drone survey LISPs (AutoCAD) | `drone_height_lisp/` | Corrects the scale of off-deck features traced from rectified drone photos, and computes the drone's height above grade from the photo's GPS + an online ground-elevation lookup, annotating the result in the drawing |

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
drone height. Nobody logs the height in the field, but the drone
records its GPS position and altitude in the photo automatically. The
drone's altitude is measured from **sea level**, so subtracting the
ground elevation at that same coordinate gives the height above grade:

1. `DDGPS` opens a file picker (starts on `H:`, remembers the last
   folder) for the original drone photo — PNG, JPG/JPEG or TIFF.
2. It reads latitude/longitude and `AbsoluteAltitude` straight out of
   the file, whatever the container: DJI's XMP text packet first (JPEG
   APP1 or PNG iTXt; attribute or element serialisation; both the
   `GpsLongitude` and DJI's misspelt `GpsLongtitude` tags), then the
   binary EXIF GPS block (JPEG `Exif` APP1, PNG `eXIf` chunk, or a bare
   TIFF header — either byte order). The first 256 KB are scanned, then
   the last 256 KB if needed, since PNG writers may park metadata after
   the image data.
   EXIF keeps the hemisphere in separate `GPSLatitudeRef` /
   `GPSLongitudeRef` tags, so those are applied; a file that omits the
   E/W one is assumed **West**, because every job is in the United
   States, and the run says so on the command line. A position that
   doesn't land in the US is flagged — that is exactly what a wrong
   hemisphere looks like.

   Reading the bytes is the fiddly part on locked-down machines, so
   there are three tiers: `ADODB.Stream` (with `Stream.Open`'s optional
   parameters passed explicitly — AutoLISP refuses the bare call),
   then the same read from a local temp copy, then a `certutil`
   hex dump parsed back to bytes for PCs where ADODB is blocked
   outright.
3. You click a point in the drawing for the report.
4. It asks a free online elevation service for the ground elevation at
   that coordinate — USGS EPQS (3DEP bare earth, answers in feet), then
   OpenTopoData NED10m, then Open-Elevation SRTM as fallbacks; no API
   keys. If all fail (no internet) it lets you type a known site
   elevation instead.
5. The height above grade is the subtraction —
   `AbsoluteAltitude − ground elevation`, rounded to the nearest foot —
   but only when the photo's altitude really is sea-level referenced.
   XMP `AbsoluteAltitude` always is; EXIF `GPSAltitude` often is **not**
   (many DJI models put the height above the *take-off point* in that
   tag). So both readings are computed and the physically possible one
   is used — a drone can't fly below the ground, and can't legally fly
   above 400 ft AGL. The command says which reading it took, and the
   text in the drawing says so too.
   and it is written into the drawing at the point you picked, as five
   lines of plain single-line `TEXT` on the current layer in the current
   text style:

   ```
   GPS position: 32.7157380, -117.1610838
   Drone altitude (MSL): 405.0 ft
   Ground elevation (MSL): 296.6 ft   [USGS 3DEP]
   405.0 - 296.6 = 108.4 ft
   Height above grade: 108 ft
   ```

   Text height defaults to the drawing's `TEXTSIZE` the first time, then
   is remembered per drawing and offered as the default (Enter keeps
   it). The rounded height also goes into the same per-drawing store
   `DDFIX` reads, so it immediately becomes the default there.

`DDELEV` prints the ground elevation at a typed latitude/longitude —
useful as a connectivity test. `DDTEST` diagnoses a photo that won't
read: it walks every reader in turn, reports what the PC actually
allows (including the exact COM step that failed and what Windows said
about it) and the first bytes each reader returned, then says whether
the file carries an XMP packet, an EXIF block, a GPS position, an
altitude, and an E/W reference.

This needs the **original camera file**. Video frame grabs, screenshots
and most export/share/convert steps strip the metadata, leaving nothing
to read — and failures are loud: a dialog box pops up saying exactly
what failed and how ("no camera metadata in this file", "no GPS data
found", "no GPS fix (position is 0,0)", "no altitude data", or which
elevation service failed and why), with the same detail printed on the
command line. Only deliberate cancels are quiet.

Accuracy note: consumer-drone GPS altitude is good to roughly 10–30 ft,
so the computed height is an estimate — but a visible one, with its
inputs written down in the drawing, instead of a blind guess. The scale
correction only changes by ~z/H² per foot of *H* error. For a hard
number, `DDCAL` back-solves *H* from one feature of known true size, and
`DDALT` remains available as a no-internet barometric alternative.

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
recovery), signed-byte and truncated-file inputs, the failure
classification behind the loud-error dialogs (no metadata / no GPS
data / no fix / bad GPS / no altitude), the GPS hemisphere rules
(a `W` reference must make the longitude negative; a *missing*
reference means the sign is unknown, never positive), the US
sanity check, the sea-level-vs-above-take-off altitude decision
(exercised with both real files that hit it), rounding to the
nearest foot, the `certutil` hex-dump
parser, and the JSON number extraction for each elevation service's
response shape.

It also parses the `.lsp` files themselves and fails on functions that
are called but never defined, calls with the wrong number of arguments
(user functions and the built-ins these files lean on), and Common Lisp
forms that AutoLISP does not have — mistakes the Python mirrors cannot
see, because they only surface as runtime errors inside AutoCAD.

The drawing-side behaviour (`getpoint`, the `entmake` TEXT entities,
the UCS→WCS conversion, and the `DDFIX` handoff) needs real AutoCAD —
it is not covered by this harness.

The exporter tests mock the bmesh structures and validate the emitted
DXF with [ezdxf](https://ezdxf.mozman.at/) when installed. The mesher
tests exercise boundary building, interior-point detection, Delaunay
triangulation (a pure-Python Bowyer-Watson fallback mirrors Blender's
built-in `mathutils.geometry.delaunay_2d_cdt`), and the
height/lowest-object classification rules.

## License

GPL-3.0-or-later (as required for Blender add-ons).
