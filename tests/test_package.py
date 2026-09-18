"""The installable bundle, against the tree it is cut from.

``tools/package.py`` writes the one artefact in this repository that a
drafter can actually install: an Autodesk ApplicationPlugins bundle.
Nothing else here can see it is wrong, because nothing else here builds
it -- ``make check`` reads source and ``make test`` drives the VM, and a
manifest naming a file that is not in the zip passes both.

The failure this is aimed at is a quiet one.  A bundle whose
``PackageContents.xml`` points at a module that did not travel does not
crash: AutoCAD logs a line most people never read and the commands are
simply absent, which looks like the tools not working rather than like a
packaging mistake.

What is checked:

1. Every ``ModuleName`` the manifest names is a file that is really in
   the bundle -- except the palette DLL, which is the one deliberate
   exception and has to be spelled as such.
2. That exception is safe: the palette entry is
   ``LoadOnCommandInvocation`` and NOT loaded at startup, which is the
   whole reason the entry may stand before the DLL exists.
3. The version is the build's own, in all three places it appears, and
   the ProductCode is the fixed one -- a new GUID per release reads to
   AutoCAD as a different product.
4. The Lisp lane is complete on its own: LAZPASS.lsp is the real
   bundle, the glue is the real glue, and neither is a stub.
5. The palette sources shipped are the ones in the tree, all of them --
   a form left out builds a palette missing a tab.
6. The zip unpacks to exactly what was assembled.

This one WRITES: it packages for real, into ``dist/``, because the thing
under test is the artefact and a mock of it would prove nothing.  That
folder is a build output -- gitignored, and rewritten from scratch by
every run of ``tools/package.py`` -- so a test run and a ``make package``
leave the same bytes behind.

Run: python3 tests/test_package.py
"""

import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import package  # noqa: E402
from callib import ROOT, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


root, zpath = package.build()
XML = read(root / "PackageContents.xml")
FILES = {p.relative_to(root).as_posix()
         for p in root.rglob("*") if p.is_file()}


print("== 1. every module named is a module shipped ==")

# The two .NET assemblies are the deliberate absences: this package is
# cut on a machine with no compiler, so they have to be named before
# they exist or the manifest would change shape depending on what was
# lying around.
UNBUILT = {"Contents/net/Calofin.dll", "Contents/net/CalofinRibbon.dll"}

modules = re.findall(r'ModuleName="\./([^"]+)"', XML)
check("the manifest names %d module(s)" % len(modules), len(modules) == 4,
      repr(modules))
for m in modules:
    if m in UNBUILT:
        check("%s is a deliberate absence" % m, m not in FILES,
              "a DLL got into a source-only package")
        continue
    check("%s travelled" % m, m in FILES, repr(sorted(FILES)[:4]))


print("== 2. the two .NET entries load the way each of them should ==")

# This is what makes naming an unbuilt module honest rather than
# broken: AutoCAD does not open the assembly until CALOFIN is typed, so
# a bundle with the slot still empty starts identically and every Lisp
# tool in it works.
palette = XML[XML.index('AppName="CalofinPalette"'):]
palette = palette[:palette.index("</ComponentEntry>")]
check("the palette loads on command invocation",
      'LoadOnCommandInvocation="True"' in palette)
check("...and explicitly not at startup",
      'LoadOnAutoCADStartup="False"' in palette)
check("...and the command it waits for is CALOFIN",
      'Global="CALOFIN"' in palette)

# The ribbon is the deliberate opposite, and the one asymmetry in this
# manifest: a tab whose whole job is to be on the strip before anybody
# types anything cannot be demand-loaded on a command, or it is a
# palette with extra steps.  It keeps the command too, for a session
# where APPAUTOLOAD stopped the startup load.
ribbon = XML[XML.index('AppName="CalofinRibbon"'):]
ribbon = ribbon[:ribbon.index("</ComponentEntry>")]
check("the ribbon loads at startup, unlike the palette",
      'LoadOnAutoCADStartup="True"' in ribbon)
check("...and can still be built by hand with CALOFINRIBBON",
      'Global="CALOFINRIBBON"' in ribbon)

# the Lisp half is the opposite: a drafter expects the commands to be
# there without typing anything
lisp = XML[XML.index('AppName="CalofinLisp"'):]
lisp = lisp[:lisp.index("/>")]
check("the Lisp half loads at startup",
      'LoadOnAutoCADStartup="True"' in lisp)


print("== 3. one version, one product code ==")

bare = package.VERSION.lstrip("v")
check("AppVersion is the build's own version",
      ('AppVersion="%s"' % bare) in XML, bare)
check("every ComponentEntry carries it",
      XML.count('Version="%s"' % bare) == 5,
      "%d occurrence(s)" % XML.count('Version="%s"' % bare))
check("the ProductCode is the fixed one, not a fresh GUID",
      ('ProductCode="%s"' % package.PRODUCT_CODE) in XML)
check("it is a well-formed GUID",
      re.fullmatch(r"\{[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}\}",
                   package.PRODUCT_CODE) is not None,
      package.PRODUCT_CODE)


print("== 4. the Lisp lane is complete on its own ==")

shipped = read(root / "Contents" / "lisp" / "LAZPASS.lsp")
source = read(ROOT / "shared" / "LAZPASS.lsp")
check("LAZPASS.lsp is the real bundle, byte for byte",
      shipped == source, "%d vs %d bytes" % (len(shipped), len(source)))
check("...and it is the whole build, not a stub",
      len(shipped.splitlines()) > 50000, str(len(shipped.splitlines())))

glue = read(root / "Contents" / "lisp" / "calofin.lsp")
check("the glue is the real glue",
      glue == read(ROOT / "ui" / "calofin_ui" / "calofin.lsp"))
check("...and it carries the form wire the state line asks",
      "calofin:unreadable-str" in glue)

# The bottom sections are DATA the assembly reads at run time, resolved
# relative to the loaded DLL -- so they belong beside the DLL SLOT, not
# beside the sources, or a built palette shows twelve empty panels.
bottoms = [f for f in FILES if f.startswith("Contents/net/assets/bottoms/")]
on_disk = [p.name for p in (ROOT / "ui" / "calofin_net" / "assets"
                            / "bottoms").iterdir() if p.is_file()]
check("all %d bottom-section files sit beside the DLL slot" % len(on_disk),
      len(bottoms) == len(on_disk),
      "%d shipped, %d in the tree" % (len(bottoms), len(on_disk)))


print("== 5. every palette source travelled ==")

want = sorted(p.relative_to(ROOT / "ui" / "calofin_net").as_posix()
              for p in (ROOT / "ui" / "calofin_net").rglob("*.vb"))
got = sorted(f[len("src/"):] for f in FILES
             if f.startswith("src/") and f.endswith(".vb"))
check("all %d .vb file(s), generated ones included" % len(want),
      got == want, repr([w for w in want if w not in got]))
check("the project file travelled", "src/Calofin.vbproj" in FILES)
check("the tooltips travelled", "src/blurbs.txt" in FILES)

# A form left out is a palette missing a tab, and it would build
# cleanly -- CalofinPalette.vb is the only file that names them all.
mounted = re.findall(r'New (\w+View)\(',
                     read(ROOT / "ui" / "calofin_net" / "CalofinPalette.vb"))
for view in sorted(set(mounted)):
    check("%s is in the package" % view, ("src/%s.vb" % view) in FILES)


print("== 5b. the ribbon: sources to build, icons where LoadIcon looks ==")

want_cs = sorted(p.relative_to(ROOT / "ui" / "calofin_ribbon").as_posix()
                 for p in (ROOT / "ui" / "calofin_ribbon").rglob("*.cs"))
got_cs = sorted(f[len("src/ribbon/"):] for f in FILES
                if f.startswith("src/ribbon/") and f.endswith(".cs"))
check("all %d .cs file(s), the generated catalog included" % len(want_cs),
      got_cs == want_cs, repr([w for w in want_cs if w not in got_cs]))
check("the ribbon project file travelled",
      "src/ribbon/CalofinRibbon.csproj" in FILES)

# The icons are read at run time and resolved relative to the loaded
# DLL, so they belong beside the DLL SLOT and not beside the sources --
# the same rule the palette's bottom sections follow, and the same
# failure if it is broken: panels with no picture on them.
icons = [f for f in FILES if f.startswith("Contents/net/icons/")]
on_disk = [p.name for p in (ROOT / "ui" / "calofin_ribbon"
                            / "icons").iterdir() if p.is_file()]
check("all %d panel icon(s) sit beside the DLL slot" % len(on_disk),
      len(icons) == len(on_disk),
      "%d shipped, %d in the tree" % (len(icons), len(on_disk)))


print("== 6. the zip is what was assembled ==")

with zipfile.ZipFile(zpath) as z:
    names = {n for n in z.namelist() if not n.endswith("/")}
    bad = [n for n in z.namelist() if n.startswith("/") or ".." in n]
check("the zip holds every file the folder does",
      names == {"%s/%s" % (package.BUNDLE_NAME, f) for f in FILES},
      repr(sorted(names ^ {"%s/%s" % (package.BUNDLE_NAME, f)
                           for f in FILES})[:4]))
check("every path is relative and inside the bundle", not bad, repr(bad))
check("it unpacks into one .bundle folder",
      {n.split("/", 1)[0] for n in names} == {package.BUNDLE_NAME})
check("the install notes travelled",
      "%s/INSTALL.md" % package.BUNDLE_NAME in names)
check("...and the Windows build script",
      "%s/build-net.cmd" % package.BUNDLE_NAME in names)


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL PACKAGE CHECKS PASSED (%d files, calofin %s)"
      % (len(FILES), package.VERSION))
