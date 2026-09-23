"""What a drafter can TYPE, pinned against what AutoCAD reads.

The spacebar is Enter at every AutoCAD input but one.  (getstring T ...)
takes a line with spaces in it and ends at Enter; everywhere else --
getpoint, getcorner, getdist, getreal, getint, getkword, getangle,
getorient, entsel, nentsel, nentselp and a getstring with no cr flag --
a space ENDS the answer.  So '44 1/2' typed at a click-or-type length
prompt is two answers, 44 to this prompt and 1/2 to the next, and a
scripted '44 1/2' there is an answer no drafter can give.  The VM took
it whole, and a test that scripted one proved a reading no keyboard
reaches: SPA's '1524 MM' and the step tools' '24 1/8' both passed.

  a spaced string   is refused, lispvm.Untypeable (an Unanswerable, so
                    neither *error* nor vl-catch-all-apply swallows it),
                    naming what AutoCAD would read.  VM(spacebar='split')
                    or LISPVM_SPACEBAR=split does what AutoCAD does
                    instead -- the first word here, the rest to the
                    prompts after -- and lispvm.keys('44 1/2') spells
                    that split in a script: ['44', '1/2'].
  a typed number    at getdist, getreal and getint is the number AutoCAD
                    reads from it: getdist in the current LUNITS (1/8,
                    2', 4'-6-1/2" and .5 in architectural units), getint a
                    whole number and getreal a decimal one -- initget
                    128 or not, since arbitrary input is only what no
                    other reading took.
  initget           is spent by the next input it speaks to.  A keyword
                    list made for one prompt no longer answers at the
                    prompt after it.

Pins are S (the spacebar), K (the split and keys), D (typed numbers), I
(initget spent), C (the test API) and V.  A V pin is VM POLICY and says
so: where AutoCAD's behaviour is not settled the VM either refuses
(lispvm.NotModelled -- a feet spelling at getdist in decimal units, a
fraction at getreal) or keeps what it did, and the pin holds it to that
choice without claiming AutoCAD makes it.

Not modelled, and pinned nowhere: a TAB in a scripted string (passes as
it is); what getangle and getorient return for an angle (refused as
NotModelled -- the tree calls neither); getint's -32768..32767 range;
and initget bits 1 + 128 together, where the reference says Enter
returns "" rather than being refused.

The file imports nothing the old VM lacks, so it runs against an older
tests/lispvm.py too and names the pins that VM fails.

Run: python3 tests/test_lispvm_input_space.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lispvm  # noqa: E402
from lispvm import VM, Sym, NIL, LispError  # noqa: E402

# ---------------------------------------------------------------- sources
GETSTRING_DOC = ("AutoLISP Reference, getstring: '(getstring [cr] [msg])' "
                 "-- cr: 'If supplied and not nil, this argument indicates "
                 "that users can include blanks in their input string "
                 "(and must terminate the string by pressing Enter). "
                 "Otherwise, the input string is terminated by entering "
                 "a space or pressing Enter.'")
REPO_SPACE = ("lisp/oasis/OASIS.lsp, the ruler block every length prompt "
              "carries: 'the prompt is a getpoint, where the spacebar is "
              "Enter: 44 1/2 is two answers there, 44 to this question "
              "and 1/2 to the next'; lisp/dimstamp/DIMSTAMP.lsp: 'At a "
              "getpoint a space is Enter, so 4'-6 1/2\" arrives as 4'-6 "
              "and then 1/2\"'; lisp/perp_points/README.md: 'the spacebar "
              "is Enter at this prompt, so 44 1/2 would enter 44 here and "
              "hand the 1/2 to the next point'")
REPO_SPA = ("tests/test_spa_runtime.py: \"'1524 mm' typed with the space: "
            "getdist returns at the space with the NUMBER 1524, and the "
            "'MM' is typed into whatever comes next\"")
ENTER_LINE = ("AutoLISP Reference, getstring: with cr the user 'must "
              "terminate the string by pressing Enter' -- a line break "
              "is Enter, at a whole-line prompt as at every other")
UNANSWERABLE = ("lispvm.Unanswerable (tests/test_lispvm_input_miss.py N2): "
                "a scripted answer no drafter can give is the TEST's "
                "error, and no *error* handler or vl-catch-all-apply in "
                "the code under test may take it for its own")
GETDIST_DOC = ("AutoLISP Reference, getdist: 'The user can also specify a "
               "distance by entering a number in the AutoCAD current "
               "distance units format.  Although the current distance "
               "units format might be in feet and inches (architectural), "
               "the getdist function always returns the distance as a "
               "real.'")
DISTOF_DOC = ("AutoLISP Reference, distof: modes 1 scientific, 2 decimal, "
              "3 engineering, 4 architectural, 5 fractional; the VM's "
              "distof reads each mode's spellings (tests/"
              "test_lispvm_values.py) -- 4'-6-1/2\", 4'6, 1/8 in 4, "
              "17-1/2 and 1/2 in 5")
REPO_HALF = ("D1's own reading: 52.5 is inches in architectural units, so "
             "the same decimal without its leading zero (.5) or with a "
             "bare point (5.) is the same count of inches -- no units "
             "format is stricter about a decimal than decimal units "
             "(D2 reads .5); lisp/cornerstp/CORNERSTP.lsp:1468 tells the "
             "drafter at a length prompt they 'can still give half an "
             "inch as 0-1/2 or .5'")
REPO_TYPED = ("lisp/perp_points/README.md: a length typed at the ruler "
              "prompt is 'read as DIMSTAMP reads -- 44, 44.5, 44-1/2, "
              "4'4.5, 4'-4-1/2\"'; tests/test_steps_ruler.py: 2' and "
              "10-3/4 'must read as their numbers'")
GETINT_DOC = ("AutoLISP Reference, getint: 'Pauses for user input of an "
              "integer, and returns that integer'; AutoCAD refuses "
              "anything else at it with 'Requires an integer value.' "
              "and asks again")
GETREAL_DOC = ("AutoLISP Reference, getreal: 'Pauses for user input of a "
               "real number, and returns that real number'")
BIT128_DOC = ("AutoLISP Reference, initget bit 128: 'Allow arbitrary "
              "input as if it is a keyword, first honoring any other "
              "control bits and listed keywords' -- text a number "
              "reading takes is not arbitrary")
BITS_DOC = ("AutoLISP Reference, initget: bit 2 'Disallow zero input', "
            "bit 4 'Disallow negative values'")
INITGET_DOC = ("AutoLISP Reference, initget: 'The control bits and "
               "keywords established by initget apply only to the next "
               "user-input function call.  They are discarded immediately "
               "afterward.'")
HONOURED_DOC = ("AutoLISP Reference, initget: it 'establishes various "
                "options for use by the next entsel, getangle, getcorner, "
                "getdist, getint, getkword, getorient, getpoint, getreal, "
                "nentsel, or nentselp function call'")
REPO_IDIOM = ("STANDARDS.md's ask-helper skeletons: tool:askkw calls "
              "(initget ...) immediately before its getkword, and "
              "tool:askpoint re-arms it inside its re-ask loop, before "
              "every getpoint")
POLICY_GETSTRING = ("VM POLICY, not AutoCAD fact.  getstring is not in "
                    "the reference's list of inputs initget speaks to "
                    "(" + HONOURED_DOC + "), and whether it discards a "
                    "pending initget anyway is not documented.  The VM "
                    "leaves it standing -- what it always did.  STANDARDS"
                    ".md: 'a getstring cannot be armed with initget'")
POLICY_UNSETTLED = ("VM POLICY, not AutoCAD fact.  Whether AutoCAD reads "
                    "a feet or fraction spelling at a getdist in decimal "
                    "units, a fraction at a getreal, or an exponent "
                    "outside scientific units is not settled, so the VM "
                    "refuses (lispvm.NotModelled) rather than decide the "
                    "test with a guess")
CONTRACT = "lispvm test API, kept"

# ---------------------------------------------------------------- driving
UNTYPEABLE = getattr(lispvm, 'Untypeable', None)
NOT_MODELLED = getattr(lispvm, 'NotModelled', None)
KEYS = getattr(lispvm, 'keys', None)
MISS = getattr(lispvm, 'MISS', None)


class Missing(Exception):
    """The VM under test lacks what this pin needs."""


def need(x, name):
    if x is None:
        raise Missing('this lispvm has no %s' % name)
    return x


def vm_(spacebar='strict', **sysvars):
    """A VM in SPACEBAR mode -- strict unless a pin says otherwise, so a
    LISPVM_SPACEBAR left set in the shell cannot move a pin (K8 is the
    one that reads it, on purpose)."""
    vm = VM()
    vm.spacebar = spacebar
    vm.sysvars.update(sysvars)
    return vm


def ask(src, script, spacebar='strict', **sysvars):
    """Evaluate SRC with SCRIPT as the answers: (value, vm)."""
    vm = vm_(spacebar, **sysvars)
    vm.script = list(script)
    return vm.loads(src), vm


def refused(fn, cls):
    """What FN raised when it was refused with CLS, else None.  Anything
    else it raises propagates."""
    try:
        fn()
    except Exception as x:              # noqa: BLE001 -- sorted below
        if cls is not None and isinstance(x, cls):
            return x
        raise
    return None


def outcome(src, script, **kw):
    """('ok', value) or (exception class name, first line)."""
    try:
        return 'ok', ask(src, script, **kw)[0]
    except Exception as x:              # noqa: BLE001 -- reported
        return type(x).__name__, str(x).splitlines()[0]


def line():
    """A VM with one LINE in it; (vm, its ename)."""
    vm = VM()
    vm.loads('(entmake (list \'(0 . "LINE") \'(8 . "0") '
             '\'(10 0.0 0.0 0.0) \'(11 1.0 0.0 0.0)))')
    return vm, vm.entities[-1]


PINS = []


def pin(pid, rule, source):
    def wrap(fn):
        PINS.append((pid, rule, source, fn))
        return fn
    return wrap


# ============================================================ the spacebar
#: every input the spacebar ends, as a form that asks it once.  The
#: keyword inputs are given a keyword list the spaced answer's first word
#: is in, so a VM that took the first word would ANSWER, and one that took
#: the whole string would refuse it as no keyword: only a refusal naming
#: the spacebar passes.
SPACE_ENDS = [
    ('getpoint', '(progn (initget 128) (getpoint "\\nPoint: "))', '44 1/2'),
    ('getcorner', '(progn (initget "Back") '
                  '(getcorner \'(0.0 0.0 0.0) "\\nCorner: "))', 'Back 2'),
    ('getdist', '(progn (initget 128) (getdist "\\nLength: "))', '44 1/2'),
    ('getreal', '(progn (initget 128) (getreal "\\nFactor: "))', '1.5 2'),
    ('getint', '(progn (initget 128) (getint "\\nCount: "))', '4 5'),
    ('getkword', '(progn (initget "Yes No") (getkword "\\nYes/No: "))',
     'Yes please'),
    ('getangle', '(progn (initget "Back") (getangle "\\nAngle: "))',
     'Back 45'),
    ('getorient', '(progn (initget "Back") (getorient "\\nAngle: "))',
     'Back 45'),
    ('entsel', '(progn (initget "Done") (entsel "\\nPick: "))', 'Done now'),
    ('nentsel', '(progn (initget "Done") (nentsel "\\nPick: "))',
     'Done now'),
    ('nentselp', '(progn (initget "Done") (nentselp "\\nPick: "))',
     'Done now'),
    ('getstring', '(getstring "\\nName: ")', 'Pool 1'),
    ('getstring nil', '(getstring nil "\\nName: ")', 'Pool 1'),
    ('getstring bare', '(getstring)', 'Pool 1'),
]


@pin('S1', "a spaced string is refused UNTYPEABLE at every input the "
     "spacebar ends -- the eleven initget inputs and a getstring with no "
     "cr flag, however it is called",
     GETSTRING_DOC + '; ' + REPO_SPACE + '; ' + REPO_SPA)
def _s1():
    need(UNTYPEABLE, 'Untypeable')
    bad = []
    for name, src, typed in SPACE_ENDS:
        vm = vm_()
        vm.script = [typed]
        try:
            r = vm.loads(src)
            bad.append((name, 'answered %r' % (r,)))
        except Exception as x:          # noqa: BLE001 -- sorted below
            if not (isinstance(x, UNTYPEABLE) and 'UNTYPEABLE' in str(x)):
                bad.append((name, '%s: %s' % (type(x).__name__,
                                              str(x).splitlines()[0])))
    return not bad, bad


@pin('S2', "(getstring T ...) takes a spaced line whole -- with a prompt, "
     "bare, and with any non-nil cr, a string included", GETSTRING_DOC)
def _s2():
    got = [ask(src, ['Pool 1 of 3'])[0]
           for src in ('(getstring T "\\nName: ")', '(getstring T)',
                       '(getstring 1 "\\nName: ")',
                       '(getstring "" "\\nName: ")')]
    return got == ['Pool 1 of 3'] * 4, got


@pin('S3', "a space that only ENDS the answer is the Enter that ends it: "
     "'44 ' is 44, and a lone space is Enter", GETSTRING_DOC)
def _s3():
    got = [outcome('(getint "\\nCount: ")', ['44 ']),
           outcome('(getpoint "\\nPoint: ")', [' ']),
           outcome('(getstring "\\nName: ")', [' ']),
           outcome('(getstring "\\nName: ")', ['Pool ']),
           outcome('(progn (initget "Yes No") (getkword))', ['Yes '])]
    return got == [('ok', 44), ('ok', NIL), ('ok', ''), ('ok', 'Pool'),
                   ('ok', 'Yes')], got


@pin('S4', "a space with nothing before it is an Enter of its own: ' 12' "
     "and a doubled space are refused as two answers", GETSTRING_DOC)
def _s4():
    need(UNTYPEABLE, 'Untypeable')
    got = []
    for src, typed in (('(getint "\\nCount: ")', ' 12'),
                       ('(getstring "\\nName: ")', 'a  b'),
                       ('(progn (initget 128) (getpoint))', '  ')):
        vm = vm_()
        vm.script = [typed]
        got.append(refused(lambda: vm.loads(src), UNTYPEABLE) is not None)
    return got == [True] * 3, got


@pin('S5', "a line break is Enter at every prompt, (getstring T ...) "
     "included: 'a\\nb' is two answers there, 'abc\\n' is abc",
     ENTER_LINE)
def _s5():
    need(UNTYPEABLE, 'Untypeable')
    vm = vm_()
    vm.script = ['Pool 1\nPool 2']
    x = refused(lambda: vm.loads('(getstring T "\\nName: ")'), UNTYPEABLE)
    y = outcome('(getstring T "\\nName: ")', ['Pool 1\n'])
    z = outcome('(getstring T "\\nName: ")', ['Pool 1\r\n'])
    return (x is not None and y == ('ok', 'Pool 1')
            and z == ('ok', 'Pool 1')), (x, y, z)


@pin('S6', "the refusal is the test's, not the routine's: an "
     "Unanswerable, and neither vl-catch-all-apply nor *error* can "
     "swallow it", UNANSWERABLE)
def _s6():
    need(UNTYPEABLE, 'Untypeable')
    vm = vm_()
    vm.handle_errors = True
    vm.loads('(defun c:t ( / *error*) (defun *error* (m) (setq t:*ran* m)) '
             '(vl-catch-all-apply \'getdist (list "\\nLength: ")) (princ))')
    x = refused(lambda: vm.run('c:t', ['44 1/2']), UNTYPEABLE)
    got = (x is not None,
           isinstance(x, getattr(lispvm, 'Unanswerable', ())),
           not isinstance(x, LispError), vm.globals.get(Sym('t:*ran*')))
    return got == (True, True, True, NIL), got


@pin('S7', "the refusal names the input, the prompt, what AutoCAD reads "
     "there and what it hands on -- and how to spell it instead",
     GETSTRING_DOC + '; ' + CONTRACT)
def _s7():
    need(UNTYPEABLE, 'Untypeable')
    vm = vm_()
    vm.script = ['44 1/2']
    msg = str(refused(lambda: vm.loads('(getdist "\\nTread 2: ")'),
                      UNTYPEABLE))
    want = ('UNTYPEABLE', 'getdist', 'Tread 2', "'44'", "['1/2']",
            'keys(', '44-1/2')
    return all(w in msg for w in want), msg.splitlines()[0]


@pin('S8', "a string with no break in it, and any answer that is not a "
     "string -- a number, a point, an ename, Enter, a miss -- passes as "
     "it did", CONTRACT)
def _s8():
    vm, e = line()
    vm.script = ['Back', 12.5, [1.0, 2.0, 0.0], None, e, need(MISS, 'MISS')]
    got = vm.loads('(list (progn (initget "Back") (getpoint)) (getdist) '
                   '(getpoint) (getpoint) (car (entsel)) (entsel))')
    return got == ['Back', 12.5, [1.0, 2.0, 0.0], NIL, e, NIL], got


@pin('S9', "the refusal says Enter for a space that is an Enter, and "
     "offers a length's spellings only where a length is typed",
     CONTRACT)
def _s9():
    need(UNTYPEABLE, 'Untypeable')
    msgs = {}
    for name, src, typed in (
            ('getint', '(getint "\\nCount: ")', ' 12'),
            ('getkword', '(progn (initget "Yes No") (getkword))', 'Yes no'),
            ('getpoint', '(progn (initget 128) (getpoint))', '44 1/2')):
        vm = vm_()
        vm.script = [typed]
        msgs[name] = str(refused(lambda: vm.loads(src), UNTYPEABLE))
    got = ('reads Enter as this answer' in msgs['getint'],
           "['12']" in msgs['getint'],
           'None' not in msgs['getint'].splitlines()[0],
           '44-1/2' not in msgs['getkword'],
           '1524mm' not in msgs['getint'],
           '44-1/2' in msgs['getpoint'])
    return all(got), (got, {k: v.splitlines()[0] for k, v in msgs.items()})


# ============================================================== the split
@pin('K1', "split: the first word answers this prompt and the rest the "
     "prompts after it -- 44 1/2 at a length prompt is 44, then 1/2",
     REPO_SPACE)
def _k1():
    got = ask('(list (progn (initget 128) (getpoint "\\nLength: ")) '
              '(progn (initget 128) (getpoint "\\nNext: ")))',
              ['44 1/2'], spacebar='split')[0]
    return got == ['44', '1/2'], got


@pin('K2', "split: a doubled space is an Enter between the words, and a "
     "getstring takes it as \"\"", GETSTRING_DOC)
def _k2():
    got = ask('(list (getstring) (getstring) (getstring))', ['a  b'],
              spacebar='split')[0]
    return got == ['a', '', 'b'], got


@pin('K3', "split: the spaced '1524 MM' at a getdist is the number 1524 "
     "there and MM typed at the next prompt", REPO_SPA)
def _k3():
    got = ask('(list (progn (initget 128) (getdist "\\nDiameter: ")) '
              '(progn (initget 128) (getdist "\\nNext: ")))',
              ['1524 MM'], spacebar='split')[0]
    return got == [1524.0, 'MM'], got


@pin('K4', "split: the prompt log says what each prompt got, not the "
     "spaced string", CONTRACT)
def _k4():
    _r, vm = ask('(list (getstring "\\nFirst: ") (getstring "\\nSecond: "))',
                 ['a b'], spacebar='split')
    return vm.prompts == [('\nFirst: ', 'a'), ('\nSecond: ', 'b')], \
        vm.prompts


@pin('K5', "split: what the words leave over when the command ends is a "
     "script left over -- a failure, never a pass", CONTRACT)
def _k5():
    vm = vm_('split')
    vm.loads('(defun c:one () (getstring "\\nName: ") (princ))')
    try:
        vm.run('c:one', ['Pool 1'])
        return False, 'ran clean'
    except LispError as x:
        msg = str(x).splitlines()[0]
        return 'left over' in msg and "'1'" in msg, msg


@pin('K6', "keys spells the split: '44 1/2', ' 12', 'a  b', '44 ', "
     "'1\\n2'", CONTRACT)
def _k6():
    k = need(KEYS, 'keys')
    got = [k('44 1/2'), k(' 12'), k('a  b'), k('44 '), k('1\n2'),
           k('Pool')]
    return got == [['44', '1/2'], [None, '12'], ['a', None, 'b'], ['44'],
                   ['1', '2'], ['Pool']], got


@pin('K7', "a script spelled with keys runs the same under strict and "
     "split", CONTRACT)
def _k7():
    k = need(KEYS, 'keys')
    src = ('(list (progn (initget 128) (getpoint)) '
           '(progn (initget 128) (getpoint)) (getstring))')
    got = [ask(src, k('24 1/8') + ['x'], spacebar=m)[0]
           for m in ('strict', 'split')]
    return got == [['24', '1/8', 'x']] * 2, got


@pin('K8', "LISPVM_SPACEBAR sets the mode for every VM made after it, "
     "VM(spacebar=...) for one, and a mode that is neither strict nor "
     "split is refused -- there is no setting that takes a spaced "
     "string whole", CONTRACT)
def _k8():
    was = os.environ.get('LISPVM_SPACEBAR')
    try:
        os.environ['LISPVM_SPACEBAR'] = 'split'
        env = VM().spacebar
        os.environ.pop('LISPVM_SPACEBAR')
        default = VM().spacebar
        arg = VM(spacebar='split').spacebar
        try:
            VM(spacebar='off')
            off = 'accepted'
        except ValueError:
            off = 'refused'
    except Exception as x:              # noqa: BLE001 -- reported
        return False, '%s: %s' % (type(x).__name__, x)
    finally:
        if was is None:
            os.environ.pop('LISPVM_SPACEBAR', None)
        else:
            os.environ['LISPVM_SPACEBAR'] = was
    got = (env, default, arg, off)
    return got == ('split', 'strict', 'split', 'refused'), got


# ========================================================= typed numbers
@pin('D1', "getdist in architectural units reads 1/8, 2', 4'6, "
     "4'-6-1/2\", 52.5, .5 and 5. as distances, and returns a real",
     GETDIST_DOC + '; ' + DISTOF_DOC + '; ' + REPO_TYPED + '; '
     + REPO_HALF)
def _d1():
    typed = ['1/8', "2'", "4'6", '4\'-6-1/2"', '52.5', '10-3/4',
             '.5', '5.']
    got = [ask('(getdist "\\nLength: ")', [t], LUNITS=4)[0] for t in typed]
    return got == [0.125, 24.0, 54.0, 54.5, 52.5, 10.75, 0.5, 5.0], got


@pin('D2', "getdist in decimal units reads a decimal number: 12 is the "
     "real 12.0", GETDIST_DOC)
def _d2():
    typed = ['12', '12.5', '-3', '.5']
    got = [ask('(getdist "\\nLength: ")', [t], LUNITS=2)[0] for t in typed]
    return (got == [12.0, 12.5, -3.0, 0.5]
            and all(isinstance(g, float) for g in got)), got


@pin('D3', "getdist in fractional units reads 17-1/2 and 1/2",
     GETDIST_DOC + '; ' + DISTOF_DOC)
def _d3():
    got = [ask('(getdist "\\nLength: ")', [t], LUNITS=5)[0]
           for t in ('17-1/2', '1/2', '17')]
    return got == [17.5, 0.5, 17.0], got


@pin('D4', "a number typed where initget 128 allows arbitrary input is "
     "still the number -- at getdist, getreal and getint", BIT128_DOC)
def _d4():
    got = [ask('(progn (initget 128) (getdist))', ["2'"], LUNITS=4)[0],
           ask('(progn (initget 128) (getdist))', ['12'])[0],
           ask('(progn (initget 128) (getreal))', ['1.5'])[0],
           ask('(progn (initget 128) (getint))', ['7'])[0]]
    return got == [24.0, 12.0, 1.5, 7], got


@pin('D5', "initget bits 2 and 4 refuse a typed 0 and a typed negative "
     "as they refuse the numbers themselves", BITS_DOC)
def _d5():
    got = [outcome('(progn (initget 2) (getdist))', ['0']),
           outcome('(progn (initget 4) (getdist))', ["-2'"], LUNITS=4),
           outcome('(progn (initget 6) (getint))', ['-1']),
           outcome('(progn (initget 130) (getreal))', ['0.0'])]
    want = ('zero not allowed', 'negative not allowed',
            'negative not allowed', 'zero not allowed')
    # the refusal must be the BIT's: a 'not among' refusal is the VM
    # failing to read the number at all
    return all(g[0] == 'LispError' and w in g[1]
               for g, w in zip(got, want)), got


@pin('D6', "getint reads a typed whole number as an integer, and refuses "
     "12.5 and 1/2 -- which come back as the text under initget 128",
     GETINT_DOC + '; ' + BIT128_DOC)
def _d6():
    got = [outcome('(getint)', ['12']), outcome('(getint)', ['-4']),
           outcome('(getint)', ['12.5'])[0], outcome('(getint)', ['1/2'])[0],
           outcome('(progn (initget 128) (getint))', ['12.5'])]
    return got == [('ok', 12), ('ok', -4), 'LispError', 'LispError',
                   ('ok', '12.5')], got


@pin('D7', "getreal reads a typed decimal number", GETREAL_DOC)
def _d7():
    got = [ask('(getreal)', [t])[0] for t in ('1.5', '2', '-0.25')]
    return got == [1.5, 2.0, -0.25], got


@pin('D8', "text that is no number and no keyword is what it always was: "
     "back as the text under initget 128, refused without it, and a "
     "keyword still wins", BIT128_DOC + '; ' + CONTRACT)
def _d8():
    got = [outcome('(progn (initget 128) (getdist))', ['2134mm']),
           outcome('(getdist)', ['2134mm'])[0],
           outcome('(progn (initget 128 "Back") (getdist))', ['B']),
           outcome('(progn (initget 128) (getint))', ['Pt.17'])]
    return got == [('ok', '2134mm'), 'LispError', ('ok', 'Back'),
                   ('ok', 'Pt.17')], got


@pin('D9', "a decimal number is inches in engineering, architectural and "
     "fractional units in every spelling of one -- .5, 5., -.5 -- "
     "initget 128 or not, and bit 4 refuses the negative one",
     GETDIST_DOC + '; ' + REPO_HALF + '; ' + BIT128_DOC + '; ' + BITS_DOC)
def _d9():
    got, bad = [], []
    for lu in (3, 4, 5):
        for typed, want in (('.5', 0.5), ('5.', 5.0), ('-.5', -0.5),
                            ('+.25', 0.25)):
            for src in ('(getdist)', '(progn (initget 128) (getdist))'):
                g = outcome(src, [typed], LUNITS=lu)
                if g != ('ok', want):
                    bad.append((lu, typed, src, g))
    g = outcome('(progn (initget 4) (getdist))', ['-.5'], LUNITS=4)
    if not (g[0] == 'LispError' and 'negative not allowed' in g[1]):
        bad.append(('bit 4', g))
    return not bad, bad


@pin('V1', "VM POLICY -- a spelling of another units format is refused as "
     "NotModelled: 2' and 1/2 at getdist in decimal units, 1/2 and 2' at "
     "a getreal, 1e2 at getdist in architectural units",
     POLICY_UNSETTLED)
def _v1():
    need(NOT_MODELLED, 'NotModelled')
    bad = []
    for src, typed, lu in (('(getdist)', "2'", 2), ('(getdist)', '1/2', 2),
                           ('(progn (initget 128) (getdist))', "2'", 2),
                           ('(getreal)', '1/2', 4), ('(getreal)', "2'", 4),
                           ('(getdist)', '1e2', 4)):
        vm = vm_(LUNITS=lu)
        vm.script = [typed]
        try:
            r = vm.loads(src)
            bad.append((src, typed, 'answered %r' % (r,)))
        except Exception as x:          # noqa: BLE001 -- sorted below
            if not isinstance(x, NOT_MODELLED):
                bad.append((src, typed, '%s: %s' % (
                    type(x).__name__, str(x).splitlines()[0])))
    return not bad, bad


# ========================================================= initget spent
@pin('I1', "a keyword list made for one prompt does not answer at the "
     "next: Back typed at the second getpoint is refused",
     INITGET_DOC)
def _i1():
    got = outcome('(list (progn (initget "Back") (getpoint)) (getpoint))',
                  [[1.0, 2.0, 0.0], 'Back'])
    return got[0] == 'LispError' and 'not among' in got[1], got


@pin('I2', "the bits are spent too: after (initget 7) is spent, Enter, "
     "zero and a negative all answer the next input",
     INITGET_DOC + '; ' + BITS_DOC)
def _i2():
    src = '(list (progn (initget 7) (getint)) (getint) (getint) (getint))'
    got = outcome(src, [5, None, 0, -3])
    return got == ('ok', [5, NIL, 0, -3]), got


@pin('I3', "it is spent however its input was answered -- Enter, a "
     "keyword or a click", INITGET_DOC)
def _i3():
    got = [outcome('(list (progn (initget "Back") (getpoint)) (getkword))',
                   [first, 'Back'])
           for first in (None, 'Back', [1.0, 2.0, 0.0])]
    return all(g[0] == 'LispError' and 'not among' in g[1]
               for g in got), got


@pin('I4', "every input initget speaks to spends it -- the eleven the "
     "reference names", HONOURED_DOC + '; ' + INITGET_DOC)
def _i4():
    firsts = {'getcorner': "(getcorner '(0.0 0.0 0.0))"}
    bad = []
    for f in ('entsel', 'getangle', 'getcorner', 'getdist', 'getint',
              'getkword', 'getorient', 'getpoint', 'getreal', 'nentsel',
              'nentselp'):
        first = firsts.get(f, '(%s)' % f)
        vm = vm_()
        vm.script = [None, 'Xyzzy']
        # the first input must RUN and take its Enter: a VM with no
        # such builtin refuses here, and that proves nothing about spend
        try:
            r = vm.loads('(progn (initget "Xyzzy") %s)' % first)
        except Exception as x:          # noqa: BLE001 -- reported
            bad.append((f, 'first: %s: %s' % (type(x).__name__,
                                             str(x).splitlines()[0])))
            continue
        if r is not NIL:
            bad.append((f, 'first answered %r' % (r,)))
            continue
        # and the keyword typed at the next input is refused AS a
        # keyword the (now empty) list does not hold
        try:
            r = vm.loads('(getkword)')
            bad.append((f, 'second answered %r' % (r,)))
        except LispError as x:
            if 'not among' not in str(x):
                bad.append((f, 'second: ' + str(x).splitlines()[0]))
    return not bad, bad


@pin('I5', "what runs between initget and its input does not spend it -- "
     "only an input does", INITGET_DOC)
def _i5():
    got = outcome('(progn (initget "Xyzzy") (setq a 1) (princ "x") '
                  '(strcat "a" "b") (getvar "ERRNO") (getkword))', ['X'])
    return got == ('ok', 'Xyzzy'), got


@pin('I6', "the idiom runs as it always did: a fresh initget before "
     "every ask, round a re-ask loop", REPO_IDIOM + '; ' + INITGET_DOC)
def _i6():
    got = outcome('(progn (setq n 0 out nil) '
                  '(while (< n 3) (initget "Back Done") '
                  '(setq out (cons (getpoint "\\nPoint: ") out) '
                  'n (1+ n))) (reverse out))',
                  ['Back', [1.0, 2.0, 0.0], 'D'])
    return got == ('ok', ['Back', [1.0, 2.0, 0.0], 'Done']), got


@pin('I7', "bits 1 and 128 together: Enter is the empty string, not a "
     "refusal and not nil -- at getkword, getdist, getint, getreal and "
     "getpoint alike; bit 1 alone still refuses Enter",
     "AutoLISP Reference, initget: bit 128 'takes precedence over bit 0; "
     "if bits 7 and 0 are set and the user presses Enter, a null string "
     "is returned'; UPADOVER.lsp (initget 129), SPA.LSP (initget (+ 7 128))")
def _i7():
    got = [outcome('(progn (initget 129 "Back") (getkword))', [None]),
           outcome('(progn (initget 129) (getdist))', [None]),
           outcome('(progn (initget (+ 7 128)) (getint))', [None]),
           outcome('(progn (initget 129) (getreal))', [None]),
           outcome('(progn (initget 129) (getpoint))', [None])]
    alone = outcome('(progn (initget 1) (getdist))', [None])
    return (all(g == ('ok', '') for g in got)
            and alone[0] == 'LispError'
            and 'Enter not allowed' in alone[1]), (got, alone)


@pin('I8', "bit 1 alone refuses Enter at getpoint and getcorner too -- "
     "the VM used to hand back nil there, so a (initget 1) (getpoint) "
     "loop's nil branch ran in a test and never in AutoCAD",
     "AutoLISP Reference, initget: bit 1 'Prevents the user from "
     "responding to the request by entering only Enter', listed for "
     "getpoint and getcorner alike")
def _i8():
    pt = outcome('(progn (initget 1) (getpoint))', [None])
    co = outcome('(progn (initget 1) (getcorner (list 0.0 0.0)))', [None])
    bare = outcome('(getpoint)', [None])
    return (pt[0] == 'LispError' and 'Enter not allowed' in pt[1]
            and co[0] == 'LispError' and 'Enter not allowed' in co[1]
            and bare == ('ok', None)), (pt, co, bare)


@pin('V2', "VM POLICY -- getstring neither honours initget nor spends "
     "it: a keyword list made before a getstring still answers the "
     "input after it", POLICY_GETSTRING)
def _v2():
    got = outcome('(list (progn (initget "Xyzzy") (getstring)) '
                  '(getkword))', ['Xyzzy', 'X'])
    return got == ('ok', ['Xyzzy', 'Xyzzy']), got


# ============================================================ the test API
@pin('C1', "a scripted function's answer is cut the way a plain one is -- "
     "refused under strict, split under split", CONTRACT)
def _c1():
    need(UNTYPEABLE, 'Untypeable')
    late = lambda vm: '44 1/2'           # noqa: E731
    vm = vm_()
    vm.script = [late]
    x = refused(lambda: vm.loads('(getstring "\\nName: ")'), UNTYPEABLE)
    got = ask('(list (getstring) (getstring))', [late], spacebar='split')[0]
    return x is not None and got == ['44', '1/2'], (x, got)


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
        print('\n%d of %d input-space pins FAILED: %s'
              % (len(fails), len(PINS), ' '.join(fails)))
        sys.exit(1)
    print('\nALL %d INPUT-SPACE PINS PASSED' % len(PINS))


if __name__ == '__main__':
    main()
