# autocady — AutoCAD Standards Matcher

An AutoLISP plugin that compares selected geometry in the current drawing
against a folder of reference standard DWGs and suggests which standard the
shape looks like — e.g. an outline with an 8'-6" rounded corner gets flagged
as "looks like a PACIFIC".

Works on AutoCAD 2018+ (full, not LT) and is written to be BricsCAD-portable
(no Express Tools, ObjectDBX ProgID probing, plain DCL).

## Install

1. Copy the whole folder anywhere on the machine.
2. In AutoCAD: `APPLOAD` → `src/acady-loader.lsp` (add it to the Startup
   Suite so it loads every session).
3. `MATCHSTD-CFG` → pick any DWG inside your standards folder.

## Commands

| Command        | What it does                                                    |
|----------------|-----------------------------------------------------------------|
| `MATCHSTD`     | Select an outline → ranked match dialog (highlight / zoom).     |
| `MATCHSTD-CFG` | Set the standards folder (persisted per user).                  |
| `ACADY-DUMPSIG`| Dev: print the shape signature of a selection.                  |
| `ACADY-SCAN`   | Dev: parse the standards folder and print what was read.        |

## How matching works

Each shape is reduced to a signature: the ordered ring of segment lengths,
corner radii, and turning angles — independent of position, rotation,
mirroring, and where the polyline starts, but **not** of size.

- **MATCH** — every element of the selected outline fits inside the
  standard's tolerance envelope.
- **CLOSE** — almost (≥80% of elements in tolerance); the off elements are
  shown in the details pane.
- **POSSIBLE** — the whole shape differs, but distinctive features line up
  (e.g. that 8'-6" corner radius, within ±6").

## Standards folder

One DWG per standard; **file name = standard name**. Tolerances are drawn
into each file on the `TOLERANCE` layer (offset MIN/MAX outlines), written as
a `TOL=` text, or defaulted from config. Full authoring rules:
[docs/AUTHORING.md](docs/AUTHORING.md).

Parsed standards are cached (`acady-cache.dat`); files re-parse automatically
when they change.

## Layout

- `src/` — the plugin (load `acady-loader.lsp`; it pulls in the rest)
- `docs/AUTHORING.md` — how to draw a standard + tolerances
- `docs/TESTING.md` — manual test scripts per milestone
- `test/dxf/` — sample fixtures (`pacific`, `atlantic`); SAVEAS to DWG to use
