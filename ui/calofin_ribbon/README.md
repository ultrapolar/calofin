# Calofin ribbon

A native AutoCAD ribbon tab for the toolset, in C#: one panel per
LAZPANEL category -- Layout, Points, Dimensions, Converters, Checking
-- each with its own icon, and a button per routine, with a routine's
variants on its own dropdown.

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

## A routine's variants ride on its dropdown

A ribbon panel is not a DCL page. It is one row on a strip shared with
every other tab AutoCAD has, and Layout's 37 buttons do not fit on it.
What makes that shrinkable without hiding anything is that a good many
of those 37 are the **same tool with one thing changed**: POOL and
"POOL with the bottom question pre-answered No", XFTCONV and "XFTCONV
undone", COVERCHECK and "COVERCHECK without marking the drawing".

Those go on one split button -- the primary on the face, the rest one
click down -- which is what AutoCAD's own flyouts are for. 94 commands
become 67 buttons, and every one of the 94 is still reachable:

| Panel | Commands | Buttons |
| --- | --- | --- |
| Layout | 37 | 26 |
| Points | 15 | 13 |
| Dimensions | 12 | 10 |
| Converters | 8 | 4 |
| Checking | 22 | 14 |

**Which is a variant of which is derived, not typed.** `variant_of` in
`tools/gen_ui_data.py` reads it off the roster with affix rules --
`<X>COVER` under `<X>`, `<X>SCAN` under `<X>` or under `<X>CHECK`,
`LITE<X>` under `<X>`, `<X>RECONV` under `<X>CONV`, plus `ALT`, `SIMP`
and `C` prefixes -- and **every rule is guarded twice**: the base it
names must be a real command, and it must be in the **same category**.
That second guard is the one that earns its keep: `LOBF` is on Points
and `ABLOBF` on Layout, so nothing folds one into the other, and a
family can never straddle two panels.

The handful no affix describes are a short editorial table
(`NAMED_VARIANTS`): POOLDEMO under POOL, LAZTXT under LAZFORM,
MOHAMADDLE under PADDLE, HONEFILLET under SMARTFILLET,
AUTODIMSIDEPOV under AUTODIM. An entry there is a claim that two tools
are one tool with something changed, and a wrong one hides a tool a
drafter would go looking for -- so what is deliberately *not* in it is
worth saying: **CORNERSTP / HEMISTEP / NORMIESTEP stay three buttons.**
Three step shapes are three tools that do parallel things, not three
versions of one, and choosing which of them wears the face of a flyout
would be an invention rather than a reading.

`tests/test_ribbon_catalog.py` holds the fold in the direction that
matters. A tool in the wrong dropdown is a nuisance a drafter works
around; a tool in **no** item at all is unreachable from this surface
and nothing about the ribbon would look broken. So the test asserts
every command in a category appears exactly once across its buttons --
on a face or in a dropdown -- and pins each family as the editorial
claim it is, rather than by asking the rules again.

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
one it actually uses, `Panels` -- the same roster with the families
already folded -- in `Generated/CommandCatalog.g.cs`. One generator,
one set of source tables, two emitted files -- not two copies of a
roster to keep in
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

`check_standards.py` runs that check alongside the mirror, the
releases, the bundle and the two palette catalogs, so `make check`
fails on a stale icon exactly as it does on a stale twin. They are the
only entry in that list that is not text, and they belong in it for the
same reason everything else does: a deflate stream over a fixed input
is deterministic, so "is this what a fresh render would write" is a
byte comparison either way.

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

## Installing it

**The ordinary way is the bundle.** `python3 tools/package.py` writes
an `ApplicationPlugins` bundle carrying this project's sources, its
icons and a manifest entry for it; `build-net.cmd` inside that bundle
builds both .NET surfaces into the slots the manifest already points
at. Copy the bundle into `%APPDATA%\Autodesk\ApplicationPlugins\`, run
that script once, restart AutoCAD, and the tab is there. The bundle's
own `INSTALL.md` is the drafter-facing version of this.

**The ribbon's manifest entry is `LoadOnAutoCADStartup`, and the
palette's is not.** That is the one asymmetry in that manifest and it
is a difference in kind: a palette is summoned by name, so waiting to
be asked costs it nothing, while a tab whose whole job is to be on the
strip before anybody types anything cannot wait. A tab you have to
summon is a palette with extra steps. The cost is one logged missing
module per startup until the DLL is built, which the bundle's
`INSTALL.md` says out loud rather than leaving to be discovered.

**Loading it by hand**, for a build you are testing:

1. `NETLOAD` the built `CalofinRibbon.dll`. The "Calofin" tab appears
   by itself -- `IExtensionApplication.Initialize()` builds it, waiting
   on `Application.Idle` if the ribbon framework is not up yet this
   early in the session.
2. If the tab does not appear, type `CALOFINRIBBON` to build it by
   hand. (The same command is registered in the bundle manifest, for a
   session where `APPAUTOLOAD` stopped the startup load.)
3. `icons/*.png` must sit next to the DLL; the project copies them on
   build, the same as the palette's `assets/bottoms/*.png`.

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
4. **Open a split button's dropdown** -- POOL on Layout, or any of the
   four on Converters -- and confirm the variants are listed, that
   picking one runs it, and that it then sits on the face
   (`IsSynchronizedWithCurrentItem`). This is the part with the most
   API surface nothing here can compile: `RibbonSplitButton.Current`,
   `IsSplit` and that synchronise flag are all taken on faith until a
   build says otherwise.
5. Confirm a command this session has not loaded still runs when
   clicked and reports its own absence at the command line, the same
   as a page button on the palette when `calofin.lsp` is not loaded --
   this surface does not grey anything out, unlike the palette's
   `UpdateAvailability`, so that failure mode is the one to watch for.
6. Install the bundle proper and confirm the tab appears **without**
   anything being typed, and that an unbuilt bundle costs one log line
   rather than a dialog.
