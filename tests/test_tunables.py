"""Every file with a knob block: all at the top, all explained, none stray.

The chart forms and the panel are the files a person tunes -- a budget
that has to change when a name gets longer, a ceiling that depends on
the screen, a registry key an installer moves.  Those numbers used to
be scattered down eight hundred to two thousand lines, each beside the
code that read it, and finding them meant reading the file.

Each of them now opens with a **tunables block**: every knob, with a
sentence saying what changing it does.  This is what keeps that true,
because a block that is merely tidy today is a block someone adds the
next knob underneath.

FILES below is the roster, and a tool joins it as it grows a block --
AutoDim did, with the styles, stand-offs and side-view thresholds a
drafter tunes.  STANDARDS.md section 5 asks for the block and for the
README row; it is this file that holds a tool to both.  The rule names
`tunables` as the word to use and leaves the older spellings alone
where they got there first, so how a file marks its block off travels
in its FILES row rather than being one constant.

1. Every file has one, and it comes BEFORE the first defun -- a knob
   defined after the code that reads it is nil while that code loads.
2. Every knob says what CHANGING it does, in a comment beside it or
   over the run it belongs to.  A block that is only a list of numbers
   moves the reading somewhere else rather than saving it.  A knob
   appended to an existing run inherits that run's paragraph and passes
   here -- check 5 is the backstop, because it still has no README row.
3. Every knob in a block is a literal nothing ever re-assigns.  A state
   variable hoisted in by mistake would read as a setting when it is
   really an initial value, and setting it would look like it worked.
4. No knob-shaped global lives OUTSIDE its block.  The exemption is the
   mirror's own ``drop_globals`` -- the stroke font and the tile
   palette, which the grouped build replaces with ``CALOFIN-LIB.lsp``'s
   -- read from tools/mirror_shared.py rather than listed here, so a
   change to what the library owns cannot make this check wrong.
5. Every knob is in its README's Tunables table, with the default it
   really has.  The sentence beside it is editorial and not compared;
   its presence is.
6. The knobs the VB palette shares -- the registry keys, the recent cap,
   the step ceiling -- say the same thing on both surfaces.  Only the
   four UI files reach the palette; a tool with no VB surface is not
   checked here and does not need to be.

Run: python3 tests/test_tunables.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import mirror_shared  # noqa: E402
from callib import ROOT, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


#: How a file rules its block off: the header line, and the first line
#: that is past it.  The four UI files use the `tunables` spelling
#: STANDARDS.md section 5 asks new work for; AutoDim's block got there
#: under `SETTINGS` and closes itself explicitly, which the same rule
#: leaves alone.
TUNABLES = (';;; -------------------- tunables ', '\n;;; ---')
SETTINGS = (';;;  SETTINGS\n', '\n;;; =' + '=' * 49 + ' end of SETTINGS')

#: (tool as mirror_shared names it, source, namespace, README, markers)
FILES = [
    ('LAZPANEL', ROOT / 'lisp' / 'lazpanel' / 'LAZPANEL.lsp', 'lzp',
     ROOT / 'lisp' / 'lazpanel' / 'README.md', TUNABLES),
    ('LAZFORM', ROOT / 'lisp' / 'lazform' / 'LAZFORM.lsp', 'lzf',
     ROOT / 'lisp' / 'lazform' / 'README.md', TUNABLES),
    ('LAZSPA', ROOT / 'lisp' / 'lazspa' / 'LAZSPA.lsp', 'lzs',
     ROOT / 'lisp' / 'lazspa' / 'README.md', TUNABLES),
    ('LAZSTEP', ROOT / 'lisp' / 'lazstep' / 'LAZSTEP.lsp', 'lzt',
     ROOT / 'lisp' / 'lazstep' / 'README.md', TUNABLES),
    ('AutoDim', ROOT / 'lisp' / 'autodim' / 'AutoDim.lsp', 'ad',
     ROOT / 'lisp' / 'autodim' / 'README.md', SETTINGS),
]


def split_block(src, markers):
    """(block, everything else). The block runs from its own header to
    the first line past it."""
    head, end = markers
    i = src.index(head)
    j = src.index(end, i + len(head))
    return src[i:j], src[:i] + src[j:]


def knobs_in(block, ns):
    """[(name, default)] in the order the block sets them."""
    return [(m.group(1), m.group(2).strip()) for m in re.finditer(
        r'^\(setq (' + ns + r':\*[a-z0-9-]+\*)\s+(.*?)\)[ \t]*(?:;.*)?$',
        block, re.M)]


def assigned(src, ns):
    """{ns:*x*: [offset of each setq that writes it]}.

    Offsets, not a bare set, and that is the whole point.  The stray
    check asks
    "is this global written anywhere ELSE?" of a setq it is standing
    on;
    a set cannot answer that, because the match it is asking about is in
    it.  That made the stray check vacuous for the one case it exists to catch
    -- a knob moved out of the block back beside its code writes itself,
    so it was read as state and excused.  With offsets the question is
    "written at some offset other than this one", which is the question.

    The other thing to get right: a multi-variable setq assigns every
    pair, not just the first.  ``(setq lzf:*dx* a lzf:*dy* b)`` writes
    both, and reading only the name after ``(setq`` calls the second one
    a constant.  So the form is walked -- but by PAIRS, not by depth:
    a setq's top-level items alternate name, value, name, value, so a
    knob is assigned only in an even slot.  In an odd one it is being
    READ, which ``(setq tol ad:*merge-tol*)`` does and which counting
    every name at depth 0 called a second assignment -- and so called
    the knob state.  A knob named in a ``;`` comment inside the form is
    not an item at all.
    """
    name = re.compile(ns + r':\*[a-z0-9-]+\*')

    def skip_string(t, j):
        j += 1
        while j < len(t) and t[j] != '"':
            j += 2 if t[j] == '\\' else 1
        return j + 1

    def skip_comment(t, j):
        while j < len(t) and t[j] != '\n':
            j += 1
        return j

    out = {}
    for m in re.finditer(r'\(setq\b', src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            c = src[i]
            if c == '"':
                i = skip_string(src, i) - 1
            elif c == ';':
                i = skip_comment(src, i)
                continue
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if not depth:
                    break
            i += 1
        body, slot, j = src[m.end():i], 0, 0
        while j < len(body):
            c = body[j]
            if c in ' \t\n\r':
                j += 1
            elif c == ';':                    # a comment is not an item
                j = skip_comment(body, j)
            elif c == "'":                   # belongs to the item after it
                j += 1
            elif c == '"':                    # a string value
                j = skip_string(body, j)
                slot += 1
            elif c == '(':                    # one whole form, however deep
                d = 0
                while j < len(body):
                    ch = body[j]
                    if ch == '"':
                        j = skip_string(body, j)
                        continue
                    if ch == ';':
                        j = skip_comment(body, j)
                        continue
                    if ch == '(':
                        d += 1
                    elif ch == ')':
                        d -= 1
                        if not d:
                            j += 1
                            break
                    j += 1
                slot += 1
            else:                             # a bare atom
                k = j
                while j < len(body) and body[j] not in ' \t\n\r();':
                    j += 1
                if slot % 2 == 0 and name.fullmatch(body[k:j]):
                    out.setdefault(body[k:j], []).append(m.start())
                slot += 1
    return out


def why_of(lines, i):
    """What line I of a block says about changing the knob it sets.

    Either a remark after the value, the ``;`` lines continuing under
    it, or the ``;;`` comment standing over the run of setqs this one
    is in -- the frame numbers share one paragraph and then a word
    each, and that is the right shape for them.  '' when none is there.

    The continuation case is what a setq too long to take a remark on
    its own line does (AutoDim's two entity-type lists), and reading
    only the line itself called those unexplained.
    """
    ln, j, q = lines[i], 0, False
    while j < len(ln):
        if ln[j] == '"':
            q = not q
        elif ln[j] == ';' and not q:
            return ln[j:].strip('; ').strip()
        j += 1
    # the ;-comment lines continuing underneath, before the next setq
    below = []
    k = i + 1
    while k < len(lines) and lines[k].lstrip().startswith(';'):
        below.append(lines[k].lstrip(';').strip())
        k += 1
    if below:
        return " ".join(below).strip()
    k = i - 1
    while k >= 0 and lines[k].startswith('(setq '):
        k -= 1
    why = []
    while k >= 0 and lines[k].lstrip().startswith(';'):
        why.insert(0, lines[k].lstrip(';').strip())
        k -= 1
    return " ".join(why).strip()


MARK = 'NOT A KNOB:'


def marked(src, at):
    """The reason a constant gives for not being a knob, or ''.

    A global can be knob-shaped -- a literal at the top level that
    nothing re-assigns -- and still not be a setting: LAZPANEL's base64
    alphabet is RFC 4648's, and reordering a character in it does not
    adjust anything, it decodes the icon to garbage.  Hoisting one of
    those into the block would advertise it as safe to change.

    So the file says so, in the comment block directly above it, and
    says why.  The reason is what is checked -- a bare marker would be
    an opt-out rather than a fact about the constant.
    """
    head = src.rfind('\n\n', 0, at)
    for line in src[head + 1:at].splitlines():
        if MARK in line:
            tail = src[head + 1:at].split(MARK, 1)[1]
            return " ".join(re.sub(r'^\s*;+', '', ln)
                            for ln in tail.splitlines()).strip()
    return ''


def table_of(readme):
    """{global: default} out of the README's Tunables table."""
    m = re.search(r'^## Tunables\b.*?(?=^## |\Z)', read(readme), re.M | re.S)
    if not m:
        return None
    return {r.group(1): r.group(2) for r in
            re.finditer(r'^\| `([a-z]+:\*[a-z0-9-]+\*)` \| `(.*?)` \|',
                        m.group(0), re.M)}


print("== 1. every file opens with a tunables block ==")

BLOCKS = {}
for tool, path, ns, _readme, mk in FILES:
    src = read(path)
    check("%s has one" % tool, mk[0] in src)
    if mk[0] not in src:
        continue
    block, rest = split_block(src, mk)
    BLOCKS[tool] = (src, block, rest, ns)
    first_defun = src.index('\n(defun ')
    check("%s: it comes before the first defun" % tool,
          src.index(mk[0]) < first_defun,
          "a knob defined after the code that reads it is nil while "
          "that code loads")
    check("%s: %d knob(s)" % (tool, len(knobs_in(block, ns))),
          len(knobs_in(block, ns)) > 0)


print("== 2. every knob says what changing it does ==")

for tool, path, ns, _readme, mk in FILES:
    if tool not in BLOCKS:
        continue
    _src, block, _rest, _ns = BLOCKS[tool]
    lines = block.splitlines()
    for i, ln in enumerate(lines):
        m = re.match(r'^\(setq (' + ns + r':\*[a-z0-9-]+\*)', ln)
        if not m:
            continue
        why = why_of(lines, i)
        check("%-18s %s" % (m.group(1), why[:46]), len(why) > 15,
              "nothing here says what changing it does, and a block that "
              "is a list of numbers moves the reading rather than saves it")


print("== 3. a knob is a literal nothing re-assigns ==")

for tool, path, ns, _readme, mk in FILES:
    if tool not in BLOCKS:
        continue
    _src, block, rest, _ns = BLOCKS[tool]
    written = assigned(rest, ns)
    bad = [n for n, _ in knobs_in(block, ns) if n in written]
    check("%s: no knob is written to elsewhere" % tool, not bad,
          "%s -- that is state, and hoisting it here reads as a setting "
          "when it is an initial value" % bad)


print("== 4. no knob-shaped global lives outside its block ==")

for tool, path, ns, _readme, mk in FILES:
    if tool not in BLOCKS:
        continue
    _src, block, rest, _ns = BLOCKS[tool]
    # what the grouped build takes from the library instead -- read from
    # the mirror, so this stays right when the library grows
    exempt = set(mirror_shared.TOOLS[tool]['drop_globals'])
    written = assigned(rest, ns)
    stray, excused = [], []
    for m in re.finditer(r'^\(setq (' + ns + r':\*[a-z0-9-]+\*)\s+([^\s)]+)',
                         rest, re.M):
        name, first = m.group(1), m.group(2)
        if name in exempt:
            continue
        if first.startswith("'") or first.startswith("("):
            continue                     # a data table, not a knob
        if first in ('nil', 'T'):
            continue                     # state
        if [o for o in written.get(name, []) if o != m.start()]:
            continue                     # state: some OTHER setq writes it
        why = marked(rest, m.start())
        if why:
            excused.append((name, why))
            continue
        stray.append(name)
    check("%s: none stray" % tool, not stray,
          "%s is a literal nothing re-assigns, so it is a knob and "
          "belongs in the block, or says NOT A KNOB and why" % stray)
    for name, why in excused:
        check("%-18s NOT A KNOB: %s" % (name, why[:40]), len(why) > 20,
              "the marker has to say WHY, or it is a way to opt out of "
              "the check rather than a fact about the constant")
    check("%s: %d font/palette global(s) exempt, as the mirror says"
          % (tool, len(exempt)),
          all(e.startswith(ns + ':') for e in exempt), repr(sorted(exempt)))


print("== 5. every knob is in its README, with the default it has ==")

for tool, path, ns, readme, mk in FILES:
    if tool not in BLOCKS:
        continue
    _src, block, _rest, _ns = BLOCKS[tool]
    told = table_of(readme)
    check("%s README has a Tunables table" % tool, told is not None)
    if told is None:
        continue
    for name, default in knobs_in(block, ns):
        # the README writes a Lisp string as it is written in the Lisp
        check("%-18s %s" % (name, default[:44]),
              told.get(name) == default,
              "README says %r" % told.get(name))
    extra = sorted(set(told) - {n for n, _ in knobs_in(block, ns)})
    check("%s README names no knob the file has not" % tool, not extra,
          repr(extra))


print("== 6. the knobs the two surfaces share ==")

VB = {p.name: read(p) for p in (ROOT / 'ui' / 'calofin_net').glob('*.vb')}
ALLVB = "\n".join(VB.values())
CATALOG = read(ROOT / 'ui' / 'calofin_net' / 'Generated' / 'ChartCatalog.g.vb')


def value(tool, name):
    _src, block, _rest, ns = BLOCKS[tool]
    return dict(knobs_in(block, ns))[name]


def lisp_str(v):
    """A Lisp string literal as VB spells it: VB has no backslash
    escape, so LAZPANEL's "\\\\Software" is VB's "\\Software"."""
    return v.strip('"').replace('\\\\', '\\')


for tool, knob, where in (('LAZPANEL', 'lzp:*pinkey*', 'PaletteMemory.vb'),
                          ('LAZFORM', 'lzf:*recallkey*', 'ChartFormView.vb'),
                          ('LAZSPA', 'lzs:*recallkey*', 'ChartFormView.vb'),
                          ('LAZSTEP', 'lzt:*recallkey*', 'ChartFormView.vb')):
    want = lisp_str(value(tool, knob))
    check("%-16s is the key %s uses" % (knob, where),
          ('"%s"' % want) in VB[where], want)

check("lzp:*reclimit* is PaletteMemory.RecentLimit",
      ("RecentLimit As Integer = %s" % value('LAZPANEL', 'lzp:*reclimit*'))
      in VB['PaletteMemory.vb'], value('LAZPANEL', 'lzp:*reclimit*'))
check("lzt:*max-steps* is ChartCatalog.MaxSteps",
      ("MaxSteps As Integer = %s" % value('LAZSTEP', 'lzt:*max-steps*'))
      in CATALOG, value('LAZSTEP', 'lzt:*max-steps*'))

# and the two treatment lists, which the palette must send as written
for tool, knob, const in (('LAZFORM', 'lzf:*ctreat*', 'PoolTreatments'),
                          ('LAZSPA', 'lzs:*ctreat*', 'SpaTreatments')):
    words = re.findall(r'"([^"]*)"', value(tool, knob))
    check("%-16s is ChartCatalog.%s, in order" % (knob, const),
          ("%s As String() = {%s}"
           % (const, ", ".join('"%s"' % w for w in words))) in CATALOG,
          repr(words))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL TUNABLES CHECKS PASSED (%d knobs over %d files)"
      % (sum(len(knobs_in(BLOCKS[t][1], BLOCKS[t][3])) for t in BLOCKS),
         len(BLOCKS)))
