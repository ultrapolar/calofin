# calofin changelog

Per-tool version banners (`POOL 082726 REV17`, `DIMCHECK v1.4`, ...) say
what changed in one file and drive its `releases/` twin. This file says
which set of them shipped together. The release name lives in
`RELEASE` at the top of `tools/build_shared_bundle.py`, so
`shared/LAZPASS.lsp` announces it on load and cannot drift from it.

## v3.3 -- 2026-09-02

Two commands the trunk had never seen, brought over from the one branch
that shares no history with it. The constellation branch was written
against a base this tree diverged from 222 commits ago, so nothing here
was cherry-picked: the files were taken one by one and fitted to the
trunk's tooling, which is what the mirror map, the loader manifest, the
panel roster and the derived counts all had to be told about.

### Added

- **`CONSTELLATION`** (`lisp/constellation/`, v1.3) places labelled
  survey points when the sheet gives only the distances BETWEEN them and
  never says where any of them is -- the one survey shape no other
  importer here can read. Stress-majorization sweeps find the answer and
  damped Gauss-Newton lands on it exactly, so a set of tape readings
  that cannot all be true still gets the layout that misses by least,
  and the report names the single dim worth re-measuring instead of
  starring nine innocent ones. Arcs, a self-crossing warning, and a
  fix-and-redraw loop, because a number typed wrong is invisible on the
  chart and obvious on the drawing.
- **`TYLERDRONESUITE`** (`lisp/tydrn/`, TYDRN v1.5) runs the whole drone
  trace in one: `TYDRN`, then `PADDLE`, then the shop's own `CDIM`, in
  the order the work has to happen in. One highlight is carried through
  every stage and grows by what each stage draws; each stage keeps its
  own undo group, so a stage that went well is not undone to get at one
  that did not; the calofin stages are checked before any of them runs.

### Fixed on the way in

- **`CONSTELLATION`'s own copies of two library helpers were behind the
  library.** `cst:syssave` skipped the whole save when a snapshot was
  already pending -- the defect v3.1 fixed in `cal:syssave` -- and
  `cst:undobegin` opened its group without the `UNDOCTL` guard, so a
  `_Begin` in a drawing with UNDO off would have errored out of the
  command. Both are the library bodies now, which is what lets the
  mirror map swap all 28 helpers away and leave the twin a rename.
- **`TYLERDRONESUITE` installed its handler by swapping the global
  `*error*`** through a pair of globals, and held PICKFIRST in one of
  them -- the class rule 1b and `handler-free-var` were added to reject
  in v3.1 and v3.2. `*error*` and the saved PICKFIRST are locals of the
  command now. Inside a stage the stage's own handler is still the one
  AutoCAD calls, which is why each stage cleans up after itself; the
  README says so where it used to promise more.

### Checks and tests

- `tests/test_constellation.py` (36 assertions) and
  `tests/test_tydrn_suite.py` run at both tiers; `CONSTELLATION` joins
  the cancel sweep by construction, and `TYLERDRONESUITE` is named in
  its `NO_PROMPT` roster with the reason -- its pre-flight check runs
  before its first question.
- The VM seeds `PICKFIRST` at AutoCAD's own default of 1, so a test that
  watches it come back has to turn it off first to prove anything.

## v3.2 -- 2026-09-02

The second stability pass. It reconciled the branches first, then closed
the classes of defect that only show up in the NEXT command a drafter
runs, and left the tree able to prove every one of them stays closed.

### Branches

- Four branches carried work the trunk had never seen -- LAZPANEL's Find
  page, OASIS's top-right bulge bound to the top wall, POOL's rectangle
  corner questions and its grecian taped-face defaults -- and each was
  ported onto the trunk by cherry-pick with its tiers regenerated. The
  POOLDEMO sample sheet was found calling `pool:muttend` with ten
  arguments where the ported commit wanted twelve; only a test noticed.
- `.claude/hooks/session-start.sh` puts a session on the trunk: a clean
  tree elsewhere is switched, a dirty one or a branch carrying unmerged
  commits stops the session with the commands to land them. CLAUDE.md
  carries the real count of historical branches (some sixty) and the
  end-of-session push that keeps the trunk in step.

### Fixed

- **`LAZPANEL v3.4` stopped re-installing itself on every drawing
  open.** With the build in the Startup Suite, every drawing paid two
  icon writes into the first support-path folder and a walk of the CUI.
  The button work is marked done on the blackboard, the one namespace
  every document shares, and icons already on disk are left alone.
- **Five tools left AutoCAD's error mode stacked after every clean
  run** -- `XFTCONV`, `PERPPTS`, `CPERPPTS`, `AUTOBEAD` (and so the
  three step routines that bead) and `OASIS` pushed it for their handler
  and popped it only from the handler. A stacked mode refuses `command-s`
  inside every later handler, so the next tool's Esc left its undo group
  open without a word. Each pops on every exit now, as POOL always did.
- **Four tools kept their undo-group flag in a global** shared with
  their demo and tutorial -- `POOL`, `SPA`, `POOLSIDE`, `SPACHECK` -- so
  a run that died between its last dim and the close had the next
  command's handler close a group it never opened. The flag is a local
  of the command that opened the group, and the grouped build swaps the
  helper pairs for `cal:undobegin` / `cal:undoend`.
- **Handlers that restored less than the run changed.** The step
  routines put CLAYER back (an Esc mid-dimension left the drafter on
  DIMENSION); the check family's entity cleanup goes through the catch so
  a throw can no longer skip the undo close; the three RESCUE commands,
  TUTORIALCOVERCHECKCLEAN and TUTORIALPADDLE gained the handler and the
  one undo group they never had; LAZTXT and LAZPIN unload their dialog
  from a handler and every dialog file deletes its temp `.dcl` when
  `load_dialog` refuses it; TUTORIALCOVERCHECK holds ATTDIA, ATTREQ and
  FILEDIA itself; AUTOBEAD's command gained a cancel-aware handler.
- **The multi-file loader asked its one-time question on every drawing**
  on a machine whose HKCU is read-only: `vl-registry-write` answers a
  denial with nil, not an error. The answer is kept in the profile
  (`setenv`) as well.

### The checks got stricter

- `check_lisp`: a pushed error mode must be popped outside the handler
  (rule 1c); an undo group opened in a defun is closed on its success
  path and from its handler (rule 5).
- `check_scope`: `handler-free-var` names a variable a handler reads
  that is neither its own nor a local of its command.
- `check_registry`: a test census -- every command is invoked by a suite
  or excused in `UNTESTED` with the reason, and an excused command a
  suite catches up with fails the check.
- The bundle verifies every `cal:` helper the tools call against the
  library at build time and again at load, and clears the build flag it
  set so a later solo library load still warns. `tests/test_shared.py`
  pins the loader's order.
- The VM counts undo groups and the error mode, refuses to return from
  a command that left either behind, runs `prompt` output through the
  same log as `princ`, seeds every system variable the tree touches at
  AutoCAD's default and answers an unknown one with nil. New suites:
  `test_autobead.py`, `test_cancel_paths.py` (every headline command
  cancelled at its first prompt), `test_loader.py`.

## v3.1 -- 2026-09-01

A stability pass over the one-file build. Nothing new to type; what was
there fails less, and two of the ways it could have failed the NEXT tool
in the session are closed.

### Fixed

- **`DRONE v1.3` / `TYDRN v1.3` no longer install their error handler by
  swapping the global `*error*`.** Both saved the global, set their own,
  and put it back on each exit -- so one exit missed (a throw inside the
  handler's own `EndUndoMark`, say) left that tool's cleanup live for
  every command run afterwards in the loaded-together build: closing an
  undo mark it never opened, re-locking layers it never touched. The
  handler is local to the command now, as the skeleton in STANDARDS 5
  has always said, sees the run's state through dynamic scope rather
  than through `*drone-doc*` / `*drone-unlocked*` globals, and closes
  only a mark the run actually opened.
- **`PADDLE v1.9`'s handler closed an undo mark it might never have
  opened.** An Esc at the perimeter prompt comes before
  `StartUndoMark`; the handler's unconditional `EndUndoMark` then threw
  from inside `*error*`, where nothing catches it. It tracks the mark now
  and closes it through `vl-catch-all-apply`.
- **`CALOFIN-LIB v1.5`: the shared sysvar snapshot merges instead of
  skipping.** Every tool in the grouped build shares `cal:*sysold*`, and
  the tools list different variables. After a run cut short, the next
  tool's `cal:syssave` used to save NOTHING -- so a variable the dead run
  never listed (`CLAYER`, `CMDECHO`) was changed and never put back. A
  variable already pending keeps its true value exactly as before; one
  the snapshot lacks is added. `tests/test_calofin_lib.py` pins both
  halves.

### The checks got stricter

- `check_lisp` fails a `(defun *error* ...)` or `(setq *error* ...)`
  whose enclosing command does not declare `*error*` local, and a
  handler at top level. Zero findings tree-wide once the two above were
  fixed; the deprecated acady matcher keeps its swap idiom.
- The VM can now run `*error*` (`vm.handle_errors = True`): a failure
  outside `vl-catch-all-apply` reaches the handler the failing code can
  see, with every frame still live, and the command is then aborted the
  way AutoCAD aborts it. It also carries just enough ActiveX -- the
  document, its undo marks, the layer collection with `Lock`, and the
  entity properties the cleanup tools put -- for `DRONE` and `TYDRN` to
  run under test for the first time: `tests/test_drone.py` drives the
  happy path, an error mid-run and an Esc at the prompt, at both tiers.

## v3.0 -- 2026-08-27

The release that made the whole toolset drivable from a filled-in chart,
and made the tree able to prove it is in step with itself.

### Zero-install GUI: fill the chart in, press Insert

- **`LAZSPA`** (new) -- `LAZFORM`'s argument applied to `SPA`: three
  charts (Rectangle, Octagon, Round), the boxes wedged into the
  dimension rows, and the spa drawn from what you typed.
- **`LAZSTEP`** (new) -- say how many steps, and the drawing is built
  for that count: N treads with their widths, N risers and N+1 drops,
  every dimension carrying its letter until you type over it.
- **`LAZFORM v2.5`** -- one authority decides what is greyed, and the
  letters it was missing are there.
- All three are plain DCL the file writes for itself, so there is no
  DLL to `NETLOAD` and no artwork to ship.

### The routines take answers from a form

`POOL`, `SPA` and the three step routines each carry an answer store the
ask helpers read before they prompt, so a filled-in chart drives the run
and a half-filled one shortens it. One contract everywhere: a key that
is absent is asked for as usual, `(key . nil)` answers NA without a
prompt, `(key . 84.0)` answers the measurement -- and **an answer is
removed as it is used**, which is what stops `Back` deadlocking on a
question the form already answered.

- `pool:*form*`, `spa:*form*`, `*cs-form*` / `*hs-form*` / `*ns-form*`,
  each with its own `run-with-answers`, cleared on both exits.
- POOL's gate questions and the step routines' count take form answers
  too -- the count is a question the step tools never had before.
- The VB palette caught up with what `SPA` actually asks, and its
  catalog with the tree.

### FITABHD fits the oasis pools too

- **`FITABHD v2.0`** -- the type list gains `OAsis`, and the survey of a
  continuous-tangent pool is fitted with **`OASIS`'s own ring solver**,
  carried into `FITABHD.lsp` under its own prefix so the two files
  cannot draw different pools from the same numbers.
  `test_oasis_ring_is_oasis_lsp_s_own` runs both through the VM and
  compares them element by element.
- Step 2, which has no corners to ask about on an oasis, asks which of
  OASIS's five families it is instead -- in OASIS's own words
  (`Center/TopRight/CLoud/Kidney/NXTcloud`). Steps 5 and 6 are skipped
  the way they are for a Round pool: neither shape has a wall to swing
  or to bow.
- **Everything else about the shape is measured.** An oasis has no walls
  for the edge vote to find a rotation from, so the frame is swept right
  round the pool and the best few placements fitted properly; the
  envelope then falls out of the bounding box, because every bulge is
  tangent to a bound.
- **A cloud's flat bottom is found, not declared.** Every joiner is
  carried as `U = h / (h + R)` rather than as a radius, so the straight
  run -- the reverse arc with an infinite radius -- is just `U = 0`,
  with no special case at either end. The report names the shape
  `straight-bottom cloud` or `rounded-bottom cloud` from what came out.
  Which way a kidney was given is settled the same way: both
  parameterisations are fitted and the points choose, with the freer one
  held to the both-ends evidence margin.
- The report prints every fitted radius under OASIS's own question
  wording, and all of them snap under the *feature* rule -- a measured
  radius, never a design dimension.
- An oasis wants at least 12 survey points, and its hopper is square to
  the envelope rather than to a wall, so all four bounds are offered as
  ends.

### Fixed

- **Output layers are repaired, not just created.** `POOL`, `SPA` and
  the four check tools drew onto a frozen or switched-off layer and
  reported success while producing nothing visible.
- **`LITELINFINSCAN` silently dropped the steps rule** -- a sheet with an
  obvious staircase reported "no step patterns detected" and lost its
  rise-vs-wall-height comparison. The one a drafter would have been
  burned by.
- **`Back` un-counted a defpoint move it could not undo**, so the report
  claimed "points adjusted: 0" over a drawing whose points had moved.
- **Scan findings never rendered red**, on the report whose whole job is
  to make problems findable.
- One canonical cancel test repo-wide (a `*break,` typo had already been
  copy-pasted into a second file), and every living tool now has an
  `*error*` handler that puts back what it changed -- including
  `AUTOBEAD`, which closed an undo group it might never have opened, and
  `PADDLE`, whose block import could leave `CMDECHO` and `ATTREQ`
  clobbered.
- `SPA` speaks the canonical `Square / Radius / Cut / NotGiven`
  treatment, with the sheet-legend words (`90`, `Diagonal`) still
  accepted and normalised -- so `LAZSPA`'s dropdown keeps the drafter's
  vocabulary while the routine keeps the standard's.
- Brackets a click can actually send, one tutorial selector, one pause
  spelling, `ROUnd` everywhere.

### The tree can now prove it is in step

- `mirror_shared.py`, `release_lisp.py` and `build_shared_bundle.py`
  each grew a `--check` mode, and `check_standards.py` runs all three:
  a hand-edited generated twin, an orphaned release or a stale bundle
  body now fails a check instead of shipping.
- `check_lisp.py` exited 0 on the unbalanced parens it advertised;
  `check_scope.py` had no exit code at all. Both gate now, with their
  false-positive classes fixed and a baseline so new findings surface.
- **47 of the 51 grouped twins are generated** (was 14), which is what
  stops the drift class that put two defects into `LAZPASS.lsp`.
- `tools/run_tests.py` + a `Makefile`: `make check`, `make test`,
  `make parity`. The canonical test list was prose in four documents and
  two files had already fallen out of it; the runner globs the directory.
- End-to-end tests for `DIMCHECK`, `LINFINCHECK` and `COVERCHECK` -- the
  three largest tools that had none -- plus `LAZSPA`, `LAZSTEP` and the
  step form suites.
- Nothing is expected to fail on a clean checkout: `EXPECTED_FAILURES`
  in `tools/run_tests.py` is empty, and a test that starts passing there
  fails the run until its entry goes.

### Deliberately deferred

Recorded in `STANDARDS.md` section 8 with reasons rather than left as
silent gaps: the uppercase `.LSP` filenames, SPA's spillaway corner-pick
keywords, `cal:askkw`'s signature (pinned by every generated twin at
once), the `prefix-` naming styles, and the VB palette's button catalog
(it cannot be compiled or tested here).
