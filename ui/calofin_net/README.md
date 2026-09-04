# Calofin palette

A dockable AutoCAD palette for the routines in this repository: find a
tool by name or by what it does, reach for the ones you use, and fill
in a form for `SPA` with the measurements you have, leaving the rest
blank.

## Why VB.NET and not VBA

The form puts text boxes on top of a shape diagram, where the dimension
letters are printed. DCL cannot do that — it packs tiles into rows and
columns with no absolute positioning and no overlap, so a box cannot sit
on an image. VBA *can* position controls freely, but it is a deprecated
per-version separate install, absent on Mac and LT, and `SendCommand`
cannot return a value. VB.NET gives the same freedom on a supported
runtime.

## The one rule

**This assembly contains no drawing logic.** It collects answers and
formats them into a call on `spa:run-with-answers`. Every geometry rule,
default, corner treatment and dimension stays in `SPA.LSP`, unchanged and
unaware a form was involved.

That is not tidiness for its own sake. It keeps a BricsCAD port a
UI-shell rewrite against their source-compatible .NET API rather than a
re-port of ~28,000 lines of Lisp — and it is why the equivalence tests
can prove the form draws what the command line draws.

## Building

Requires the AutoCAD .NET reference assemblies, pulled from NuGet:

```
dotnet build ui/calofin_net/Calofin.vbproj -c Release
```

| AutoCAD | TargetFramework | AutoCAD.NET |
| --- | --- | --- |
| 2021–2024 | `net48` | `24.x` |
| 2025+ | `net8.0-windows` | `25.x` |

`ExcludeAssets="runtime"` on the package reference is deliberate.
Shipping `acmgd.dll` / `acdbmgd.dll` beside the output makes AutoCAD load
a second copy of its own API and fail in ways that look unrelated to this
project.

## The Commands tab

Everything `LAZPANEL` does, on plumbing that does not blink:

- **Find.** Type any part of a command name *or of its caption* and the
  list narrows; the top hit is selected as you type, so a search and
  Enter runs it. The needle is taken **literally** -- `lzp:instr` is
  written out rather than handed to `wcmatch` for exactly this reason,
  and `String.Contains` is the same promise: a `*` you type is a star.
  Searching captions is the point rather than a bonus, because `survey`
  finds `ABHD`, `ABPCHECK` and `ABHDCOVER`, none of which say so in
  their names.
- **Recent and Pinned.** The last five launched, newest first, and
  whatever you pinned -- right-click any button to pin it. A tool
  already pinned is remembered but not *shown* on Recent, or Recent
  fills up with the handful Pinned is already carrying. A row with
  nothing in it is not drawn.
- **Every page of the panel's tab strip**, job pages included:
  `Pool`, `Cover`, `Spa`, `Rest` and the four categories, with their
  columns. The palette used to offer the four categories alone, which
  are the pages answering "what is this tool" rather than "what am I
  doing this hour". It reopens on the page you left it on.

**Pins and recents are LAZPANEL's, not a second set.** `PaletteMemory`
reads and writes `lzp:*pinkey*` -- the same registry key, the same
`Pins` / `Recent` values, the same `;`-joined format, the same cap of
five. Pin `CORNERSTP` on the DCL panel and it is pinned here.
`tests/test_palette_shell.py` holds that seam, and the wording of every
Find message, against `LAZPANEL.lsp` itself.

One behaviour is deliberately opposite on the two halves of this tab,
and both halves are the panel's. On a **page**, a routine this session
has not loaded is greyed -- a dead spot in a grid is visible, and
reaching for it tells you why. On the **Find list** it is listed
instead, marked `(not loaded)`, and Run refuses it with that reason:
a search that silently omits what you searched for reads as the tool
not existing.

## The command catalog is generated

`Generated/CommandCatalog.g.vb` is **not hand-edited**. It is written by
`tools/gen_ui_data.py` from `LAZPANEL`'s own tables --
`lzp:*captions*` for the words on a button, `lzp:*groups*` for which
group and which page a tool belongs to -- so the palette and the
zero-install DCL panel offer the same routines under the same captions
by construction rather than by anybody remembering.

That is a fix for a real failure. The catalog used to be typed here,
and the palette shipped **60 of the panel's 67** commands; every
caption it did carry still agreed, and no tool was in the wrong group,
which is exactly why nobody noticed.

```
python3 tools/gen_ui_data.py           # rewrite it
python3 tools/gen_ui_data.py --check   # is it current?  make check runs this
```

The one thing still typed is the tooltip, in `blurbs.txt`, because a
blurb is words somebody chose and no table here holds them. A command
with no blurb line is **reported**, and falls back to its caption
rather than being invented.

Adding a tool to the palette is therefore: put it on `LAZPANEL`, write
its blurb, run the generator.

## The Pool chart tab

The sheet `LAZFORM` draws, in the palette: pick one of the thirteen
charts, fill in the boxes, press Draw.

It is **drawn, not photographed**. `ChartSheet` renders
`ChartCatalog`'s polylines onto a canvas and puts a box at the
**midpoint of each dimension line** — so no box has a position of its
own, and there is nothing for a human to nudge against artwork. Resize
the palette and the chart is redrawn rather than stretched.

Every key gets a row in the column beside the chart as well, including
the ones with a box on the drawing. That is `lzf:*charts*`' own
decision and it is kept for its reason: a sheet read as two kinds of
thing at once — some letters answered on the drawing, the rest in a
list — is harder to check than one column you can run your eye down.

**The state line** is phase 3's feature, and it holds `Draw` back the
same way `LAZFORM`'s holds `Insert` back:

- a box that will not read as a measurement is **named, by the letter
  the sheet prints**, and Draw is disabled — because that is the failure
  a drafter cannot see, the chart going on showing what was typed while
  the wire drops it;
- otherwise the line is the **hand-off**: how much of the sheet is
  filled and how many questions the routine will still ask.

It **asks the wire** what would be dropped (`calofin:unreadable-str`)
rather than deciding for itself. The palette does not read a
measurement any more, and a line that named a box the wire would happily
accept would be worse than no line at all. With the glue not loaded,
nothing is named and the form is exactly as honest as it was before the
line existed.

**Recall last** puts the last accepted sheet for *this chart* back into
the **empty** boxes only, so it can never overwrite a number just typed
and pressing it twice is a no-op. It is never a default: pre-filling
would put the last pool's numbers on this pool, and a wrong number that
looks answered is worse than an empty box. The store is the DCL forms'
own — same registry keys, same `key=typed;key=typed` format — so a sheet
filled in on `LAZFORM` comes back here, and the other way round.

`tests/test_chart_form.py` holds every one of those seams to the file it
has to agree with.

## The chart geometry is generated too

`Generated/ChartCatalog.g.vb` is the vector charts `LAZFORM`, `LAZSPA`
and `LAZSTEP` draw, written from `lzf:*charts*`, `lzs:*charts*` and
`lzt:chart` by `tools/gen_ui_charts.py`. It carries, per sheet: the
outline as flat polylines, every dimension with the two ends of the line
it measures, the column-only keys, the corner letters, and the answers
the sheet implies.

**Arcs arrive flattened**, by the Lisp's own `lzX:flatten`, so the
palette needs no arc arithmetic and cannot round an oval a different way
from the panel.

That is what makes a real form possible here. While the palette drew a
photograph of a chart, every box needed a hand-nudged fraction in
`fieldmap.json` and the READMEs had to admit those were "seeded
estimates". Drawn from the vectors, a box needs no position at all: it
belongs at the **midpoint of its dimension line**, in the chart's own
0..1000 co-ordinates.

What the catalog deliberately does **not** carry is `lzf:dead`, the
cross-dim mode dropdowns, `lzf:picks` and the corner tables. Those are
rules -- what a page asks about given the bottom type and the in-square
toggle -- and a second copy of a rule in VB is the drift all of this
exists to end. A form sends what was typed; the routine asks for the
rest, which is the wire's contract already.

`tests/test_ui_charts.py` reads the VB back and holds every sheet,
dimension and outline point to the Lisp table it came from.

## Nothing here can be compiled, so it is checked instead

`tools/check_vb.py` reads every `.vb` in this folder the way
`check_lisp.py` reads a `.lsp`: blocks opened and closed by the right
closer, quotes and parens balanced per logical line, and every member
and constructor arity of this assembly's **own** types resolved. That
last one is what holds the hand-written palette to the generated
catalog -- rename `CommandCatalog.Groups` and the call site fails here
rather than in somebody's AutoCAD.

It is not a compiler and does not type-check; `Option Strict On` will
still have opinions this cannot have. `tests/test_check_vb.py` drives
it against VB that is wrong on purpose, so a checker that has quietly
stopped checking fails the suite.

## Loading

1. `NETLOAD` the built `Calofin.dll`.
2. `APPLOAD` `ui/calofin_ui/calofin.lsp` — the palette asks it which
   commands exist so it can grey out the ones this session hasn't loaded.
   Without it every button stays enabled and a missing command reports
   its own absence.
3. Type `CALOFIN`.

`assets/shapes/*.png` must sit next to the DLL; the project copies them
on build.

For a permanent install put the DLL, the assets folder and
`calofin.lsp` in a bundle under `%APPDATA%\Autodesk\ApplicationPlugins\`
so it autoloads, and add the folder to the trusted paths.

## The shape diagrams

`assets/shapes/` holds twelve pool shapes cropped from the shape chart.
`fieldmap.json` records where each dimension letter sits — as a
**fraction** of the image, so boxes track their letters as the palette is
resized — and which Lisp key it feeds.

Three things the map has to translate rather than assume:

- **Chart letters are not always the Lisp keys.** Octagon and Round line
  up 1:1 (their prompts literally read `B - overall size ACROSS`), but
  the Rectangle flow calls the same two overalls `w` and `l`.
- **`SPA.LSP` reuses A–D for corner positions** (A bottom-left, B
  bottom-right, C top-right, D top-left), which collides with the chart's
  A/B *dimension* letters. Corner fields are keyed `cornera-ty` /
  `cornera-sz` and kept separate so the two senses never merge.
- **These are pool charts.** Every shape carries letters SPA never asks
  for — H, G, F, E, M, K, L are hopper, step and depth dimensions
  belonging to `POOL.LSP`. They are listed as `inactive`.

Positions are seeded estimates read off the crops, meant to be nudged
against the real artwork. Nothing depends on them being exact.

Nine of the twelve shapes are POOL shapes awaiting phase 3.

## Pool bottoms

`assets/bottoms/` holds the twelve side-view bottom types from the Bottom
Types chart. **POOL draws six of them** — `pool:*btypes*` is the
authority:

| Chart panel | POOL keyword |
| --- | --- |
| Standard Hopper | `Normal` |
| Sloping Shallow End | `SHallow` |
| Sport | `Sport` |
| Slope Bottom | `SLope` |
| Wedge | `Wedge` |
| Modified Flat | `MOdflat` |

The other six are listed on the tab but disabled, with the reason in a
tooltip, so the screen matches the paper and the gap is visible rather
than looking like something you failed to find. A `btype` the form sends
that isn't one of the six is ignored and POOL asks as usual.

The depths needed a different mechanism from everything else. The plan
chain (`H G F E`, or `E2 F2 G F1 E1` on a Sport) is keyed through
`pool:askseqb` exactly like SPA's fields — but `C`, `D` and `C2` are not:
they go through `pool:askh` / `pool:askdeep` / `pool:askc2` and land in
local variables with no keys at all. They are keyed off the prompt's
letter prefix instead, which is why `pool:fkeyof` insists on the
`"<letter> - "` shape: `pool:askh` also asks *"Total pool length (arc tip
to arc tip)"*, and that must never become a form key.

`pool:askdeep` and `pool:askc2` re-ask through plain `pool:askh` — there
is no separate `pool:askh-prompt`, and none is needed: the store is
consume-once, so a form value that fails their range check is already
gone by the re-ask and the correction is typed at the keyboard.
Re-reading the same form entry would spin forever, which is exactly why
an answer is REMOVED as it is used rather than marked used.

Chart letters `C1`, `C3`, `C4` and `F3` are collected nowhere: they
appear only on bottoms POOL cannot draw. `B` is on every section but is
never an input here — the overall length is settled by the plan view
before a bottom is asked for.

The Pool tab covers the **bottom only**. Shape, corners and cross dims
are still answered at the command line.

## Blank versus missing

The distinction the whole feature rests on, and how a box says which:

| In the form | On the wire | The routine reads it as |
| --- | --- | --- |
| box left empty | key omitted | not supplied — **ask at the command line** |
| `NA` typed in it | `(key . nil)` | **blank**, the measurement was not taken |
| a measurement | `(key . 84.0)` | that value, no prompt |
| anything else | key omitted | not supplied — **ask**, and the state line says which box was dropped |

**The palette does not read the measurement.** It sends the box's text
as typed, through `calofin.lsp`:

```
(calofin:run "spa:run-with-answers"
             '((mode . "Watersedge") (shape . "Rectangle"))
             '((w . "84") (l . "6'-3\"")))
```

Two lists, and the split is the palette's to make: a **literal** — a
shape word, a keyword answer, a point — travels as written, while a
**measure** is typed text and is read on the other side by
`calofin:answer`, which is `cal:formanswer`'s body and therefore the
same reader the DCL charts use.

That was a bug fix, not tidiness. The palette used to parse the box
itself with `Double.TryParse`, which takes a plain decimal and nothing
else — so `6'-3"`, a spelling the charts read perfectly and tell the
drafter to use, produced no number and the palette sent `(key . nil)`.
That is not "ask me". `nil` is NA: the measurement travelled as **not
taken**, and the routine never asked for it. A wrong answer that looks
answered.

`tests/test_palette_wire.py` drives the wire in the VM over all four
states and pins the two copied helpers to `CALOFIN-LIB.lsp`'s;
`tests/test_spa_form.py` checks the exact literal this assembly emits
against the real `SPA.LSP`.

The insertion point is deliberately **not** sent — it is still picked in
the drawing, where the user's own object snaps are live.
