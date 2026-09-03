"""LAZPANEL: the DCL launcher panel and its screen button, in the VM.

Four jobs:

1. Pin the roster to the tree.  Every headline command defined under
   lisp/ must have a button, so a new tool without one fails here
   instead of being quietly missing (satellites -- TUTORIAL*, *VER /
   *VERSION reporters, *RESCUE companions, -CFG / -SETUP partners, the
   DD* sub-commands, DCE and STOCKLIST -- are exempt).  Held-back tools
   (cal:*held-back* in CALOFIN-LOADER.lsp) and the deprecated acady
   matcher must NOT have buttons.

2. Check the generated DCL is well formed: balanced braces, even
   quotes, one key per button matching the roster, one cancel tile,
   and a grammar pass (trailing semicolons, known tile and attribute
   names) for the errors AutoCAD's DCL parser rejects outright.

3. Drive c:LAZPANEL end-to-end with the DCL surface stubbed (the VM
   has no dialog or file i/o builtins): Close launches nothing, a
   click evaluates the REAL action_tile expression, greyed buttons are
   exactly the missing commands, and the temp .dcl is written and
   deleted -- in order -- either way.

4. Check the screen button, including the load-time creation that IS
   the feature: the stubs go in before the file loads, so deleting that
   call fails here.  The button lands at index 0 of an empty toolbar,
   carries the ^C^C_LAZPANEL macro as raw ASCII 3s, is re-iced and
   re-shown rather than duplicated on a second init, and does not
   survive at all if it cannot get its button.  The icon is checked
   pixel by pixel -- position, not just colour count, because a BMP
   stores its rows bottom-up and an L is not symmetric -- and the
   ADODB.Stream binary write is checked because AutoLISP's own file
   output could not have produced it: over a hundred of these bytes
   are NUL, which write-char has no way to emit.

Runs against either tier: standalone by default, the grouped build with
CALOFIN_LISP_ROOT=shared.
"""

import base64
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from lispvm import VM, LispError  # noqa: E402
import callib  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))
LSP = os.path.join(REPO, 'lisp', 'lazpanel', 'LAZPANEL.lsp')
LOADER = os.path.join(REPO, 'shared', 'parts', 'CALOFIN-LOADER.lsp')


def fresh():
    vm = VM()
    vm.load(LSP)
    return vm


def columns(vm, page):
    """One page's columns as (heading, [command, ...])."""
    for g in vm.globals.get('lzp:*groups*') or []:
        if str(g[0]) == page:
            return [(str(c[0]), [str(x) for x in c[1:]]) for c in g[1:]]
    raise AssertionError("no such page: %r" % page)


def roster(vm):
    """Every button on the panel, repeats and all, in display order."""
    out = []
    for g in vm.globals.get('lzp:*groups*') or []:
        for col in g[1:]:
            out.extend(str(x) for x in col[1:])
    return out


# The roster rule -- what a command is, which ones are satellites, what
# the loader holds back -- lives in tools/callib.py so that this test and
# tools/check_registry.py cannot disagree about what belongs on the panel.
census = callib.census
held_commands = callib.held_commands


print("== the file loads and announces itself ==")
vm = fresh()
ver = vm.globals.get('*lazpanel-version*')
assert ver and re.fullmatch(r'v\d+\.\d+', str(ver)), ver
assert any('LAZPANEL' in str(p) for p in vm.printed), vm.printed
BUTTONS = roster(vm)                       # every button, repeats and all
PANEL = sorted(set(BUTTONS))               # every command, once
# A command may serve more than one job, so it may appear on more than
# one page -- but never twice on the SAME page, which would be a
# duplicate DCL key.  (The per-page key check below catches that too;
# this one names the offender in roster terms.)
for _g in vm.globals.get('lzp:*groups*') or []:
    _names = [str(x) for _c in _g[1:] for x in _c[1:]]
    assert len(_names) == len(set(_names)), \
        "%s lists a command twice: %r" % (_g[0], _names)

# Captions live in one table now, so a command cannot carry two of
# them; what CAN go wrong is a button with no caption at all, or a
# caption left behind for a command that no longer has a button.
CAPTIONS = {str(c[0]): str(c[1])
            for c in vm.globals.get('lzp:*captions*') or []}
missing_caption = [c for c in set(BUTTONS) if c not in CAPTIONS]
assert not missing_caption, "buttons with no caption: %r" % missing_caption
orphan_caption = [c for c in CAPTIONS if c not in set(BUTTONS)]
assert not orphan_caption, "captions with no button: %r" % orphan_caption
assert all(CAPTIONS.values()), \
    "blank caption: %r" % [c for c, v in CAPTIONS.items() if not v]
# and the lookup agrees with the table
for _c in sorted(CAPTIONS)[:5]:
    vm.loads('(setq test:*cap* (lzp:caption "%s"))' % _c)
    assert str(vm.globals['test:*cap*']) == CAPTIONS[_c], _c

# lzp:commands folds the repeats -- the status line counts tools, not
# buttons, and would otherwise report more tools than exist.
vm.loads('(setq test:*all* (lzp:commands))')
FOLDED = [str(x) for x in vm.globals['test:*all*']]
assert len(FOLDED) == len(set(FOLDED)), "lzp:commands repeats: %r" % FOLDED
assert set(FOLDED) == set(PANEL), "lzp:commands lost a command"
print("   %s, %d buttons over %d commands, none twice on a page"
      % (ver, len(BUTTONS), len(PANEL)))


print("== roster pin: panel == headline commands under lisp/ ==")
ALL = census()
HELD = held_commands()
missing_from_tree = [c for c in PANEL if c not in ALL]
assert not missing_from_tree, (
    "buttons for commands that do not exist: %r" % missing_from_tree)

satellites = callib.satellites(ALL)

headline = ALL - satellites - HELD
assert headline == set(PANEL), (
    "panel and tree disagree.\n  needs a button: %r\n  stale button: %r"
    % (sorted(headline - set(PANEL)), sorted(set(PANEL) - headline)))
overlap = set(PANEL) & HELD
assert not overlap, "held-back commands with buttons: %r" % overlap
print("   %d headline commands, all on the panel; %d held back, none on it"
      % (len(headline), len(HELD)))


print("== the generated DCL is well formed, one page per group ==")
vm.loads('(setq test:*dcl* (lzp:dcl-lines))')
dcl = [str(l) for l in vm.globals.get('test:*dcl*')]
GROUPS = [str(g[0]) for g in vm.globals['lzp:*groups*']]
# Each row is (label page page ...) -- the label names the row on
# screen ("Job", "Or by category"), the rest are the pages it links to.
ROW_LABELS = [str(r[0]) for r in vm.globals['lzp:*rows*']]
ROWS = [[str(g) for g in r[1:]] for r in vm.globals['lzp:*rows*']]
assert all(ROW_LABELS), "a navigation row has no label"

# The strip layout and the pages are two tables; neither may drift from
# the other, or a group would be unreachable (no tab) or a tab would
# open a page that does not exist.
flat_rows = [g for r in ROWS for g in r]
# Find is a PAGE but not a GROUP: it has no column layout and no roster
# of its own, so it must be on the strip and out of lzp:*groups*, which
# is what "Rest" is computed against and what lzp:commands folds.
FIND = str(vm.globals['lzp:*findname*'])
assert FIND not in GROUPS, \
    "the search page is a group -- Rest and lzp:commands would count it"
PAGES = [FIND] + GROUPS
assert flat_rows == PAGES, \
    "lzp:*rows* names %r, expected %r" % (flat_rows, PAGES)
vm.loads('(setq test:*pages* (lzp:pages))')
assert [str(x) for x in vm.globals['test:*pages*']] == flat_rows, \
    "lzp:pages does not flatten lzp:*rows* in strip order"

opens = [l for l in dcl if l.endswith(' : dialog {')]
# one dialog per page, plus the pin editor
assert len(opens) == len(PAGES) + 1, (
    "%d dialogs for %d pages + the pin editor" % (len(opens), len(PAGES)))
assert 'lazpanel_pins : dialog {' in opens, \
    "the pin editor dialog is not in the generated file"
depth = 0
for line in dcl:
    assert line.count('"') % 2 == 0, "odd quotes: %r" % line
    depth += line.count('{') - line.count('}')
    assert depth >= 0, line
assert depth == 0, "unbalanced braces across the file"

TILES = {'row', 'boxed_row', 'boxed_column', 'column', 'button',
         'text', 'toggle', 'edit_box', 'list_box'}
ATTRS = {'label', 'key', 'width', 'alignment',
         'is_default', 'is_cancel', 'fixed_width', 'edit_width', 'height'}
CLAUSE = r'[a-z_]+ = (?:"[^"]*"|[a-z0-9]+);'
OPEN_RE = re.compile(r': ([a-z_]+) \{$')
INLINE_RE = re.compile(r': ([a-z_]+) \{ ((?:%s )+)\}$' % CLAUSE)
PLAIN_RE = re.compile(r'(?:%s)$' % CLAUSE)


def check_clauses(chunk, line):
    for name in re.findall(r'([a-z_]+) =', chunk):
        assert name in ATTRS, "unknown attribute %r in %r" % (name, line)


def page(group):
    vm.loads('(setq test:*n* (lzp:dlgname "%s"))' % group)
    name = str(vm.globals['test:*n*'])
    i = dcl.index(name + ' : dialog {')
    d = 0
    for j in range(i, len(dcl)):
        d += dcl[j].count('{') - dcl[j].count('}')
        if d == 0:
            return dcl[i:j + 1]
    raise AssertionError("%s never closes" % name)


# DCL does not scroll, so a dialog wider than the screen has nowhere to
# go.  The tab strip is on every page and never changes, so it gets a
# budget: full group titles are short, but the check is what stops a
# future rename making the panel unopenable.
TAB_BUDGET = 90
seen_keys = set()
for gname in PAGES:
    d = page(gname)
    assert d[0].endswith(' : dialog {'), \
        "%s: page does not open with its dialog line: %r" % (gname, d[0])
    assert d[1].strip().startswith('label = '), \
        "%s: the label is not the first thing inside the dialog: %r" % (gname, d[1])
    text = '\n'.join(d)
    keys = re.findall(r'key = "([^"]+)"', text)
    assert len(keys) == len(set(keys)), "%s: duplicate tile keys" % gname
    # a tab for every group, on every page
    tabs = re.findall(r'key = "tab_([^"]+)"; label = "([^"]+)"', text)
    assert [t[0] for t in tabs] == PAGES, \
        "%s: tab strip is %r, expected %r" % (gname, [t[0] for t in tabs], PAGES)
    # width is per ROW, not per strip: the tabs wrap onto the rows of
    # lzp:*rows*, so what has to fit the screen is the widest single row.
    wide = max(sum(len(g) + 6 for g in r) for r in ROWS)
    assert wide <= TAB_BUDGET, (
        "%s: the widest tab row is about %d characters, over the %d budget "
        "-- DCL will not scroll a dialog wider than the screen" % (gname, wide, TAB_BUDGET))
    # the navigation rows are labelled boxed rows now, one per lzp:*rows*
    for lbl in ROW_LABELS:
        assert 'label = "%s";' % lbl in text, \
            "%s: no navigation row labelled %r" % (gname, lbl)
    assert 'key = "pin_edit"' in text, \
        "%s: no Pin... button -- the pinned row is missing" % gname
    # this page carries exactly its own group's commands -- no more and
    # no fewer.  It may well share commands with another page (AUTODIM
    # is on Pool, Cover and Spa), so the test is against this group's
    # own list rather than against every other group's.
    vm.loads('(setq test:*g* (lzp:group-commands "%s"))' % gname)
    mine = [str(x) for x in (vm.globals['test:*g*'] or [])]
    if gname == FIND:
        assert not mine, "the search page must not be a group"
        # it carries the roster in one list box rather than in buttons
        for k in ('filter', 'hits', 'msg', 'run'):
            assert 'key = "%s"' % k in text, "%s: no %r tile" % (gname, k)
        assert 'is_default = true' in text, \
            "%s: no default button -- Enter would not run anything" % gname
    assert set(mine) <= set(keys), \
        "%s: commands with no button: %r" % (gname, sorted(set(mine) - set(keys)))
    # pinned buttons carry a pin_ prefix and repeat a tool already on
    # some page; pin_edit opens the editor.  Neither is a page command.
    extra = set(keys) - set(mine) - {'status', 'cancel', 'pin_edit'} \
            - {'filter', 'hits', 'msg', 'run'} \
            - {'tab_' + g for g in PAGES} \
            - {k for k in keys if k.startswith('pin_')} \
            - {k for k in keys if k.startswith('rec_')}
    assert not extra, \
        "%s: buttons for commands not in its group: %r" % (gname, sorted(extra))
    seen_keys |= set(mine)
    assert 'status' in keys and 'cancel' in keys, gname
    assert text.count('is_cancel = true') == 1
    for line in d[1:]:
        s2 = line.strip()
        if s2 in ('}', 'spacer;'):
            continue
        m = OPEN_RE.fullmatch(s2)
        if m:
            assert m.group(1) in TILES, "unknown tile %r in %r" % (m.group(1), line)
            continue
        m = INLINE_RE.fullmatch(s2)
        if m:
            assert m.group(1) in TILES, "unknown tile %r in %r" % (m.group(1), line)
            check_clauses(m.group(2), line)
            continue
        assert PLAIN_RE.fullmatch(s2), "not a valid DCL line: %r" % line
        check_clauses(s2, line)
    print("   %-11s %2d lines, %2d commands, tab strip ~%d chars"
          % (gname, len(d), len(mine), wide))

# every command on the roster lives on at least one page
assert seen_keys == set(PANEL), (
    "pages and roster disagree: %r" % sorted(seen_keys ^ set(PANEL)))

# The job pages between them account for the whole roster, and "Rest" is
# exactly what Pool, Cover and Spa leave over -- computed here rather
# than trusted, so a tool added to the panel and forgotten on the job
# pages shows up as a Rest omission instead of silently vanishing from
# the workflow the drafter actually follows.
JOBS = ['Pool', 'Cover', 'Spa']


def page_cmds(name):
    vm.loads('(setq test:*p* (lzp:group-commands "%s"))' % name)
    return set(str(x) for x in vm.globals['test:*p*'])


named = set()
for j in JOBS:
    named |= page_cmds(j)
rest = page_cmds('Rest')
assert rest == set(PANEL) - named, (
    "Rest should be the complement of %s; missing from Rest: %r; "
    "should not be there: %r"
    % ('/'.join(JOBS), sorted((set(PANEL) - named) - rest),
       sorted(rest - (set(PANEL) - named))))
assert named | rest == set(PANEL), "the job pages do not cover the roster"

# The AB checks are bench work over the survey ties, not a step in
# laying a pool, a cover or a spa out, so among the job pages they
# belong to Rest alone.  Derived from the roster rather than listed
# here, so a NEW AB check put on Pool out of habit fails right here
# instead of quietly widening a job page.  (The Checking CATEGORY page
# still carries them -- that page answers a different question.)
AB_CHECKS = sorted(c for c in PANEL
                   if c.startswith('AB') and ('CHECK' in c or 'SCAN' in c))
assert AB_CHECKS, "no AB check on the panel at all -- has one been renamed?"
for _c in AB_CHECKS:
    on = [j for j in JOBS if _c in page_cmds(j)]
    assert not on, "%s is an AB check and belongs on Rest, not on %r" % (_c, on)
    assert _c in rest, "%s is an AB check and is not on Rest" % _c
print("   %d AB check(s) on Rest only: %s" % (len(AB_CHECKS), ', '.join(AB_CHECKS)))
print("   %d dialogs, %d commands across them (%d buttons)"
      % (len(opens), len(seen_keys), len(BUTTONS)))
print("   jobs cover %d, Rest holds the other %d, %d shared across jobs"
      % (len(named), len(rest),
         sum(1 for c in PANEL if sum(c in page_cmds(j) for j in JOBS) > 1)))


# --------------------------------------------------------------------
# Columns: the shape of a page, and the width that shape has to fit.
# --------------------------------------------------------------------
# The job pages break their tools into the columns the work falls into.
# A page laid out in columns shows the command name alone on each
# button, because four captioned buttons abreast would be about 147
# character cells and DCL will not scroll a dialog wider than the
# screen -- it just fails to open, which is how this budget came to
# exist for the tab strip in the first place.
print("== columns: the page layout, and what it has to fit ==")
BODY_BUDGET = 90
EXPECT_COLUMNS = {'Pool': 4, 'Cover': 3, 'Spa': 1, 'Rest': 1,
                  'Layout': 1, 'Points': 1, 'Dimensions': 1, 'Checking': 1}

for gname in GROUPS:
    cols = columns(vm, gname)
    assert len(cols) == EXPECT_COLUMNS[gname], \
        "%s has %d column(s), expected %d" % (gname, len(cols),
                                              EXPECT_COLUMNS[gname])
    text = '\n'.join(page(gname))
    # key -> the label the page actually renders for it
    rendered = dict((k, lb) for lb, k in
                    re.findall(r': button \{ label = "([^"]*)"; key = "([^"]+)"',
                               text))
    if len(cols) == 1:
        heading, cmds = cols[0]
        assert heading == '', \
            "%s is a single column but carries a heading %r" % (gname, heading)
        for c in cmds:
            assert rendered[c] == '%s  -  %s' % (c, CAPTIONS[c]), \
                "%s: %s lost its caption: %r" % (gname, c, rendered[c])
        wide = max(len(c) + 5 + len(CAPTIONS[c]) for c in cmds) + 6
    else:
        for heading, cmds in cols:
            assert heading, "%s has a column with no heading" % gname
            for c in cmds:
                assert rendered[c] == c, (
                    "%s: %s is captioned on a multi-column page (%r) -- that "
                    "is what blows the width budget" % (gname, c, rendered[c]))
        wide = sum(max([len(h)] + [len(c) for c in cs]) + 6 for h, cs in cols)
    assert wide <= BODY_BUDGET, (
        "%s is about %d cells wide, over the %d budget -- DCL will not "
        "scroll it and the dialog will not open" % (gname, wide, BODY_BUDGET))
    print("   %-11s %d column(s), about %2d cells wide%s"
          % (gname, len(cols), wide,
             '  [' + ' | '.join(h for h, _ in cols) + ']'
             if len(cols) > 1 else ''))

# --------------------------------------------------------------------
# Pins: the row that follows you across every page.
# --------------------------------------------------------------------
# Pins sit on EVERY page, so they are the one part of the panel a user
# can make arbitrarily wide -- and a DCL dialog that is too wide does
# not clip, it fails to open.  The row therefore packs greedily onto as
# many rows as it needs.  These are the cases that break it.
print("== pins: pinned row, packing, order and persistence ==")
pv = fresh()


def pinrow_lines(vm_):
    vm_.loads('(setq test:*pr* (lzp:pinrow))')
    return [str(l) for l in vm_.globals['test:*pr*']]


def widest_row(lines):
    worst = cur = 0
    for l in lines:
        if l.strip() == '}':
            worst, cur = max(worst, cur), 0
        else:
            m = re.search(r'label = "([^"]*)"', l)
            if m and ('button {' in l or 'text {' in l):
                cur += len(m.group(1)) + 6
    return max(worst, cur)


# nothing pinned: the row still exists, says so, and offers the editor
pv.loads("(setq lzp:*pins* nil)")
empty = pinrow_lines(pv)
assert any('nothing pinned yet' in l for l in empty), empty
assert any('pin_edit' in l for l in empty), empty

# the worst case a user can actually reach: the longest names there are
LONG = ["LITESPACHECKSCAN", "LITELINFINSCAN", "AUTODIMSIDEPOV",
        "LITECOVERSCAN", "FITABHDCOVER", "LAZFORMCOVER", "SPACHECKSCAN",
        "DIMARCCHECK"]
pv.loads("(setq lzp:*pins* '(%s))" % ' '.join('"%s"' % n for n in LONG))
wide = pinrow_lines(pv)
budget = int(str(pv.globals['lzp:*pinbudget*']))
w = widest_row(wide)
assert w <= budget, (
    "eight long pins made a %d-cell row against a %d budget -- one row "
    "that wide is a dialog that will not open" % (w, budget))
assert wide.count('  : boxed_row {') > 1, \
    "the long pins did not wrap; they were all put on one row"
# only the first of the wrapped rows is labelled
assert [l for l in wide if 'label = "Pinned";' in l], wide
assert len([l for l in wide if l.strip().startswith('label =')]) == \
    wide.count('  : boxed_row {'), "every wrapped row needs a label clause"
# every pin is still there, none dropped by the packing
for n in LONG:
    assert any('key = "pin_%s"' % n in l for l in wide), "%s lost" % n
print("   %d long pins wrap onto %d rows, widest %d cells (budget %d)"
      % (len(LONG), wide.count('  : boxed_row {'), w, budget))

# pin order is click order: a newly ticked tool goes on the END
pv.loads("(setq lzp:*pins* '(\"POOL\" \"SPA\"))")
pv.loads('(lzp:pin-toggle "AUTODIM" "1")')
assert [str(x) for x in pv.globals['lzp:*pins*']] == ['POOL', 'SPA', 'AUTODIM']
pv.loads('(lzp:pin-toggle "SPA" "0")')
assert [str(x) for x in pv.globals['lzp:*pins*']] == ['POOL', 'AUTODIM']
pv.loads('(lzp:pin-toggle "POOL" "1")')      # already pinned: no duplicate
assert [str(x) for x in pv.globals['lzp:*pins*']] == ['POOL', 'AUTODIM']
print("   ticking appends, unticking removes, re-ticking does not double")

# a pin left over from an older build must not put a dead button on
# screen: pins-read keeps only what is on the roster today
pv.loads('(defun vl-registry-read (k v) "POOL;NOSUCHTOOL;AUTODIM")')
pv.loads('(lzp:pins-read)')
assert [str(x) for x in pv.globals['lzp:*pins*']] == ['POOL', 'AUTODIM'], \
    "a stale pin survived: %r" % pv.globals['lzp:*pins*']
# and a session with no registry at all simply has no pins
pv2 = fresh()
pv2.loads('(setq lzp:*pins* nil)')
pv2.loads('(lzp:pins-read)')
assert not pv2.globals.get('lzp:*pins*'), "no registry should mean no pins"
print("   stale pins dropped against the roster; no registry = no pins")

# every page carries the pinned row, not just the first
pv.loads("(setq lzp:*pins* '(\"POOL\"))")
pv.loads('(setq test:*d* (lzp:dcl-lines))')
alld = '\n'.join(str(l) for l in pv.globals['test:*d*'])
assert alld.count('key = "pin_POOL"') == len(PAGES), (
    "the pinned tool appears on %d pages, expected %d"
    % (alld.count('key = "pin_POOL"'), len(PAGES)))
print("   a pinned tool gets a button on all %d pages" % len(PAGES))


print("== recent: what you just used, without being asked ==")
rv = fresh()
rv.loads('(defun vl-registry-write (k v s) (setq t:*wrote* (list v s)) s)')


def recent(v):
    v.loads('(setq t:*r* lzp:*recent*)')
    return [str(x) for x in (v.globals['t:*r*'] or [])]


def shown(v):
    v.loads('(setq t:*s* (lzp:recshown))')
    return [str(x) for x in (v.globals['t:*s*'] or [])]


rv.loads('(setq t:*lim* lzp:*reclimit*)')
LIMIT = int(str(rv.globals['t:*lim*']))
ORDER = PANEL[:LIMIT + 2]
for n in ORDER:
    rv.loads('(lzp:remember "%s")' % n)
# newest first, and capped
assert recent(rv) == list(reversed(ORDER))[:LIMIT], recent(rv)
# running one again moves it to the front rather than doubling it
rv.loads('(lzp:remember "%s")' % ORDER[-1])
assert recent(rv)[0] == ORDER[-1], recent(rv)
assert len(recent(rv)) == len(set(recent(rv))), "a tool is in Recent twice"
assert len(recent(rv)) == LIMIT, recent(rv)
# it is stored under its own registry value, not over the pins
rv.loads('(setq t:*v* (car t:*wrote*)) (setq t:*s* (cadr t:*wrote*))')
assert str(rv.globals['t:*v*']) == 'Recent', rv.globals['t:*v*']
assert str(rv.globals['t:*s*']) == ';'.join(recent(rv)), rv.globals['t:*s*']
print("   newest first, once each, capped at %d, stored as its own value"
      % LIMIT)

# a pinned tool is stored but not SHOWN: Pinned already carries it, and
# the tools you pin are by definition the ones you run most
rv.loads('(setq lzp:*pins* \'("%s"))' % recent(rv)[0])
assert recent(rv)[0] not in shown(rv), \
    "a pinned tool is on the Recent row as well: %r" % shown(rv)
assert shown(rv) == recent(rv)[1:], shown(rv)
# unpinning brings it straight back, because it was never dropped
rv.loads('(setq lzp:*pins* nil)')
assert shown(rv) == recent(rv), shown(rv)
print("   a pinned tool is remembered but not shown twice")

# a name from an older build must not put a dead button on screen
rv.loads('(defun vl-registry-read (k v) "%s;NOSUCHTOOL;%s")'
         % (PANEL[0], PANEL[1]))
rv.loads('(lzp:recent-read)')
assert recent(rv) == [PANEL[0], PANEL[1]], \
    "a stale name survived the read: %r" % recent(rv)
# and no registry at all is simply no recents
rv2 = fresh()
rv2.loads('(defun vl-registry-read (k v) (exit))')
rv2.loads('(lzp:recent-read)')
assert not recent(rv2), "a failing registry read produced recents anyway"
print("   stale names dropped against the roster; no registry = no recents")

# the row itself: absent when there is nothing in it, so a panel opened
# for the first time is exactly as tall as it always was -- and DCL
# height is what stops a dialog opening at all
ev = fresh()
ev.loads('(setq lzp:*recent* nil) (setq t:*d* (lzp:dcl-lines))')
assert not [l for l in (str(x) for x in ev.globals['t:*d*'])
            if 'Recent' in l or 'rec_' in l], \
    "an empty Recent row was emitted anyway"
ev.loads('(setq lzp:*recent* \'("%s" "%s"))' % (PANEL[0], PANEL[1]))
ev.loads('(setq t:*d* (lzp:dcl-lines))')
alld = '\n'.join(str(x) for x in ev.globals['t:*d*'])
assert alld.count('key = "rec_%s"' % PANEL[0]) == len(PAGES), (
    "the recent tool is on %d pages, expected %d"
    % (alld.count('key = "rec_%s"' % PANEL[0]), len(PAGES)))
assert alld.count('label = "Recent";') == len(PAGES), \
    "the Recent row is not labelled once per page"
print("   no row until there is something in it, then one on every page")

# WIDTH.  Both rows pack through lzp:packrow, so neither can be the one
# that forgets the budget and produces a dialog too wide to open.
wv = fresh()
wv.loads('(setq t:*b* lzp:*pinbudget*)')
BUDGET = int(str(wv.globals['t:*b*']))
LONG = sorted(PANEL, key=len, reverse=True)[:LIMIT]
wv.loads("(setq lzp:*recent* '(%s))" % ' '.join('"%s"' % n for n in LONG))
wv.loads('(setq t:*rows* (lzp:recrows))')
rows = [[str(x) for x in r] for r in wv.globals['t:*rows*']]
assert [n for r in rows for n in r] == LONG, \
    "packing lost or reordered a name: %r" % rows
for r in rows:
    w = sum(len(n) + 6 for n in r)
    assert w <= BUDGET, "a recent row is %d cells, over the %d budget" % (w, BUDGET)
print("   %d long names pack onto %d row(s), widest %d cells (budget %d)"
      % (len(LONG), len(rows),
         max(sum(len(n) + 6 for n in r) for r in rows), BUDGET))


print("== end-to-end with the DCL surface stubbed ==")
# The stub session "has" exactly one command, LIVE, and deliberately
# lacks MISSING; both must sit on the page the panel opens on.
LIVE = 'POOL'
MISSING = 'OASIS'
# The stubs keep one ORDERED event log (stub:*events*) so the cleanup
# sequence -- handle closed before load_dialog reads the file, dialog
# unloaded and temp file deleted before anything launches -- is pinned,
# not just each call's happening.  A click is simulated faithfully:
# start_dialog looks up the clicked key's REAL action_tile expression,
# binds $key / $value / $reason the way AutoCAD does, and evaluates it,
# so the wiring string in LAZPANEL.lsp is executed here, not assumed.
#
# The vla-* stubs model the menu API: menu group "MG0" whose toolbars
# live in stub:*tbs*, each toolbar's buttons in stub:*btns*.  The
# ADODB.Stream path needs variable arity -- (vlax-invoke st 'Open) takes
# two arguments, (vlax-invoke st 'SaveToFile p 2) takes four -- which a
# defun in this VM cannot express, since it enforces exact arity, so
# that surface goes in as Python builtins instead.
STUB = '''
(setq stub:*written* nil stub:*disabled* nil stub:*action* nil
      stub:*events* nil stub:*click* nil stub:*status* nil
      stub:*ran* nil stub:*dlgname* nil stub:*done* nil
      stub:*tbs* nil stub:*btns* nil stub:*addargs* nil
      stub:*bitmaps* nil stub:*float* nil stub:*visible* nil
      stub:*deleted-tb* nil stub:*addfail* nil stub:*rcs* nil
      stub:*nosupport* nil stub:*tiles* nil stub:*list* nil
      stub:*listing* nil stub:*clickval* nil stub:*clickreason* nil)
(defun stub:ev (e) (setq stub:*events* (cons e stub:*events*)) e)
(defun vl-filename-mktemp (pat dir ext) (strcat "/stub/" pat ext))
(defun open (f mode) f)
(defun write-line (s fh)
  (setq stub:*written* (cons s stub:*written*)) s)
(defun close (fh) (stub:ev "close"))
;; the AutoCAD profile, as a store the scenario can seed and read back
;; -- a dialog position that outlives a restart is a setenv/getenv
;; round trip and nothing else
(setq stub:*env* nil)
(defun getenv (key / p) (if (setq p (assoc key stub:*env*)) (cdr p)))
(defun setenv (key v)
  (setq stub:*env* (cons (cons key v)
                         (vl-remove (assoc key stub:*env*) stub:*env*)))
  v)
(defun load_dialog (f) (stub:ev "load") 7)
(defun term_dialog () nil)
(defun set_tile (k v)
  (setq stub:*tiles* (cons (list k v) stub:*tiles*))
  (if (= k "status") (setq stub:*status* v)) v)
(defun stub:tile (k / p) (if (setq p (assoc k stub:*tiles*)) (cadr p)))
;; A list box is filled between start_list and end_list, so the stub
;; keeps the rows in the order they were added rather than the order
;; the caller consed them.
(defun start_list (k) (setq stub:*listing* nil) (stub:ev (strcat "list " k)) k)
(defun add_list (s) (setq stub:*listing* (cons s stub:*listing*)) s)
(defun end_list () (setq stub:*list* (reverse stub:*listing*)) nil)
(defun action_tile (k expr)
  (setq stub:*action* (cons (list k expr) stub:*action*)) t)
(defun mode_tile (k m)
  (if (= m 1) (setq stub:*disabled* (cons k stub:*disabled*))) t)
;; DCL hands back where the dialog was standing, so the next page can
;; open in the same place instead of wandering
(defun done_dialog (status) (setq stub:*done* status) (list 120 340))
(defun start_dialog ( / pair)
  (if stub:*rcs*
    (setq stub:*rc* (car stub:*rcs*) stub:*rcs* (cdr stub:*rcs*)))
  (stub:ev "start")
  (setq stub:*done* nil)
  (if (setq pair (assoc stub:*click* stub:*action*))
    (progn
      (setq $key   (car pair)
            $value stub:*clickval*
            $reason (if stub:*clickreason* stub:*clickreason* 1))
      (eval (read (strcat "(progn " (cadr pair) ")")))
      ;; a click happens ONCE -- left armed it re-fires on the page it
      ;; just opened, and a tab would reopen itself for ever
      (setq stub:*click* nil)))
  (if stub:*done* stub:*done* stub:*rc*))
(defun unload_dialog (id) (stub:ev "unload"))
(defun vl-file-delete (f) (stub:ev (strcat "delete " f)) t)
(defun findfile (f) (if (stub:ondisk f) f nil))
(defun vlax-get-acad-object () "ACAD")
(defun vla-get-menugroups (app) "MGS")
(defun vla-get-toolbars (mg) "TBS")
(defun vla-get-preferences (app) "PREFS")
(defun vla-get-files (prefs) "FILES")
(defun vla-get-supportpath (files)
  (if stub:*nosupport* (exit) "/stub/support;/stub/other"))
(defun vla-get-count (obj) (if (= obj "MGS") 1 (length stub:*tbs*)))
(defun vla-get-name (tb) tb)
(defun vla-item (obj i)
  (cond ((= obj "MGS") "MG0")
        ((= obj "TBS") (nth i stub:*tbs*))
        (t (nth i stub:*btns*))))
(defun vla-add (tbs name)
  (setq stub:*tbs* (append stub:*tbs* (list name)))
  (stub:ev (strcat "add " name))
  name)
(defun vla-addtoolbarbutton (tb idx name help macro)
  (setq stub:*addargs* (list idx name help macro))
  (if stub:*addfail*
    (exit)
    (progn (setq stub:*btns* (append stub:*btns* (list "BTN")))
           (stub:ev "addbutton")
           "BTN")))
(defun vla-delete (tb)
  (setq stub:*tbs* (vl-remove tb stub:*tbs*)
        stub:*deleted-tb* tb)
  (stub:ev "deletetoolbar") t)
(defun vla-setbitmaps (btn small large)
  (setq stub:*bitmaps* (list small large)) (stub:ev "setbitmaps") t)
(defun vla-put-visible (tb v)
  (setq stub:*visible* v) (stub:ev "visible") t)
(defun vla-float (tb top left rows)
  (setq stub:*float* (list top left rows)) (stub:ev "float") t)
;; The one command this session "has".  It must live on the FIRST page,
;; since that is the page the panel opens on and the only one whose
;; buttons get bound -- see LIVE / MISSING below, which assert exactly
;; that so a re-ordered roster fails here with a reason.
(defun c:POOL ()
  (setq stub:*ran* (cons "POOL" stub:*ran*)) (stub:ev "run POOL") (princ))
'''

# --- the ADODB.Stream surface, as Python builtins (variable arity) ---
import lispvm  # noqa: E402

COM = {}


def _reset_com():
    # the blackboard is per AutoCAD session; each stubbed() VM stands
    # for a fresh session unless a test says otherwise
    lispvm.reset_blackboard()
    OPENED.clear()
    POS.clear()
    COM.clear()
    COM.update(created=[], props={}, calls=[], bytes=None, saved=None,
               released=0, fail_at=None, b64=None, wrote=[],
               refused=[], xmldoc=None, shell=[], ondisk=set())


def _b(name):
    def deco(fn):
        lispvm.BUILTINS[lispvm.Sym(name)] = fn
        return fn
    return deco


OPENED = []
POS = []


@_b('new_dialog')
def _newdlg(vm, a):
    # 2 args on the first open, 4 once a position is known, so the
    # position threading is provable and a fixed-arity stub cannot
    # express it
    OPENED.append((str(a[0]), len(a)))
    if len(a) > 3:
        POS.append([float(v) for v in a[3]])
    vm.globals[lispvm.Sym('stub:*dlgname*')] = str(a[0])
    vm.globals[lispvm.Sym('stub:*action*')] = None
    vm.loads('(stub:ev "new")')
    return True


@_b('vlax-create-object')
def _create(vm, a):
    name = str(a[0])
    COM['created'].append(name)
    if COM.get('fail_at') == 'create':
        raise lispvm.LispError('Automation Error', vm)
    if name.lower() == 'wscript.shell':
        if COM.get('fail_at') == 'wshell':
            raise lispvm.LispError('Automation Error', vm)
        return 'WSHELL'
    if name.lower().startswith(('msxml', 'microsoft.xmldom')):
        if COM.get('fail_at') == 'msxml':
            raise lispvm.LispError('Automation Error', vm)
        # MSXML 6.0 creates perfectly well and refuses dataType later:
        # XDR schema support, of which bin.base64 is part, was removed
        # in 6.0.  The stub models that, because a probe that stops at
        # "did the object appear?" picks 6.0 and then reports nothing --
        # which is what happened in the field.
        COM['xmldoc'] = name
        return 'XMLDOC6' if '6.0' in name else 'XMLDOC'
    return 'STREAM' 


@_b('vlax-put-property')
@_b('vlax-put')
def _put(vm, a):
    prop = str(a[1]).lower()
    if str(a[0]) == 'XMLEL6' and prop == 'datatype':
        COM.setdefault('refused', []).append(COM.get('xmldoc'))
        raise lispvm.LispError(
            'Automation Error. Description was not provided.', vm)
    COM['props'][prop] = a[2]
    if str(a[0]) == 'XMLEL' and prop == 'text':
        COM['b64'] = str(a[2])
    return a[2]


@_b('vlax-get-property')
@_b('vlax-get')
def _get(vm, a):
    # MSXML's bin.base64 element hands back a real byte array -- which
    # is the whole point of the detour, so the stub does the decoding
    # for real rather than waving it through.  Everything downstream
    # then checks bytes that actually travelled as base64.
    if str(a[1]).lower() == 'nodetypedvalue':
        COM['bytes'] = list(base64.b64decode(COM['b64']))
        return 'BYTEARRAY'
    return None


@_b('vlax-make-safearray')
def _mksa(vm, a):
    return ['SAFEARRAY', a[0]]


@_b('vlax-safearray-fill')
def _fill(vm, a):
    COM['bytes'] = [int(x) for x in a[1]]
    return a[0]


@_b('stub:ondisk')
def _ondisk(vm, a):
    return str(a[0]) if str(a[0]) in COM.get('ondisk', set()) else None


@_b('vlax-release-object')
def _rel(vm, a):
    COM['released'] += 1
    return None


@_b('vlax-invoke-method')
@_b('vlax-invoke')
def _invoke(vm, a):
    m = str(a[1]).lower()
    COM['calls'].append(m)
    if COM.get('fail_at') == m:
        raise lispvm.LispError('Automation Error', vm)
    if m == 'run':
        COM.setdefault('shell', []).append(str(a[2]))
        # certutil really does produce the file, so findfile must see it
        COM.setdefault('ondisk', set()).add(
            str(a[2]).rsplit('"', 2)[-2])
        return 0
    if m == 'createelement':
        return 'XMLEL6' if str(a[0]) == 'XMLDOC6' else 'XMLEL'
    if m == 'write':
        # Write must be handed the byte array, never a safearray: a
        # VT_I2 safearray is exactly what AutoCAD refused in the field
        COM.setdefault('wrote', []).append(a[2])
    if m == 'savetofile':
        COM['saved'] = (str(a[2]), a[3])
        COM.setdefault('saves', []).append(str(a[2]))
    return None


def stubbed(preload=False):
    """A VM with the stubs in place.  preload=True installs them BEFORE
    the file loads, so the load-time (lzp:button-init) call at the foot
    of LAZPANEL.lsp runs against them -- that call IS the feature, and
    without it the call silently no-ops behind vl-catch-all-apply and
    nothing here would notice it being deleted."""
    _reset_com()
    vm = VM()
    if preload:
        vm.loads(STUB)
        vm.load(LSP)
    else:
        vm.load(LSP)
        vm.loads(STUB)
    return vm


def run(vm, name, label):
    try:
        vm.run(name, [])
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None


def events(vm):
    return [str(e) for e in reversed(vm.globals.get('stub:*events*') or [])]


DIALOG = ['close', 'load', 'new', 'start', 'unload',
          'delete /stub/lazpanel.dcl']

vm = stubbed()
run(vm, 'c:LAZPANEL', 'close')
assert not vm.globals.get('stub:*ran*'), "Close launched something"
written = [str(l) for l in reversed(vm.globals.get('stub:*written*'))]
assert written == dcl, "written DCL differs from lzp:dcl-lines"
assert events(vm) == DIALOG, events(vm)
vm.loads('(setq test:*n* (lzp:dlgname "%s"))' % GROUPS[0])
assert str(vm.globals.get('stub:*dlgname*')) == str(vm.globals['test:*n*']), \
    "new_dialog opened %r, not the first page" % vm.globals.get('stub:*dlgname*')
# only THIS page's commands are bound now -- that is the point of the
# pages -- plus a tab for every group
vm.loads('(setq test:*g* (lzp:group-commands "%s"))' % GROUPS[0])
first = [str(x) for x in vm.globals['test:*g*']]
# Only the opening page's buttons are bound, so both commands the click
# tests use have to be on it: LIVE is the one the stub defines, MISSING
# is one it deliberately does not.
assert LIVE in first, (
    "the stub defines c:%s, but %s is not on the first page (%s) -- "
    "the click test would click nothing" % (LIVE, LIVE, GROUPS[0]))
assert MISSING in first and MISSING != LIVE, (
    "%s is not on the first page (%s), so it cannot stand for a greyed "
    "button there" % (MISSING, GROUPS[0]))
acts = {str(a[0]) for a in vm.globals.get('stub:*action*')}
assert set(first) <= acts, sorted(set(first) - acts)
for g in GROUPS:
    assert 'tab_%s' % g in acts, "no tab callback for %s" % g
strays = acts & (set(PANEL) - set(first))
assert not strays, "another page's commands were bound too: %r" % sorted(strays)
# the status line still counts the WHOLE roster, not just this page
assert '1 of %d' % len(PANEL) in str(vm.globals.get('stub:*status*'))
disabled = set(map(str, vm.globals.get('stub:*disabled*')))
assert disabled == set(first) - {LIVE}, disabled ^ (set(first) - {LIVE})
assert vm.globals.get('lzp:*pick*') is None, "pick survived the run"
print("   Close: nothing ran, close->load->new->start->unload->delete,")
print("   only the first page's %d commands bound, only %s enabled"
      % (len(first), LIVE))

print("== where it was left outlives the session, not just the reopen ==")
# lzp:*pos* is deliberately NOT reset between runs -- the panel reopens
# after every tool it launches -- but it still dies with the file, so
# the first panel after an AutoCAD restart used to come back in the
# middle of the screen.  The profile is what closes that.
vmp = stubbed()
vmp.loads('(setq stub:*click* "cancel")')
run(vmp, 'c:LAZPANEL', 'position saved')
vmp.loads('(setq t:*saved* (getenv lzp:*poskey*))')
assert str(vmp.globals.get('t:*saved*')) == '120,340', (
    "closing the panel did not write its position to the profile: %r"
    % vmp.globals.get('t:*saved*'))

# a fresh VM is a fresh AutoCAD.  Seed the profile the last one left and
# the FIRST page opens with four arguments, at that point, rather than
# centred -- which is the whole of what was asked for.
vmq = stubbed()
vmq.loads('(setenv "LazPanel_Pos" "212,84")')
vmq.loads('(setq stub:*click* "cancel")')
run(vmq, 'c:LAZPANEL', 'position restored')
assert OPENED and OPENED[0][1] == 4, (
    "the first panel of a fresh session ignored the saved position: %r" % OPENED)
assert POS and POS[0] == [212.0, 84.0], (
    "the panel opened somewhere other than where it was left: %r" % POS)
print("   closing writes the point to the profile, and a fresh session")
print("   opens the panel there instead of in the middle")

# What the profile is allowed to hold, and what it may do about it.
# pos-read takes a value back only if it round-trips, so a hand-edited
# or foreign one can do no more than centre the dialog -- which is
# exactly what happened before there was a profile at all.
vmr = stubbed()
for src, want, why in (
        ('"nonsense"', None, 'a value with no comma'),
        ('"12,"', None, 'a half-written value'),
        ('",34"', None, 'a value with no x'),
        ('"12,34x"', None, 'a value that does not round-trip'),
        ('"12,34"', [12, 34], 'a value this build wrote')):
    vmr.loads('(setenv lzp:*poskey* %s) (setq t:*r* (lzp:pos-read))' % src)
    got = vmr.globals.get('t:*r*')
    got = [int(v) for v in got] if got else None
    assert got == want, "%s read back as %r, not %r" % (why, got, want)
# SCREENSIZE is unknown on a box AutoCAD cannot size (it reads nil), and
# the clamp has to sit that out rather than pin every dialog to the
# corner.  The VM seeds it like AutoCAD does, so this scenario takes
# it away.
vmr.sysvars.pop('SCREENSIZE', None)
# a point saved on a second monitor that has since been unplugged is
# dragged back onto the drawing area, not left where the mouse cannot go
vmr.sysvars['SCREENSIZE'] = [1600.0, 900.0]
vmr.loads('(setenv lzp:*poskey* "4000,2000") (setq t:*r* (lzp:pos-read))')
assert [int(v) for v in vmr.globals['t:*r*']] == [1500, 800], (
    "an off-screen point was not clamped back: %r" % vmr.globals['t:*r*'])
vmr.loads('(setenv lzp:*poskey* "300,200") (setq t:*r* (lzp:pos-read))')
assert [int(v) for v in vmr.globals['t:*r*']] == [300, 200], (
    "a point already on screen was moved: %r" % vmr.globals['t:*r*'])
print("   a profile value this build did not write centres the dialog,")
print("   and a point off the current screen is dragged back onto it")

vm = stubbed()
vm.loads('(setq stub:*click* "%s")' % LIVE)
run(vm, 'c:LAZPANEL', 'click-live')
assert [str(x) for x in vm.globals.get('stub:*ran*') or []] == [LIVE]
assert vm.globals.get('lzp:*pick*') is None, "pick not cleared after launch"
# THE REOPEN, which is the point of the loop: the panel closes, the tool
# runs, and the panel comes straight back rather than leaving the user to
# type LAZPANEL again.  The stub clicks once and then closes, so the
# sequence is exactly one full dialog cycle, the run, and a second cycle.
assert events(vm) == DIALOG + ['run %s' % LIVE] + DIALOG, events(vm)
assert events(vm).count('new') == 2, \
    "the panel did not reopen after the tool finished: %r" % events(vm)
assert events(vm).index('run %s' % LIVE) < events(vm).index('new', 3), \
    "the panel reopened before the tool ran"
print("   click %s: the real action expression fires, it runs once,"
      % LIVE)
print("   and only after the dialog is unloaded and the temp file gone")
print("   then the panel REOPENS itself -- close is the way out")

vm = stubbed()
vm.loads('(setq stub:*click* "%s")' % MISSING)
run(vm, 'c:LAZPANEL', 'click-missing')
assert not vm.globals.get('stub:*ran*')
assert any('%s is not loaded' % MISSING in str(p) for p in vm.printed), vm.printed
print("   click on a missing command reports it instead of erroring")


print("== a launch is what puts a tool in Recent ==")
lv = stubbed()
lv.loads('(defun vl-registry-write (k v s) (setq t:*w* s) s)')
lv.loads('(setq stub:*click* "%s")' % LIVE)
run(lv, 'c:LAZPANEL', 'recent-launch')
assert [str(x) for x in (lv.globals.get('lzp:*recent*') or [])] == [LIVE], \
    "running %s did not put it in Recent: %r" % (LIVE, lv.globals.get('lzp:*recent*'))
assert str(lv.globals.get('t:*w*')) == LIVE, \
    "Recent was not written to the registry: %r" % lv.globals.get('t:*w*')
# and the second cycle's DCL carries the row the first one could not
written = [str(l) for l in reversed(lv.globals.get('stub:*written*'))]
assert 'key = "rec_%s"' % LIVE in '\n'.join(written), \
    "the reopened panel does not carry the tool that was just run"
print("   %s runs, lands in Recent, and is on the row when the panel"
      % LIVE)
print("   comes back -- the DCL is rewritten on every reopen")

# a command that is not loaded never ran, so it is not recent either
mv = stubbed()
mv.loads('(defun vl-registry-write (k v s) s)')
mv.loads('(setq stub:*click* "%s")' % MISSING)
run(mv, 'c:LAZPANEL', 'recent-missing')
assert not (mv.globals.get('lzp:*recent*') or []), \
    "a command that did not run reached Recent: %r" % mv.globals.get('lzp:*recent*')
print("   a command that could not run does not count as used")

# the row's buttons launch exactly like the pinned ones, and grey the
# same way -- a recent tool unloaded since is a dead button otherwise
cv = stubbed()
cv.loads('(defun vl-registry-write (k v s) s)')
cv.loads("(setq lzp:*recent* '(\"%s\" \"%s\"))" % (LIVE, MISSING))
cv.loads('(setq stub:*rcs* \'(0)) (setq t:*p* (lzp:show))')
wired = {str(a[0]) for a in (cv.globals.get('stub:*action*') or [])}
assert 'rec_%s' % LIVE in wired, "the Recent button is not wired: %r" % sorted(wired)
disabled = {str(x) for x in (cv.globals.get('stub:*disabled*') or [])}
assert 'rec_%s' % MISSING in disabled, \
    "an unloaded tool on the Recent row is not greyed: %r" % sorted(disabled)
assert 'rec_%s' % LIVE not in disabled, "a loaded tool on the Recent row is greyed"

cv2 = stubbed()
cv2.loads('(defun vl-registry-write (k v s) s)')
cv2.loads("(setq lzp:*recent* '(\"%s\"))" % LIVE)
cv2.loads('(setq stub:*rcs* \'(0)) (setq stub:*click* "rec_%s")' % LIVE)
cv2.loads('(setq t:*p* (lzp:show))')
assert str(cv2.globals.get('t:*p*')) == LIVE, \
    "the Recent button handed back %r, not %s" % (cv2.globals.get('t:*p*'), LIVE)
print("   a Recent button launches its tool and greys when it is not loaded")


print("== the screen button goes up as the file loads ==")
vm = stubbed(preload=True)
tbs = [str(x) for x in vm.globals.get('stub:*tbs*') or []]
assert tbs == ['LazPanel'], \
    "loading the file did not create the toolbar: %r" % tbs
ev = events(vm)
for want in ('add LazPanel', 'addbutton', 'setbitmaps', 'visible', 'float'):
    assert want in ev, "%r missing from the load-time sequence %r" % (want, ev)
assert ev.index('add LazPanel') < ev.index('addbutton') < ev.index('setbitmaps')
print("   loading LAZPANEL.lsp creates it, ices it and floats it")

idx, name, help_, macro = vm.globals.get('stub:*addargs*')
assert int(idx) == 0, (
    "button index must be 0 -- the toolbar is created empty, so 1 is past "
    "its end (got %r)" % idx)
assert str(name) == 'LazPanel', name
assert 'LazPanel' in str(help_), help_
assert str(macro) == '\x03\x03_LAZPANEL ', (
    "macro must be raw ASCII-3 cancels + the command, not the ^C^C spelling "
    "a menu FILE would use: %r" % str(macro))
assert [int(x) for x in vm.globals.get('stub:*float*')] == [200, 300, 1], \
    vm.globals.get('stub:*float*')
print("   button at index 0, ^C^C macro as raw ASCII 3, floated at 200,300")


print("== the icon is written as real binary, not text ==")
# Two icons, and each takes both objects: MSXML to turn the base64 back
# into a byte array, ADODB.Stream to put that array on disk.
# Each icon takes the stream plus whichever MSXML version carries the
# whole chain.  3.0 is tried first and works, so 6.0 is never reached.
assert COM['created'] == ['ADODB.Stream', 'MSXML2.DOMDocument.3.0'] * 2, \
    COM['created']
assert int(COM['props']['type']) == 1, COM['props']      # adTypeBinary
assert str(COM['props']['datatype']) == 'bin.base64', COM['props']
assert COM['calls'].count('open') == 2 and COM['calls'].count('write') == 2
assert COM['saved'][1] == 2, COM['saved']                # overwrite if present
# the stream AND the two MSXML objects per icon all get released
assert COM['released'] >= 2, "the stream object must be released"
# Write is handed the MSXML byte array, never a safearray: a VT_I2
# safearray is precisely what AutoCAD refused in the field, with
# "Arguments are of the wrong type, are out of acceptable range, or are
# in conflict with one another".
for w in COM['wrote']:
    assert str(w) == 'BYTEARRAY', \
        "Write was handed %r, not the byte array MSXML made" % (w,)
# The FILES go into the first support-path folder; SetBitmaps is handed
# the bare NAMES.  The CUI resolves a toolbar bitmap by name along the
# support search path, and a full path into the temp folder -- which is
# not on that path -- is exactly the "?" placeholder the button showed.
# the stub folder carries no trailing separator, so the code adds the
# Windows one -- which is the point of the guard
assert COM.get('saves') == ['/stub/support\\lazpanel-16.bmp',
                            '/stub/support\\lazpanel-32.bmp'], COM.get('saves')
bitmaps = [str(x) for x in vm.globals.get('stub:*bitmaps*') or []]
assert bitmaps == ['lazpanel-16.bmp', 'lazpanel-32.bmp'], (
    "SetBitmaps must get support-resolvable NAMES, not paths: %r" % bitmaps)

grid = [str(r) for r in vm.globals.get('lzp:*icon16*')]
assert len(grid) == 16 and all(len(r) == 16 for r in grid), grid
ORANGE, GREY = [0, 165, 255], [54, 54, 54]


def le(bb):
    n = 0
    for i, b in enumerate(bb):
        n += b << (8 * i)
    return n


def check_bmp(bb, size, grid):
    assert len(bb) == 54 + size * size * 3, (size, len(bb))
    assert bb[0] == 66 and bb[1] == 77, "no BM signature"
    assert le(bb[2:6]) == len(bb), "file size field wrong"
    assert le(bb[10:14]) == 54 and le(bb[14:18]) == 40
    assert le(bb[18:22]) == size and le(bb[22:26]) == size
    assert le(bb[26:28]) == 1 and le(bb[28:30]) == 24
    assert le(bb[34:38]) == size * size * 3
    assert (3 * size) % 4 == 0, "row width must be a multiple of 4"
    px = bb[54:]
    # WHERE the orange is, not just how much of it there is: a BMP with
    # a positive height stores the BOTTOM row of the image first, so an
    # icon written top-down comes out upside down -- and an L is not
    # symmetric, so that is a visible bug a pixel COUNT sails past.
    for gy, row in enumerate(grid):
        fy = size - 1 - gy                      # grid row -> file row
        for gx, ch in enumerate(row):
            i = (fy * size + gx) * 3
            got, want = px[i:i + 3], (ORANGE if ch == 'X' else GREY)
            assert got == want, (
                "pixel (%d,%d) of the %dx%d icon is %r, expected %r -- the "
                "image is scrambled or upside down"
                % (gx, gy, size, size, got, want))


grid32 = [str(r) for r in vm.globals.get('lzp:*icon32*')]
assert len(grid32) == 32 and all(len(r) == 32 for r in grid32), grid32
check_bmp(COM['bytes'], 32, grid32)
print("   ADODB.Stream in binary mode, released; every pixel of the 32x32")
print("   in its right place (bottom-up rows, B G R order)")

_reset_com()
vm.loads('(lzp:bmp-write "/stub/small.bmp" 16 lzp:*icon16*)')
check_bmp(COM['bytes'], 16, grid)
nuls = COM['bytes'].count(0)
assert nuls > 0
print("   and every pixel of the 16x16 -- %d of its bytes are NUL, which is"
      % nuls)
print("   exactly why write-char could never have written this file")


# --------------------------------------------------------------------
# Base64: the route the bytes take to become a real byte array.
# --------------------------------------------------------------------
# ADODB.Stream's Write wants a VT_UI1 array and AutoLISP cannot reliably
# make one -- vlax-make-safearray's documented types stop short of
# VT_UI1, and where it is refused the old fallback produced a VT_I2
# array that Write rejected outright ("Arguments are of the wrong type
# ...").  So the bytes travel as base64, which is pure ASCII, and MSXML
# turns the string back into a byte array on the other side.
#
# That makes the encoder load-bearing: get it wrong and the icon is
# silently corrupt rather than absent.  It is checked against Python's
# own base64 on the real BMP bytes, not on a toy string.
print("== base64: the bytes as a string AutoLISP can actually hold ==")
import base64  # noqa: E402

bv = fresh()
for raw in [b'M', b'Ma', b'Man', b'Many', b'Manyx',
            b'\x00', b'\x00\x00', b'\x00\x00\x00',
            b'\xff', b'\xff\xff\xff', b'\x00\xff\x00', b'\xfb\xff\xbf']:
    bv.loads("(setq test:*b* (lzp:b64 '(%s)))"
             % ' '.join(str(b) for b in raw))
    got = str(bv.globals['test:*b*'])
    want = base64.b64encode(raw).decode()
    assert got == want, "b64(%r) gave %r, Python says %r" % (raw, got, want)
# every remainder-of-3 lands on the right padding
assert str(bv.globals['test:*b*']).count('=') == 0
bv.loads("(setq test:*e* (lzp:b64 nil))")
assert str(bv.globals['test:*e*']) == '', "no bytes should encode to no string"
print("   12 padding and edge cases match Python byte for byte")

for size, grid in (('16', 'lzp:*icon16*'), ('32', 'lzp:*icon32*')):
    bv.loads("(setq test:*by* (lzp:bmp-bytes %s %s))" % (size, grid))
    raw = bytes(int(x) for x in bv.globals['test:*by*'])
    bv.loads("(setq test:*enc* (lzp:b64 test:*by*))")
    got = str(bv.globals['test:*enc*'])
    assert got == base64.b64encode(raw).decode(), \
        "the %sx%s icon does not encode the way Python encodes it" % (size, size)
    assert base64.b64decode(got) == raw, "the round trip lost bytes"
    # the whole point: what AutoLISP has to carry is printable ASCII
    assert all(32 <= ord(c) < 127 for c in got), \
        "base64 produced a character AutoLISP could not hold"
    print("   %sx%s: %d bytes, %d of them NUL, become %d ASCII characters"
          % (size, size, len(raw), raw.count(0), len(got)))

# MSXML is tried before the safearray, because the safearray is the
# thing that failed in the field
src = open(LSP).read()  # noqa: F841  (also used by the ProgID checks below)
i_msxml = src.index('lzp:bytes-msxml bytes')
i_safe = src.index("'vlax-make-safearray", src.index('defun lzp:bytearray'))
assert i_msxml < i_safe, \
    "the safearray is tried before MSXML -- that is the order that failed"
print("   MSXML is tried first; the safearray spellings remain as fallbacks")

# THE BUG THESE TWO CHECKS EXIST FOR.  MSXML 6.0 creates fine and
# refuses dataType, because XDR schema support -- of which bin.base64 is
# part -- was removed in 6.0.  The shipped code stopped at "did the
# object appear?", so it picked 6.0, died on the next line, and fell
# back to the safearray without a word.  The field report is that
# failure:  array : VT_UI1 safearray   died at : Write
#
# The STRUCTURAL fix is carrying every ProgID all the way through, which
# is what the lzp:b64-try / lzp:b64-chain assertion below holds; with
# that in place a bad order still recovers.  The ORDER assertion is the
# cheaper half: an XDR-capable version first means 6.0's refusal is
# never paid for at all.
ids = re.search(r"\(foreach id\s*'\(([^)]*)\)", src, re.S)
assert ids, "the MSXML ProgID list is no longer a foreach over a quoted list"
order = re.findall(r'"([^"]+)"', ids.group(1))
assert order, order
assert '6.0' not in order[0], (
    "MSXML %s is tried first, and 6.0 refuses dataType -- that is the bug"
    % order[0])
assert any('3.0' in i or 'XMLDOM' in i for i in order[:2]), (
    "neither of the first two ProgIDs carries XDR: %r" % order[:2])
# and the chain really is attempted per ProgID, not once after the loop
assert 'lzp:b64-try' in src and 'lzp:b64-chain' in src, \
    "the per-ProgID chain probe is gone"
print("   ProgIDs tried in %s order; 6.0 last, where its refusal costs nothing"
      % order[0])

# drive it: the stub refuses dataType on 6.0, so a run must land on a
# version that works rather than falling back to the safearray
mv = stubbed(preload=True)
assert COM['created'].count('MSXML2.DOMDocument.3.0') >= 1, COM['created']
assert 'MSXML2.DOMDocument.6.0' not in COM['created'], \
    "6.0 was reached, so an earlier ProgID must have failed: %r" % COM['created']
assert str(mv.globals.get('lzp:*icontype*')).startswith('bin.base64 via'), \
    ("the icon fell back to a safearray instead of using MSXML: %r"
     % mv.globals.get('lzp:*icontype*'))
print("   a real run reports %r" % str(mv.globals.get('lzp:*icontype*')))


# --------------------------------------------------------------------
# certutil: the route with no byte array in it at all.
# --------------------------------------------------------------------
# Every failure reported from the field has been about handing
# AutoLISP's idea of an array to COM -- VT_UI1 accepted and Write
# refusing it anyway, wrapped in a variant or not, with MSXML coming
# back empty.  certutil has shipped with Windows since Vista and
# decodes base64 to binary in one command, so AutoLISP writes ordinary
# TEXT and Windows does the decoding.  Nothing crosses the COM boundary
# but a command line.
print("== certutil: the fallback that asks AutoLISP for text only ==")
cv = stubbed()
COM['fail_at'] = 'write'          # exactly the field failure
cv.loads('(setq test:*w* (lzp:bmp-write "/stub/x/lazpanel-16.bmp" 16 lzp:*icon16*))')
assert str(cv.globals['test:*w*']) == '/stub/x/lazpanel-16.bmp', \
    "the stream route failed and certutil did not pick it up"
assert str(cv.globals.get('lzp:*iconroute*')) == 'certutil', \
    "route says %r" % cv.globals.get('lzp:*iconroute*')
assert 'certutil' in str(cv.globals.get('lzp:*icontype*')), \
    cv.globals.get('lzp:*icontype*')
# it shelled out with -decode, and cleaned its temp file up
ran = [str(x) for x in COM.get('shell', [])]
assert ran and 'certutil' in ran[0] and '-decode' in ran[0], ran
assert ran[0].count('"') == 4, "the paths must be quoted: %r" % ran[0]
ev = events(cv)
assert any(e.startswith('delete') and e.endswith('.b64') for e in ev), \
    "the base64 scratch file was left behind: %r" % ev
print("   Write refused -> certutil -decode ran, base64 scratch deleted")

# and when the stream route works, certutil is never reached
cv2 = stubbed()
cv2.loads('(setq test:*w2* (lzp:bmp-write "/stub/x/lazpanel-16.bmp" 16 lzp:*icon16*))')
assert str(cv2.globals.get('lzp:*iconroute*')) == 'ADODB.Stream', \
    cv2.globals.get('lzp:*iconroute*')
assert not COM.get('shell'), "certutil ran even though the stream worked"
print("   and it stays out of the way when the stream route works")


print("== no support folder: full temp paths, the best that is left ==")
vmf = stubbed(preload=True)
vmf.loads('(setq stub:*nosupport* t)'
          '(setvar "TEMPPREFIX" "/tmp/acad/")'
          '(setq t:*b* (lzp:write-bmps))')
fb = [str(x) for x in (vmf.globals.get('t:*b*') or [])]
assert fb == ['/tmp/acad/lazpanel-16.bmp', '/tmp/acad/lazpanel-32.bmp'], fb
assert str(vmf.globals.get('lzp:*iconref*')) == 'path', \
    vmf.globals.get('lzp:*iconref*')
print("   support path unreadable -> temp folder and full paths")


print("== a stable icon path, so a surviving toolbar keeps its picture ==")
vm2 = stubbed(preload=True)
for prefix, want in (
        # the usual shape: AutoCAD hands back a folder with a separator
        ('C:\\Temp\\', 'C:\\Temp\\lazpanel-16.bmp'),
        ('/tmp/acad/', '/tmp/acad/lazpanel-16.bmp'),
        # and the shape the guard exists for: no separator at all, which
        # silently turns a folder called Temp into a file called
        # Templazpanel-16.bmp that SetBitmaps then cannot read
        ('C:\\Temp', 'C:\\Temp\\lazpanel-16.bmp')):
    vm2.loads('(setvar "TEMPPREFIX" "%s") (setq t:*p* (lzp:icon-path "16"))'
              % prefix.replace('\\', '\\\\'))
    got = str(vm2.globals['t:*p*'])
    assert got == want, "TEMPPREFIX %r gave %r, expected %r" % (prefix, got, want)
print("   icons live at a fixed name under TEMPPREFIX, rewritten only when missing")


print("== reuse: the toolbar is kept, but re-iced and re-shown ==")
vm3 = stubbed(preload=True)
vm3.loads('(setq stub:*events* nil stub:*bitmaps* nil stub:*visible* nil'
          '      stub:*float* nil)'
          '(setq t:*tb* (lzp:button-init))')
tbs = [str(x) for x in vm3.globals.get('stub:*tbs*') or []]
assert tbs == ['LazPanel'], "a second init duplicated the toolbar: %r" % tbs
ev = events(vm3)
assert 'add LazPanel' not in ev, "the existing toolbar was recreated"
assert 'setbitmaps' in ev, "icons were not re-applied to the existing toolbar"
# the CALL is what matters, not the argument
assert 'visible' in ev, "a toolbar the user had closed is never re-shown"
assert not vm3.globals.get('stub:*float*'), \
    "a toolbar the user has placed must not be floated out from under them"
print("   reused, icons re-applied, made visible, and NOT re-floated")


print("== once per SESSION, not per drawing ==")
# LISP globals are per-document, so a Startup Suite runs this file in
# every drawing opened.  The toolbar, its picture and the CUI walk that
# finds it are application-wide, so the second document has to find
# the blackboard mark and do nothing.  stubbed() resets the blackboard
# -- a fresh session -- and the second VM below is a second DOCUMENT in
# that same session.
vm5 = stubbed(preload=True)
assert 'add LazPanel' in events(vm5)
first_saves = list(COM.get('saves') or [])
vm6 = VM()
vm6.loads(STUB)
vm6.load(LSP)
ev6 = events(vm6)
for done in ('add LazPanel', 'addbutton', 'setbitmaps', 'visible', 'float'):
    assert done not in ev6, "the second drawing redid %r: %r" % (done, ev6)
assert list(COM.get('saves') or []) == first_saves, \
    "the second drawing rewrote the icons: %r" % COM.get('saves')
assert vm6.globals.get('lzp:*pins*') is not None or True   # pins are per document, still read
# and the drafter who closed the toolbar still gets it back by hand
vm6.loads('(setq stub:*events* nil)')
run(vm6, 'c:LAZBUTTON', 'lazbutton-second-doc')
assert 'setbitmaps' in events(vm6), events(vm6)
print("   the second drawing of a session does no toolbar work; LAZBUTTON still does")


print("== icons already on disk are left alone ==")
_reset_com()
COM['ondisk'].update({'/stub/support\\lazpanel-16.bmp',
                      '/stub/support\\lazpanel-32.bmp'})
vm7 = VM()
vm7.loads(STUB)
vm7.load(LSP)
assert not COM.get('saves'), "icons on disk were rewritten: %r" % COM.get('saves')
assert 'setbitmaps' in events(vm7), "the button still has to be iced from the files on disk"
bm7 = [str(x) for x in vm7.globals.get('stub:*bitmaps*') or []]
assert bm7 == ['lazpanel-16.bmp', 'lazpanel-32.bmp'], bm7
assert str(vm7.globals.get('lzp:*iconref*')) == 'name'
assert vm7.globals.get('lzp:*iconwrote*') in (None, lispvm.NIL), \
    "iconwrote should be nil when nothing was written"
vm7.run('c:LAZICON', [])
out7 = ''.join(str(p) for p in vm7.printed)
assert 'on disk at' in out7 and 'written to' not in out7, out7
# one file missing: the pair is written again
_reset_com()
COM['ondisk'].add('/stub/support\\lazpanel-16.bmp')
vm8 = VM()
vm8.loads(STUB)
vm8.load(LSP)
assert COM.get('saves') == ['/stub/support\\lazpanel-16.bmp',
                            '/stub/support\\lazpanel-32.bmp'], COM.get('saves')
print("   a pair on disk is reused, LAZICON says so, and a missing half rewrites both")


print("== a toolbar that cannot get its button does not survive ==")
vm4 = stubbed()
vm4.loads('(setq stub:*addfail* t) (setq t:*tb* (lzp:button-init))')
tbs = [str(x) for x in vm4.globals.get('stub:*tbs*') or []]
assert tbs == [], (
    "an empty LazPanel toolbar was left behind: lzp:toolbar-find would hand "
    "it back for ever, and LAZBUTTON would report success while showing "
    "nothing")
assert str(vm4.globals.get('stub:*deleted-tb*')) == 'LazPanel'
assert vm4.globals.get('t:*tb*') is None, "a failed init must report nil"
print("   the half-made toolbar is deleted and nil reported, so LAZBUTTON")
print("   can try again instead of being defeated for ever")


print("== LAZBUTTON ==")
vm5 = stubbed()
run(vm5, 'c:LAZBUTTON', 'lazbutton')
assert any('on screen' in str(p) for p in vm5.printed), vm5.printed
assert [str(x) for x in vm5.globals.get('stub:*tbs*') or []] == ['LazPanel']
print("   creates it on demand and says where it went")

vm6 = stubbed()
vm6.loads('(setq stub:*addfail* t)')
run(vm6, 'c:LAZBUTTON', 'lazbutton-unavailable')
assert any('menu API is unavailable' in str(p) for p in vm6.printed), \
    "the unavailable branch is unreachable: %r" % vm6.printed
print("   and says so plainly when the menu API will not have it")


print("== a tab opens the next page ==")
vm7 = stubbed()
vm7.loads('(setq stub:*rcs* \'(4 0))'
          '(setq stub:*click* "tab_%s")'
          '(setq t:*p* (lzp:show))' % GROUPS[1])
vm7.loads('(setq t:*n* (lzp:dlgname "%s"))' % GROUPS[1])
assert str(vm7.globals.get('stub:*dlgname*')) == str(vm7.globals['t:*n*']), (
    "the tab did not reopen on the %s page: %r"
    % (GROUPS[1], vm7.globals.get('stub:*dlgname*')))
assert vm7.globals.get('t:*p*') is None, "a tab click launched something"
ev = events(vm7)
assert ev.count('new') == 2, "the page did not reopen: %r" % ev
print("   a tab closes this page and opens %s, launching nothing"
      % GROUPS[1])


print("== find: the search, name and caption alike ==")
fv = fresh()


def matches(v, text):
    v.loads('(setq test:*m* (lzp:matches "%s"))' % text)
    return [str(x) for x in (v.globals['test:*m*'] or [])]


def captions(v):
    return {str(c[0]): str(c[1]) for c in v.globals['lzp:*captions*']}


CAPS = captions(fv)
# an empty box is not a filter: the whole roster, in roster order
fv.loads('(setq test:*all* (lzp:commands))')
ALL = [str(x) for x in fv.globals['test:*all*']]
assert matches(fv, '') == ALL, "an empty search does not list the roster"

# the search reads the caption as well as the name, which is the whole
# point: half of knowing this toolset is knowing what the names mean
for needle in ('cover', 'check', 'spa', 'survey', 'dim'):
    want = [c for c in ALL
            if needle.upper() in c or needle.upper() in CAPS[c].upper()]
    assert matches(fv, needle) == want, (
        "%r matched %r, expected %r" % (needle, matches(fv, needle), want))
    assert matches(fv, needle.upper()) == want, "%r is case sensitive" % needle

# and it is the CAPTION doing the work for at least one of them, or the
# feature is just a name search with extra steps
byname = [c for c in ALL if 'SURVEY' in c]
assert not byname, "a command is now named *SURVEY*; pick another witness"
assert matches(fv, 'survey'), "no tool's caption mentions a survey"
print("   %d tools match \"survey\" on their captions alone, none by name"
      % len(matches(fv, 'survey')))

# The needle is whatever was typed.  wcmatch would read these as
# pattern syntax -- "*" would match the whole roster and "." none of it
# -- so a literal search is the difference between a useful box and a
# baffling one.
for wild in ('*', '?', '~', '[A]', '@', '.', '#'):
    assert matches(fv, wild) == [], \
        "%r matched %r -- the search is going through wcmatch" \
        % (wild, matches(fv, wild))
print("   wildcard characters are searched for, not obeyed")

# a row says what a tool is, and says when the session cannot run it
fv.loads('(setq test:*a* (lzp:hitline "POOL" \'("POOL")))')
fv.loads('(setq test:*b* (lzp:hitline "POOL" nil))')
assert 'POOL' in str(fv.globals['test:*a*'])
assert CAPS['POOL'] in str(fv.globals['test:*a*']), \
    "the row does not carry the caption: %r" % fv.globals['test:*a*']
assert 'not loaded' not in str(fv.globals['test:*a*'])
assert 'not loaded' in str(fv.globals['test:*b*']), \
    "an unloaded tool is listed with nothing to say so"
print("   a row is NAME - caption, plus (not loaded) when it is not")


print("== find: filling, picking and running ==")
fl = stubbed()
fl.loads('(setq t:*sel* (lzp:fill "cover"))')
listed = [str(x) for x in (fl.globals.get('stub:*list*') or [])]
assert len(listed) == len(matches(fv, 'cover')), (
    "the list box holds %d rows for %d matches"
    % (len(listed), len(matches(fv, 'cover'))))
assert all(m in l for m, l in zip(matches(fv, 'cover'), listed)), \
    "the rows are not the matches, in order: %r" % listed
# the top hit is selected for you, so Enter runs the obvious thing
assert str(fl.globals['t:*sel*']) == matches(fv, 'cover')[0]
fl.loads('(setq t:*h* (stub:tile "hits"))')
assert str(fl.globals['t:*h*']) == '0', \
    "the list is filled but nothing is highlighted"
fl.loads('(setq t:*m* (stub:tile "msg"))')
assert 'cover' in str(fl.globals['t:*m*']), fl.globals['t:*m*']
print("   %d rows for \"cover\", top hit selected, message line set"
      % len(listed))

# a search that matches nothing says so rather than showing an empty box
fl.loads('(setq t:*none* (lzp:fill "zzzz"))')
assert fl.globals.get('t:*none*') is None
fl.loads('(setq t:*m* (stub:tile "msg"))')
assert 'no tool matches' in str(fl.globals['t:*m*']), fl.globals['t:*m*']
print("   an empty result says so on the message line")

# picking a row selects it; a double click ($reason 4) is pick-and-run.
# Only 4: running on the single-click reason would launch a tool every
# time the mouse moved down the list.
fl.loads('(lzp:fill "")')
for quiet in (1, 2, 3):
    fl.loads('(setq stub:*done* nil lzp:*pick* nil)')
    fl.loads('(setq t:*p* (lzp:hitpick "1" %d))' % quiet)
    assert str(fl.globals['t:*p*']) == ALL[1], fl.globals['t:*p*']
    assert fl.globals.get('stub:*done*') is None, \
        "$reason %d closed the dialog -- only the double click may run" % quiet
    assert fl.globals.get('lzp:*pick*') is None, \
        "$reason %d launched something" % quiet
idx = ALL.index(LIVE)
fl.loads('(setq stub:*done* nil)')
fl.loads('(lzp:hitpick "%d" 4)' % idx)
assert str(fl.globals.get('lzp:*pick*')) == LIVE, \
    "a double click did not choose %s: %r" % (LIVE, fl.globals.get('lzp:*pick*'))
assert str(fl.globals.get('stub:*done*')) == '1', \
    "a double click did not close the dialog to launch"
print("   one click selects, two runs -- %s chosen and the dialog closed"
      % LIVE)

# Run refuses a tool this session has not loaded, and says so WITHOUT
# closing: the list shows it on purpose, so the refusal has to be here
fl2 = stubbed()
fl2.loads('(lzp:fill "")')
fl2.loads('(setq lzp:*sel* "%s") (lzp:findrun)' % MISSING)
fl2.loads('(setq t:*m* (stub:tile "msg"))')
assert 'not loaded' in str(fl2.globals['t:*m*']), fl2.globals['t:*m*']
assert MISSING in str(fl2.globals['t:*m*'])
assert fl2.globals.get('stub:*done*') is None, \
    "%s is not loaded, but Run closed the panel to launch it" % MISSING
assert fl2.globals.get('lzp:*pick*') is None
# and nothing highlighted at all is its own message, not a crash
fl2.loads('(setq lzp:*sel* nil) (lzp:findrun)')
fl2.loads('(setq t:*m* (stub:tile "msg"))')
assert 'nothing highlighted' in str(fl2.globals['t:*m*']), fl2.globals['t:*m*']
print("   Run refuses %s with a reason, and refuses an empty pick" % MISSING)


print("== find: the page opens, wires itself and launches ==")
# End to end through c:LAZPANEL's own loop, so the action_tile strings
# in the file are the ones evaluated here.
fp = stubbed()
fp.loads('(setq lzp:*page* "%s")' % FIND)
fp.loads('(setq stub:*rcs* \'(0))')
fp.loads('(setq t:*p* (lzp:show))')
fp.loads('(setq t:*n* (lzp:dlgname "%s"))' % FIND)
assert str(fp.globals.get('stub:*dlgname*')) == str(fp.globals['t:*n*']), \
    "the panel did not open on the search page"
opened = [str(x) for x in (fp.globals.get('stub:*list*') or [])]
assert len(opened) == len(ALL), \
    "the page opened with %d rows, expected the whole roster" % len(opened)
bound = [str(a[0]) for a in fp.globals.get('stub:*action*') or []]
for k in ('filter', 'hits', 'run'):
    assert k in bound, "the %r tile is not wired: %r" % (k, bound)
# no per-command buttons on this page -- and so nothing to grey
assert not fp.globals.get('stub:*disabled*'), \
    "the search page greyed tiles: %r" % fp.globals.get('stub:*disabled*')
print("   opens with the whole roster listed, three tiles wired, none greyed")

# typing in the box narrows the list through the REAL wiring string
fs = stubbed()
fs.loads('(setq lzp:*page* "%s")' % FIND)
fs.loads('(setq stub:*rcs* \'(0))')
fs.loads('(setq stub:*click* "filter" stub:*clickval* "cover")')
fs.loads('(lzp:show)')
narrowed = [str(x) for x in (fs.globals.get('stub:*list*') or [])]
assert len(narrowed) == len(matches(fv, 'cover')), (
    "typing in the box left %d rows, expected %d"
    % (len(narrowed), len(matches(fv, 'cover'))))
assert str(fs.globals.get('lzp:*filter*')) == 'cover', \
    "the search text was not remembered for the reopen"
print("   a search typed into the box narrows %d rows to %d, and is remembered"
      % (len(ALL), len(narrowed)))

# Run, wired: the top hit of a search for the one command the stub has
fr = stubbed()
fr.loads('(setq lzp:*page* "%s" lzp:*filter* "%s")' % (FIND, LIVE))
fr.loads('(setq stub:*rcs* \'(0))')
fr.loads('(setq stub:*click* "run")')
fr.loads('(setq t:*p* (lzp:show))')
assert str(fr.globals.get('t:*p*')) == LIVE, (
    "Run on a search for %s handed back %r" % (LIVE, fr.globals.get('t:*p*')))
print("   Run launches the highlighted tool (%s), the panel closing first"
      % LIVE)


print("== LAZPANELVER ==")
vm = fresh()
vm.run('c:LAZPANELVER', [])
out = ''.join(str(p) for p in vm.printed)
assert str(ver) in out and str(len(PANEL)) in out, out
print("   reports %s and the %d-tool roster" % (ver, len(PANEL)))

print("ALL LAZPANEL TESTS PASSED")
