# DDFIX / DDGPS -- drone height and distortion toolset (AutoLISP / AutoCAD 2018+)

Two files, one per-drawing store, eight `DD*` commands. A near-nadir
drone photo rectified to deck scale is only true ON the deck plane: a
raised spa traces larger than it is, a sunken catch basin smaller.
`DroneDistortion.lsp` corrects the traced geometry by
`factor = (H - z) / H`; `DroneHeightGPS.lsp` works the drone height H
out of the photo's own GPS metadata instead of the office's blind
"100 ft" guess. Either file also works on its own.

## What it does

**`DroneDistortion.lsp`** -- the correction:

| Command | What it does |
| --- | --- |
| `DDFIX` | Select a feature, enter its height above/below the deck, apply the scale correction (about the selection's centre by default -- pick a shared corner as base point when the feature shares an edge with the pool) |
| `DDSET` | Set or forget the drone height H (DDFIX also asks the first time) |
| `DDALT` | Read RelativeAltitude out of the original DJI image and set H |
| `DDCAL` | Back-solve H from a feature of known true size (cross-check) |
| `DDINFO` | Show the current settings and the distortion rate (~1/H) |

**`DroneHeightGPS.lsp`** -- H from the photo:

| Command | What it does |
| --- | --- |
| `DDGPS` | Pick the original drone photo, read its GPS position and altitude (DJI XMP first, binary EXIF GPS as fallback), ask a free elevation service for the ground elevation there, compute H = altitude - ground, write a 5-line report at a clicked point, and save H so DDFIX offers it as its default |
| `DDELEV` | Type a latitude/longitude, print the ground elevation (handy as an internet-connectivity test) |
| `DDTEST` | Diagnose a photo that will not read: walks every access path and says whether the file carries GPS metadata at all |

Both files write to the same per-drawing LDATA dictionary
(`"DRONE_DISTORTION"`), so H survives save/close/reopen and the two
halves see each other's values without either needing the other
loaded.

## Install & run

1. In AutoCAD run `APPLOAD` and load `DroneDistortion.lsp`,
   `DroneHeightGPS.lsp`, or both (add them to the *Startup Suite* to
   have them every session). The shared build (`shared/LAZPASS.lsp`)
   carries both.
2. Typical flow: `DDGPS` (or `DDALT`, or `DDSET`) to establish H, then
   `DDFIX` per raised/sunken feature; `DDCAL` when a feature of known
   size is available to cross-check H.

## Assumptions

* **Windows AutoCAD.** DDGPS/DDALT/DDTEST read files through
  `ADODB.Stream` and DDGPS talks HTTP through `MSXML2.XMLHTTP` --
  both Windows ActiveX objects. DDGPS also needs internet access for
  the elevation lookup (USGS EPQS, then OpenTopoData, then
  Open-Elevation; no API keys); when none can be reached it lets you
  type a known site elevation instead.
* **An original drone photo.** PNG, JPG/JPEG and TIFF are all read --
  by their metadata containers, not the extension -- but only a file
  that still carries the camera metadata works: not a video frame
  grab, screenshot, or stripped export.
* **Units.** H is entered and reported in FEET; feature heights are
  typed feet-and-inches (`6"`, `2'`, `1'6-1/2"`, `18'6.5"`; a bare
  number is inches; a leading `-` means below the deck). Altitude in
  the file is metres (DJI writes metres) and is converted. The
  correction itself is a dimensionless ratio, so drawing units do not
  matter.
* H is the height ABOVE THE DECK: if the drone took off X below the
  deck subtract X, X above add X.

## Notes & limitations

* EXIF `GPSAltitude` on plenty of DJI models is referenced to the
  take-off point, not sea level; DDGPS computes both readings and
  keeps the physically possible one (a drone cannot fly below the
  ground nor legally above 400 ft AGL), and says which it took.
* A file that omits the E/W hemisphere reference is assumed WEST
  (every job is in the United States) and the run says so; a position
  outside the US is flagged.
* Consumer GPS vertical error is routinely 10-30 ft and DJI's
  sea-level reference does not exactly match the USGS datum -- still
  far better than a 100 ft guess, and 1/H keeps the residual error
  small (at H = 100 ft, 10 ft of H error moves a 2 ft raised spa by
  ~0.2%). For a hard number, DDCAL back-solves H from a known size.
* The HTTP request is synchronous: AutoCAD sits for a second or two,
  up to ~30 s when the network is down, and Esc cannot interrupt an
  in-flight request.
* Every DDGPS failure is loud -- a dialog names exactly what failed
  (no metadata / no GPS / no fix / no altitude / which service and
  why) and the same detail prints on the command line.
* The first 256 KB of the photo is scanned, then the last 256 KB (PNG
  writers may park metadata after the image data).

## Tests

`python3 tests/test_drone_height_lisp.py` covers both files: a
paren/quote lint of `DroneHeightGPS.lsp`, byte-identical
transliterations of the metadata parsers run against synthetic
DJI-style JPEG/PNG/TIFF files (EXIF and XMP, both serializations, both
byte orders), the failure classification behind the loud alerts, the
rounding, the JSON number extraction against real elevation-service
response shapes, and `DroneDistortion.lsp`'s height parsing and scale
factor.
