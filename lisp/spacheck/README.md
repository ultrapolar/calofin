# SPACHECK — audit a finished spa drawing (AutoLISP / AutoCAD 2018+)

Holds a spa sheet against the rules `SPA.LSP` builds to. Every audit is
derived from what SPA actually draws, so **a drawing SPA produced passes
and a hand-edited one shows exactly where it drifted** — which also makes
it a check on drawings that never came from SPA at all.

Highlight the spa drawing **together with its `Spa Cover Details`
block**: the block supplies the grade and taper, and without them the
hinge section has nothing to measure against.

Built from the same bones as `covercheck`, `linfincheck` and `dimcheck` —
the Move/Keep/Pick style review, the stashed-colour markers, the
on-drawing MTEXT report — with the spa rules in place of the liner ones.

## What it checks

1. **The Spa Cover Details block.** One must be in the selection, with a
   readable `TAPER` tag. `GRADE` may be absent — Standard is assumed,
   exactly as SPA assumes it. A Thermo-Light block claiming any taper
   but `1-3/8` is called out.
2. **The cover outline.** Exactly one, on `COVER`, and a single **closed
   bounded entity** — one LWPOLYLINE, or a CIRCLE/ELLIPSE for a round
   spa. Loose lines and arcs are the old pre-bounded output and are
   reported as such.
3. **The water's edge outline.** Optional; a sheet may show one outline
   only. When present it must also be one closed entity, on `POOL`, and
   it must lie **inside** the cover — the cover is always the larger.
4. **The dimension layer.** Every dimension must sit on `DIMENSION`.
   Any that do not are counted, the layers they landed on are named,
   and the report tells you to run **`CDIM`** to move them. This is
   the one dimension check `LITESPACHECKSCAN` keeps.
5. **The dimensions.** Each one for its layer (`DIMENSION`), its style
   (`STANDARD INCHES` for the cover's, `STANDARD INCHES 0.5` for the
   water's edge's) and agreement with its own definition points. Then
   the roster: both overalls present, carrying their `Cover Size` /
   `Water's Edge` note, and **reading the outline's true size**; an
   `Overlap` dimension whenever both outlines are drawn, reading the
   true lap; and the overall standoffs at SPA's 2 ft above / 3 ft left.
6. **The hinges** — the LINEs on `COVER` (the outline is a polyline, so
   the two never confuse) — against the block's grade and taper: a piece
   count the taper allows, no piece wider than the foam sheet, no hinge
   longer than it, the fold/velcro arrangement matching the **Hinge
   Arrangement Chart** for that piece count, and a label on `TEXT`
   against every hinge. Hardware called for by the longest hinge —
   velcro hinges, double C channel, hold down kit — comes out as advice.
7. **Feet and inches.** Every text box — TEXT, MTEXT and the `ATTRIB`
   values on blocks — must state its inches wherever it states feet.
   `5'` is flagged; `5'-0"`, `3'-2"` and a plain `40"` are fine. A feet
   mark is an apostrophe **straight after a digit**, so `Water's Edge`
   is prose and never flagged. `LITESPACHECKSCAN` keeps this one.
8. **The Tech Title date.** The `Date` attribute of the `Tech Title`
   block must read **today**, written `MM/DD/YYYY` — a sheet going out
   under an old date is the mistake this catches. Wrong format, an
   impossible day (`02/30`), a blank, and a stale-but-valid date are
   all reported. The block is looked for in the selection and then
   across the drawing; with none in reach the report says the date was
   not checked rather than flagging it. `LITESPACHECKSCAN` keeps this.
9. **The title block.** Everything on the `border` layer is measured
   together, so a frame drawn as one polyline and one drawn as four
   lines both measure the same. **A spa title block is exactly 0.6× the
   liner block**: the liner nominal is 704 × 543.625, so the spa nominal
   is **422.4 × 326.175**. Anything else is reported with the factor it
   actually came out at, and a border out of proportion is reported
   separately as `STRETCHED`.

The report is an MTEXT placed to the right of the drawing and sized to
scale with it: problems in **red** at full size, advice in **cyan**,
all-clear in green at 75%.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `SPACHECK.lsp`, and load it (add
   it to the *Startup Suite* to have it every session).
2. Highlight the drawing and its details block, then run one of:

| Command | What it does |
| --- | --- |
| `SPACHECK` | The audits, then a walk of everything they flagged — one item at a time, zoomed to each, colouring the ones you confirm are wrong. |
| `SPACHECKSCAN` | The identical audits, **read-only** — writes the report and nothing else. Good as a pre-flight. |
| `LITESPACHECKSCAN` | The scan minus the per-dimension audit (layer, style, span agreement) — for a drawing `DIMCHECK` already went over, when only the spa rules are wanted. It keeps the dimension-layer verdict (which tells you to run `CDIM`) and the feet-and-inches check. |
| `SPACHECKRESCUE` | Puts back every colour SPACHECK stashed and removes the report — the way out after a crash, or once you're done with the marks. |
| `SPACHECKVER` | Prints the loaded version and the title-block size it is checking for. |
| `TUTORIALSPACHECK` | Teaches the tool — see below. |

Pressing Enter at the selection prompt takes the whole drawing. A single
`U` undoes an entire `SPACHECK` run, including the report.

## TUTORIALSPACHECK

Asks up front — **Checks**, **Demo**, or **Both**:

* **Checks** — every audit spelled out at the command line, generated
  live from the tunables below, so the list cannot drift from what the
  code does.
* **Demo** — draws a small practice spa in an empty spot you pick, with
  **three faults planted in it**, and walks you through each one, zoomed
  in and explained:
  1. an overall dimension reading 80 across a cover that is really 84,
  2. a hinge with no label,
  3. a title block left at the liner size instead of 0.6× it.

  It then offers to run `SPACHECKSCAN` for a real report — which names
  those three and nothing else — and to erase the practice drawing
  afterwards.
* **Both** — the checklist, then the demo.

The demo runs inside one UNDO group and never touches existing geometry.

## Tunables

All at the top of the file. The audit is only as right as these are, so
they are named after the SPA globals they shadow.

| Tunable | Default | What it is |
| --- | --- | --- |
| `spachk:*lay-cover*` / `*lay-water*` | `COVER` / `POOL` | where each outline lives |
| `spachk:*lay-dim*` / `*lay-text*` | `DIMENSION` / `TEXT` | dimensions, hinge labels |
| `spachk:*dimfix-cmd*` | `CDIM` | the command the report tells you to run when dimensions are off `*lay-dim*` |
| `spachk:*techtitle-block*` / `*date-tag*` | `Tech Title` / `Date` | the block and attribute carrying the sheet date (spaces optional in the name) |
| `spachk:*ds-cover*` / `*ds-water*` | `STANDARD INCHES` / `... 0.5` | the two dimension styles |
| `spachk:*sfx-cover*` / `*sfx-water*` / `*sfx-lap*` | `Cover Size` / `Water's Edge` / `Overlap` | the notes stacked under a measurement |
| `spachk:*topoff*` / `*dimoff*` / `*off-tol*` | 24 / 36 / 2 | SPA's standoffs, and the slack allowed on them |
| `spachk:*details-block*` | `Spa Cover Details` | the block read for grade and taper |
| `spachk:*liner-w*` / `*liner-h*` | 704 / 543.625 | the liner block nominal |
| `spachk:*title-frac*` | **0.6** | the spa title block as a fraction of it |
| `spachk:*border-layer*` / `*border-tol*` | `border` / 0.005 | where the frame lives, and the slack on "exactly" |
| `spachk:*meas-tol*` | 0.0625 | how close a dim must read to what it spans (1/16", so a fractional dim rounding is not a fault) |
| `spachk:*foamtab*` / `*hardtab*` | — | copies of SPA's foam-sheet and hardware charts, so both tools decide from the same numbers |

## Assumptions

* The drawing is in **inches**, as SPA draws it.
* Hinges are LINEs on `COVER`; the outline is a closed polyline. A
  drawing that puts hinges on another layer will report none.
* "Exactly 0.6×" means within `*border-tol*` — 0.5% either way — so a
  border drawn to 422.4 × 326.175 passes and one at the liner size does
  not. Tighten it to 0.0 to demand the number to the last decimal.
* The roster is the set of dimensions **SPA emits**. A sheet that
  legitimately carries more is not penalised for them; one that carries
  fewer is.

## Notes & limitations

* Requires the Visual LISP engine (bounding boxes), which ships with
  full AutoCAD. **AutoCAD LT has no LISP engine and cannot run this.**
* Loading `SPACHECK.lsp` beside `covercheck.lsp`, `dimcheck.lsp` or
  `linfincheck.lsp` is safe: distinct `spachk:` prefix, `SPACHECK-REPORT`
  layer and `SPACHECK` xdata tag, so no rescue command touches another's
  markers.
* It reports; apart from the colours you confirm in the walk, it does
  **not** repair. Fixing a wrong overall is a job for the person who
  knows which number is right.
* The grouped twin is generated — run `python3 tools/mirror_shared.py
  SPACHECK` after changing this file, never hand-edit
  `shared/parts/SPACHECK.lsp`.

## Tests

```
python3 tests/test_spacheck.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_spacheck.py # grouped tier
```

The tests run the **real** `SPA.LSP` in `tests/lispvm.py` to build a
drawing, then run the **real** `SPACHECK` over that same drawing and
read its report — so a drawing SPA produced must come back clean, and a
drawing damaged in a specific way must come back naming that damage.
Both tools reading one `Spa Cover Details` block is what keeps their two
copies of the foam and hinge charts honest.
