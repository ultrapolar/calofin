# Calofin palette

A dockable AutoCAD palette for the routines in this repository: a button
for every command, and a form for `SPA` that lets you enter the
measurements you have and leave the rest blank.

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
dotnet build calofin_net/Calofin.vbproj -c Release
```

| AutoCAD | TargetFramework | AutoCAD.NET |
| --- | --- | --- |
| 2021–2024 | `net48` | `24.x` |
| 2025+ | `net8.0-windows` | `25.x` |

`ExcludeAssets="runtime"` on the package reference is deliberate.
Shipping `acmgd.dll` / `acdbmgd.dll` beside the output makes AutoCAD load
a second copy of its own API and fail in ways that look unrelated to this
project.

## Loading

1. `NETLOAD` the built `Calofin.dll`.
2. `APPLOAD` `calofin_ui/calofin.lsp` — the palette asks it which
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

`pool:askdeep` and `pool:askc2` re-ask through `pool:askh-prompt` rather
than `pool:askh`. A form value that fails their range check has to be
corrected at the keyboard — re-reading the same form entry would spin
forever.

Chart letters `C1`, `C3`, `C4` and `F3` are collected nowhere: they
appear only on bottoms POOL cannot draw. `B` is on every section but is
never an input here — the overall length is settled by the plan view
before a bottom is asked for.

The Pool tab covers the **bottom only**. Shape, corners and cross dims
are still answered at the command line.

## Blank versus missing

The distinction the whole feature rests on:

| In the form | On the wire | `SPA.LSP` reads it as |
| --- | --- | --- |
| field left empty | key omitted | not supplied — **ask at the command line** |
| field explicitly cleared | `(key . nil)` | **blank**, the same answer as `NA` |
| field filled | `(key . 84.0)` | that value, no prompt |

`tests/test_spa_form.py` pins all three, and checks the exact literal
this assembly emits against the real `SPA.LSP`.

The insertion point is deliberately **not** sent — it is still picked in
the drawing, where the user's own object snaps are live.
