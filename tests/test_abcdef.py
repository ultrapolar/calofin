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
from lispvm import VM, LispError, Sym  # noqa: E402

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
(defun open (path mode) (setq *rpt-path* path *rpt* '()) 'FP)
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


def run(rows, method="Auto", answer="No", with_abhd=False):
    """Drive c:ABCDEF over ROWS -- (name, [dA,dB,dC,dD]) with None for a
    blank cell -- and hand back the VM for inspection."""
    vm = VM()
    lispvm.BUILTINS[Sym('vl-cmdf')] = lispvm.BUILTINS[Sym('command')]
    vm.loads(STUBS)
    vm.load(LSP)
    if with_abhd:
        vm.loads('(defun c:ABHD () nil)')
    body = " ".join(
        '(list "%s" %s)' % (nm, " ".join('nil' if d is None else repr(d)
                                         for d in ds))
        for nm, ds in rows)
    # the sheet reader itself is Excel COM and file I/O, neither of which
    # is what these tests are about; the rows go in directly
    vm.loads("(defun abcdef:read-file (file maxd) (list %s))" % body)
    vm.run('c:ABCDEF', [WSTR, HSTR, method, [0.0, 0.0, 0.0], answer])
    return vm


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
               test_the_view_reset_survives_its_own_catch):
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
