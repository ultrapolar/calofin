# AUTOBEAD -- bead selected pool lines toward a clicked side (AutoLISP / AutoCAD 2018+)

Draws the bead line -- a fixed 2" offset from the pool edge -- for
everything you select in one go, on the `Bead Track` layer. You select
the pool lines, click the side the bead goes on, and AUTOBEAD does the
joining, offsetting and corner-resolving; your original geometry is
never modified.

## What it does

1. **Select** LINEs, ARCs and polylines on any `POOL*` layer (the
   selection filter ignores everything else, so a window select cannot
   pick up dimensions, text or hatch).
2. **Click the side to bead toward.** One click sets the direction for
   the whole selection, and it is also the direction the bead is
   heading -- step clicks (below) find their breakline by looking this
   way. `Back` at this prompt re-opens the selection.
3. The selection is **copied in place** (the originals are never
   touched), the copies are joined into continuous chains, and each
   chain is offset 2" toward the click using AutoCAD's native offset
   engine, so corners resolve automatically:
   - convex (outside) corners have the excess trimmed,
   - concave (inside) corners are extended to meet,
   - arc / radius corners offset as true concentric arcs.
4. **Step lines** -- selected lines that cross the pool, touching
   walls at both ends -- are recognized automatically and always bead
   full length.
5. **The side-wall question**:
   `Are the side walls beaded? [Yes/No/Back] <No>`.
   Answer `No` (or Enter) and every selected wall beads full length.
   Answer `Yes` and you click each step (tread) that has beaded side
   walls; each click assumes its breakline -- the next step line from
   the click in the direction the bead is heading. The wall bead is
   cut flush at that line, kept on the clicked side, and removed
   everywhere else. Step-face beads always draw either way.
6. A **report** prints on every run: source layers, chain split
   (wall vs step), which treads were honored, offset asked vs the
   offset actually measured back off the finished bead, and how many
   bead objects landed on the output layer.

The whole run is one undo group -- a single `U` removes every bead.
Esc mid-run cleans up the temporary chains and restores `OSMODE`,
`PEDITACCEPT` and `CMDECHO`.

## Install & run

1. In AutoCAD run `APPLOAD`, browse to `AUTOBEAD.lsp`, and load it
   (add it to the *Startup Suite* to have it every session). The
   shared build (`shared/LAZPASS.lsp`) carries it too.
2. Run one of:

| Command | What it does |
| --- | --- |
| `AUTOBEAD` | Bead the selected pool lines |
| `TUTORIALAUTOBEAD` | Guided walkthrough -- `[Read/Demo/Both] <Read>`: a written rundown of every step and check, a live demo on a sample pool it draws for you, or both |
| `AUTOBEADVER` | Print the loaded version and the current settings |

## Tunables

At the top of `AUTOBEAD.lsp` (the `AUTOBEAD SETTINGS` block):

| Variable | Default | Meaning |
| --- | --- | --- |
| `*autobead-offset*` | `2.0` | Bead offset in drawing units (2 = 2") |
| `*autobead-layer*` | `"Bead Track"` | Output layer (created if missing; thawed/unlocked if not) |
| `*autobead-filter*` | `"POOL*"` | Layer wildcard the selection is limited to |
| `*autobead-fuzz*` | `0.001` | Endpoint tolerance when joining the copies into chains |

## Notes & limitations

* A step line is recognized when **both** of its endpoints land
  mid-span on other selected chains -- a step whose end stops short of
  the wall is counted as a wall and beads full length. The report's
  `joined chains (wall, step)` line is where to check the split.
* A clicked step whose ray toward the direction click meets no step
  line is counted and ignored (step lines get 6" of slop past their
  drawn ends). The bead then survives everywhere on that wall.
* Every copy is verified to have landed exactly on top of its
  original; if any drifted, the run aborts and draws nothing rather
  than leave geometry in the wrong place. A copy that fails outright
  usually means a locked source layer.
* Chains the offset engine rejects are counted in the report instead
  of failing silently -- clicking farther from the pool line usually
  fixes it.
* The tutorial demo's cleanup (`Erase the demo pool and its bead?
  [Yes/No] <Yes>`) erases **everything on the bead layer**, not just
  the demo's own bead -- run it in a drawing without real beads, or
  answer `No` and erase by hand.
* Requires the Visual LISP engine, which ships with full AutoCAD.
  AutoCAD LT has no LISP engine and cannot run this file.

## Tests

`python3 tests/test_autobead.py` runs AUTOBEAD in the repo's AutoLISP
VM. The VM does not model OFFSET, PEDIT or the in-place copy, so no
run can bead anything there -- the suite is about the two exits that
matter for the rest of the session: the run that finds nothing to do
and the run that dies mid-build both put OSMODE, CMDECHO and
PEDITACCEPT back, close the one undo group, and take the pushed error
mode off the stack (until v1.4 a clean run left it stacked, which
refuses `command-s` inside every later tool's handler). Back at the
direction click, Esc there, and the tutorial's written route are
covered too. `CALOFIN_LISP_ROOT=shared` reruns it against the grouped
twin, and `python3 tests/test_shared.py` still loads it with
everything else. The step routines' hand-off *to* AUTOBEAD --
the geometry and clicked treads `CORNERSTP`/`HEMISTEP`/`NORMIESTEP`
pass it -- is covered from their side by
`tests/test_cornerstp_geometry.py`.
