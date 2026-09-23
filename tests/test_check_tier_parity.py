#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""tools/check_tier_parity.py on made files: every rule fires on the drift
it exists for, and stays quiet on the shape that is right.

Every tier drift found so far was in what a swapped helper reads from
AROUND its arguments: a knob the local copy read and the library's
hard-coded (lin:*back-words*, *cchk-flat-eps*), a profile key the
library read and eleven local copies did not (CalofinInk-<ROLE>), a
sysvar a builtin read behind the helper's back (rtos and DIMZIN), a
mirror expand that kept snapshotting a sysvar the source had dropped
(SPACHECK's CLAYER), a sentinel renamed on one side only.  Each fixture
below is one of those shapes, cut down to a few lines, run through the
REAL mirror (mirror_shared.generate pointed at a temporary tree), and
paired with the shape that fixed it.  The second half was added when a
review mutated every branch of the checker and found the ones no
fixture noticed: each branch now has one (a per-pair state read, a
getvar read in place, rtos's mode and precision by argument count, the
refusing mirror, a hand-kept twin), and every blind spot it found has
one too (a '(lambda ...) arity, a knob renamed onto a library global, a
sibling's knob, a DIM sysvar, a tool's own baseline key).

The last section runs the check over the real tree, at the standalone
tier only: the check reads lisp/, the library and the mirror's output
whatever CALOFIN_LISP_ROOT says, so make parity would run it twice.

Run: python3 tests/test_check_tier_parity.py
"""

import os
import pathlib
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
import check_tier_parity  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


LIB = r""";;; fixture library
(defun cal:setting (key dflt / v)
  (setq v (getenv key))
  (if (and v (/= v "")) v dflt))
(defun cal:ink (knob role / ov)
  (cond ((numberp knob) knob)
        ((/= "" (setq ov (cal:setting (strcat "CalofinInk-" (vl-symbol-name role)) "")))
         (atoi ov))
        (t 7)))
(defun cal:back-word-p (s) (member (strcase s) '("B" "BACK" "U" "UNDO")))
(defun cal:datestr ( / d) (setq d (getvar "CDATE")) (itoa (fix d)))
(setq cal:*sysold* nil)
(defun cal:syssave (vars)
  (if (not cal:*sysold*)
    (setq cal:*sysold* (mapcar '(lambda (v) (cons v (getvar v))) vars))))
(defun cal:sysrestore ()
  (foreach p cal:*sysold* (setvar (car p) (cdr p)))
  (setq cal:*sysold* nil))
(defun cal:askkw (msg kws / v)
  (initget kws) (setq v (getkword msg))
  (if (= v "Back") 'CAL-BACK v))
(setq cal:*eps* 1e-12)
(defun cal:unite (v) (if (> (distance '(0.0 0.0 0.0) v) cal:*eps*) v))
(defun cal:nearest (pts p snap)
  (car (vl-remove-if-not '(lambda (q) (< (distance p q) snap)) pts)))
(defun cal:mtext (ins txt / e)
  (setq e (entmakex (list '(0 . "MTEXT") (cons 10 ins) (cons 1 txt))))
  e)
(defun cal:pair (a b) (list a b))
(setq cal:*font-w* 40)
(defun cal:textw (s) (* (strlen s) cal:*font-w*))
(setq cal:*odstyle* nil)
(defun cal:stysave () (setq cal:*odstyle* (getvar "DIMSTYLE")))
(defun cal:styrestore ()
  (if cal:*odstyle* (command "_.-DIMSTYLE" "_Restore" cal:*odstyle*))
  (setq cal:*odstyle* nil))
(defun cal:stydrop () (command "_.-DIMSTYLE" "_Restore" "Standard"))
(setq cal:*old* nil)
(defun cal:savevars (vars)
  (setq cal:*old* (mapcar '(lambda (v) (cons v (getvar v))) vars)))
(defun cal:restorevars () (foreach p cal:*old* (setvar (car p) (cdr p))))
(defun cal:scale () 1.0)
(defun cal:fmt (x) (rtos x))
(defun cal:getnum (msg) (getreal msg))
(defun cal:pick (key x) x)
(defun cal:pt (p) (entmake (list '(0 . "POINT") (cons 10 p))))
(defun cal:putvars (vars vals)
  (foreach p (mapcar 'cons vars vals) (setvar (car p) (cdr p))))
(defun cal:prep () (princ))
(defun cal:pad (s w) (while (< (strlen s) w) (setq s (strcat s " "))) s)
"""


def tool(prefix, knobs, body):
    """A made lisp/ file: a tunables block, then BODY."""
    return (";;; %s -- a fixture\n;;; Command: %s\n;;;\n"
            ";;; -------------------- tunables --------------------\n"
            "%s\n;;; -------------------- the code --------------------\n%s\n"
            % (prefix.upper(), prefix.upper(), knobs, body))


FILES, SPECS = {}, {}


def add(name, knobs, body, **spec):
    path = "lisp/%s/%s.lsp" % (name.lower(), name)
    FILES[path] = tool(name, knobs, body)
    spec.setdefault("swap", {})
    spec.setdefault("drop_globals", [])
    spec["src"] = path
    SPECS[name] = spec


# P1 global: a knob the local helper reads and the library hard-codes
# (lin:*back-words*), and the same helper with its words written in
add("KNOBBAD", "(setq kb:*back-words* '(\"B\" \"BACK\" \"U\" \"UNDO\"))",
    "(defun kb:back-word (s) (member (strcase s) kb:*back-words*))\n"
    "(defun c:KNOBBAD () (kb:back-word (getstring)))",
    swap={"kb:back-word": "cal:back-word-p"})
add("KNOBOK", "(setq ko:*gap* 1.0)",
    "(defun ko:back-word (s) (member (strcase s) '(\"B\" \"BACK\" \"U\" \"UNDO\")))\n"
    "(defun c:KNOBOK () (ko:back-word (getstring)))",
    swap={"ko:back-word": "cal:back-word-p"})

# P1 env: the library reads CalofinInk-<ROLE> through cal:setting, the
# local ink does not -- and the local that reads it through getenv
add("INKBAD", "(setq ib:*col* 'auto)",
    "(defun ib:ink (knob role) (if (numberp knob) knob 7))\n"
    "(defun c:INKBAD () (ib:ink ib:*col* 'guide))",
    swap={"ib:ink": "cal:ink"})
add("INKOK", "(setq io:*col* 'auto)",
    "(defun io:ink (knob role / ov)\n"
    "  (cond ((numberp knob) knob)\n"
    "        ((setq ov (getenv (strcat \"CalofinInk-\" (vl-symbol-name role))))\n"
    "         (atoi ov))\n"
    "        (t 7)))\n"
    "(defun c:INKOK () (io:ink io:*col* 'guide))",
    swap={"io:ink": "cal:ink"})

# P1 implicit: rtos reads DIMZIN; the library's itoa does not
add("DATEBAD", "(setq db:*gap* 1.0)",
    "(defun db:datestr () (rtos (getvar \"CDATE\") 2 6))\n"
    "(defun c:DATEBAD () (db:datestr))",
    swap={"db:datestr": "cal:datestr"})

# P1 sysvar: the hand-typed expand still snapshots CLAYER after the
# source dropped it (SPACHECK) -- and the expand that matches.  The
# save/restore pair shares tb:*sysold* / cal:*sysold*: state, not a
# knob, so the two are one slot
SYS = ("(setq %s:*sysold* nil)",
       "(defun %s:syssave ()\n"
       "  (if (not %s:*sysold*)\n"
       "    (setq %s:*sysold* (mapcar '(lambda (v) (cons v (getvar v)))\n"
       "                              '(\"CMDECHO\")))))\n"
       "(defun %s:sysrestore ()\n"
       "  (foreach p %s:*sysold* (setvar (car p) (cdr p)))\n"
       "  (setq %s:*sysold* nil))\n"
       "(defun c:%s () (%s:syssave) (%s:sysrestore))")
for name, pre, typed in (("TABLEBAD", "tb", '"CMDECHO" "CLAYER"'),
                         ("TABLEOK", "to", '"CMDECHO"')):
    add(name, SYS[0] % pre, SYS[1] % ((pre,) * 6 + (name, pre, pre)),
        swap={pre + ":syssave": "cal:syssave",
              pre + ":sysrestore": "cal:sysrestore"},
        drop_globals=[pre + ":*sysold*"],
        expand={"(cal:syssave)": ["(cal:syssave '(%s))" % typed]})

# ...and the same drift in a SATELLITE, whose swapped helper lives in
# its sibling (TUTORIALSPA drives SPA's)
FILES["lisp/tablebad/TABLESAT.lsp"] = tool(
    "TABLESAT", "(setq ts:*gap* 1.0)",
    "(defun c:TABLESAT () (tb:syssave) (tb:sysrestore))")
SPECS["TABLESAT"] = {
    "src": "lisp/tablebad/TABLESAT.lsp", "drop_globals": [],
    "swap": {"tb:syssave": "cal:syssave", "tb:sysrestore": "cal:sysrestore"},
    "expand": {"(cal:syssave)": ["(cal:syssave '(\"CMDECHO\" \"OSMODE\"))"]}}

# P1 sym: the local ask hands back SB-BACK and the caller tests for it;
# without the symbols map the grouped caller never sees CAL-BACK
ASK = ("(defun %s:askkw (msg kws / v)\n"
       "  (initget kws) (setq v (getkword msg))\n"
       "  (if (= v \"Back\") '%s-BACK v))\n"
       "(defun c:%s ( / r)\n"
       "  (setq r (%s:askkw \"Go? \" \"Yes No Back\"))\n"
       "  %s)")
add("SYMBAD", "(setq sb:*gap* 1.0)",
    ASK % ("sb", "SB", "SYMBAD", "sb", "(if (eq r 'SB-BACK) (princ))"),
    swap={"sb:askkw": "cal:askkw"})
add("SYMOK", "(setq so:*gap* 1.0)",
    ASK % ("so", "SO", "SYMOK", "so", "(if (eq r 'SO-BACK) (princ))"),
    swap={"so:askkw": "cal:askkw"}, symbols={"SO-BACK": "CAL-BACK"})
add("SYMUNTESTED", "(setq su:*gap* 1.0)",
    ASK % ("su", "SU", "SYMUNTESTED", "su", "(princ r)"),
    swap={"su:askkw": "cal:askkw"})

# P1 global, the prefix rule: kn:*eps* is a KNOB of the tool, so it is
# not the same input as the library's cal:*eps* however alike the names
add("KNOBNAME", "(setq kn:*eps* 1e-12)",
    "(defun kn:unite (v) (if (> (distance '(0.0 0.0 0.0) v) kn:*eps*) v))\n"
    "(defun c:KNOBNAME () (kn:unite (getpoint)))",
    swap={"kn:unite": "cal:unite"})

# P1 via collapse: the knob handed over as the extra argument -- and a
# literal handed over in its place (UPADOVER's snap)
NEAR = ("(defun %s:nearest (pts p)\n"
        "  (car (vl-remove-if-not '(lambda (q) (< (distance p q) %s:*snap*)) pts)))\n"
        "(defun c:%s () (%s:nearest (list (getpoint)) (getpoint)))")
add("COLLAPSEOK", "(setq co:*snap* 12.0)", NEAR % ("co", "co", "COLLAPSEOK", "co"),
    collapse={"co:nearest": ("cal:nearest", "co:*snap*")})
add("COLLAPSEBAD", "(setq cb:*snap* 12.0)", NEAR % ("cb", "cb", "COLLAPSEBAD", "cb"),
    collapse={"cb:nearest": ("cal:nearest", "12.0")})

# P1 effect: a rewrite that loses the entmod the local body makes
add("REWRITEBAD", "(setq rb:*gap* 1.0)",
    "(defun rb:mtext (ins txt / e)\n"
    "  (setq e (entmakex (list '(0 . \"MTEXT\") (cons 10 ins) (cons 1 txt))))\n"
    "  (entmod (subst (cons 8 \"REPORT\") (assoc 8 (entget e)) (entget e)))\n"
    "  e)\n"
    "(defun c:REWRITEBAD () (rb:mtext (getpoint) \"x\"))",
    rewrite={"rb:mtext": "(defun rb:mtext (ins txt) (cal:mtext ins txt))\n"})

# P3: a swap onto a library helper of another arity, with no expand to
# make up the difference -- and the expand that does
PAIR = ("(defun %s:pair (a) (list a nil))\n"
        "(defun c:%s () (%s:pair (getpoint)))")
add("ARITYBAD", "(setq ab:*gap* 1.0)", PAIR % ("ab", "ARITYBAD", "ab"),
    swap={"ab:pair": "cal:pair"})
add("ARITYOK", "(setq ao:*gap* 1.0)", PAIR % ("ao", "ARITYOK", "ao"),
    swap={"ao:pair": "cal:pair"},
    expand={"(cal:pair (getpoint))": ["(cal:pair (getpoint) nil)"]})

# P4: the mirror drops a table and the surviving code still names it
# (no symbols rename), or renames it onto a name the library never says
FONT = ("(setq %s:*font-w* 40)",
        "(defun %s:textw (s) (* (strlen s) %s:*font-w*))\n"
        "(defun c:%s () (list (%s:textw \"ab\") %s:*font-w*))")
# (LAZFORM's font table sits below its tunables block, not in it)
for name, pre, sym in (("DROPBAD", "pb", None),
                       ("DROPOK", "po", "cal:*font-w*"),
                       ("DROPWRONG", "pw", "cal:*fnt-w*")):
    add(name, "(setq %s:*gap* 1.0)" % pre,
        FONT[0] % pre + "\n" + FONT[1] % (pre, pre, name, pre, pre),
        swap={pre + ":textw": "cal:textw"}, drop_globals=[pre + ":*font-w*"],
        symbols=({pre + ":*font-w*": sym} if sym else {}))

# P4, the slot a swapped-away helper kept: the run resets rs:*sysold*
# at its top so a stale snapshot cannot silence syssave -- in the grouped
# build that clears a global nothing writes, and cal:*sysold* stays
# stale.  POOL renames its slot onto the library's for exactly this;
# SPACHECK keeps only the load-time setq, which is inert
RESET = ("(defun c:%s ()\n  %s(%s:syssave) (%s:sysrestore))")
for name, pre, reset, sym in (
        ("RESETBAD", "rs", True, None),
        ("RESETOK", "rk", True, "cal:*sysold*"),
        ("INITONLY", "ri", False, None)):
    body = (SYS[1] % ((pre,) * 6 + (name, pre, pre))).rsplit("(defun c:", 1)[0]
    body += RESET % (name, ("(setq %s:*sysold* nil)\n  " % pre) if reset else "",
                     pre, pre)
    add(name, SYS[0] % pre, body,
        swap={pre + ":syssave": "cal:syssave",
              pre + ":sysrestore": "cal:sysrestore"},
        expand={"(cal:syssave)": ["(cal:syssave '(\"CMDECHO\"))"]},
        # POOL's shape: the slot renamed AND its load-time setq dropped
        drop_globals=([pre + ":*sysold*"] if sym else []),
        symbols=({pre + ":*sysold*": sym} if sym else {}))

# ---- added after review: one fixture for every branch a mutation of the
# ---- checker survived, and for every blind spot the review found

# P3 inside a quoted lambda: '(lambda ...) is how mapcar is written here
add("ARITYLAM", "(setq al:*gap* 1.0)",
    "(defun al:pair (a) (list a nil))\n"
    "(defun c:ARITYLAM () (mapcar '(lambda (p) (al:pair p)) (list (getpoint))))",
    swap={"al:pair": "cal:pair"})

# P3 reached through a symbols rename onto a library FUNCTION -- a swap
# in all but name, with nothing pairing the two argument lists
add("SYMFN", "(setq sf:*gap* 1.0)",
    "(defun sf:pair (a) (list a nil))\n"
    "(defun c:SYMFN () (sf:pair (getpoint)))",
    symbols={"sf:pair": "cal:pair"})

# P1 + P4: a LAZTUNE knob dropped AND renamed onto the library's global:
# the grouped build reads cal:*eps*, never the drafter's kr:*eps*
add("KNOBREN", "(setq kr:*eps* 1e-3)",
    "(defun kr:unite (v) (if (> (distance '(0.0 0.0 0.0) v) kr:*eps*) v))\n"
    "(defun c:KNOBREN () (kr:unite (getpoint)))",
    swap={"kr:unite": "cal:unite"}, drop_globals=["kr:*eps*"],
    symbols={"kr:*eps*": "cal:*eps*"})
# ...and merely dropped
add("KNOBDROP", "(setq kd:*eps* 1e-3)",
    "(defun kd:unite (v) (if (> (distance '(0.0 0.0 0.0) v) kd:*eps*) v))\n"
    "(defun c:KNOBDROP () (kd:unite (getpoint)))",
    swap={"kd:unite": "cal:unite"}, drop_globals=["kd:*eps*"])

# P1 in a satellite: the swapped helper lives in the sibling and reads
# the SIBLING's knob, which must not fold onto cal:*eps*
FILES["lisp/satbase/SATBASE.lsp"] = tool(
    "SATBASE", "(setq sb:*eps* 1e-3)",
    "(defun sb:unite (v) (if (> (distance '(0.0 0.0 0.0) v) sb:*eps*) v))\n"
    "(defun c:SATBASE () (sb:unite (getpoint)))")
SPECS["SATBASE"] = {"src": "lisp/satbase/SATBASE.lsp", "swap": {},
                    "drop_globals": []}
FILES["lisp/satbase/SATSAT.lsp"] = tool(
    "SATSAT", "(setq ss:*gap* 1.0)", "(defun c:SATSAT () (sb:unite (getpoint)))")
SPECS["SATSAT"] = {"src": "lisp/satbase/SATSAT.lsp", "drop_globals": [],
                   "swap": {"sb:unite": "cal:unite"}}

# P1 per-pair state: the save still writes the slot, the grouped RESTORE
# stops reading it (restores "Standard" whatever was saved) -- and the
# restore that reads it
STY = ("(setq %s:*odstyle* nil)\n"
       "(defun %s:stysave () (setq %s:*odstyle* (getvar \"DIMSTYLE\")))\n"
       "(defun %s:styrestore ()\n"
       "  (if %s:*odstyle* (command \"_.-DIMSTYLE\" \"_Restore\" %s:*odstyle*))\n"
       "  (setq %s:*odstyle* nil))\n"
       "(defun c:%s () (%s:stysave) (%s:styrestore))")
for name, pre, restore in (("STYLEBAD", "yb", "cal:stydrop"),
                           ("STYLEOK", "yo", "cal:styrestore")):
    add(name, "(setq %s:*gap* 1.0)" % pre,
        STY % ((pre,) * 7 + (name, pre, pre)),
        swap={pre + ":stysave": "cal:stysave", pre + ":styrestore": restore},
        drop_globals=[pre + ":*odstyle*"])

# the union of pairs that READ state: the restore names no sysvar in the
# grouped build (the save's expand does), and neither restore writes the
# slot -- only reading it ties the two into one mechanism
add("STATEREAD", "(setq rd:*gap* 1.0)",
    "(setq rd:*old* nil)\n"
    "(defun rd:save () (setq rd:*old* (getvar \"CLAYER\")))\n"
    "(defun rd:restore () (if rd:*old* (setvar \"CLAYER\" rd:*old*)))\n"
    "(defun c:STATEREAD () (rd:save) (rd:restore))",
    swap={"rd:save": "cal:savevars", "rd:restore": "cal:restorevars"},
    drop_globals=["rd:*old*"],
    expand={"(cal:savevars)": ["(cal:savevars '(\"CLAYER\"))"]})

# P1 sysvar, read in place: (getvar "INSUNITS") in the local only
add("GETVARBAD", "(setq gb:*gap* 1.0)",
    "(defun gb:scale () (if (= 4 (getvar \"INSUNITS\")) 25.4 1.0))\n"
    "(defun c:GETVARBAD () (gb:scale))",
    swap={"gb:scale": "cal:scale"})

# P1 implicit, by argument count: (rtos x 2 2) names mode and precision,
# the library's (rtos x) reads LUNITS and LUPREC -- and the one that
# leaves them out as the library does
add("IMPLBAD", "(setq ib2:*gap* 1.0)",
    "(defun ib2:fmt (x) (rtos x 2 2))\n(defun c:IMPLBAD () (ib2:fmt 1.0))",
    swap={"ib2:fmt": "cal:fmt"})
add("IMPLOK", "(setq io2:*gap* 1.0)",
    "(defun io2:fmt (x) (rtos x))\n(defun c:IMPLOK () (io2:fmt 1.0))",
    swap={"io2:fmt": "cal:fmt"})

# P1 fn: a LAZDIAG hook the local helper calls and the library's does not
add("FNBAD", "(setq fb:*gap* 1.0)",
    "(defun fb:getnum (msg / v)\n"
    "  (setq v (getreal msg))\n  (if lzd:ask (lzd:ask msg v) v))\n"
    "(defun c:FNBAD () (fb:getnum \"n: \"))",
    swap={"fb:getnum": "cal:getnum"})

# a function named in quoted DATA is a call: the dispatch table's qd:fa
# reads a knob the library's helper never does
add("DATAFN", "(setq qd:*k* 2.0)",
    "(defun qd:fa (x) (* x qd:*k*))\n"
    "(defun qd:pick (key x) ((cdr (assoc key '((\"A\" . qd:fa)))) x))\n"
    "(defun c:DATAFN () (qd:pick \"A\" 1.0))",
    swap={"qd:pick": "cal:pick"})

# quiet: entmakex and entmake are one effect
add("ENTMKOK", "(setq em:*gap* 1.0)",
    "(defun em:pt (p) (entmakex (list '(0 . \"POINT\") (cons 10 p))))\n"
    "(defun c:ENTMKOK () (em:pt (getpoint)))",
    swap={"em:pt": "cal:pt"})

# quiet: (mapcar 'setvar ...) is a setvar -- a quoted builtin handed to
# an applier is a call, not a sentinel
add("APPLYOK", "(setq ap:*gap* 1.0)",
    "(defun ap:putvars (vars vals) (mapcar 'setvar vars vals))\n"
    "(defun c:APPLYOK () (ap:putvars '(\"CMDECHO\") '(0)))",
    swap={"ap:putvars": "cal:putvars"})

# P1 sysvar through a WRAPPER: sw:setv hands its first argument to
# setvar, so "MIRRTEXT" handed to it is a sysvar name -- no bare getvar
# of it anywhere in the tree says so
add("SETVW", "(setq sw:*gap* 1.0)",
    "(defun sw:setv (v val) (if (/= nil (getvar v)) (setvar v val)))\n"
    "(defun sw:prep () (sw:setv \"MIRRTEXT\" 0))\n"
    "(defun c:SETVW () (sw:prep))",
    swap={"sw:prep": "cal:prep"})

# P1 sysvar: a hand-typed snapshot list naming a DIMENSION variable
# (SPA's table does) against an expand that does not
add("DIMV", "(setq dv:*sysold* nil)",
    "(defun dv:syssave ()\n  (if (not dv:*sysold*)\n"
    "    (setq dv:*sysold* (mapcar '(lambda (v) (cons v (getvar v)))\n"
    "                              '(\"CMDECHO\" \"DIMTAD\")))))\n"
    "(defun dv:sysrestore ()\n  (foreach p dv:*sysold* (setvar (car p) (cdr p)))\n"
    "  (setq dv:*sysold* nil))\n"
    "(defun c:DIMV () (dv:syssave) (dv:sysrestore))",
    swap={"dv:syssave": "cal:syssave", "dv:sysrestore": "cal:sysrestore"},
    drop_globals=["dv:*sysold*"],
    expand={"(cal:syssave)": ["(cal:syssave '(\"CMDECHO\"))"]})

# the baseline key is the TOOL: a second satellite typing the same CLAYER
# into its own expand over TABLEBAD's helpers is its own finding
FILES["lisp/tablebad/TABLESAT2.lsp"] = tool(
    "TABLESAT2", "(setq t2:*gap* 1.0)",
    "(defun c:TABLESAT2 () (tb:syssave) (tb:sysrestore))")
SPECS["TABLESAT2"] = {
    "src": "lisp/tablebad/TABLESAT2.lsp", "drop_globals": [],
    "swap": {"tb:syssave": "cal:syssave", "tb:sysrestore": "cal:sysrestore"},
    "expand": {"(cal:syssave)": ["(cal:syssave '(\"CMDECHO\" \"CLAYER\"))"]}}

# P0: the mirror refuses (a replace that no longer matches); the twin on
# disk is read in its place
add("MIRRORBAD", "(setq mb:*gap* 1.0)",
    "(defun mb:pair (a) (list a nil))\n(defun c:MIRRORBAD () (mb:pair (getpoint)))",
    swap={"mb:pair": "cal:pair"}, replace=[("no such text", "x")])
DISK = {"shared/parts/MIRRORBAD.lsp": tool(
    "MIRRORBAD", "(setq mb:*gap* 1.0)",
    "(defun c:MIRRORBAD () (cal:pair (getpoint) nil))")}

# the HAND-KEPT twins (LISPLAB's kind): in shared/parts, in no mirror
# entry.  Their swap map is what they lack; their strings are prose, and
# may differ.  HANDHOOK's twin lost a LAZDIAG hook (P5); HANDARITY's
# calls the library's two-argument pair with one (P3)
HAND = ('(defun %(p)s:pad (s w) (while (< (strlen s) w) (setq s (strcat s " "))) s)\n'
        '%(def)s(defun c:%(n)s ()\n'
        '  (if lzd:begin (lzd:begin "%(n)s" "v1"))\n'
        '  (princ (%(p)s:pad "the lisp/ prose" 4))\n'
        '%(call)s  (if lzd:end (lzd:end "%(n)s"))\n'
        '  (princ))\n')
TWIN = ('(defun c:%(n)s ()\n'
        '  (if lzd:begin (lzd:begin "%(n)s" "v1"))\n'
        '  (princ (cal:pad "the library\'s own prose" 4))\n'
        '%(twincall)s%(end)s  (princ))\n')
for name, pre, end, pair in (("HANDOK", "hk", True, False),
                             ("HANDHOOK", "hh", False, False),
                             ("HANDARITY", "ha", True, True)):
    v = {"p": pre, "n": name,
         "def": "(defun %s:pair (a) (list a nil))\n" % pre if pair else "",
         "call": "  (%s:pair (getpoint))\n" % pre if pair else "",
         "twincall": "  (cal:pair (getpoint))\n" if pair else "",
         "end": '  (if lzd:end (lzd:end "%s"))\n' % name if end else ""}
    FILES["lisp/%s/%s.lsp" % (name.lower(), name)] = tool(
        name, "(setq %s:*gap* 1.0)" % pre, HAND % v)
    DISK["shared/parts/%s.lsp" % name] = tool(
        name, "(setq %s:*gap* 1.0)" % pre, TWIN % v)
# ...and one with no lisp/ file at all: nothing to compare it with, but
# its cal: calls are still read
DISK["shared/parts/HANDLONE.lsp"] = tool(
    "HANDLONE", "(setq hl:*gap* 1.0)",
    "(defun c:HANDLONE () (cal:pair (getpoint)))")

def run():
    with tempfile.TemporaryDirectory() as d:
        root = pathlib.Path(d)
        (root / "shared" / "parts").mkdir(parents=True)
        (root / "shared" / "parts" / "CALOFIN-LIB.lsp").write_text(LIB)
        for rel, text in list(FILES.items()) + list(DISK.items()):
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        rows, _, tree = check_tier_parity.audit(root=root, tools=SPECS)
        return rows, tree


def hits(rows, name, rule=None, what=""):
    return [r for r in rows if r["tool"] == name
            and (rule is None or r["rule"] == rule) and what in r["what"]]


print("== check_tier_parity: one fixture per drift ==")
rows, tree = run()
check("the hand twins with a lisp/ file are found as such, and only they",
      sorted(tree.hand) == ["HANDARITY", "HANDHOOK", "HANDOK"], sorted(tree.hand))
check("a hand twin's swap map is the helpers it lacks with a cal: namesake",
      tree.hand["HANDARITY"]["swap"] == {"ha:pad": "cal:pad",
                                         "ha:pair": "cal:pair"},
      tree.hand["HANDARITY"]["swap"])
# P3 reads a twin as code only where its calls can differ from lisp/'s
# by more than a name -- the rest would be parsed for nothing
parsed = {t for t in tree.twin_text if tree.rewrites_calls(t)}
check("only the twins whose calls can differ are read for arity",
      {"ARITYBAD", "ARITYLAM", "SYMFN", "HANDLONE", "HANDOK", "TABLEBAD"}
      <= parsed and not parsed & {"KNOBOK", "INKOK", "SYMOK", "ENTMKOK"},
      sorted(parsed))

for name, rule, what, why in (
        ("KNOBBAD", "P1", "standalone-only global:kb:*back-words*",
         "a knob the local reads and the library hard-codes"),
        ("KNOBBAD", "P2", "knob mentioned less often",
         "...which the twin mentions less often than lisp/ does"),
        ("INKBAD", "P1", "grouped-only env:CalofinInk-*",
         "a profile key the library reads through cal:setting only"),
        ("DATEBAD", "P1", "standalone-only implicit:DIMZIN",
         "rtos reads DIMZIN behind the local helper's back"),
        ("TABLEBAD", "P1", "grouped-only sysvar:CLAYER",
         "the mirror's typed expand snapshots a sysvar the source dropped"),
        ("TABLESAT", "P1", "grouped-only sysvar:OSMODE",
         "...and in a satellite whose helper lives in its sibling"),
        ("SYMBAD", "P1", "standalone-only sym:SB-BACK",
         "a sentinel the caller tests, with no symbols rename"),
        ("KNOBNAME", "P1", "standalone-only global:kn:*eps*",
         "a tool knob is not the library global of the same short name"),
        ("COLLAPSEBAD", "P1", "standalone-only global:cb:*snap*",
         "a collapse that hands over a literal instead of the knob"),
        ("REWRITEBAD", "P1", "standalone-only effect:entmod",
         "a rewrite that loses an effect of the local body"),
        ("ARITYBAD", "P3", "given 1 argument, takes 2",
         "a swap onto a helper of another arity"),
        ("DROPBAD", "P4", "still named in the twin",
         "a dropped table the surviving code still names"),
        ("DROPWRONG", "P4", "never names",
         "a symbols rename onto a name the library never says"),
        ("RESETBAD", "P4", "kept by rs:syssave",
         "a reset of the slot a swapped-away helper kept"),
        # added after review
        ("ARITYLAM", "P3", "given 1 argument, takes 2",
         "a wrong arity inside a quoted '(lambda ...)"),
        ("SYMFN", "P3", "given 1 argument, takes 2",
         "a wrong arity reached through a symbols rename onto a function"),
        ("KNOBREN", "P1", "standalone-only global:kr:*eps*",
         "a knob renamed onto a library global is still the tool's knob"),
        ("KNOBREN", "P4", "a LAZTUNE knob the mirror renames",
         "...and a knob the mirror renames is never read by the build"),
        ("KNOBDROP", "P4", "a LAZTUNE knob the mirror drops",
         "a knob the mirror drops is never read by the build"),
        ("SATSAT", "P1", "standalone-only global:sb:*eps*",
         "a satellite's swapped helper reads its SIBLING's knob"),
        ("STYLEBAD", "P1", "standalone-only global:*odstyle*",
         "a grouped restore that stops reading the saved slot"),
        ("GETVARBAD", "P1", "standalone-only sysvar:INSUNITS",
         "a (getvar \"X\") read in place, in one build only"),
        ("IMPLBAD", "P1", "grouped-only implicit:LUNITS",
         "rtos with its mode left out reads LUNITS"),
        ("IMPLBAD", "P1", "grouped-only implicit:LUPREC",
         "...and with its precision left out, LUPREC"),
        ("FNBAD", "P1", "standalone-only fn:lzd:ask",
         "a LAZDIAG hook only the local helper calls"),
        ("DATAFN", "P1", "standalone-only global:qd:*k*",
         "a function named in quoted data is followed into"),
        ("SETVW", "P1", "standalone-only sysvar:MIRRTEXT",
         "a literal handed to a setvar WRAPPER is a sysvar"),
        ("DIMV", "P1", "standalone-only sysvar:DIMTAD",
         "a dimension variable in a hand-typed snapshot list"),
        ("TABLESAT2", "P1", "grouped-only sysvar:CLAYER",
         "a second satellite's own typed expand"),
        ("MIRRORBAD", "P0", "the mirror refused",
         "the mirror refusing to write the twin"),
        ("HANDHOOK", "P5", "standalone-only code: ( if lzd:end",
         "a hand twin that lost a LAZDIAG hook"),
        ("HANDARITY", "P3", "given 1 argument, takes 2",
         "a wrong arity in a hand twin"),
        ("HANDLONE", "P3", "given 1 argument, takes 2",
         "...and in one with no lisp/ file")):
    check("%s: %s" % (rule, why), hits(rows, name, rule, what),
          [(r["rule"], r["subject"], r["what"]) for r in hits(rows, name)])

for name, why in (
        ("KNOBOK", "the same helper with its words written in"),
        ("INKOK", "a local ink that reads the key through getenv"),
        ("TABLEOK", "an expand list that matches, *sysold* as one slot"),
        ("SYMOK", "the sentinel renamed by the symbols map"),
        ("SYMUNTESTED", "a sentinel nobody tests for"),
        ("COLLAPSEOK", "a collapse that hands over the knob"),
        ("ARITYOK", "the expand that supplies the missing argument"),
        ("DROPOK", "a dropped table renamed onto the library's"),
        ("RESETOK", "the reset renamed onto cal:*sysold*, as POOL does"),
        ("INITONLY", "a slot the twin only initialises at load"),
        # added after review
        ("SATBASE", "the sibling itself, nothing swapped"),
        ("STYLEOK", "a grouped restore that reads the saved slot"),
        ("STATEREAD", "a restore tied to its save by READING the slot"),
        ("IMPLOK", "rtos with the mode left out in both builds"),
        ("ENTMKOK", "entmakex against entmake: one effect"),
        ("APPLYOK", "(mapcar 'setvar ..) is a setvar, not a sentinel"),
        ("HANDOK", "a hand twin that differs in its swaps and prose only")):
    check("quiet: %s" % why, not hits(rows, name),
          [(r["rule"], r["subject"], r["what"]) for r in hits(rows, name)])

print("\n== the baseline: accepted, and stale ==")
bad = hits(rows, "KNOBBAD", "P1")[0]
key = check_tier_parity.key_of(bad)
out = []
nnew, nstale, nold = check_tier_parity.report(
    [r for r in rows if r["tool"] == "KNOBBAD"],
    {key: "fixture", ("lisp/gone/GONE.lsp", "g:x", "standalone-only global:g:*y*"):
     "a site that no longer exists"}, out=out.append)
check("a baselined P1 difference is not a finding", nold == 1 and nnew == 1, out)
check("a baseline line the tree no longer produces is reported stale",
      nstale == 1 and any("GONE.lsp" in ln and "no longer produces" in ln
                          for ln in out), out)
arity = hits(rows, "ARITYBAD", "P3")[0]
nnew, _, _ = check_tier_parity.report(
    [arity], {check_tier_parity.key_of(arity): "no"},
    out=lambda s: None)
check("a P3 finding cannot be baselined", nnew == 1)
for rule, name in (("P4", "KNOBDROP"), ("P5", "HANDHOOK")):
    r = hits(rows, name, rule)[0]
    nnew, _, _ = check_tier_parity.report(
        [r], {check_tier_parity.key_of(r): "no"}, out=lambda s: None)
    check("a %s finding cannot be baselined" % rule, nnew == 1)

# the key is the tool's own file: accepting TABLEBAD's CLAYER must not
# accept TABLESAT2's, though both are tb:syssave's in lisp/tablebad/
first = hits(rows, "TABLEBAD", "P1", "grouped-only sysvar:CLAYER")[0]
second = hits(rows, "TABLESAT2", "P1", "grouped-only sysvar:CLAYER")[0]
check("two tools driving one sibling helper report the same helper",
      first["file"] == second["file"] and first["subject"] == second["subject"],
      (first["file"], second["file"]))
nnew, _, nold = check_tier_parity.report(
    [first, second], {check_tier_parity.key_of(first): "fixture"},
    out=lambda s: None)
check("...but baselining one tool's does not accept the other's",
      nold == 1 and nnew == 1, (nold, nnew))

# a line with no reason is refused, not silently accepted
with tempfile.TemporaryDirectory() as d:
    for text, why in (("a|b|c|\n", "an empty reason"),
                      ("a|b|c\n", "three fields")):
        bl = pathlib.Path(d) / "bl.txt"
        bl.write_text("# header\n" + text)
        try:
            check_tier_parity.load_baseline(bl)
            ok = False
        except check_tier_parity.BaselineError:
            ok = True
        check("a baseline line with %s is an error" % why, ok)
    bl.write_text("# header\nlisp/x/X.lsp|x:y|grouped-only sysvar:Z|why\n")
    check("a whole line loads",
          check_tier_parity.load_baseline(bl) ==
          {("lisp/x/X.lsp", "x:y", "grouped-only sysvar:Z"): "why"})

print("\n== the tree ==")
if os.environ.get("CALOFIN_LISP_ROOT"):
    # the check reads lisp/, the library and the mirror's output whatever
    # the root says: at the shared tier this would be the same run twice
    print("  skip the tree run: CALOFIN_LISP_ROOT is set, and the check "
          "reads both tiers either way")
else:
    real, _, _ = check_tier_parity.audit()
    base = check_tier_parity.load_baseline()
    lines = []
    nnew, nstale, _ = check_tier_parity.report(real, base, out=lines.append)
    check("the tree and tools/tier_parity_baseline.txt agree",
          nnew == 0 and nstale == 0, "\n".join(lines))

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall check_tier_parity rules fire, and the right shapes pass")
