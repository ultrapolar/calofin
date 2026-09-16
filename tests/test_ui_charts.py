"""The palette's generated chart geometry, against the charts it copies.

``ui/calofin_net/Generated/ChartCatalog.g.vb`` is the vector charts
LAZFORM, LAZSPA, LAZSTEP and LAZSIDE draw, written out by
tools/gen_ui_charts.py.
It exists so the palette can draw the sheet rather than photograph it:
with the outline in the chart's own co-ordinates a dimension box needs
no position of its own, because it belongs at the midpoint of the line
it measures.  ``assets/*/fieldmap.json``'s hand-nudged fractions were
the thing standing between the palette and a real form, and this is what
replaces them.

The generator is the risk now, so the VB is read BACK and held to the
Lisp -- never by asking the generator what it generates, which would
agree with itself whatever it emitted:

1. Every chart is carried, under its own key, with the shape word that
   actually travels as the answer -- NOT always the key: GRSquare
   answers "Grecian" and the five OASIS sheets drop their OA prefix,
   so six of the sixteen would draw the wrong pool if the key were
   sent -- and the title the sheet prints.
2. Every dimension is carried with its letter, its key, both ends of
   its line and its label, and every key it names is one the routine
   reads.
3. Every outline point matches, ARC INCLUDED: an arc is flattened by
   the file's own lzX:flatten before it is written, so the palette
   cannot round an oval a different way from the panel.  This is the
   check that would catch a re-implementation creeping in.
4. Every step sheet exists, one per routine per count up to
   lzt:*max-steps*, because LAZSTEP builds its chart from the count
   rather than keeping a table of them.
5. Every side section exists, one per bottom type, and the six type
   WORDS are the six POOLSIDE's own initget string accepts -- in its
   order.  A type is not a label on this sheet, it is the answer to
   POOLSIDE's first prompt, so a seventh added to one table and not the
   other is a form whose Draw could only fail.  Every key a side sheet
   could send is one POOLSIDE reads, asked of psd:chain and psd:key
   rather than typed here.
6. Nothing is off the chart: every co-ordinate is inside the 0..1000
   square the palette scales, which is test_lazform.py's own rule for
   the same tables.

Run: python3 tests/test_ui_charts.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import check_vb  # noqa: E402
import gen_ui_charts as gen  # noqa: E402
from callib import read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


SRC = read(gen.OUT)


# --------------------------------------------------------------------
# Reading the VB back.  A deliberately separate parser: the generator's
# own emitters would only confirm themselves.
# --------------------------------------------------------------------

def table(opener):
    """The body of one Shared table."""
    i = SRC.index(opener)
    j = SRC.index("\n    }", i)
    return SRC[i:j]


def blocks(body, head):
    """Each `New <head>(...)` entry of a table, as text, split on the
    indentation the generator writes them at."""
    marker = "\n        New %s(" % head
    parts = body.split(marker)
    return parts[1:]


def strokes_in(text):
    return [[float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", m)]
            for m in re.findall(r"New Stroke\(New Double\(\) \{([^}]*)\}\)",
                                text)]


def dims_in(text):
    out = []
    for m in re.finditer(
            r'New ChartDim\("((?:[^"]|"")*)", "((?:[^"]|"")*)", '
            r'(-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+), '
            r'(True|False), "((?:[^"]|"")*)"\)', text):
        out.append((m.group(1), m.group(2),
                    float(m.group(3)), float(m.group(4)),
                    float(m.group(5)), float(m.group(6)),
                    m.group(7) == "True", m.group(8).replace('""', '"')))
    return out


def head_of(block):
    """The three strings a chart block opens with."""
    m = re.match(r'"((?:[^"]|"")*)", "((?:[^"]|"")*)", "((?:[^"]|"")*)"',
                 block)
    return (m.group(1), m.group(2), m.group(3)) if m else None


print("== 1. every sheet, with the word that actually travels ==")

WANT = {}
for prefix, path, var in gen.SOURCES:
    WANT[prefix] = gen.read_charts(path, prefix, var)

pool_body = table("ReadOnly Pool As Chart() = {")
spa_body = table("ReadOnly Spa As Chart() = {")

for prefix, body, name in (("lzf", pool_body, "Pool"),
                           ("lzs", spa_body, "Spa")):
    want = WANT[prefix]
    got = [head_of(b) for b in blocks(body, "Chart")]
    check("%s carries all %d sheets" % (name, len(want)),
          len(got) == len(want), "%d in the file" % len(got))
    check("%s: key, shape word and title, all three" % name,
          got == [(c["key"], c["shape"], c["title"]) for c in want],
          repr(got[:2]))

# The reason the shape word is carried separately at all.  GRSquare is
# a sheet of its own and answers "Grecian"; the five OASIS sheets are
# keyed OA-something and answer without the prefix.  Send the key and
# six of the sixteen sheets draw the wrong pool.
renamed = {c["key"]: c["shape"] for prefix in ("lzf", "lzs")
           for c in WANT[prefix] if c["key"] != c["shape"]}
check("the sheets whose answer is not their key are carried as such",
      renamed == {"GRSquare": "Grecian", "OACenter": "Center",
                  "OATopRight": "TopRight", "OACloud": "Cloud",
                  "OAKidney": "Kidney", "OANXT": "NXTcloud"},
      repr(renamed))


print("== 2. every dimension, with the key the routine reads ==")

for prefix, body, name in (("lzf", pool_body, "Pool"),
                           ("lzs", spa_body, "Spa")):
    want = WANT[prefix]
    for c, block in zip(want, blocks(body, "Chart")):
        got = dims_in(block)
        check("%-11s %2d dimension(s)" % (c["key"], len(c["dims"])),
              got == c["dims"],
              repr([d for d in got if d not in c["dims"]][:2]))

# every key the palette could send is a key the routine takes: read off
# POOL.LSP and SPA.LSP the way test_spa_form.py section 14 does, so
# neither list is typed here
def readable(path, ns):
    src = read(path)
    keys = set(m.group(1).lower() for m in re.finditer(
        r"\(list\s+'([a-z][a-z0-9]*)\s+'(?:REQ|NAX|ZER|SUG)", src))
    keys |= set(m.group(1).lower() for m in re.finditer(
        r"\(%s:(?:askdf|askkwf|askseqb|asknum|askh|askdeep|askc2)\s+'"
        r"([a-z][a-z0-9]*)" % ns, src))
    keys |= set(m.group(1).lower() for m in re.finditer(
        r"\(%s:f(?:has|take)\s+'([a-z][a-z0-9]*)" % ns, src))
    return keys


HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..'))
SPA_KEYS = readable(os.path.join(REPO, 'lisp', 'spa', 'SPA.LSP'), 'spa')
spa_sent = set()
for c in WANT["lzs"]:
    spa_sent |= {d[1].lower() for d in c["dims"]}
    spa_sent |= {e[0].lower() for e in c["extra"]}
check("every spa chart key is one SPA.LSP reads",
      spa_sent <= SPA_KEYS, repr(sorted(spa_sent - SPA_KEYS)))


print("== 3. every outline point, arcs flattened the Lisp's way ==")

for prefix, body, name in (("lzf", pool_body, "Pool"),
                           ("lzs", spa_body, "Spa")):
    want = WANT[prefix]
    for c, block in zip(want, blocks(body, "Chart")):
        got = strokes_in(block)
        check("%-11s %2d stroke(s), %4d point(s)"
              % (c["key"], len(c["strokes"]),
                 sum(len(s) for s in c["strokes"]) // 2),
              got == c["strokes"],
              "%d vs %d strokes" % (len(got), len(c["strokes"])))

# An arc is the case that separates "flattened by the Lisp" from
# "re-drawn by something else": the Round spa sheet is one 0-360 arc and
# nothing else, so its stroke is entirely arc points.
rnd = [c for c in WANT["lzs"] if c["key"].lower() == "round"]
check("a full-circle sheet flattens to a many-point polyline",
      rnd and len(rnd[0]["strokes"]) == 1 and len(rnd[0]["strokes"][0]) > 60,
      repr(len(rnd[0]["strokes"][0]) if rnd else None))


print("== 4. a step sheet for every routine and every count ==")

top, routines, steps = gen.read_steps()
step_body = table("ReadOnly StepSheets As StepChart() = {")
got_steps = re.findall(r'New StepChart\("([A-Z]+)", "([^"]*)", (\d+),',
                       step_body)
check("MaxSteps is lzt:*max-steps*",
      ("Public Const MaxSteps As Integer = %d" % top) in SRC, str(top))
check("%d routines x %d counts = %d sheets"
      % (len(routines), top, len(routines) * top),
      len(got_steps) == len(routines) * top, "%d in the file" % len(got_steps))
check("every (routine, count) pair is there, once",
      [(r, int(n)) for r, _t, n in got_steps]
      == [(c["routine"], c["steps"]) for c in steps],
      repr(got_steps[:3]))

for c, block in zip(steps, blocks(step_body, "StepChart")):
    if c["steps"] not in (1, top):
        continue                    # the ends are where a loop goes wrong
    check("%-11s %d step(s): %2d dims, %2d strokes"
          % (c["routine"], c["steps"], len(c["dims"]), len(c["strokes"])),
          dims_in(block) == c["dims"] and strokes_in(block) == c["strokes"])

# a tread key per step and no more: the loop that builds them is the
# thing most likely to be off by one
for c in steps:
    treads = [d for d in c["dims"] if d[1].startswith("tread")]
    if treads and len(treads) != c["steps"]:
        check("%s %d steps has %d tread boxes"
              % (c["routine"], c["steps"], len(treads)), False)
check("every sheet's tread boxes match its step count", True)


print("== 5. a side section for every bottom type ==")

entry, sidetypes, depths, asks, sides = gen.read_sides()
side_body = table("ReadOnly SideSheets As SideChart() = {")
got_sides = re.findall(r'New SideChart\("([A-Za-z0-9]+)", "([^"]*)",',
                       side_body)

check("a section for each of the %d bottom types" % len(sidetypes),
      [g[0] for g in got_sides] == [c["style"] for c in sides],
      repr(got_sides))
check("SideEntryPoint is the one c:LAZSIDE calls",
      ('Public Const SideEntryPoint As String = "%s"' % entry) in SRC,
      entry)

for c, block in zip(sides, blocks(side_body, "SideChart")):
    check("%-8s %d dim(s), %d stroke(s)"
          % (c["style"], len(c["dims"]), len(c["strokes"])),
          dims_in(block) == c["dims"] and strokes_in(block) == c["strokes"],
          repr([d for d in dims_in(block) if d not in c["dims"]][:2]))

# THE TYPE IS THE ANSWER, not a label.  lzv:*types* names the six
# keywords and POOLSIDE's psd:*btypes* is the initget string it has to
# satisfy -- a seventh in either table alone is a page whose Draw could
# only fail, so they are held together here rather than by anybody
# remembering.  Read out of POOLSIDE itself, never typed.
psd = gen.vm_for(os.path.join(REPO, 'lisp', 'poolside', 'POOLSIDE.lsp'))
btypes = str(psd.globals["psd:*btypes*"]).split()
check("the six type words are POOLSIDE's own, in its order",
      [k for k, _t in sidetypes] == btypes,
      "%r vs %r" % ([k for k, _t in sidetypes], btypes))
check("the VB carries the same six",
      all(('New SideType("%s", "%s")' % (k, t)) in SRC for k, t in sidetypes),
      repr(sidetypes))

# Every key a side sheet could send is one POOLSIDE reads.  The run
# letters come back through psd:key, which is the very function that
# spells a chart letter as a form key, so this cannot drift by spelling.
side_reads = {"b", "style", "mirror"} | set(depths)
for style, _t in sidetypes:
    psd.loads('(setq t:*ch* (mapcar (function (lambda (c) (psd:key (car c))))'
              ' (psd:chain "%s")))' % style)
    side_reads |= {str(k) for k in psd.globals["t:*ch*"]}
side_sent = set()
for c in sides:
    side_sent |= {d[1] for d in c["dims"]}
check("every side chart key is one POOLSIDE reads",
      side_sent <= side_reads, repr(sorted(side_sent - side_reads)))

# ...and the chain a page draws is the chain POOLSIDE measures that
# floor by.  A Sport drawn with a Normal's letters would collect four
# answers the routine never asks for and miss five it does.
for (style, _t), c in zip(sidetypes, sides):
    psd.loads('(setq t:*ch* (mapcar (function (lambda (c) (psd:key (car c))))'
              ' (psd:chain "%s")))' % style)
    want = [str(k) for k in psd.globals["t:*ch*"]]
    got = [d[1] for d in c["dims"] if d[1] != "b" and d[1] not in depths]
    check("%-8s run chain is POOLSIDE's" % style, got == want,
          "%r vs %r" % (got, want))

# The depths are the keys an NA may not travel in, and the reason is
# that POOLSIDE marks them REQ -- read off psd:items' own spelling
# rather than asserted here.
src_psd = read(os.path.join(REPO, 'lisp', 'poolside', 'POOLSIDE.lsp'))
check("every depth key is REQ in POOLSIDE, which is why NA is withheld",
      all(("(list '%s 'REQ" % k) in src_psd for k in depths), repr(depths))
side_keys_body = table("ReadOnly SideDepthKeys As String() = {")
check("SideDepthKeys carries exactly those",
      ("        %s" % ", ".join('"%s"' % k for k in depths))
      in side_keys_body, repr(depths))

# The one question that is not a letter, and the word that sends
# nothing.  POOLSIDE's default for it is No, which is exactly why
# "(ask)" may not be a value: picking it must leave the prompt to apply
# its own default rather than send one.
check("the mirror question is carried with (ask) first",
      [(k, tuple(ch)) for k, _l, ch in asks]
      == [("mirror", ("(ask)", "Yes", "No"))], repr(asks))
check("POOLSIDE reads that key as a keyword with its own default",
      '(psd:fkw \'mirror "Yes No" "No")' in src_psd)


print("== 6. nothing is drawn off the sheet ==")

off = []
for prefix in ("lzf", "lzs"):
    for c in WANT[prefix]:
        for s in c["strokes"]:
            for v in s:
                if not -50 <= v <= 1100:
                    off.append((c["key"], v))
        for d in c["dims"]:
            for v in d[2:6]:
                if not -50 <= v <= 1100:
                    off.append((c["key"], v))
for c in steps:
    for s in c["strokes"]:
        for v in s:
            if not -50 <= v <= 1100:
                off.append((c["routine"], v))
for c in sides:
    for s in c["strokes"]:
        for v in s:
            if not -50 <= v <= 1100:
                off.append((c["style"], v))
    for d in c["dims"]:
        for v in d[2:6]:
            if not -50 <= v <= 1100:
                off.append((c["style"], v))
check("every co-ordinate is on the 0..1000 sheet", not off, repr(off[:4]))


print("== 7. the file is current, and it is well-formed VB ==")

check("gen_ui_charts --check is happy", not gen.check(), repr(gen.check()))

# The generator reads the DEVELOPMENT HOME whatever tier a suite is
# running under.  lispvm remaps a lisp/ path to shared/parts/ when
# CALOFIN_LISP_ROOT is set -- which is how every suite gets re-run
# against the grouped build -- and the grouped twin swaps lzf:flatten
# for cal:imgflatten, so a generator that let itself be remapped died
# outright at the other tier.  make parity is what found it.
_keep = os.environ.pop('CALOFIN_LISP_ROOT', None)
_plain = gen.build()
os.environ['CALOFIN_LISP_ROOT'] = 'shared'
_grouped = gen.build()
if _keep is None:
    os.environ.pop('CALOFIN_LISP_ROOT', None)
else:
    os.environ['CALOFIN_LISP_ROOT'] = _keep
check("it writes the same file at either tier", _plain == _grouped,
      "the tier a test happens to run under is changing the palette")
_, vb_problems = check_vb.check()
check("check_vb passes over the whole palette", not vb_problems,
      repr(vb_problems[:3]))

types = check_vb.declared(check_vb.vb_files())
check("ChartCatalog declares what a form would read",
      {'Pool', 'Spa', 'StepSheets', 'StepRoutines', 'MaxSteps', 'Span',
       'Chart', 'StepChart', 'ChartDim', 'Stroke', 'ListKey', 'Gate',
       'Mark', 'PoolChart', 'SpaChart', 'StepChartFor',
       'SideSheets', 'SideTypes', 'SideAsks', 'SideDepthKeys',
       'SideChart', 'SideType', 'SideAsk', 'SideChartFor', 'IsSideDepth',
       'SideEntryPoint'}
      <= types.get('ChartCatalog', {}).get('members', set()),
      repr(sorted(types.get('ChartCatalog', {}).get('members', ()))))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL UI CHART CHECKS PASSED "
      "(%d pool, %d spa, %d step, %d side sheets)"
      % (len(WANT["lzf"]), len(WANT["lzs"]), len(steps), len(sides)))
