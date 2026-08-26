# CUSTBLOCK — A custom block drawn from its length, width and height

An AutoLISP routine for AutoCAD 2018+ that asks three sizes and a base
point and draws the block as a **pictorial**: the front face, the top
face and the right-hand face of a box, on the **`COVER`** layer, with
its length, width and height dimensioned on the **`DIMENSION`** layer in
the **`STANDARD INCHES`** style.

It is the drawing on the sample sheet this was written from — an
84 × 36 × 4 block — reproduced from three numbers instead of drawn by
hand.

## What it does

1. **Asks the three sizes**, in this order:

   ```
   Block length:
   Block width [Back]:
   Block height [Back]:
   Insertion base point [Back] <0,0>:
   ```

   * **length** is the long axis, the one that runs **back-right** into
     the sheet;
   * **width** runs **across** the front face;
   * **height** runs **up** it.

   Type the number or pick the distance in the drawing — your own object
   snaps stay live for that, and for the base point. All three are
   required and all three must be positive. `Back` (or `Undo`, or `B`)
   at any question after the first re-asks the one before it; nothing is
   drawn until all four answers are in, so backing out costs nothing.

2. **Draws nine lines on `COVER`.** The base point is the block's
   **front bottom left** corner. The back face is the front face slid
   up-right at 45°, and it is slid by the true length ÷ √2 on each
   axis — so the receding edge measures the length that was typed. It is
   a pictorial, not an isometric projection: nothing is foreshortened.

   The three **hidden** edges — the bottom-left receding edge and the
   bottom and left edges of the back face — are **not** drawn. That is
   what makes the block read as a solid rather than a wire cage; no edge
   at all reaches the back bottom-left corner.

3. **Dimensions it three times**, on `DIMENSION` in `STANDARD INCHES`:

   | Dimension | Where it goes | Kind |
   | --- | --- | --- |
   | length | along the top-left receding edge, pushed out clear of the top face | aligned |
   | height | up the left of the front face | linear, held vertical |
   | width | along under the front face | linear, held horizontal |

   Text centred, dimension lines standing `cbk:*dimoff*` clear of the
   block. The two linear dims have their axis **forced**, not left to
   AutoCAD to infer from where the dimension line landed, so a retuned
   stand-off cannot flip a width dim into a height one. Each is put on
   the layer and in the style CUSTBLOCK promises, **ByLayer** — any
   per-entity colour, linetype or lineweight override the command left
   behind is stripped.

The whole run is one undo group, so a single `U` takes the block and its
dimensions away together. The dimension style, current layer, `CMDECHO`
and `OSMODE` in force before the command are restored afterwards,
whether the run finishes, errors, or is cancelled with Esc.

## Install & run

1. Load the file: `Manage` ribbon → `Load Application` (`APPLOAD`) →
   pick `CUSTBLOCK.lsp`. Add it to the *Startup Suite* to have it in
   every drawing.
2. Type the command:

   | Command | What it does |
   | --- | --- |
   | `CUSTBLOCK` | Ask length, width, height and a base point, and draw the block |
   | `CUSTBLOCKVER` | Print the version |

## Tunables

`setq` these after loading (in a startup file, say) when a drawing needs
different names:

| Variable | Default | Meaning |
| --- | --- | --- |
| `cbk:*layer*` | `"COVER"` | Layer the nine block lines go on |
| `cbk:*laycolor*` | `7` | Colour that layer is **created** with, when the drawing has no such layer yet |
| `cbk:*dimlayer*` | `"DIMENSION"` | Layer the three dimensions go on |
| `cbk:*dimcolor*` | `141` | Colour *it* is created with |
| `cbk:*style*` | `"STANDARD INCHES"` | Dimension style the new dims get |
| `cbk:*dimoff*` | `12.0` | How far the dimension lines stand off the block, in drawing units — a foot in an inch drawing |

## Notes & limitations

* **The base point is the front bottom left corner**, and its elevation
  is carried: based at a point with a Z, the whole block is drawn at
  that Z, so a UCS with an elevation is honoured. Enter takes `0,0`.
* **The current UCS is honoured.** The base point arrives in the UCS
  you are working in and the block is built in it, so the front face is
  square to your UCS rather than to the world. The lines are translated
  to world coordinates on the way into the drawing; the dimensions are
  handed their points in the UCS, which is what a command reads.
* The block lines are made with `entmakex`, not the `LINE` command — no
  command echo, no chance of a running object snap catching an endpoint,
  and the layer is stated outright instead of depending on `CLAYER`.
* Both output layers are **created** when the drawing lacks them — and
  when one is already there but frozen, locked or switched off, it is
  thawed, unlocked and switched back on, with a line saying so. A run
  onto a frozen layer would otherwise look like the command did nothing.
* A missing `STANDARD INCHES` style is **not** invented. The dims are
  drawn in whatever style is current and the routine says so, so a
  drawing started from the wrong template is obvious instead of quietly
  producing wrong-looking dims. Create the style — or start from the
  standard template — and run it again.
* `DIMLAYER` (which forces dimensions onto a layer of its own,
  regardless of the current layer) does not get the last word: each new
  dimension is pulled back onto `DIMENSION` after it is drawn.
* Nothing is grouped or blocked: the result is nine plain lines and
  three plain dimensions, so any of it can be stretched, trimmed or
  re-dimensioned afterwards like anything else on the sheet.
* CUSTBLOCK draws one block per run. Run it again for the next one.

## Tests

`python3 tests/test_custblock.py` loads the real `CUSTBLOCK.lsp` into the
repo's AutoLISP VM (`tests/lispvm.py`) and drives `c:CUSTBLOCK` with
scripted answers: the sample sheet's 84 × 36 × 4 block asserted corner by
corner, the three hidden edges absent, the three dimensions' kinds,
measurements, layer, style and stand-offs, the forced linear axes, a
moved base point, an elevated one, Enter at the base point, `Back` and
`Undo` at each of the three questions that offer them, `Back` refused at
the first, a drawing with no `STANDARD INCHES` style, a frozen `COVER`
layer, a cube, zero and negative sizes, and the closing report.
`CALOFIN_LISP_ROOT=shared python3 tests/test_custblock.py` runs the same
suite against the grouped build.
