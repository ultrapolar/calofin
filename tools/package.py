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
  * **the palette**, which is a .NET assembly and needs Windows, the
    AutoCAD reference assemblies and ``dotnet build``.  The bundle
    carries the SOURCES and a one-line Windows script that builds them
    into the slot left for the DLL.

The manifest names both either way, and that is deliberate rather than
sloppy.  The palette entry is ``LoadOnCommandInvocation``: AutoCAD does
not touch the assembly until somebody types CALOFIN, so a bundle with
the DLL slot still empty starts up exactly as fast and every Lisp tool
in it works.  Type CALOFIN before building and AutoCAD says it cannot
find the module, which is the truth and is what INSTALL.md says will
happen.

The alternative -- writing a different manifest depending on whether a
DLL happened to be lying around -- would mean the thing you tested is
not the thing you shipped.

Run:  python3 tools/package.py            # Lisp lane + palette sources
      python3 tools/package.py --with-dll path/to/Calofin.dll
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


def manifest(with_dll):
    """PackageContents.xml, the file AutoCAD actually reads.

    SeriesMin R23.0 is AutoCAD 2019, which is what the .lsp headers say
    they target ("AutoCAD 2018 and later" plus the 2019 DCL behaviour the
    forms rely on).  Platform is left as ``AutoCAD*`` so the verticals
    load it too -- Civil 3D is where a good deal of this work happens.
    """
    net = """
  <!-- THE PALETTE.  LoadOnCommandInvocation, which is what lets this
       entry stand whether or not Contents/net/Calofin.dll has been
       built yet: AutoCAD does not open the assembly until somebody
       types CALOFIN, so startup is identical either way and every Lisp
       tool in the bundle above works regardless.  Build it with
       build-palette.cmd; see INSTALL.md. -->
  <Components Description="The Calofin palette (.NET, built separately)">
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R23.0" />
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
""" % {"version": VERSION.lstrip("v")}

    built = ("" if with_dll else
             "\n     The palette's DLL is NOT in this package yet - run\n"
             "     build-palette.cmd on a Windows machine with the .NET SDK.\n"
             "     Every AutoLISP tool below works without it.\n")

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
    <RuntimeRequirements OS="Win64" Platform="AutoCAD*" SeriesMin="R23.0" />
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
rem  Build the Calofin palette and drop it into this bundle.
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
rem  The bottom-section PNGs are NOT copied by this build: they are
rem  already in Contents\net\assets\bottoms, which is where the DLL
rem  lands and therefore where BottomCatalog looks for them.  The
rem  project's own copy step finds nothing to do here, which is right.
rem
rem  AutoCAD 2025 and later moved to .NET 8.  Edit TargetFramework in
rem  src\Calofin.vbproj to net8.0-windows and the AutoCAD.NET version to
rem  25.x before building for those; src\README.md has the table.
rem ---------------------------------------------------------------------
setlocal
cd /d "%~dp0"

echo Building the Calofin palette...
dotnet build "src\Calofin.vbproj" -c Release -o "build" || goto :failed

if not exist "Contents\net" mkdir "Contents\net"
copy /y "build\Calofin.dll" "Contents\net\Calofin.dll" >nul || goto :failed

echo.
echo   Calofin.dll is in Contents\net - the palette is ready.
echo   Restart AutoCAD, or NETLOAD it, then type CALOFIN.
echo.
goto :eof

:failed
echo.
echo   BUILD FAILED.  The AutoLISP tools in this bundle do not need it:
echo   they load on their own and every command works.  Only the CALOFIN
echo   palette needs this DLL.
echo.
exit /b 1
"""


def install_doc(with_dll, commands):
    return """# Installing Calofin %(version)s

%(commands)d commands, and a palette.  Two lanes: the AutoLISP half needs
nothing installed and works the moment you copy the folder, and the
palette needs one build on a Windows machine with the .NET SDK.

## 1. The tools (no build, ~2 minutes)

Copy `%(bundle)s` into:

```
%%APPDATA%%\\Autodesk\\ApplicationPlugins\\
```

so that you end up with
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

### If AutoCAD does not pick it up

* The folder must keep the `.bundle` suffix -- that is what the loader
  scans for.
* `OPTIONS > Files > Trusted Locations`: add the `ApplicationPlugins`
  folder if your site has `SECURELOAD` set to 1 or 2.
* `APPAUTOLOAD` must not be 0.

## 2. The palette (one build)

The palette is a .NET assembly, so it has to be compiled on Windows
against the AutoCAD reference assemblies.  The sources are in `src\\`.

```
build-palette.cmd
```

It runs `dotnet build` and copies `Calofin.dll` into `Contents\\net\\`,
which is the slot the manifest already points at.  Restart AutoCAD and
type `CALOFIN`.

**Until you do that, typing `CALOFIN` reports a missing module** -- the
manifest names the palette either way, on purpose, so that what you test
is what you ship.  Nothing else is affected: the palette entry is
`LoadOnCommandInvocation`, so AutoCAD never opens the assembly until the
command is typed, and every AutoLISP tool above works without it.
`APPLOAD > Loaded Applications` may list the palette component as not
loaded before you build it, which is the same fact said another way.

For AutoCAD 2025 and later, edit `src\\Calofin.vbproj` first --
`net8.0-windows` and AutoCAD.NET `25.x`.  `src\\README.md` has the table.

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
        "dll": ("The palette DLL is included in this package.\n"
                if with_dll else
                "The palette DLL is not included - see step 2.\n")}


def build(with_dll=None):
    """Assemble dist/Calofin.bundle and zip it.  Returns (folder, zip)."""
    if DIST.exists():
        shutil.rmtree(DIST)
    root = DIST / BUNDLE_NAME
    root.mkdir(parents=True)

    payload = lisp_payload() + palette_payload()
    if with_dll:
        payload.append((pathlib.Path(with_dll), "Contents/net/Calofin.dll"))

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
    (root / "PackageContents.xml").write_text(manifest(bool(with_dll)))
    (root / "build-palette.cmd").write_text(BUILD_CMD)
    (root / "INSTALL.md").write_text(install_doc(bool(with_dll), commands))

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
    ap.add_argument("--check", action="store_true",
                    help="report what would be packaged, and write nothing")
    args = ap.parse_args(argv)

    if args.check:
        missing = [str(s.relative_to(ROOT))
                   for s, _r in lisp_payload() + palette_payload()
                   if not s.is_file()]
        for m in missing:
            print("package: missing %s" % m)
        if missing:
            return 1
        print("package: %d file(s) ready, calofin %s, %d commands"
              % (len(lisp_payload()) + len(palette_payload()), VERSION,
                 len(headline_commands())))
        return 0

    root, zpath = build(args.with_dll)
    n = sum(1 for p in root.rglob("*") if p.is_file())
    print("package: %s" % zpath.relative_to(ROOT))
    print("         %d file(s), %.1f MB, calofin %s"
          % (n, zpath.stat().st_size / 1048576.0, VERSION))
    print("         sha256 %s"
          % hashlib.sha256(zpath.read_bytes()).hexdigest()[:16])
    print("         palette DLL: %s"
          % ("included" if args.with_dll else
             "not built - run build-palette.cmd on Windows"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
