"""The palette's shell against LAZPANEL's, where the two must agree.

The VB palette and the DCL panel are now the same panel on different
plumbing: both find a tool by any part of its name or caption, both
remember the last five launched and whatever is pinned, and both offer
the panel's whole tab strip.  Nothing here can run the VB, so what is
checked is the seam -- the places where "the same" is a fact about text
in two files and would otherwise rot quietly.

1. **They remember in the same place.**  The palette writes LAZPANEL's
   registry key, LAZPANEL's value names, LAZPANEL's ";"-joined format
   and LAZPANEL's cap of five.  A drafter has one set of pins; which
   surface they pinned from should not be something they can tell.  Move
   ``lzp:*pinkey*`` and this fails rather than silently splitting the
   two stores in half.
2. **They say the same words.**  Every message the Find page can print
   -- the count line, the no-match line, "(not loaded)", the two
   refusals -- is read out of LAZPANEL and required to appear in the VB.
   The strings are lifted from the Lisp, never typed here, so re-wording
   one surface fails until the other follows.
3. **They drop a stale name the same way.**  ``lzp:pins-read`` filters
   what it reads through the roster, because a pin left over from an
   older build must not put a dead button on screen.  A copy that
   forgets that rule is a bug the drafter sees and nobody else does.

Run: python3 tests/test_palette_shell.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from lispvm import VM  # noqa: E402
from callib import ROOT, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


PANEL = ROOT / 'lisp' / 'lazpanel' / 'LAZPANEL.lsp'
MEMORY = ROOT / 'ui' / 'calofin_net' / 'PaletteMemory.vb'
TAB = ROOT / 'ui' / 'calofin_net' / 'CalofinPalette.vb'

PANEL_SRC = read(PANEL)
MEM = read(MEMORY)
VB = read(TAB)

vm = VM()
vm.load(PANEL)


def vb_literal(text):
    """TEXT as it would be spelled inside a VB string literal.  VB has no
    backslash escape and doubles a quote instead."""
    return text.replace('"', '""')


print("== 1. one store, shared with the panel ==")

pinkey = str(vm.globals['lzp:*pinkey*'])
check("the palette writes LAZPANEL's own registry key",
      vb_literal(pinkey) in MEM, pinkey)

values = set(re.findall(r'lzp:\*pinkey\*\s+"([A-Za-z]+)"', PANEL_SRC))
check("the panel keeps exactly two values there",
      values == {'Pins', 'Recent'}, repr(sorted(values)))
for v in sorted(values):
    check("the palette reads and writes %r too" % v,
          ('"%s"' % v) in MEM)

limit = vm.globals['lzp:*reclimit*']
check("the same cap on Recent",
      re.search(r"RecentLimit As Integer = %d\b" % int(limit), MEM)
      is not None, "lzp:*reclimit* is %s" % limit)

# lzp:pins-write joins with ";" and lzp:split takes it apart again
check("the panel splits and joins on ';'",
      '(lzp:split s ";")' in PANEL_SRC
      and '(strcat s (if (= s "") "" ";") n)' in PANEL_SRC)
check("the palette splits and joins on the same ';'",
      '";"c' in MEM and 'String.Join(";"' in MEM)

# Recent is newest-first on both sides: lzp:remember conses onto the
# front, and the palette inserts at 0
check("newest first, both sides",
      '(cons name (vl-remove name lzp:*recent*))' in PANEL_SRC
      and 'rec.Insert(0, c)' in MEM)


print("== 2. the same words on the Find page ==")


def literals_of(defun):
    """Every message a LAZPANEL defun can print, longest first.

    A literal with no space in it is a DCL tile key -- "msg", "hits" --
    and not a message at all.  Letting those through would pass on
    coincidence: "msg" is a substring of half the identifiers in any
    file that has a message line.
    """
    i = PANEL_SRC.index("(defun %s " % defun)
    j = PANEL_SRC.index("\n(defun ", i + 1)
    body = PANEL_SRC[i:j]
    out = set()
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', body):
        text = m.group(1).replace('\\"', '"').replace('\\\\', '\\')
        if len(text.strip()) >= 3 and " " in text:
            out.add(text)
    return sorted(out, key=len, reverse=True)


for fn in ('lzp:hitline', 'lzp:findmsg', 'lzp:findrun'):
    for text in literals_of(fn):
        check("%-14s %r" % (fn, text), vb_literal(text) in VB)

# the panel calls it "(not loaded)" on the list and greys it on a page;
# the palette has to do BOTH, and they are different code paths
check("a page greys what is missing", 'IsEnabled = IsLoaded' in VB)
check("the Find list refuses it instead, with the reason",
      'is not loaded in this session' in VB)


print("== 3. a stale pin is dropped, not drawn ==")

check("the panel filters what it reads through the roster",
      "vl-remove-if-not '(lambda (n) (member n (lzp:commands)))"
      in PANEL_SRC)
for fn in ('Pins', 'Recent'):
    body = re.search(r"Public Shared Function %s\(\) As List\(Of String\)"
                     r"(.*?)End Function" % fn, MEM, re.S)
    check("PaletteMemory.%s filters through the roster too" % fn,
          body is not None and 'OnRoster' in body.group(1))

# and the roster it filters against is the generated catalog, which is
# LAZPANEL's own -- so "on the roster" means the same thing on both
check("the roster is the generated catalog",
      'For Each e In CommandCatalog.All' in MEM)


print("== 4. the search is literal, and it reads captions too ==")

check("the panel spells the substring search out rather than wcmatch",
      '(defun lzp:instr ' in PANEL_SRC and 'wcmatch' not in
      PANEL_SRC[PANEL_SRC.index('(defun lzp:instr '):
                PANEL_SRC.index('(defun lzp:matches ')])
check("the palette uses Contains, not a pattern matcher",
      '.Contains(needle)' in VB and 'Regex' not in VB)
check("both search the caption as well as the name",
      '(lzp:instr (strcase (lzp:caption n)) up)' in PANEL_SRC
      and 'e.Caption.ToUpperInvariant().Contains(needle)' in VB)

# lzp:fill selects the top hit so a search and Enter runs it
check("the top hit is selected for you, both sides",
      '(set_tile "hits" "0")' in PANEL_SRC
      and '_hits.SelectedIndex = 0' in VB)


print("== 5. every page of the strip, not just the categories ==")

pages = [str(g[0]) for g in vm.globals['lzp:*groups*']]
check("the panel has the four job pages and the four categories",
      pages == ['Pool', 'Cover', 'Spa', 'Rest', 'Layout', 'Points',
                'Dimensions', 'Checking'], repr(pages))
check("the palette builds a tab per page of the catalog",
      'For Each page In CommandCatalog.Pages' in VB)
check("and remembers which one it was left on",
      'PaletteMemory.SetPage' in VB and 'PaletteMemory.Page()' in VB)


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL PALETTE SHELL CHECKS PASSED")
