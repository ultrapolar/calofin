# Calofin ribbon

A native AutoCAD ribbon tab for the toolset, in C#: one panel per
LAZPANEL category -- Layout, Points, Dimensions, Converters, Checking --
each with its own icon, and a button per routine, with a routine's
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
every other tab AutoCAD has, and Layout's 37 commands do not fit on it.
What makes that shrinkable without hiding anything is that a good many
of those 37 are the **same tool with one thing changed**: POOL and
"POOL with the bottom question pre-answered No", XFTCONV and "XFTCONV
undone", COVERCHECK and "COVERCHECK without marking the drawing".

Those go on one split button -- the primary on the face, the rest one
click down, which is what AutoCAD's own flyouts are for. 94 commands
become 67 buttons, and every one of the 94 is still reachable:

| Panel | Commands | Buttons | Large | Small, with a glyph | Small, text |
| --- | --- | --- | --- | --- | --- |
| Layout | 37 | 26 | 10 | 0 | 16 |
| Points | 15 | 13 | 3 | 0 | 10 |
| Dimensions | 12 | 10 | 5 | 0 | 5 |
| Converters | 8 | 4 | 4 | 0 | 0 |
| Checking | 22 | 14 | 0 | 14 | 0 |
| **total** | **94** | **67** | **22** | **14** | **31** |

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

## Which routines get a picture, and how big

**Thirty-six routines have a glyph of their own. The other thirty-one
are plain text buttons.** That is the first decision, and it is
editorial: `gen_ui_data.FEATURED`, the shop's own answer to "which ones
do you actually run".

What a ribbon can do that the palette cannot is let a drafter reach a
tool by SHAPE, without reading -- and that only works for a tool they
run often enough to learn the shape of. Drawing a glyph for all 67
buttons would spend the distinction it is made of: 67 pictures nobody
can tell apart is the same failure as one picture repeated 67 times,
which is what this surface shipped with when every button wore its
category's icon.

**How big a button wears it is a separate decision**, and `FEATURED`
carries it as the value against each name:

- `LARGE` -- full height, the glyph at 32 with the command under it.
  Twenty-two of them: the pool and spa layouts, the step shapes, the
  survey point work, the callouts and the stamp, the four converters.
- `SMALL` -- an ordinary row, the glyph at 16 beside the name.
  Fourteen: all of **Checking**. Fourteen large buttons made it the
  widest panel on the tab at 1120px, which is a lot of strip to spend
  on the things you run after the drawing is done. They keep their
  pictures -- a review pass is still easier to find by shape than by
  reading -- on a row a third the height, and the panel came to 554px.

So a small button comes in two kinds: with a glyph where one was drawn
(Checking) and plain text where none was (everywhere else). No panel
mixes them, because Checking is the only panel whose routines are all
featured.

`FEATURED` is guarded three ways, in `gen_ui_data.featured()`: a name
there must be a real command on the panel; it must be a **primary** --
the face of its own button, not a variant riding in a dropdown, since a
glyph drawn for a variant is one no button ever shows; and its size
must be one of the two. `tests/test_ribbon_catalog.py` adds the
invariant the two emitted flags have to keep: **every large button has
a glyph**, because you cannot show at 32 a picture nobody drew.

**The face says the COMMAND, not the caption.** A ribbon button is
about a word wide and LAZPANEL's captions are sentences: "Pool from a
filled-in chart" is a fine thing to read in a list and an unaffordable
thing to put on a strip shared with every other tab AutoCAD has. The
caption is the tooltip's title, one hover away, and the command name is
what the drafter types anyway.

## Three rows to a column

A ribbon panel is **three rows of standard-size items tall**, and that
is the whole of the layout budget. Large buttons lead the panel, one
column each; the small ones follow, three to a column, each column its
own `RibbonRowPanel` -- `RibbonPanelSource.Items` lays out across the
panel, a `RibbonRowPanel` stacks down it, and a `RibbonRowBreak`
*between* two items is what makes the second start a new row.

This is worth writing down because the first version got it wrong in a
way that looked fine in the source: it put a `RibbonRowBreak` after
**every** item, which is not "wrap", it is one button per row. Layout
asked for 26 rows in a panel that can show three, so 23 of its buttons
were simply not on the screen -- and a panel that renders its first
three buttons and stops does not look broken, it looks short.

## The icons are generated too

`tools/gen_ribbon_icons.py` draws all 82 of them with nothing but
`zlib` and `struct` -- no imaging library, because blocky icons on a
32-unit grid are not a reason for this repo to gain one:

```
python3 tools/gen_ribbon_icons.py           # rewrite them all
python3 tools/gen_ribbon_icons.py --check   # are they current?
python3 tools/gen_ribbon_icons.py --prune   # ...and delete orphans
```

**Two kinds.** One per category, for the panel header -- a floor plan
for Layout, a scatter of points for Points, a dimension line for
Dimensions, two arrows chasing each other for Converters, a checkmark
for Checking -- and one per FEATURED routine. A routine's icon takes
its **category's colours**, so a panel reads as one family and the
glyph is what distinguishes a tool inside it.

**Two sizes, because the ribbon asks for two.** `LargeImage` is the
32x32 on a large button's face; `Image` is the 16x16 a small button
wears beside its name, and the one the same command wears when a panel
is squeezed into its collapsed drop-down. Handing
one 32x32 to both slots -- which this file used to do -- makes WPF
downscale hard-edged pixel art by half, and hard-edged pixel art is the
worst thing there is to downscale. So every glyph is drawn on a 32-unit
design grid and **rendered** at each size, never resampled. Six
subjects that carry more detail than 13 pixels hold (the spa's jets,
ABHD's eight survey dots, PADDLE's ten pads, the pictorial box, the
exclamation inside LAZDIAG's page) say it again in fewer strokes at 16;
a small icon is not a small picture of the big one.

**A badge says what KIND of tool it is** -- a checkmark in the corner
for a review pass, chasing arrows for a converter -- and the subject
says what it acts on. At 16 the badge is dropped and the subject takes
the whole field: a checkmark in the six pixels a 16x16 icon can spare
for a corner is noise. Checking's fourteen are the icons this matters
most for, since 16 is the size they are normally seen at -- and they
carry it, because the subject alone tells them apart (the test asserts
it) and they are all the panel's one teal, which says "a check" more
plainly than a tick a drafter cannot resolve.

**The four converters wear their own initials** -- XFT, SO, VS, G2M --
over the chasing arrows, in a 3x5 bitmap font. A format is a name
rather than a picture, and four variations on "two arrows" would be
four icons you have to read the tooltip to tell apart, which is the
whole thing an icon is for. The initials are taken off the command name
(`XFTCONV` -> `XFT`), never typed.

`check_standards.py` runs `--check` alongside the mirror, the releases,
the bundle and the two palette catalogs, so `make check` fails on a
stale icon exactly as it does on a stale twin. They are the only entry
in that list that is not text, and they belong in it for the same
reason everything else does: a deflate stream over a fixed input is
deterministic, so "is this what a fresh render would write" is a byte
comparison either way. `--check` also reports an **orphan** -- a PNG
nothing would write any more -- because a routine dropped from
`FEATURED` otherwise leaves its picture behind to be copied into every
bundle for ever.

`tests/test_ribbon_icons.py` adds the one thing a byte comparison
cannot see: **no two icons are the same picture.** The whole argument
for spending 36 glyphs is that a drafter can tell them apart, and two
commands that got the same drawing -- a copy-paste in `DESIGN`, a
subject reused by accident -- would look exactly like a working ribbon
and be worth nothing.

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
already folded and each button's size on it -- in
`Generated/CommandCatalog.g.cs`. One generator, one set of source
tables, two emitted files -- not two copies of a roster to keep in step
by hand, which is the exact drift `gen_ui_data.py`'s own docstring
already tells the story of.

```
python3 tools/gen_ui_data.py           # rewrite both generated catalogs
python3 tools/gen_ui_data.py --check   # are they both current?  make check runs this
```

**Never hand-edit `Generated/CommandCatalog.g.cs` or `icons/`.** Add a
tool the same way as always: put it on `LAZPANEL`, write its blurb in
`blurbs.txt`, and re-run the generator. To give it a picture, add its name
to `gen_ui_data.FEATURED` with a size (`LARGE` or `SMALL`) and a glyph
to `gen_ribbon_icons.DESIGN` -- `make check` fails until both are
there, in either direction.

## The tab puts itself back

Three lifecycle things, none of which is obvious and all of which show
up as "the tab is just gone":

- **The ribbon is not up yet during a startup load.** The bundle
  demand-loads this assembly at AutoCAD startup, before the default
  workspace has finished building the ribbon, so `Initialize()` cannot
  assume `ComponentManager.Ribbon`. It builds at the next
  `Application.Idle` instead, which is after the editor is responsive.
- **A workspace switch takes the tab away.** Switching workspace
  rebuilds the ribbon out of the CUI, and a tab added through the API
  is not in the CUI. So `WSCURRENT` is watched, and the tab is rebuilt
  when it changes. Nothing about the loss looks like a failure -- the
  drafter picks a different workspace and the toolset's tab has quietly
  stopped existing -- which is exactly why it is worth code.
- **The tab does not make itself current.** Only `CALOFINRIBBON`, typed
  by hand, activates it. An automatic path that did would mean every
  AutoCAD session opens on Calofin instead of Home.

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

The icons are `<None Update=...>`, not `Include`: the .NET SDK's
default `None` glob already holds every file in the project folder, so
`Include` declares them a second time and the build stops on
NETSDK1022 before it compiles a line. `Calofin.vbproj` carries the same
note over `assets\bottoms`.

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

## What this does not do

**It does not grey out a command this session has not loaded.** The
palette asks `calofin:loaded` which routines exist and disables the
rest; this surface has no equivalent, so a button for an unloaded
command reports its own absence at the command line instead. That is
the same thing a LAZPANEL page button does when `calofin.lsp` is not
loaded, and it is a deliberate gap rather than an oversight -- but it
is the failure mode to watch for on a machine with a partial install.

## Nothing here can be compiled, so less can be checked than the palette

`ui/calofin_net/` has `tools/check_vb.py`: a structural reader that
catches unbalanced blocks, unresolved members of the assembly's own
types, and missing framework imports, without a VB compiler in this
tree. This project has no equivalent yet -- `RibbonExtensionApplication.cs`
is checked by nothing but a human reader, and `Generated/CommandCatalog.g.cs`
is checked only by `tests/test_ribbon_catalog.py` reading it back as
text against the panel it must agree with. Writing a `check_cs.py` for
C# (or teaching that one to read both) is future work, named here
rather than left to be discovered as a silent gap the way the VB
palette's own drift once was.

**What to do with the first real build**, because nothing here can
prove any of it:

1. `NETLOAD` and confirm the "Calofin" tab appears with five panels,
   in the order Layout / Points / Dimensions / Converters / Checking,
   each carrying its own icon -- and that it does **not** steal focus
   from Home.
2. Confirm each panel is **three rows tall and no more**, with the
   large buttons leading and the small ones in columns of three. This
   is the part the source got wrong once; `RibbonRowPanel`,
   `RibbonRowBreak` and how `RibbonPanelSource.Items` lays out across
   the panel are all taken on faith until a build says otherwise.
3. Confirm a large button shows its 32x32 glyph with the command under
   it, that **Checking**'s rows show their 16x16 glyph beside the name,
   and that every other small button is text only. Then confirm the
   **tooltip** carries the command name, the caption and the blurb --
   `RibbonToolTip`'s `Command` / `Title` / `Content` are the other
   unverified API surface here.
4. Click a button and confirm it runs the command exactly as typing it
   would -- `POOL`, say, should start prompting the way it does from
   the command line or from the palette.
5. **Open a split button's dropdown** -- POOL on Layout, or any of the
   four on Converters -- and confirm the variants are listed, that
   picking one runs it, and that it then sits on the face without
   changing size (`RibbonSplitButton.Current`, `IsSplit` and
   `IsSynchronizedWithCurrentItem`).
6. **Switch workspace and switch back**, and confirm the tab survives
   -- that is what the `WSCURRENT` watch is for and it cannot be tested
   any other way.
7. Squeeze the ribbon narrow enough to **collapse a panel** and confirm
   the drop-down shows the 16x16 icons beside their names.
8. Confirm a command this session has not loaded still runs when
   clicked and reports its own absence at the command line -- see "what
   this does not do" above.
9. Install the bundle proper and confirm the tab appears **without**
   anything being typed, and that an unbuilt bundle costs one log line
   rather than a dialog.
