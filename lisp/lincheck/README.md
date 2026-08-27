# LINCHECK -- liner tech drawing checklist (AutoLISP / AutoCAD 2018+)

Runs down the liner drawing checklist one item at a time at the
command line -- read the notes, verify wall height and depth, place
the liner pattern block, dims and orientation, corners, special bottom
conditions, trowel lines, the steps/bench branches -- and prints a
report of everything checked, answered and noted along the way. It
draws nothing and changes nothing in the drawing; it is the checklist,
not the fixer. Shipped alongside the `CCPRECHECK` flowchart walker
(`lisp/ccprecheck/`).

## What it does

The items, in order (each either a check-off you Enter through --
optionally typing a note or value to record with it -- a `[Yes/No]`
question, or a value prompt that takes `NA`):

* **Job Review** -- read all WSN, Notes from Merlin and Customer Info;
  then the gate: `Does this job actually require a Tech drawing?
  [Yes/No]` -- `No` stops the checklist (the report still prints).
* **Walls & Depth** -- verify finished wall height and pool depth;
  record the Finished Wall Ht (a single value, or "Varies").
* **Liner Pattern & Bead** -- place the liner pattern block (GLP),
  delete the "Not Supplied" text; record the bead type / overlap.
* **Dimensions & Orientation** -- perimeter and overall dims; verify
  the shallow end is to the RIGHT of the page; then report ALL
  customer cross dimensions in a loop (`label=value`, e.g.
  `A-C=24'6"`, blank line to finish, `B` removes the last entry).
* **Corners** -- pool corners with dimensions; watch for special
  manufacturers (Esther Williams 3x3/5x5, Foxx 37" deep).
* **Special Bottom Conditions** -- cove, safety ledge, various
  depths provided, side view required (all `[Yes/No]`).
* **Bottom & Trowel Lines** -- are hopper corners radius; draw trowel
  lines accurately.
* **Steps / Bench, Fiberglass** -- if Yes: place the FGS note or draw
  the outline, and `Is the step Straight or Radius? (ask if not
  given) [Straight/Radius]` (this is the step FACE, not a corner
  treatment).
* **Steps / Bench, Vinyl-Covered** -- if Yes: verify step corner type
  and dims, place the Step Attachment block, is the attachment type
  provided, place side views for all steps and benches.
* **Final** -- did you scale the titleblock (** REDVIEW! **).

Then the LINER CHECKLIST REPORT prints: every item with `[x]`, the
notes you typed, the values recorded (or `NA (not provided)`), and the
cross-dim list.

**Back everywhere after the first item.** `Back` re-asks the previous
item and drops what it logged (`Undo` accepted; at the typed prompts
type `B`, `BACK`, `U` or `UNDO` alone, any case -- the prompts say
so). Branch tests are re-evaluated on the way back through, so
changing the Fiberglass or Vinyl-covered answer re-routes which items
follow. The cross-dim loop's `B` removes the last entry first, then
backs out of the stage.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `lincheck.lsp`, and load it
   (add it to the *Startup Suite* to have it every session). The
   shared build (`shared/LAZPASS.lsp`) carries it too.
2. Type the command and work down the list:

| Command | What it does |
| --- | --- |
| `LINCHECK` | Run the liner checklist and print the report |

## Assumptions

* The checklist items and their order are fixed in the file -- there
  are no tunable globals. Changing an item means editing the
  `lin:st-*` stages in `lincheck.lsp`.
* Output is command-line text only; nothing is placed in the drawing,
  written to disk, or remembered between runs.

## Notes & limitations

* Because the command touches no drawing state, cancelling with Esc
  mid-list loses only the answers collected so far -- there is nothing
  to restore and no undo group (and no `*error*` handler, a known
  structure gap listed in `STANDARDS.md` section 7.4).
* The report is printed, not returned: copy it off the text screen
  (F2) if it needs to go anywhere.
* The `[Straight/Radius]` question is a step-face shape, not the
  corner Treatment vocabulary -- `STANDARDS.md` section 7.1 flags it
  for review in migration rather than auto-renaming.

## Tests

`python3 tests/test_lincheck.py` drives the real checklist end-to-end
in the repo's AutoLISP VM: the full run, the does-not-need-a-drawing
gate, the Back step (B/U at typed prompts, Back/Undo at keyword
prompts) with its report rollback, branch re-routing after a Back, and
the cross-dim loop's remove-last behaviour -- asserting exact report
lines, so a wording change here fails loudly.
`CALOFIN_LISP_ROOT=shared python3 tests/test_lincheck.py` reruns it
against the grouped build.
