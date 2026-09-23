"""A click on nothing, pinned against what AutoCAD answers.

entsel, nentsel and nentselp answer nil when the click lands on empty
paper -- the same nil Enter gets.  AutoCAD tells the two apart in one
place only: ERRNO, which a missed pick sets to 7 ("Object selection:
pick failed") and Enter never does.  ERRNO is sticky: a hit or a
keyword does not clear it, so a 7 an earlier pick left behind still
reads 7 afterwards -- which is why every pick in this tree that tells
the two apart zeroes it right before it asks.

The VM had no way to script that click.  Each suite that needed one
wrote its own fake -- a function answer that set ERRNO and handed back
Enter -- ten of them, one per file, and a COVERCHECK test that wrapped
entsel itself.  lispvm.MISS is that click now:

  entsel / nentsel / nentselp   MISS answers nil and sets ERRNO 7;
                                Enter (None) answers nil and never sets
                                7; a hit and a keyword leave ERRNO as
                                it was.
  any other input               MISS is refused (lispvm.Unanswerable,
                                which neither *error* nor
                                vl-catch-all-apply can swallow): a
                                click at getpoint or getcorner is a
                                point, at getdist the first of two, and
                                at ssget a window's first corner --
                                there is nothing there to miss.

Two kinds of pin.  An M, P, N or C pin is AutoCAD behaviour, or the
test API, and names the source it relies on.  A V pin is VM POLICY and
says so: what Enter writes to ERRNO.  Autodesk's AutoLISP error-code
table has a code for exactly that event -- 52, "Entity selection: null
response" -- and releases differ on whether they write it
(tools/check_input.py: "what a release writes on a null response
varies").  The VM writes nothing.  That is the conservative reading,
chosen to agree with check_input's STICKY rule: under it a pick that
reads ERRNO without zeroing it first is wrong, while a pick that zeroes
first (M6) is right under it and under 52 alike.  The V pins hold the
VM to that choice; they do not claim AutoCAD makes it, and a later
model that writes 52 on Enter replaces them rather than failing them.

Not modelled, and pinned nowhere: what nentsel hands back for an
object nested in a block (the matrix and the list of containing
inserts are whatever the test scripts); and nentselp given a point,
which asks the drafter nothing and selects at that point -- the VM
refuses it (lispvm.NotModelled) rather than invent a pick.

The file imports nothing the old VM lacks, so it runs against an older
tests/lispvm.py too and names the pins that VM fails.

Run: python3 tests/test_lispvm_input_miss.py
"""

import copy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lispvm  # noqa: E402
from lispvm import VM, Sym, NIL  # noqa: E402

# ---------------------------------------------------------------- sources
ERRNO_DOC = ("AutoCAD ERRNO system variable: it 'displays the number of "
             "the appropriate error code when an AutoLISP function call "
             "causes an error that AutoCAD detects'; the AutoLISP error "
             "codes table: '7  Object selection: pick failed'")
REPO_MISS = ("lisp/pool/POOL.LSP pool:givendone: a click on empty space "
             "'entsel answers it with the same nil as Enter, and ERRNO 7 "
             "is the only difference'; lisp/spa/SPA.LSP spa:readblock: "
             "'entsel answers nil for Enter AND for a click that hit "
             "nothing ... ERRNO 7 tells the two apart'")
REPO_STICKY = ("lisp/lazdiag/LAZDIAG.lsp lzd:begin: 'ERRNO is sticky: "
               "AutoCAD sets it on a failed call and nothing clears it, so "
               "the code a report printed could be a missed pick from a "
               "command an hour ago'")
REPO_LEAVE = ("tools/check_input.py: 'ERRNO is STICKY -- a failing call "
              "sets it and a later answer is not promised to clear it (a "
              "keyword, a point, a pick that hits all leave it be; what a "
              "release writes on a null response varies)'")
REPO_IDIOM = ("lisp/spa/SPA.LSP spa:readblock and every fixed pick in the "
              "tree: '(vl-catch-all-apply 'setvar (list \"ERRNO\" 0))' "
              "right before the entsel, '(= 7 (getvar \"ERRNO\"))' right "
              "after it -- 'It is sticky, so it is cleared before each "
              "pick and read straight after'")
PICKS_REPO = ("tools/check_input.py PICK rule: 'An entsel / nentsel / "
              "nentselp whose nil answer is a DECISION' must zero ERRNO "
              "before the pick and read '(= 7 (getvar \"ERRNO\"))' after "
              "it -- the three pick the same way and miss the same way")
KW_DOC = ("AutoLISP Reference, initget: entsel, nentsel and nentselp "
          "honor its keywords; lispvm _pick: 'AutoCAD hands a typed one "
          "straight back as a string' (wcalst.lsp)")
NENTSELP_DOC = ("AutoLISP Reference, nentselp: '(nentselp [msg] [pt])' -- "
                "pt is a selection point that allows object selection "
                "without user input; tools/check_input.py interactive(): "
                "'(nentselp pt) with a point is a query the drafter never "
                "sees'")
POINT_DOC = ("AutoLISP Reference, getpoint / getcorner / getdist: a click "
             "in the drawing is a point -- getpoint and getcorner answer "
             "with it, getdist takes it as the first of two -- and there "
             "is no object to miss; ssget's default 'Select objects:' "
             "takes a click on nothing as the first corner of a window; "
             "getreal, getint, getkword and getstring take typed input.  "
             "'Object selection: pick failed' belongs to the three "
             "single-object picks")
NO_ERROR = ("REPO_MISS: a miss is an ANSWER -- the loops in POOL, SPA and "
            "the fit pickers read nil and ERRNO and ask again; no "
            "AutoLISP error is raised and *error* never runs")
CONTRACT = "lispvm test API, kept"
ERRNO_52 = ("the AutoLISP error codes table: '52  Entity selection: null "
            "response' -- Enter at a pick has a code of its own, and it is "
            "not 7; routines that catch Enter at entsel with "
            "(= 52 (getvar \"ERRNO\")) rely on a release writing it")
POLICY = ("VM POLICY, not AutoCAD fact.  " + ERRNO_52 + "; "
          "tools/check_input.py: 'what a release writes on a null "
          "response varies'.  The VM writes nothing on Enter -- the "
          "conservative reading, chosen to agree with check_input's "
          "STICKY rule: a pick that zeroes ERRNO first (M6) is right "
          "under it and under 52 alike, one that does not is wrong under "
          "it.  A faithful 52-on-Enter model replaces this pin; it does "
          "not fail it for a tool bug")


# ---------------------------------------------------------------- driving
MISS = getattr(lispvm, 'MISS', None)
UNANSWERABLE = getattr(lispvm, 'Unanswerable', None)
NOT_MODELLED = getattr(lispvm, 'NotModelled', None)


class NoMiss(Exception):
    """The VM under test has no lispvm.MISS -- no way to script a miss."""


def need(x, name):
    if x is None:
        raise NoMiss('this lispvm has no %s' % name)
    return x


def ask(src, script, **sysvars):
    """Evaluate SRC with SCRIPT as the answers; (value, ERRNO after)."""
    vm = VM()
    vm.sysvars.update(sysvars)
    vm.script = list(script)
    r = vm.loads(src)
    return r, vm.sysvars.get('ERRNO'), vm


def line():
    """A VM with one LINE in it; (vm, its ename)."""
    vm = VM()
    vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "0") '
             '\'(10 0.0 0.0 0.0) \'(11 1.0 0.0 0.0)))')
    return vm, vm.entities[-1]


def refused(fn, cls):
    """What FN raised when it was refused with CLS, else None."""
    try:
        fn()
    except Exception as x:              # noqa: BLE001 -- sorted below
        if cls is not None and isinstance(x, cls):
            return x
        raise
    return None


PINS = []


def pin(pid, rule, source):
    def wrap(fn):
        PINS.append((pid, rule, source, fn))
        return fn
    return wrap


# =============================================================== the miss
# Each check takes the pick function's name: the M pins run it on
# entsel, P0 runs every one of them again on nentsel and nentselp, and
# the V pins run the three policy checks on all three picks.
def miss_is_nil(f):
    got = ask('(%s "\\nPick: ")' % f, [need(MISS, 'MISS')])[0]
    return got is NIL, got


def miss_sets_7(f):
    got = [ask('(%s)' % f, [need(MISS, 'MISS')], ERRNO=e)[1]
           for e in (0, 52, 5)]
    return got == [7, 7, 7], got


def enter_not_7(f):
    got = ask('(%s "\\nPick: ")' % f, [None])[:2]
    return (got[0] is NIL and got[1] != 7), got


def enter_keeps_0(f):
    got = ask('(%s "\\nPick: ")' % f, [None])[:2]
    return got == (NIL, 0), got


def enter_keeps_7(f):
    got = ask('(%s)' % f, [None], ERRNO=7)[1]
    return got == 7, got


def hit_keeps_7(f):
    vm, e = line()
    vm.script = [need(MISS, 'MISS'), e]
    r = vm.loads('(list (%s) (%s))' % (f, f))
    got = (r, vm.sysvars.get('ERRNO'))
    return (r[0] is NIL and r[1][0] is e and got[1] == 7), got


def keyword_keeps_7(f):
    got = ask('(progn (%s) (initget "Done") (%s))' % (f, f),
              [need(MISS, 'MISS'), 'D'])[:2]
    return got == ('Done', 7), got


IDIOM = '''
(defun t:pick ( / s out)
  (repeat 4
    (vl-catch-all-apply 'setvar (list "ERRNO" 0))
    (setq s (%s "\\nPick: "))
    (setq out (cons (cond (s 'HIT)
                          ((= 7 (getvar "ERRNO")) 'MISS)
                          (t 'ENTER))
                    out)))
  (reverse out))
'''


def idiom_tells(f):
    vm, e = line()
    vm.loads(IDIOM % f)
    vm.script = [need(MISS, 'MISS'), None, e, need(MISS, 'MISS')]
    got = vm.loads('(t:pick)')
    return got == [Sym('miss'), Sym('enter'), Sym('hit'), Sym('miss')], got


def unzeroed_misreads(f):
    vm, e = line()
    vm.loads((IDIOM % f).replace(
        '(vl-catch-all-apply \'setvar (list "ERRNO" 0))', ''))
    vm.script = [None, need(MISS, 'MISS'), None, e]
    got = vm.loads('(t:pick)')
    return got == [Sym('enter'), Sym('miss'), Sym('miss'), Sym('hit')], got


def on_entsel(check):
    return lambda: check('entsel')


def over(picks, checks):
    """Each CHECK run on each pick in PICKS; ((pick, check, got), ...)
    for the ones that fail."""
    bad = []
    for f in picks:
        for check in checks:
            try:
                ok, got = check(f)
            except Exception as x:          # noqa: BLE001 -- reported
                ok, got = False, '%s: %s' % (type(x).__name__,
                                             str(x).splitlines()[0])
            if not ok:
                bad.append((f, check.__name__, got))
    return not bad, bad


THE_PICKS = ('entsel', 'nentsel', 'nentselp')


def on_every_pick(check):
    return lambda: over(THE_PICKS, (check,))


pin('M1', "entsel answered with MISS returns nil", REPO_MISS)(
    on_entsel(miss_is_nil))
pin('M2', "a miss sets ERRNO 7 -- from 0, and over any code already there",
    ERRNO_DOC + '; ' + REPO_MISS)(on_entsel(miss_sets_7))
pin('M3', "Enter returns nil and does not set 7 -- ERRNO 7 is the one "
    "difference from a miss",
    REPO_MISS + " ('the only difference'); " + ERRNO_52)(
    on_entsel(enter_not_7))
pin('M4', "a hit after a miss returns (ename point) and leaves the 7 "
    "standing", REPO_LEAVE)(on_entsel(hit_keeps_7))
pin('M5', "a keyword typed at a pick after a miss comes back as the "
    "keyword, and the 7 stays", KW_DOC + '; ' + REPO_LEAVE)(
    on_entsel(keyword_keeps_7))
pin('M6', "setvar is the one clear: zeroed before each pick, ERRNO tells "
    "a miss from Enter every time round -- Enter straight after a miss "
    "included", REPO_IDIOM + '; ' + ERRNO_52)(on_entsel(idiom_tells))


@pin('M7', "ERRNO outlives the command: a miss in one run still reads 7 "
     "in the next", REPO_STICKY)
def _m7():
    vm = VM()
    vm.loads('(defun c:one () (entsel) (princ))')
    vm.loads('(defun c:two () (getvar "ERRNO"))')
    vm.run('c:one', [need(MISS, 'MISS')])
    got = vm.run('c:two', [])
    return got == 7, got


# ======================================================= the VM's policy
# What Enter writes to ERRNO is not settled across releases (POLICY).
# These pin the VM's declared choice -- nothing -- over all three picks,
# and say so in every line they print.
pin('V1', "VM POLICY -- Enter writes nothing to ERRNO: 0 stays 0",
    POLICY)(on_every_pick(enter_keeps_0))
pin('V2', "VM POLICY -- Enter leaves a 7 an earlier miss left standing",
    REPO_STICKY + '; ' + POLICY)(on_every_pick(enter_keeps_7))
pin('V3', "VM POLICY -- so, without the zero, the Enter after a miss "
    "reads as a second miss: the sticky 7 is what the zero is for",
    REPO_STICKY + '; ' + POLICY)(on_every_pick(unzeroed_misreads))


# ============================================================ the picks
@pin('P0', "nentsel and nentselp miss, take Enter and keep ERRNO exactly "
     "as entsel does (M1-M6 over each)", PICKS_REPO + '; ' + ERRNO_DOC)
def _p0():
    return over(('nentsel', 'nentselp'),
                (miss_is_nil, miss_sets_7, enter_not_7, hit_keeps_7,
                 keyword_keeps_7, idiom_tells))


@pin('P1', "nentsel and nentselp pick as entsel does: a hit is "
     "(ename point), a scripted list is handed back whole",
     PICKS_REPO + '; ' + NENTSELP_DOC)
def _p1():
    vm, e = line()
    nested = [e, [1.0, 2.0, 0.0], [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0],
                                   [0.0, 0.0, 1.0], [0.0, 0.0, 0.0]],
              []]
    vm.script = [e, e, nested]
    got = vm.loads('(list (nentsel "\\nPick: ") (nentselp "\\nPick: ") '
                   '(nentsel))')
    return (got[0] == [e, [0.0, 0.0, 0.0]] and got[1] == got[0]
            and got[2] == nested), got


@pin('P2', "nentselp given a point asks nothing -- the VM refuses it as "
     "unmodelled, and never answers it from the script", NENTSELP_DOC)
def _p2():
    need(NOT_MODELLED, 'NotModelled')
    vm = VM()
    vm.script = [need(MISS, 'MISS')]
    x = refused(lambda: vm.loads('(nentselp \'(1.0 2.0 0.0))'), NOT_MODELLED)
    y = refused(lambda: vm.loads('(nentselp "\\nPick: " \'(1.0 2.0 0.0))'),
                NOT_MODELLED)
    return (x is not None and y is not None and len(vm.script) == 1
            and not vm.prompts), (x, y, vm.script)


@pin('P3', "a miss is an answer, not an error: with *error* in force it "
     "never runs, and vl-catch-all-apply hands back nil", NO_ERROR)
def _p3():
    vm = VM()
    vm.handle_errors = True
    vm.loads('(defun c:t ( / *error* r) (defun *error* (m) '
             '(setq t:*ran* m)) (setq r (list (entsel) (vl-catch-all-apply '
             '\'entsel nil))) (setq t:*r* r) (princ))')
    vm.run('c:t', [need(MISS, 'MISS'), need(MISS, 'MISS')])
    got = (vm.globals.get(Sym('t:*ran*')), vm.globals.get(Sym('t:*r*')),
           vm.handled_errors)
    return got == (NIL, [NIL, NIL], []), got


# ==================================================== nothing there to miss
REFUSED_AT = [
    ('getpoint', '(getpoint "\\nPoint: ")'),
    ('getcorner', '(getcorner \'(0.0 0.0 0.0) "\\nCorner: ")'),
    ('getdist', '(getdist "\\nDistance: ")'),
    ('getreal', '(getreal "\\nReal: ")'),
    ('getint', '(getint "\\nWhole number: ")'),
    ('getkword', '(progn (initget "Yes No") (getkword "\\nYes/No: "))'),
    ('getstring', '(getstring "\\nName: ")'),
    ('ssget', '(ssget)'),
]


@pin('N1', "MISS at an input that cannot miss is refused -- a click there "
     "is a point, a window corner or nothing typed", POINT_DOC)
def _n1():
    need(UNANSWERABLE, 'Unanswerable')
    bad = []
    for name, src in REFUSED_AT:
        vm = VM()
        vm.script = [need(MISS, 'MISS')]
        try:
            r = vm.loads(src)
            bad.append((name, 'answered %r' % (r,)))
        except Exception as x:          # noqa: BLE001 -- sorted below
            if not isinstance(x, UNANSWERABLE):
                bad.append((name, '%s: %s' % (type(x).__name__,
                                              str(x).splitlines()[0])))
    return not bad, bad


@pin('N2', "...and the refusal is the test's, not the routine's: neither "
     "vl-catch-all-apply nor *error* can swallow it", CONTRACT)
def _n2():
    need(UNANSWERABLE, 'Unanswerable')
    vm = VM()
    vm.handle_errors = True
    vm.loads('(defun c:t ( / *error*) (defun *error* (m) (setq t:*ran* m)) '
             '(vl-catch-all-apply \'getpoint (list "\\nPoint: ")) (princ))')
    x = refused(lambda: vm.run('c:t', [need(MISS, 'MISS')]), UNANSWERABLE)
    got = (x is not None, vm.globals.get(Sym('t:*ran*')))
    return got == (True, NIL), got


@pin('N3', "the refusal names the prompt and the input it came to -- "
     "getreal by its own name, not the getdist it shares code with",
     CONTRACT)
def _n3():
    need(UNANSWERABLE, 'Unanswerable')
    got = []
    for name, src, label in (('getpoint', '(getpoint "\\nBase point: ")',
                              'Base point'),
                             ('getreal', '(getreal "\\nScale factor: ")',
                              'Scale factor')):
        vm = VM()
        vm.script = [need(MISS, 'MISS')]
        msg = str(refused(lambda: vm.loads(src), UNANSWERABLE))
        got.append((name, 'the %s prompt' % name in msg and label in msg,
                    msg.splitlines()[0]))
    return all(ok for _n, ok, _m in got), got


# ============================================================ the test API
@pin('C1', "a scripted function may answer MISS -- at a pick it is a miss, "
     "anywhere else it is refused like a plain MISS", CONTRACT)
def _c1():
    need(UNANSWERABLE, 'Unanswerable')
    late = need(MISS, 'MISS')
    r, errno, _vm = ask('(entsel)', [lambda vm: late])
    vm = VM()
    vm.script = [lambda vm: late]
    x = refused(lambda: vm.loads('(getpoint)'), UNANSWERABLE)
    return (r is NIL and errno == 7 and x is not None), (r, errno, x)


@pin('C2', "the prompt log keeps the miss as MISS, apart from Enter's "
     "None, and LASTPROMPT is the pick's", CONTRACT)
def _c2():
    _r, _e, vm = ask('(list (entsel "\\nFirst: ") (entsel "\\nSecond: "))',
                     [need(MISS, 'MISS'), None])
    got = (vm.prompts, vm.loads('(getvar "LASTPROMPT")'))
    return (vm.prompts[0][1] is MISS and vm.prompts[1][1] is None
            and got[1] == 'Second: '), got


@pin('C3', "lispvm.MISS is one object: a copied or deep-copied script "
     "still misses", CONTRACT)
def _c3():
    m = need(MISS, 'MISS')
    script = copy.deepcopy([None, [m]])[1] + copy.copy([m])
    got = [ask('(entsel)', [x])[1] for x in script]
    return (all(x is m for x in script) and got == [7, 7]), (script, got)


@pin('C4', "the fakes it replaces still work: a function answer that sets "
     "ERRNO itself and hands back Enter",
     CONTRACT + " -- and it rests on the V policy: a VM that wrote 52 on "
     "Enter would write it over the fake's 7")
def _c4():
    def fake(vm):
        vm.sysvars['ERRNO'] = 7
        return None
    r, errno, _vm = ask('(entsel)', [fake])
    return (r is NIL and errno == 7), (r, errno)


def main():
    fails = []
    for pid, rule, source, fn in PINS:
        try:
            ok, detail = fn()
        except Exception as x:          # a pin must report, never crash
            ok, detail = False, 'raised %s: %s' % (
                type(x).__name__, str(x).splitlines()[0])
        print('  %-4s %-4s %s' % ('ok' if ok else 'FAIL', pid, rule))
        if not ok:
            print('            got: %r' % (detail,))
            print('            source: %s' % source)
            fails.append(pid)
    if fails:
        print('\n%d of %d input-miss pins FAILED: %s'
              % (len(fails), len(PINS), ' '.join(fails)))
        sys.exit(1)
    print('\nALL %d INPUT-MISS PINS PASSED' % len(PINS))


if __name__ == '__main__':
    main()
