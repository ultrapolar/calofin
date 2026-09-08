# CCPRECHECK -- walk the Tech Flow Chart product checklist (AutoLISP / AutoCAD 2018+)

Walks the "Tech Flow Chart" decision tree for pool/spa products at the
command line: it asks you to answer or confirm each item along the
flowchart until every branch it enters reaches its end, then prints a
summary of every note and confirmation collected on the way. It draws
nothing and changes nothing in the drawing.

Renamed from `CHECK` during consolidation: that name also belonged to
the dimension/arc geometry audit in `lisp/check/`, which kept it (see
the root `README.md`, "`ABCDEF` vs `ALTABCDEF`, and `CHECK` vs
`CCPRECHECK`").

## What it does

The top level asks `Product type [Liner/PoolCover/SpaCover]` and each
answer opens its branch:

* **Liner** -> `Liner for [Pool/Spa]`, then confirmations (liner
  pattern, corners, depth / wall height; a spa adds `Spillway?
  [Yes/No]` with its detail note and dimensions) and the shared steps
  sub-flow: `Steps? [Yes/No]`, `Step type [Fiberglass/VinylOver]`,
  with the follow-up confirms each type needs (step face straight or
  radius and step size for fiberglass; riser sum vs wall height and
  step back corners for vinyl-over).
* **PoolCover** -> `Pool shape [Freeform/Rectangle]` (18" overlap and
  3x3 spacing vs 12" and 5x5, unless stated otherwise), overlap and
  spacing confirmed, `Are there obstacles? [Yes/No]` opening the
  obstruction flow (`Proximity to water's edge
  [MoreThan3ft/OverlapTo3ft/ZeroToOverlap/InsidePerimeter]` and its
  follow-ups), then the decking flow: `Decking material
  [Concrete/Paver/Grass/Wood]`, the raised-wood questions with
  `Strap type [ExtendedStraps/ExtensionStraps]`, and `Deck space (for
  springs) [GreaterThan18in/9to18in/6to9in/LessThan4in]`.
* **SpaCover** -> `Spa cover type [SafetyCover/HardCover/ThermoLight]`:
  the safety flow (spillway, obstructions -- reusing the pool-cover
  obstruction flow -- raised, attachment, drum style, joined wall),
  the hard-cover flow (`Spa type [AboveGround/InGround]`, pieces no
  more than 48", hinges, cover size, the spillway rules), or the
  ThermoLight confirmations.

Every rule the chart encodes ("Avoid strap", "Up and Over", "9\" Tubes
/ 15\" Tubes", ...) is printed as a `>>` note when its branch is
taken, and logged. `Confirm ...` prompts take a typed value or note,
or plain Enter.

**Back everywhere after the first question.** `Back` (hidden synonym
`Undo`; at typed Confirm prompts type `B`, `BACK`, `U` or `UNDO`
alone) re-asks the previous question and drops what it logged --
including backing OUT of a sub-branch into the question that opened
it. Branch tests are re-evaluated on every pass, so changing an answer
re-routes the walk. The first question has nothing to go back to.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `ccprecheck.lsp`, and load it
   (add it to the *Startup Suite* to have it every session). The
   shared build (`shared/LAZPASS.lsp`) carries it too.
2. Type `CCPRECHECK` and answer the prompts; the summary prints when
   the walk ends.

| Command | What it does |
| --- | --- |
| `CCPRECHECK` | Walk the flowchart and print the summary |

## Tunables

Every value CCPRECHECK reads that you might want to change sits in one
`TUNABLES` block at the top of `ccprecheck.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**How the summary reads**

| Global | Default | Meaning |
| --- | --- | --- |
| `chk:*note-mark*` | `"NOTE: "` | The summary is printed to the command line when the walk finishes, one line per thing answered or noted. These are the pieces it is built from: what marks an instruction the walk gave you, what marks something you confirmed, and the two separators -- between a question and the answer picked, and between a confirmation and the value typed against it |
| `chk:*confirm-mark*` | `"CONFIRMED: "` | The summary is printed to the command line when the walk finishes, one line per thing answered or noted. These are the pieces it is built from: what marks an instruction the walk gave you, what marks something you confirmed, and the two separators -- between a question and the answer picked, and between a confirmation and the value typed against it |
| `chk:*ans-sep*` | `" -> "` | The summary is printed to the command line when the walk finishes, one line per thing answered or noted. These are the pieces it is built from: what marks an instruction the walk gave you, what marks something you confirmed, and the two separators -- between a question and the answer picked, and between a confirmation and the value typed against it |
| `chk:*val-sep*` | `" = "` | The summary is printed to the command line when the walk finishes, one line per thing answered or noted. These are the pieces it is built from: what marks an instruction the walk gave you, what marks something you confirmed, and the two separators -- between a question and the answer picked, and between a confirmation and the value typed against it |
| `chk:*note-echo*` | `"\n  >> "` | A note is echoed to the command line as it is given, behind this |
| `chk:*sum-open*` | `"\n\n--- Checklist summary ---"` | The summary's own furniture: its opening and closing rules, and the indent every line inside it carries |
| `chk:*sum-close*` | `"\n--- End of checklist ---\n"` | The summary's own furniture: its opening and closing rules, and the indent every line inside it carries |
| `chk:*sum-indent*` | `"  "` | The summary's own furniture: its opening and closing rules, and the indent every line inside it carries |

**What a typed answer may say**

| Global | Default | Meaning |
| --- | --- | --- |
| `chk:*back-words*` | `'("B" "BACK" "U" "UNDO")` | A getstring prompt cannot take initget keywords, so "go back a step" has to be typed like a note. These are the words that mean it, matched case-blind and whole; add a synonym and every typed prompt takes it. (The keyword prompts get Back and Undo from initget instead, which is a separate list by necessity.) |
## Assumptions

* The flowchart's questions, keyword sets and notes are fixed in the
  file -- there are no tunable globals. Changing the chart means
  editing the `chk:` stage lists in `ccprecheck.lsp`.
* Output is command-line text only; nothing is placed in the drawing,
  written to disk, or remembered between runs.

## Notes & limitations

* Because the command touches no drawing state, cancelling with Esc
  mid-walk loses only the answers collected so far -- there is nothing
  to restore and no undo group (and no `*error*` handler, a known
  structure gap listed in `STANDARDS.md` section 7.4).
* The summary is printed, not returned: copy it off the text screen
  (F2) if it needs to go anywhere.
* The companion checklist for liner drawings themselves is `LINCHECK`
  (`lisp/lincheck/`), shipped alongside this walker.

## Tests

`python3 tests/test_ccprecheck.py` drives the real flowchart
end-to-end in the repo's AutoLISP VM: straight runs down several
branches, Back-stress (backing out of a sub-branch into the question
that opened it, changing an answer to re-route the walk) and the
summary rollback that goes with it -- including asserting exact report
lines, so a wording change here fails loudly.
`CALOFIN_LISP_ROOT=shared python3 tests/test_ccprecheck.py` reruns it
against the grouped build.
