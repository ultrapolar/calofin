# XFTCONV — survey import cleanup (AutoCAD 2018)

Takes a raw survey import and turns it into drawing-ready geometry in one step:
scale it up ×12 and swap every point marker for the `ab_pt` block with its
number in the `number` attribute.

Two exports are read, and XFTCONV acts on whichever it finds in the selection:

| flavour | its point marker | its point name |
| --- | --- | --- |
| **Leica XFT** | an X of two crossing `LINE`s on layer `LEICA_POINT` (a plain `POINT` there works too) | `TEXT`/`MTEXT` on layer `LEICA_POINT_NAME`, stacked above the marker — `P22` |
| **site trace** | a small `CIRCLE` on layer `POOL_POINTS`, `BREAK_LINES` or `CROSS_MEASUREMENTS` | `TEXT` on layer `TEXT`, sitting **on** the circle's centre — `C1` |

Both arrive in feet, and both leave as the same thing.

## What it does

| stage | what is in the drawing |
| --- | --- |
| **before** | the marker and the name text, per the table above |
| **scaled** | the same thing ×12 — a `0.16404167` high name becomes `1.9685` |
| **after** | an `ab_pt` block on layer `POINTS`, attribute `number` = `22` (Leica) or `C1` (trace) |

`XFTCONV` does all three: it scales what you selected ×12 about the middle of
the selection, then for each marker it inserts the block at the exact centre of
the marker, fills in the number, and erases the old marker and the name text it
used. Non-text geometry is scaled and otherwise left alone.

### Two things the trace flavour does differently

- **A corner is drawn twice.** The trace puts a circle on `POOL_POINTS` for the
  pool corner and another on `CROSS_MEASUREMENTS` where a diagonal ends, at the
  same coordinate. Markers are grouped by location, so the pair becomes the one
  block it should be — and both circles are erased.
- **The letter stays on.** Leica names every point `P<n>`, so the `P` is noise
  and `P22` → `22` loses nothing. The trace's letter is the point's family — `C`
  for a pool corner, `S` for a shallow-end break, `D` for a deep-end one — and
  the numbers restart per family, so `C1`, `S1` and `D1` would all strip to `1`:
  three points wearing one number in the attribute every downstream tool labels
  them from. The trace's label therefore goes in whole. `*xft-dot-strip-prefix*`
  is the line that changes its mind.

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

and on a site trace, where the circle count is called out so a support
screenshot says which export was read:

```
Scaling 39 objects by 12.0000 about the middle of the selection ...
8 point(s) replaced with "ab_pt".
8 of those were circle markers off a site trace (POOL_POINTS,BREAK_LINES,CROSS_MEASUREMENTS).
```

The whole run is a single `U` step, so one undo puts the drawing back if the
import turns out to be worse than usual. (In a drawing with undo recording
switched off -- `UNDO` `Control` `None` -- it runs without a group rather than
dying on the group it could not open; it used to.)

Notes:

- **Always ×12**, always about the centre of the bounding box around everything
  you highlighted. Neither is asked for.
- **Leftover text goes, for the Leica flavour only.** A Leica export writes
  nothing but point names, so once the numbers are safely in block attributes
  every other `TEXT` and `MTEXT` in the selection is erased — including names it
  could not match to a marker. Highlight only the import, or set
  `*xft-purge-text*` to `nil` if you need the text kept. **A site trace is not
  swept**, because it captions its own break lines and diagonals (`Deep End`,
  `Diagonal 1`) on the same layer as the point names, and a blanket sweep would
  throw the survey's annotation away with the noise. The name text a point
  actually used is erased either way. A selection holding both flavours — which
  no real import does — is swept.
- **A marker with no name nearby** still gets a block, with a blank number.
- Points nested inside a block reference are not touched — explode first.
- **Locked layers stop the run**, and the message names the ones that are
  actually in the way: any layer carrying something highlighted that the swap
  has to erase, plus `POINTS`. A locked layer with none of the selection on it
  is not in the way and is not mentioned.
- If layer `POINTS` or block `ab_pt` are missing (a bare DXF rather than the
  template), they are created to match the template — a `POINT` at the origin
  plus the `number` attribute definition.

## Settings

The constants at the top of `xftconv.lsp` are the whole configuration, and
each one carries its explanation in the file -- what it is, when to change it
and what depends on it. Nothing below that section is meant to be edited for a
shop's own conventions.

| variable | default | meaning |
| --- | --- | --- |
| `*xft-scale*` | `12.0` | scale factor applied to the whole selection (feet → inches); `1.0` skips the SCALE step |
| `*xft-block*` | `"ab_pt"` | block that replaces the marker; built to match the template if missing |
| `*xft-block-layer*` | `"POINTS"` | layer the block goes on; created if missing, repaired if frozen or off |
| `*xft-block-layer-color*` | `6` | colour a missing `POINTS` is **created** with (magenta, as `SOCONV`, `VSCONV` and `DRONE` create it); an existing layer is never recoloured |
| `*xft-att-tag*` | `"number"` | attribute tag that holds the number |
| `*xft-att-style*` | `"Attributes"` | text style for the attribute; the current `TEXTSTYLE` when the drawing has no such style |
| `*xft-att-height*` | `4.0` | attribute height, after the scale, as on the sample drawing |
| `*xft-att-offset*` | `(0.8697246 -3.5316825)` | attribute offset from the point, after the scale, as on the sample |
| `*xft-marker-layer*` | `"LEICA_POINT"` | layer of the Leica X marker (a `wcmatch` pattern) |
| `*xft-name-layer*` | `"LEICA_POINT_NAME"` | layer of the Leica point name text (a `wcmatch` pattern) |
| `*xft-name-reach*` | `6.0` | how far to look for a Leica name, in text heights |
| `*xft-strip-prefix*` | `T` | take the letter prefix off a Leica name (`P22` → `22`); `nil` keeps the label whole |
| `*xft-purge-text*` | `T` | erase every text object left in the selection (Leica flavour) |
| `*xft-dot-layer*` | `"POOL_POINTS,BREAK_LINES,CROSS_MEASUREMENTS"` | layers the trace's circle markers sit on (a `wcmatch` comma list) |
| `*xft-dot-name-layer*` | `"TEXT"` | layer of the trace's point name text |
| `*xft-dot-reach*` | `1.0` | how far to look for a trace name, in text heights |
| `*xft-dot-strip-prefix*` | `nil` | take the letter prefix off a trace name too |
| `*xft-dot-purge-text*` | `nil` | erase every text object left in the selection (trace flavour) |
| `*xft-column-tol*` | `0.5` | how far off the marker's X, in text heights, a name still counts as "in its column" -- the rule that beats plain nearness |
| `*xft-fuzz*` | `1e-4` | tolerance, after the scale, for "these two markers share a centre" |

`XFTCONV-SETUP` is a separate command that only creates the layer and the block,
if you want them in a drawing without running a conversion.

## How the matching works

- The two lines of an X share an identical midpoint, so markers are grouped by
  midpoint rather than by guessing at intersections. A stray `POINT` on the
  marker layer is treated as a marker too, since some exports write those.
- The trace's circles are grouped by centre for the same reason, which is what
  merges a corner's `POOL_POINTS` copy with its `CROSS_MEASUREMENTS` one.
- Each flavour matches its own markers against its own names, at its own reach —
  they are never pooled, so a trace caption can never be offered to a Leica
  marker six text heights away.
- Both exports put the name in the marker's column: Leica stacks it directly
  above (2.5 × text height up, same X), the trace lands it on the centre. A name
  in that column -- its X within `*xft-column-tol*` text heights of the
  marker's -- therefore wins over one that is merely closer, which is what
  keeps tight clusters of points from stealing each other's numbers. Failing
  that, nearest-within-reach wins, and each name is used only once.
- **The reach is what tells a trace's name from its caption**, since both are on
  layer `TEXT`. `Deep End` is justified onto the middle of its break line, in
  the same column as both endpoints — exactly where the column rule would reward
  it — but it is half a break line away, and `*xft-dot-reach*` gives a name one
  text height to be found in. The Leica reach is six, because there the name is
  a deliberate distance above its marker and the layer already rules the rest of
  the drawing out.
- The Leica number is everything from the first digit onward, after MTEXT
  formatting codes are stripped: `P22` → `22`, `P1A` → `1A`, `22` → `22`. A name
  with no digits at all is passed through unchanged. A trace name is passed
  through whole (see above), formatting codes stripped and trimmed. Each
  flavour has its own switch -- `*xft-strip-prefix*` and
  `*xft-dot-strip-prefix*` -- with opposite defaults, for the reasons above.

## Tests

```
python3 tests/test_xftconv.py
CALOFIN_LISP_ROOT=shared python3 tests/test_xftconv.py
```

The trace sections run the sample export's own geometry — a 40′ × 20′
rectangular pool in feet, its four corners drawn twice, its two break lines
captioned — and assert that the captions survive and that no point ends up
called `Deep End`. The second command runs the same script over the grouped
twin in `shared/parts/`, with the library loaded first.

After the two flavours come the contingencies: undo switched off in the
drawing (no group opened, so none closed), an import already in inches
(`*xft-scale*` `1.0`), a plain `POINT` for a marker, an MTEXT name and a
justified one, every settings switch in its non-default position, a frozen
and switched-off `POINTS` repaired rather than drawn onto blind, the
attribute style falling back to `TEXTSTYLE`, an error mid-run reaching the
command's own handler, both flavours in one highlight, and `XFTCONV-SETUP`.
