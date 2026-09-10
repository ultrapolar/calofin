# G2MCONV -- a G2M architectural export converted onto the shop layers (AutoLISP / AutoCAD 2018+)

Takes a pool plan the way a G2M architect exports it -- AIA layer names
with a Spanish half after them, the architect's own text and dimension
styles, an annotative flag on every dimension -- and puts the whole
thing on the layers and styles the rest of the build looks for, in one
command and one undo step.

It is the third of the converter family (`XFTCONV`, `SOCONV`, `VSCONV`)
and sits between the other two in how much it changes. `SOCONV` is a
layer remap and nothing else. `VSCONV` remaps and restyles the
dimensions. **G2MCONV remaps, forces the appearance, restyles the notes
AND the dimensions, and turns the annotative flag off** -- not because
a cleanup is nice to have, but because each of those is an override
that outranks the layer or style it now sits on, so a layer move alone
would leave the plan looking exactly as it did before.

## What it does

Five rules, applied in order, first match winning:

| from the export | what is on it | onto | linetype | scale |
| --- | --- | --- | --- | --- |
| `1 A POOL WALL - PARED PISCINA` | everything | `POOL` | ByLayer | 0.4 |
| `A-STAIRS - GRADAS` | everything | `POOL` | `DASHED2` | left alone |
| `A-ANNO-TEXT - TEXTO` | everything | `TEXT` | ByLayer | 0.4 |
| `A-ANNO-DIMS - DIMENSIONES` | `TEXT`, `MTEXT`, `MULTILEADER` | `TEXT` | ByLayer | 0.4 |
| `A-ANNO-DIMS - DIMENSIONES` | everything else | `DIMENSION` | ByLayer | 0.4 |

Three things about that table are worth saying out loud:

* **Two source layers land on `POOL`, and they still tell each other
  apart.** The wall and the stairs are one drawing to this office and
  two to the architect -- but the wall arrives solid and the stairs in
  the architect's `HIDDEN2`, which is the whole point of a stair under
  water. So the stairs row carries the shop's own dashed pattern
  instead of going ByLayer with everything else, and keeps its own
  linetype scale. That row is the only one that lands *dashed*, and
  0.4 would shrink `DASHED2` to two-fifths of the size the drawing's
  `LTSCALE` was set for, closing it up until it reads solid. On the
  other four rows the 0.4 is simply what the drawing gives anything
  drawn in it -- its `CELTSCALE` -- so a converted object carries the
  same scale as whatever the shop draws beside it later.
* **`A-ANNO-DIMS - DIMENSIONES` splits in two**, which is what the
  ordering is for -- the same shape `SOCONV` uses on its export's one
  `Dimensions` layer. The notes and the leaders are caught by the text
  row, so the catch-all under it takes the dimensions and whatever else
  the architect left on that layer (the sample left an arc).
* **The layer names are `wcmatch` patterns.** An architect who numbers
  the wall layer differently, or drops the Spanish half, is retuned in
  `*g2mconv-map*` and nowhere else: `"A-STAIRS*"` and `"*GRADAS"` both
  work as a row's first column.

Then the three overrides, each of which would otherwise outrank what it
sits on:

1. **Appearance.** Colour and lineweight go BYLAYER
   (`*g2mconv-force-bylayer*`), the linetype goes to the map's fourth
   column, and the linetype scale to the fifth. The export writes an
   explicit `Continuous` onto geometry that then cannot follow its
   layer; this takes it off.
2. **Notes.** Every `TEXT` and `MTEXT` the run moves is put on the shop
   text style (`Attributes`) at the shop text height (`9.5`). The
   architect's notes arrive in Century Gothic at 4.384 -- a paper
   height already scaled by a viewport -- and read half-size beside the
   shop's own. It is both or neither: a height is measured for the
   style it is set in, so a drawing without the shop style keeps the
   architect's style AND height, and the run says so.
3. **Dimensions.** Every dimension is put on the shop dimension style
   (`STANDARD`), has its `ACAD`/`DSTYLE` override block removed, and
   stops being annotative. All three for one reason: a dimension merely
   renamed to `STANDARD` would still draw itself in the architect's
   text through its override block, and an annotative one would still
   scale itself by the viewport.

The three numbers in 1 and 2 are not invented -- they are `$CELTSCALE`,
`$TEXTSTYLE` and `$TEXTSIZE` as the shop drawing carries them, which is
what the drafter's hand conversion put on every object it touched.

**Nothing is erased and nothing is drawn.** The leaders keep their own
multileader style and the text inside them keeps its height; the sample
restyles the standalone notes and leaves the leaders alone, and so does
this. The emptied source layers are left in the drawing and named in
the done line rather than purged, so the whole run stays one `U`.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `G2MCONV.lsp`, and load it (add
   it to the *Startup Suite* to have it every session). The shared
   build (`shared/LAZPASS.lsp`) carries it too.
2. Open the export and:

| Command | What it does |
| --- | --- |
| `G2MCONV` | Move the export onto `POOL` / `TEXT` / `DIMENSION`, and restyle it |
| `G2MRECONV` | Put it all back on the architect's layers and styles |
| `G2MCONVVER` | Print the loaded version |

The one question is what to convert:

```
Command: G2MCONV
Select the G2M export to convert <Enter = whole drawing>:
```

Highlight the plan first and it converts the highlight without asking.
Enter at the prompt takes the whole drawing, which is what an export
usually is. Either way only the layers in the table are touched, so a
sheet that already carries converted work cannot be converted twice --
run it again and it says so rather than reporting a conversion of
nothing.

What it reports:

```
G2MCONV done: 63 object(s) moved -- 29 -> POOL, 22 -> TEXT, 12 -> DIMENSION.
  10 note(s) restyled to Attributes at 9.50.
  9 dimension(s) put on STANDARD, style overrides removed.
  Moved off 1 A POOL WALL - PARED PISCINA, A-STAIRS - GRADAS, ... - PURGE
  those layers once the result looks right.
  G2MRECONV moves it all back; PURGE only when you are sure.
```

It will not purge the emptied layers itself: purging is not part of the
undo group, and one `U` has to back the whole run out.

## Undoing it -- `G2MRECONV`

`U` undoes a run while the session lasts. `G2MRECONV` undoes one that
was saved and reopened -- which is when a sheet turns out to have been
converted by mistake, or has to go back to the architect it came from.

Every object `G2MCONV` moves carries a record in its own xdata under
`"G2MCONV"`: the layer it came off and that layer's colour, the
colour, linetype, lineweight and linetype scale the appearance step
overwrote, the text style and height the text step overwrote, the
annotative flag, and -- for a dimension -- the style name it had and
the whole `ACAD`/`DSTYLE` block, kept verbatim as the xdata items it
already was. Every step is undone, or the revert would leave the
drawing in a state neither the architect nor the shop ever drew.

A source layer `PURGE`d on the tool's own advice is re-created, in the
colour the record kept off the layer itself.

Two things to know:

* **A linetype or style the record names that the drawing no longer
  has stops that object being finished.** It keeps its record and is
  named in the report, so loading the pattern or the style back and
  running `G2MRECONV` again finishes the job rather than finding
  nothing left to do.
* **One thing the revert spells out rather than restores.** An object
  that arrived carrying no colour, linetype, lineweight or linetype
  scale of its own comes back carrying an explicit ByLayer -- `256`,
  `"ByLayer"`, `-1`, `1.0` -- where it had the absent group that means
  the same thing. It draws and plots identically, and a DXF diff of
  the before and after says so; nothing else about the round trip is
  approximate.

## Tunables

Everything settable is in one block at the top of `G2MCONV.lsp`.

| Tunable | Default | Changing it |
| --- | --- | --- |
| `*g2mconv-map*` | the five rows above | The conversion IS this table: source layer, entity types, destination, linetype, linetype scale. Both patterns are `wcmatch`; rows are tried in order, first match winning. The linetype scale is a column rather than a knob of its own: the rows are quoted data, so a global beside them would be a setting nothing reads |
| `*g2mconv-make-dashed2*` | `T` | Whether a missing `DASHED2` is created on the spot. `nil` and a run that needs it names it and leaves those objects' linetype alone |
| `*g2mconv-colors*` | `POOL` 4, `TEXT` 4, `DIMENSION` 141 | The colour a destination layer is **created** with. A drawing that already has the layer keeps its own colour |
| `*g2mconv-default-color*` | `7` | The colour for a destination the table above does not name |
| `*g2mconv-force-bylayer*` | `T` | Whether colour and lineweight go BYLAYER on the way past. The linetype is the map's own column, not this switch's |
| `*g2mconv-text-style*` | `"Attributes"` | The text style every moved note is put on. `nil`, or a style the drawing has not got, leaves the notes' style and height as they arrived |
| `*g2mconv-text-height*` | `9.5` | The height that goes with it |
| `*g2mconv-dim-style*` | `"STANDARD"` | The dimension style every moved dimension is put on. A style the drawing has not got leaves the dimensions' style and overrides alone, with a line saying so |
| `*g2mconv-dim-xdata*` | `"ACAD"` | The application whose style overrides come off each dimension. `nil` leaves the overrides on and changes only the style name |
| `*g2mconv-deannotate*` | `T` | Whether an object that arrives annotative stops being so. `nil` and an annotative dimension keeps scaling itself under the shop's style name |
| `*g2mconv-anno-xdata*` | `"AcadAnnotative"` | The application that flag lives under |
| `*g2mconv-record*` | `T` | Whether the record `G2MRECONV` reads is written at all. `nil` converts exactly as before and writes nothing down, so only `U` undoes the run |
| `*g2mconv-xdata-app*` | `"G2MCONV"` | The application the record lives under |

`*g2mconv-record-len*` is **not** a knob -- it is the length of the
record's fixed part, which the reader indexes into. Changing it does
not change the record's shape, it stops the reader agreeing with the
writer.

## How the rules were arrived at

From `G2MCONV.dxf`, a before/after sample the shop supplied: one plan
converted by hand, kept beside the original in the one drawing, 63
objects. Every row of the table, and every one of the three overrides,
is what the drafter's own hands did to those objects, pair for pair.

**Two things in the sample are edits rather than rules, and are not in
the tool.** Its after side leaves three objects behind on the export
layers -- one arc, one leader and one `GRASS` note -- where the same
kind of object either side of them converted; the drafter's window
missed them, and the give-away is that the other five notes on that
layer went across. And three of the converted notes have a defined
width of exactly 130 where the rest carry the width AutoCAD recomputed
for them; that is a drag of the text box, not a number the tool could
know. MTEXT widths are left to AutoCAD here, which is what produced
every other width in the sample.

**One judgement call the sample does not settle: which way a leader on
the annotation layer goes.** The drafter sent six of the twelve to
`TEXT` and five to `DIMENSION` and left one behind, and the twelve are
otherwise identical -- same multileader style, same `4"` in most of
them -- so there is no rule in there to find, only a window dragged
twice. They go to `TEXT`: a leader is a note with a line attached, it
is where the majority went, and it is what `SOCONV` already does with
the notes on its export's dimension layer. The fourth row of
`*g2mconv-map*` is the one line that changes its mind, and
`tests/test_g2mconv.py` drives it both ways.

## Notes & limitations

* **It does not purge**, on purpose: purging is not part of the undo
  group. The done line names the emptied layers for you.
* **It converts what is in model space**, or what you highlight. An
  export arriving as an xref has to be bound first -- there is nothing
  on the shop's layers to move until it is.
* **A locked source layer** is unlocked for the run and re-locked
  afterwards, on the error path too. A destination layer that is
  frozen, locked or off is repaired *for good*, with a line saying so:
  it is an output layer, and a successful run onto an invisible one
  looks like the command did nothing.
* **The leaders' own text is not restyled.** A multileader carries its
  style and its text inside itself, and the sample leaves both alone.
  A shop that wants them restyled has an `MLEADERSTYLE` change, not a
  conversion.
* **Blocks are moved, not exploded.** An object on a source layer moves
  whatever it is; geometry nested inside a block definition is on
  whatever layer the definition puts it on and is not reached.

## Tests

```
python3 tests/test_g2mconv.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_g2mconv.py # grouped tier
```

The suite builds a plan the way the export drops it, runs the real
commands over it, and checks the layers, all three overrides, the
locks, the undo mark, the error and Esc paths, the tunables one at a
time, and the whole round trip through `G2MRECONV` -- including that a
note's own `ACAD` xdata (`ACAD_MTEXT_DEFINED_HEIGHT`) survives the
dimension step, which deletes an application by name.
