"""The palette's generated tables, against the tables they come from.

``ui/calofin_net/Generated/CommandCatalog.g.vb`` is written by
tools/gen_ui_data.py from LAZPANEL's own ``lzp:*captions*`` and
``lzp:*groups*``.  That is the fix for a real failure: the palette used
to type its own copy of the roster, it shipped 60 of the panel's 67
commands, every caption it DID carry still agreed, and nothing anywhere
said the two had parted.

A generator only moves the risk, though -- from a forgotten edit to a
generator that transcribes wrongly, which would be just as invisible.
So this reads the VB back out and holds it to the panel:

1. Every command on the panel is in the catalog, with the panel's own
   caption, in the panel's own category.
2. Every page of the tab strip is carried, in order, with its columns
   and their commands -- the job pages included, which the palette
   never used to have at all.
3. Every blurb in the file is the blurb blurbs.txt gives, and every
   command has one; the fallback exists but nothing should be using it.
4. The file on disk is what the generator would write now, and the
   VB it writes is well formed (check_vb agrees) -- the two halves of
   "current" that nothing else here can see.

Reading the VB rather than calling the generator's own build() is the
point: a test that asked the generator what it generates would agree
with itself no matter what it emitted.

Run: python3 tests/test_ui_data.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_registry as cr  # noqa: E402
import check_vb  # noqa: E402
import gen_ui_data  # noqa: E402
from callib import read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


SRC = read(gen_ui_data.OUT)
PANEL = read(cr.PANEL)
CAPS = cr.captions(PANEL)
PAGES = cr.pages(PANEL)
BLURBS = gen_ui_data.blurbs()


# --------------------------------------------------------------------
# Reading the generated VB back.  These parsers are deliberately not
# the generator's emitters: a round trip through the same code proves
# nothing.
# --------------------------------------------------------------------

def vb_entries(block):
    """[(command, caption, blurb)] out of a run of New Entry(...) calls."""
    return [(m.group(1), m.group(2), m.group(3))
            for m in cr.VB_ENTRY.finditer(block)]


def section(name, opener, closer='\n    }'):
    """The body of one Shared table in the generated file."""
    i = SRC.index(opener)
    j = SRC.index(closer, i)
    return SRC[i:j]


print("== 1. every command, with the panel's caption and category ==")

all_block = section('All', 'ReadOnly All As Entry() = {')
all_entries = vb_entries(all_block)
check("All carries every command once",
      sorted(e[0] for e in all_entries) == sorted(CAPS),
      "%d in the file, %d on the panel" % (len(all_entries), len(CAPS)))
check("All is alphabetical",
      [e[0] for e in all_entries] == sorted(e[0] for e in all_entries))

wrong = [(c, cap, CAPS.get(c)) for c, cap, _ in all_entries
         if cap != CAPS.get(c)]
check("every caption is the panel's own", not wrong, repr(wrong[:3]))

groups_block = section('Groups', 'ReadOnly Groups As New Dictionary')
by_group = {m.group(1): dict((e[0], e[1]) for e in vb_entries(m.group(2)))
            for m in cr.VB_GROUP.finditer(groups_block)}
check("the four category pages are the palette's groups",
      sorted(by_group) == sorted(cr.CATEGORIES), repr(sorted(by_group)))

for group in cr.CATEGORIES:
    want = [c for names in PAGES.get(group, {}).values() for c in names]
    check("%s carries the panel's %d" % (group, len(want)),
          sorted(by_group.get(group, {})) == sorted(want),
          repr(sorted(set(want) ^ set(by_group.get(group, {})))))

filed = [c for g in by_group.values() for c in g]
check("no command is filed under two categories",
      len(filed) == len(set(filed)))
check("every command is filed somewhere",
      set(filed) == set(CAPS),
      repr(sorted(set(CAPS) - set(filed))))


print("== 2. the whole tab strip, pages and columns, in order ==")

pages_block = section('Pages', 'ReadOnly Pages As Page() = {')
vb_pages = []
for m in re.finditer(r'New Page\("([^"]*)", \{(.*?)\n        \}\)',
                     pages_block, re.S):
    cols = [(c.group(1), re.findall(r'"([^"]+)"', c.group(2)))
            for c in re.finditer(r'New Column\("([^"]*)", \{(.*?)\}\)',
                                 m.group(2))]
    vb_pages.append((m.group(1), cols))

check("every page, in the panel's order",
      [p for p, _ in vb_pages] == list(PAGES),
      "%r vs %r" % ([p for p, _ in vb_pages], list(PAGES)))

for title, cols in vb_pages:
    want = PAGES[title]
    check("%-11s %d column(s), %d button(s)"
          % (title, len(cols), sum(len(c) for _, c in cols)),
          [(h, list(cs)) for h, cs in cols]
          == [(h, list(cs)) for h, cs in want.items()],
          repr(cols))

job = [p for p, _ in vb_pages if p not in cr.CATEGORIES]
check("the job pages are carried too - the palette never had them",
      job == ['Pool', 'Cover', 'Spa', 'Rest'], repr(job))


print("== 3. the blurbs are read, never invented ==")

blurb_of = {c: b for c, _, b in all_entries}
check("every command has a blurb line of its own",
      not sorted(set(CAPS) - set(BLURBS)),
      repr(sorted(set(CAPS) - set(BLURBS))[:5]))
check("blurbs.txt names no command the panel does not",
      not sorted(set(BLURBS) - set(CAPS)),
      repr(sorted(set(BLURBS) - set(CAPS))[:5]))
bad = [c for c, b in blurb_of.items() if b != BLURBS.get(c, CAPS.get(c))]
check("every blurb in the file is the one blurbs.txt gives", not bad,
      repr(bad[:3]))
check("a blurb is never empty", all(b.strip() for b in blurb_of.values()))

# The same caption on every surface is the whole point; a blurb that is
# only the caption again is a tooltip that says nothing new.
echo = [c for c, b in blurb_of.items() if b == CAPS.get(c)]
check("no blurb is just the caption repeated", not echo, repr(echo[:3]))


print("== 4. the file is current, and it is well-formed VB ==")

check("gen_ui_data --check is happy", not gen_ui_data.check(),
      repr(gen_ui_data.check()))
_, vb_problems = check_vb.check()
check("check_vb passes over the whole palette", not vb_problems,
      repr(vb_problems[:3]))

# The seam that a generator makes and nothing else would catch: the
# hand-written palette names members of the generated class.  Rename
# one and this is where it shows.
types = check_vb.declared(check_vb.vb_files())
check("CommandCatalog declares what the palette reads",
      {'All', 'Groups', 'Pages', 'CaptionOf', 'Entry', 'Column', 'Page'}
      <= types.get('CommandCatalog', {}).get('members', set())
      | set(types),
      repr(sorted(types.get('CommandCatalog', {}).get('members', ()))))

# through check_vb's lexer, not the raw text: the file's own comments
# name Generated\CommandCatalog.g.vb, and a regex over the source reads
# that filename as a member called "g"
used = set()
for _row in check_vb.logical_lines(
        read(cr.ROOT / 'ui' / 'calofin_net' / 'CalofinPalette.vb')):
    used |= set(re.findall(r'CommandCatalog\.(\w+)', _row[1]))
check("every CommandCatalog member the palette uses exists",
      used <= types['CommandCatalog']['members'],
      repr(sorted(used - types['CommandCatalog']['members'])))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL UI DATA CHECKS PASSED (%d commands, %d pages)"
      % (len(CAPS), len(PAGES)))
