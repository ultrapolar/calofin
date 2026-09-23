#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_offered.py on made files: every rule fires on the shape
it exists for, and stays quiet on the shapes that are right.

A getkword can only RETURN a keyword of its initget list.  Everything a
prompt hands back WITHOUT a keystroke -- the Enter default, a remembered
answer, a LAZTUNE knob, a form's stored answer -- is the code's own
choice, and nothing in AutoCAD holds it to the list.  ABHD's "Keep which
fit" erased every fit on a knob of "tight", POINTRENAMER numbered a
survey clockwise under <Counterclockwise>, MOHAMADDLE died on a size its
table had dropped, FITABHD fitted sharp corners under <radius>.  The
check traces each of those answers back to where it comes from; these
fixtures pin each rule both ways, the grouped tier's library hop, and
the baseline both ways.

Run: python3 tests/test_check_offered.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = pathlib.Path(HERE).parent
sys.path.insert(0, str(ROOT / 'tools'))
import check_offered  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


#: a tunables block, read by tools/knobs.py exactly as a tool's is: what
#: it declares is what LAZTUNE would offer a drafter to set
KNOBS = r""";;; -------------------- tunables ----------------------------------------
(setq fx:*kw*    "Radius")   ; the corner treatment Enter takes
(setq fx:*size*  "36")       ; the pad size Enter takes
(setq fx:*band*  6.0)        ; inches off the perimeter that count as on
(setq fx:*pct*   0.15)       ; the share of points allowed off, a fraction
(setq fx:*cap*   20)         ; the most features a run may add
;;; -------------------- end of tunables ---------------------------------
"""


def findings(*texts, names=None):
    """check_offered over made files read as one tier: [(rule, defun,
    word, file name)] for every finding that fails (advisories left
    out), and the Finding rows themselves."""
    with tempfile.TemporaryDirectory() as d:
        paths = []
        for i, t in enumerate(texts):
            name = names[i] if names else 'CASE%d.lsp' % i
            p = pathlib.Path(d) / name
            p.write_text(t, encoding='utf-8')
            paths.append(p)
        _u, rows, _n = check_offered.analyse(paths)
        got = [(r.rule, r.d.name, r.word, pathlib.Path(r.path).name)
               for r in rows if r.rule != 'E?']
        return got, rows


def rules(text):
    return {(r, dn, w) for r, dn, w, _f in findings(KNOBS + text)[0]}


def advisories(text):
    """The E? rows: what the trace could not follow.  A fixture that
    passes because its shape is RECOGNISED asserts there are none, so it
    cannot pass merely because the shape went untraced."""
    return [(r.d.name, r.word) for r in findings(KNOBS + text)[1]
            if r.rule == 'E?']


def messages(text):
    return {(r.rule, r.d.name, r.word): r.msg
            for r in findings(KNOBS + text)[1]}


# ---------------------------------------------------------------------
print("== E: the Enter answer at a keyword prompt ==")

ASKKW = r"""
(defun fx:askkw (msg kws dflt / v)
  (initget kws)
  (setq v (getkword (strcat "\n" msg " <" dflt ">: ")))
  (if v v dflt))
"""
got = rules(ASKKW + r"""
(defun c:EKNOB () (fx:askkw "Corners? [Square/Radius]" "Square Radius" fx:*kw*) (princ))
""")
check("a knob handed to an ask helper's Enter answer, raw, fails "
      "(where it enters: c:EKNOB)", ('E', 'c:eknob', 'fx:*kw*') in got, got)

got = rules(ASKKW + r"""
(defun fx:kwcanon (s kws / u out)
  (setq u (if (= (type s) 'STR) (strcase s) ""))
  (foreach w '("Square" "Radius") (if (= u (strcase w)) (setq out w)))
  out)
(defun c:EOK1 ()
  (fx:askkw "Corners? [Square/Radius]" "Square Radius"
            (cond ((fx:kwcanon fx:*kw* "Square Radius")) ("Radius")))
  (princ))
""")
check("...read through a canonicaliser at the call, it passes -- and the "
      "fallback literal is a keyword", not got, got)

CANON_OPAQUE = ASKKW + r"""
(defun fx:kwcanon (s kws)
  (car (vl-remove-if-not '(lambda (w) (= (strcase w) (strcase s))) kws)))
(defun c:EOK3 ()
  (fx:askkw "Corners? [Square/Radius]" "Square Radius"
            (cond ((fx:kwcanon fx:*kw* '("Square" "Radius"))) ("Radius")))
  (princ))
"""
got, adv = rules(CANON_OPAQUE), advisories(CANON_OPAQUE)
check("...a canonicaliser the trace cannot see into is known by its NAME: "
      "passes, with no advisory either", not got and not adv, (got, adv))

got = rules(r"""
(defun fx:askkw2 (msg kws dflt / v)
  (if (not (member dflt '("Square" "Radius"))) (setq dflt "Radius"))
  (initget kws)
  (setq v (getkword (strcat "\n" msg " <" dflt ">: ")))
  (if v v dflt))
(defun c:EOK2 () (fx:askkw2 "Corners? [Square/Radius]" "Square Radius" fx:*kw*) (princ))
""")
check("...vetted in the helper by a member test that REASSIGNS it, it "
      "passes", not got, got)

got = rules(r"""
(defun fx:askkw3 (msg kws dflt / v)
  (if (member dflt '("Square" "Radius")) (princ "\n(remembered)"))
  (initget kws)
  (setq v (getkword (strcat "\n" msg " <" dflt ">: ")))
  (if v v dflt))
(defun c:EBRANCH () (fx:askkw3 "Corners? [Square/Radius]" "Square Radius" fx:*kw*) (princ))
""")
check("...but a member test that only picks a branch is no guard",
      ('E', 'c:ebranch', 'fx:*kw*') in got, got)

got = rules(r"""
(defun c:EGBR ( / v)
  (if (member fx:*kw* '("Square" "Radius")) (princ "\n(remembered)"))
  (initget "Square Radius")
  (setq v (getkword (strcat "\nCorners? [Square/Radius] <" fx:*kw* ">: ")))
  (if (null v) (setq v fx:*kw*))
  (princ))
(defun c:EGOK ( / v)
  (if (not (member fx:*kw* '("Square" "Radius"))) (setq fx:*kw* "Radius"))
  (initget "Square Radius")
  (setq v (getkword (strcat "\nCorners? [Square/Radius] <" fx:*kw* ">: ")))
  (if (null v) (setq v fx:*kw*))
  (princ))
(defun c:EGBAD ( / v)
  (if (member fx:*kw* '("Square" "Radius")) (setq fx:*kw* "Radius"))
  (initget "Square Radius")
  (setq v (getkword (strcat "\nCorners? [Square/Radius] <" fx:*kw* ">: ")))
  (if (null v) (setq v fx:*kw*))
  (princ))
""")
check("a GLOBAL knob asked about in the prompt's own defun, by a test that "
      "only picks a branch, is no guard", ('E', 'c:egbr', 'fx:*kw*') in got,
      got)
check("...reassigned when the test calls it BAD, it passes",
      not any(dn == 'c:egok' for _r, dn, _w in got), got)
check("...reassigned when the test calls it GOOD -- the wrong way round -- "
      "it still fails", ('E', 'c:egbad', 'fx:*kw*') in got, got)

got = rules(r"""
(defun fx:asksize (dflt / hit v)
  (setq hit (if (= (type dflt) 'STR)
                (vl-some '(lambda (s) (if (= (strcase s) (strcase dflt)) s))
                         '("24" "36"))))
  (setq dflt (cond (hit) ("36")))
  (initget "24 36")
  (setq v (getkword (strcat "\nPad size? [24/36] <" dflt ">: ")))
  (if v v dflt))
(defun c:ELOOKUP () (fx:asksize fx:*size*) (princ))
""")
LOOKUP = r"""
(defun fx:asksize (dflt / hit v)
  (setq hit (if (= (type dflt) 'STR)
                (vl-some '(lambda (s) (if (= (strcase s) (strcase dflt)) s))
                         '(%s))))
  (setq dflt (cond (hit) ("36")))
  (initget "24 36")
  (setq v (getkword (strcat "\nPad size? [24/36] <" dflt ">: ")))
  (if v v dflt))
(defun c:ELOOKUP () (fx:asksize fx:*size*) (princ))
"""
adv = advisories(LOOKUP % '"24" "36"')
check("MOHAMADDLE's shape -- the default looked up in the table and "
      "reassigned -- passes, RECOGNISED as a lookup (no advisory)",
      not got and not adv, (got, adv))
got = rules(LOOKUP % '"24" "48"')
check("...a lookup whose table holds an entry the prompt does not offer "
      "fails on that entry", ('E', 'fx:asksize', '48') in got, got)

got = rules(r"""
(defun c:EARM (mode / d v)
  (setq d "Square")
  (if mode
    (setq d fx:*kw*)
    (progn
      (initget "Square Radius")
      (setq v (getkword (strcat "\nCorners? [Square/Radius] <" d ">: ")))
      (if (null v) (setq v d))))
  (princ))
(defun c:ECOND (mode / d v)
  (setq d fx:*kw*)
  (if mode (setq d "Radius"))
  (initget "Square Radius")
  (setq v (getkword (strcat "\nCorners? [Square/Radius] <" d ">: ")))
  (if (null v) (setq v d))
  (princ))
""")
check("an assignment in the OTHER arm of the if the prompt sits in never "
      "reaches it: passes", not any(dn == 'c:earm' for _r, dn, _w in got),
      got)
check("...a reassignment made only under a condition that does not test "
      "the old value leaves the knob reaching the prompt: fails",
      ('E', 'c:econd', 'fx:*kw*') in got, got)

got = rules(r"""
(defun c:ECORN (outflag / dflt key)
  (setq dflt (if outflag "Equidistant" "True"))
  (if outflag
    (progn
      (initget "Parallel Equidistant")
      (setq key (getkword (strcat "\n[Parallel/Equidistant] <" dflt ">: ")))
      (if (null key) (setq key dflt)))
    (progn
      (initget "Parallel True")
      (setq key (getkword (strcat "\n[Parallel/True] <" dflt ">: ")))
      (if (null key) (setq key dflt))))
  (princ))
""")
check("CORNERSTP's shape: a default spelt (if outflag A B) is read against "
      "the arm of (if outflag ...) the prompt sits in -- passes", not got,
      got)

got = rules(r"""
(defun c:ECASE ( / v)
  (initget "Dark Light Auto")
  (setq v (getkword "\nTheme [Dark/Light/Auto] <Auto>: "))
  (setq v (if v (strcase v) "AUTO"))
  (princ))
""")
check("CALSET's shape: (if v (strcase v) \"AUTO\") is spelt in the strcased "
      "domain, not the keyword list's -- passes", not got, got)

got = rules(ASKKW + r"""
(defun c:ELIT () (fx:askkw "Corners? [Square/Radius]" "Square Radius" "Round") (princ))
(defun c:ELIT2 () (fx:askkw "Corners? [Square/Radius]" "Square Radius" "Square") (princ))
""")
check("a literal Enter answer the caller's keyword list does not carry "
      "fails", ('E', 'c:elit', 'Round') in got, got)
check("...and one it does carry passes",
      not any(dn == 'c:elit2' for _r, dn, _w in got), got)

got = rules(r"""
(defun c:ESHOWN ( / v)
  (initget "Yes No")
  (setq v (getkword "\nKeep it? [Yes/No] <Maybe>: "))
  (princ))
""")
check("a getkword SHOWING a default that is not one of its keywords fails",
      ('E', 'c:eshown', 'Maybe') in got, got)

got = rules(r"""
(defun fx:recall () (setq fx:*last* (getenv "FxLast")))
(defun c:EGLOB ( / v)
  (initget "Yes No")
  (setq v (getkword (strcat "\nKeep? [Yes/No] <" fx:*last* ">: ")))
  (if (null v) (setq v fx:*last*))
  (princ))
(defun c:EGLOB2 ( / v)
  (initget "Yes No")
  (setq v (getkword (strcat "\nKeep? [Yes/No] <" fx:*mem* ">: ")))
  (if (null v) (setq v fx:*mem*))
  (setq fx:*mem* v)
  (princ))
""")
check("a remembered global read back from the registry fails",
      ('E', 'c:eglob', 'fx:*last*') in got, got)
check("...one only ever set from the prompt's own answer passes",
      not any(dn == 'c:eglob2' for _r, dn, _w in got), got)

# ---------------------------------------------------------------------
print("== the initget bits, one value per path ==")


def bits(src):
    from check_handlers import read_forms
    return check_offered.bits_of(read_forms(src)[0])


for src, want in (("(initget (+ (if dflt 6 7) 128) kw)", {134, 135}),
                  ("(initget (logior 4 (if z 0 2)))", {4, 6}),
                  ("(initget (if dflt 0 (if back 0 1)) kws)", {0, 1}),
                  ("(initget (cond ((eq k 'ZER) 5) (dflt 6) (t 7)) \"NA\")",
                   {5, 6, 7}),
                  ("(initget (strcat kws \" Back Undo\"))", {0}),
                  ("(initget (+ 1 flags) \"A B\")", {1})):
    got = bits(src)
    check("%s is %s" % (src, sorted(want)), got == want, sorted(got))

# ---------------------------------------------------------------------
print("== N: the Enter answer at a number prompt that refuses 0 / < 0 ==")

got = rules(r"""
(defun fx:asklim (dflt / v)
  (initget 6)
  (setq v (getdist (strcat "\nBand <" (rtos dflt) ">: ")))
  (if v v dflt))
(defun c:NBAND () (fx:asklim fx:*band*) (princ))
""")
check("POINTRENAMER's band: a knob the initget-6 prompt would refuse, "
      "handed back on Enter, fails", ('N', 'c:nband', 'fx:*band*') in got,
      got)

got = rules(r"""
(defun fx:asklim2 (dflt / v)
  (if (not (and (numberp dflt) (> dflt 0))) (setq dflt 6.0))
  (initget 6)
  (setq v (getdist (strcat "\nBand <" (rtos dflt) ">: ")))
  (if v v dflt))
(defun c:NOK () (fx:asklim2 fx:*band*) (princ))
""")
check("...range-tested where it is used, it passes", not got, got)

got = rules(r"""
(defun fx:askpct (def / pct)
  (initget 4)
  (setq pct (getint (strcat "\nPercent <" (itoa (fix (* 100.0 def))) ">: ")))
  (cond ((null pct) def) ((> pct 100) 1.0) (T (/ pct 100.0))))
(defun c:NPCT () (fx:askpct fx:*pct*) (princ))
""")
check("the miss-percent shape: a clamp on what is TYPED does not vet the "
      "knob Enter hands back", ('N', 'c:npct', 'fx:*pct*') in got, got)

got = rules(r"""
(defun fx:askpct2 (def / pct)
  (initget 4)
  (setq pct (getint (strcat "\nPercent <" (itoa (fix (* 100.0 def))) ">: ")))
  (cond ((null pct) (max 0.0 (min 1.0 def))) ((> pct 100) 1.0)
        (T (/ pct 100.0))))
(defun c:NPCT2 () (fx:askpct2 fx:*pct*) (princ))
""")
check("...clamped on the Enter branch ONLY, it still fails: <...> shows "
      "the raw knob (<1500>) while Enter takes 1.0 -- shown and taken "
      "differ", ('N', 'c:npct2', 'fx:*pct*') in got, got)
check("...and says it is the SHOWN value",
      'SHOWN' in messages(r"""
(defun fx:askpct2 (def / pct)
  (initget 4)
  (setq pct (getint (strcat "\nPercent <" (itoa (fix (* 100.0 def))) ">: ")))
  (cond ((null pct) (max 0.0 (min 1.0 def))) ((> pct 100) 1.0)
        (T (/ pct 100.0))))
(defun c:NPCT2 () (fx:askpct2 fx:*pct*) (princ))
""").get(('N', 'c:npct2', 'fx:*pct*'), ''))

got = rules(r"""
(defun fx:askpct3 (def / pct)
  (if (not (and (numberp def) (>= def 0) (<= def 1.0))) (setq def 0.15))
  (initget 4)
  (setq pct (getint (strcat "\nPercent <" (itoa (fix (* 100.0 def))) ">: ")))
  (cond ((null pct) def) ((> pct 100) 1.0) (T (/ pct 100.0))))
(defun c:NPCT3 () (fx:askpct3 fx:*pct*) (princ))
""")
check("...vetted at the top of the helper, before the prompt shows it, it "
      "passes", not got, got)

got = rules(r"""
(defun fx:askcap (dflt / v)
  (if (> dflt 100.0) (setq dflt 100.0))
  (initget 6)
  (setq v (getdist (strcat "\nBand <" (rtos dflt) ">: ")))
  (if v v dflt))
(defun c:NUPPER () (fx:askcap fx:*band*) (princ))
(defun fx:askfloor (dflt / v)
  (setq dflt (max 0.5 dflt))
  (initget 6)
  (setq v (getdist (strcat "\nBand <" (rtos dflt) ">: ")))
  (if v v dflt))
(defun c:NFLOOR () (fx:askfloor fx:*band*) (princ))
""")
check("an UPPER-only clamp is no range test where the initget refuses zero "
      "and negatives: fails", ('N', 'c:nupper', 'fx:*band*') in got, got)
check("...a (max ...) floor is one: passes",
      not any(dn == 'c:nfloor' for _r, dn, _w in got), got)

got = rules(r"""
(defun fx:askif (dflt / v)
  (initget 6)
  (setq v (getdist (strcat "\nBand" (if dflt (strcat " <" (rtos dflt) ">") "")
                           ": ")))
  (cond ((null v) (max 0.5 dflt)) (T v)))
(defun c:NSHOWIF () (fx:askif fx:*band*) (princ))
(defun fx:asklocal (dflt / v prompt)
  (setq prompt (strcat "\nBand <" (rtos dflt) ">: "))
  (initget 6)
  (setq v (getdist prompt))
  (cond ((null v) (max 0.5 dflt)) (T v)))
(defun c:NSHOWLOC () (fx:asklocal fx:*band*) (princ))
""")
check("the value SHOWN is read through an (if dflt (strcat \" <\" ...) \"\") "
      "arm: vetted on Enter only, it fails",
      ('N', 'c:nshowif', 'fx:*band*') in got, got)
check("...and through a local the prompt text was built in (spa:askd's "
      "PROMPT)", ('N', 'c:nshowloc', 'fx:*band*') in got, got)

got = rules(r"""
(defun fx:askmin (dflt / v)
  (initget 6)
  (setq v (getdist "\nBand: "))
  (if v v dflt))
(defun c:NMIN () (fx:askmin (min 12.0 fx:*band*)) (princ))
(defun fx:askfl2 (dflt / v)
  (initget 6)
  (setq v (getdist "\nBand: "))
  (cond ((null v) (setq v dflt)))
  (setq v (max 0.5 v))
  v)
(defun c:NFLOOR2 () (fx:askfl2 fx:*band*) (princ))
""")
check("a ceiling handed over -- (min 12.0 knob) -- is still the knob, "
      "unfloored: fails", ('N', 'c:nmin', 'fx:*band*') in got, got)
check("...a floor put on the ANSWER after Enter substitutes it, where "
      "nothing shows the knob: passes",
      not any(dn == 'c:nfloor2' for _r, dn, _w in got), got)

got = rules(r"""
(defun c:NOR ( / v d)
  (setq d 3.0)
  (initget 6)
  (setq v (getdist "\nBand: "))
  (if (or (null v) (equal v d 1e-9)) (setq v fx:*band*))
  (princ))
(defun c:NCONDV ( / v out)
  (initget 6)
  (setq v (getdist "\nBand: "))
  (cond (v (setq out v)) (T (setq out fx:*band*)))
  (princ))
""")
check("an (or (null v) ...) branch that ASSIGNS the answer is an Enter "
      "branch, bound or no bound: fails", ('N', 'c:nor', 'fx:*band*') in got,
      got)
check("...and so is the (T X) a (cond (v ...) ...) falls to: fails",
      ('N', 'c:ncondv', 'fx:*band*') in got, got)

KEEP = r"""
(defun fx:settings (def / pct v)
  (setq pct (nth 1 def))
  (initget 6)
  (setq v (getint (strcat "\nPercent <" (itoa (fix (* 100.0 pct))) ">: ")))
  (cond ((null v) (princ "\nKept."))
        (T (setq pct (/ v 100.0))))
  pct)
"""
got = rules(KEEP + r"""
(defun c:NKEEP () (fx:settings (list "x" fx:*pct*)) (princ))
""")
check("FITABHD's percent: Enter KEEPS the shown value, a knob nothing "
      "range-tests, and that fails", ('N', 'c:nkeep', 'fx:*pct*') in got,
      got)
msg = messages(KEEP + r"""
(defun c:NKEEP () (fx:settings (list "x" fx:*pct*)) (princ))
""").get(('N', 'c:nkeep', 'fx:*pct*'), '')
check("...as the value ENTER KEEPS, not merely the one shown",
      'is the Enter answer' in msg, msg)
got = rules(KEEP + r"""
(defun c:NKEEP2 ()
  (fx:settings (list "x" (if (and (numberp fx:*pct*) (> fx:*pct* 0)
                                  (<= fx:*pct* 1.0))
                             fx:*pct* 0.15)))
  (princ))
""")
check("...vetted where it is handed over, it passes", not got, got)

got = rules(r"""
(defun c:NLIT ( / v)
  (initget 6)
  (setq v (getint "\nHow many <0>: "))
  (if (null v) (setq v 0))
  (princ))
""")
check("a literal Enter answer the initget refuses (0 at bit 2) fails",
      ('N', 'c:nlit', '0') in got, got)

ASKD = r"""
(defun fx:askd (msg dflt back / kw v out prompt)
  (setq kw (if back "Back Undo" nil))
  (setq prompt (strcat "\n" msg (if dflt (strcat " <" (rtos dflt) ">") "")
                       (if back " [Back]" "") ": "))
  (while (null out)
    (if kw (initget (+ (if dflt 6 7) 128) kw)
        (initget (+ (if dflt 6 7) 128)))
    (setq v (getdist prompt))
    (cond
      ((and back (= (type v) 'STR) (member v '("Back" "Undo")))
       (setq out 'FX-BACK))
      ((and (null v) dflt) (setq out dflt))
      ((numberp v) (setq out v))))
  out)
"""
got = rules(ASKD + r"""
(defun c:NSPA () (fx:askd "Lap" fx:*band* T) (princ))
(defun c:NSPAOK ()
  (fx:askd "Lap" (if (and (numberp fx:*band*) (> fx:*band* 0)) fx:*band* 6.0)
           T)
  (princ))
""")
check("SPA's cover lap: (+ (if dflt 6 7) 128) is bits 134 or 135 -- Enter "
      "allowed, zero and negatives refused -- and ((and (null v) dflt) "
      "(setq out dflt)) is the Enter branch: a raw knob fails",
      ('N', 'c:nspa', 'fx:*band*') in got, got)
check("...vetted where it is handed over, it passes",
      not any(dn == 'c:nspaok' for _r, dn, _w in got), got)

got = rules(r"""
(defun fx:askdist (kind msg dflt / v)
  (initget (cond ((eq kind 'ZER) 5) ((and (eq kind 'SUG) dflt) 6) (t 7))
           "NA")
  (setq v (getdist (strcat "\n" msg (if dflt (strcat " <" (rtos dflt) ">")
                                        "") ": ")))
  (cond ((= (type v) 'STR) nil)
        ((and (null v) (eq kind 'SUG)) dflt)
        (t v)))
(defun c:NSUG () (fx:askdist 'SUG "Band" fx:*band*) (princ))
""")
check("the library's askdist: ((and (null v) (eq kind 'SUG)) dflt) hands a "
      "SUG knob back on Enter: fails", ('N', 'c:nsug', 'fx:*band*') in got,
      got)

got = rules(r"""
(defun fx:askshown (dflt / v shown out)
  (setq shown (if (and (numberp dflt) (> dflt 0)) dflt 6.0))
  (initget 6)
  (setq v (getdist (strcat "\nBand <" (rtos shown) ">: ")))
  (cond ((null v) (setq out fx:*band*)) (T (setq out v)))
  out)
(defun c:NHAND () (fx:askshown fx:*band*) (princ))
""")
check("an Enter branch that HANDS OVER a value -- (setq out knob) -- is "
      "traced as that value, not read as keeping the one shown: fails",
      ('N', 'fx:askshown', 'fx:*band*') in got, got)

got = rules(r"""
(defun c:NOWN ( / n)
  (initget "Back Undo")
  (setq n (getint (strcat "\nMaximum features <" (itoa fx:*cap*) ">: ")))
  (if (or (not n) (< n 1)) (setq n fx:*cap*))
  (princ))
(defun c:NOWNOK ( / n cap)
  (setq cap (if (and (numberp fx:*cap*) (>= fx:*cap* 1)) fx:*cap* 20))
  (initget "Back Undo")
  (setq n (getint (strcat "\nMaximum features <" (itoa cap) ">: ")))
  (if (or (not n) (< n 1)) (setq n cap))
  (princ))
(defun c:NOWNLOOP ( / n)
  (while (progn (initget "Back Undo")
                (setq n (getint (strcat "\nHeight <" (rtos fx:*band*)
                                        ">: ")))
                (if (or (null n) (<= n 0)) (princ "\nMore than 0.")))
    (princ))
  (princ))
(defun c:NCLICK ( / v)
  (initget 6)
  (setq v (getdist "\nBand: "))
  (cond ((and (null v) (= 7 (getvar "ERRNO"))) (setq v fx:*band*)))
  (princ))
""")
check("WCALST's cap: no initget bits, but the code refuses a typed value "
      "below 1 and hands the knob back instead, never testing the knob "
      "against its own bound: fails", ('N', 'c:nown', 'fx:*cap*') in got,
      got)
nown = [r for r in findings(KNOBS + r"""
(defun c:NOWN ( / n)
  (initget "Back Undo")
  (setq n (getint (strcat "\nMaximum features <" (itoa fx:*cap*) ">: ")))
  (if (or (not n) (< n 1)) (setq n fx:*cap*))
  (princ))
""")[0]]
check("...ONE finding, though the knob is both shown and handed back raw",
      len(nown) == 1, nown)
check("...the knob held to the same bound first: passes",
      not any(dn == 'c:nownok' for _r, dn, _w in got), got)
check("...an (or (null v) ...) branch that only prints and re-asks is a "
      "refusal, not an answer: passes",
      not any(dn == 'c:nownloop' for _r, dn, _w in got), got)
check("...and (and (null v) (= 7 (getvar \"ERRNO\"))) is a missed CLICK, "
      "not Enter: passes", not any(dn == 'c:nclick' for _r, dn, _w in got),
      got)

# ---------------------------------------------------------------------
print("== T1 / T2: a bit-128 prompt and the words it never offered ==")

got = rules(r"""
(defun c:TNEVER ( / a)
  (initget 128 "None Back")
  (setq a (getpoint "\nPick a point [None/Back]: "))
  (cond ((= a "Whole") (princ "whole")) ((= a "None") (princ "none")))
  (princ))
""")
check("a typed word compared with one the prompt never offers fails",
      ('T1', 'c:tnever', 'Whole') in got, got)
TNEVER_MSG = messages(r"""
(defun c:TNEVER ( / a)
  (initget 128 "None Back")
  (setq a (getpoint "\nPick a point [None/Back]: "))
  (cond ((= a "Whole") (princ "whole")) ((= a "None") (princ "none")))
  (princ))
""")
check("...and says so, as NEVER offered",
      'never offers' in TNEVER_MSG.get(('T1', 'c:tnever', 'Whole'), ''),
      TNEVER_MSG)

got = rules(r"""
(defun t1:gate (msg back / a)
  (initget 128 (if back "None Back" "None"))
  (setq a (getpoint (strcat "\n" msg (if back " [None/Back]" " [None]")
                            ": ")))
  (if back (if (= a "Whole") (princ "\nwhole")))
  a)
(defun c:TGATE ( / p) (setq p (t1:gate "Point" T)) (princ))
""")
check("...a never-offered word compared under a gate (the gate guards "
      "only what IS offered) still fails", ('T1', 't1:gate', 'Whole') in got,
      got)
check("...and the one it offers does not",
      ('T1', 'c:tnever', 'None') not in got, got)

T1ASK = r"""
(defun t1:ask (msg whole / a)
  (initget 128 (if whole "Whole Back" "Back"))
  (setq a (getpoint (strcat "\n" msg (if whole " [Whole/Back]" " [Back]")
                            ": ")))
  (cond ((= a "Whole") 'T1-WHOLE)
        ((= a "Back") 'T1-BACK)
        (T a)))
"""
got = rules(T1ASK + r"""
(defun c:TCOND ( / p) (setq p (t1:ask "Point" nil)) (princ))
""")
check("UPADOVER's Whole: offered only when WHOLE, compared always, and a "
      "caller that does not offer it never tests the sentinel -- fails",
      ('T1', 't1:ask', 'Whole') in got, got)

got = rules(T1ASK + r"""
(defun c:TCOND2 ( / p)
  (setq p (t1:ask "Point" nil))
  (if (eq p 'T1-WHOLE) (princ "\nNot offered here.") (princ))
  (princ))
(defun c:TCOND3 ( / p) (setq p (t1:ask "Point" T)) (princ))
""")
check("...every caller either offers it or handles the sentinel: passes",
      not got, got)

got = rules(r"""
(defun c:TTYPE ( / p)
  (initget 128 "Back")
  (setq p (getpoint "\nPick [Back]: "))
  (if (= p "Back") (princ) (princ (car p)))
  (princ))
""")
check("DRONOTE's shape: (car p) where a typed word can still be fails",
      ('T2', 'c:ttype', 'car p') in got, got)

got = rules(r"""
(defun c:TTYPE2 ( / p)
  (initget 128 "Back")
  (setq p (getpoint "\nPick [Back]: "))
  (cond ((= (type p) 'STR) (princ "\nNot a point."))
        (p (princ (car p))))
  (princ))
""")
check("...behind a (type p) test it passes", not got, got)

# ---------------------------------------------------------------------
print("== S: a stored answer standing in for the prompt ==")

STORE = r"""
(defun fx:ftake (k) (cdr (assoc k fx:*form*)))
(defun fx:fok (k v) (member v '("A" "B")))
(defun fx:ask2 () (initget "A B") (getkword "\nWhich? [A/B]: "))
"""
got = rules(STORE + r"""
(defun c:SRAW ( / v)
  (setq v (if (fx:ftake 'which) (fx:ftake 'which) (fx:ask2)))
  (princ))
""")
check("POOL/SPA askseqb's old shape: the form's answer taken raw fails",
      ('S', 'c:sraw', 'v') in got, got)

got = rules(STORE + r"""
(defun c:SOK ( / v fv)
  (setq v (if (fx:fok 'which (setq fv (fx:ftake 'which))) fv (fx:ask2)))
  (princ))
""")
check("...handed to a check before it stands in, it passes", not got, got)

# ---------------------------------------------------------------------
print("== I: an initget spent before the loop re-asks ==")

got = rules(r"""
(defun c:ILOOP ( / v)
  (initget "Yes No")
  (while (not (setq v (getkword "\nReady? [Yes/No]: ")))
    (princ "\nYes or No."))
  (princ))
""")
check("an initget outside the loop that re-asks its prompt fails",
      any(r == 'I' and dn == 'c:iloop' for r, dn, _w in got), got)

got = rules(r"""
(defun c:IOK ( / v)
  (while (progn (initget "Yes No")
                (not (setq v (getkword "\nReady? [Yes/No]: "))))
    (princ "\nYes or No."))
  (princ))
""")
check("...re-armed inside the loop, it passes", not got, got)

# ---------------------------------------------------------------------
print("== the grouped tier: a part's knob into the library's prompt ==")

LIB = r"""
(defun cal:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'CAL-BACK)
        ((null v) (if dflt dflt (cal:askkw msg kws shown dflt back)))
        (t v)))
"""
PART = KNOBS + r"""
(defun c:PART ()
  (cal:askkw "Corners?" "Square Radius" "Square/Radius" fx:*kw* T)
  (princ))
"""
got, _rows = findings(LIB, PART, names=['CALOFIN-LIB.lsp', 'PART.lsp'])
check("a part's knob reaching the library's getkword is reported in the "
      "PART, where it enters",
      ('E', 'c:part', 'fx:*kw*', 'PART.lsp') in got, got)

# ---------------------------------------------------------------------
print("== the baseline: a decision holds a site, and goes stale ==")

BAD = KNOBS + r"""
(defun c:TNEVER ( / a)
  (initget 128 "None Back")
  (setq a (getpoint "\nPick a point [None/Back]: "))
  (if (= a "Whole") (princ "\nJust click it."))
  (princ))
"""
with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d) / 'BASE.lsp'
    p.write_text(BAD, encoding='utf-8')
    key = (check_offered.rel(p), 'c:tnever', 'T1 Whole')
    out = []
    n = check_offered.report([p], {}, out=out.append)
    check("with no baseline the site fails", n == 1, out)
    hit, out = set(), []
    n = check_offered.report([p], {key: 'prints guidance, takes nothing'},
                             out=out.append, hit=hit)
    check("a baselined site is not a failure", n == 0 and key in hit, out)
    gone = (check_offered.rel(p), 'c:tnever', 'T1 Pick')
    out = []
    ns = check_offered.stale_lines({key: 'x', gone: 'y'}, hit,
                                   out=out.append)
    check("a baseline line nothing matches is reported stale",
          ns == 1 and 'T1 Pick' in out[0], out)
    bfile = pathlib.Path(d) / 'b.txt'
    bfile.write_text('# a comment\n%s|%s|%s|the reason, with a | in it\n'
                     % key, encoding='utf-8')
    base = check_offered.load_baseline(bfile)
    check("the baseline reads file|defun|RULE word|reason",
          base == {key: 'the reason, with a | in it'}, base)

# one line holds a site in every tier: the key is the defun's lisp/ home,
# so the grouped twin and a dated release file their site under it too


class _Home:
    name = 'c:pointrenamer'
    line = 1


keys = set()
for where in (ROOT / 'lisp' / 'pointrenamer' / 'POINTRENAMER.lsp',
              ROOT / 'shared' / 'parts' / 'POINTRENAMER.lsp',
              ROOT / 'releases' / 'POINTRENAMER_010126_REV01.lsp'):
    _Home.path = where
    keys.add(check_offered.key_of(
        check_offered.Finding('N', _Home, 1, 'ptr:*band*', '', where)))
check("a site in lisp/, its grouped twin and its release share one "
      "baseline key", keys == {('lisp/pointrenamer/POINTRENAMER.lsp',
                                'c:pointrenamer', 'N ptr:*band*')}, keys)

# ...and a nested helper, which no top-level defun names, by its FILE
_Home.name = 'ptr:no-such-top-level-defun'
keys = {check_offered.key_of(check_offered.Finding(
    'E', _Home, 1, 'x', '', where)) for where in (
        ROOT / 'shared' / 'parts' / 'POINTRENAMER.lsp',
        ROOT / 'releases' / 'POINTRENAMER_010126_REV01.lsp')}
check("...as does a nested helper's, found by its file's name",
      {k[0] for k in keys} == {'lisp/pointrenamer/POINTRENAMER.lsp'}, keys)

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall check_offered rules fire, and the right shapes pass")
