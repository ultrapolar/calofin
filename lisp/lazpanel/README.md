# LAZPANEL -- clickable button panel that launches the calofin tools (AutoLISP / AutoCAD 2018+)

## What it does

`LAZPANEL` opens a dialog with one button per headline calofin command
-- 51 of them across 119 buttons, because the pages come in two kinds
and a tool that serves two jobs sits on both.

**The job pages** are what you are actually doing this hour, and each
runs in the order the work runs: lay the shape out, tie the points,
build the steps, then dimension and check.

| Job | Buttons |
| --- | --- |
| Pool | POOL, LAZFORM, OASIS, ABHD, ADAB, FITABHD, XFTCONV / ABFIND, ABMOVE, CDCREATE, CDCALLOUT, BPCALLOUT / CORNERSTP, HEMISTEP, NORMIESTEP, AUTOBEAD, PERPPTS, CPERPPTS / AUTODIM, LINFINCHECK, LINFINSCAN, LITELINFINSCAN, DIMCHECK, DIMSCAN |
| Cover | POOL, LAZFORM, OASIS, ABHD, FITABHD, STOCKCOVER, XFTCONV / ABFIND, ABMOVE, CDCREATE, CDCALLOUT, BPCALLOUT / PADDLE, AUTODIM, COVERCHECK, COVERSCAN, LITECOVERSCAN, DIMCHECK, DIMSCAN |
| Spa | SPA, AUTODIM, SPACHECK, SPACHECKSCAN, LITESPACHECKSCAN, DIMCHECK, DIMSCAN |
| Rest | POOLDEMO, CABHD, LHD, WCALST, ABCDEF, ALTABCDEF, XYPLOT, DRONE, TYDRN, AUTODIMSIDEPOV, STAIRDIM, FLOORDIM, DIMCONTEND, CHECK, DIMARCCHECK, LINCHECK, LINTXTCHK, CCPRECHECK |

**The category pages** are the roster filed by what each tool *is*
rather than when you reach for it -- the four the panel has always had,
and the same four group names the VB palette uses. Everything is on
them, so a tool you cannot place in a job is still one tab away.

| Group | Buttons |
| --- | --- |
| Layout | LAZFORM, SPA, POOL, POOLDEMO, OASIS, FITABHD, ABHD, ADAB, CABHD, LHD, PADDLE, AUTOBEAD, CORNERSTP, HEMISTEP, NORMIESTEP, STOCKCOVER, WCALST |
| Points | ABCDEF, ALTABCDEF, XYPLOT, ABFIND, ABMOVE, PERPPTS, CPERPPTS, XFTCONV, DRONE, TYDRN |
| Dimensions | AUTODIM, AUTODIMSIDEPOV, STAIRDIM, FLOORDIM, DIMCONTEND, CDCREATE, CDCALLOUT, BPCALLOUT |
| Checking | CHECK, DIMARCCHECK, DIMCHECK, DIMSCAN, LINCHECK, LINFINCHECK, LINFINSCAN, LITELINFINSCAN, COVERCHECK, COVERSCAN, LITECOVERSCAN, SPACHECK, SPACHECKSCAN, LITESPACHECKSCAN, LINTXTCHK, CCPRECHECK |

`AUTODIM` and `DIMCHECK`/`DIMSCAN` are on all three jobs, because every
job ends the same way; 14 commands are shared between jobs in total.

**Rest is not a hand-kept list.** It is every command Pool, Cover and
Spa do not name, and the test recomputes that complement from the tree
-- so a tool added to the panel and forgotten on the job pages shows up
as a Rest omission instead of quietly falling out of the workflow.

A **tab strip** across the top switches pages: jobs on the first row,
categories on the second. That is both what they mean and what keeps
the strip narrow -- eight tabs on one row run about 94 character cells,
and DCL will not scroll a dialog wider than the screen. Two rows put
the widest at 54.

The pages ARE `lzp:*groups*` and the strip layout is `lzp:*rows*` --
re-ordering the tools, re-grouping them or moving a tab to the other
row is an edit to those two tables and nothing else, and the test
asserts they name exactly the same groups so neither can drift. The
status line counts tools rather than buttons (`lzp:commands` folds the
repeats), so it still reports the whole 51 and not 119. The panel
reopens where you left it rather than jumping back to the middle of the
screen.

Clicking a button closes the panel and runs that command exactly as if
its name had been typed -- the panel adds nothing in front of a tool and
nothing behind it. A command that is not loaded in this session shows as
a greyed button instead of one that would fail, and the status line
across the top says how many tools the session has. `LAZPANELVER`
prints the loaded version.

**The screen button.** Loading the file also puts a one-button toolbar
named "LazPanel" on screen -- drag it anywhere or dock it like any
toolbar; clicking it opens the panel. It is created through the
ActiveX menu API (no CUI file to install) when no toolbar of that name
exists yet, and its icon -- an orange hexagon with a corner facing
north -- is generated as 16x16 and 32x32 `.bmp` files, each drawn at
its own resolution rather than the small one doubled, because a
hexagon doubled from 16 pixels keeps the 16-pixel staircase on its
diagonals and those diagonals are the whole shape. If the
toolbar gets closed or lost, `LAZBUTTON` brings it back; a toolbar
that is merely hidden is re-shown rather than duplicated, and one that
you have docked or moved is left where you put it.

Two details worth knowing, because both were wrong first time round:

- **The icon is written through an `ADODB.Stream` in binary mode, not
  with `write-char`.** AutoLISP writes text-mode files and has no NUL
  in its character model at all -- `(chr 0)` is the empty string --
  while a 24-bit BMP header carries 43 NULs before the first pixel.
  There is no arrangement of this format the language's own file
  output could produce. COM is not a new dependency: the toolbar the
  icon goes on is built through the same ActiveX API, so a session
  that cannot reach COM has no button to decorate.
- **The icon files live at a fixed name under `TEMPPREFIX` and are
  rewritten on every load**, because `SetBitmaps` stores the *path*,
  not the picture, and AutoCAD re-reads it whenever the button
  redraws. A toolbar that survives into a later session would
  otherwise be pointing at a swept temp file.

The point of the design is **zero install**: the dialog is plain DCL,
and LAZPANEL.lsp writes its own `.dcl` into the system temp folder each
time the panel opens (and deletes it when the panel closes). There is no
second file to ship, no support-path entry to add, and no DLL to
`NETLOAD` -- unlike the VB.NET palette in `ui/`, which needs its
assembly loaded on every machine.

## Install & run

APPLOAD `LAZPANEL.lsp` on its own, or load `shared/LAZPASS.lsp`, which
carries it along with every tool it lists. The button toolbar appears
on load; type `LAZPANEL` to open the panel directly, or `LAZBUTTON` to
re-summon the button.

## Assumptions

- The system temp folder is writable -- `vl-filename-mktemp` decides
  where the dialog goes, `TEMPPREFIX` where the icons go. If it is not
  writable, the panel reports that it could not write the dialog file
  and leaves the session untouched; the button simply keeps its
  default face.
- The screen button needs the ActiveX menu API (COM). Where it is
  unavailable or the CUI is locked, the button is quietly skipped --
  the panel itself never depends on it.
- Command names on the roster are the headline drafting commands under
  `lisp/`. Satellites stay off the panel on purpose: `TUTORIAL*`
  walkthroughs, `*VER` reporters, `*RESCUE` companions, `-CFG` /
  `-SETUP` partners, `DCE` (DIMCONTEND's alias) and `STOCKLIST`
  (STOCKCOVER's listing companion). The `DD*` drone-height toolset
  stays off as a whole -- eight specialist photo-EXIF commands, not
  part of the drafting flow the panel serves. `LISPLAB` never appears:
  it is held back from the shared build as OMITTED. The deprecated
  acady matcher (`MATCHSTD`, `ACADY-*`) never appears.

## Notes & limitations

- DCL dialogs are modal, so the panel cannot stay docked and open while
  a tool runs the way the VB palette can: click, the panel closes, the
  tool runs, `LAZPANEL` reopens it. The screen button is the shortcut
  for that reopen.
- A toolbar created through the ActiveX API may or may not survive an
  AutoCAD restart, depending on how the main CUI is saved. That is why
  every load re-creates it when it is missing, and re-ices and re-shows
  it when it is not: sessions that load LAZPANEL.lsp or LAZPASS.lsp
  always end up with a visible button carrying a current icon, and one
  that somehow lost it can type `LAZBUTTON`.
- If the button cannot be added to a freshly created toolbar, that
  toolbar is deleted again rather than left behind. An empty "LazPanel"
  would be found by name for ever afterwards, and `LAZBUTTON` would
  report success while putting nothing on screen.
- The panel changes no system variables and draws nothing, so it takes
  no undo group; whatever it launches manages its own.
- The availability probe is the same one the VB palette uses (evaluate
  `C:<NAME>`; unbound symbols are nil), so commands loaded after the
  panel's file was loaded are still picked up, each time it opens.

## When the button comes up blank -- or shows the "?" cloud

The picture is best effort and fails quietly on purpose -- a missing
icon must never stop the panel working. `LAZICON` is the way to find
out why: it walks the same steps out loud and prints where each one
got to.

```
LAZICON: where the button's picture comes from.
  TEMPPREFIX : C:\Users\you\AppData\Local\Temp\
  small      : C:\Users\you\AppData\Local\Temp\lazpanel-16.bmp
  large      : C:\Users\you\AppData\Local\Temp\lazpanel-32.bmp
  written    : yes, as a VT_UI1 array
  on disk    : found
  SetBitmaps : accepted - the button should show it now
```

The **"?" placeholder** is its own story, and the giveaway is that it
means `SetBitmaps` *worked*: the button carries bitmap names, AutoCAD
just cannot load them. The CUI resolves a toolbar bitmap by **name
along the support file search path**, and the temp folder is not on
that path -- so a full temp path can come back as the "?" even though
the file is exactly where the path says. The icons therefore go into
the **first folder of the support path** (the user's own Support
folder) and `SetBitmaps` is handed the bare names, which resolve the
way the CUI wants to resolve them; the temp folder and full paths are
only the fallback when that folder cannot be written. `LAZICON` runs
the CUI's own test -- `findfile` on the name it handed over -- and says
`CANNOT RESOLVE - this is the ? placeholder` when that is the problem.

The two steps most likely to fail, and what they mean:

- **`written : NO`** -- the bytes never reached the disk. The reason is
  printed after it. The usual cause is the byte array: writing binary
  from AutoLISP needs a `VT_UI1` safearray, and `vlax-make-safearray`'s
  documented type constants stop at `vlax-vbVariant`, so whether type
  17 is accepted is a property of the release rather than of this code.
  A second spelling is tried before giving up, and the line says which
  one worked.
- **`SetBitmaps : <error>`** -- the files were written but AutoCAD would
  not take them for the button.

## Tests

```
python3 tests/test_lazpanel.py                          # standalone tier
CALOFIN_LISP_ROOT=shared python3 tests/test_lazpanel.py # grouped tier
```

The test pins the roster to the tree: every headline command defined
under `lisp/` must have a button, held-back commands must not, so a new
tool without a button (or a button whose command does not exist) fails
the suite. It validates the generated DCL with a grammar pass, drives
`c:LAZPANEL` end-to-end in the VM with the dialog surface stubbed
(executing the real button-wiring expression), and checks the toolbar
creation path and both generated bitmaps pixel by pixel -- position,
not just colour count, since a BMP stores its rows bottom-up and an L
is not symmetric.

The stubs go in *before* the file loads, so the load-time toolbar call
is itself under test: delete it and the suite fails rather than
quietly passing.
