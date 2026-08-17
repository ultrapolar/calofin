# XFTCONV — Leica survey import cleanup (AutoCAD 2018)

Takes a raw Leica XFT/DXF survey import and turns it into drawing-ready geometry
in one step: scale it up ×12 and swap every Leica point marker for the `ab_pt`
block with its number in the `number` attribute.

## What it does

Given what the export drops in the drawing:

| stage | what is in the drawing |
| --- | --- |
| **before** | an X made of two crossing `LINE`s on layer `LEICA_POINT`, plus the point name as `TEXT` — `P22` — on layer `LEICA_POINT_NAME` |
| **scaled** | the same thing ×12 — a `0.16404167` high name becomes `1.9685` |
| **after** | an `ab_pt` block on layer `POINTS`, attribute `number` = `22` |

`XFTCONV` does all three: it scales what you selected, then for each marker it
inserts the block at the exact centre of the X, fills in the number with the
letter prefix stripped (`P22` → `22`), and erases the old X and its name text.
Everything else in the selection is just scaled and left alone.

## Install

1. Put `xftconv.lsp` somewhere on your support file search path
   (*Options → Files → Support File Search Path*).
2. `APPLOAD` → add it to the **Startup Suite** so it loads with every drawing.

Or just drag the file into the drawing window to load it for the session.

## Use

```
Command: XFTCONV
Select objects:                      ← highlight the import (Enter = everything in this space)
Scale factor <12.0000>:              ← Enter
Base point for the scale <0,0>:      ← Enter
```

It reports what it did:

```
Scaling 431 objects by 12.0000 ...
118 point(s) replaced with "ab_pt".
2 name text(s) had no marker - left in the drawing so you can look at them.
```

The whole run is a single `U` step, so one undo puts the drawing back if the
import turns out to be worse than usual.

Notes:

- **Already scaled?** Enter `1` at the scale prompt and it will only swap the
  points.
- **Names it could not match** are left in place rather than deleted, so
  anything odd stays visible instead of disappearing quietly.
- **A marker with no name nearby** still gets a block, with a blank number.
- Points nested inside a block reference are not touched — explode first.
- `LEICA_POINT`, `LEICA_POINT_NAME` and `POINTS` must be unlocked; the command
  says so and stops if they are not.
- If layer `POINTS` or block `ab_pt` are missing (a bare DXF rather than the
  template), they are created to match the template — a `POINT` at the origin
  plus the `number` attribute definition.

## Settings

The constants at the top of `xftconv.lsp` are the whole configuration:

| variable | default | meaning |
| --- | --- | --- |
| `*xft-scale*` | `12.0` | default scale factor (feet → inches) |
| `*xft-marker-layer*` | `"LEICA_POINT"` | layer of the X marker (wildcards ok) |
| `*xft-name-layer*` | `"LEICA_POINT_NAME"` | layer of the point name text |
| `*xft-block*` | `"ab_pt"` | block that replaces the marker |
| `*xft-block-layer*` | `"POINTS"` | layer the block goes on |
| `*xft-att-tag*` | `"number"` | attribute tag that holds the number |
| `*xft-att-style*` | `"Attributes"` | text style for the attribute |
| `*xft-att-height*` | `4.0` | attribute height, as on the sample drawing |
| `*xft-att-offset*` | `(0.8697246 -3.5316825)` | attribute offset from the point, as on the sample |
| `*xft-name-reach*` | `6.0` | how far to look for a name, in text heights |
| `*xft-fuzz*` | `1e-4` | tolerance for "these two lines share a centre" |

`XFTCONV-SETUP` is a separate command that only creates the layer and the block,
if you want them in a drawing without running a conversion.

## How the matching works

- The two lines of an X share an identical midpoint, so markers are grouped by
  midpoint rather than by guessing at intersections. A stray `POINT` on the
  marker layer is treated as a marker too, since some exports write those.
- The export stacks the name directly above its marker (2.5 × text height up,
  same X). A name in that same column therefore wins over one that is merely
  closer, which is what keeps tight clusters of points from stealing each
  other's numbers. Failing that, nearest-within-reach wins, and each name is
  used only once.
- The number is everything from the first digit onward, after MTEXT formatting
  codes are stripped: `P22` → `22`, `P1A` → `1A`, `22` → `22`. A name with no
  digits at all is passed through unchanged.
