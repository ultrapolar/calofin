"""Every knob block in the tree: all at the top, all explained, none stray.

The chart forms and the panel are the files a person tunes -- a budget
that has to change when a name gets longer, a ceiling that depends on
the screen, a registry key an installer moves.  Those numbers used to
be scattered down eight hundred to two thousand lines, each beside the
code that read it, and finding them meant reading the file.

Each of the four now opens with a **tunables block**: every knob, with
a sentence saying what changing it does.  This is what keeps that true,
because a block that is merely tidy today is a block someone adds the
next knob underneath.

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
   the step ceiling -- say the same thing on both surfaces.

The four GUI files came first and check 6 is still theirs -- they are
the ones whose knobs the VB palette shares.  Checks 1-5 are the general
rule (STANDARDS.md section 5, "Tunables") and every file in FILES meets
them; ``abcdef`` and ``ALTABCDEF`` joined when they grew blocks of their
own.

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


#: How a file rules its block off: its header line, and the first line
#: past it.  Most use the `tunables` spelling STANDARDS.md section 5
#: asks new work for; AutoDim's block got there under `SETTINGS` and
#: closes itself explicitly, which the same rule leaves alone.  So this
#: travels in the FILES row rather than being one constant.
TUNABLES = (';;; -------------------- tunables ', '\n;;; ---')
SETTINGS = (';;;  SETTINGS\n', '\n;;; =' + '=' * 49 + ' end of SETTINGS')
#: The check family rules its block off with a banner naming itself at
#: both ends, which reads better in a 4,000-line file than a single
#: rule does -- same block, same rule, its own furniture.
BANNER = (';;;  TUNABLES', '\n;;;  END TUNABLES')


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
    # the two point plotters, which grew blocks of their own: the same
    # rule, and the same reason -- a confidence weight or a drop-evidence
    # ratio buried beside the solver is a number nobody can reach
    ('abcdef', ROOT / 'lisp' / 'abcdef' / 'abcdef.lsp', 'abcdef',
     ROOT / 'lisp' / 'abcdef' / 'README.md', TUNABLES),
    ('ALTABCDEF', ROOT / 'lisp' / 'altabcdef' / 'ALTABCDEF.lsp', 'altabcdef',
     ROOT / 'lisp' / 'altabcdef' / 'README.md', TUNABLES),
    # AutoDim, whose block is the styles, stand-offs and side-view
    # thresholds a drafter tunes -- and which rules it off as SETTINGS,
    # the older spelling the rule leaves where it got there first
    ('AutoDim', ROOT / 'lisp' / 'autodim' / 'AutoDim.lsp', 'ad',
     ROOT / 'lisp' / 'autodim' / 'README.md', SETTINGS),
    # the check family.  Six of the ten name their globals tool:*x*, so
    # they read here; the other four (CHECK, DIMCHECK, LINFINCHECK,
    # COVERCHECK) still spell theirs *tool-x*, which this file's
    # namespace pattern cannot see -- their own suites carry the same
    # three assertions until that rename happens.
    ('SPACHECK', ROOT / 'lisp' / 'spacheck' / 'SPACHECK.lsp', 'spachk',
     ROOT / 'lisp' / 'spacheck' / 'README.md', BANNER),
    ('ABPCHECK', ROOT / 'lisp' / 'abpcheck' / 'ABPCHECK.lsp', 'abp',
     ROOT / 'lisp' / 'abpcheck' / 'README.md', BANNER),
    ('ABCURCHECK', ROOT / 'lisp' / 'abcurcheck' / 'ABCURCHECK.lsp', 'acc',
     ROOT / 'lisp' / 'abcurcheck' / 'README.md', BANNER),
    ('lincheck', ROOT / 'lisp' / 'lincheck' / 'lincheck.lsp', 'lin',
     ROOT / 'lisp' / 'lincheck' / 'README.md', BANNER),
    ('ccprecheck', ROOT / 'lisp' / 'ccprecheck' / 'ccprecheck.lsp', 'chk',
     ROOT / 'lisp' / 'ccprecheck' / 'README.md', BANNER),
    ('LINTXTCHK', ROOT / 'lisp' / 'lintxtchk' / 'LINTXTCHK.lsp', 'ltc',
     ROOT / 'lisp' / 'lintxtchk' / 'README.md', BANNER),
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
    a constant.  So the form is walked and every name at paren depth 0
    inside it counts -- but only in a NAME position.

    That last clause is the one to be careful about.  A setq alternates
    name, value, name, value, and a knob is perfectly ordinary in a
    VALUE position: ``(setq iter abcdef:*solve-iters*)`` reads the knob
    to end a loop and ``(setq th abcdef:*text-min*)`` reads it to floor
    a text height.  Counting those as writes calls a constant state and
    fails a file for using its own settings, so the depth-0 atoms are
    counted off in pairs and only the even ones are assignments.  A
    parenthesised value takes one slot like any other atom, and a quote
    binds to the token after it rather than taking a slot of its own.
    """
    out = {}
    for m in re.finditer(r'\(setq\b', src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            c = src[i]
            if c == '"':
                i += 1
                while i < len(src) and src[i] != '"':
                    i += 2 if src[i] == '\\' else 1
            elif c == ';':
                while i < len(src) and src[i] != '\n':
                    i += 1
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if not depth:
                    break
            i += 1
        d = k = 0
        for t in re.finditer(r'"(?:[^"\\]|\\.)*"|;[^\n]*|[()\']|[^\s()\'";]+',
                             src[m.end():i]):
            s = t.group(0)
            if s == '(':
                if d == 0:
                    k += 1                    # a list is one value slot
                d += 1
            elif s == ')':
                d -= 1
            elif d or s == "'" or s.startswith(';') or s.startswith('"'):
                continue                      # nested, quote, comment
            else:
                if k % 2 == 0 and re.fullmatch(ns + r':\*[a-z0-9-]+\*', s):
                    out.setdefault(s, []).append(m.start())
                k += 1
    return out


def why_of(lines, i):
    """What line I of a block says about changing the knob it sets.

    Either a remark after the value, the ``;`` lines continuing under
    it, or the ``;;`` comment standing over the run of setqs this one
    is in -- the frame numbers share one paragraph and then a word
    each, and that is the right shape for them.  '' when none is there.

    The continuation case is what a setq too long to leave room for a
    remark does (AutoDim's two entity-type lists run to the margin).
    Reading only the line itself called those unexplained -- and worse,
    let the NEXT knob down inherit their paragraph and pass.
    """
    parts = []
    ln, j, q = lines[i], 0, False
    while j < len(ln):
        if ln[j] == '"':
            q = not q
        elif ln[j] == ';' and not q:
            parts.append(ln[j:].strip('; ').strip())
            break
        j += 1
    # the ;-comment lines continuing underneath, before the next setq
    k = i + 1
    while k < len(lines) and lines[k].lstrip().startswith(';'):
        parts.append(lines[k].lstrip(';').strip())
        k += 1
    # ...and the ;; paragraph standing over the run this setq is in.
    # All three are joined rather than the first one winning: the check
    # family writes the UNIT as the remark and the explanation in the
    # paragraph above, and a unit on its own is not what changing it
    # does.  Joining can only lengthen an answer, so nothing that
    # explained itself before can start failing here.
    k = i - 1
    while k >= 0 and lines[k].startswith('(setq '):
        k -= 1
    why = []
    while k >= 0 and lines[k].lstrip().startswith(';'):
        why.insert(0, lines[k].lstrip(';').strip())
        k -= 1
    parts.extend(why)
    return " ".join(p for p in parts if p).strip()


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
