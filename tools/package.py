# SPDX-License-Identifier: GPL-3.0-or-later
"""One zip a drafter can install, out of a tree nothing here can compile.

``make check`` proves the tree is consistent and ``make test`` proves it
draws; neither produces anything somebody can put on a CAD machine.  This
does: an Autodesk **ApplicationPlugins bundle**, which is the one install
shape AutoCAD loads by itself -- drop the folder in, start AutoCAD, the
tools are there.

THERE ARE TWO LANES AND ONLY ONE OF THEM NEEDS A COMPILER, which is the
whole reason this script exists in a repo with no .NET in it:

  * **the Lisp**, which is every routine in the tree.  ``LAZPASS.lsp`` is
    already one self-contained file, so the bundle carries it and the
    glue and is finished -- no build, no NuGet, no network.  This runs on
    the machine you are reading this on.
  * **the two .NET surfaces**, the palette and the ribbon, which need
    Windows, the AutoCAD reference assemblies and ``dotnet build``.  The
    bundle carries their SOURCES and one Windows script that builds both
    into the slots left for them.

The manifest names all of it either way, and that is deliberate rather
than sloppy: writing a different manifest depending on whether a DLL
happened to be lying around would mean the thing you tested is not the
thing you shipped.  Type CALOFIN before building and AutoCAD says it
cannot find the module, which is the truth and is what INSTALL.md says
will happen.

**The two .NET entries load differently, and that is the point.**  The
palette is ``LoadOnCommandInvocation``: AutoCAD does not open the
assembly until somebody types CALOFIN, so an unbuilt bundle starts up
exactly as fast.  The ribbon is ``LoadOnAutoCADStartup``, because a
ribbon tab whose whole job is to be on the strip before anybody types
anything cannot wait to be asked for -- a tab you have to summon by
name is a palette with extra steps.  The cost is one logged missing
module per startup until the DLL is built, which INSTALL.md says out
loud; the Lisp tools are unaffected either way.

Run:  python3 tools/package.py            # Lisp lane + .NET sources
      python3 tools/package.py --with-dll path/to/Calofin.dll
      python3 tools/package.py --with-ribbon-dll path/to/CalofinRibbon.dll
      python3 tools/package.py --check    # is the tree packageable?
"""

import argparse
import datetime
import hashlib
import pathlib
import shutil
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from callib import BUNDLE, ROOT, headline_commands, read  # noqa: E402

import build_shared_bundle  # noqa: E402

DIST = ROOT / "dist"
BUNDLE_NAME = "Calofin.bundle"
UI = ROOT / "ui" / "calofin_net"
RIBBON = ROOT / "ui" / "calofin_ribbon"
GLUE = ROOT / "ui" / "calofin_ui" / "calofin.lsp"

#: The version the whole build answers to -- read off the bundle builder
#: rather than typed, so a release bump is one edit and not two.
VERSION = build_shared_bundle.RELEASE

#: Stable per-product GUID.  AutoCAD keys a plug-in's registration on
#: this, so it must NOT change between releases: a new one reads as a
#: second, unrelated product and the old registration is left behind.
PRODUCT_CODE = "{4F0A8C21-7D93-4B16-9E5A-8C1D2E6F3A47}"


def lisp_payload():
    """What the Lisp lane ships: the one-file build, and the glue.

    ``LAZPASS.lsp`` is the file the tree already tells people to hand
    anyone -- 71 files concatenated, nothing to find beside it -- and
    ``calofin.lsp`` is what the palette asks which commands exist, plus
    the form wire.  The glue loads whether or not the DLL ever does:
    without it the palette cannot grey a button and cannot name an
    unreadable box, and with no palette at all it simply defines
    functions nobody calls.
    """
    return [(BUNDLE, "Contents/lisp/LAZPASS.lsp"),
            (GLUE, "Contents/lisp/calofin.lsp")]


def palette_payload():
    """The palette's own files: sources to build, and the art to ship.

    The bottom sections are DATA the assembly loads at run time --
    BottomCatalog resolves them relative to the loaded DLL -- so they
    travel whether or not a build has happened yet.  Everything else
    here is source, and it is shipped so the build can be run from the
    bundle itself on a machine that never saw this repository.
    """
    out = []
    for p in sorted(UI.glob("*.vb")) + sorted(UI.glob("Generated/*.vb")):
        out.append((p, "src/" + p.relative_to(UI).as_posix()))
    out.append((UI / "Calofin.vbproj", "src/Calofin.vbproj"))
    out.append((UI / "blurbs.txt", "src/blurbs.txt"))
    out.append((UI / "README.md", "src/README.md"))
    for p in sorted((UI / "assets" / "bottoms").iterdir()):
        if p.is_file():
            out.append((p, "Contents/net/assets/bottoms/" + p.name))
    return out


def ribbon_payload():
    """The ribbon's own files: sources to build, and its panel icons.

    The icons are DATA the assembly reads at run time -- LoadIcon
    resolves them relative to the loaded DLL -- so they go beside the
    DLL SLOT rather than beside the sources, exactly as the palette's
    bottom sections do.  The sources sit under ``src/ribbon/`` because
    ``src/`` is already the palette's project root and two .csproj/
    .vbproj files in one folder is a build nobody can explain.
    """
    out = [(RIBBON / "RibbonExtensionApplication.cs",
            "src/ribbon/RibbonExtensionApplication.cs"),
           (RIBBON / "Generated" / "CommandCatalog.g.cs",
            "src/ribbon/Generated/CommandCatalog.g.cs"),
           (RIBBON / "CalofinRibbon.csproj", "src/ribbon/CalofinRibbon.csproj"),
           (RIBBON / "README.md", "src/ribbon/README.md")]
    for p in sorted((RIBBON / "icons").iterdir()):
        if p.is_file():
            out.append((p, "Contents/net/icons/" + p.name))
    return out


def manifest(dlls_present):
    """PackageContents.xml, the file AutoCAD actually reads.

    SeriesMin R22.0 is AutoCAD **2018**, which is what the .lsp headers
    actually say ("AutoCAD 2018 and later", in 41 of them).  It read
    R23.0 -- 2019 -- for no reason anyone wrote down, and that is not a
    harmless extra year of caution: AutoCAD does not warn about a
    RuntimeRequirements it fails, it silently skips the whole component.
    A shop on 2018 would have installed this bundle, started AutoCAD,
    and found not one of the 94 commands, with nothing anywhere saying
    why.  ``tools/check_netapi.py --refs`` against the 2018 reference
    assemblies (AutoCAD.NET 22.0.0) resolves every type and member both
    .NET surfaces call, so the floor is real and not a guess.

    Platform is left as ``AutoCAD*`` so the verticals load it too --
    Civil 3D is where a good deal of this work happens.
    """
    net = """
  <!-- THE PALETTE.  LoadOnCommandInvocation, which is what lets this
       entry stand whether or not Contents/net/Calofin.dll has been
       built yet: AutoCAD does not open the assembly until somebody
       types CALOFIN, so startup is identical either way and every Lisp
       tool in the bundle above works regardless.  Build it with
       build-net.cmd; see INSTALL.md. -->
  <Components Description="The Calofin palette (.NET, built separately)">
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R22.0" />
    <ComponentEntry AppName="CalofinPalette"
                    Version="%(version)s"
                    ModuleName="./Contents/net/Calofin.dll"
                    AppDescription="Pool, spa, step and side-view sheets"
                    LoadOnCommandInvocation="True"
                    LoadOnAutoCADStartup="False">
      <Commands GroupName="CALOFIN_PALETTE">
        <Command Global="CALOFIN" Local="CALOFIN" />
      </Commands>
    </ComponentEntry>
  </Components>

  <!-- THE RIBBON.  LoadOnAutoCADStartup, which is the one place this
       manifest differs from the palette above and is a difference in
       kind rather than an oversight: a palette is summoned by name, so
       waiting to be asked for costs it nothing, while a ribbon tab
       whose whole job is to be on the strip before anybody types
       anything cannot wait.  A tab you have to summon is a palette
       with extra steps.

       CALOFINRIBBON is registered as well, so the tab can still be
       built by hand in a session where APPAUTOLOAD stopped the startup
       load.  Until build-net.cmd has been run there is no assembly in
       the slot and AutoCAD logs the missing module once per startup -
       INSTALL.md says so.  Every AutoLISP tool is unaffected. -->
  <Components Description="The Calofin ribbon (.NET, built separately)">
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R22.0" />
    <ComponentEntry AppName="CalofinRibbon"
                    Version="%(version)s"
                    ModuleName="./Contents/net/CalofinRibbon.dll"
                    AppDescription="Every tool on a ribbon tab, by category"
                    LoadOnCommandInvocation="True"
                    LoadOnAutoCADStartup="True">
      <Commands GroupName="CALOFIN_RIBBON">
        <Command Global="CALOFINRIBBON" Local="CALOFINRIBBON" />
      </Commands>
    </ComponentEntry>
  </Components>
""" % {"version": VERSION.lstrip("v")}

    built = ("" if dlls_present else
             "\n     The .NET DLLs are NOT in this package yet - run\n"
             "     build-net.cmd on a Windows machine with the .NET SDK.\n"
             "     Every AutoLISP tool below works without them.\n")

    return """<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by tools/package.py - do not edit in the bundle.
     Edit the generator and re-run it, or your change goes away the next
     time anybody packages a release.
%(built)s-->
<ApplicationPackage SchemaVersion="1.0"
                    AppVersion="%(version)s"
                    ProductCode="%(code)s"
                    Name="Calofin"
                    Description="Pool and spa drafting tools for AutoCAD"
                    Author="Calofin"
                    ProductType="Application">
  <CompanyDetails Name="Calofin" />

  <!-- THE AUTOLISP TOOLS.  One file: LAZPASS.lsp is the whole build
       concatenated, so there are no siblings for AutoCAD to find and
       nothing depends on which folder it was loaded from.  Loaded at
       startup because a drafter expects the commands to be there, and
       the build is quiet inside itself - *calofin-quiet* stops 63
       greetings from scrolling past in every drawing opened. -->
  <Components Description="Calofin AutoLISP tools (%(commands)d commands)">
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R22.0" />
    <ComponentEntry AppName="CalofinLisp"
                    Version="%(version)s"
                    ModuleName="./Contents/lisp/LAZPASS.lsp"
                    AppDescription="Every calofin routine, in one file"
                    LoadOnAutoCADStartup="True" />
    <!-- The palette's glue: which commands are loaded, and the form
         wire that reads a typed measurement with AutoCAD's own distof.
         Harmless with no palette present - it defines functions and
         waits. -->
    <ComponentEntry AppName="CalofinGlue"
                    Version="%(version)s"
                    ModuleName="./Contents/lisp/calofin.lsp"
                    AppDescription="Palette glue and form wire"
                    LoadOnAutoCADStartup="True" />
  </Components>
%(net)s</ApplicationPackage>
""" % {"version": VERSION.lstrip("v"), "code": PRODUCT_CODE,
       "commands": len(headline_commands()), "net": net, "built": built}


BUILD_CMD = r"""@echo off
rem ---------------------------------------------------------------------
rem  Build the Calofin .NET surfaces - the palette and the ribbon - and
rem  drop both into this bundle.
rem
rem  Needs: Windows, and the .NET SDK (dotnet --version should answer).
rem  The AutoCAD reference assemblies come from NuGet on the first run,
rem  so the first build wants a network connection and later ones do not.
rem
rem  net48 also needs the .NET Framework 4.8 TARGETING PACK, which the
rem  SDK does not carry.  If the build stops with MSB3644 ("reference
rem  assemblies for .NETFramework,Version=v4.8 were not found"), install
rem  the .NET Framework 4.8 Developer Pack from Microsoft - or Visual
rem  Studio with the desktop workload, which brings it.
rem
rem  Neither the palette's bottom-section PNGs nor the ribbon's panel
rem  icons are copied by this build: both are already in Contents\net,
rem  which is where the DLLs land and therefore where BottomCatalog and
rem  LoadIcon look for them.  Each project's own copy step finds nothing
rem  to do here, which is right.
rem
rem  WHICH AUTOCAD.  Pass the year.  The default is 2018, the oldest
rem  release these tools claim, and a build against it also loads on
rem  2019-2024 -- building against the OLDEST you support is how a
rem  plugin stays loadable on all of them.  2025 moved to .NET Core and
rem  needs a build of its own.
rem
rem      build-net.cmd          2018-2024   net46            AutoCAD.NET 22.0.0
rem      build-net.cmd 2019     2019-2020   net47            AutoCAD.NET 23.0.0
rem      build-net.cmd 2021     2021-2024   net48            AutoCAD.NET 24.3.0
rem      build-net.cmd 2025     2025        net8.0-windows   AutoCAD.NET 25.0.0
rem      build-net.cmd 2026     2026        net10.0-windows  AutoCAD.NET 25.1.1
rem      build-net.cmd 2027     2027        net10.0-windows  AutoCAD.NET 26.0.0
rem
rem  Each needs its TARGETING PACK, which the SDK does not carry: the
rem  .NET Framework Developer Pack for that version (4.6 / 4.7 / 4.8),
rem  or the matching .NET SDK (8 or 10) for 2025 and later.  If the
rem  build stops on MSB3644 naming a version, that is the one to
rem  install.  net48 also works for 2018 if 4.8 is on the machine -
rem  .NET Framework 4.x is one in-place runtime - so that is the
rem  fallback when only the 4.8 pack is available.
rem ---------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set "ACADAPI=22.0.0"
set "ACADTFM=net46"
if /i "%~1"=="2019" ( set "ACADAPI=23.0.0" & set "ACADTFM=net47" )
if /i "%~1"=="2020" ( set "ACADAPI=23.1.0" & set "ACADTFM=net47" )
if /i "%~1"=="2021" ( set "ACADAPI=24.3.0" & set "ACADTFM=net48" )
if /i "%~1"=="2022" ( set "ACADAPI=24.3.0" & set "ACADTFM=net48" )
if /i "%~1"=="2023" ( set "ACADAPI=24.3.0" & set "ACADTFM=net48" )
if /i "%~1"=="2024" ( set "ACADAPI=24.3.0" & set "ACADTFM=net48" )
if /i "%~1"=="2025" ( set "ACADAPI=25.0.0" & set "ACADTFM=net8.0-windows" )
if /i "%~1"=="2026" ( set "ACADAPI=25.1.1" & set "ACADTFM=net10.0-windows" )
if /i "%~1"=="2027" ( set "ACADAPI=26.0.0" & set "ACADTFM=net10.0-windows" )
echo Building for AutoCAD.NET %ACADAPI% (%ACADTFM%)...

if not exist "Contents\net" mkdir "Contents\net"

echo Building the Calofin palette...
dotnet build "src\Calofin.vbproj" -c Release -o "build\palette" -p:AcadApi=%ACADAPI% -p:TargetFramework=%ACADTFM% || goto :failed
copy /y "build\palette\Calofin.dll" "Contents\net\Calofin.dll" >nul || goto :failed

echo Building the Calofin ribbon...
dotnet build "src\ribbon\CalofinRibbon.csproj" -c Release -o "build\ribbon" -p:AcadApi=%ACADAPI% -p:TargetFramework=%ACADTFM% || goto :failed
copy /y "build\ribbon\CalofinRibbon.dll" "Contents\net\CalofinRibbon.dll" >nul || goto :failed

echo.
echo   Both DLLs are in Contents\net.
echo   Restart AutoCAD: the Calofin ribbon tab appears by itself, and
echo   CALOFIN opens the palette.
echo.
goto :eof

:failed
echo.
echo   BUILD FAILED.  The AutoLISP tools in this bundle do not need it:
echo   they load on their own and every command works.  Only the CALOFIN
echo   palette and the ribbon tab need these DLLs.
echo.
exit /b 1
"""


INSTALL_CMD = r"""@echo off
rem ---------------------------------------------------------------------
rem  install.cmd -- put this bundle where AutoCAD looks for it.
rem
rem  AutoCAD finds a plugin by scanning ApplicationPlugins under APPDATA.
rem  That folder lives inside AppData, which Windows HIDES by default,
rem  so finding it by clicking through Explorer is harder than it should
rem  be and is the step people get stuck on.  This copies the bundle
rem  there and prints the path it used.
rem
rem  No admin rights needed: APPDATA is your own user profile.
rem ---------------------------------------------------------------------
setlocal

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"

rem  WHERE.  All three named below are folders AutoCAD's autoloader
rem  scans; which one you want depends on your site's TRUSTEDPATHS
rem  rather than on taste.
rem
rem      install.cmd                just you, no admin rights  (default)
rem      install.cmd allusers       every user on this machine (admin)
rem      install.cmd programfiles   every user, under Program Files (admin)
rem      install.cmd "D:\some\dir"  a folder you name
rem
rem  A shop whose trusted location is a machine path wants one of the
rem  middle two -- see the TRUSTEDPATHS note this prints at the end.
set "TARGET=%APPDATA%\Autodesk\ApplicationPlugins"
if /i "%~1"=="allusers"     set "TARGET=%PROGRAMDATA%\Autodesk\ApplicationPlugins"
if /i "%~1"=="programfiles" set "TARGET=%PROGRAMFILES%\Autodesk\ApplicationPlugins"
if not "%~1"=="" if /i not "%~1"=="allusers" if /i not "%~1"=="programfiles" set "TARGET=%~1"
set "DEST=%TARGET%\Calofin.bundle"

if not exist "%SRC%\PackageContents.xml" (
  echo.
  echo   This script has to sit INSIDE the Calofin.bundle folder, beside
  echo   PackageContents.xml.  Unzip the archive first, open the
  echo   Calofin.bundle folder, and run install.cmd from there.
  echo.
  pause
  exit /b 1
)

if /i "%SRC%"=="%DEST%" (
  echo.
  echo   Already installed - this IS the installed copy:
  echo     %DEST%
  echo.
  echo   Start AutoCAD and type CALVER.
  echo.
  pause
  exit /b 0
)

if exist "%DEST%\PackageContents.xml" echo   Replacing the copy already in %TARGET%

if not exist "%TARGET%" mkdir "%TARGET%" 2>nul
if not exist "%TARGET%" goto :failed

xcopy "%SRC%" "%DEST%" /E /I /Y /Q >nul
if errorlevel 1 goto :failed

echo.
echo   Installed:
echo     %DEST%
echo.
echo   1. TRUSTED LOCATION.  AutoCAD will not load code from a folder it
echo      does not trust (SECURELOAD), and that shows up as a warning
echo      dialog - or as nothing loading at all.  If the folder above is
echo      not already covered by your site's trusted paths, add it:
echo.
echo        OPTIONS  ^>  Files  ^>  Trusted Locations  ^>  Add...
echo        %TARGET%
echo.
echo      Leave "subfolders" allowed - the bundle keeps its Lisp under
echo      Contents\lisp and its DLLs under Contents\net.
echo.
echo   2. Start AutoCAD and type CALVER - it lists everything that
echo      loaded.  LAZPANEL opens the tool panel.  That is the AutoLISP
echo      half and it needs nothing else installed.
echo.
echo   3. For the ribbon tab and the palette, run build-net.cmd in the
echo      folder above, then restart AutoCAD.
echo.
pause
exit /b 0

:failed
echo.
echo   COULD NOT COPY.  Do it by hand - put the Calofin.bundle folder in:
echo.
echo     %TARGET%
echo.
echo   A machine folder needs elevation: right-click install.cmd and
echo   pick "Run as administrator".
echo.
echo   To open that folder: press Win+R, paste the line above, press
echo   Enter.  %%APPDATA%% works there even though AppData is hidden.
echo.
pause
exit /b 1
"""


def install_doc(dlls_present, commands):
    return """# Installing Calofin %(version)s

%(commands)d commands, a ribbon tab and a palette.  Two lanes: the
AutoLISP half needs nothing installed and works the moment you copy the
folder, and the two .NET surfaces need one build on a Windows machine
with the .NET SDK.

## 1. The tools (no build, ~2 minutes)

**Double-click `install.cmd` inside `%(bundle)s`.**  It copies the
bundle where AutoCAD looks and prints the path it used.  That is the
whole of this step.

It exists because the destination is inside `AppData`, which Windows
hides by default, so clicking your way there is harder than it should
be.  To do it by hand instead: press **Win+R**, paste

```
%%APPDATA%%\\Autodesk\\ApplicationPlugins
```

and press Enter -- `%%APPDATA%%` resolves even though the folder is
hidden.  Create `ApplicationPlugins` if it is not there yet, and copy
`%(bundle)s` in, so that you end up with
`%%APPDATA%%\\Autodesk\\ApplicationPlugins\\%(bundle)s\\PackageContents.xml`.

Start AutoCAD.  That is all of it -- AutoCAD reads the manifest and loads
`LAZPASS.lsp` itself.  Check it with:

```
CALVER      the version of every file that loaded
LAZPANEL    the tool panel, which is DCL and needs no palette
```

If you would rather not install anything at all, `APPLOAD` the one file
`%(bundle)s\\Contents\\lisp\\LAZPASS.lsp` by hand.  It is self-contained;
nothing else has to be found beside it.

### Trusted locations -- read this one

AutoCAD will not load code from a folder it does not trust.  That is
`SECURELOAD`, it is on by default, and depending on how strictly it is
set you either get a warning you can wave through or the load is simply
refused.  A shop that has ever added a trusted path has a list that
this folder is almost certainly not on.

`(getvar "SECURELOAD")` says which mode you are in and
`(getvar "TRUSTEDPATHS")` prints the list.

Add it:

```
OPTIONS  >  Files  >  Trusted Locations  >  Add...
```

and point it at the folder `install.cmd` printed.  Keep subfolders
allowed: the bundle holds its Lisp under `Contents\\lisp` and, once
built, its DLLs under `Contents\\net`.

The equivalent from the command line, if you would rather not click --
note the trailing `\\...`, which is what includes subfolders:

```
(setvar "TRUSTEDPATHS"
  (strcat (getvar "TRUSTEDPATHS") ";"
          (strcat (getenv "APPDATA") "\\\\Autodesk\\\\ApplicationPlugins\\\\...")))
```

**Or put the bundle where you already trust.**  The autoloader scans
three places, and any of them works -- pick the one your trusted list
already covers:

| | Where | `install.cmd` |
| --- | --- | --- |
| just you | `%%APPDATA%%\\Autodesk\\ApplicationPlugins` | `install.cmd` |
| all users | `%%PROGRAMDATA%%\\Autodesk\\ApplicationPlugins` | `install.cmd allusers` |
| all users | `%%PROGRAMFILES%%\\Autodesk\\ApplicationPlugins` | `install.cmd programfiles` |

The last two need administrator rights -- right-click `install.cmd`,
"Run as administrator".

A folder **outside** those three is a different thing: AutoCAD will not
autoload from it at all, whatever its trust setting, because the
autoloader only looks in those paths.  If your trusted folder is
somewhere else entirely, keep the bundle in one of the three above and
trust that, or drop the autoloader and `APPLOAD`
`Contents\\lisp\\LAZPASS.lsp` from wherever you like (Startup Suite
makes that stick).

### If AutoCAD still does not pick it up

* The folder must keep the `.bundle` suffix -- that is what the loader
  scans for.
* `APPAUTOLOAD` must not be 0.
* `SECURELOAD` 0 turns the check off entirely; that is your call to
  make, not this file's.

## 2. The ribbon and the palette (one build)

Both are .NET assemblies, so they have to be compiled on Windows
against the AutoCAD reference assemblies.  The sources are in `src\\`
(the palette) and `src\\ribbon\\` (the ribbon).  You need the **.NET
SDK** (`dotnet --version` should answer) and, on the first run, a
network connection: the AutoCAD reference assemblies come from NuGet
and are cached afterwards.

**Pass your AutoCAD year.**  AutoCAD loads a plugin in-process against
the runtime it was built for, so a DLL built for the wrong one simply
does not load:

```
build-net.cmd            AutoCAD 2018-2024  (net46, the default)
build-net.cmd 2019       AutoCAD 2019-2020  (net47)
build-net.cmd 2021       AutoCAD 2021-2024  (net48)
build-net.cmd 2025       AutoCAD 2025       (.NET 8 SDK)
build-net.cmd 2026       AutoCAD 2026       (.NET 10 SDK)
build-net.cmd 2027       AutoCAD 2027       (.NET 10 SDK)
```

The default builds against the **2018** API, which is the oldest these
tools claim -- and one such build loads on 2018 through 2024, because a
plugin built against the oldest release you support stays loadable on
every release above it.  Only take a later line if you want the newer
API, or if you are on 2025+.

It runs `dotnet build` twice and copies `Calofin.dll` and
`CalofinRibbon.dll` into `Contents\\net\\`, which are the slots the
manifest already points at.  Restart AutoCAD: the **Calofin** ribbon tab
is there by itself, and `CALOFIN` opens the palette.

If the build stops on **MSB3644** ("reference assemblies for
.NETFramework,Version=vX.Y were not found"), install the .NET Framework
**Developer Pack** for the version it names -- the SDK does not carry
targeting packs.  If only the 4.8 pack is available, `build-net.cmd
2021` works for AutoCAD 2018 too, as long as .NET Framework 4.8 is
installed on the machine that will run it: 4.x is one in-place runtime,
so a net48 assembly loads in AutoCAD 2018 perfectly well.

**Until you do that**, typing `CALOFIN` reports a missing module and
there is no ribbon tab -- the manifest names both either way, on
purpose, so that what you test is what you ship.  Every AutoLISP tool
above works without either of them.

The two load differently, and it is worth knowing which:

| | When AutoCAD opens it | If it is not built yet |
| --- | --- | --- |
| Palette | when you type `CALOFIN` | nothing happens until you type it, then a missing-module message |
| Ribbon | at startup, so the tab is simply there | one missing-module line in the log, once per startup |

The ribbon loads at startup because a tab you have to summon by name is
a palette with extra steps.  `APPLOAD > Loaded Applications` may list
either component as not loaded before you build, which is the same fact
said another way.

For AutoCAD 2025 and later, edit `src\\Calofin.vbproj` and
`src\\ribbon\\CalofinRibbon.csproj` first -- `net8.0-windows` and
AutoCAD.NET `25.x`.  `src\\README.md` has the table.

### If the build stops

* **MSB3644, "reference assemblies for .NETFramework v4.8 were not
  found"** -- the .NET SDK does not include the Framework targeting
  pack.  Install the *.NET Framework 4.8 Developer Pack*, or Visual
  Studio with the desktop workload.
* **NU1101, cannot find package AutoCAD.NET** -- the first build pulls
  the AutoCAD reference assemblies from NuGet and needs a network.
  Later builds do not.

Neither stops the AutoLISP half.  It is already installed and working
from step 1.

## What is on the ribbon

Five panels, one per category, and every command in the toolset on one
of them:

| Panel | What it holds |
| --- | --- |
| Layout | the pool, spa, step and pad routines - everything that draws the shape |
| Points | plots, ties, best fits and the drone tidy-ups |
| Dimensions | the dimensioning routines and the callouts |
| Converters | the four survey imports, and each one's undo |
| Checking | the reviews and the scans |

**A routine's variants sit on its own dropdown**, not beside it:
`POOL` carries *Pool layout, no bottom* and *Worked pool example*,
`XFTCONV` carries *Import cleanup, undone*, `COVERCHECK` carries its
scan and the no-dims scan.  Click the face to run what is on it, or
the arrow to pick a variant - which then stays on the face, the way
AutoCAD's own flyouts work.  Nothing is hidden: all %(commands)d
commands are reachable, on 67 buttons instead of 94.

## What is in the palette

| Tab | What it is |
| --- | --- |
| Commands | every tool, searchable by name *or caption*, with the panel's own pins and recents |
| Pool chart | LAZFORM's thirteen sheets, drawn from vectors -- eight POOL, five OASIS |
| Steps | LAZSTEP's sheet, built for the step count |
| Spa | LAZSPA's sheet, with the corners, the other outline and the cover |
| Pool bottom | the twelve section types off the paper chart, six of them live |
| Pool side | LAZSIDE's longitudinal section, one page per bottom type |

Everything on those tabs is also a command you can type, and the sheets
share their saved answers with the DCL forms both ways -- fill one in on
`LAZFORM` and `Recall last` brings it back on the palette.

## The one rule worth knowing

A box left **empty** is asked for at the command line.  `NA` typed in it
means *the measurement was not taken*, which is a different answer.  The
state line under each sheet says which of the two is about to happen.

---
Packaged %(date)s from calofin %(version)s.
%(dll)s"""  % {
        "version": VERSION, "bundle": BUNDLE_NAME, "commands": commands,
        "date": datetime.date.today().isoformat(),
        "dll": ("The palette and ribbon DLLs are included in this "
                "package.\n" if dlls_present else
                "The palette and ribbon DLLs are not included - see "
                "step 2.\n")}


def build(with_dll=None, with_ribbon_dll=None):
    """Assemble dist/Calofin.bundle and zip it.  Returns (folder, zip)."""
    if DIST.exists():
        shutil.rmtree(DIST)
    root = DIST / BUNDLE_NAME
    root.mkdir(parents=True)

    payload = lisp_payload() + palette_payload() + ribbon_payload()
    if with_dll:
        payload.append((pathlib.Path(with_dll), "Contents/net/Calofin.dll"))
    if with_ribbon_dll:
        payload.append((pathlib.Path(with_ribbon_dll),
                        "Contents/net/CalofinRibbon.dll"))

    for src, rel in payload:
        if not src.is_file():
            raise SystemExit("package: %s is missing - cannot package" % src)
        dst = root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    # the slot the DLL goes in, so the folder shape is the same before
    # and after a build and nobody has to guess where it lands
    (root / "Contents" / "net").mkdir(parents=True, exist_ok=True)

    commands = len(headline_commands())
    built = bool(with_dll) and bool(with_ribbon_dll)
    (root / "PackageContents.xml").write_text(manifest(built))
    (root / "build-net.cmd").write_text(BUILD_CMD)
    (root / "install.cmd").write_text(INSTALL_CMD)
    (root / "INSTALL.md").write_text(install_doc(built, commands))

    zpath = DIST / ("Calofin-%s-%s.zip"
                    % (VERSION, datetime.date.today().strftime("%Y%m%d")))
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(root.rglob("*")):
            if p.is_file():
                z.write(p, p.relative_to(DIST).as_posix())
    return root, zpath


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--with-dll", metavar="PATH",
                    help="a Calofin.dll built elsewhere, to ship inside")
    ap.add_argument("--with-ribbon-dll", metavar="PATH",
                    help="a CalofinRibbon.dll built elsewhere, likewise")
    ap.add_argument("--check", action="store_true",
                    help="report what would be packaged, and write nothing")
    args = ap.parse_args(argv)

    everything = lisp_payload() + palette_payload() + ribbon_payload()

    if args.check:
        missing = [str(s.relative_to(ROOT)) for s, _r in everything
                   if not s.is_file()]
        for m in missing:
            print("package: missing %s" % m)
        if missing:
            return 1
        print("package: %d file(s) ready, calofin %s, %d commands"
              % (len(everything), VERSION, len(headline_commands())))
        return 0

    root, zpath = build(args.with_dll, args.with_ribbon_dll)
    n = sum(1 for p in root.rglob("*") if p.is_file())
    print("package: %s" % zpath.relative_to(ROOT))
    print("         %d file(s), %.1f MB, calofin %s"
          % (n, zpath.stat().st_size / 1048576.0, VERSION))
    print("         sha256 %s"
          % hashlib.sha256(zpath.read_bytes()).hexdigest()[:16])
    for label, given in (("palette", args.with_dll),
                         ("ribbon ", args.with_ribbon_dll)):
        print("         %s DLL: %s"
              % (label, "included" if given else
                 "not built - run build-net.cmd on Windows"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
