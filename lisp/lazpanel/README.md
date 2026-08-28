# LAZPANEL -- clickable button panel that launches the calofin tools (AutoLISP / AutoCAD 2018+)

## What it does

`LAZPANEL` opens a dialog with one button per headline calofin command
-- 57 of them across 128 buttons, because the pages come in two kinds
and a tool that serves two jobs sits on both.

**The job pages** are what you are actually doing this hour, and each
is laid out in **columns that follow the work**: lay the shape out, tie
the points, build the steps, dimension and check. A job is not a flat
list of two dozen tools -- it is a few short lists in the order you
reach for them.

**Pool** -- 4 columns, in the order the work runs:

| **Shape** | **Points** | **Steps** | **Dims & check** |
| --- | --- | --- | --- |
| `POOL` | `ABFIND` | `CORNERSTP` | `AUTODIM` |
| `LAZFORM` | `ABMOVE` | `HEMISTEP` | `LINFINCHECK` |
| `LAZTXT` | `CDCREATE` | `NORMIESTEP` | `LINFINSCAN` |
| `OASIS` | `CDCALLOUT` | `AUTOBEAD` | `LITELINFINSCAN` |
| `ABHD` | `BPCALLOUT` | `PERPPTS` | `DIMCHECK` |
| `ADAB` |  | `CPERPPTS` | `DIMSCAN` |
| `FITABHD` |  |  |  |
| `XFTCONV` |  |  |  |

**Cover** -- 3 columns, in the order the work runs:

| **Shape** | **Points** | **Pads, dims & check** |
| --- | --- | --- |
| `POOLCOVER` | `ABFIND` | `PADDLE` |
| `LAZFORMCOVER` | `ABMOVE` | `AUTODIM` |
| `OASIS` | `CDCREATE` | `COVERCHECK` |
| `ABHDCOVER` | `CDCALLOUT` | `COVERSCAN` |
| `FITABHDCOVER` | `BPCALLOUT` | `LITECOVERSCAN` |
| `STOCKCOVER` |  | `DIMCHECK` |
| `CUSTBLOCK` |  | `DIMSCAN` |
| `XFTCONV` |  |  |

`Spa` and `Rest` are a single column each:

| Job | Buttons |
| --- | --- |
| Spa | `SPA`, `CUSTBLOCK`, `AUTODIM`, `SPACHECK`, `SPACHECKSCAN`, `LITESPACHECKSCAN`, `DIMCHECK`, `DIMSCAN` |
| Rest | `POOLDEMO`, `CABHD`, `LHD`, `SMARTFILLET`, `WCALST`, `ABCDEF`, `ALTABCDEF`, `XYPLOT`, `DRONE`, `TYDRN`, `AUTODIMSIDEPOV`, `STAIRDIM`, `FLOORDIM`, `DIMCONTEND`, `CHECK`, `DIMARCCHECK`, `ABCURCHECK`, `ABCURCHECKSCAN`, `LINCHECK`, `LINTXTCHK`, `CCPRECHECK` |

**A page laid out in columns shows the command name alone**; the column
heading carries the meaning instead of a caption on every button. That
is a width limit, not a preference: a button reading
`CDCALLOUT  -  Point-to-point cross dims` is about 39 character cells,
four of those abreast is 147, and DCL will not scroll a dialog wider
than the screen -- it simply fails to open. Names alone put the widest
page at about 64. Single-column pages have the room and keep the
caption, which is why the category pages below are the place to go to
find out what a tool *is*, and the job pages are the place to go when
you already know.

**The category pages** are the roster filed by what each tool *is*
rather than when you reach for it -- the four the panel has always had,
and the same four group names the VB palette uses. Everything is on
them, so a tool you cannot place in a job is still one tab away.

| Group | Buttons |
| --- | --- |
| Layout | LAZFORM, LAZTXT, LAZFORMCOVER, SPA, POOL, POOLCOVER, POOLDEMO, OASIS, FITABHD, FITABHDCOVER, ABHD, ABHDCOVER, ADAB, CABHD, LHD, PADDLE, AUTOBEAD, CORNERSTP, HEMISTEP, NORMIESTEP, SMARTFILLET, STOCKCOVER, WCALST, CUSTBLOCK |
| Points | ABCDEF, ALTABCDEF, XYPLOT, ABFIND, ABMOVE, PERPPTS, CPERPPTS, XFTCONV, DRONE, TYDRN |
| Dimensions | AUTODIM, AUTODIMSIDEPOV, STAIRDIM, FLOORDIM, DIMCONTEND, CDCREATE, CDCALLOUT, BPCALLOUT |
| Checking | CHECK, DIMARCCHECK, DIMCHECK, DIMSCAN, ABCURCHECK, ABCURCHECKSCAN, LINCHECK, LINFINCHECK, LINFINSCAN, LITELINFINSCAN, COVERCHECK, COVERSCAN, LITECOVERSCAN, SPACHECK, SPACHECKSCAN, LITESPACHECKSCAN, LINTXTCHK, CCPRECHECK |

`AUTODIM` and `DIMCHECK`/`DIMSCAN` are on all three jobs, because every
job ends the same way; 10 commands are shared between jobs in total.

**The Cover page runs cover twins, not the plain tools.** A cover sheet
records the perimeter and nothing below it, so `POOLCOVER`,
`LAZFORMCOVER`, `ABHDCOVER` and `FITABHDCOVER` answer their tool's
pool-bottom question No before it is asked -- and with it goes the
whole depth interrogation behind it (POOL's C, C2 and D, the hopper
type and its corner method; ABHD's breaks, hopper offsets and slope
lines). They are commands of their own rather than a mode the panel
switches on, so a button still runs exactly the command named on it and
typing `POOLCOVER` does what clicking it does. Each sets a flag its
tool clears on both exits, so a cancelled cover run cannot leave the
next pool silently bottomless. `OASIS` is on the Cover page unchanged
-- it has no such gate.

**Rest is not a hand-kept list.** It is every command Pool, Cover and
Spa do not name, and the test recomputes that complement from the tree
-- so a tool added to the panel and forgotten on the job pages shows up
as a Rest omission instead of quietly falling out of the workflow.

**`CUSTBLOCK` is on Cover and Spa.** A custom block drawn from three
typed sizes is what you reach for on those two sheets -- the custom
answer where `STOCKCOVER` is the stock one, and the block a spa sheet
needs beside the spa. It stays off Pool, which is why it is not
"everything the other jobs leave over" and so not on Rest.

**The AB checks are on Rest and on no other job.** `ABCURCHECK` and
`ABCURCHECKSCAN` read the A/B survey ties themselves -- the tape rather
than the pool -- so they are bench work over the numbers, not a step in
laying out a pool, a cover or a spa. Any further `AB*` check joins them
there and stays off Pool, Cover and Spa; the test derives the rule from
the roster, so a new one dropped onto Pool out of habit fails the suite.
The **Checking** category page still carries them, because that page
answers what a tool *is* rather than what you are doing this hour.

A **tab strip** across the top switches pages: two labelled boxed rows,
`Job` (Pool / Cover / Spa / Rest) and `Or by category` (Layout / Points
/ Dimensions / Checking) -- they are not eight equal things, and the
labels say so. That is both what they mean and what keeps
the strip narrow -- eight tabs on one row run about 94 character cells,
and DCL will not scroll a dialog wider than the screen. Two rows put
the widest at 54.

The pages ARE `lzp:*groups*` and the strip layout is `lzp:*rows*` --
re-ordering the tools, re-grouping them or moving a tab to the other
row is an edit to those two tables and nothing else, and the test
asserts they name exactly the same groups so neither can drift. The
status line counts tools rather than buttons (`lzp:commands` folds the
repeats), so it still reports the whole 57 and not 128. The panel
reopens where you left it rather than jumping back to the middle of the
screen.

**The panel reopens itself.** Click a button, the panel closes, the
tool runs to its own end, and the panel comes straight back -- on the
page and at the screen position it was at, with the session re-probed
so a tool loaded meanwhile is no longer greyed. Close is the way out,
and it is the default button. DCL dialogs are modal, so the panel still
has to close while a tool runs; what it no longer needs is you typing
`LAZPANEL` again afterwards.

A tool you cancel with Escape comes back to the panel exactly as a
finished one does. A tool that dies with a hard error does **not** --
its own error handler runs, the panel stays closed, and `LAZPANEL`
brings it back. That is the right way round: the alternative is a panel
bouncing back in front of the error you are trying to read.

**The Pinned row.** Pins are the answer to "I run four of these
fifty-six all day": ticked tools sit in a row at the top of *every*
page, in the order you pinned them, so the ones you actually use stop
being three tabs apart. `Pin...` on the row opens the editor -- every
tool as a toggle, three columns -- and so does the `LAZPIN` command.
The list is remembered under
`HKEY_CURRENT_USER\Software\Calofin\LazPanel`, beside the key the
multi-file loader already uses, so it survives the session. Cancel in
the editor re-reads the stored list rather than unwinding the ticks one
by one. A pin naming a tool that no longer exists is dropped on read,
so an old pin cannot put a dead button on screen.

Pins wrap onto as many rows as they need. That is not cosmetic: the
pinned row is on every page and is the one part of the panel you can
make arbitrarily wide, and a DCL dialog that is too wide does not clip
-- it fails to open. Eight of the longest tool names would be a
150-cell row; packed, they are two rows of 83 or less, and the test
holds that line.

Clicking a button closes the panel and runs that command exactly as if
its name had been typed -- the panel adds nothing in front of a tool and
nothing behind it. A command that is not loaded in this session shows as
a greyed button instead of one that would fail, and the status line
across the top says how many tools the session has. `LAZPANELVER` prints the loaded version, the page count and how many
tools are pinned.

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

**The button is drawn at 32 pixels**, not 16 — the small one is easy to
miss on a crowded screen, and both pictures were already being written,
so AutoCAD simply had to be told which to use. One thing to know before
turning it off again: **AutoCAD's large-button setting is not per
toolbar.** Asking for it here turns it on for every toolbar in the
session — it is the same switch as `Options ▸ Display ▸ "Use large
buttons for Toolbars"`. That is why it is a tunable, and why `LAZBUTTON`
says out loud what it did rather than letting you wonder why the rest of
your toolbars changed:

```
LazPanel button is on screen - drag it anywhere, dock it, click it to open the panel.
  Drawn at 32 pixels.  AutoCAD sizes every toolbar together, so the rest grew
  with it; (setq lzp:*bigbutton* nil) before loading leaves them alone.
```

Thirty-two is the ceiling, not a choice: a toolbar bitmap is 16 or 32,
and `SetBitmaps` takes one of each.

Two details worth knowing, because both were wrong first time round:

- **The bytes travel as base64.** `ADODB.Stream`'s `Write` wants a
  `VT_UI1` byte array and nothing else, and AutoLISP cannot reliably
  make one: `vlax-make-safearray`'s documented type constants stop at
  `vlax-vbVariant`, `VT_UI1` (17) is not among them, and whether a
  given release accepts it anyway is a property of that release. Where
  it is refused, the old fallback built a `vbInteger` (`VT_I2`) array
  and `Write` rejected it outright --

  ```
    written : NO - writing ...lazpanel-16.bmp failed: ADODB.Stream:
    Arguments are of the wrong type, are out of acceptable range, or
    are in conflict with one another.
  ```

  -- which is a blank button rather than a wrong one, and was reported
  from the field. (On the machine that reported it `VT_UI1` turned out
  to be *accepted*, and `Write` refused the array anyway -- so the
  undocumented type constant was never the whole story.) The way round it is to stop building a byte array in
  AutoLISP at all: base64 is a pure-ASCII encoding of arbitrary bytes,
  so the icon can be carried in an ordinary string, and MSXML's
  `bin.base64` element turns that string back into a real byte array
  on the other side. Both components ship with Windows, and the
  toolbar already needs COM. The safearray spellings stay as
  fallbacks, so a machine where they do work is no worse off.
- **Every MSXML version is tried all the way through, not just far
  enough to create.** MSXML 6.0 creates perfectly happily and then
  refuses `dataType`, because XDR schema support -- of which
  `bin.base64` is part -- was removed in 6.0. A probe that stops at
  "did the object appear?" therefore picks 6.0, dies on the next line
  and falls back without a word. That is exactly what the second field
  report caught: `array : VT_UI1 safearray`, meaning the MSXML route
  had returned nothing while a working version sat three entries
  further down the list. `MSXML2.DOMDocument.3.0` and the
  version-independent `Microsoft.XMLDOM` both carry XDR and come
  first; 6.0 sits at the back where its refusal costs one failed
  attempt and nothing else. `LAZICON` names the version that carried
  the bytes -- `bin.base64 via MSXML2.DOMDocument.3.0` -- rather than
  a generic label that says nothing about which of four routes worked.
- **When no array works at all, `certutil` does.** Every failure
  reported from the field has been about handing AutoLISP's idea of an
  array to COM: `VT_UI1` accepted and `Write` refusing it anyway,
  wrapped in a variant or not, with MSXML coming back empty. So the
  last route has no array in it. `certutil` has shipped with Windows
  since Vista and decodes base64 to binary in one command, so
  LAZPANEL writes the base64 as **ordinary text** with `write-line` --
  the one thing AutoLISP has never had trouble with -- and Windows
  does the decoding. Nothing crosses the COM boundary but a command
  line. It runs only when the stream route has failed, because it
  costs a process and a scratch file (which it deletes).
- **`Write` has two spellings.** It takes a `Variant`, and whether a
  raw safearray marshals into one is another per-release question, so
  a refused plain call is retried wrapped in `vlax-make-variant`
  before giving up. `died at` distinguishes them.
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
re-summon the button, or `LAZPIN` to choose the pinned tools.

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

- **`written : NO`** -- the bytes never reached the disk. Three lines
  now say why: `array` names the route that produced (or failed to
  produce) the byte array, `died at` names the COM call that refused,
  and `written` carries the message itself. One report pins it. The usual cause is the byte array: writing binary
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
