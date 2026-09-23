# DDFIX / DDGPS -- drone height and distortion toolset (AutoLISP / AutoCAD 2018+)

Two files, one per-drawing store, eight `DD*` commands. A near-nadir
drone photo rectified to deck scale is only true ON the deck plane: a
raised spa traces larger than it is, a sunken catch basin smaller.
`DroneDistortion.lsp` corrects the traced geometry by
`factor = (H - z) / H`; `DroneHeightGPS.lsp` works the drone height H
out of the photo's own metadata instead of the office's blind
"100 ft" guess. Either file also works on its own.

## What it does

**`DroneDistortion.lsp`** -- the correction:

| Command | What it does |
| --- | --- |
| `DDFIX` | Select a feature, enter its height above/below the deck, apply the scale correction about the selection's centre. There is no base-point option: for a feature that shares an edge with the pool, U the DDFIX and `SCALE` it about the shared corner by the factor DDFIX printed |
| `DDSET` | Set or forget the drone height H (DDFIX also asks the first time) |
| `DDALT` | Read RelativeAltitude out of the original DJI image and set H |
| `DDCAL` | Back-solve H from a feature of known true size (cross-check) |
| `DDINFO` | Show the current settings and the distortion rate (~1/H) |

**`DroneHeightGPS.lsp`** -- H from the photo:

| Command | What it does |
| --- | --- |
| `DDGPS` | Pick the original drone photo, read its GPS position and both altitudes (DJI XMP first, binary EXIF GPS as fallback), take H = RelativeAltitude + the take-off-vs-deck offset you confirm (Enter = it took off from the deck), write a 5-line report at a clicked point, and save H so DDFIX offers it as its default. A file with no RelativeAltitude falls back to a free elevation service and H = altitude - ground, flagged as rough |
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
3. `DDFIX` will not take a pick with anything on a locked layer: it
   names the layer and asks for the pick again. SCALE would skip that
   object without a word and scale the rest about a centre the skipped
   object still pulled on, so the feature would come out half corrected
   and out of place.

## Assumptions

* **Windows AutoCAD.** DDGPS/DDALT/DDTEST read files through
  `ADODB.Stream` and DDGPS talks HTTP through `MSXML2.XMLHTTP` --
  both Windows ActiveX objects. DDGPS needs internet access only on
  its fallback route, for a file with no RelativeAltitude (USGS EPQS,
  then OpenTopoData, then Open-Elevation; no API keys); when none can
  be reached it lets you type a known site elevation instead.
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

* **A DJI `AbsoluteAltitude` is not sea level.** It is the WGS84
  ellipsoid height (or a barometric estimate seeded from it), and
  across the United States the ellipsoid sits 50-115 ft BELOW mean
  sea level -- so at a low-lying site a drone 100 ft up records a
  NEGATIVE altitude, and "altitude minus ground" comes out 50-115 ft
  short everywhere else. Do not "fix" the sign by hand: the number is
  the file's. DDGPS prints it for the record and uses the barometric
  `RelativeAltitude` (above the take-off point, good to a foot or
  two) instead, plus the take-off offset you confirm. A shot whose
  RelativeAltitude is under a foot was taken on the ground and is
  refused.
* On the fallback route (no RelativeAltitude) the one altitude may be
  DJI's "sea level" or, on some models, the height above the take-off
  point in EXIF `GPSAltitude`; DDGPS computes both readings, keeps
  the physically possible one (a drone cannot fly below the ground
  nor legally above 400 ft AGL), says which it took, and calls it
  rough -- DDCAL is the hard number.
* A file that omits the E/W hemisphere reference is assumed WEST
  (every job is in the United States) and the run says so; a position
  outside the US is flagged.
* 1/H keeps a residual H error small: at H = 100 ft, 10 ft of H error
  moves a 2 ft raised spa by ~0.2%. For a hard number, DDCAL
  back-solves H from a known size.
* The HTTP request (fallback route only) is synchronous: AutoCAD sits
  for a second or two, up to ~30 s when the network is down, and Esc
  cannot interrupt an in-flight request.
* Every DDGPS failure is loud -- a dialog names exactly what failed
  (no metadata / no GPS / no fix / no altitude / taken on the ground /
  which service and why) and the same detail prints on the command
  line.
* The first 256 KB of the photo is scanned, then the last 256 KB (PNG
  writers may park metadata after the image data).

## Tests

`python3 tests/test_drone_height_lisp.py` covers both files: a
paren/quote lint of `DroneHeightGPS.lsp`, byte-identical
transliterations of the metadata parsers run against synthetic
DJI-style JPEG/PNG/TIFF files (EXIF and XMP, both serializations, both
byte orders, signed and unsigned altitudes), the failure
classification behind the loud alerts, the route choice, the
rounding, the JSON number extraction against real elevation-service
response shapes, and `DroneDistortion.lsp`'s height parsing and scale
factor. `python3 tests/test_ddgps_runtime.py` runs `DDGPS` itself in
the repo's AutoLISP VM over those synthetic photos -- the negative
AbsoluteAltitude case, the take-off offset, Back at every prompt, the
on-the-ground refusal, the fallback route online and offline, and the
last-256-KB scan -- and `tests/test_dronedistortion.py` does the same
for `DDFIX` / `DDSET` / `DDCAL` / `DDINFO`. `CALOFIN_LISP_ROOT=shared`
reruns the VM suites against the grouped twins.
