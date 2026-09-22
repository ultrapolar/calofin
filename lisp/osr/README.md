# OSR -- put your object snaps back to the preset you chose (AutoLISP / AutoCAD 2018+)

## What it does

Running object snaps drift. Tangent gets ticked for one arc, Nearest
for one leader, F3 goes off to click in open space -- and an hour later
the snaps are whatever the last fiddle left them.

`OSR` sets `OSMODE` to a **preset** you chose once and prints which
modes it put back. It asks nothing.

The preset covers the fourteen modes on the Object Snap tab of
AutoCAD's Drafting Settings (Endpoint, Midpoint, Center, Geometric
Center, Node, Quadrant, Intersection, Extension, Insertion,
Perpendicular, Tangent, Nearest, Apparent intersection, Parallel) and
whether Object Snap is on (F3).

### Choosing the preset

- **Options (`LAZSET`)** -- the panel's Options button. The
  **Object snaps** box has a tick for every mode plus Object Snap On.
  **Use current** copies what the drawing has ticked now, and
  **Default** goes back to the shipped set. Nothing is saved until OK.
- **`CALSET` -> `Osnaps`** -- at the command line: `Current` (Enter),
  `Default`, or an OSMODE number.

It is stored in the AutoCAD profile under `CalofinOsnapPreset`, so it
lasts through restarts and tool updates.

## Install & run

APPLOAD `OSR.lsp` (or `shared/LAZPASS.lsp`, which includes it), then
type `OSR`. `OSRVER` prints the loaded version.

## Tunables

| Knob | Shipped | Changing it |
| --- | --- | --- |
| `osr:*default*` | `191` | the OSMODE used when no preset has been saved: Endpoint, Midpoint, Center, Node, Quadrant, Intersection, Perpendicular, Object Snap on |

## Notes & limitations

- Object Snap Tracking (AUTOSNAP), polar tracking and the 3D object
  snaps (3DOSMODE) are not touched.
- A profile value that is not an OSMODE (0-32767) is ignored and the
  shipped preset used, with a message saying so.
- OSR is the one command in the tree that changes OSMODE on purpose
  and leaves it changed.

## Tests

```
python3 tests/test_osr.py
CALOFIN_LISP_ROOT=shared python3 tests/test_osr.py
```
