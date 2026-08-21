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

`XFTCONV` does all three: it scales what you selected ×12 about the middle of
the selection, then for each marker it inserts the block at the exact centre of
the X, fills in the number with the letter prefix stripped (`P22` → `22`), and
erases the old X and its name text. Any text still left in the selection after
that is erased too. Non-text geometry is scaled and otherwise left alone.

## Install

1. Put `xftconv.lsp` somewhere on your support file search path
   (*Options → Files → Support File Search Path*).
2. `APPLOAD` → add it to the **Startup Suite** so it loads with every drawing.

Or just drag the file into the drawing window to load it for the session.

## Use

Highlighting the import is the only answer it needs:

```
Command: XFTCONV
Select objects:            ← highlight the import (Enter = everything in this space)
```

It reports what it did:

```
Scaling 431 objects by 12.0000 about the middle of the selection ...
118 point(s) replaced with "ab_pt".
26 leftover text object(s) erased.
```

The whole run is a single `U` step, so one undo puts the drawing back if the
import turns out to be worse than usual.

Notes:

- **Always ×12**, always about the centre of the bounding box around everything
  you highlighted. Neither is asked for.
- **All remaining text goes.** Once the point numbers are safely in block
  attributes, every other `TEXT` and `MTEXT` in the selection is erased —
  including point names it could not match to a marker. Highlight only the
  import, or set `*xft-purge-text*` to `nil` if you need the text kept.
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
| `*xft-scale*` | `12.0` | scale factor (feet → inches) |
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
| `*xft-purge-text*` | `t` | erase every text object left in the selection |

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
