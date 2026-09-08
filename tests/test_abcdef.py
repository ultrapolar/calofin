#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Runtime tests for abcdef.lsp -- locating points from tape distances.

The whole of c:ABCDEF is driven in the AutoLISP VM against surveys whose
TRUE coordinates are known: points are chosen inside a rectangle, their
distances to the four corners computed and rounded to the quarter inch a
field tape actually reads, and the command asked to find them again.  That
turns every claim the tool makes into something checkable -- not "the fit
error is small" but "the point came back where it started".

What is checked, in the order it matters:

  * THE ARITHMETIC.  Clean quarter-inch data comes back within rounding,
    from four tapes, from three, and from two.

  * THE MIRROR ROOT.  Two tapes fix a point twice over, once inside the
    rectangle and once beyond the side between the two corners.  Taking
    the wrong one puts the point outside the pool; the inside root has to
    win, and every plotted point has to land inside the frame.

  * WHEN A TAPE IS DROPPED, AND WHEN IT IS NOT.  Four tapes with one bad
    reading, at a point the rectangle constrains well, must drop exactly
    the bad one.  The same corruption at a point near a diagonal must NOT
    drop anything: there the good and bad triples fit equally well, so the
    data cannot say which tape is wrong and the honest answer is to keep
    them all and say so.  Three tapes that disagree must never be trimmed
    to a flattering pair.

  * THE CONFIDENCE COLUMN.  It has to separate cases a human would
    separate: clean four-tape work above a repaired row, a repaired row
    above one nobody could repair, and two tapes never at the top however
    neatly they crossed.

  * THE HANDOFF.  Points are ab_pt blocks on POINTS carrying the sheet's
    label, which is what ABHD reads, and answering Yes pre-selects exactly
    the points this run made and starts ABHD on them.

Usage:  python3 tests/test_abcdef.py
        CALOFIN_LISP_ROOT=shared python3 tests/test_abcdef.py
"""

import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Dot, LispError, Sym  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
#: always the lisp/ path -- VM.load remaps it to shared/parts/ when
#: CALOFIN_LISP_ROOT says so, which is how one test covers both tiers.
LSP = os.path.join(REPO, 'lisp', 'abcdef', 'abcdef.lsp')

failures = []


def check(label, cond):
    print(('  ok   ' if cond else '  FAIL ') + label)
    if not cond:
        failures.append(label)


# ---------------------------------------------------------------- the VM --

#: AutoCAD entry points the VM has no opinion about.  open/write-line/close
#: are captured rather than stubbed away so the report FILE can be asserted
#: on too -- it is half of what the command promises.
STUBS = r'''
(defun vl-string-search (pat s / n m i found)
  (setq n (strlen pat) m (strlen s) i 1 found nil)
  (while (and (null found) (<= i (1+ (- m n))))
    (if (= (substr s i n) pat) (setq found (1- i)))
    (setq i (1+ i)))
  found)
(defun getfiled (title dflt ext flags) "C:\\jobs\\survey.csv")
(defun alert (s) (setq *alert* s))
(defun sssetfirst (a b) (setq *preselect* b))
(setq *csv* '() *no-write* nil)
(defun open (path mode)
  (if (= mode "r")
    (progn (setq *csv-left* *csv*) 'FPR)
    (if *no-write* nil (progn (setq *rpt-path* path *rpt* '()) 'FP))))
(defun read-line (fp / l)
  (if *csv-left*
    (progn (setq l (car *csv-left*) *csv-left* (cdr *csv-left*)) l)))
(defun write-line (s fp) (setq *rpt* (cons s *rpt*)) s)
(defun close (fp) nil)
'''

W = 36 * 12 + 5.25          # 36'-5 1/4"
H = 22 * 12 + 0.25          # 22'-0 1/4"
WSTR, HSTR = "36'-5 1/4", "22'-0 1/4"
CORNERS = [(0.0, 0.0), (W, 0.0), (0.0, -H), (W, -H)]     # A B C D


def quarter(v):
    """What a tape reads: the nearest quarter inch."""
    return round(v * 4.0) / 4.0


def tapes(x, y):
    return [quarter(math.hypot(x - cx, y - cy)) for cx, cy in CORNERS]


def lstr(v):
    """A python string as a LISP string literal."""
    return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'


def rowsrc(rows):
    return " ".join(
        '(list %s %s)' % (lstr(nm),
                          " ".join('nil' if d is None else repr(d) for d in ds))
        for nm, ds in rows)


def fresh(pre=''):
    vm = VM()
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(STUBS)
    if pre:
        vm.loads(pre)
    vm.load(LSP)
    return vm


def run(rows, method="Auto", answer="No", with_abhd=False,
        script=None, pre='', post='', csv=None):
    """Drive c:ABCDEF over ROWS -- (name, [dA,dB,dC,dD]) with None for a
    blank cell -- and hand back the VM for inspection.

    SCRIPT replaces the default answer queue outright (for the Back and
    cancel paths); PRE runs before the file is loaded and POST after it
    (for a drawing to plot into, or a tunable to change); CSV leaves the
    command's OWN sheet reader in place and feeds it those lines."""
    vm = fresh(pre)
    if with_abhd:
        vm.loads('(defun c:ABHD () nil)')
    if csv is None:
        # the sheet reader itself is Excel COM and file I/O, neither of
        # which is what most of these tests are about; the rows go in
        # directly
        vm.loads("(defun abcdef:read-file (file maxd) (list %s))"
                 % rowsrc(rows))
    else:
        vm.loads("(setq *csv* '(%s))" % " ".join(lstr(l) for l in csv))
    if post:
        vm.loads(post)
    vm.run('c:ABCDEF', script if script is not None
           else [WSTR, HSTR, method, [0.0, 0.0, 0.0], answer])
    return vm


def said(vm):
    return "".join(vm.printed)


def grp(d, code):
    for pair in d:
        if isinstance(pair, Dot) and pair.a == code:
            return pair.b
        if isinstance(pair, list) and pair and pair[0] == code:
            return pair[1] if len(pair) == 2 else pair[1:]
    return None


def ents(vm, etype):
    return [vm.entdata[e] for e in vm.entities
            if e not in vm.deleted and grp(vm.entdata[e], 0) == etype]


def layer_flags(vm, name):
    return grp(vm.recdata[vm.tablerecs['LAYER'][name.upper()]], 70) or 0


def layer_color(vm, name):
    return grp(vm.recdata[vm.tablerecs['LAYER'][name.upper()]], 62)


def layer_src(name, color, flags=0):
    return ('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
            ' \'(100 . "AcDbLayerTableRecord") \'(2 . "%s") \'(70 . %d)'
            ' \'(62 . %d) \'(6 . "Continuous")))' % (name, flags, color))


def report(vm):
    return list(reversed(vm.globals.get(Sym('*rpt*')) or []))


def row(vm, name):
    """The report line for one point, split into fields."""
    for ln in report(vm):
        if ln.strip().startswith(name + ' '):
            return ln
    return ''


def placed(vm):
    """{label: (x, y)} read back off the ab_pt blocks actually drawn."""
    out, pending = {}, None
    for e in vm.entities:
        data = vm.entdata[e]
        kind = next((p.b for p in data if getattr(p, 'a', None) == 0), None)
        xy = next((p[1:3] for p in data
                   if isinstance(p, list) and p[0] == 10), None)
        if kind == 'INSERT':
            pending = xy
        elif kind == 'ATTRIB' and pending:
            label = next((p.b for p in data if getattr(p, 'a', None) == 1), '')
            out[label] = tuple(pending)
            pending = None
    return out


def field(line, name):
    """One named column out of a report line."""
    m = re.search(r'\s%s\s+([-\d.]+)' % name, line)
    return float(m.group(1)) if m else None


def used_of(line):
    """The USED column - the corner letters that placed the point."""
    m = re.search(r'\d of \d\s+([A-D]+)\s', line)
    return m.group(1) if m else ''


def conf_of(line):
    m = re.search(r'(\d+)% (HIGH|GOOD|FAIR|WEAK|POOR)', line)
    return (int(m.group(1)), m.group(2)) if m else (None, None)


# ------------------------------------------------------- the arithmetic --

def test_clean_four_tapes():
    print("\nfour clean tapes: every point comes back where it started")
    truth = [("N1", 120.0, -60.0), ("P", 300.0, -40.0), ("Q", 200.0, -150.0),
             ("R", 60.0, -200.0), ("S", 400.0, -220.0), ("T", 30.0, -30.0)]
    vm = run([(nm, tapes(x, y)) for nm, x, y in truth])
    got = placed(vm)
    check("all six points drawn", len(got) == 6)
    worst = 0.0
    for nm, x, y in truth:
        worst = max(worst, math.hypot(got[nm][0] - x, got[nm][1] - y))
    # a quarter-inch tape cannot do better than an eighth of an inch of
    # rounding per reading; a fifth of an inch overall is the honest bar
    check("worst point within 0.20\" of truth (%.3f\")" % worst, worst < 0.20)
    for nm, _, _ in truth:
        ln = row(vm, nm)
        check("%s used all four tapes" % nm, used_of(ln) == 'ABCD')
        pct, word = conf_of(ln)
        check("%s graded HIGH or GOOD (%s%% %s)" % (nm, pct, word),
              word in ('HIGH', 'GOOD'))


def test_three_and_two_tapes():
    print("\nthree tapes and two: fewer readings, same answer")
    x, y = 300.0, -40.0
    d = tapes(x, y)
    for label, given in (("ABC", [d[0], d[1], d[2], None]),
                         ("ABD", [d[0], d[1], None, d[3]]),
                         ("AD",  [d[0], None, None, d[3]]),
                         ("AB",  [d[0], d[1], None, None]),
                         ("CD",  [None, None, d[2], d[3]])):
        vm = run([("P", given)])
        px, py = placed(vm)["P"]
        off = math.hypot(px - x, py - y)
        check("%s places P within 0.5\" (%.3f\")" % (label, off), off < 0.5)
        check("%s reports the tapes it used" % label,
              used_of(row(vm, "P")) == label)


def test_two_tapes_take_the_inside_root():
    print("\ntwo tapes: the root inside the rectangle wins")
    # measured from the two TOP corners, the mirror root sits above the
    # top edge - outside the pool, and the wrong answer by twice the depth
    for nm, x, y in (("P", 200.0, -40.0), ("Q", 90.0, -220.0),
                     ("R", 380.0, -130.0)):
        d = tapes(x, y)
        vm = run([(nm, [d[0], d[1], None, None])])
        px, py = placed(vm)[nm]
        check("%s: inside root taken, not the mirror (y=%.2f)" % (nm, py),
              -H - 0.01 <= py <= 0.01)
        check("%s: within 0.5\" of truth" % nm,
              math.hypot(px - x, py - y) < 0.5)


def test_every_point_lands_inside_the_frame():
    print("\nevery plotted point is inside the rectangle")
    rows, truth = [], [("A1", 12.0, -12.0), ("A2", W - 8.0, -6.0),
                       ("A3", 6.0, -H + 9.0), ("A4", W - 3.0, -H + 2.0),
                       ("A5", W / 2, -H / 2)]
    for nm, x, y in truth:
        rows.append((nm, tapes(x, y)))
    # ...and one row that describes a point genuinely OUTSIDE the frame,
    # 8" left of corner A and 10" above it.  A pool point measured from
    # four corners of its own rectangle cannot be there; it has to come
    # back onto the frame, and the report has to say how far it moved.
    rows.append(("OUT", tapes(-8.0, 10.0)))
    vm = run(rows)
    for nm, (px, py) in placed(vm).items():
        check("%s inside the frame (%.2f, %.2f)" % (nm, px, py),
              -0.001 <= px <= W + 0.001 and -H - 0.001 <= py <= 0.001)
    out = row(vm, "OUT")
    check("the outside row is reported as snapped", 'snapped' in out)
    check("...by about the distance it really was out (%s)" % out.strip()[-40:],
          re.search(r'snapped (\d+\.\d+)"', out)
          and 11.0 < float(re.search(r'snapped (\d+\.\d+)"', out).group(1)) < 14.0)


# --------------------------------------------- dropping a tape, or not --

def test_drops_the_bad_tape_when_the_geometry_says_which():
    print("\nfour tapes, one bad, at a well-constrained point")
    x, y = 300.0, -40.0
    for i, letter in enumerate("ABCD"):
        d = tapes(x, y)
        d[i] += 6.0                       # one tape reads six inches long
        vm = run([("P", d)])
        ln = row(vm, "P")
        want = "ABCD".replace(letter, "")
        check("a bad %s tape is the one dropped (used %s)"
              % (letter, used_of(ln)), used_of(ln) == want)
        px, py = placed(vm)["P"]
        off = math.hypot(px - x, py - y)
        check("...and P still lands within 0.3\" of truth (%.3f\")" % off,
              off < 0.3)
        check("...and the row is flagged for a human", '**CHECK' in ln)


def test_keeps_every_tape_when_the_geometry_cannot_say():
    print("\nfour tapes, one bad, at a point near a diagonal")
    # (200,-120) sits almost exactly on the A-D diagonal, where A and D
    # cross at about 2 degrees.  A wrong third tape slides the answer
    # along that diagonal while the fit stays tiny, so dropping the
    # lowest-error tape would discard a GOOD one.  Both triples fit
    # equally well; the honest answer is to keep all four and say so.
    d = tapes(200.0, -120.0)
    d[2] += 6.0
    vm = run([("P", d)])
    ln = row(vm, "P")
    check("no tape is dropped (used %s)" % used_of(ln), used_of(ln) == 'ABCD')
    check("the report says why", 'none provably wrong' in ln)
    check("the row is flagged for a human", '**CHECK' in ln)
    pct, word = conf_of(ln)
    check("confidence is POOR (%s%% %s)" % (pct, word), word == 'POOR')


def test_three_disagreeing_tapes_are_never_trimmed():
    print("\nthree tapes that disagree are kept, not trimmed to a pair")
    d = tapes(300.0, -40.0)
    vm = run([("P", [d[0], d[1], d[2] + 6.0, None])])
    ln = row(vm, "P")
    check("all three kept (used %s)" % used_of(ln), used_of(ln) == 'ABC')
    check("the row is flagged", '**CHECK' in ln)
    pct, word = conf_of(ln)
    check("confidence is low (%s%%)" % pct, pct is not None and pct < 60)


def test_rows_with_too_little_are_skipped_not_guessed():
    print("\na row with fewer than two tapes is skipped, not guessed at")
    d = tapes(120.0, -60.0)
    vm = run([("GOOD", d), ("ONE", [d[0], None, None, None]),
              ("NONE", [None, None, None, None])])
    got = placed(vm)
    check("the complete row is plotted", "GOOD" in got)
    check("the one-tape row is not", "ONE" not in got)
    check("the empty row is not", "NONE" not in got)
    check("and the total says so",
          any('1 point(s) plotted, 2 skipped' in l for l in report(vm)))


# ------------------------------------------------------- the confidence --

def test_confidence_separates_the_cases():
    print("\nconfidence separates cases a human would separate")
    x, y = 300.0, -40.0
    clean = run([("P", tapes(x, y))])
    repaired_d = tapes(x, y)
    repaired_d[2] += 6.0
    repaired = run([("P", repaired_d)])
    hopeless_d = tapes(200.0, -120.0)
    hopeless_d[2] += 6.0
    hopeless = run([("P", hopeless_d)])
    two = run([("P", [tapes(x, y)[0], tapes(x, y)[1], None, None])])

    c_clean = conf_of(row(clean, "P"))[0]
    c_rep = conf_of(row(repaired, "P"))[0]
    c_hop = conf_of(row(hopeless, "P"))[0]
    c_two = conf_of(row(two, "P"))[0]
    check("clean four tapes (%d%%) beat a repaired row (%d%%)"
          % (c_clean, c_rep), c_clean > c_rep)
    check("a repaired row (%d%%) beats one nobody could repair (%d%%)"
          % (c_rep, c_hop), c_rep > c_hop)
    check("two tapes (%d%%) never reach the top" % c_two, c_two < 90)
    check("but two clean tapes still beat a hopeless four (%d vs %d)"
          % (c_two, c_hop), c_two > c_hop)


def test_fit_reports_every_tape_even_the_dropped_one():
    print("\nFIT keeps the dropped tape's objection visible")
    d = tapes(300.0, -40.0)
    d[2] += 6.0
    ln = row(run([("P", d)]), "P")
    fit = field(ln, 'ABD')          # the FIT column follows USED
    check("FIT still carries the 6\" error (%.2f\")" % (fit or -1),
          fit is not None and fit > 2.0)
    check("...while the point is graded on the tapes that placed it",
          conf_of(ln)[0] > 50)


# ------------------------------------------------- methods, frame, exit --

def test_every_method_places_points_inside_the_frame():
    print("\nall four methods place points, inside the frame")
    truth = [("P", 300.0, -40.0), ("Q", 200.0, -150.0), ("R", 60.0, -200.0)]
    rows = [(nm, tapes(x, y)) for nm, x, y in truth]
    for method in ("Auto", "Furthest", "Mean", "Least"):
        vm = run(rows, method=method)
        got = placed(vm)
        check("%s: all three plotted" % method, len(got) == 3)
        for nm, (px, py) in got.items():
            check("%s: %s inside the frame" % (method, nm),
                  -0.001 <= px <= W + 0.001 and -H - 0.001 <= py <= 0.001)
        check("%s: named in the report" % method,
              any(('method : ' + method) in l for l in report(vm)))


def test_frame_is_a_true_rectangle():
    print("\nthe frame is measured, not asserted")
    vm = run([("P", tapes(120.0, -60.0))])
    line = [l for l in report(vm) if 'corner angles' in l]
    check("the report measures the corner angles", len(line) == 1)
    if line:
        angles = re.findall(r'(\d+\.\d+) /|(\d+\.\d+) deg', line[0])
        flat = [float(a or b) for a, b in angles]
        check("all four corners measure 90 degrees (%s)" % flat,
              len(flat) == 4 and all(abs(a - 90.0) < 0.01 for a in flat))


def test_report_file_is_written_beside_the_sheet():
    print("\nthe report is written to disk, not only to the command line")
    vm = run([("P", tapes(120.0, -60.0))])
    path = vm.globals.get(Sym('*rpt-path*'))
    check("written next to the sheet (%s)" % path,
          path == r'C:\jobs\survey_ABCDEF_report.txt')
    text = "\n".join(report(vm))
    for want in ('TAPES', 'USED', 'CONF', 'method : Auto', 'P '):
        check("the file carries %r" % want, want in text)


# ------------------------------------------------------------ the handoff --

def test_points_are_the_survey_points_abhd_reads():
    print("\nthe points are ab_pt blocks on POINTS, numbered from the sheet")
    vm = run([("17", tapes(120.0, -60.0)), ("18", tapes(300.0, -40.0))])
    blocks, attribs = [], []
    for e in vm.entities:
        data = vm.entdata[e]
        kind = next((p.b for p in data if getattr(p, 'a', None) == 0), None)
        lay = next((p.b for p in data if getattr(p, 'a', None) == 8), None)
        if kind == 'INSERT':
            blocks.append((next(p.b for p in data
                                if getattr(p, 'a', None) == 2), lay))
        if kind == 'ATTRIB':
            attribs.append((next(p.b for p in data
                                 if getattr(p, 'a', None) == 2),
                            next(p.b for p in data
                                 if getattr(p, 'a', None) == 1)))
    check("both points are ab_pt blocks on POINTS",
          blocks == [('ab_pt', 'POINTS'), ('ab_pt', 'POINTS')])
    check("each carries its sheet label in the number attribute",
          attribs == [('number', '17'), ('number', '18')])
    check("nothing else was put on the POINTS layer",
          all(vm.layer_of(e) != 'POINTS'
              or next((p.b for p in vm.entdata[e]
                       if getattr(p, 'a', None) == 0), None)
              in ('INSERT', 'ATTRIB', 'SEQEND')
              for e in vm.entities))


def test_abhd_handoff():
    print("\nanswering Yes hands the survey to ABHD")
    rows = [("1", tapes(120.0, -60.0)), ("2", tapes(300.0, -40.0)),
            ("3", tapes(200.0, -150.0))]
    vm = run(rows, answer="Yes", with_abhd=True)
    check("ABHD is started", ['_.ABHD'] in vm.commands)
    ss = vm.globals.get(Sym('*preselect*'))
    check("with exactly this run's three points pre-selected",
          ss is not None and len(ss) - 1 == 3)

    vm = run(rows, answer="No", with_abhd=True)
    check("answering No starts nothing", ['_.ABHD'] not in vm.commands)

    vm = run(rows, answer="Yes", with_abhd=False)
    check("ABHD not loaded: nothing is started",
          ['_.ABHD'] not in vm.commands)


def test_the_view_reset_survives_its_own_catch():
    print("\nthe closing view reset runs instead of raising")
    vm = run([("P", tapes(120.0, -60.0))])
    check("plan and zoom both ran",
          ['_.plan', '_World'] in vm.commands
          and ['_.zoom', '_Extents'] in vm.commands)


# ============================================================ contingencies ==
#
# Everything above drives the happy path with the sheet handed in as a
# list.  What follows is the rest of a real run: the file itself, the
# questions, the drawing it plots into, and every way the run can be cut
# short.  These are the paths a drafter hits on a bad afternoon, and the
# ones that were read by eye rather than executed.

#: the dirty forms a scanned or re-typed field sheet comes back in
PARSER_CASES = [
    ('12\'-3 1/2"', 147.5),
    ("34'-4 1 /4", 412.25),        # fraction split by a stray space
    ('20\'-7 1/ 4"', 247.25),      # ...on the other side of the slash
    ('20\'-7 1 / 4"', 247.25),     # ...both sides
    ('20\'-7 114"', 247.25),       # "/" scanned as a "1"
    ('28-7"', 343.0),              # missing foot mark
    ('101-10"', 130.0),            # foot mark scanned as a "1"
    ("26' -8\"", 320.0),
    ('1 1\'-IO 1/2"', 142.5),      # split feet, letters for digits
    ("9'", 108.0),
    ('3 1/2"', 3.5),
]


def parse(vm, raw, maxd=514.0):
    return vm.eval(lispvm.parse_all(
        '(abcdef:ftin->in %s %s)' % (lstr(raw), maxd))[0])


def test_the_parser_reads_a_scanned_sheet():
    print("\nthe feet-inch parser, on the sheets it actually gets")
    vm = fresh()
    for raw, want in PARSER_CASES:
        got = parse(vm, raw)
        check("%-18s -> %s" % (lstr(raw), want),
              isinstance(got, float) and abs(got - want) < 1e-9)
    for raw in ('600\'-0"', '-4\'-0"', '', 'not a number', '0'):
        check("%-18s is refused rather than guessed at" % lstr(raw),
              parse(vm, raw) is lispvm.NIL)
    check("a plausible reading keeps its digits", parse(vm, '41-10"') == 502.0)


#: the shipped sample sheet, as the command's own reader sees it
SHEET = [
    "POINT NAME,DIST FROM A,DIST FROM B,DIST FROM C,DIST FROM D",
    'N1,34\'-4 1 /4,"38\'-5""","16\'-11""","24\'-1 1/2"""',
    'P,12\'-7 1/2,"27\'-6 1 /2""","17\'-5 1 /2""","30\'-0 3/4"""',
    ',,,,',
]


def test_the_command_reads_its_own_csv():
    print("\nthe CSV reader: quoted cells, blanks, and the repair log")
    vm = run(None, csv=SHEET)
    got = placed(vm)
    check("both named rows were read and placed", set(got) == {"N1", "P"},
          )
    check("the nameless row is not a point", len(got) == 2)
    check("the split fractions were repaired and logged",
          "dirty values cleaned before import" in said(vm))
    check("...and the log writes back what it made of them",
          "34'-4 1/4\"" in said(vm))
    check("every point landed inside the frame",
          all(-0.001 <= x <= W + 0.001 and -H - 0.001 <= y <= 0.001
              for x, y in got.values()))


def test_columns_are_found_in_any_order():
    print("\nthe columns are found by their headers, in any order")
    a = run(None, csv=SHEET[:2])
    b = run(None, csv=[
        "DIST FROM D,DIST FROM C,POINT NAME,DIST FROM B,DIST FROM A",
        '"24\'-1 1/2""","16\'-11""",N1,"38\'-5""",34\'-4 1 /4'])
    pa, pb = placed(a)["N1"], placed(b)["N1"]
    check("the same row placed identically either way",
          math.hypot(pa[0] - pb[0], pa[1] - pb[1]) < 1e-6)


def test_a_sheet_with_nothing_usable_draws_nothing():
    print("\na sheet with no rows in it plots nothing and says so")
    vm = run(None, csv=[SHEET[0]], script=[WSTR, HSTR, "Auto", [0.0, 0.0, 0.0]])
    check("nothing at all was drawn", not vm.entities)
    check("and it says so", "No usable rows found" in said(vm))


# ------------------------------------------------------- asking and backing --

def test_back_walks_the_whole_question_chain():
    print("\nBack at any question re-opens the one before it")
    vm = run([("P", tapes(120.0, -60.0))],
             script=[WSTR, "B", WSTR, HSTR, "Back", HSTR, "Auto",
                     "Back", "Least", [0.0, 0.0, 0.0], "No"])
    asked = [q for q, _ in vm.prompts]
    check("the width was asked twice", sum('A-B' in q for q in asked) == 2)
    check("the height was asked three times",
          sum('A-C' in q for q in asked) == 3)
    check("the method was asked three times",
          sum('placed?' in q for q in asked) == 3)
    check("the last answer is the one that counted",
          any('method : Least' in l for l in report(vm)))
    check("and the run still plotted", len(placed(vm)) == 1)


def test_back_at_the_first_dimension_returns_to_the_file_dialog():
    print("\nBack at the first dimension re-opens the file dialog")
    vm = run([("P", tapes(120.0, -60.0))],
             script=["B", WSTR, HSTR, "Auto", [0.0, 0.0, 0.0], "No"])
    check("the dialog was opened twice",
          said(vm).count("--- Rectangle A(top-left)") == 2)
    check("and the run completed", len(placed(vm)) == 1)


def test_back_at_the_base_point_reopens_the_method():
    print("\nBack at the insertion point re-opens the method question")
    vm = run([("P", tapes(120.0, -60.0))],
             script=[WSTR, HSTR, "Auto", "Back", "Mean", [0.0, 0.0, 0.0],
                     "No"])
    check("the method was re-asked and the new answer used",
          any('method : Mean' in l for l in report(vm)))


def test_the_method_question_is_asked_in_the_house_format():
    print("\nthe method question follows the house prompt format")
    vm = run([("P", tapes(120.0, -60.0))],
             script=[WSTR, HSTR, None, [0.0, 0.0, 0.0], "No"])
    q = [q for q, _ in vm.prompts if 'placed?' in q][0]
    check("it is a question, with the bracket a click can send",
          '[Auto/Furthest/Mean/Least/Back]' in q, )
    check("...and its default is shown", '<Auto>' in q)
    check("Enter takes that default",
          any('method : Auto' in l for l in report(vm)))
    check("it ends colon-space", q.endswith(': '))


def test_a_bad_dimension_is_re_asked():
    print("\na dimension that is not a positive length is re-asked")
    vm = run([("P", tapes(120.0, -60.0))],
             script=["", "-5'", "0", WSTR, HSTR, "Auto", [0.0, 0.0, 0.0],
                     "No"])
    check("it kept asking until it got one", len(placed(vm)) == 1)
    check("and said why each time",
          said(vm).count("enter a positive dimension") == 3)


def test_enter_at_the_base_point_takes_the_origin():
    print("\nEnter at the insertion point takes 0,0")
    vm = run([("P", tapes(120.0, -60.0))],
             script=[WSTR, HSTR, "Auto", None, "No"])
    verts = [tuple(v[1:3]) for v in ents(vm, 'LWPOLYLINE')[0]
             if isinstance(v, list) and v[0] == 10]
    check("corner A is at the origin", verts[0] == (0.0, 0.0))


def test_cancel_in_the_dialog_draws_nothing():
    print("\nCancel in the file dialog ends the run, quietly")
    vm = fresh('(defun getfiled (t d e f) nil)')
    vm.loads("(defun abcdef:read-file (file maxd) nil)")
    vm.run('c:ABCDEF', [])
    check("nothing drawn", not vm.entities)
    check("no question was asked", not vm.prompts)
    check("and it says it was cancelled", "Cancelled" in said(vm))


# ---------------------------------------------- the sheet's own labelling --

def test_a_clockwise_sheet_is_noticed_and_swapped():
    print("\na sheet labelled C bottom-RIGHT is noticed, swapped and named")
    truth = [("P1", 120.0, -60.0), ("P2", 300.0, -40.0), ("P3", 200.0, -150.0),
             ("P4", 60.0, -200.0), ("P5", 400.0, -220.0)]
    # the same survey written the other way round: the C and D columns
    # exchanged, which is exactly what a clockwise-labelled sheet holds
    rows = []
    for nm, x, y in truth:
        d = tapes(x, y)
        rows.append((nm, [d[0], d[1], d[3], d[2]]))
    vm = run(rows)
    check("the swap is detected and said out loud", "C/D NOTE" in said(vm))
    check("...and recorded in the report",
          any('C/D read swapped' in l for l in report(vm)))
    worst = max(math.hypot(placed(vm)[nm][0] - x, placed(vm)[nm][1] - y)
                for nm, x, y in truth)
    check("every point still lands where it really is (%.3f\")" % worst,
          worst < 0.25)


def test_a_correctly_labelled_sheet_is_left_alone():
    print("\n...and a correctly labelled one is not touched")
    truth = [("P1", 120.0, -60.0), ("P2", 300.0, -40.0), ("P3", 200.0, -150.0),
             ("P4", 60.0, -200.0), ("P5", 400.0, -220.0)]
    vm = run([(nm, tapes(x, y)) for nm, x, y in truth])
    check("no swap note", "C/D NOTE" not in said(vm))
    check("no swap in the report",
          not any('C/D read swapped' in l for l in report(vm)))


def test_a_sheet_that_fits_the_rectangle_badly_raises_an_alert():
    print("\na sheet that fits the rectangle badly warns, and still plots")
    # every row a foot out on every tape, in directions no single point
    # can satisfy.  No swap fixes that, so either the dimensions or the
    # sheet is wrong and the drafter has to be told before they draft
    # over it.  (Six inches is NOT enough: the least-squares fit absorbs
    # it to about 0.9" a row, under the threshold, and the per-point
    # confidence column carries it instead -- which is the design.)
    rows = []
    for nm, x, y in (("P1", 120.0, -60.0), ("P2", 300.0, -40.0),
                     ("P3", 200.0, -150.0), ("P4", 60.0, -200.0)):
        d = tapes(x, y)
        rows.append((nm, [d[0] + 12.0, d[1] - 12.0, d[2] + 12.0,
                          d[3] - 12.0]))
    vm = run(rows)
    check("the command line warns", "fit the rectangle poorly" in said(vm))
    check("and so does an alert the drafter cannot miss",
          'POORLY' in (vm.globals.get(Sym('*alert*')) or ''))
    check("the points are still plotted", len(placed(vm)) == 4)
    check("...and every one of them graded",
          all('%' in row(vm, nm) for nm, _, _ in
              (("P1", 0, 0), ("P2", 0, 0), ("P3", 0, 0), ("P4", 0, 0))))


def test_a_mirror_pair_is_named_rather_than_guessed_at():
    print("\ntwo tapes from OPPOSITE corners answer twice, and say so")
    # A and D are opposite corners under the Z order.  The mirror of the
    # answer across the A-D line fits the SAME two tapes to the same
    # hundredth and lands inside the frame too, so the sheet does not say
    # which of the two the point is -- and the seed that breaks the tie
    # sits exactly between them.
    x, y = 300.0, -40.0
    d = tapes(x, y)
    vm = run([("P", [d[0], None, None, d[3]])])
    ln = row(vm, "P")
    check("the point is still plotted", len(placed(vm)) == 1)
    check("but the row is named a mirror pair", 'mirror pair' in ln, )
    check("...and told what would settle it", 'third tape' in ln)
    check("it is counted among the points wanting checking",
          any('1 point(s) want checking' in l for l in report(vm)))
    pct, _ = conf_of(ln)
    check("and it cannot read as a confident point (%s%%)" % pct, pct < 50)
    # an ADJACENT pair is fixed by its frame and must not be flagged
    quiet = run([("Q", [d[0], d[1], None, None])])
    check("an adjacent pair is not flagged",
          'mirror pair' not in row(quiet, "Q"))


# ------------------------------------------------- the drawing it plots into --

def test_the_corner_self_check_refuses_to_plot_a_bad_frame():
    print("\na frame that is not the entered rectangle stops the run")
    vm = fresh()
    ok = vm.eval(lispvm.parse_all(
        '(abcdef:frame-check 0.0 0.0 %r 0.0 0.0 %r %r %r %r %r)'
        % (W, -H, W, -H, W, H))[0])
    check("the documented corner layout is accepted", ok is lispvm.NIL)
    bad = vm.eval(lispvm.parse_all(
        '(abcdef:frame-check 0.0 0.0 %r 0.0 %r %r %r %r %r %r)'
        % (W, 2 * W, -H, W, -H, W, H))[0])
    check("the parallelogram that failed in the field is rejected (%s)" % bad,
          isinstance(bad, str) and bad)
    # end to end: when the check fails, NOTHING is drawn
    vm = run([("P", tapes(120.0, -60.0))],
             post='(defun abcdef:frame-check (a b c d e f g h w y)'
                  ' "A-B measures 1.00\\" but should be 2.00\\"")',
             script=[WSTR, HSTR, "Auto", [0.0, 0.0, 0.0]])
    check("nothing at all is drawn", not vm.entities)
    check("the abort is on the command line", "ABORT" in said(vm))
    check("...and in an alert",
          'self-check FAILED' in (vm.globals.get(Sym('*alert*')) or ''))


def test_a_frozen_or_locked_output_layer_is_repaired():
    print("\nan output layer that is off, frozen or locked is restored")
    vm = run([("P", tapes(120.0, -60.0))],
             pre=layer_src('POINTS', -2, 1 | 4))
    check("POINTS is thawed and unlocked",
          not layer_flags(vm, 'POINTS') & (1 | 4))
    check("and switched back on", layer_color(vm, 'POINTS') == 2)
    check("and the drafter is told it had to be",
          'POINTS was off, frozen or locked' in said(vm))
    check("the survey really did land on it", len(placed(vm)) == 1)


def test_the_point_block_is_made_once_and_reused():
    print("\nab_pt is created when the drawing has never seen one, then reused")
    vm = run([("P", tapes(120.0, -60.0))])
    check("the block was created", 'ab_pt' in vm.tables.get('BLOCK', set()))
    check("and the drafter told", 'was not in this drawing' in said(vm))
    # a drawing that already has one is left alone
    have = ('(entmake (list \'(0 . "BLOCK") \'(2 . "ab_pt") \'(70 . 2)'
            ' \'(10 0.0 0.0 0.0) \'(3 . "ab_pt") \'(1 . "")))'
            '(entmake \'((0 . "ENDBLK")))')
    vm = run([("P", tapes(120.0, -60.0))], pre=have)
    check("an existing block is reused silently",
          'was not in this drawing' not in said(vm))


def test_a_second_import_hands_abhd_only_its_own_points():
    print("\na second import in one drawing does not sweep up the first")
    # a survey already in the drawing, as the previous import left it
    prior = ('(entmake (list \'(0 . "INSERT") \'(8 . "POINTS") \'(66 . 1)'
             ' \'(2 . "ab_pt") \'(10 5.0 -5.0 0.0)))'
             '(entmake (list \'(0 . "SEQEND") \'(8 . "POINTS")))')
    rows = [("1", tapes(120.0, -60.0)), ("2", tapes(300.0, -40.0))]
    vm = run(rows, answer="Yes", with_abhd=True, pre=prior)
    ss = vm.globals.get(Sym('*preselect*'))
    check("ABHD is started", ['_.ABHD'] in vm.commands)
    check("with this run's two points only, not the earlier three",
          ss is not None and len(ss) - 1 == 2, )


def test_the_report_file_failing_does_not_lose_the_plot():
    print("\na report that cannot be written costs the note, not the plot")
    vm = run([("P", tapes(120.0, -60.0))], post='(setq *no-write* T)')
    check("the points are plotted anyway", len(placed(vm)) == 1)
    check("and the failure is reported, not swallowed",
          'could not be written' in said(vm))


# ------------------------------------------------------- the run's manners --

def test_one_undo_group_opened_and_closed():
    print("\nthe whole plot is one undo group")
    vm = run([("P", tapes(120.0, -60.0))])
    marks = [c for c in vm.commands if c and c[0] == '_.UNDO']
    check("opened once and closed once",
          marks == [['_.UNDO', '_Begin'], ['_.UNDO', '_End']])


def test_no_undo_group_when_undo_is_off():
    print("\nwith UNDO off, no group is opened -- _Begin would error")
    vm = fresh()
    vm.sysvars['UNDOCTL'] = 4                 # bit 1 clear: undo disabled
    vm.loads("(defun abcdef:read-file (file maxd) (list %s))"
             % rowsrc([("P", tapes(120.0, -60.0))]))
    vm.run('c:ABCDEF', [WSTR, HSTR, "Auto", [0.0, 0.0, 0.0], "No"])
    check("no undo command was issued",
          not [c for c in vm.commands if c and c[0] == '_.UNDO'])
    check("but the point was still plotted", len(placed(vm)) == 1)


def test_esc_partway_through_goes_through_the_handler():
    print("\nEsc partway through is handled, and closes the group")
    def esc(vm):
        raise LispError('Function cancelled', vm)
    for where, script in (("the height", [WSTR, esc]),
                          ("the method", [WSTR, HSTR, esc]),
                          ("the base point", [WSTR, HSTR, "Auto", esc])):
        vm = fresh()
        vm.handle_errors = True
        vm.loads("(defun abcdef:read-file (file maxd) (list %s))"
                 % rowsrc([("P", tapes(120.0, -60.0))]))
        before = dict(vm.sysvars)
        vm.run('c:ABCDEF', script)
        check("Esc at %s reached the handler, once" % where,
              list(vm.handled_errors) == ['Function cancelled'])
        check("...leaving every setting as it was",
              {k: v for k, v in vm.sysvars.items() if before.get(k) != v} == {})
        check("...and saying nothing about an error",
              not re.search(r'\berror\b', said(vm), re.I))
        # run() itself refuses to return with an undo group still open


def test_the_version_is_announced():
    print("\nthe command says which build it is")
    vm = run([("P", tapes(120.0, -60.0))])
    ver = vm.globals.get(Sym('*abcdef-version*'))
    check("on load", ("ABCDEF.lsp rev %s loaded" % ver) in said(vm))
    check("and at the top of the run", ("\nABCDEF %s\n" % ver) in said(vm))
    check("and at the top of the report",
          any(("ABCDEF %s results" % ver) in l for l in report(vm)))


# -------------------------------------------------------------- the knobs --

def test_every_knob_is_live():
    print("\nthe tunables at the top of the file really are the knobs")
    d = tapes(300.0, -40.0)
    clean = tapes(120.0, -60.0)

    vm = run([("P", clean)], post='(setq abcdef:*frame-layer* "F2"'
                                  ' abcdef:*warn-layer* "W2"'
                                  ' abcdef:*point-layer* "P2"'
                                  ' abcdef:*frame-color* 5'
                                  ' abcdef:*point-color* 6)')
    check("the layer names are knobs", {'F2', 'W2', 'P2'} <= vm.tables['LAYER'])
    check("so are the colours they are created with",
          (layer_color(vm, 'F2'), layer_color(vm, 'P2')) == (5, 6))
    check("and the survey follows the point layer",
          all(grp(e, 8) == 'P2' for e in ents(vm, 'INSERT')))

    vm = run([("P", clean)], post='(setq abcdef:*point-block* "my_pt"'
                                  ' abcdef:*point-tag* "num")')
    check("the block and its attribute are knobs",
          'my_pt' in vm.tables.get('BLOCK', set())
          and grp(ents(vm, 'ATTRIB')[0], 2) == 'num')

    base = run([("P", clean)])
    big = run([("P", clean)], post='(setq abcdef:*text-div* 30.0)')
    hb = grp(ents(base, 'ATTRIB')[0], 40)
    hg = grp(ents(big, 'ATTRIB')[0], 40)
    check("*text-div* sets the text height (%.2f -> %.2f)" % (hb, hg),
          hg > hb * 3.0)
    tiny = run([("P", clean)], post='(setq abcdef:*text-div* 1.0e6'
                                    ' abcdef:*text-min* 3.0)')
    check("*text-min* is the floor under it",
          abs(grp(ents(tiny, 'ATTRIB')[0], 40) - 3.0) < 1e-9)

    # *fit-bad*: what counts as a row to flag
    bad = list(d)
    bad[2] += 0.4
    loose = run([("P", bad)], post='(setq abcdef:*fit-bad* 5.0)')
    tight = run([("P", bad)], post='(setq abcdef:*fit-bad* 0.01)')
    check("*fit-bad* decides what is flagged **CHECK",
          '**CHECK' not in row(loose, "P") and '**CHECK' in row(tight, "P"))

    # *fit-ok*: whether Auto goes looking for a tape to drop at all
    six = list(d)
    six[2] += 6.0
    kept = run([("P", six)], post='(setq abcdef:*fit-ok* 100.0)')
    check("*fit-ok* is the fit Auto is content with",
          used_of(row(kept, "P")) == 'ABCD')
    dropped = run([("P", six)])
    check("...and under it the bad tape is dropped",
          used_of(row(dropped, "P")) == 'ABD')

    # *drop-ratio* / *drop-margin*: how sure the evidence has to be
    strict = run([("P", six)], post='(setq abcdef:*drop-ratio* 1.0e6)')
    check("*drop-ratio* can refuse a drop the evidence does not carry",
          used_of(row(strict, "P")) == 'ABCD')

    # *edge-tol*: how far outside the frame counts as rounding.  A point
    # three tenths of an inch out fits and grades well, so the tunable is
    # the ONLY thing deciding whether it wants checking.
    near = tapes(-0.3, -100.0)
    lax = run([("OUT", near)])
    strict = run([("OUT", near)], post='(setq abcdef:*edge-tol* 0.1)')
    check("*edge-tol* decides when a snap stops being rounding",
          '(snapped' in row(lax, "OUT")
          and '0 point(s) want checking' in "".join(report(lax))
          and '1 point(s) want checking' in "".join(report(strict)))
    check("...and the summary quotes the value it used",
          any('snapped over 0.10' in l for l in report(strict)))

    # confidence and grades
    hi = run([("P", clean)], post='(setq abcdef:*grade-high* 1.0)')
    lo = run([("P", clean)], post='(setq abcdef:*grade-high* 99.5)')
    check("*grade-high* moves the word beside the number",
          conf_of(row(hi, "P"))[1] == 'HIGH'
          and conf_of(row(lo, "P"))[1] != 'HIGH')
    two = run([("P", [clean[0], clean[1], None, None])])
    two2 = run([("P", [clean[0], clean[1], None, None])],
               post='(setq abcdef:*conf-two* 0.0)')
    check("*conf-two* is what a bare pair costs",
          conf_of(row(two2, "P"))[0] > conf_of(row(two, "P"))[0])

    # the swap detector, and the poor-fit alert
    quiet = run([("P", clean), ("Q", d), ("R", tapes(200.0, -150.0))],
                post='(setq abcdef:*swap-min* 1.0e-9'
                     ' abcdef:*swap-ratio* 1.0e9)')
    check("*swap-min* / *swap-ratio* arm the C/D detector",
          "C/D NOTE" in said(quiet))
    shout = run([("P", clean)], post='(setq abcdef:*poor-fit* 1.0e-9)')
    check("*poor-fit* arms the badly-fitting-sheet alert",
          'POORLY' in (shout.globals.get(Sym('*alert*')) or ''))

    # the sheet
    vm = fresh()
    vm.loads('(setq abcdef:*hdr-dist* (list "OFF A" "OFF B" "OFF C" "OFF D")'
             ' abcdef:*hdr-name* (list "STATION"))')
    kinds = [vm.eval(lispvm.parse_all('(abcdef:col-of %s)' % lstr(h))[0])
             for h in ("OFF A", "STATION", "DIST FROM A")]
    check("*hdr-dist* / *hdr-name* name the columns",
          [str(k) for k in kinds[:2]] == ['a', 'name']
          and kinds[2] is lispvm.NIL)
    rpt = run([("P", clean)], post='(setq abcdef:*report-suffix* "_X.txt")')
    check("*report-suffix* names the report file",
          rpt.globals.get(Sym('*rpt-path*')) == r'C:\jobs\survey_X.txt')

    # the parser
    vm = fresh()
    vm.loads('(setq abcdef:*fractions* (list 2))')
    check("*fractions* bounds the fraction rebuild",
          abs(parse(vm, '20\'-7 114"') - (20 * 12 + 7 + 114)) < 1e-9)
    vm = fresh()
    vm.loads('(setq abcdef:*log-denom* 4)')
    check("*log-denom* rounds the correction log",
          vm.eval(lispvm.parse_all('(abcdef:in->ftin 476.78)')[0])
          == "39'-8 3/4\"")


def main():
    tier = os.environ.get('CALOFIN_LISP_ROOT') or 'lisp/ (standalone)'
    print("abcdef.lsp runtime tests -- tier: %s" % tier)
    for fn in (test_clean_four_tapes,
               test_three_and_two_tapes,
               test_two_tapes_take_the_inside_root,
               test_every_point_lands_inside_the_frame,
               test_drops_the_bad_tape_when_the_geometry_says_which,
               test_keeps_every_tape_when_the_geometry_cannot_say,
               test_three_disagreeing_tapes_are_never_trimmed,
               test_rows_with_too_little_are_skipped_not_guessed,
               test_confidence_separates_the_cases,
               test_fit_reports_every_tape_even_the_dropped_one,
               test_every_method_places_points_inside_the_frame,
               test_frame_is_a_true_rectangle,
               test_report_file_is_written_beside_the_sheet,
               test_points_are_the_survey_points_abhd_reads,
               test_abhd_handoff,
               test_the_view_reset_survives_its_own_catch,
               test_the_parser_reads_a_scanned_sheet,
               test_the_command_reads_its_own_csv,
               test_columns_are_found_in_any_order,
               test_a_sheet_with_nothing_usable_draws_nothing,
               test_back_walks_the_whole_question_chain,
               test_back_at_the_first_dimension_returns_to_the_file_dialog,
               test_back_at_the_base_point_reopens_the_method,
               test_the_method_question_is_asked_in_the_house_format,
               test_a_bad_dimension_is_re_asked,
               test_enter_at_the_base_point_takes_the_origin,
               test_cancel_in_the_dialog_draws_nothing,
               test_a_clockwise_sheet_is_noticed_and_swapped,
               test_a_correctly_labelled_sheet_is_left_alone,
               test_a_sheet_that_fits_the_rectangle_badly_raises_an_alert,
               test_a_mirror_pair_is_named_rather_than_guessed_at,
               test_the_corner_self_check_refuses_to_plot_a_bad_frame,
               test_a_frozen_or_locked_output_layer_is_repaired,
               test_the_point_block_is_made_once_and_reused,
               test_a_second_import_hands_abhd_only_its_own_points,
               test_the_report_file_failing_does_not_lose_the_plot,
               test_one_undo_group_opened_and_closed,
               test_no_undo_group_when_undo_is_off,
               test_esc_partway_through_goes_through_the_handler,
               test_the_version_is_announced,
               test_every_knob_is_live):
        try:
            fn()
        except LispError as e:
            check("%s raised: %s" % (fn.__name__, e), False)

    print("\n%d check(s) failed" % len(failures) if failures
          else "\nall checks passed")
    for f in failures:
        print("  - " + f)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
