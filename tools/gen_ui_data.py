# SPDX-License-Identifier: GPL-3.0-or-later
"""The palette's tables, written from the tables the panel already has.

The VB palette and the DCL panel offer the same 71 routines, filed into
the same groups, under the same captions.  Until now they said so
twice: ``lzp:*captions*`` and ``lzp:*groups*`` in LAZPANEL.lsp, and a
hand-typed ``CommandCatalog.Groups`` in CalofinPalette.vb.  Two copies
of one roster is a drift machine, and it drifted -- the palette shipped
60 of the panel's 67, every caption that was there agreed, and nothing
said the catalogs had parted.

So the palette's copy stops being typed.  This writes
``ui/calofin_net/Generated/CommandCatalog.g.vb`` from LAZPANEL's own
tables plus ``ui/calofin_net/blurbs.txt``, and ``--check`` fails when
what is on disk is not what a fresh run would write -- the same
contract ``releases/`` and ``shared/LAZPASS.lsp`` are held to.

The ribbon add-in (``ui/calofin_ribbon/``) needs the same category
table -- Layout/Points/Dimensions/Converters/Checking, with a caption
and a tooltip per command -- and it is written in C#, not VB, so it
cannot reference ``CalofinPalette.vb``'s class without dragging the
whole palette assembly along as a runtime dependency it does not
otherwise need.  Rather than hand-type a second roster in a second
language and reopen the exact drift this file exists to close, this
also writes ``ui/calofin_ribbon/Generated/CommandCatalog.g.cs`` -- the
category table alone, since the ribbon has no Find page and no job
pages to carry.  One generator, two languages, the same source tables.

**Why generating VB is allowed here when check_registry --fix refuses.**
check_registry will not write VB because the decisions it would be
writing are editorial: a caption is words somebody chose, a category is
a judgement about what a tool IS, and a codemod inventing either would
be writing code no test in this repo can run.  Nothing in this file is
a decision.  Every command, caption, group and page is transcribed from
a table that test_lazpanel.py already holds to the tree, and the one
piece of editorial text -- the tooltip blurb -- is READ from
blurbs.txt, never invented: a command with no blurb line is reported,
and falls back to its caption rather than being guessed at.

The generated file is data, not behaviour.  It defines no method, calls
nothing, and imports one namespace; what the palette DOES with the
tables stays hand-written in CalofinPalette.vb, where a human can read
it.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from callib import ROOT, read  # noqa: E402
from check_registry import CATEGORIES, PANEL, captions, pages, tutorials  # noqa: E402

BLURBS = ROOT / "ui" / "calofin_net" / "blurbs.txt"
HOWTO = ROOT / "ui" / "calofin_net" / "howto.txt"
OUT = ROOT / "ui" / "calofin_net" / "Generated" / "CommandCatalog.g.vb"
OUT_CS = ROOT / "ui" / "calofin_ribbon" / "Generated" / "CommandCatalog.g.cs"

#: What the palette's Commands tab shows as its groups.  They ARE the
#: panel's category pages -- lzp:*groups* files every tool into
#: exactly one of them -- so the palette's grouping is not a second
#: opinion about where a tool belongs.
GROUPS = CATEGORIES


# ------------------------------------------------------- variant families
#
# A ribbon panel is not a DCL page: it is one row of buttons on a strip
# shared with every other tab AutoCAD has, and Layout's 37 buttons do
# not fit on one.  What makes that shrinkable without hiding anything is
# that a good many of those 37 are the SAME tool with one thing changed
# -- POOL and "POOL with the bottom question pre-answered No", XFTCONV
# and "XFTCONV undone", COVERCHECK and "COVERCHECK without marking the
# drawing".  Those belong on one split button, primary on the face and
# the rest one click down, which is what AutoCAD's own flyouts are.
#
# Which is which is NOT typed out.  It is derived from the roster by the
# rules below, each of which fires only when the base it names is itself
# a real command IN THE SAME CATEGORY -- the same shape of reasoning
# callib.satellites() already uses to decide which commands carry no
# panel button.  The same-category guard is the one that matters: LOBF
# is on Points and ABLOBF on Layout, so nothing folds one into the
# other, and a family can never straddle two panels.

#: (kind, affix) -> a command wearing this affix is a variant of the
#: command underneath it.  Each is written for a case that really
#: exists; none fires unless it lands on a real sibling.
VARIANT_AFFIXES = (
    ("suffix", "COVER"),   # POOLCOVER -> POOL, ABHDCOVER -> ABHD
    ("suffix", "SCAN"),    # ABCURCHECKSCAN -> ABCURCHECK
    ("prefix", "LITE"),    # LITECOVERSCAN -> COVERSCAN
    ("prefix", "ALT"),     # ALTABCDEF -> ABCDEF
    ("prefix", "SIMP"),    # SIMPABHD -> ABHD
    ("prefix", "C"),       # CPERPPTS -> PERPPTS, CABHD -> ABHD
)

#: The families no affix rule describes, because the variant is not
#: spelled off its primary's name.  Editorial, and short on purpose: an
#: entry here is a claim that two tools are one tool with something
#: changed, and a wrong one hides a tool a drafter would go looking for.
#:
#: What is deliberately NOT here: CORNERSTP / HEMISTEP / NORMIESTEP.
#: Three step SHAPES are three tools that do parallel things, not three
#: versions of one, and picking which of them wears the face of a
#: flyout would be an invention rather than a reading.
NAMED_VARIANTS = {
    "POOLDEMO": "POOL",            # POOL, run on a worked example
    "LAZTXT": "LAZFORM",           # LAZFORM's chart, drawn in tiles
    "MOHAMADDLE": "PADDLE",        # PADDLE, with a size pick first
    "HONEFILLET": "SMARTFILLET",   # SMARTFILLET, honed between two radii
    "AUTODIMSIDEPOV": "AUTODIM",   # AUTODIM, for a side-view flight
}


#: The routines that get a GLYPH of their own, and how big a button
#: they wear it on.
#:
#: A ribbon is not a list.  What it can do that the palette cannot is
#: let a drafter reach a tool by SHAPE, without reading -- and that only
#: works for a tool they reach for often enough to learn the shape of.
#: Drawing a glyph for all 67 buttons would spend the distinction it is
#: made of: 67 pictures nobody can tell apart is the same failure as one
#: picture repeated 67 times, which is what this surface shipped with.
#:
#: So this is editorial, exactly like NAMED_VARIANTS above, and it is
#: the shop's own answer to "which ones do you actually run".  A name
#: NOT here still has a button, still has its dropdown and still reads
#: its caption in the tooltip -- it is a plain text button, which is
#: what most of AutoCAD's own ribbon is made of too.
#:
#: The size is the second half of the decision, and it is a separate
#: one.  LARGE is a full-height button, the glyph at 32 with the command
#: under it; SMALL is an ordinary row with the glyph at 16 beside the
#: name.  Checking is every routine on its panel and all of them SMALL:
#: 14 large buttons made it the widest panel on the tab at 1120px, which
#: is a lot of strip to spend on the things you run after the drawing is
#: done.  They keep their pictures -- a review pass is still easier to
#: find by shape -- on a row a third the height.
#:
#: Three guards, all in featured(): a name here must be a real command
#: on the panel; it must be a PRIMARY, the face of its own button rather
#: than a variant riding in a dropdown, because a glyph drawn for a
#: variant is a glyph no button ever shows; and its size must be one of
#: the two.  tools/gen_ribbon_icons.py reads the same table, so a name
#: here without a glyph -- or a glyph without a name here -- fails
#: make check in either direction.

LARGE = "large"
SMALL = "small"

FEATURED = {
    # Layout -- the shapes the shop draws
    "POOL": LARGE, "OASIS": LARGE, "ABHD": LARGE, "SPA": LARGE,
    "PADDLE": LARGE, "CUSTBLOCK": LARGE,
    "LAZSTEP": LARGE, "CORNERSTP": LARGE, "HEMISTEP": LARGE,
    "NORMIESTEP": LARGE,
    # Points -- the survey work
    "ABFIND": LARGE, "ABMOVE": LARGE, "PERPPTS": LARGE,
    # Dimensions -- the callouts and the stamp
    "AUTODIM": LARGE, "CDCREATE": LARGE, "CDCALLOUT": LARGE,
    "BPCALLOUT": LARGE, "DIMSTAMP": LARGE,
    # Converters -- all four; the panel is four buttons wide either way
    "XFTCONV": LARGE, "SOCONV": LARGE, "VSCONV": LARGE, "G2MCONV": LARGE,
    # Checking -- every review pass and the two that read the record,
    # all of them small: see the note above about 1120px
    "CHECK": SMALL, "DIMARCCHECK": SMALL, "DIMCHECK": SMALL,
    "ABCURCHECK": SMALL, "OLAUTO": SMALL, "ABPCHECK": SMALL,
    "LINCHECK": SMALL, "LINFINCHECK": SMALL, "COVERCHECK": SMALL,
    "SPACHECK": SMALL, "LINTXTCHK": SMALL, "CCPRECHECK": SMALL,
    "LAZDIAG": SMALL, "LAZLOG": SMALL,
}


def featured(src=None):
    """FEATURED, in panel order, as [(category, command, size), ...].

    Ordered rather than a mapping so the icon generator and the catalog
    walk the same list in the same order, and so a diff of either reads
    like the panel does.

    Raises if a name is not a real command on the panel, if it names a
    variant instead of the button it rides on, or if its size is not one
    of the two: a glyph drawn for a command no button shows is work that
    vanishes silently, which is the one way this table can be wrong
    without anything looking wrong.
    """
    bad_size = sorted(c for c, z in FEATURED.items()
                      if z not in (LARGE, SMALL))
    if bad_size:
        raise SystemExit(
            "gen_ui_data: FEATURED gives %d command(s) a size that is "
            "neither LARGE nor SMALL: %s"
            % (len(bad_size), ", ".join(bad_size)))

    src = read(PANEL) if src is None else src
    pg = pages(src)
    if pg is None:
        raise SystemExit(
            "gen_ui_data: cannot read LAZPANEL's lzp:*groups* table")

    out, seen = [], set()
    for group in GROUPS:
        cmds = [c for names_ in pg.get(group, {}).values() for c in names_]
        for primary, _variants in families(cmds):
            if primary in FEATURED:
                out.append((group, primary, FEATURED[primary]))
                seen.add(primary)

    missing = sorted(set(FEATURED) - seen)
    if missing:
        raise SystemExit(
            "gen_ui_data: FEATURED names %d command(s) that are not the "
            "face of any ribbon button: %s\n"
            "  Each is either absent from LAZPANEL's roster, or a "
            "variant riding in another tool's dropdown.  A glyph drawn "
            "for one would never be shown."
            % (len(missing), ", ".join(missing)))
    return out


def variant_of(cmd, roster):
    """The command CMD is a variant OF, or None.

    ROSTER is the set of commands in CMD's own category: every rule is
    guarded by it, so a rule can neither invent a base nor reach into
    another panel to find one."""
    base = NAMED_VARIANTS.get(cmd)
    if base:
        return base if base in roster else None

    for kind, affix in VARIANT_AFFIXES:
        if kind == "suffix" and cmd.endswith(affix):
            base = cmd[:-len(affix)]
        elif kind == "prefix" and cmd.startswith(affix):
            base = cmd[len(affix):]
        else:
            continue
        if base and base in roster:
            return base

    # The undo half of a converter: XFTRECONV is XFTCONV run backwards,
    # and neither is spelled off the other by an affix on the whole name.
    if cmd.endswith("RECONV"):
        base = cmd[:-len("RECONV")] + "CONV"
        if base in roster:
            return base

    # A scan is the check with nothing marked: COVERSCAN reports what
    # COVERCHECK walks you through.  The stem is shared rather than one
    # name sitting inside the other, so the affix rules cannot see it.
    if cmd.endswith("SCAN"):
        base = cmd[:-len("SCAN")] + "CHECK"
        if base in roster:
            return base

    return None


def families(cmds):
    """CMDS, an ordered category roster, as [(primary, [variant, ...])].

    A family keeps its PRIMARY's position in the panel, and its variants
    keep theirs relative to each other, so the ribbon reads in the order
    LAZPANEL already lists the category in.  Every command comes back
    exactly once -- as a face or as a dropdown row -- which is the
    property tests/test_ribbon_catalog.py holds: a tool that fell into
    the wrong family is a nuisance, and a tool that fell out of all of
    them is unreachable."""
    roster = set(cmds)

    def root(cmd):
        seen = {cmd}
        while True:
            base = variant_of(cmd, roster)
            if base is None or base in seen:
                return cmd
            cmd = base
            seen.add(cmd)

    out = []
    index = {}
    for cmd in cmds:
        primary = root(cmd)
        if primary not in index:
            index[primary] = len(out)
            out.append((primary, []))
        if cmd != primary:
            out[index[primary]][1].append(cmd)
    return out


def blurbs(path=BLURBS):
    """{COMMAND: tooltip} out of the hand-edited blurb file."""
    out = {}
    for line in read(path).splitlines():
        line = line.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cmd, _, text = line.partition(" ")
        text = text.strip()
        if cmd and text:
            out[cmd] = text
    return out


def howto(path=HOWTO):
    """{COMMAND: fuller explanation} out of the hand-edited howto file --
    one multi-line block per command, "== COMMAND ==" then its text up
    to the next such heading or the end of file."""
    out = {}
    cmd = None
    body = []

    def flush():
        if cmd is not None:
            text = "\n".join(body).strip("\n")
            if text:
                out[cmd] = text

    for line in read(path).splitlines():
        if line.startswith("== ") and line.endswith(" =="):
            flush()
            cmd = line[3:-3].strip()
            body = []
        elif cmd is not None:
            body.append(line)
    flush()
    return out


# ------------------------------------------------------------- emitting

def vbstr(s):
    """S as a VB string literal.  VB escapes a quote by doubling it and
    has no backslash escape at all, so a path or a 3\" lap needs nothing
    else done to it.  A VB string literal cannot itself hold a newline,
    which the howto text often has, so a multi-line S is written as
    consecutive literals joined by " & vbLf & " instead -- a plain
    single-line S (everything but HowTo, today) round-trips through
    this unchanged."""
    if "\n" not in s:
        return '"' + s.replace('"', '""') + '"'
    return " & vbLf & ".join(
        '"' + part.replace('"', '""') + '"' for part in s.split("\n"))


def entry(cmd, caption, blurb, howto_text, tutorial, indent):
    return "%sNew Entry(%s, %s, %s, %s, %s)" % (
        indent, vbstr(cmd), vbstr(caption), vbstr(blurb),
        vbstr(howto_text), vbstr(tutorial))


def build(src=None, blurb=None, howto_map=None):
    """The generated VB source, as text."""
    src = read(PANEL) if src is None else src
    caps = captions(src)
    pg = pages(src)
    if caps is None or pg is None:
        raise SystemExit(
            "gen_ui_data: cannot read LAZPANEL's roster tables - has "
            "lzp:*captions* or lzp:*groups* been renamed?")
    blurb = blurbs() if blurb is None else blurb
    howto_map = howto() if howto_map is None else howto_map
    tuts = tutorials(src)

    def blurb_of(cmd):
        # A caption is never nothing (test_lazpanel.py refuses a blank
        # one), so the fallback is always a sentence rather than an
        # empty tooltip.
        return blurb.get(cmd) or caps.get(cmd, cmd)

    def howto_of(cmd):
        # lzp:howto's own fallback, mirrored: a command with no howto.txt
        # block falls back to its blurb rather than showing blank.
        return howto_map.get(cmd) or blurb_of(cmd)

    L = []
    add = L.append
    add("' SPDX-License-Identifier: GPL-3.0-or-later")
    add("'")
    add("' GENERATED FILE - DO NOT EDIT.  Your change will vanish.")
    add("'")
    add("'   written by : tools/gen_ui_data.py")
    add("'   from       : lisp/lazpanel/LAZPANEL.lsp  (lzp:*captions*,")
    add("'                lzp:*groups*, lzp:*tutorials*) and")
    add("'                ui/calofin_net/blurbs.txt, ui/calofin_net/howto.txt")
    add("'   regenerate : python3 tools/gen_ui_data.py")
    add("'   checked by : python3 tools/gen_ui_data.py --check, which")
    add("'                make check runs")
    add("'")
    add("' The panel and the palette offer the same routines under the same")
    add("' captions because this file is the panel's own tables, transcribed.")
    add("' To add a tool: put it on LAZPANEL, write its blurb in blurbs.txt,")
    add("' and re-run the generator.")
    add("")
    add("Imports System.Collections.Generic")
    add("")
    add("")
    add("''' <summary>")
    add("''' Every routine the palette offers, in the panel's own words.")
    add("'''")
    add("''' <para>Four views of one roster: <see cref=\"All\"/> is every")
    add("''' command once, <see cref=\"Groups\"/> is the category")
    add("''' pages the Commands tab lists, <see cref=\"Pages\"/> is the")
    add("''' whole tab strip including the job pages, and")
    add("''' <see cref=\"CaptionOf\"/> resolves one name.</para>")
    add("''' </summary>")
    add("Public NotInheritable Class CommandCatalog")
    add("")
    add("    Private Sub New()")
    add("    End Sub")
    add("")
    add("    ''' <summary>One routine: the command, its caption, its")
    add("    ''' tooltip, the fuller step-by-step explanation Find's How")
    add("    ''' it works shows, and the TUTORIAL* command for Find's")
    add("    ''' Tutorial button -- \"\" when this command has none.</summary>")
    add("    Public Structure Entry")
    add("        Public ReadOnly Command As String")
    add("        Public ReadOnly Caption As String")
    add("        Public ReadOnly Blurb As String")
    add("        Public ReadOnly HowTo As String")
    add("        Public ReadOnly TutorialCommand As String")
    add("")
    add("        Public Sub New(command As String, caption As String, blurb As String,")
    add("                       howTo As String, tutorialCommand As String)")
    add("            Me.Command = command")
    add("            Me.Caption = caption")
    add("            Me.Blurb = blurb")
    add("            Me.HowTo = howTo")
    add("            Me.TutorialCommand = tutorialCommand")
    add("        End Sub")
    add("    End Structure")
    add("")
    add("    ''' <summary>One column of a page: a heading and the commands")
    add("    ''' under it.  A heading of \"\" means the page is one plain")
    add("    ''' column, which is what the category pages are.</summary>")
    add("    Public Structure Column")
    add("        Public ReadOnly Heading As String")
    add("        Public ReadOnly Commands As String()")
    add("")
    add("        Public Sub New(heading As String, commands As String())")
    add("            Me.Heading = heading")
    add("            Me.Commands = commands")
    add("        End Sub")
    add("    End Structure")
    add("")
    add("    ''' <summary>One page of the panel's tab strip.</summary>")
    add("    Public Structure Page")
    add("        Public ReadOnly Title As String")
    add("        Public ReadOnly Columns As Column()")
    add("")
    add("        Public Sub New(title As String, columns As Column())")
    add("            Me.Title = title")
    add("            Me.Columns = columns")
    add("        End Sub")
    add("    End Structure")
    add("")

    # ---- All: every headline command once, alphabetically.  Find reads
    #      this one, and alphabetical is the order a list of everything
    #      wants when the search box is empty.
    names = sorted(caps)
    add("    ''' <summary>Every command once, alphabetically - the list")
    add("    ''' Find searches and the list an empty search shows.</summary>")
    add("    Public Shared ReadOnly All As Entry() = {")
    for i, cmd in enumerate(names):
        tail = "," if i < len(names) - 1 else ""
        add(entry(cmd, caps[cmd], blurb_of(cmd), howto_of(cmd),
                  tuts.get(cmd, ""), "        ") + tail)
    add("    }")
    add("")

    # ---- Groups: the category pages.
    add("    ''' <summary>The category pages, which are the palette's")
    add("    ''' groups: lzp:*groups* files every tool into exactly one, so")
    add("    ''' this is not a second opinion about where a tool")
    add("    ''' belongs.</summary>")
    add("    Public Shared ReadOnly Groups As New Dictionary(Of String, Entry()) From {")
    for gi, group in enumerate(GROUPS):
        cmds = [c for names_ in pg.get(group, {}).values() for c in names_]
        add('        {"%s", {' % group)
        for i, cmd in enumerate(cmds):
            tail = "," if i < len(cmds) - 1 else ""
            add(entry(cmd, caps.get(cmd, ""), blurb_of(cmd), howto_of(cmd),
                      tuts.get(cmd, ""), "            ") + tail)
        add("        }}" + ("," if gi < len(GROUPS) - 1 else ""))
    add("    }")
    add("")

    # ---- Pages: the whole strip, job pages included.  The palette has
    #      never offered these; they are what the panel opens on, and
    #      the reason a drafter can find a tool by the job rather than
    #      by what it is.
    add("    ''' <summary>Every page of the panel's tab strip, in its order:")
    add("    ''' the job pages first, then the categories.  A job page")
    add("    ''' carries a tool under the work it belongs to; a category")
    add("    ''' page answers what a tool IS.</summary>")
    add("    Public Shared ReadOnly Pages As Page() = {")
    items = list(pg.items())
    for pi, (title, cols) in enumerate(items):
        add('        New Page(%s, {' % vbstr(title))
        cols = list(cols.items())
        for ci, (heading, cmds) in enumerate(cols):
            names_ = ", ".join(vbstr(c) for c in cmds)
            add("            New Column(%s, {%s})%s"
                % (vbstr(heading), names_,
                   "," if ci < len(cols) - 1 else ""))
        add("        })" + ("," if pi < len(items) - 1 else ""))
    add("    }")
    add("")

    add("    ''' <summary>The caption for a command, or \"\" for a name the")
    add("    ''' panel does not carry.</summary>")
    add("    Public Shared Function CaptionOf(command As String) As String")
    add("        For Each e In All")
    add("            If String.Equals(e.Command, command, "
        "StringComparison.OrdinalIgnoreCase) Then Return e.Caption")
    add("        Next")
    add('        Return ""')
    add("    End Function")
    add("")
    add("End Class")
    return "\n".join(L) + "\n"


def csstr(s):
    """S as a C# string literal.  C# escapes a backslash and a quote
    with a leading backslash -- unlike VB, which doubles the quote and
    has no backslash escape at all -- so the two emitters cannot share
    one quoting function."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def entry_cs(cmd, caption, blurb):
    """One ``new Entry(...)``, with no indent and no trailing comma: it
    is a list element in one place and a constructor argument in
    another, and only the caller knows which."""
    return "new Entry(%s, %s, %s)" % (
        csstr(cmd), csstr(caption), csstr(blurb))


def build_cs(src=None, blurb=None):
    """The generated C# source, as text.

    Only the category table: the ribbon has one panel per
    Layout/Points/Dimensions/Converters/Checking group and no Find page
    or job pages to carry, so ``All``, ``Pages`` and ``CaptionOf`` --
    the VB catalog's other three views -- would be dead code here."""
    src = read(PANEL) if src is None else src
    caps = captions(src)
    pg = pages(src)
    if caps is None or pg is None:
        raise SystemExit(
            "gen_ui_data: cannot read LAZPANEL's roster tables - has "
            "lzp:*captions* or lzp:*groups* been renamed?")
    blurb = blurbs() if blurb is None else blurb
    featured(src)   # raises if FEATURED names a command no button shows

    def blurb_of(cmd):
        return blurb.get(cmd) or caps.get(cmd, cmd)

    L = []
    add = L.append
    add("// SPDX-License-Identifier: GPL-3.0-or-later")
    add("//")
    add("// GENERATED FILE - DO NOT EDIT.  Your change will vanish.")
    add("//")
    add("//   written by : tools/gen_ui_data.py")
    add("//   from       : lisp/lazpanel/LAZPANEL.lsp  (lzp:*captions*,")
    add("//                lzp:*groups*) and ui/calofin_net/blurbs.txt")
    add("//   regenerate : python3 tools/gen_ui_data.py")
    add("//   checked by : python3 tools/gen_ui_data.py --check, which")
    add("//                make check runs")
    add("//")
    add("// The ribbon and the VB palette's Commands tab offer the same")
    add("// routines under the same captions and the same categories,")
    add("// because both are generated from LAZPANEL's own tables -- this")
    add("// file carries only the category table, which is all the ribbon")
    add("// needs.  To add a tool: put it on LAZPANEL, write its blurb in")
    add("// blurbs.txt, and re-run the generator.")
    add("//")
    add("// A FEATURED routine has a glyph of its own, drawn by")
    add("// tools/gen_ribbon_icons.py off this same list, and wears it")
    add("// either on a full-height button or on an ordinary row; the")
    add("// rest are plain text buttons.  A ribbon is only faster than a")
    add("// list where a drafter knows the shape, and that is a thing")
    add("// you learn about tools you run -- so the list is short and")
    add("// editorial: gen_ui_data.FEATURED.")
    add("//")
    add("// Variants ride in their primary's dropdown rather than taking a")
    add("// button of their own -- POOLCOVER under POOL, XFTRECONV under")
    add("// XFTCONV -- which is what fits 94 commands onto five ribbon")
    add("// panels without hiding any of them.  Which is a variant of what")
    add("// is derived from the roster by gen_ui_data.variant_of; see the")
    add("// rules there.")
    add("")
    add("using System.Collections.Generic;")
    add("")
    add("namespace Calofin.Ribbon")
    add("{")
    add("    /// <summary>")
    add("    /// The category panels the ribbon builds, in LAZPANEL's own")
    add("    /// words.  lzp:*groups* files every tool into exactly one, so")
    add("    /// this is not a second opinion about where a tool belongs --")
    add("    /// it is the VB palette's own Groups table, written again in")
    add("    /// C# by the same generator so the ribbon needs no reference")
    add("    /// to the VB assembly to read it.")
    add("    /// </summary>")
    add("    public static class CommandCatalog")
    add("    {")
    add("        /// <summary>One routine: the command, its caption and")
    add("        /// its tooltip.</summary>")
    add("        public readonly struct Entry")
    add("        {")
    add("            public readonly string Command;")
    add("            public readonly string Caption;")
    add("            public readonly string Blurb;")
    add("")
    add("            public Entry(string command, string caption, string blurb)")
    add("            {")
    add("                Command = command;")
    add("                Caption = caption;")
    add("                Blurb = blurb;")
    add("            }")
    add("        }")
    add("")
    add("        /// <summary>One button on a panel: the routine on its face,")
    add("        /// and the variants of that routine behind its dropdown.")
    add("        /// No variants means a plain button, not a split one.")
    add("        ///")
    add("        /// HasIcon says a glyph was drawn for this routine and")
    add("        /// sits beside the assembly as cmd-<name>-16/32.png;")
    add("        /// IsLarge says it wears it on a full-height button")
    add("        /// rather than an ordinary row.  IsLarge implies")
    add("        /// HasIcon -- only a routine with a picture can be")
    add("        /// large.  Both come off gen_ui_data.FEATURED, which")
    add("        /// tools/gen_ribbon_icons.py reads too, so a button can")
    add("        /// never be left asking for a picture nobody drew.")
    add("        /// </summary>")
    add("        public readonly struct Item")
    add("        {")
    add("            public readonly Entry Primary;")
    add("            public readonly Entry[] Variants;")
    add("            public readonly bool HasIcon;")
    add("            public readonly bool IsLarge;")
    add("")
    add("            public Item(Entry primary, Entry[] variants,")
    add("                        bool hasIcon, bool isLarge)")
    add("            {")
    add("                Primary = primary;")
    add("                Variants = variants;")
    add("                HasIcon = hasIcon;")
    add("                IsLarge = isLarge;")
    add("            }")
    add("        }")
    add("")
    add("        /// <summary>The category panels, keyed by LAZPANEL's own")
    add("        /// names.  Every command in a category appears exactly once")
    add("        /// across its Items -- on a face or in a dropdown.</summary>")
    add("        public static readonly Dictionary<string, Item[]> Panels =")
    add("            new Dictionary<string, Item[]>")
    add("        {")
    for group in GROUPS:
        cmds = [c for names_ in pg.get(group, {}).values() for c in names_]
        add('            { %s, new[]' % csstr(group))
        add("            {")
        for primary, variants in families(cmds):
            face = entry_cs(primary, caps.get(primary, ""),
                            blurb_of(primary))
            size = FEATURED.get(primary)
            flags = "%s, %s" % ("true" if size else "false",
                                "true" if size == LARGE else "false")
            if not variants:
                add("                new Item(%s, new Entry[0], %s),"
                    % (face, flags))
                continue
            add("                new Item(%s, new[]" % face)
            add("                {")
            for v in variants:
                add("                    %s,"
                    % entry_cs(v, caps.get(v, ""), blurb_of(v)))
            add("                }, %s)," % flags)
        add("            } },")
    add("        };")
    add("    }")
    add("}")
    return "\n".join(L) + "\n"


# --------------------------------------------------------------- driver

def check():
    """Problems as a list of strings, empty when the file is current."""
    problems = []
    want = build()
    if not OUT.is_file():
        problems.append("%s: missing - run python3 tools/gen_ui_data.py"
                         % OUT.relative_to(ROOT))
    elif read(OUT) != want:
        problems.append(
            "%s: stale - it is not what tools/gen_ui_data.py would "
            "write now.  Regenerate: python3 tools/gen_ui_data.py"
            % OUT.relative_to(ROOT))

    want_cs = build_cs()
    if not OUT_CS.is_file():
        problems.append("%s: missing - run python3 tools/gen_ui_data.py"
                         % OUT_CS.relative_to(ROOT))
    elif read(OUT_CS) != want_cs:
        problems.append(
            "%s: stale - it is not what tools/gen_ui_data.py would "
            "write now.  Regenerate: python3 tools/gen_ui_data.py"
            % OUT_CS.relative_to(ROOT))
    return problems


def blurb_gaps():
    """Commands the panel carries that blurbs.txt has no line for."""
    caps = captions(read(PANEL)) or {}
    have = blurbs()
    return sorted(set(caps) - set(have)), sorted(set(have) - set(caps))


def howto_gaps():
    """Commands the panel carries that howto.txt has no block for.  Not
    an error the way a missing blurb is -- lzp:howto falls back to the
    blurb -- so main() reports these as notes, same tone as blurb_gaps."""
    caps = captions(read(PANEL)) or {}
    have = howto()
    return sorted(set(caps) - set(have)), sorted(set(have) - set(caps))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="report staleness instead of writing")
    args = ap.parse_args(argv)

    missing, extra = blurb_gaps()
    notes = []
    for c in missing:
        notes.append("blurbs.txt: no blurb for %s - it falls back to its "
                     "caption; add a line" % c)
    for c in extra:
        notes.append("blurbs.txt: %s is not a panel command - remove the "
                     "line" % c)
    missing, extra = howto_gaps()
    for c in missing:
        notes.append("howto.txt: no block for %s - it falls back to its "
                     "blurb; add a \"== %s ==\" block" % (c, c))
    for c in extra:
        notes.append("howto.txt: %s is not a panel command - remove the "
                     "block" % c)

    if args.check:
        problems = check() + notes
        for p in problems:
            print(p)
        if problems:
            return 1
        print("gen_ui_data: %s current, %d commands, %d groups, %d pages"
              % (OUT.relative_to(ROOT), len(captions(read(PANEL))),
                 len(GROUPS), len(pages(read(PANEL)))))
        return 0

    text = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    changed = not OUT.is_file() or read(OUT) != text
    OUT.write_text(text, encoding="utf-8")

    text_cs = build_cs()
    OUT_CS.parent.mkdir(parents=True, exist_ok=True)
    changed_cs = not OUT_CS.is_file() or read(OUT_CS) != text_cs
    OUT_CS.write_text(text_cs, encoding="utf-8")

    for n in notes:
        print(n)
    print("gen_ui_data: %s %s (%d commands, %d pages)"
          % (OUT.relative_to(ROOT), "written" if changed else "unchanged",
             len(captions(read(PANEL))), len(pages(read(PANEL)))))
    print("gen_ui_data: %s %s (%d commands, %d groups)"
          % (OUT_CS.relative_to(ROOT), "written" if changed_cs else "unchanged",
             len(captions(read(PANEL))), len(GROUPS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
