# Calofin ribbon

A native AutoCAD ribbon tab for the toolset, in C#: one panel per
LAZPANEL category -- Layout, Points, Dimensions, Converters, Checking
-- each with its own icon, and one button per routine filed into it.

This is a second surface, not a replacement. `ui/calofin_net/` is the
dockable palette (find-by-name, Recent/Pinned, the drawn chart forms);
this is the ribbon a drafter who lives in the ribbon UI reaches for
instead. Both can be `NETLOAD`ed in the same session -- different
assembly names (`Calofin.dll` / `CalofinRibbon.dll`), different root
namespaces (`Calofin` / `Calofin.Ribbon`), different command names
(`CALOFIN` / `CALOFINRIBBON`) -- and neither references the other.

## The one rule

Same one as the palette's: **this assembly contains no drawing logic.**
A button sends the command name it always had --
`doc.SendStringToExecute("_." + command + "\n", ...)` -- and the `.lsp`
routine does everything else, unaware a ribbon button was ever
involved.

## Why the catalog needs no reference to the VB palette

The ribbon's panels are LAZPANEL's own category table --
`lzp:*groups*`, the same one `CalofinPalette.vb`'s `CommandCatalog.Groups`
already carries. Referencing the VB project from C# would work
(project-to-project references across languages are ordinary MSBuild),
but it would make this ribbon's only purpose -- five panels and their
buttons -- carry the whole palette assembly as a runtime dependency,
just to read one table out of it.

So `tools/gen_ui_data.py` writes this table **twice**, in two
languages, from the one source: LAZPANEL's `lzp:*captions*` and
`lzp:*groups*`, plus `ui/calofin_net/blurbs.txt` for the tooltip. VB
gets its four views (`All`, `Groups`, `Pages`, `CaptionOf`) in
`ui/calofin_net/Generated/CommandCatalog.g.vb`; this project gets the
one it actually uses, `Groups` alone, in
`Generated/CommandCatalog.g.cs`. One generator, one set of source
tables, two emitted files -- not two copies of a roster to keep in
step by hand, which is the exact drift `gen_ui_data.py`'s own docstring
already tells the story of.

```
python3 tools/gen_ui_data.py           # rewrite both generated catalogs
python3 tools/gen_ui_data.py --check   # are they both current?  make check runs this
```

**Never hand-edit `Generated/CommandCatalog.g.cs`.** Add a tool the
same way as always: put it on `LAZPANEL`, write its blurb in
`blurbs.txt`, and re-run the generator.

## The icons are generated too

Five PNGs, one per category, in `icons/` -- a background colour and a
small glyph (a floor plan for Layout, a scatter of points for Points,
a dimension line for Dimensions, two arrows chasing each other for
Converters, a checkmark for Checking) so the row of panels reads as
five different things before anyone reads a caption.

`tools/gen_ribbon_icons.py` draws them with nothing but `zlib` and
`struct` -- no imaging library, because five blocky 32x32 icons are not
a reason for this repo to gain one:

```
python3 tools/gen_ribbon_icons.py           # rewrite the five PNGs
python3 tools/gen_ribbon_icons.py --check   # are they current?
```

**Not yet wired into `check_standards.py`.** The five checks that run
there (`mirror_shared`, `release_lisp`, `build_shared_bundle`,
`gen_ui_data`, `gen_ui_charts`) all hold `lisp/`-derived text to a
byte-identical regeneration; icon bytes drift the same way source text
does (`zlib` is deterministic for a given input), so wiring this in is
a natural next step, deliberately left for once this surface has been
built and run at least once. `make verify` runs it today.

## Building

Same requirement as the palette: the AutoCAD .NET reference assemblies,
pulled from NuGet.

```
dotnet build ui/calofin_ribbon/CalofinRibbon.csproj -c Release
```

| AutoCAD | TargetFramework | AutoCAD.NET |
| --- | --- | --- |
| 2021-2024 | `net48` | `24.x` |
| 2025+ | `net8.0-windows` | `25.x` |

`ExcludeAssets="runtime"` is deliberate, exactly as in
`Calofin.vbproj`: shipping `acmgd.dll` / `acdbmgd.dll` /
`AdWindows.dll` beside the output makes AutoCAD load a second copy of
its own API.

## Loading

1. `NETLOAD` the built `CalofinRibbon.dll`. The "Calofin" tab appears
   on the ribbon automatically -- `IExtensionApplication.Initialize()`
   builds it, waiting on `Application.Idle` if the ribbon framework
   itself is not up yet this early in the session.
2. If the tab does not appear (a session that loaded the DLL before
   the ribbon existed, and somehow never fired the wait), type
   `CALOFINRIBBON` to build it by hand.
3. `icons/*.png` must sit next to the DLL; the project copies them on
   build, the same as the palette's `assets/bottoms/*.png`.

For a permanent install, put `CalofinRibbon.dll` and `icons/` in the
same `ApplicationPlugins` bundle `tools/package.py` already builds for
the palette (see `ui/UI-PLAN.md` phase 5k) -- `LoadOnCommandInvocation`
manifests do not care how many assemblies they name.

## Nothing here can be compiled, so less can be checked than the palette

`ui/calofin_net/` has `tools/check_vb.py`: a structural reader that
catches unbalanced blocks, unresolved members of the assembly's own
types, and missing framework imports, without a VB compiler in this
tree. This project has no equivalent yet -- `RibbonExtensionApplication.cs`
is checked by nothing but a human reader, and `Generated/CommandCatalog.g.cs`
is checked only by `tests/test_ribbon_catalog.py` reading it back as
text against the panel it must agree with. Writing a `check_vb.py` for
C# (or teaching that one to read both) is future work, named here
rather than left to be discovered as a silent gap the way the VB
palette's own drift once was.

**What to do with the first real build**, because nothing here can
prove any of it:

1. `NETLOAD` and confirm the "Calofin" tab appears with five panels,
   in the order Layout / Points / Dimensions / Converters / Checking,
   each carrying its own icon.
2. Confirm every button's caption matches `LAZPANEL`'s -- the same
   words the palette's Commands tab shows for the same command.
3. Click a button and confirm it runs the command exactly as typing it
   would -- `POOL`, say, should start prompting the way it does from
   the command line or from the palette.
4. Confirm a command this session has not loaded still runs when
   clicked and reports its own absence at the command line, the same
   as a page button on the palette when `calofin.lsp` is not loaded --
   this surface does not grey anything out, unlike the palette's
   `UpdateAvailability`, so that failure mode is the one to watch for.
