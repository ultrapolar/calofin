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
from check_registry import CATEGORIES, PANEL, captions, pages  # noqa: E402

BLURBS = ROOT / "ui" / "calofin_net" / "blurbs.txt"
OUT = ROOT / "ui" / "calofin_net" / "Generated" / "CommandCatalog.g.vb"

#: What the palette's Commands tab shows as its groups.  They ARE the
#: panel's four category pages -- lzp:*groups* files every tool into
#: exactly one of them -- so the palette's grouping is not a second
#: opinion about where a tool belongs.
GROUPS = CATEGORIES


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


# ------------------------------------------------------------- emitting

def vbstr(s):
    """S as a VB string literal.  VB escapes a quote by doubling it and
    has no backslash escape at all, so a path or a 3\" lap needs nothing
    else done to it."""
    return '"' + s.replace('"', '""') + '"'


def entry(cmd, caption, blurb, indent):
    return "%sNew Entry(%s, %s, %s)" % (
        indent, vbstr(cmd), vbstr(caption), vbstr(blurb))


def build(src=None, blurb=None):
    """The generated VB source, as text."""
    src = read(PANEL) if src is None else src
    caps = captions(src)
    pg = pages(src)
    if caps is None or pg is None:
        raise SystemExit(
            "gen_ui_data: cannot read LAZPANEL's roster tables - has "
            "lzp:*captions* or lzp:*groups* been renamed?")
    blurb = blurbs() if blurb is None else blurb

    def blurb_of(cmd):
        # A caption is never nothing (test_lazpanel.py refuses a blank
        # one), so the fallback is always a sentence rather than an
        # empty tooltip.
        return blurb.get(cmd) or caps.get(cmd, cmd)

    L = []
    add = L.append
    add("' SPDX-License-Identifier: GPL-3.0-or-later")
    add("'")
    add("' GENERATED FILE - DO NOT EDIT.  Your change will vanish.")
    add("'")
    add("'   written by : tools/gen_ui_data.py")
    add("'   from       : lisp/lazpanel/LAZPANEL.lsp  (lzp:*captions*,")
    add("'                lzp:*groups*) and ui/calofin_net/blurbs.txt")
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
    add("''' command once, <see cref=\"Groups\"/> is the four category")
    add("''' pages the Commands tab lists, <see cref=\"Pages\"/> is the")
    add("''' whole tab strip including the job pages, and")
    add("''' <see cref=\"CaptionOf\"/> resolves one name.</para>")
    add("''' </summary>")
    add("Public NotInheritable Class CommandCatalog")
    add("")
    add("    Private Sub New()")
    add("    End Sub")
    add("")
    add("    ''' <summary>One routine: the command, its caption and its")
    add("    ''' tooltip.</summary>")
    add("    Public Structure Entry")
    add("        Public ReadOnly Command As String")
    add("        Public ReadOnly Caption As String")
    add("        Public ReadOnly Blurb As String")
    add("")
    add("        Public Sub New(command As String, caption As String, blurb As String)")
    add("            Me.Command = command")
    add("            Me.Caption = caption")
    add("            Me.Blurb = blurb")
    add("        End Sub")
    add("    End Structure")
    add("")
    add("    ''' <summary>One column of a page: a heading and the commands")
    add("    ''' under it.  A heading of \"\" means the page is one plain")
    add("    ''' column, which is what the four category pages are.</summary>")
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
        add(entry(cmd, caps[cmd], blurb_of(cmd), "        ") + tail)
    add("    }")
    add("")

    # ---- Groups: the four category pages.
    add("    ''' <summary>The four category pages, which are the palette's")
    add("    ''' groups: lzp:*groups* files every tool into exactly one, so")
    add("    ''' this is not a second opinion about where a tool")
    add("    ''' belongs.</summary>")
    add("    Public Shared ReadOnly Groups As New Dictionary(Of String, Entry()) From {")
    for gi, group in enumerate(GROUPS):
        cmds = [c for names_ in pg.get(group, {}).values() for c in names_]
        add('        {"%s", {' % group)
        for i, cmd in enumerate(cmds):
            tail = "," if i < len(cmds) - 1 else ""
            add(entry(cmd, caps.get(cmd, ""), blurb_of(cmd),
                      "            ") + tail)
        add("        }}" + ("," if gi < len(GROUPS) - 1 else ""))
    add("    }")
    add("")

    # ---- Pages: the whole strip, job pages included.  The palette has
    #      never offered these; they are what the panel opens on, and
    #      the reason a drafter can find a tool by the job rather than
    #      by what it is.
    add("    ''' <summary>Every page of the panel's tab strip, in its order:")
    add("    ''' the job pages first, then the four categories.  A job page")
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


# --------------------------------------------------------------- driver

def check():
    """Problems as a list of strings, empty when the file is current."""
    want = build()
    if not OUT.is_file():
        return ["%s: missing - run python3 tools/gen_ui_data.py"
                % OUT.relative_to(ROOT)]
    if read(OUT) != want:
        return ["%s: stale - it is not what tools/gen_ui_data.py would "
                "write now.  Regenerate: python3 tools/gen_ui_data.py"
                % OUT.relative_to(ROOT)]
    return []


def blurb_gaps():
    """Commands the panel carries that blurbs.txt has no line for."""
    caps = captions(read(PANEL)) or {}
    have = blurbs()
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
    for n in notes:
        print(n)
    print("gen_ui_data: %s %s (%d commands, %d pages)"
          % (OUT.relative_to(ROOT), "written" if changed else "unchanged",
             len(captions(read(PANEL))), len(pages(read(PANEL)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
