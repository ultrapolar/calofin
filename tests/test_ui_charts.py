"""The palette's generated chart geometry, against the charts it copies.

``ui/calofin_net/Generated/ChartCatalog.g.vb`` is the vector charts
LAZFORM, LAZSPA and LAZSTEP draw, written out by tools/gen_ui_charts.py.
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
5. Nothing is off the chart: every co-ordinate is inside the 0..1000
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


print("== 5. nothing is drawn off the sheet ==")

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
check("every co-ordinate is on the 0..1000 sheet", not off, repr(off[:4]))


print("== 6. the file is current, and it is well-formed VB ==")

check("gen_ui_charts --check is happy", not gen.check(), repr(gen.check()))
_, vb_problems = check_vb.check()
check("check_vb passes over the whole palette", not vb_problems,
      repr(vb_problems[:3]))

types = check_vb.declared(check_vb.vb_files())
check("ChartCatalog declares what a form would read",
      {'Pool', 'Spa', 'StepSheets', 'StepRoutines', 'MaxSteps', 'Span',
       'Chart', 'StepChart', 'ChartDim', 'Stroke', 'ListKey', 'Gate',
       'Mark', 'PoolChart', 'SpaChart', 'StepChartFor'}
      <= types.get('ChartCatalog', {}).get('members', set()),
      repr(sorted(types.get('ChartCatalog', {}).get('members', ()))))


print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL UI CHART CHECKS PASSED (%d pool, %d spa, %d step sheets)"
      % (len(WANT["lzf"]), len(WANT["lzs"]), len(steps)))
