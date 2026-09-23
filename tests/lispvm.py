"""A minimal AutoLISP interpreter, good enough to EXECUTE POOL.LSP.

Not a toy for show: tests/test_pool_runtime.py loads the real POOL.LSP
into this VM and drives c:POOL end-to-end with scripted answers, so a
change that would die at the AutoCAD command line (wrong arity, unbound
function, nil where a list was expected, an (if ...) with too many
arguments) dies here first.

Deliberately AutoLISP-strict where it matters:
  * (if test then [else]) -- MORE than three arguments is an error,
    exactly like AutoLISP at evaluation time;
  * symbols are case-insensitive; unbound symbols evaluate to nil;
  * dynamic scoping: a function's body sees its caller's locals;
  * integer / is integer division; floats propagate;
  * *error* (with vm.handle_errors on) runs in the error mode its
    command put in force: after *push-error-using-command* it sees
    globals only, without one a bare (command) in it is refused, and a
    handler that throws is a failure, not a handled error (see
    VM.__init__ and tests/test_lispvm_errmode.py);
  * rtos, distof, vl-sort, entmod and entdel answer only what AutoCAD
    promises: rtos follows DIMZIN and defaults to LUNITS / LUPREC (a
    whole foot is 15' at DIMZIN 0), distof reads back every spelling
    rtos writes and defaults to LUNITS too, vl-sort drops EQ duplicates
    only (two equal integers, never two equal reals or lists), and
    entmod / entdel refuse -- nil, nothing changed -- an entity on a
    LOCKED layer (tests/test_lispvm_values.py).  angtos is NOT in that
    list: it still ignores DIMZIN, AUNITS and AUPREC.

Interaction is scripted: every input -- getpoint, getdist, getint,
getreal, getkword, getstring, entsel and the rest -- pops its answer
from a queue.  A number is the number, a list a point, None is Enter,
and a string is what the drafter TYPES: a keyword where the initget
list has it, else the number getdist / getreal / getint read from it
(below), else the text itself under initget 128, else refused.
Running out of script, or ending with script left over, is a test
failure -- the prompt log tells you where.

MISS is a click on empty paper.  At an entsel, nentsel or nentselp it
answers nil -- the nil Enter gets -- and sets ERRNO 7, AutoCAD's "pick
failed" and the only thing that tells the two apart.  ERRNO is sticky:
a hit and a keyword leave it as it was, and only a setvar clears it.
Enter leaves it too, and THAT is VM policy rather than AutoCAD fact:
AutoCAD's code for it is 52, "Entity selection: null response", which
releases differ on writing, so the VM writes nothing -- the reading
under which a pick that reads ERRNO without zeroing it first is wrong
(tests/test_lispvm_input_miss.py, the V pins).  Scripted anywhere else
MISS is refused with Unanswerable: a click at getpoint is a point, and
there is nothing there to miss.

The spacebar is Enter at every input but (getstring T ...), so a
scripted string with a space in it anywhere else -- '44 1/2' at a
length prompt -- is two answers in AutoCAD and none a drafter can give
as one.  It is refused with Untypeable (an Unanswerable, message
UNTYPEABLE); a line break is Enter everywhere and is refused the same
way.  VM(spacebar='split') or LISPVM_SPACEBAR=split cuts it as AutoCAD
does instead, the first word to this prompt and the rest to the next,
and keys('44 1/2') spells that cut in a script.  Text typed at getdist
is a distance in the current LUNITS (2', 1/8, 4'-6-1/2" and .5 in
architectural), at getint a whole number and at getreal a decimal one,
initget 128 or not; a spelling of some other units format is refused
as NotModelled.  And an initget is spent by the next input it speaks
to (HONOURS_INITGET): its keywords do not answer at the prompt after
(tests/test_lispvm_input_space.py).

So vm.run raises three things that are NOT LispErrors -- Unanswerable,
its Untypeable, and NotModelled, all AssertionErrors -- and a harness
that drives the VM and sorts what comes out by catching LispError has
to catch those too: they say the SCRIPT reached a prompt it cannot
answer there, which in a replay is a run that has left its transcript.
"""

import functools
import math
import os
import re


def _where(msg, vm):
    """MSG with the call chain and the last prompts answered appended --
    what a failure message needs to say where in the run it happened."""
    if vm is not None and getattr(vm, 'calls', None):
        msg += "\n  in: " + " > ".join(vm.calls[-8:])
    if vm is not None and vm.prompts:
        msg += "\n  last prompts:\n    " + "\n    ".join(
            f"{p!r} -> {a!r}" for p, a in vm.prompts[-8:])
    return msg


class LispError(Exception):
    def __init__(self, msg, vm=None):
        super().__init__(_where(msg, vm))


class Unanswerable(AssertionError):
    """A scripted answer no drafter can give at the prompt it reached --
    a MISS at a getpoint, where a click is always a point.  The TEST is
    wrong, not the routine, so this is not a LispError: no *error*
    handler and no vl-catch-all-apply in the code under test can take it
    for a failure of its own and carry on."""

    def __init__(self, msg, vm=None):
        super().__init__(_where(msg, vm))


class NotModelled(AssertionError):
    """An input the VM will not invent an answer for, because it has no
    model of what AutoCAD would hand back -- nentselp given a point, which
    selects there without asking.  Not a LispError, for Unanswerable's
    reason: a routine that caught it would run on an answer made up."""

    def __init__(self, msg, vm=None):
        super().__init__(_where(msg, vm))


class Untypeable(Unanswerable):
    """A scripted STRING no drafter can type at the prompt it reached:
    one with a space in it at a prompt the spacebar ends -- every input
    but (getstring T ...) -- or a line break anywhere.  AutoCAD reads the
    first word as this answer and hands the rest to the next prompt, so
    the one answer the script means never arrives.  Its message starts
    UNTYPEABLE.  An Unanswerable, not a LispError, for that class's
    reason: a routine that wraps its prompt in vl-catch-all-apply to
    catch Esc would otherwise take the refusal for an Esc and carry on.
    VM(spacebar='split') -- or LISPVM_SPACEBAR=split -- does what AutoCAD
    does instead, and lispvm.keys spells that split in a script."""


class CaughtError:
    """What vl-catch-all-apply hands back instead of throwing.  It is
    truthy, so (if (vl-catch-all-apply ...) ...) takes the then-branch
    on a failure -- which is why callers must test it with
    vl-catch-all-error-p and not for nil."""
    __slots__ = ('msg',)

    def __init__(self, msg):
        self.msg = msg

    def __repr__(self):
        return f"<caught {self.msg!r}>"


class HandlerDeath(LispError):
    """The *error* handler itself threw.  AutoCAD abandons it at that
    form: every line after it is skipped -- the restores, the undo
    close, the pop, the LAZDIAG report -- and what the drafter sees is
    a raw error line.  run() raises this instead of returning as if
    the handler had done its job, and the VM runs the handler once per
    error: an outer frame never runs it again.  The error that killed
    it is __cause__; its first line is also in vm.handler_deaths."""


class HandlerAbort(HandlerDeath):
    """An error AutoCAD raises past vl-catch-all-apply: the whole
    handler is abandoned ("INTERNAL error in FAIL / message lost, reset
    to top"), so nothing after it runs -- not the undo close, not the
    pop, not the report."""


class Sym(str):
    """Interned, lower-cased symbol."""


class Dot:
    """A dotted pair (a . b) whose cdr is an atom."""
    __slots__ = ('a', 'b')

    def __init__(self, a, b):
        self.a, self.b = a, b

    def __repr__(self):
        return f"({self.a!r} . {self.b!r})"

    def __eq__(self, other):
        return isinstance(other, Dot) and \
            self.a == other.a and self.b == other.b

    def __hash__(self):
        return hash((self.a, self.b))


class Ent:
    """An entity name."""
    _n = 0

    def __init__(self):
        Ent._n += 1
        self.id = Ent._n

    @property
    def handle(self):
        """AutoCAD hands every entity a hex handle and entget always
        carries it as group 5, so routines that label a finding by
        handle have something to print."""
        return format(self.id, 'X')

    def __repr__(self):
        return f"<Entity {self.id}>"


NIL = None
T = Sym("t")


class _Miss:
    """The one MISS: a click that landed on nothing.  One object, kept
    one through copy, deepcopy and pickle, so `v is MISS` is the test."""
    __slots__ = ()

    def __repr__(self):
        return 'MISS'

    def __copy__(self):
        return self

    def __deepcopy__(self, memo):
        return self

    def __reduce__(self):
        return 'MISS'


MISS = _Miss()

#: the inputs a click can miss at: the single-object picks.  AutoCAD's
#: ERRNO 7 is "Object selection: pick failed", and these are the three
#: calls that select one object and hand back nil when the click hits
#: none.  Everywhere else a click is a point (getpoint and getcorner
#: answer with it, getdist takes it as the first of two), a window's
#: first corner (the default ssget) or no answer at all.  One exception
#: is not modelled because nothing in the tree reaches it: a
#: single-selection ssget -- (ssget "_+.:E:S") and the like -- comes
#: back nil from a click on nothing.  The tree calls ssget with "_X"
#: and "_I" only; whoever adds the first ":S" or "+." site widens this
#: for it (the kind pop_script is given there would have to say which
#: ssget it is).
PICKS = frozenset({'entsel', 'nentsel', 'nentselp'})

#: the inputs initget speaks to -- the AutoLISP Reference's own list
#: (initget: 'establishes various options for use by the next entsel,
#: getangle, getcorner, getdist, getint, getkword, getorient, getpoint,
#: getreal, nentsel, or nentselp function call') -- and so the calls
#: that SPEND it: 'The control bits and keywords established by initget
#: apply only to the next user-input function call.  They are discarded
#: immediately afterward.'  getstring, ssget and getfiled are not in
#: it: whether they spend a pending initget is not documented, so they
#: leave it as they find it (VM policy, tests/test_lispvm_input_space.py)
HONOURS_INITGET = frozenset({
    'entsel', 'getangle', 'getcorner', 'getdist', 'getint', 'getkword',
    'getorient', 'getpoint', 'getreal', 'nentsel', 'nentselp'})

#: what the spacebar may do in a scripted string: 'strict' refuses a
#: string it would cut (Untypeable), 'split' cuts it as AutoCAD does --
#: the first word to this prompt, the rest to the next.  There is no
#: third setting that takes a spaced string whole: that is the kindness
#: this rule exists to take away.
SPACEBAR_MODES = ('strict', 'split')


def _cut(text, breaks):
    out, cur = [], ''
    for ch in text.replace('\r\n', '\n').replace('\r', '\n'):
        if ch in breaks:
            out.append(cur if cur else None)
            cur = ''
        else:
            cur += ch
    if cur:
        out.append(cur)
    return out


def keys(text):
    """TEXT as the answers AutoCAD reads from it at any prompt but a
    (getstring T ...): the spacebar is Enter there, so '44 1/2' is
    ['44', '1/2'] -- 44 to this prompt, 1/2 to the next.  A space with
    nothing before it is an Enter of its own (None): ' 12' is
    [None, '12'] and 'a  b' is ['a', None, 'b'].  A space that ends the
    text is only the Enter that ends it: '44 ' is ['44'].  A line break
    is Enter at every prompt and cuts the same way.

    Splice it into a script where a test means to show what the real
    keystrokes do:  vm.run('c:X', [..., *keys('24 1/8'), ...])."""
    return _cut(text, ' \n')


def _typed(vm, v, prompt, kind, line=False):
    """V as the prompt really receives it.  Only a string can hold a
    space; any other answer, and a string with no break in it, passes
    as it is.  LINE is (getstring T ...)'s cr flag: a space is text
    there and only a line break ends the answer."""
    if not isinstance(v, str):
        return v
    breaks = '\n' if line else ' \n'
    if not any(c in breaks for c in v.replace('\r', '\n')):
        return v
    toks = _cut(v, breaks)
    first, rest = (toks[0], toks[1:]) if toks else (None, [])
    if rest and vm.spacebar != 'split':
        what = "a line break is Enter" if line else "the spacebar is Enter"

        def said(x):
            return 'Enter' if x is None else repr(x)
        split = f"spell the split with lispvm.keys({v!r})"
        if line:
            fix = "Script each line as an answer of its own"
        elif kind in ('getpoint', 'getdist'):
            fix = (f"Script what the drafter can type -- a dashed fraction "
                   f"(44-1/2), the unit touching the number (1524mm) -- "
                   f"{split}, or ask with (getstring T ...)")
        elif kind in ('getreal', 'getint'):
            fix = f"Script the one number the drafter types, or {split}"
        elif kind == 'getstring':
            fix = (f"Script one word, {split}, or -- where the answer is "
                   f"a line of text -- ask with (getstring T ...)")
        else:
            fix = (f"Script one word -- a keyword has no space in it -- "
                   f"or {split}")
        raise Untypeable(
            f"UNTYPEABLE at the {kind} prompt {prompt!r}: {v!r} -- {what} "
            f"here, so AutoCAD reads {said(first)} as this answer and "
            f"hands [{', '.join(said(r) for r in rest)}] to the prompts "
            f"after it.  {fix}", vm)
    if rest:
        vm.script[0:0] = rest
    if vm.prompts and vm.prompts[-1][1] is v:
        # the log says what THIS prompt got; the rest logs at its own
        vm.prompts[-1] = (vm.prompts[-1][0], first)
    return first


def tokenize(src):
    # strip ; comments (strings are handled inline)
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            buf = []
            while j < n and src[j] != '"':
                if src[j] == '\\' and j + 1 < n:
                    esc = src[j + 1]
                    buf.append({'n': '\n', 't': '\t', 'r': '\r',
                                '\\': '\\', '"': '"', 'e': '\x1b'}.get(esc, esc))
                    j += 2
                else:
                    buf.append(src[j])
                    j += 1
            out.append(('str', ''.join(buf)))
            i = j + 1
        elif c == ';':
            while i < n and src[i] != '\n':
                i += 1
        elif c in '()':
            out.append((c, c))
            i += 1
        elif c == "'":
            out.append(("'", "'"))
            i += 1
        elif c in ' \t\r\n':
            i += 1
        else:
            j = i
            while j < n and src[j] not in " \t\r\n()';\"":
                j += 1
            out.append(('atom', src[i:j]))
            i = j
    return out


def atom(tok):
    t = tok.lower()
    if t == 'nil':
        return NIL
    if re.fullmatch(r'[+-]?\d+', t):
        return int(t)
    if re.fullmatch(r'[+-]?(\d+\.\d*|\.\d+|\d+)(e[+-]?\d+)?', t) and \
       ('.' in t or 'e' in t):
        try:
            return float(t)
        except ValueError:
            pass
    return Sym(t)


def parse(tokens, k=0):
    kind, val = tokens[k]
    if kind == "'":
        node, k = parse(tokens, k + 1)
        return [Sym('quote'), node], k
    if kind == '(':
        k += 1
        items = []
        while tokens[k][0] != ')':
            if tokens[k] == ('atom', '.') and items:
                tail, k = parse(tokens, k + 1)
                if tokens[k][0] != ')':
                    raise LispError("bad dotted pair")
                if isinstance(tail, list):
                    return items + tail, k + 1
                if len(items) == 1:
                    return Dot(items[0], tail), k + 1
                return items[:-1] + [Dot(items[-1], tail)], k + 1
            node, k = parse(tokens, k)
            items.append(node)
        return items, k + 1
    if kind == ')':
        raise LispError("unexpected )")
    if kind == 'str':
        return val, k + 1
    return atom(val), k + 1


def _parse_all(src):
    tokens = tokenize(src)
    out, k = [], 0
    while k < len(tokens):
        node, k = parse(tokens, k)
        out.append(node)
    return out


#: Parsed trees of the larger sources, keyed by the source TEXT and never
#: by path, so an edited file cannot be served a stale tree.  The suites
#: that sweep the roster build a fresh VM per case and load the same
#: files into each: test_undo_off parsed 155 MB of text out of 170
#: distinct sources, and parsing was most of its wall clock.  Only text
#: of _PARSE_CACHE_MIN characters or more is kept -- the one-off
#: (setq ...) snippets the tests build are all different strings, and
#: holding them would cost memory for no hit.
_PARSED = {}
_PARSE_CACHE_MIN = 4096


def _copy_tree(x):
    """A fresh copy of a parse tree, exactly as a fresh parse would have
    built it.  Lists must be new because running code gets its hands on
    parse-tree lists -- sf_quote returns them, ssdel mutates lists in
    place, entmake keeps the inner (10 x y z) lists it was handed -- and
    a Dot must be new because its car can be one of them.  Strings,
    floats and ints must be new objects too, because eq compares them
    with `is`: a fresh parse gives every literal its own object, so the
    same literal read by two loads of one source is two objects, and
    (eq) between them is nil.  Only Syms, which compare by value, and
    the objects CPython itself shares (small ints, one-character and
    empty strings -- shared by a fresh parse as well) are handed on."""
    t = type(x)
    if t is list:
        return [_copy_tree(y) for y in x]
    if t is Sym:
        return x
    if t is Dot:
        return Dot(_copy_tree(x.a), _copy_tree(x.b))
    if t is str:
        return x[:1] + x[1:]
    if t is float:
        return x * 1.0
    if t is int:
        return x + 0
    return x


def parse_all(src):
    """Every top-level form in SRC.  A large source is parsed once per
    process and handed out as a fresh copy each time after that, so no
    two callers ever share a list (tests/test_lispvm_cache.py)."""
    if len(src) < _PARSE_CACHE_MIN:
        return _parse_all(src)
    tree = _PARSED.get(src)
    if tree is None:
        # get-then-store, not setdefault: setdefault's argument would be
        # evaluated -- a full parse -- on every hit as well
        tree = _PARSED[src] = _parse_all(src)
    return [_copy_tree(f) for f in tree]


def truthy(v):
    """AutoLISP has exactly one false value, and '() IS it: an empty list
    reads as nil, so (if '() ...) takes the else-branch and (null '())
    is T.  The VM builds empty lists as Python [], which is not the NIL
    object, so the test lives here rather than at every call site."""
    return v is not NIL and not (isinstance(v, list) and not v)


class VM:
    def __init__(self, spacebar=None):
        self.globals = {}
        self.stack = []          # list of dicts (dynamic scope frames)
        self.calls = []          # defun names currently on the stack
        self._entmakex = False   # entmake returning an ename, not a list
        self._blockdef = None    # name of the block being defined, if any
        self.blocks = {}         # block name -> its definition entities
        self.blockhdr = {}       # block name -> its BLOCK header alist
        self.blockents = {}      # block name -> (n, [Ent ... ENDBLK]), the
                                 # definition as a walkable run; see
                                 # _block_chain
        self.blockof = {}        # Ent -> (block name, index in that run)
        self.script = []
        self.prompts = []        # (prompt, answer) log
        self.printed = []        # everything princ'd, in order
        self.commands = []       # every (command ...) call
        self.dimstyle_log = []   # every dim style made current, in order
        self.entities = []       # Ent -> alist, in creation order
        self.entdata = {}
        self.deleted = set()
        self.lastprompt = ''     # what AutoCAD's LASTPROMPT would hold
        self.pickfirst = None    # the implied selection sssetfirst
                                 # left for the next command's "_I"
        self.initget_kws = ""
        self.initget_bits = 0
        # an initget is spent by the next input that honours it
        # (HONOURS_INITGET): True from the initget until that input
        # starts, and the input after that finds it cleared
        self.initget_live = False
        # what a space in a scripted string does (SPACEBAR_MODES)
        self.spacebar = (spacebar or os.environ.get('LISPVM_SPACEBAR')
                         or 'strict')
        if self.spacebar not in SPACEBAR_MODES:
            raise ValueError(f"spacebar {self.spacebar!r}: one of "
                             f"{SPACEBAR_MODES} (LISPVM_SPACEBAR)")
        self.sysvars = {
            'CMDECHO': 1, 'OSMODE': 4133, 'CLAYER': '0', 'LUNITS': 2,
            # acad.dwt's; (rtos v) with no precision reads it
            'LUPREC': 4,
            'LTSCALE': 1.0, 'UNDOCTL': 5, 'MIRRTEXT': 1,
            'DIMSTYLE': 'STANDARD', 'INSUNITS': 1, 'ATTREQ': 1,
            'ATTDIA': 0, 'CMDACTIVE': 0,
            # CDATE is YYYYMMDD.HHMMSS.  A fixed one, not the wall
            # clock: a routine that stamps the date into its output
            # must produce the same output on every run, or the test
            # asserting on it would pass today and fail tomorrow.
            'CDATE': 20260821.143000, 'DATE': 2461274.5,
            # Every variable the tree reads or writes, at AutoCAD's own
            # default.  An unseeded name used to read as 0, which hid a
            # class of bug (a text height scaled by a DIMSCALE of 0) and
            # made every cancel test see "changed" settings that were
            # only ever the VM inventing a value; a name not listed here
            # now reads as nil, exactly as AutoCAD answers an unknown one.
            'PDMODE': 0, 'VIEWSIZE': 100.0, 'PLINETYPE': 2, 'PICKFIRST': 1,
            'PICKBOX': 3,
            # The angle three, which SQUAREUP zeroes round its ROTATE:
            # decimal degrees, zero east, counterclockwise.  They belong
            # here for the reason the paragraph above gives -- the tree
            # writes them, so a run that puts them back has to have
            # something to put back.  Left unseeded, getvar answered nil
            # and a save that SKIPS a nil (the library's) left them
            # written while a save that keeps one restored nil over the
            # value: two tiers, two answers, from one file.
            'AUNITS': 0, 'ANGBASE': 0.0, 'ANGDIR': 0,
            # ERRNO exists from the moment AutoCAD starts, at 0, and a
            # routine that clears it before an entsel (the only way to
            # tell a missed click from Enter) has to have something to
            # clear.  Left unseeded, getvar answered nil and the clear
            # read as a sysvar the run had created and never put back.
            # PLINEWID is 0.0 in a new drawing; PLINE runs at it.
            'ERRNO': 0, 'PLINEWID': 0.0,
            # the command line: "" between commands, the command's
            # name while run() drives one (see run)
            'CMDNAMES': '',
            'CANNOSCALEVALUE': 1.0, 'DIMSCALE': 1.0, 'FILEDIA': 1,
            'DIMTXT': 0.18, 'TEMPPREFIX': 'C:\\Temp\\',
            'CECOLOR': 'BYLAYER', 'CELTYPE': 'BYLAYER', 'CELWEIGHT': -1,
            'CELTSCALE': 1.0, 'CTAB': 'Model', 'TEXTSTYLE': 'STANDARD',
            'SCREENSIZE': [1920.0, 1080.0], 'PEDITACCEPT': 0,
            'VIEWCTR': [0.0, 0.0, 0.0], 'DIMASSOC': 2, 'TEXTSIZE': 0.2,
            'FILLETRAD': 0.0, 'TRIMMODE': 1, 'DIMTMOVE': 0,
            'DIMLUNIT': 2, 'DIMFRAC': 0, 'DIMDEC': 4, 'DIMZIN': 0,
            'DIMPOST': '', 'DIMTAD': 0, 'DIMASZ': 0.18, 'DIMEXE': 0.18,
            'DIMEXO': 0.0625, 'DIMGAP': 0.09, 'DIMTIX': 0, 'DIMTOFL': 0,
            'DIMATFIT': 3, 'DIMLAYER': '.', 'CVPORT': 2, 'TILEMODE': 1,
        }
        # *error* dispatch is OPT-IN (vm.handle_errors = True): with it
        # on, a LispError raised outside vl-catch-all-apply runs the
        # *error* in force at the failing code -- and then aborts the
        # command, which run() reports as a normal return.  Off, the
        # error propagates as it always has, so the suites that assert
        # on a raised LispError keep their footing.
        #
        # The handler runs in the ERROR MODE the command put in force,
        # as AutoCAD runs it (tests/test_lispvm_errmode.py pins each
        # rule, with its source):
        #   default  the stack is live, so the handler reads its
        #            command's locals; command-s drives a command, and
        #            a bare (command) is refused ("Cannot invoke
        #            (command) from *error* without prior call to
        #            (*push-error-using-command*)").
        #   pushed   AutoCAD resets the evaluator BEFORE *error* runs:
        #            the handler is still the one in force at the
        #            failure (a local (defun *error* ...) included), but
        #            it runs with every frame gone -- a command local
        #            reads its GLOBAL value, a helper the command
        #            defined in its arglist is undefined, a setq writes
        #            the global.  (command) is allowed; command-s is
        #            refused past vl-catch-all-apply (HandlerAbort).
        # The VM used to run every handler with the frames live, which
        # is how SPA's and ten other handlers passed here and died in
        # AutoCAD.  An error INSIDE the handler ends it where it stands
        # and run() raises HandlerDeath: the handler is not run again.
        self.handle_errors = False
        self.handled_errors = []   # the messages *error* was handed
        self.handler_deaths = []   # first line of each error that killed one
        self._catch_depth = 0      # inside vl-catch-all-apply: no dispatch
        self._in_handler = False   # a throw inside *error* is not re-handled
        # *push-error-using-command* stacks an error-handling mode for
        # the document; *pop-error-mode* takes it off.  Both are bound
        # so the (if *push-error-using-command* ...) guards see them,
        # and the depth is what a test asserts on: a command that pushes
        # and pops only from its handler leaves 1 behind after a clean
        # run, which is the defect five tools carried until v3.2.
        self.error_mode_depth = 0
        # pops with nothing pushed.  run() fails a command that makes
        # one, as it fails one that leaves an undo group open: the pop
        # takes off a mode somebody else pushed, or none at all
        self.error_mode_underflow = 0
        self._underflow_mark = 0   # the count when the current run() began
        self.globals[Sym('*push-error-using-command*')] = T
        self.globals[Sym('*pop-error-mode*')] = T
        #: the AutoCAD environment strings getenv/setenv read and write.
        #: Per-VM and empty, never the process environment: a test that
        #: read the real one would pass or fail by what the machine
        #: running it had exported.
        self.env = {}
        #: Files written by (open ... "w") / write-line, as path -> the
        #: text written.  In memory for the same reason env is: a suite
        #: that wrote a real DXF into the tree would leave litter behind
        #: and would pass or fail by what the running user may write.
        #: lzd:dxfwrite is asserted against this.
        self.files = {}
        self.dirs = set()          # every vl-mkdir that was allowed
        self.readonly_dirs = set()  # ones where (open ... "w") answers nil
        self.undo_groups = 0       # _.UNDO _Begin / _End balance
        self.undo_marks = 0        # StartUndoMark / EndUndoMark balance
        self.undo_log = []         # 'start' / 'end', in order
        self.lock_log = []         # (layer name, locked?) per vla-put-Lock
        # (builtin, ename) for every entmod / entdel a LOCKED layer
        # refused -- nil back, nothing changed, as in AutoCAD
        self.lock_refusals = []
        self.tablerecs = {}      # table -> {NAME: Ent} for tblobjname
        self.recdata = {}        # Ent -> alist for those records; kept
                                 # out of entdata, which is the DRAWING
        self.tables = {'LAYER': set(), 'LTYPE': {'CONTINUOUS'},
                       'DIMSTYLE': {'STANDARD'}, 'STYLE': {'STANDARD'}}
        # the ActiveX constants a routine compares against or hands to a
        # property.  :vlax-true / :vlax-false are two distinct symbols
        # that are BOTH non-nil, so they self-evaluate here; an unbound
        # symbol would read as nil and make every lock test succeed.
        for k in (':vlax-true', ':vlax-false'):
            self.globals[Sym(k)] = Sym(k)
        self.globals[Sym('acbylayer')] = 256
        self.globals[Sym('aclnwtbylayer')] = -1

    # ---------------- scripted input
    def pop_script(self, prompt, kind):
        if kind in HONOURS_INITGET:
            # this input spends the initget made for it; one made for an
            # input before it is gone (HONOURS_INITGET)
            if not self.initget_live:
                self.initget_bits, self.initget_kws = 0, ""
            self.initget_live = False
        if not self.script:
            raise LispError(f"SCRIPT EXHAUSTED at {kind} prompt: {prompt!r}",
                            self)
        v = self.script.pop(0)
        # AutoCAD keeps the prompt it just showed in LASTPROMPT, and an
        # input site whose prompt is built at run time labels its
        # transcript line with that -- so the VM has to keep it too, or
        # every such line would read "nil".  It is NOT in sysvars: it is
        # read-only in AutoCAD and changes at every prompt, and a test
        # that diffs the settings a run left behind must not see it
        self.lastprompt = prompt.lstrip("\n") if prompt else ""
        if callable(v):
            # A scripted answer that is a function is CALLED here, with
            # the VM, at the moment the prompt is reached.  That is the
            # only way to answer a prompt about something the run itself
            # drew: a preview a command makes and then asks you to click
            # has no entity name until the command has made it.
            v = v(self)
        self.prompts.append((prompt, v))
        if v is MISS and kind not in PICKS:
            raise Unanswerable(
                f"MISS scripted at the {kind} prompt {prompt!r}: only an "
                f"entsel, nentsel or nentselp can miss.  Anywhere else a "
                f"click is a point (at ssget, a window's first corner) or "
                f"no answer at all -- script what the drafter gives "
                f"there", self)
        return v

    # ---------------- name lookup (dynamic scope)
    def get(self, name):
        for frame in reversed(self.stack):
            if name in frame:
                return frame[name]
        return self.globals.get(name, NIL)

    def bound_local(self, name):
        """T when NAME is bound by some active call frame - an argument,
        a declared local, or a foreach variable.  Such a binding hides
        any function of the same name for as long as it is live."""
        for frame in self.stack:
            if name in frame:
                return True
        return False

    def set(self, name, val):
        for frame in reversed(self.stack):
            if name in frame:
                frame[name] = val
                return val
        self.globals[name] = val
        return val

    # ---------------- evaluation
    def eval(self, x):
        if isinstance(x, Sym):
            if x == 't':
                return T
            if x == 'pi':
                return math.pi
            return self.get(x)
        if not isinstance(x, list):
            return x            # number, string, Ent, NIL
        if not x:
            return NIL
        head = x[0]
        if isinstance(head, Sym):
            # This runs once per call form -- millions of times in the
            # big suites -- so the special form's method name comes out
            # of SF_NAME, mangled once at import, and the head is looked
            # up in ONE pass over the frames instead of get() and then
            # bound_local() walking them both.  The order is the one
            # those two gave: a special form wins outright, then the
            # innermost frame binding the name, then globals, then the
            # built-ins.  tests/test_lispvm_dispatch.py pins it.
            sf = SF_NAME.get(head)
            if sf is not None:
                special = getattr(self, sf, None)
                if special is not None:
                    return special(x[1:])
            for frame in reversed(self.stack):
                if head in frame:
                    fn = frame[head]
                    if isinstance(fn, tuple) and fn[0] == 'defun':
                        return self.call_defun(
                            head, fn, [self.eval(a) for a in x[1:]])
                    # A LOCAL SHADOWS THE FUNCTION OF THE SAME NAME.
                    # Declaring "last" in a defun's local list makes
                    # (last ...) inside that call "no function
                    # definition: LAST" in AutoCAD, even though last is
                    # a built-in -- the local binding is what the name
                    # resolves to.  Without this the VM would happily
                    # call the built-in (or an outer defun) and a
                    # routine that dies at the command line would pass
                    # its tests.
                    raise LispError(
                        f"no function definition: {head.upper()} -- it is "
                        f"declared as a local variable (or argument) of "
                        f"the defun being run, which shadows the function",
                        self)
            fn = self.globals.get(head, NIL)
            if isinstance(fn, tuple) and fn[0] == 'defun':
                return self.call_defun(head, fn,
                                       [self.eval(a) for a in x[1:]])
            b = BUILTINS.get(head)
            if b is not None:
                if self._in_handler and head in HANDLER_GATED:
                    args = [self.eval(a) for a in x[1:]]
                    self._handler_gate(head)
                    return b(self, args)
                return b(self, [self.eval(a) for a in x[1:]])
            raise LispError(f"undefined function: {head}", self)
        if isinstance(head, list) and head and head[0] == 'lambda':
            return self.call_lambda(head, [self.eval(a) for a in x[1:]])
        raise LispError(f"bad function position: {head!r}", self)

    def call_defun(self, name, fn, args):
        _, params, locals_, body = fn
        if len(args) != len(params):
            raise LispError(f"{name}: expected {len(params)} args, "
                            f"got {len(args)}", self)
        frame = dict(zip(params, args))
        for l in locals_:
            frame[l] = NIL
        self.stack.append(frame)
        self.calls.append(name)
        try:
            r = NIL
            for form in body:
                r = self.eval(form)
            return r
        except LispError as e:
            # The innermost defun is the point of failure, and the one
            # place the handler is dispatched from; the frames above see
            # the error already handled and just unwind.
            if (self.handle_errors and not self._catch_depth
                    and not self._in_handler
                    and not getattr(e, 'handled', False)):
                self._run_handler(e)
            raise
        finally:
            self.stack.pop()
            self.calls.pop()

    def _run_handler(self, e):
        """Run the *error* in force for error E, in the error mode in
        force (see __init__).  Returns when the handler finished; raises
        HandlerDeath (HandlerAbort for the uncatchable refusal) when it
        did not, marked handled so no outer frame runs it again."""
        # resolved HERE, with the stack live: in either mode the handler
        # AutoCAD calls is the one in force at the failure, a local
        # (defun *error* ...) of the command included
        h = self.get(Sym('*error*'))
        if not ((isinstance(h, tuple) and h[0] == 'defun') or (
                isinstance(h, list) and h and h[0] == 'lambda')):
            return
        e.handled = True
        msg = str(e).split('\n')[0]
        self.handled_errors.append(msg)
        # the pushed mode resets the evaluator before *error* runs: the
        # handler gets an EMPTY stack, so every binding the failing
        # code made -- the command's locals, its local helpers, the
        # locals of whatever it had called -- is out of scope, and a
        # name reads (or setq writes) its global.  Decided on entry: a
        # pop inside the handler does not bring the frames back.
        live = self.stack
        pushed = self.error_mode_depth > 0
        if pushed:
            self.stack = []
        self._in_handler = True
        try:
            if isinstance(h, tuple):
                self.call_defun(Sym('*error*'), h, [msg])
            else:
                self.call_lambda(h, [msg])
        except HandlerAbort as inner:
            inner.handled = True
            self.handler_deaths.append(str(inner).split('\n')[0])
            raise
        except LispError as inner:
            first = str(inner).split('\n')[0]
            self.handler_deaths.append(first)
            death = HandlerDeath(
                "*error* handler died%s on %r: %s" % (
                    " (pushed mode: the stack was reset)" if pushed else "",
                    msg, first), self)
            death.handled = True
            raise death from inner
        finally:
            self.stack = live
            self._in_handler = False

    def _handler_gate(self, name):
        """What AutoCAD refuses while *error* runs, by the error mode in
        force at the CALL -- so a handler that pops first is in the
        default mode from then on.  Called from eval and call_value, not
        from the builtins, so a test's stand-in for (command) keeps the
        rule."""
        if name == 'command':
            if self.error_mode_depth <= 0:
                raise LispError(
                    "Cannot invoke (command) from *error* without prior "
                    "call to (*push-error-using-command*).  Converting "
                    "(command) calls to (command-s) is recommended.", self)
        elif name == 'command-s':
            # the pushed mode is the one that says (command) is how
            # this handler drives commands.  The refusal is not an
            # ordinary error: vl-catch-all-apply does not catch it, and
            # the handler dies where it stands.  SPA's -DIMSTYLE restore
            # did exactly that on every Esc.
            if self.error_mode_depth > 0:
                raise HandlerAbort(
                    "INTERNAL error in FAIL: command-s inside *error* "
                    "while *push-error-using-command* is in effect -- "
                    "message lost, reset to top", self)

    def call_lambda(self, lam, args):
        params, locals_ = split_params(lam[1])
        return self.call_defun(Sym('<lambda>'),
                               ('defun', params, locals_, lam[2:]), args)

    def call_value(self, fnval, args):
        """apply/mapcar: fnval is a symbol or a (lambda ...) list."""
        if isinstance(fnval, Sym):
            fn = self.get(fnval)
            if isinstance(fn, tuple) and fn[0] == 'defun':
                return self.call_defun(fnval, fn, args)
            b = BUILTINS.get(fnval)
            if b is not None:
                # (vl-catch-all-apply 'command-s ...) is the spelling a
                # handler uses, so the handler rules apply here too
                if self._in_handler and fnval in HANDLER_GATED:
                    self._handler_gate(fnval)
                return b(self, args)
            raise LispError(f"apply: undefined function {fnval}", self)
        if isinstance(fnval, list) and fnval and fnval[0] == 'lambda':
            return self.call_lambda(fnval, args)
        raise LispError(f"apply: not a function: {fnval!r}", self)

    # ---------------- special forms
    def sf_quote(self, a):
        return a[0]

    def sf_function(self, a):
        return a[0]

    def sf_lambda(self, a):
        """(lambda (args) body ...) evaluates to the function itself, so
        it can be stored and called later -- how a command installs its
        own *error* handler without giving it a global name."""
        return [Sym('lambda')] + list(a)

    def sf_setq(self, a):
        if len(a) % 2:
            raise LispError("setq: odd number of arguments", self)
        r = NIL
        for i in range(0, len(a), 2):
            if not isinstance(a[i], Sym):
                raise LispError(f"setq: bad symbol {a[i]!r}", self)
            r = self.set(a[i], self.eval(a[i + 1]))
        return r

    def sf_if(self, a):
        # THE AutoLISP rule this VM exists to enforce
        if not 2 <= len(a) <= 3:
            raise LispError(f"(if ...) takes 2 or 3 arguments, got {len(a)}",
                            self)
        if truthy(self.eval(a[0])):
            return self.eval(a[1])
        return self.eval(a[2]) if len(a) == 3 else NIL

    def sf_progn(self, a):
        r = NIL
        for f in a:
            r = self.eval(f)
        return r

    def sf_cond(self, a):
        for clause in a:
            v = self.eval(clause[0])
            if truthy(v):
                for f in clause[1:]:
                    v = self.eval(f)
                return v
        return NIL

    # AutoLISP's and/or answer T or nil -- NEVER the deciding value, the
    # way Common Lisp's do.  The VM once returned the value, and code
    # that leaned on it (DIMSTAMP's parse, every (or (canon knob) "Yes")
    # default) passed every test and died in AutoCAD on "consp T" /
    # "stringp T".  tests/test_lispvm_logic.py pins this.
    def sf_and(self, a):
        v = T
        for f in a:
            v = self.eval(f)
            if not truthy(v):
                return NIL
        return T

    def sf_or(self, a):
        for f in a:
            v = self.eval(f)
            if truthy(v):
                return T
        return NIL

    def sf_while(self, a):
        while truthy(self.eval(a[0])):
            for f in a[1:]:
                self.eval(f)
        return NIL

    def sf_repeat(self, a):
        n = self.eval(a[0])
        r = NIL
        for _ in range(int(n)):
            for f in a[1:]:
                r = self.eval(f)
        return r

    def sf_foreach(self, a):
        var, lst = a[0], self.eval(a[1])
        r = NIL
        for item in (lst or []):
            self.stack.append({var: item})
            try:
                for f in a[2:]:
                    r = self.eval(f)
            finally:
                self.stack.pop()
        return r

    def sf_defun(self, a):
        # A defun assigns the symbol like any other, so a name the
        # enclosing defun localised (the (defun *error* ...) idiom, and
        # defun-local helpers alongside it) lands in that frame and goes
        # away with it, instead of leaking into the global namespace.
        name = a[0]
        params, locals_ = split_params(a[1])
        fn = ('defun', params, locals_, a[2:])
        # A defun whose name is a declared LOCAL of the call in progress
        # defines it into that local binding, not globally - which is
        # exactly why routines here list their inner helpers (and
        # *error*) among their locals: the helper lives for the command
        # and reverts when it ends.  Writing it straight to globals
        # would leave the local sitting at nil and make the helper look
        # like a name that shadows a function it never defines.
        if self.bound_local(name):
            self.set(name, fn)
        else:
            self.globals[name] = fn
        return name

    # ---------------- program entry
    def load(self, path):
        self.loads(open(self._remap_root(path)).read())

    def _remap_root(self, path):
        """CALOFIN_LISP_ROOT=shared reruns any VM-driven test against the
        loaded-together build: a path under lisp/ is remapped to
        <repo>/<root>/<basename> (flat folder, extension lowercased) and
        CALOFIN-LIB.lsp is loaded first, once per VM.  Unset, this is a
        no-op and every test loads the standalone lisp/ files as before."""
        root = os.environ.get('CALOFIN_LISP_ROOT')
        if not root:
            return path
        ap = os.path.abspath(path)
        parts = ap.split(os.sep)
        if 'lisp' not in parts:
            return path
        repo = os.sep.join(parts[:parts.index('lisp')])
        stem, ext = os.path.splitext(os.path.basename(ap))

        def under(name):
            # the members sit in <root>/parts/; <root>/ itself is kept as a
            # fallback so CALOFIN_LISP_ROOT=shared/parts works too
            for base in (os.path.join(repo, root, 'parts'),
                         os.path.join(repo, root)):
                cand = os.path.join(base, name)
                if os.path.exists(cand):
                    return cand
            return os.path.join(repo, root, name)

        if not getattr(self, '_shared_lib_loaded', False):
            self._shared_lib_loaded = True
            lib = under('CALOFIN-LIB.lsp')
            if os.path.exists(lib):
                self.loads(open(lib).read())
        return under(stem + ext.lower())

    def loads(self, src):
        """Evaluate LISP source text (for test fixtures / extra defuns)."""
        r = NIL
        for form in parse_all(src):
            r = self.eval(form)
        return r

    def run(self, name, script):
        self.script = list(script)
        self.prompts = []
        fn = self.get(Sym(name.lower()))
        if not (isinstance(fn, tuple) and fn[0] == 'defun'):
            raise LispError(f"{name} is not defined", self)
        # CMDNAMES names the command AutoCAD is running, as it does for
        # a c: command typed at the command line -- and only that one: a
        # (c:OTHER) the command calls as a function adds nothing to it,
        # which is how LAZDIAG tells a nested run from a later one
        was = self.sysvars.get('CMDNAMES', '')
        if name.lower().startswith('c:'):
            self.sysvars['CMDNAMES'] = name[2:].upper()
        self._underflow_mark = self.error_mode_underflow
        try:
            r = self.call_defun(Sym(name.lower()), fn, [])
        except LispError as e:
            # the command went through its handler and was aborted --
            # what the user sees is a prompt back, not a crash.  A
            # handler that DIED on the way is not that: the drafter got
            # a raw error and none of the handler's cleanup
            if (self.handle_errors and getattr(e, 'handled', False)
                    and not isinstance(e, HandlerDeath)):
                self._check_balanced(name)
                return NIL
            raise
        finally:
            self.sysvars['CMDNAMES'] = was
        self._check_balanced(name)
        if self.script:
            raise LispError(
                f"{len(self.script)} scripted answers left over: "
                f"{self.script[:6]!r}", self)
        return r

    def _check_balanced(self, name):
        """A command hands the session back the way it found it: no
        undo group of its own still open, no error mode still pushed,
        and no mode popped that it never pushed.  Each is the class of
        defect that only shows up in the NEXT command a drafter runs,
        so every run() checks."""
        if self.undo_groups:
            raise LispError(f"{name} returned with {self.undo_groups} undo "
                            f"group(s) still open", self)
        if self.error_mode_depth:
            raise LispError(f"{name} returned with the error mode still "
                            f"pushed ({self.error_mode_depth} deep)", self)
        under = self.error_mode_underflow - self._underflow_mark
        if under > 0:
            raise LispError(f"{name} popped the error mode with nothing "
                            f"pushed ({under} time(s))", self)

    def layer_of(self, e):
        for pair in self.entdata.get(e, []):
            if isinstance(pair, Dot) and pair.a == 8:
                return pair.b
            if isinstance(pair, list) and pair and pair[0] == 8:
                return pair[1]
        return NIL


#: builtins whose use inside *error* depends on the error mode; see
#: VM._handler_gate
HANDLER_GATED = frozenset({Sym('command'), Sym('command-s')})

SPECIAL = {Sym(s) for s in
           ['quote', 'function', 'setq', 'if', 'progn', 'cond', 'and', 'or',
            'while', 'repeat', 'foreach', 'defun', 'lambda']}


def _sf_name(s):
    """The VM method a special form dispatches to: sf_ plus its name with
    the characters a Python identifier cannot hold spelled out."""
    return 'sf_' + (s.replace(':', '_').replace('-', '_').replace('*', '_')
                    .replace('+', 'plus').replace('/', 'slash')
                    .replace('=', 'eq').replace('<', 'lt').replace('>', 'gt'))


#: SPECIAL name -> its method name, mangled once here rather than on every
#: call form eval sees.
SF_NAME = {s: _sf_name(s) for s in SPECIAL}


def split_params(plist):
    params, locals_, in_locals = [], [], False
    for p in (plist or []):
        if p == '/':
            in_locals = True
        elif in_locals:
            locals_.append(p)
        else:
            params.append(p)
    return params, locals_


# ---------------- builtins ------------------------------------------------

def num(v, ctx='arithmetic'):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise LispError(f"{ctx}: not a number: {v!r}")
    return v


def pt(v):
    if not isinstance(v, list) or len(v) < 2:
        raise LispError(f"not a point: {v!r}")
    return v


def _arith(op, args, unit):
    if not args:
        return unit
    r = num(args[0])
    for v in args[1:]:
        r = op(r, num(v))
    return r


def _div(a, b):
    # AutoCAD's own message, and an AutoLISP error rather than a Python
    # one, so it reaches the routine's *error* handler the way it does
    # at the command line -- for a real as much as for an int
    if b == 0:
        raise LispError("divide by zero")
    if isinstance(a, int) and isinstance(b, int):
        return a // b if (a < 0) == (b < 0) or a % b == 0 else -((-a) // b)
    return a / b


def _cmp(op, args, eq=False):
    for x, y in zip(args, args[1:]):
        if isinstance(x, str) and isinstance(y, str):
            if not op(x, y):
                return NIL
        elif x is NIL or y is NIL:
            # AutoCAD's = and /= accept nil ((/= nil 4) is T, (= nil nil)
            # is T); the ordering comparators reject it, and the lenient
            # stance for those stays NIL rather than a hard error.
            if not eq or not op(x, y):
                return NIL
        else:
            if not op(num(x), num(y)):
                return NIL
    return T


def bi(name):
    def deco(f):
        BUILTINS[Sym(name)] = f
        return f
    return deco


BUILTINS = {}

BUILTINS[Sym('+')] = lambda vm, a: _arith(lambda x, y: x + y, a, 0)
BUILTINS[Sym('-')] = lambda vm, a: (-num(a[0]) if len(a) == 1
                                    else _arith(lambda x, y: x - y, a, 0))
BUILTINS[Sym('*')] = lambda vm, a: _arith(lambda x, y: x * y, a, 1)
BUILTINS[Sym('/')] = lambda vm, a: (_div(1, num(a[0])) if len(a) == 1
                                    else _arith(_div, a, 1))
BUILTINS[Sym('1+')] = lambda vm, a: num(a[0]) + 1
BUILTINS[Sym('1-')] = lambda vm, a: num(a[0]) - 1
BUILTINS[Sym('=')] = lambda vm, a: _cmp(lambda x, y: x == y, a, eq=True)
BUILTINS[Sym('/=')] = lambda vm, a: _cmp(lambda x, y: x != y, a, eq=True)
BUILTINS[Sym('<')] = lambda vm, a: _cmp(lambda x, y: x < y, a)
BUILTINS[Sym('<=')] = lambda vm, a: _cmp(lambda x, y: x <= y, a)
BUILTINS[Sym('>')] = lambda vm, a: _cmp(lambda x, y: x > y, a)
BUILTINS[Sym('>=')] = lambda vm, a: _cmp(lambda x, y: x >= y, a)


@bi('eq')
def _eq(vm, a):
    x, y = a
    return T if (x is y or (isinstance(x, Sym) and isinstance(y, Sym)
                            and x == y)
                 or (x is NIL and y is NIL)) else NIL


@bi('equal')
def _equal(vm, a):
    x, y = a[0], a[1]
    fuzz = a[2] if len(a) > 2 else 0

    def same(p, q):
        if isinstance(p, (int, float)) and isinstance(q, (int, float)):
            return abs(p - q) <= fuzz
        if isinstance(p, Dot) and isinstance(q, Dot):
            return same(p.a, q.a) and same(p.b, q.b)
        if isinstance(p, list) and isinstance(q, list):
            return len(p) == len(q) and all(same(i, j) for i, j in zip(p, q))
        return p == q or (p is NIL and q is NIL)
    return T if same(x, y) else NIL


BUILTINS[Sym('null')] = lambda vm, a: T if not truthy(a[0]) else NIL
BUILTINS[Sym('not')] = lambda vm, a: T if not truthy(a[0]) else NIL
BUILTINS[Sym('numberp')] = lambda vm, a: (T if isinstance(a[0], (int, float))
                                          else NIL)
BUILTINS[Sym('listp')] = lambda vm, a: (T if (a[0] is NIL or
                                              isinstance(a[0], list)) else NIL)
BUILTINS[Sym('zerop')] = lambda vm, a: T if num(a[0]) == 0 else NIL
BUILTINS[Sym('minusp')] = lambda vm, a: T if num(a[0]) < 0 else NIL
BUILTINS[Sym('boundp')] = lambda vm, a: (T if vm.get(a[0]) is not NIL
                                         else NIL)


@bi('type')
def _type(vm, a):
    v = a[0]
    if v is NIL:
        return NIL
    if isinstance(v, Sym):
        return Sym('sym')
    if isinstance(v, str):
        return Sym('str')
    if isinstance(v, int):
        return Sym('int')
    if isinstance(v, float):
        return Sym('real')
    if isinstance(v, Ent):
        return Sym('ename')
    if isinstance(v, list):
        # A selection set is a list in disguise here, but it is not one
        # in AutoCAD and code that asks is entitled to the real answer:
        # lzd:watch takes an ename, a set or a list of either, and told
        # LIST for a set it would walk the '<ss>' marker as an entity.
        return Sym('pickset') if _is_ss(v) else Sym('list')
    if isinstance(v, FileHandle):
        return Sym('file')
    return Sym('other')


# lists
def _car(vm, a):
    v = a[0]
    if v is NIL:
        return NIL
    if isinstance(v, Dot):
        return v.a
    if not isinstance(v, list):
        raise LispError(f"car: not a list: {v!r}", vm)
    return v[0] if v else NIL


def _cdr(vm, a):
    v = a[0]
    if v is NIL:
        return NIL
    if isinstance(v, Dot):
        return v.b
    if not isinstance(v, list):
        raise LispError(f"cdr: not a list: {v!r}", vm)
    return v[1:] or NIL


BUILTINS[Sym('car')] = _car
BUILTINS[Sym('cdr')] = _cdr


def _cxr(path):
    def f(vm, a):
        v = a[0]
        for c in reversed(path):
            if v is NIL:
                return NIL
            if isinstance(v, Dot):
                v = v.a if c == 'a' else v.b
                continue
            if not isinstance(v, list):
                raise LispError(f"c{path}r: not a list: {v!r}")
            v = (v[0] if c == 'a' else (v[1:] or NIL))
        return v
    return f


for _p in ['aa', 'ad', 'da', 'dd', 'aaa', 'aad', 'ada', 'add',
           'daa', 'dad', 'dda', 'ddd', 'adda', 'addd', 'adad']:
    BUILTINS[Sym('c' + _p + 'r')] = _cxr(_p)
BUILTINS[Sym('cadddr')] = _cxr('addd')
BUILTINS[Sym('caddr')] = _cxr('add')
BUILTINS[Sym('cadr')] = _cxr('ad')
def _cons(vm, a):
    x, y = a
    if y is NIL:
        return [x]
    if isinstance(y, list):
        return [x] + y
    return Dot(x, y)


BUILTINS[Sym('cons')] = _cons
BUILTINS[Sym('list')] = lambda vm, a: list(a)
BUILTINS[Sym('append')] = lambda vm, a: (sum([x for x in a if x], [])
                                         or NIL)
BUILTINS[Sym('reverse')] = lambda vm, a: (list(reversed(a[0])) if a[0]
                                          else NIL)
BUILTINS[Sym('length')] = lambda vm, a: len(a[0] or [])
BUILTINS[Sym('last')] = lambda vm, a: (a[0][-1] if a[0] else NIL)


@bi('nth')
def _nth(vm, a):
    i, lst = int(num(a[0])), (a[1] or [])
    return lst[i] if 0 <= i < len(lst) else NIL


@bi('member')
def _member(vm, a):
    x, lst = a[0], (a[1] or [])
    for i, v in enumerate(lst):
        if truthy(_equal(vm, [x, v])):
            return lst[i:]
    return NIL


@bi('assoc')
def _assoc(vm, a):
    key, lst = a[0], (a[1] or [])
    if not isinstance(lst, list):
        raise LispError(f"assoc: not a list: {lst!r}", vm)
    for item in lst:
        if isinstance(item, Dot) and truthy(_equal(vm, [key, item.a])):
            return item
        if isinstance(item, list) and item and \
           truthy(_equal(vm, [key, item[0]])):
            return item
    return NIL


@bi('subst')
def _subst(vm, a):
    new, old, lst = a
    return [new if truthy(_equal(vm, [x, old])) else x for x in (lst or [])] \
        or NIL


@bi('mapcar')
def _mapcar(vm, a):
    fn, lists = a[0], [x or [] for x in a[1:]]
    return [vm.call_value(fn, list(args)) for args in zip(*lists)] or NIL


@bi('apply')
def _apply(vm, a):
    return vm.call_value(a[0], list(a[1] or []))


BUILTINS[Sym('eval')] = lambda vm, a: vm.eval(a[0])


@bi('read')
def _read(vm, a):
    """(read string) -- the first expression in it, NIL for an empty
    string.  Malformed text is an AutoLISP error ("malformed list"),
    and one vl-catch-all-apply can catch -- which is how LAZTUNE
    refuses a half-typed value -- so it is raised as one here rather
    than escaping as the parser's own IndexError."""
    if not a[0]:
        return NIL
    try:
        return parse_all(a[0])[0]
    except (IndexError, ValueError, LispError):
        raise LispError("read: malformed input", vm)

# math
BUILTINS[Sym('min')] = lambda vm, a: min(num(v) for v in a)
BUILTINS[Sym('max')] = lambda vm, a: max(num(v) for v in a)
BUILTINS[Sym('abs')] = lambda vm, a: abs(num(a[0]))
BUILTINS[Sym('sqrt')] = lambda vm, a: math.sqrt(num(a[0]))
BUILTINS[Sym('expt')] = lambda vm, a: num(a[0]) ** num(a[1])
BUILTINS[Sym('sin')] = lambda vm, a: math.sin(num(a[0]))
BUILTINS[Sym('cos')] = lambda vm, a: math.cos(num(a[0]))
BUILTINS[Sym('atan')] = lambda vm, a: (math.atan(num(a[0])) if len(a) == 1
                                       else math.atan2(num(a[0]),
                                                       num(a[1])))


def _rem(vm, a):
    if num(a[1]) == 0:
        raise LispError("divide by zero", vm)
    return num(a[0]) % num(a[1])


BUILTINS[Sym('rem')] = _rem
BUILTINS[Sym('float')] = lambda vm, a: float(num(a[0]))
BUILTINS[Sym('fix')] = lambda vm, a: int(num(a[0]))
# logand lives with logior further down -- the n-argument _logop pair
BUILTINS[Sym('gcd')] = lambda vm, a: math.gcd(int(a[0]), int(a[1]))
BUILTINS[Sym('distance')] = lambda vm, a: math.dist(pt(a[0])[:2],
                                                    pt(a[1])[:2])
BUILTINS[Sym('angle')] = lambda vm, a: math.atan2(
    pt(a[1])[1] - pt(a[0])[1], pt(a[1])[0] - pt(a[0])[0]) % (2 * math.pi)
BUILTINS[Sym('polar')] = lambda vm, a: [pt(a[0])[0] + a[2] * math.cos(a[1]),
                                        pt(a[0])[1] + a[2] * math.sin(a[1])]


@bi('inters')
def _inters(vm, a):
    """(inters p1 p2 p3 p4 [onseg]) -- where the two lines cross, in
    plan.  With onseg absent or non-nil the crossing must lie on both
    segments; an explicit nil intersects the INFINITE lines, which is
    how the drafting routines project a tread onto a wall."""
    (x1, y1), (x2, y2) = pt(a[0])[:2], pt(a[1])[:2]
    (x3, y3), (x4, y4) = pt(a[2])[:2], pt(a[3])[:2]
    d1x, d1y = x2 - x1, y2 - y1
    d2x, d2y = x4 - x3, y4 - y3
    den = d1x * d2y - d1y * d2x
    if abs(den) < 1e-12:
        return NIL
    t = ((x3 - x1) * d2y - (y3 - y1) * d2x) / den
    u = ((x3 - x1) * d1y - (y3 - y1) * d1x) / den
    if (len(a) < 5 or truthy(a[4])) \
            and not (-1e-9 <= t <= 1.0 + 1e-9 and -1e-9 <= u <= 1.0 + 1e-9):
        return NIL
    return [x1 + t * d1x, y1 + t * d1y, 0.0]


# vector graphics: previews the VM has no screen for
BUILTINS[Sym('grdraw')] = lambda vm, a: NIL

# strings
@bi('strcat')
def _strcat(vm, a):
    """AutoCAD's strcat takes strings and nothing else -- a nil that
    reached it is a bug in the routine, so it dies here rather than
    quietly stringifying itself.

    A SYMBOL is not a string either, and that one needs saying because
    Sym subclasses str here: without the isinstance below, a routine
    that strcats a symbol -- an entry point handed 'pool:run instead of
    "pool:run" -- reads as fine in the VM and dies in AutoCAD with bad
    argument type: stringp.  (vl-princ-to-string or princ is the way to
    name a symbol in a message.)"""
    for i, x in enumerate(a):
        if isinstance(x, Sym) or not isinstance(x, str):
            raise LispError(
                f"strcat: bad argument type: stringp {x!r} (arg {i + 1})", vm)
    return ''.join(a)
BUILTINS[Sym('strlen')] = lambda vm, a: len(a[0]) if a else 0
BUILTINS[Sym('itoa')] = lambda vm, a: str(int(num(a[0])))


@bi('atoi')
def _atoi(vm, a):
    """AutoLISP reads the leading integer and stops there: (atoi "34x")
    is 34 and (atoi "x") is 0.  Testing the prefix and then converting
    the WHOLE string, as this did, raised on every value AutoCAD simply
    answers -- and a routine parsing a string it did not write is
    exactly where that shows up."""
    m = re.match(r'^[+-]?\d+', a[0])
    return int(m.group()) if m else 0


BUILTINS[Sym('atof')] = lambda vm, a: float(re.match(
    r'^[+-]?\d*\.?\d*', a[0]).group() or 0)
BUILTINS[Sym('chr')] = lambda vm, a: chr(int(a[0]))
BUILTINS[Sym('ascii')] = lambda vm, a: ord(a[0][0]) if a[0] else 0


@bi('strcase')
def _strcase(vm, a):
    s = a[0]
    return s.lower() if len(a) > 1 and truthy(a[1]) else s.upper()


@bi('substr')
def _substr(vm, a):
    s, start = a[0], int(a[1])
    ln = int(a[2]) if len(a) > 2 else len(s)
    return s[start - 1:start - 1 + ln]


#: an architectural / engineering distance: feet, inches, a fraction, in
#: any of the spellings AutoCAD accepts -- 3', 3'6, 3'-6", 42, 42-1/2",
#: 1/2.  Anchored at both ends, so trailing junk is not a distance.
_ARCH = re.compile(r'''^\s*(?P<sign>[-+]?)\s*
                     (?:(?P<feet>\d+(?:\.\d+)?)\s*'\s*)?
                     (?:-?\s*(?P<inch>\d+(?:\.\d+)?)(?!\s*/))?
                     (?:\s*-?\s*(?P<num>\d+)\s*/\s*(?P<den>\d+))?
                     \s*(?:"|\'\')?\s*$''', re.X)


#: mode 5's spellings: a whole number, a fraction, or both -- 17, 1/2,
#: and 17 1/2 as rtos writes it (17-1/2 as the keyboard types it).
_FRAC5 = re.compile(r'''^\s*(?P<sign>[-+]?)\s*
                      (?:(?P<whole>\d+(?:\.\d+)?)\s*$
                       | (?:(?P<w>\d+)(?:\s+|\s*-\s*))?
                         (?P<num>\d+)\s*/\s*(?P<den>\d+)\s*$)''', re.X)


@bi('distof')
def _distof(vm, a):
    """(distof string [mode]) -- nil when the text is not a distance.

    The complement of rtos (AutoLISP Reference, distof: 'If you pass
    distof a string created by rtos, distof is guaranteed to return a
    valid value ... assuming the mode values are the same'), and a
    mode left out is the current LUNITS, as it is for rtos.

    Modes 3 and 4 are engineering and architectural, and in those
    AutoCAD really does read the feet-and-inches spellings back --
    which is the whole reason a routine asks in mode 4 and then falls
    back to mode 2 (LAZFORM, LAZSTEP, ABHD's hopper offsets).  Reading
    only the leading number here made 3'6 come back as 3, so every
    feet-inch answer in the tree was being tested at a twelfth of its
    size, silently.  Mode 1 reads rtos's 1.7500E+01 and mode 5 its
    17 1/2, both of which the leading-number read took as 1.75 and 17.
    Mode 2 keeps the lenient leading-number read, because several tools
    use (distof s 2) as their "is this text a number?" test and a
    stricter one would reclassify drawing text."""
    try:
        s = str(a[0])
    except (TypeError, ValueError):
        return NIL
    if len(a) > 1 and isinstance(a[1], (int, float)):
        mode = int(a[1])
    else:
        mode = int(vm.sysvars.get('LUNITS') or 2)
    if mode == 1:
        m = re.match(r'\s*[-+]?(\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?', s)
        return float(m.group(0)) if m else NIL
    if mode == 5:
        m = _FRAC5.match(s)
        if not m:
            return NIL
        if m.group('whole'):
            v = float(m.group('whole'))
        else:
            den = float(m.group('den'))
            if den == 0:
                return NIL
            v = float(m.group('w') or 0) + float(m.group('num')) / den
        return -v if m.group('sign') == '-' else v
    if mode in (3, 4):
        m = _ARCH.match(s)
        if not m or not (m.group('feet') or m.group('inch')
                         or m.group('num')):
            return NIL
        v = 12.0 * float(m.group('feet') or 0)
        v += float(m.group('inch') or 0)
        if m.group('num'):
            den = float(m.group('den'))
            if den == 0:
                return NIL
            v += float(m.group('num')) / den
        return -v if m.group('sign') == '-' else v
    m = re.match(r'\s*[-+]?(\d+\.?\d*|\.\d+)', s)
    try:
        return float(m.group(0)) if m else NIL
    except ValueError:
        return NIL


def _rtos_decimal(v, prec, dimzin):
    """Mode 2: DIMZIN bit 8 trims the trailing zeros (and the point, when
    nothing is left after it), bit 4 the leading zero -- 12.5000 is 12.5
    and 0.5000 is .5000 (the DIMZIN reference's own examples)."""
    s = f"{v:.{prec}f}"
    if dimzin & 8 and '.' in s:
        s = s.rstrip('0').rstrip('.')
    if dimzin & 4:
        if s.startswith('0.'):
            s = s[1:]
        elif s.startswith('-0.'):
            s = '-' + s[2:]
    return s


def _frac(n, den):
    g = math.gcd(n, den)
    return f"{n // g}/{den // g}"


def _rtos_feet_inches(v, mode, prec, dimzin):
    """Modes 3 (engineering) and 4 (architectural), spelled after DIMZIN's
    two low bits: 0 drops zero feet AND precisely zero inches, 1 keeps
    both, 2 keeps zero feet and drops zero inches, 3 keeps zero inches
    and drops zero feet.  So at 0 -- acad.dwt's setting -- a whole foot
    is 15' and six inches is 6", where the VM used to write 15'-0" and
    0'-6" whatever DIMZIN held.  DIMZIN's leading/trailing bits are NOT
    applied to mode 3's decimal inches: whether AutoCAD does is not
    documented, so the inches keep every digit of PREC."""
    low = dimzin & 3
    keep_feet = low in (1, 2)
    keep_inch = low in (1, 3)
    neg = v < 0
    v = abs(v)
    if mode == 4:
        den = 2 ** prec
        inches, frac = divmod(round(v * den), den)
        feet, whole = divmod(inches, 12)
        zero_in = whole == 0 and frac == 0
        if frac:
            ins = (f"{whole} {_frac(frac, den)}"
                   if (whole or feet or keep_feet) else _frac(frac, den))
        else:
            ins = str(whole)
    else:
        feet = int(v // 12)
        ins = f"{v - 12 * feet:.{prec}f}"
        if float(ins) >= 12.0:          # rounded up to the next foot
            feet += 1
            ins = f"{0.0:.{prec}f}"
        zero_in = float(ins) == 0.0
    ins += '"'
    if feet == 0 and not keep_feet:
        s = ins
    elif zero_in and not keep_inch and feet != 0:
        s = f"{feet}'"
    else:
        s = f"{feet}'-{ins}"
    return ('-' if neg else '') + s


@bi('rtos')
def _rtos(vm, a):
    """(rtos number [mode [precision]]) -- the number as AutoCAD spells
    it, which is NOT one spelling: it follows the system variables
    (AutoLISP Reference, rtos: 'according to the settings of mode,
    precision, and the AutoCAD UNITMODE, DIMZIN, LUNITS, and LUPREC
    system variables').  A mode or precision left out is LUNITS /
    LUPREC; the text follows DIMZIN -- feet and inches by its two low
    bits, a decimal's leading zero by bit 4 and its trailing zeros by
    bit 8.  The VM used to read none of them, so a tool that printed a
    whole foot through rtos read 15'-0" here and 15' in the drafter's
    drawing, and a CDATE sliced through rtos was whole here and
    trimmed at DIMZIN 8.  UNITMODE 1's spelling is not modelled (0 is
    assumed).  tests/test_lispvm_values.py pins each rule."""
    v = num(a[0])
    mode = int(a[1]) if len(a) > 1 else int(vm.sysvars.get('LUNITS') or 2)
    if len(a) > 2:
        prec = int(a[2])
    else:
        lup = vm.sysvars.get('LUPREC')
        prec = 4 if lup is None else int(lup)
    dimzin = int(vm.sysvars.get('DIMZIN') or 0)
    if mode in (3, 4):
        return _rtos_feet_inches(v, mode, prec, dimzin)
    if mode == 1:                       # scientific: 1.7500E+01
        return f"{v:.{prec}E}"
    if mode == 5:                       # fractional: 17 1/2
        den = 2 ** prec
        whole, frac = divmod(round(abs(v) * den), den)
        if frac:
            s = (f"{whole} " if whole else '') + _frac(frac, den)
        else:
            s = str(whole)
        return ('-' if v < 0 else '') + s
    return _rtos_decimal(v, prec, dimzin)


def _angtos(vm, a):
    """(angtos ang [mode [prec]]) -- an angle in radians as a string.
    Mode 0 is AutoLISP's default and the only one anything here asks
    for: decimal DEGREES, which is also what the commands that read an
    angle back -- DIMLINEAR's Rotated option, say -- expect.  Mode 3 is
    radians; the surveyor / grad / deg-min-sec spellings are not
    modelled, and come out as decimal degrees too.
    """
    mode = int(num(a[1])) if len(a) > 1 else 0
    prec = int(num(a[2])) if len(a) > 2 else 4
    v = num(a[0])
    if mode == 3:                       # radians, spelled as such
        return f"{v:.{prec}f}r"
    return f"{math.degrees(v) % 360.0:.{prec}f}"


BUILTINS[Sym('angtos')] = _angtos

# io
def _princ(vm, a):
    """(princ [x]) -- returns x, and keeps what was written.  What a
    command tells the user is behaviour like any other: a run that ends
    saying nothing is a bug, and a test can only see that if the VM
    remembers the words."""
    if a and a[0] is not NIL:
        vm.printed.append(a[0] if isinstance(a[0], str) else str(a[0]))
    return a[0] if a else NIL


BUILTINS[Sym('princ')] = _princ


def _alert(vm, a):
    """(alert msg) -- an OK-only message box.  The VM has no UI to pop
    one on, so this records what would have been shown, the same way
    princ's own output is kept, and returns nil -- what alert itself
    returns once the box is dismissed."""
    if a and a[0] is not NIL:
        vm.printed.append(a[0] if isinstance(a[0], str) else str(a[0]))
    return NIL


BUILTINS[Sym('alert')] = _alert


def _to_string(v):
    """(vl-princ-to-string x) -- what princ would have shown, as a
    string.  The one way to get a symbol or an ename into a message
    without strcat refusing it, which is how lzd:str takes "anything at
    all" and gives back something a DXF line can hold."""
    if v is NIL:
        return "nil"
    if v is T:
        return "T"
    if isinstance(v, bool):
        return "T" if v else "nil"
    # Sym BEFORE str: Sym subclasses str, so the str branch would hand
    # the symbol back unconverted and strcat would then refuse it --
    # which is exactly how AutoCAD behaves with a symbol, and exactly
    # not what vl-princ-to-string is for
    if isinstance(v, Sym):
        return str.__str__(v).upper()
    if isinstance(v, str):
        return v
    if isinstance(v, float):
        return _rtos_default(v)
    if _is_ss(v):
        return "<Selection set: %d>" % (len(v) - 1)
    if isinstance(v, list):
        return "(" + " ".join(_to_string(x) for x in v) + ")"
    return str(v)


BUILTINS[Sym('vl-princ-to-string')] = lambda vm, a: _to_string(a[0])
BUILTINS[Sym('prin1')] = lambda vm, a: (a[0] if a else NIL)
BUILTINS[Sym('print')] = lambda vm, a: (a[0] if a else NIL)
BUILTINS[Sym('terpri')] = lambda vm, a: NIL


@bi('prompt')
def _prompt(vm, a):
    """(prompt msg) -- shown to the user like princ, returns nil.  It
    used to be a silent no-op here, so a tool that reports through
    prompt (AUTOBEAD, PADDLE) looked mute to every test."""
    if a and isinstance(a[0], str):
        vm.printed.append(a[0])
    return NIL




# sysvars, tables
@bi('getvar')
def _getvar(vm, a):
    """An unknown variable is nil, as in AutoCAD -- not 0, which this
    VM used to invent and which no arithmetic ever complained about."""
    if a[0].upper() == 'LASTPROMPT':
        return vm.lastprompt
    return vm.sysvars.get(a[0].upper(), NIL)


@bi('setvar')
def _setvar(vm, a):
    name = a[0].upper()
    if name == 'CLAYER' and a[1] not in vm.tables['LAYER'] and a[1] != '0':
        raise LispError(f"setvar CLAYER: layer does not exist: {a[1]!r}", vm)
    vm.sysvars[name] = a[1]
    return a[1]


def _block_chain(vm, name):
    """The definition of NAME as a run of entities entnext can walk, the
    way AutoCAD hands one out: group -2 of the block table record is the
    first entity, entnext steps along, and an ENDBLK ends the run.

    They live in vm.entdata so entget reads them, and NOT in vm.entities,
    because a block definition is not in the drawing: (ssget "_X"),
    entlast and a bare (entnext) must never see one.  Rebuilt when the
    definition grows, so a test that entmakes into a block after reading
    it still gets the whole thing."""
    key = _blockkey(vm, name)
    if key is None:
        return []
    alists = vm.blocks.get(key, [])
    have = vm.blockents.get(key)
    if have is not None and have[0] == len(alists):
        return have[1]
    run = []
    for alist in alists:
        e = Ent()
        vm.entdata[e] = list(alist)
        run.append(e)
    end = Ent()
    vm.entdata[end] = [Dot(0, 'ENDBLK'), Dot(8, '0')]
    run.append(end)
    for i, e in enumerate(run):
        vm.blockof[e] = (key, i)
    vm.blockents[key] = (len(alists), run)
    return run


def _blockkey(vm, name):
    """The spelling vm.blocks is keyed by, for a name given in any case."""
    if name in vm.blocks:
        return name
    for k in vm.blocks:
        if k.upper() == str(name).upper():
            return k
    return name if name in {x for x in vm.tables.get('BLOCK', set())} else None


@bi('tblsearch')
def _tblsearch(vm, a):
    """The symbol-table record as an assoc list, the way AutoLISP hands
    it back.  A record a test materialized (entmake, or a tblobjname +
    entmod round trip) is returned live, so a frozen/locked flag shows
    here too; a name known only by membership gets the same defaults
    tblobjname would invent for it.  Only LAYER carries the full default
    record -- routines read 70/62/6 off layers (lock checks, effective
    linetype), while other tables are only probed for existence."""
    table, name = a[0].upper(), a[1].upper()
    if name not in {x.upper() for x in vm.tables.get(table, set())}:
        return NIL
    rec = vm.tablerecs.get(table, {}).get(name)
    if rec is not None:
        return list(vm.recdata[rec])
    if table == 'LAYER':
        return [Dot(0, table), Dot(2, a[1]), Dot(70, 0),
                Dot(62, 7), Dot(6, 'Continuous')]
    if table == 'BLOCK':
        key = _blockkey(vm, a[1])
        hdr = dict()
        for g in vm.blockhdr.get(key, []):
            if isinstance(g, Dot):
                hdr.setdefault(g.a, g.b)
            elif isinstance(g, list) and g:
                hdr.setdefault(g[0], g[1:] if len(g) > 2 else g[1])
        base = hdr.get(10, [0.0, 0.0, 0.0])
        if not isinstance(base, list):
            base = [float(base), 0.0, 0.0]
        base = [float(x) for x in (list(base) + [0.0, 0.0, 0.0])[:3]]
        run = _block_chain(vm, a[1])
        return [Dot(0, table), Dot(2, key if key else a[1]),
                Dot(70, int(hdr.get(70, 0))),
                [10] + base,
                Dot(-2, run[0] if run else NIL)]
    return [Dot(0, table), Dot(2, a[1])]


@bi('tblobjname')
def _tblobjname(vm, a):
    """The symbol table RECORD, which entget/entmod can then work on --
    how a routine thaws, unlocks or switches a layer back on.  A layer a
    test declared by name alone gets a record made for it here, on
    demand, with the defaults AutoCAD would have given it."""
    table, name = a[0].upper(), a[1].upper()
    if name not in {x.upper() for x in vm.tables.get(table, set())}:
        return NIL
    recs = vm.tablerecs.setdefault(table, {})
    if name not in recs:
        e = Ent()
        vm.recdata[e] = [Dot(0, table), Dot(2, a[1]), Dot(70, 0),
                         Dot(62, 7), Dot(6, 'Continuous')]
        recs[name] = e
    return recs[name]


# entities
@bi('entmake')
def _entmake(vm, a):
    alist = a[0]
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    etype = d.get(0)
    if etype == 'LAYER':
        vm.tables['LAYER'].add(d[2])
        # the record itself, so tblobjname can hand it to a routine that
        # thaws or unlocks the layer.  It is NOT an entity in the
        # drawing: symbol table records never appear to entnext/entlast
        # or to a selection set, and a test that walks the drawing must
        # not trip over them
        e = Ent()
        vm.recdata[e] = list(alist)
        vm.tablerecs.setdefault('LAYER', {})[d[2].upper()] = e
        return alist
    if etype == 'LTYPE':
        vm.tables['LTYPE'].add(d[2])
        return alist
    if etype == 'STYLE':
        vm.tables.setdefault('STYLE', set()).add(d[2])
        return alist
    # A BLOCK ... ENDBLK run defines a block: everything between the two
    # belongs to the definition in the block table, NOT to the drawing.
    # Model it, or a routine that defines a block would leave its ATTDEFs
    # lying in model space for the next (ssget "_X") to trip over.
    if etype == 'BLOCK':
        vm._blockdef = d.get(2, '')
        vm.tables.setdefault('BLOCK', set()).add(vm._blockdef)
        vm.blocks.setdefault(vm._blockdef, [])
        # kept so tblsearch can hand back the record AutoCAD would --
        # group 10 is the insertion BASE POINT, which a routine reading
        # a definition's geometry has to subtract
        vm.blockhdr[vm._blockdef] = list(alist)
        return alist
    if etype == 'ENDBLK':
        vm._blockdef = None
        return alist
    if vm._blockdef is not None:
        vm.blocks[vm._blockdef].append(list(alist))
        return alist
    if etype in ('LINE', 'ARC', 'TEXT', 'CIRCLE', 'ELLIPSE'):
        lay = d.get(8, '0')
        if lay != '0' and lay not in vm.tables['LAYER']:
            raise LispError(f"entmake on missing layer {lay!r}", vm)
    if etype == 'LWPOLYLINE':
        # AutoCAD refuses a polyline of fewer than two vertices and
        # RETURNS NIL rather than erroring, so a routine that builds an
        # empty outline gets a quiet nil back and has to notice.  The VM
        # used to accept it, which hid exactly that class of bug.
        verts = sum(1 for p in alist
                    if (isinstance(p, Dot) and p.a == 10)
                    or (isinstance(p, list) and p and p[0] == 10))
        if verts < 2:
            return NIL
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return e if vm._entmakex else vm.entdata[e]


@bi('entmakex')
def _entmakex(vm, a):
    """Same as entmake but hands back the new entity's name instead of
    its data, which is the whole reason routines reach for it."""
    vm._entmakex = True
    try:
        r = _entmake(vm, a)
    finally:
        vm._entmakex = False
    # a table entry (LAYER, LTYPE) has no ename to give back
    return r if isinstance(r, Ent) else T


@bi('entlast')
def _entlast(vm, a):
    for e in reversed(vm.entities):
        if e not in vm.deleted:
            return e
    return NIL


@bi('entget')
def _entget(vm, a):
    e = a[0]
    if not isinstance(e, Ent):
        raise LispError(f"entget: not an entity: {e!r}", vm)
    if e in vm.deleted:
        return NIL
    # (-1 . <ename>) leads the list in AutoLISP, and it is what entmod
    # follows back to the entity after subst/append have rebuilt it.
    # (5 . handle) rides along the same way AutoCAD's does, unless the
    # entity carries one of its own already.
    # a symbol table record -- a layer, say -- is not in the drawing, but
    # entget reads and entmod writes it just the same: that is how a
    # routine thaws the layer it is about to draw on
    data = vm.entdata.get(e, vm.recdata.get(e))
    if data is None:
        raise LispError(f"entget: no such entity: {e!r}", vm)
    head = [Dot(-1, e)]
    if not any(isinstance(g, Dot) and g.a == 5 for g in data):
        head.append(Dot(5, e.handle))
    return head + data


def _on_locked_layer(vm, e):
    """True when drawing entity E sits on a LOCKED layer: its group 8
    names a layer whose record has bit 4 of group 70 set (the bit
    vla-put-Lock and an entmod of the record both write).  Always False
    for a symbol-table record -- the record is how a layer is unlocked
    -- and for an entity inside a block definition, where AutoCAD's
    rule is not documented.  The layer that counts is the one the
    entity is on NOW, so an entmod that would move it off the locked
    layer is refused as well."""
    if e not in vm.entdata or e in vm.blockof:
        return False
    lay = vm.layer_of(e)
    if not isinstance(lay, str):
        return False
    rec = vm.tablerecs.get('LAYER', {}).get(lay.upper())
    if rec is None:
        return False
    for g in vm.recdata.get(rec, ()):
        if isinstance(g, Dot) and g.a == 70:
            return isinstance(g.b, int) and bool(g.b & 4)
    return False


@bi('entmod')
def _entmod(vm, a):
    """(entmod alist) -- writes the list back to the entity its (-1 .
    ename) names and returns the list; nil, and nothing written, when
    it cannot (AutoLISP Reference: 'If entmod is unable to modify the
    specified entity, the function returns nil').  An erased entity is
    one such, and an entity on a LOCKED layer is the everyday other:
    the VM used to write straight through the lock, so a tool that
    counted every entmod as done read "updated" here over a date still
    standing on the sheet in AutoCAD.  A refusal is logged in
    vm.lock_refusals as ('entmod', ename)."""
    alist = a[0]
    for g in alist or []:
        if isinstance(g, Dot) and g.a == -1 and isinstance(g.b, Ent):
            if g.b in vm.deleted:
                return NIL
            if _on_locked_layer(vm, g.b):
                vm.lock_refusals.append(('entmod', g.b))
                return NIL
            store = vm.recdata if g.b in vm.recdata else vm.entdata
            store[g.b] = [x for x in alist
                          if not (isinstance(x, Dot) and x.a == -1)]
            return alist
    # a list built from scratch, with no (-1 . ename) to follow: nothing
    # to write it back to
    for e, data in vm.entdata.items():
        if data is alist:
            return alist
    return alist


@bi('entdel')
def _entdel(vm, a):
    """(entdel ename) -- erase, or un-erase, one entity.  An attributed
    INSERT (group 66 = 1) owns the ATTRIBs and the SEQEND that follow
    it, and AutoCAD erases them with it -- the tests build such blocks
    as separate entmakes, so the run is toggled here as one, or a
    routine that erases a point block would leave its number attribute
    behind as a live entity the next sweep trips over.

    An entity on a LOCKED layer is not erased: entdel answers nil and it
    stays, attributes and all (logged in vm.lock_refusals as ('entdel',
    ename)).  Only the erase is refused -- whether AutoCAD un-erases on
    a locked layer is not documented, so that toggle still goes
    through."""
    e = a[0]
    if isinstance(e, Ent):
        if e not in vm.deleted and _on_locked_layer(vm, e):
            vm.lock_refusals.append(('entdel', e))
            return NIL
        run = [e]
        if _dxf(vm, e, 0) == 'INSERT' and _dxf(vm, e, 66) == 1:
            try:
                i = vm.entities.index(e)
            except ValueError:
                i = None
            if i is not None:
                for f in vm.entities[i + 1:]:
                    t = _dxf(vm, f, 0)
                    if t not in ('ATTRIB', 'SEQEND'):
                        break
                    run.append(f)
                    if t == 'SEQEND':
                        break
        # which way the toggle goes is decided ONCE, off the INSERT:
        # asking again inside the loop would see the erase just made
        # and put the attributes straight back
        restoring = e in vm.deleted
        for f in run:
            if restoring:
                vm.deleted.discard(f)
            else:
                vm.deleted.add(f)
    return e


@bi('entnext')
def _entnext(vm, a):
    if not a or a[0] is NIL:
        for e in vm.entities:
            if e not in vm.deleted:
                return e
        return NIL
    # inside a block definition entnext walks THAT run, not the drawing
    where = vm.blockof.get(a[0])
    if where is not None:
        name, i = where
        run = _block_chain(vm, name)
        return run[i + 1] if i + 1 < len(run) else NIL
    try:
        i = vm.entities.index(a[0])
    except ValueError:
        return NIL
    for e in vm.entities[i + 1:]:
        if e not in vm.deleted:
            return e
    return NIL


BUILTINS[Sym('entupd')] = lambda vm, a: a[0]
BUILTINS[Sym('handent')] = lambda vm, a: NIL
BUILTINS[Sym('redraw')] = lambda vm, a: NIL


# selection sets (minimal: a python list in disguise)
@bi('ssadd')
def _ssadd(vm, a):
    if not a:
        return ['<ss>']
    ss = a[1]
    ss.append(a[0])
    return ss


def _is_ss(v):
    return isinstance(v, list) and v and v[0] == '<ss>'


@bi('sslength')
def _sslength(vm, a):
    """(sslength ss) -- and NOT (sslength nil).  An empty ssget gives
    nil, not an empty set, so this is the trap LISPLAB teaches by name;
    AutoLISP answers it with "bad argument type: lselsetp nil".  It has
    to be a LispError and not a Python one, because only a LispError
    reaches *error* and only a LispError is caught by
    vl-catch-all-apply -- a TypeError escaping here would take the whole
    test run down instead of the one routine that forgot to check."""
    if not _is_ss(a[0] if a else None):
        raise LispError("sslength: bad argument type: lselsetp "
                        f"{a[0] if a else None!r}", vm)
    return len(a[0]) - 1


@bi('ssname')
def _ssname(vm, a):
    """(ssname ss i) -- the i-th entity, or NIL past the end.  Running
    off the end is not an error in AutoLISP, which is what lets
    (while (setq e (ssname ss i)) ...) terminate; a nil set, though,
    is the same bad argument type sslength refuses."""
    if not _is_ss(a[0] if a else None):
        raise LispError("ssname: bad argument type: lselsetp "
                        f"{a[0] if a else None!r}", vm)
    i = int(num(a[1]))
    return a[0][i + 1] if 0 <= i < len(a[0]) - 1 else NIL


def _dxf(vm, e, code):
    """One DXF group value off an entity, nil when it has no such group."""
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return NIL


def _filt_pairs(a):
    """The DXF filter list out of an ssget argument list, as (code, value)."""
    for x in a:
        if isinstance(x, list) and x and isinstance(x[0], (Dot, list)):
            pairs = []
            for g in x:
                if isinstance(g, Dot):
                    pairs.append((g.a, g.b))
                elif isinstance(g, list) and len(g) >= 2:
                    pairs.append((g[0], g[1]))
            return pairs
    return None


def _filt_one(vm, e, code, want):
    """One (code . value) test.  String values match the way AutoCAD's
    do -- case-insensitively and through wcmatch, so a layer filter of
    "border" finds an entity on "BORDER" and "COVER*" finds them all.
    Everything else compares straight."""
    got = _dxf(vm, e, code)
    if code == 410 and (got is NIL or got is None):
        # 410 is the layout an entity lives in, and AutoCAD reports it
        # for EVERY graphical entity -- "Model" for everything in model
        # space.  The VM models one space and only stamps 410 on the
        # entities that carry it explicitly, so without this default a
        # filter of (410 . "Model") -- the documented way to keep "_X"
        # from sweeping the paper-space tabs, which LISPLAB teaches as
        # a trap to avoid -- matched NOTHING here.  Six tools scope
        # their sweep that way (AutoDim, CDCREATE, PADDLE, POINTRENAMER,
        # xftconv, covercheck); every one of them selected an empty set
        # in the VM while the same code finds the whole drawing in
        # AutoCAD, so the tests were reading the "nothing found" branch
        # and passing on it.
        got = 'Model'
    if isinstance(want, str):
        if not isinstance(got, str):
            return False
        return _wcmatch(vm, [got.upper(), want.upper()]) is not NIL
    return got == want


#: how a -4 grouping operator combines the tests inside it.  <NOT takes
#: exactly one operand in AutoCAD, so "none of them" is the same thing.
_FILT_JOIN = {'OR': any, 'AND': all, 'NOT': lambda r: not any(r),
              'XOR': lambda r: sum(1 for x in r if x) == 1}


def _filt_eval(vm, e, pairs, i=0, stop=None):
    """(does the entity pass?, next index) over a filter list, honouring
    the -4 grouping operators.

    Without these a filter list is one long AND, which is not what
    ABHD's ADAB asks for: its point sweep is an <OR of three <AND
    groups, and read as an AND it matches nothing at all -- so the
    command would look like it found no survey points when the drawing
    is full of them.  An unknown or unbalanced operator raises rather
    than quietly matching, because a filter that silently selects the
    wrong set is the failure this exists to catch."""
    out = []
    while i < len(pairs):
        code, want = pairs[i]
        if code == -4:
            op = str(want).upper()
            if op.startswith('<'):
                if op[1:] not in _FILT_JOIN:
                    raise LispError("ssget: unknown filter operator %r"
                                    % want, vm)
                val, i = _filt_eval(vm, e, pairs, i + 1, op[1:])
                out.append(val)
                continue
            if op.endswith('>'):
                if stop is None or op[:-1] != stop:
                    raise LispError("ssget: %r closes no open filter group"
                                    % want, vm)
                return _FILT_JOIN[stop](out), i + 1
            # a relational operator ("<", ">=", "*") constrains the NEXT
            # pair's comparison; nothing in this tree uses one on a
            # selection filter, so it is passed over rather than guessed
            i += 1
            continue
        out.append(_filt_one(vm, e, code, want))
        i += 1
    if stop is not None:
        raise LispError("ssget: filter group <%s is never closed" % stop, vm)
    return all(out), i


def _filt_hit(vm, e, pairs):
    """Does one entity pass a DXF filter list?"""
    return _filt_eval(vm, e, pairs)[0]


@bi('ssget')
def _ssget(vm, a):
    """(ssget [mode] [pt] [filter]) -- scripted, like every other bit of
    interaction here: the answer is the list of entities the user
    highlighted, or None for "nothing" (Enter, or no pickfirst set when
    the routine asks for "_I").  A DXF filter list is honoured, so a
    routine that lets AutoCAD keep only the LINEs gets only LINEs here.
    Returns nil for an empty result, exactly as AutoLISP does.

    "_X" and "_A" are the exception: in AutoCAD they sweep the database
    and never prompt, so they are answered from the drawing itself
    rather than from the script.  A routine that falls back to
    (ssget "_X") when the user picked nothing must not stall here."""
    mode = ' '.join(x for x in a if isinstance(x, str))
    pairs = _filt_pairs(a)
    if mode.upper().lstrip('_') == 'I' and vm.pickfirst is not None:
        # a routine handed this selection over with sssetfirst; it is
        # consumed once, exactly as AutoCAD's pickfirst set is
        ents = [e for e in vm.pickfirst[1:] if e not in vm.deleted]
        vm.pickfirst = None
    elif mode.upper().lstrip('_') in ('X', 'A'):
        ents = [e for e in vm.entities if e not in vm.deleted]
    else:
        v = vm.pop_script(('ssget ' + mode).strip(), 'ssget')
        if v is None:
            return NIL
        if isinstance(v, Ent):
            v = [v]
        if not isinstance(v, list) or any(not isinstance(e, Ent) for e in v):
            raise LispError(
                f"ssget: scripted answer {v!r} is not an entity or a list "
                f"of them -- the script is out of step with the prompts", vm)
        ents = [e for e in v if e not in vm.deleted]
    if pairs:
        ents = [e for e in ents if _filt_hit(vm, e, pairs)]
    return ['<ss>'] + ents if ents else NIL


@bi('ssmemb')
def _ssmemb(vm, a):
    """(ssmemb ename ss) -- the entity name when it is in the set."""
    return a[0] if (a[1] and a[0] in a[1][1:]) else NIL


@bi('ssdel')
def _ssdel(vm, a):
    """(ssdel ename ss) -- take the entity out of the set, in place as
    AutoLISP does, and hand the set back (nil if it was not in it)."""
    if a[1] and a[0] in a[1][1:]:
        a[1].remove(a[0])
        return a[1]
    return NIL


@bi('sssetfirst')
def _sssetfirst(vm, a):
    """(sssetfirst grip pick) -- highlight a selection and leave it as the
    pickfirst set the NEXT command sees.  The VM has no grips to draw,
    but it does model the handover: a routine that hands its work to
    another command this way has to have that command's (ssget "_I")
    find it."""
    vm.pickfirst = a[1] if len(a) > 1 and a[1] is not NIL else None
    return NIL


BUILTINS[Sym('vlax-ename->vla-object')] = lambda vm, a: a[0]
"""The VM has no separate ActiveX object layer: an entity name stands in
for its VLA object, so routines that convert before calling a method
still line up with the entity the rest of the VM knows."""


@bi('trans')
def _trans(vm, a):
    """(trans pt from to [disp]) -- the VM's world is flat: WCS, UCS and
    every entity's OCS coincide, so this is the identity.  It still
    type-checks the point, which is the failure it exists to catch: nil
    reaching a coordinate transform dies here as it would in AutoCAD."""
    return list(pt(a[0]))


def _dimrot_angle(a):
    """The angle, in radians, of a DIMLINEAR "_R" (Rotated) call --
    None when the call is not a rotated one.  The angle follows the
    keyword as a string, in degrees, exactly as angtos writes it."""
    for i, x in enumerate(a[:-1]):
        if isinstance(x, str) and x.upper().lstrip('_') in ('R', 'ROTATED'):
            try:
                return math.radians(float(a[i + 1]))
            except (TypeError, ValueError):
                return None
    return None


def _line_ends(vm, e):
    """The two ends of a LINE, or (None, None) for anything else."""
    if not isinstance(e, Ent) or e in vm.deleted:
        return None, None
    data = vm.entdata.get(e, [])
    if next((g.b for g in data if isinstance(g, Dot) and g.a == 0), None) \
            != 'LINE':
        return None, None
    ends = {}
    for g in data:
        if isinstance(g, list) and g and g[0] in (10, 11):
            ends[g[0]] = [float(v) for v in g[1:3]]
    return ends.get(10), ends.get(11)


def _move_line_end(vm, e, code, p):
    vm.entdata[e] = [[code, float(p[0]), float(p[1]), 0.0]
                     if isinstance(g, list) and g and g[0] == code else g
                     for g in vm.entdata[e]]


def _fillet_zero(vm, one, two):
    """A zero-radius FILLET between two LINEs: each is trimmed back or
    run on to the point where the two cross, and each keeps the side it
    was picked on -- which is what makes the pick point part of the
    answer and not decoration.  Two lines that never cross (parallel,
    or one of the picks is not a line at all) are left alone, exactly
    as AutoCAD refuses them."""
    (e1, k1), (e2, k2) = one, two
    if e1 is e2:
        return
    a1, b1 = _line_ends(vm, e1)
    a2, b2 = _line_ends(vm, e2)
    if not (a1 and b1 and a2 and b2):
        return
    d1 = [b1[0] - a1[0], b1[1] - a1[1]]
    d2 = [b2[0] - a2[0], b2[1] - a2[1]]
    den = d1[0] * d2[1] - d1[1] * d2[0]
    if abs(den) < 1e-12:                      # parallel: nothing to meet at
        return
    t = ((a2[0] - a1[0]) * d2[1] - (a2[1] - a1[1]) * d2[0]) / den
    x = [a1[0] + d1[0] * t, a1[1] + d1[1] * t]
    for e, a, b, d, k in ((e1, a1, b1, d1, k1), (e2, a2, b2, d2, k2)):
        n = d[0] * d[0] + d[1] * d[1]
        spick = ((k[0] - a[0]) * d[0] + (k[1] - a[1]) * d[1]) / n
        sx = ((x[0] - a[0]) * d[0] + (x[1] - a[1]) * d[1]) / n
        # the end on the far side of the crossing from the pick is the
        # end that moves; the picked side is the side FILLET keeps
        _move_line_end(vm, e, 11 if spick < sx else 10, x)


#: DXF groups that carry a POINT and so travel with a rotation.  210 is
#: the extrusion direction and is deliberately not among them: it says
#: which way the entity's own plane faces, and a turn in that plane
#: leaves it exactly where it was.
_ROT_POINTS = (10, 11, 12, 13, 14, 15, 16, 17)

#: ...and the groups that carry an ANGLE.  entget hands these back in
#: RADIANS (an ARC's ends, a TEXT's or an INSERT's rotation), which is
#: what the tree's own arc readers assume, so the turn is added in
#: radians here too.
_ROT_ANGLES = (50, 51)

#: The one entity whose group 11 is a VECTOR from its group 10 rather
#: than a place in the drawing: an ELLIPSE's major axis.  A vector turns
#: about the origin, never about the base point.
_ROT_RELATIVE = {'ELLIPSE': (11,)}


def _rot_pt(p, base, ca, sa):
    dx, dy = p[0] - base[0], p[1] - base[1]
    return [base[0] + dx * ca - dy * sa,
            base[1] + dx * sa + dy * ca] + list(p[2:])


def _rotate_ss(vm, a):
    """(command "_.ROTATE" ss "" [_non] base angle) -- turn a selection.

    ROTATE is the whole of what a squaring-up tool DOES, so a VM that
    files the call away and leaves the drawing where it was would let
    a tool with the angle's sign backwards pass every test it has.  So
    the geometry really moves: every point group about the base point,
    every angle group by the same turn, and an ELLIPSE's major axis
    about the origin because it is a vector and not a place.

    The angle is read in DEGREES, as AutoCAD reads it off the command
    line -- the caller is responsible for having AUNITS, ANGBASE and
    ANGDIR zeroed, which is the same thing it is responsible for in
    the real editor.
    """
    ss = next((x for x in a if isinstance(x, list) and x and x[0] == '<ss>'),
              None)
    if ss is None:
        return
    base, ang = None, None
    for x in a[1:]:
        if isinstance(x, bool):
            continue
        if isinstance(x, (int, float)):
            ang = float(x)
        elif isinstance(x, str):
            try:
                ang = float(x)
            except ValueError:
                pass
        elif isinstance(x, list) and x and x[0] != '<ss>' \
                and all(isinstance(v, (int, float)) for v in x):
            base = [float(v) for v in x[:2]]
    if base is None or ang is None:
        raise LispError('_.ROTATE: no base point or no angle in %r' % (a,), vm)
    rad = math.radians(ang)
    ca, sa = math.cos(rad), math.sin(rad)
    for e in ss[1:]:
        if e in vm.deleted:
            continue
        rel = _ROT_RELATIVE.get(_dxf(vm, e, 0), ())
        data = vm.entdata.get(e, [])
        for i, g in enumerate(data):
            if isinstance(g, list) and g and g[0] in _ROT_POINTS:
                about = [0.0, 0.0] if g[0] in rel else base
                data[i] = [g[0]] + _rot_pt([float(v) for v in g[1:]],
                                           about, ca, sa)
            elif isinstance(g, Dot) and g.a in _ROT_ANGLES \
                    and isinstance(g.b, (int, float)):
                data[i] = Dot(g.a, g.b + rad)


# command + input
@bi('command')
def _command(vm, a):
    vm.commands.append(list(a))
    # One undo group per command (STANDARDS 5), and the VM keeps the
    # count: _Begin with undo off errors out of the command in AutoCAD,
    # and an _End with no group open is the strict reading of the same
    # mistake -- a handler that closes a group it never opened.  Inside
    # vl-catch-all-apply the raise is swallowed, so a guarded close in
    # a handler stays quiet; what shows is a leftover count, which run()
    # refuses to return with.
    if a and isinstance(a[0], str) and a[0].upper().lstrip('._') == 'UNDO' \
            and len(a) >= 2 and isinstance(a[1], str):
        sub = a[1].upper().lstrip('_')
        if sub == 'BEGIN':
            if not (vm.sysvars.get('UNDOCTL', 5) & 1):
                raise LispError('_.UNDO _Begin with undo off (UNDOCTL bit 1 '
                                'clear) errors out of the command', vm)
            vm.undo_groups += 1
        elif sub == 'END':
            if vm.undo_groups <= 0:
                raise LispError('_.UNDO _End with no group open', vm)
            vm.undo_groups -= 1
    # -DIMSTYLE Restore really does change the current dim style, and
    # code that saves/restores it round-trips through getvar, so the
    # VM has to model it or a wrong-style restore would go unnoticed
    # ROTATE really turns the drawing (see _rotate_ss): a tool whose
    # whole job is the angle it passes here needs the geometry to move
    if a and isinstance(a[0], str) and a[0].upper().lstrip('._') == 'ROTATE':
        _rotate_ss(vm, a)
    if a and a[0] == '_.-DIMSTYLE' and len(a) >= 3 \
            and a[1] in ('_Restore', '_Save'):
        # Save writes the current settings out under a name AND leaves
        # that name current, so a routine that builds a style it needs
        # and dimensions straight afterwards gets the style it built.
        if a[1] == '_Save':
            vm.tables['DIMSTYLE'].add(a[2])
        vm.sysvars['DIMSTYLE'] = a[2]
        vm.dimstyle_log.append(a[2])
    # a dimension command leaves a DIMENSION entity behind, on the
    # current layer and in the current style -- routines that reach for
    # (entlast) afterwards to fix those up need something to find
    if a and a[0] in ('_.DIMALIGNED', '_.DIMLINEAR'):
        pts = [x for x in a[1:] if isinstance(x, list) and len(x) >= 2]
        # DIMLAYER, when the drawing sets it, overrides CLAYER for
        # dimensions -- the very thing a routine has to undo when it
        # wants its dims on a layer of its own choosing
        lay = vm.sysvars.get('DIMLAYER')
        if not (isinstance(lay, str) and lay in vm.tables['LAYER']):
            lay = vm.sysvars.get('CLAYER', '0')
        e = Ent()
        vm.entities.append(e)
        # 410 is the space the dim lives in -- these are made in model
        # space, and routines that re-read the drawing filter on it.
        # DXF 70's low bits are its kind: 0 rotated/linear, 1 aligned.
        # A routine that asks "is this one of the kinds I place?" reads
        # them, so they have to be here too.
        kind = 1 if a[0] == '_.DIMALIGNED' else 0
        vm.entdata[e] = [Dot(0, 'DIMENSION'), Dot(8, lay), Dot(410, 'Model'),
                         Dot(70, kind),
                         Dot(3, vm.sysvars.get('DIMSTYLE', 'STANDARD'))] + \
            [[code] + [float(v) for v in p] for code, p in zip((13, 14, 10), pts)]
        # 42 is the measurement AutoCAD computed.  Aligned dims measure
        # the distance between the two origins; a linear one measures
        # its projection onto the dimension line's axis.
        if len(pts) >= 2:
            p1, p2 = pt(pts[0]), pt(pts[1])
            if kind == 1:
                meas = math.dist(p1[:2], p2[:2])
            elif len(pts) >= 3:
                loc = pt(pts[2])
                dx, dy = abs(p2[0] - p1[0]), abs(p2[1] - p1[1])
                # "_V"/"_H" among the arguments forces the axis, which
                # is how a routine dimensions the drop between two
                # corners that run diagonally to each other
                forced = {x.upper().lstrip('_') for x in a
                          if isinstance(x, str)} & {'V', 'H',
                                                    'VERTICAL',
                                                    'HORIZONTAL'}
                rot = _dimrot_angle(a)
                if forced:
                    meas = dy if forced & {'V', 'VERTICAL'} else dx
                elif rot is not None:
                    # "_R <angle>" turns the dimension line to that
                    # angle; a rotated dim measures the span PROJECTED
                    # onto it, which is how a dim hooked to two points
                    # off the wall still reads the wall's full run
                    meas = abs((p2[0] - p1[0]) * math.cos(rot) +
                               (p2[1] - p1[1]) * math.sin(rot))
                else:
                    # the dim line stands off along whichever axis
                    # separates it from the points; it measures across
                    # the other one
                    off_y = abs(loc[1] - (p1[1] + p2[1]) / 2.0)
                    off_x = abs(loc[0] - (p1[0] + p2[0]) / 2.0)
                    meas = dx if off_y >= off_x else dy
            else:
                meas = math.dist(p1[:2], p2[:2])
            vm.entdata[e].append(Dot(42, meas))
            # 11 is the middle of the text, which starts out in the
            # middle of the measured span -- where AutoCAD centres it
            vm.entdata[e].append(
                [11] + [0.5 * (x + y) for x, y in zip(p1, p2)])
        # "_T <text>" is a text override, and AutoCAD keeps it verbatim
        # in group 1 with "<>" standing in for the measurement
        for i, x in enumerate(a[:-1]):
            if isinstance(x, str) and x.upper() in ('_T', 'T', '_TEXT') \
                    and isinstance(a[i + 1], str):
                vm.entdata[e].append(Dot(1, a[i + 1]))
                break
    # DIMTEDIT re-homes the text: group 11 moves, and group 70 gains bit
    # 128, "text position defined by the user" -- the flag that stops the
    # text springing back to the middle
    if a and a[0] == '_.DIMTEDIT' and isinstance(a[1], Ent):
        loc = [x for x in a[2:] if isinstance(x, list) and len(x) >= 2]
        if loc:
            data = [g for g in vm.entdata[a[1]]
                    if not (isinstance(g, list) and g and g[0] == 11)]
            data = [Dot(g.a, g.b | 128) if isinstance(g, Dot) and g.a == 70
                    else g for g in data]
            vm.entdata[a[1]] = data + [[11] + [float(v) for v in loc[0]]]
    # FILLET at a radius leaves the arc it cut behind as the last
    # entity, which is how a routine gets hold of what it just made.
    # The VM does NOT do that fillet's geometry: the two lines are left
    # exactly as they were and the arc's centre is a stand-in, halfway
    # between the two picks.  What IS real is the radius on it -- the
    # FILLETRAD that reached AutoCAD -- because a routine that sets
    # FILLETRAD and then trusts (entlast) has to be held to both halves
    # of that.
    #
    # FILLET at radius ZERO is the one fillet the VM does for real.  It
    # cuts no arc at all in AutoCAD -- it runs the two objects on, or
    # trims them back, to the point where they cross -- and PADDLE
    # leans on exactly that to close a drafting gap in a perimeter.  A
    # VM that left the lines where they were could not tell a fillet
    # that took from one AutoCAD refused, and PADDLE reports the
    # difference, so the lines move here too.
    if a and a[0] == '_.FILLET':
        picks = [(x[0], pt(x[1])) for x in a[1:]
                 if isinstance(x, list) and len(x) == 2
                 and isinstance(x[0], Ent) and isinstance(x[1], list)]
        rad = float(num(vm.sysvars.get('FILLETRAD', 0)))
        if len(picks) >= 2 and rad == 0.0:
            _fillet_zero(vm, picks[0], picks[1])
        elif len(picks) >= 2:
            p1, q1 = picks[0][1], picks[1][1]
            c = [0.5 * (p1[i] + q1[i]) for i in range(2)]
            e = Ent()
            vm.entities.append(e)
            vm.entdata[e] = [Dot(0, 'ARC'),
                             Dot(8, vm.sysvars.get('CLAYER', '0')),
                             [10] + c + [0.0],
                             Dot(40, rad)]
    # DIMRADIUS: (command "_.DIMRADIUS" (list arc point-on-it) [_T s] loc)
    # A radial dim is group 70 bit 4 with the centre in 10 and the point
    # it was picked at in 15 -- that pair is how the tools recognize one
    # (ad:raddimpts, AutoDim.lsp:312), so it is what the VM writes.
    if a and a[0] == '_.DIMRADIUS':
        arc = next((x[0] for x in a[1:]
                    if isinstance(x, list) and len(x) == 2
                    and isinstance(x[0], Ent)), None)
        on = next((x[1] for x in a[1:]
                   if isinstance(x, list) and len(x) == 2
                   and isinstance(x[0], Ent)), None)
        loc = [x for x in a[2:] if isinstance(x, list) and len(x) >= 2
               and not isinstance(x[0], Ent)]
        if arc is not None and on is not None:
            ctr, rad = None, None
            for g in vm.entdata.get(arc, []):
                if isinstance(g, list) and g and g[0] == 10:
                    ctr = list(g[1:])
                elif isinstance(g, Dot) and g.a == 40:
                    rad = g.b
            if ctr is None:
                ctr = list(pt(on))
            if rad is None:
                rad = math.dist(pt(on)[:2], ctr[:2])
            lay = vm.sysvars.get('DIMLAYER')
            if not (isinstance(lay, str) and lay in vm.tables['LAYER']):
                lay = vm.sysvars.get('CLAYER', '0')
            e = Ent()
            vm.entities.append(e)
            vm.entdata[e] = [Dot(0, 'DIMENSION'), Dot(8, lay),
                             Dot(410, 'Model'), Dot(70, 4),
                             Dot(3, vm.sysvars.get('DIMSTYLE', 'STANDARD')),
                             [10] + [float(v) for v in ctr[:2]] + [0.0],
                             [15] + [float(v) for v in pt(on)[:2]] + [0.0],
                             Dot(40, float(rad)), Dot(42, float(rad))]
            # AutoCAD stores a per-dimension DIMGAP override in xdata,
            # and a NEGATIVE gap is how it draws the text in a BOX --
            # which is what a corner mark's "?" is drawn with.  The VM
            # writes the gap in force under the dimvar's own code so a
            # test can see a boxed dim from an unboxed one.
            gap = vm.sysvars.get('DIMGAP')
            if isinstance(gap, (int, float)):
                vm.entdata[e].append(Dot(147, float(gap)))
            if loc:
                vm.entdata[e].append([11] + [float(v) for v in loc[0]])
            for i, x in enumerate(a[:-1]):
                if isinstance(x, str) and x.upper() in ('_T', 'T', '_TEXT') \
                        and isinstance(a[i + 1], str):
                    vm.entdata[e].append(Dot(1, a[i + 1]))
                    break
    return NIL


@bi('command-s')
def _command_s(vm, a):
    # What command-s may do inside *error* is decided where it is
    # CALLED (VM._handler_gate), not here: a test that swaps its own
    # stand-in in for this builtin keeps the rule.
    return BUILTINS[Sym('command')](vm, a)


@bi('initget')
def _initget(vm, a):
    vm.initget_bits = a[0] if a and isinstance(a[0], (int, float)) else 0
    kws = [x for x in a if isinstance(x, str)]
    vm.initget_kws = kws[0] if kws else ""
    vm.initget_live = True
    return NIL


def _match_kw(vm, v):
    """Match scripted keyword input against the current initget list."""
    for kw in vm.initget_kws.split():
        caps = ''.join(c for c in kw if c.isupper()) or kw
        if v.upper() == kw.upper() or v.upper() == caps.upper():
            return kw
    return None


def _enter(vm, kind, prompt):
    """What Enter answers at an input under the current initget bits.
    Bit 1 refuses it (AutoCAD asks again; the VM cannot, so the script
    is wrong).  But bit 128 'takes precedence over bit 0; if bits 7 and
    0 are set and the user presses Enter, a null string is returned'
    (AutoLISP Reference, initget) -- so (initget 129) or (initget (+ 7
    128)) hands back "" for Enter, which UPADOVER and SPA rely on.
    Without bit 1 Enter is nil.  getpoint and getcorner do not refuse
    under bit 1 alone here -- not modelled yet -- but do return "" under
    1 + 128."""
    bits = vm.initget_bits or 0
    if bits & 1 and bits & 128:
        return ""
    if bits & 1 and kind not in ('getpoint', 'getcorner'):
        raise LispError(f"{kind}: Enter not allowed at {prompt!r}", vm)
    return NIL


@bi('getkword')
def _getkword(vm, a):
    prompt = a[0] if a else ""
    v = _typed(vm, vm.pop_script(prompt, 'getkword'), prompt, 'getkword')
    if v is None:
        return _enter(vm, 'getkword', prompt)
    kw = _match_kw(vm, str(v))
    if kw is None:
        raise LispError(f"getkword: {v!r} not among "
                        f"{vm.initget_kws!r} at {prompt!r}", vm)
    return kw


#: a number as typed at getreal, and at getdist in decimal units:
#: 12, -3, 12.5, .5, 12.  -- and getint's whole number
_DECIMAL = re.compile(r'^\s*[-+]?(?:\d+\.?\d*|\.\d+)\s*$')
_INTEGER = re.compile(r'^\s*[-+]?\d+\s*$')
_SCIENTIFIC = re.compile(r'^\s*[-+]?(?:\d+\.?\d*|\.\d+)[eE][-+]?\d+\s*$')


def _read_number(vm, s, kind, prompt):
    """The number getdist, getreal or getint makes of text S typed at
    it that no keyword took -- or None when S is no number at all, which
    is arbitrary input under initget 128 and refused without it.

    getdist reads 'a number in the AutoCAD current distance units
    format' (AutoLISP Reference, getdist) and always returns a real, so
    in architectural or engineering units (LUNITS 4 / 3) 1/8, 2', 4'6
    and 4'-6-1/2" are distances, read by distof in that mode; fractional
    (5) reads 17-1/2 and 1/2; decimal (2) and scientific (1) read a
    decimal number, and scientific its 1.75E+01 as well.  A decimal
    number is inches in 3, 4 and 5 too, in every spelling of one --
    52.5, .5, 5., -.5 -- so no units format is stricter about it than
    decimal units are.  getint reads
    a whole number and nothing else -- 12.5 is AutoCAD's 'Requires an
    integer value' -- and getreal a decimal one.

    A spelling some OTHER units format reads -- 2' or 1/2 in decimal
    units, 1/2 at a getreal, an exponent anywhere but scientific -- is
    refused as NotModelled: whether AutoCAD takes it there is not
    settled, and a guess either way would decide the test."""
    if kind == 'getint':
        return int(s) if _INTEGER.match(s) else None
    mode = int(vm.sysvars.get('LUNITS') or 2)
    if kind == 'getdist' and mode in (3, 4, 5):
        v = _distof(vm, [s, mode])
        if v is not NIL:
            return v
        # a decimal number is a count of inches in these units however
        # it is spelled: 52.5 reads through distof above, and .5, 5. and
        # -.5 -- AutoCAD's own spellings of a decimal, which distof's
        # feet-inch grammar here does not take -- are the same reading
        if _DECIMAL.match(s):
            return float(s)
    elif _DECIMAL.match(s) or (kind == 'getdist' and mode == 1
                               and _SCIENTIFIC.match(s)):
        return float(s)
    if _SCIENTIFIC.match(s) or any(_distof(vm, [s, m]) is not NIL
                                   for m in (4, 5)):
        where = (f"getdist in LUNITS {mode}" if kind == 'getdist'
                 else "getreal")
        raise NotModelled(
            f"{kind}: {s!r} typed at {prompt!r} -- whether AutoCAD reads "
            f"that spelling at a {where} is not settled, so the VM will "
            f"not guess a number or hand the text back.  Script the "
            f"number, or set LUNITS to the units the spelling is in", vm)
    return None


@bi('getdist')
def _getdist(vm, a, kind='getdist'):
    # getreal shares this (below); KIND is which of the two was called,
    # so a refusal or an exhausted script names the prompt's own input
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = _typed(vm, vm.pop_script(prompt, kind), prompt, kind)
    if v is None:
        return _enter(vm, kind, prompt)
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is not None:
            return kw
        # typed text that is a number IS the number -- initget 128 or
        # not: arbitrary input is what no other reading took ('first
        # honoring any other control bits and listed keywords')
        n = _read_number(vm, v, kind, prompt)
        if n is None:
            # initget bit 128 = arbitrary input: unmatched text comes
            # back as the string itself instead of being rejected
            if vm.initget_bits & 128:
                return v
            raise LispError(f"{kind}: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        v = n
    v = float(v)
    if v == 0 and vm.initget_bits & 2:
        raise LispError(f"{kind}: zero not allowed at {prompt!r}", vm)
    if v < 0 and vm.initget_bits & 4:
        raise LispError(f"{kind}: negative not allowed at {prompt!r}", vm)
    return v


@bi('getint')
def _getint(vm, a):
    # (getint [prompt]) -- a whole number, honouring the same initget
    # bits and keywords getdist does
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = _typed(vm, vm.pop_script(prompt, 'getint'), prompt, 'getint')
    if v is None:
        return _enter(vm, 'getint', prompt)
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is not None:
            return kw
        n = _read_number(vm, v, 'getint', prompt)
        if n is None:
            if vm.initget_bits & 128:
                return v
            raise LispError(f"getint: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        v = n
    v = int(v)
    if v == 0 and vm.initget_bits & 2:
        raise LispError(f"getint: zero not allowed at {prompt!r}", vm)
    if v < 0 and vm.initget_bits & 4:
        raise LispError(f"getint: negative not allowed at {prompt!r}", vm)
    return v


@bi('getpoint')
def _getpoint(vm, a):
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = _typed(vm, vm.pop_script(prompt, 'getpoint'), prompt, 'getpoint')
    if v is None:
        return _enter(vm, 'getpoint', prompt)
    # a scripted NUMBER at a prompt that allows arbitrary input is the
    # drafter typing digits, and AutoCAD hands those back as the text
    # typed, never as a point: "44" is not a coordinate pair.  It is
    # what lets one script feed the same length to a getdist prompt and
    # to the getpoint that replaced it (PERPPTS's ruler prompt)
    if isinstance(v, (int, float)) and not isinstance(v, bool) \
            and vm.initget_bits & 128:
        v = repr(float(v)) if isinstance(v, float) else str(v)
    # a scripted string is keyword input -- getpoint honours initget
    # keywords exactly as getdist does ("Back" at a pick prompt)
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is None:
            # initget bit 128 = arbitrary input: unmatched text comes
            # back as the string itself instead of being rejected.  It
            # is what lets ONE prompt take a click or a typed answer
            # (ABFIND: "Pick the point, or type its number").
            if vm.initget_bits & 128:
                return v
            raise LispError(f"getpoint: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    return list(v)


@bi('getcorner')
def _getcorner(vm, a):
    # (getcorner basept [prompt]) -- the second corner of a window,
    # rubber-banded from BASEPT in AutoCAD; scripted here exactly as a
    # getpoint is: a point, nil for Enter, a string for a keyword
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = _typed(vm, vm.pop_script(prompt, 'getcorner'), prompt, 'getcorner')
    if v is None:
        return _enter(vm, 'getcorner', prompt)
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is None:
            raise LispError(f"getcorner: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    return list(v)


def _getangle(vm, a, kind):
    # (getangle [pt] [msg]) and (getorient [pt] [msg]).  The tree calls
    # neither; they are here so that a spaced answer is refused and an
    # initget spent at them exactly as at every other input.  What they
    # hand back for an angle typed or picked -- radians, after AUNITS,
    # ANGBASE and ANGDIR, getorient ignoring the last two -- is not
    # modelled, so anything but Enter and a keyword is refused as that
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = _typed(vm, vm.pop_script(prompt, kind), prompt, kind)
    if v is None:
        return _enter(vm, kind, prompt)
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is not None:
            return kw
    raise NotModelled(f"{kind} answered {v!r} at {prompt!r}: the VM has "
                      f"no model of the angle AutoCAD would hand back", vm)


@bi('getangle')
def _getangle_bi(vm, a):
    return _getangle(vm, a, 'getangle')


@bi('getorient')
def _getorient_bi(vm, a):
    return _getangle(vm, a, 'getorient')


@bi('getstring')
def _getstring(vm, a):
    # (getstring [cr] [prompt]) -- Enter gives "", never nil.  CR is the
    # first argument when that is not the prompt: non-nil, the answer
    # is a whole line and a space is text in it; otherwise the spacebar
    # ends it, as it ends every other input (AutoLISP Reference,
    # getstring)
    # Of two arguments the first IS cr, whatever its type -- a string
    # is non-nil, so (getstring "" "x") takes a whole line.  A lone
    # argument is the prompt when it is text and cr when it is not.
    # (A symbol is a str in this VM, so "is it text" asks for a str that
    # is not a Sym: the T of (getstring T) is the flag, not the prompt.)
    text = [isinstance(x, str) and not isinstance(x, Sym) for x in a]
    prompt = a[-1] if a and text[-1] else ""
    line = (truthy(a[0]) if len(a) > 1
            else bool(a) and not text[0] and truthy(a[0]))
    v = _typed(vm, vm.pop_script(prompt, 'getstring'), prompt,
               'getstring', line)
    return "" if v is None else str(v)


def _pick(vm, a, kind):
    # (entsel [prompt]), (nentsel [prompt]), (nentselp [prompt]) -- nil
    # when the user just presses Enter, nil with ERRNO 7 for a click
    # that hit nothing (MISS), otherwise (ename point) as AutoLISP
    # returns it.  A scripted list is handed back whole, which is how a
    # test gives nentsel the matrix and inserts of a nested pick.
    prompt = next((x for x in a if isinstance(x, str)), "")
    v = _typed(vm, vm.pop_script(prompt, kind), prompt, kind)
    if v is MISS:
        # ERRNO is written by the miss and by nothing else here: a hit
        # and a keyword leave whatever was there -- a 7 some earlier
        # miss left included -- which is why a pick that tells the two
        # apart zeroes ERRNO right before it asks.  Enter leaves it too,
        # by POLICY: AutoCAD's own code for Enter is 52 and releases
        # differ on writing it, so the VM writes nothing, the reading a
        # pick that skips the zero cannot pass (the module docstring)
        vm.sysvars['ERRNO'] = 7
        return NIL
    if v is None:
        return NIL
    if isinstance(v, Ent):
        return [v, [0.0, 0.0, 0.0]]
    if isinstance(v, str):
        # initget keywords work at entsel too, and AutoCAD hands a typed
        # one straight back as a string -- which is what a routine tests
        # for when it offers a way out of a pick (wcalst.lsp:473).  So a
        # scripted string is a keyword, checked against the live initget
        # list like every other keyword answer.
        kw = _match_kw(vm, v)
        if kw is None:
            raise LispError(f"{kind}: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    return list(v)


@bi('entsel')
def _entsel(vm, a):
    return _pick(vm, a, 'entsel')


@bi('nentsel')
def _nentsel(vm, a):
    return _pick(vm, a, 'nentsel')


@bi('nentselp')
def _nentselp(vm, a):
    # (nentselp [prompt] [pt]) -- given a point it selects THERE and asks
    # the drafter nothing.  What it would find is the drawing's business,
    # which the VM has no model of, so it refuses rather than hand the
    # routine a pick nobody made -- or take one off the script.
    if any(isinstance(x, list) for x in a):
        raise NotModelled(f"nentselp at a given point {a!r}: the VM does "
                          f"not select by point", vm)
    return _pick(vm, a, 'nentselp')


def _wc_re(pat):
    """AutoCAD wcmatch pattern -> regex. Covers the constructs SPA.LSP
    uses (* ? , ~ # @ .) plus ` escaping and [...] character classes
    (with ~ negation and - ranges, XFTCONV's MTEXT-code sniff); enough
    for the taper/grade string sniffing, not a full DWG-name matcher."""
    out, i = [], 0
    while i < len(pat):
        c = pat[i]
        if c == '`' and i + 1 < len(pat):
            out.append(re.escape(pat[i + 1])); i += 2; continue
        if c == '[':
            j = pat.find(']', i + 1)
            if j > i + 1:                   # a real class; [] and a
                body = pat[i + 1:j]         # stray [ stay literal
                neg = body.startswith('~')
                if neg:
                    body = body[1:]
                cls = re.sub(r'([\\^\]])', r'\\\1', body)
                out.append('[' + ('^' if neg else '') + cls + ']')
                i = j + 1
                continue
        if c == '*':
            out.append('.*')
        elif c == '?':
            out.append('.')
        elif c == '#':
            out.append('[0-9]')
        elif c == '@':
            out.append('[A-Za-z]')
        elif c == '.':
            out.append('[^A-Za-z0-9]')
        else:
            out.append(re.escape(c))
        i += 1
    return ''.join(out)


@bi('wcmatch')
def _wcmatch(vm, a):
    s = a[0] if isinstance(a[0], str) else ""
    pat = a[1] if len(a) > 1 and isinstance(a[1], str) else ""
    for alt in pat.split(','):          # comma = alternation
        neg = alt.startswith('~')
        if neg:
            alt = alt[1:]
        hit = re.fullmatch(_wc_re(alt), s) is not None
        if hit != neg:
            return T
    return NIL


BUILTINS[Sym('logior')] = lambda vm, a: _logop(vm, a, lambda x, y: x | y, 0)
# (~ n) is the bitwise NOT -- (logand flags (~ 4)) clears a layer's lock
# bit -- and (lsh n k) shifts left for k > 0, right for k < 0.  Both are
# 32-bit integer operations in AutoLISP; the tree reaches them in the
# locked-layer paths of the review tools, which no suite could run.
BUILTINS[Sym('~')] = lambda vm, a: _i32(~_int(vm, a[0], '~'))
BUILTINS[Sym('lsh')] = lambda vm, a: _i32(
    (_int(vm, a[0], 'lsh') << _int(vm, a[1], 'lsh')) if _int(vm, a[1], 'lsh') >= 0
    else ((_int(vm, a[0], 'lsh') & 0xFFFFFFFF) >> -_int(vm, a[1], 'lsh')))


def _int(vm, v, who):
    if not isinstance(v, int) or isinstance(v, bool):
        raise LispError(f"{who}: bad argument type: fixnump {v!r}", vm)
    return v


def _i32(n):
    n &= 0xFFFFFFFF
    return n - 0x100000000 if n & 0x80000000 else n
BUILTINS[Sym('logand')] = lambda vm, a: _logop(vm, a, lambda x, y: x & y, -1)


def _logop(vm, args, op, unit):
    out = unit
    for v in args:
        if not isinstance(v, (int, float)):
            raise LispError(f"logop: bad argument type: numberp {v!r}", vm)
        out = op(out, int(v))
    return out


BUILTINS[Sym('getreal')] = lambda vm, a: _getdist(vm, a, 'getreal')
# getint is the validated @bi('getint') above -- it honours initget
# bits and keywords exactly as getdist does
BUILTINS[Sym('exit')] = lambda vm, a: (_ for _ in ()).throw(
    LispError("exit called", vm))
@bi('atoms-family')
def _atoms_family(vm, a):
    """(atoms-family fmt [names]) -- the symbols this session has.

    It answered [] until CALVER needed it.  The one thing a support
    call always asks is which versions are loaded, and the build has
    no table of them: every tool sets its own banner global as it
    loads, so the SESSION is the table and this is how it is read.
    Format 0 hands back symbols, 1 hands back strings, and AutoCAD
    upcases either way.  With a name list, only those -- and a name
    the session has not got comes back nil in its own slot, which is
    how a caller tells "not loaded" from "loaded and nil"."""
    fmt = a[0] if a else 0
    have = {str(k).upper() for k in vm.globals}
    have |= {str(k).upper() for k in BUILTINS}
    have |= {str(k).upper() for k in SPECIAL}
    if len(a) > 1 and a[1] is not NIL:
        out = [n.upper() if str(n).upper() in have else None
               for n in a[1]]
        return [NIL if n is None else (Sym(n) if fmt == 0 else n)
                for n in out]
    names = sorted(have)
    return [Sym(n) for n in names] if fmt == 0 else names
# (regapp name) -- registers an xdata application, returns the name.
# Re-registering an app already there is not an error in AutoCAD, so it
# is not one here either.
BUILTINS[Sym('regapp')] = lambda vm, a: (
    vm.tables.setdefault('APPID', set()).add(a[0]) or a[0])
BUILTINS[Sym('vl-load-com')] = lambda vm, a: NIL


def _sort_lt(vm, fn, x, y):
    return truthy(vm.call_value(fn, [x, y]))


def _sort_eq(x, y):
    """The duplicates vl-sort drops: EQ ones.  Two equal integers are EQ
    in AutoLISP, and so are two symbols of one name (nil included); two
    equal reals, strings or lists are not, and survive the sort.  Two
    references to the ONE list or string are EQ too, but whether vl-sort
    drops those is not documented, so they are kept."""
    if type(x) is int and type(y) is int:
        return x == y
    if isinstance(x, Sym) and isinstance(y, Sym):
        return x == y
    return x is NIL and y is NIL


@bi('vl-sort')
def _vl_sort(vm, a):
    """(vl-sort lst less) -- sorted, with an item DROPPED when it is EQ to
    the one before it: '(3 2 1 3) comes back (1 2 3) (the AutoLISP
    Reference's own example), but '(3.0 1.0 3.0) keeps both 3.0s and two
    points that tie on the key both stay -- 'only lists of plain
    integers with duplicate numbers can fall victim'.  The VM used to
    drop every item that merely COMPARED equal, so a sort of points by X
    lost one of two points with the same X here and kept it in AutoCAD,
    and a dedupe of reals that leaned on vl-sort held only here.
    tests/test_lispvm_values.py pins it."""
    fn = a[1]
    ordered = sorted(list(a[0] or []), key=functools.cmp_to_key(
        lambda x, y: -1 if _sort_lt(vm, fn, x, y)
        else (1 if _sort_lt(vm, fn, y, x) else 0)))
    out = []
    for v in ordered:
        if out and _sort_eq(out[-1], v):
            continue                      # EQ to its predecessor
        out.append(v)
    return out or NIL


@bi('vl-sort-i')
def _vl_sort_i(vm, a):
    """(vl-sort-i lst less) -- the INDEXES in sorted order.  Nothing is
    dropped; ties keep their original order."""
    lst = list(a[0] or [])
    fn = a[1]
    idx = sorted(range(len(lst)), key=functools.cmp_to_key(
        lambda i, j: -1 if _sort_lt(vm, fn, lst[i], lst[j])
        else (1 if _sort_lt(vm, fn, lst[j], lst[i]) else i - j)))
    return idx or NIL
# (vl-string-translate source-chars dest-chars str)
BUILTINS[Sym('vl-string-translate')] = lambda vm, a: str(a[2]).translate(
    str.maketrans(str(a[0]), str(a[1])))


# (vl-string-trim char-set str) -- strip any leading and trailing
# characters that appear in char-set.  A date attribute read out of a
# block routinely arrives padded, so the check tools lean on this.
BUILTINS[Sym('vl-string-trim')] = lambda vm, a: str(a[1]).strip(str(a[0]))


# (vl-string->list "AB") -> (65 66) and back again -- the pair every
# text-normalising helper in the check tools is built on.
BUILTINS[Sym('vl-string->list')] = \
    lambda vm, a: [ord(c) for c in str(a[0])] or NIL
BUILTINS[Sym('vl-list->string')] = \
    lambda vm, a: ''.join(chr(int(c)) for c in (a[0] or []))


# (vl-string-search pattern str [start]) -> index of the first hit,
# nil when the pattern is not there.  0 is a real answer, so the miss
# must be NIL by name, never a falsy 0.
@bi('vl-string-search')
def _vl_string_search(vm, a):
    i = str(a[1]).find(str(a[0]), int(a[2]) if len(a) > 2 else 0)
    return i if i >= 0 else NIL


# vl- list functions.  All of them return nil for an empty result, which
# is the whole reason a routine can write (if (vl-remove-if ...) ...).
@bi('vl-remove')
def _vl_remove(vm, a):
    return [x for x in (a[1] or []) if not truthy(_equal(vm, [x, a[0]]))] or NIL


@bi('vl-remove-if')
def _vl_remove_if(vm, a):
    return [x for x in (a[1] or [])
            if not truthy(vm.call_value(a[0], [x]))] or NIL


@bi('vl-remove-if-not')
def _vl_remove_if_not(vm, a):
    return [x for x in (a[1] or [])
            if truthy(vm.call_value(a[0], [x]))] or NIL


@bi('vl-member-if')
def _vl_member_if(vm, a):
    lst = list(a[1] or [])
    for i, x in enumerate(lst):
        if truthy(vm.call_value(a[0], [x])):
            return lst[i:]
    return NIL


@bi('vl-position')
def _vl_position(vm, a):
    for i, x in enumerate(a[1] or []):
        if truthy(_equal(vm, [x, a[0]])):
            return i
    return NIL


@bi('vl-some')
def _vl_some(vm, a):
    for x in (a[1] or []):
        v = vm.call_value(a[0], [x])
        if truthy(v):
            return v
    return NIL


@bi('vl-every')
def _vl_every(vm, a):
    for x in (a[1] or []):
        if not truthy(vm.call_value(a[0], [x])):
            return NIL
    return T


@bi('vl-catch-all-apply')
def _vl_catch_all_apply(vm, a):
    # (vl-catch-all-apply 'function list) -- the list is REQUIRED, even
    # for a function that takes no arguments.  Leaving it off is an
    # error in AutoCAD, and one vl-catch-all-apply cannot catch: it is
    # the call to vl-catch-all-apply itself that is malformed
    if len(a) < 2:
        raise LispError("vl-catch-all-apply: too few arguments", vm)
    vm._catch_depth += 1
    try:
        return vm.call_value(a[0], list(a[1] or []))
    except HandlerAbort:
        raise
    except LispError as e:
        return CaughtError(str(e))
    finally:
        vm._catch_depth -= 1


BUILTINS[Sym('vl-catch-all-error-p')] = lambda vm, a: (
    T if isinstance(a[0], CaughtError) else NIL)
BUILTINS[Sym('vl-catch-all-error-message')] = lambda vm, a: (
    a[0].msg if isinstance(a[0], CaughtError) else "")


# ---------------------------------------------------------------- ActiveX
#
# Just enough of the vla-/vlax- surface for the one thing the drafting
# routines actually use it for: an entity's bounding box.  A vla-object
# here is the ename itself, so the round trip is free and the box is
# computed from the entity's own DXF geometry.

BUILTINS[Sym('vlax-ename->vla-object')] = lambda vm, a: a[0]
BUILTINS[Sym('vlax-vla-object->ename')] = lambda vm, a: a[0]
BUILTINS[Sym('vlax-safearray->list')] = lambda vm, a: a[0]
BUILTINS[Sym('vlax-curve-isclosed')] = lambda vm, a: (
    T if _closed_p(vm, a[0]) else NIL)


def _closed_p(vm, e):
    t = _dxf(vm, e, 0)
    if t in ('CIRCLE', 'ELLIPSE'):
        return True
    if t == 'LWPOLYLINE':
        f = _dxf(vm, e, 70)
        return isinstance(f, (int, float)) and int(f) & 1
    return False


# The rest of the vlax-curve surface: closest point, ends, params and
# lengths for LINE / ARC / CIRCLE / LWPOLYLINE, read straight off the
# DXF store.  Angles are RADIANS - entget's unit, which is what the
# routines' math is written against.  Entities the real functions
# reject (SPLINEs, ELLIPSEs, closed polylines asked for their ends)
# raise here too, so a vl-catch-all-apply wrapper in a tool behaves
# exactly as it does in AutoCAD - and a routine calling one of these
# bare fails loudly instead of silently skipping its audit.  The check
# suites that predate this surface carry the same semantics as
# in-process shims (test_dimcheck.py and siblings); those override
# harmlessly in their own processes.

def _curve_ent(vm, a):
    e = a[0]
    if not isinstance(e, Ent) or e in vm.deleted:
        raise LispError('vlax-curve: not an entity', vm)
    return e


def _curve_arc_geo(vm, e):
    """(centre, radius, start angle, CCW sweep) of an ARC entity."""
    c = pt(_dxf(vm, e, 10))
    r = num(_dxf(vm, e, 40))
    a0 = num(_dxf(vm, e, 50) or 0.0)
    a1 = num(_dxf(vm, e, 51) or 0.0)
    sweep = (a1 - a0) % (2 * math.pi)
    if sweep <= 1e-12:
        sweep = 2 * math.pi
    return (c[0], c[1]), r, a0, sweep


def _curve_arc_pt(c, r, ang):
    return [c[0] + r * math.cos(ang), c[1] + r * math.sin(ang), 0.0]


def _curve_seg_closest(p, a, b):
    ax, ay, bx, by = float(a[0]), float(a[1]), float(b[0]), float(b[1])
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 < 1e-24:
        return [ax, ay, 0.0]
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2
    t = max(0.0, min(1.0, t))
    return [ax + t * dx, ay + t * dy, 0.0]


def _curve_arc_closest(c, r, a0, sweep, p):
    """Closest point on the CCW arc from a0 over sweep: radially when
    the direction lands inside the sweep, else the nearer endpoint."""
    dx, dy = p[0] - c[0], p[1] - c[1]
    if dx * dx + dy * dy < 1e-24:
        return _curve_arc_pt(c, r, a0)
    ang = math.atan2(dy, dx)
    if (ang - a0) % (2 * math.pi) <= sweep:
        return _curve_arc_pt(c, r, ang)
    p1, p2 = _curve_arc_pt(c, r, a0), _curve_arc_pt(c, r, a0 + sweep)
    return p1 if math.dist(p[:2], p1[:2]) <= math.dist(p[:2], p2[:2]) \
        else p2


def _curve_bulge_circle(p1, p2, bulge):
    """Centre, radius and CCW angular interval of one bulged polyline
    segment, either bulge sign; None for a straight (or degenerate)
    segment.  Same construction as _bulge_arc_pts, kept separate
    because this one needs the interval, not the extreme points."""
    inc = 4 * math.atan(bulge)
    ch = math.dist(p1[:2], p2[:2])
    if ch == 0 or abs(math.sin(inc / 2)) < 1e-12:
        return None
    r = abs(ch / (2 * math.sin(inc / 2)))
    mid = ((p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0)
    th = math.atan2(p2[1] - p1[1], p2[0] - p1[0])
    d = (ch / 2.0) / math.tan(inc / 2)
    cx = mid[0] + d * math.cos(th + math.pi / 2)
    cy = mid[1] + d * math.sin(th + math.pi / 2)
    a0 = math.atan2(p1[1] - cy, p1[0] - cx)
    a1 = math.atan2(p2[1] - cy, p2[0] - cx)
    if bulge < 0:
        # drawn clockwise: the point set is the CCW interval a1 -> a0
        a0, a1 = a1, a0
    return (cx, cy), r, a0, (a1 - a0) % (2 * math.pi)


def _curve_poly_segs(vm, e):
    """(p1, p2, bulge) per segment of an LWPOLYLINE, closing edge
    included when the closed bit is set."""
    vs = [pt(v) for v in _all_dxf(vm, e, 10)]
    bs = [num(b) for b in _all_dxf(vm, e, 42)]
    if not vs:
        return []
    n = len(vs)
    last = n if (_closed_p(vm, e) and n > 2) else n - 1
    return [(vs[i], vs[(i + 1) % n], bs[i] if i < len(bs) else 0.0)
            for i in range(last)]


def _curve_closest_on(vm, e, p):
    t = _dxf(vm, e, 0)
    if t == 'LINE':
        return _curve_seg_closest(p, _dxf(vm, e, 10), _dxf(vm, e, 11))
    if t == 'ARC':
        c, r, a0, sw = _curve_arc_geo(vm, e)
        return _curve_arc_closest(c, r, a0, sw, p)
    if t == 'CIRCLE':
        c, r = pt(_dxf(vm, e, 10)), num(_dxf(vm, e, 40))
        dx, dy = p[0] - c[0], p[1] - c[1]
        ln = math.hypot(dx, dy)
        if ln < 1e-12:
            return [c[0] + r, c[1], 0.0]
        return [c[0] + dx / ln * r, c[1] + dy / ln * r, 0.0]
    if t == 'LWPOLYLINE':
        best = None
        for p1, p2, b in _curve_poly_segs(vm, e):
            circ = _curve_bulge_circle(p1, p2, b) if b else None
            q = (_curve_arc_closest(circ[0], circ[1], circ[2], circ[3], p)
                 if circ else _curve_seg_closest(p, p1, p2))
            if best is None or math.dist(p[:2], q[:2]) < \
                    math.dist(p[:2], best[:2]):
                best = q
        if best is None:
            raise LispError('vlax-curve: empty polyline', vm)
        return best
    raise LispError(f'vlax-curve: no curve for {t}', vm)


def _curve_ends(vm, e):
    t = _dxf(vm, e, 0)
    if t == 'LINE':
        p1, p2 = pt(_dxf(vm, e, 10)), pt(_dxf(vm, e, 11))
        return ([p1[0], p1[1], 0.0], [p2[0], p2[1], 0.0])
    if t == 'ARC':
        c, r, a0, sw = _curve_arc_geo(vm, e)
        return _curve_arc_pt(c, r, a0), _curve_arc_pt(c, r, a0 + sw)
    if t == 'LWPOLYLINE' and not _closed_p(vm, e):
        vs = [pt(v) for v in _all_dxf(vm, e, 10)]
        if vs:
            return ([vs[0][0], vs[0][1], 0.0],
                    [vs[-1][0], vs[-1][1], 0.0])
    raise LispError(f'vlax-curve: no ends on {t}', vm)


def _curve_length(vm, e):
    t = _dxf(vm, e, 0)
    if t == 'LINE':
        p1, p2 = pt(_dxf(vm, e, 10)), pt(_dxf(vm, e, 11))
        return math.dist(p1[:2], p2[:2])
    if t == 'ARC':
        _c, r, _a0, sw = _curve_arc_geo(vm, e)
        return r * sw
    if t == 'LWPOLYLINE':
        total = 0.0
        for p1, p2, b in _curve_poly_segs(vm, e):
            circ = _curve_bulge_circle(p1, p2, b) if b else None
            total += circ[1] * circ[3] if circ \
                else math.dist(p1[:2], p2[:2])
        return total
    raise LispError(f'vlax-curve: no length on {t}', vm)


BUILTINS[Sym('vlax-curve-getclosestpointto')] = lambda vm, a: (
    _curve_closest_on(vm, _curve_ent(vm, a), pt(a[1])))
BUILTINS[Sym('vlax-curve-getstartpoint')] = lambda vm, a: (
    _curve_ends(vm, _curve_ent(vm, a))[0])
BUILTINS[Sym('vlax-curve-getendpoint')] = lambda vm, a: (
    _curve_ends(vm, _curve_ent(vm, a))[1])


@bi('vlax-curve-getendparam')
def _curve_end_param(vm, a):
    """An ARC's parameter is its swept angle; everything else here is
    parameterized by distance, exactly as the audit tools assume."""
    e = _curve_ent(vm, a)
    if _dxf(vm, e, 0) == 'ARC':
        return _curve_arc_geo(vm, e)[3]
    return _curve_length(vm, e)


@bi('vlax-curve-getdistatparam')
def _curve_dist_at_param(vm, a):
    e = _curve_ent(vm, a)
    if _dxf(vm, e, 0) == 'ARC':
        return _curve_arc_geo(vm, e)[1] * num(a[1])
    return num(a[1])


@bi('vlax-curve-getpointatdist')
def _curve_point_at_dist(vm, a):
    e, d = _curve_ent(vm, a), num(a[1])
    t = _dxf(vm, e, 0)
    if t == 'ARC':
        c, r, a0, _sw = _curve_arc_geo(vm, e)
        return _curve_arc_pt(c, r, a0 + d / r)
    if t == 'LINE':
        p1, p2 = pt(_dxf(vm, e, 10)), pt(_dxf(vm, e, 11))
        ln = math.dist(p1[:2], p2[:2])
        t01 = 0.0 if ln < 1e-12 else max(0.0, min(1.0, d / ln))
        return [p1[0] + (p2[0] - p1[0]) * t01,
                p1[1] + (p2[1] - p1[1]) * t01, 0.0]
    raise LispError(f'vlax-curve: pointAtDist on {t}', vm)


def _all_dxf(vm, e, code):
    """Every value at one group code, in order -- LWPOLYLINE vertices
    and bulges repeat, and reading only the first would collapse a
    polygon to a point."""
    out = []
    for g in vm.entdata.get(e, []):
        if isinstance(g, Dot) and g.a == code:
            out.append(g.b)
        elif isinstance(g, list) and g and g[0] == code:
            out.append(g[1] if len(g) == 2 else g[1:])
    return out


def _arc_pts(cx, cy, r, a0, a1):
    """The extreme points of a CCW arc: its two ends, plus whichever of
    the four cardinal directions the sweep actually crosses.  Without
    the cardinals a filleted corner's box would stop at the vertices
    and miss the part of the arc that swings past them."""
    out = [(cx + r * math.cos(a0), cy + r * math.sin(a0)),
           (cx + r * math.cos(a1), cy + r * math.sin(a1))]
    sweep = (a1 - a0) % (2 * math.pi)
    for k in range(4):
        ang = k * math.pi / 2
        if ((ang - a0) % (2 * math.pi)) <= sweep:
            out.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return out


def _bulge_arc_pts(p1, p2, bulge):
    """The extreme points of one bulged polyline segment.  bulge is
    tan(theta/4) of the included angle, positive counter-clockwise."""
    inc = 4 * math.atan(bulge)
    c = math.dist(p1[:2], p2[:2])
    if c == 0 or abs(math.sin(inc / 2)) < 1e-12:
        return [p1[:2], p2[:2]]
    r = c / (2 * math.sin(inc / 2))
    mid = ((p1[0] + p2[0]) / 2.0, (p1[1] + p2[1]) / 2.0)
    th = math.atan2(p2[1] - p1[1], p2[0] - p1[0])
    d = (c / 2.0) / math.tan(inc / 2)
    cx = mid[0] + d * math.cos(th + math.pi / 2)
    cy = mid[1] + d * math.sin(th + math.pi / 2)
    a0 = math.atan2(p1[1] - cy, p1[0] - cx)
    a1 = math.atan2(p2[1] - cy, p2[0] - cx)
    return _arc_pts(cx, cy, abs(r), a0, a1)


def _block_pts(vm, name, seen=None):
    """The definition's geometry, in the block's own coordinates.  Each
    sub-entity is read through the same _ent_pts every drawing entity
    uses, by lending it an entdata slot for the length of the call --
    nested INSERTs recurse, and a definition that contains itself stops
    at SEEN instead of running the stack out."""
    seen = set() if seen is None else seen
    if name in seen:
        return []
    seen = seen | {name}
    out = []
    for alist in vm.blocks.get(name, []):
        tmp = Ent()
        vm.entdata[tmp] = list(alist)
        try:
            if _dxf(vm, tmp, 0) == 'INSERT':
                out += _insert_pts(vm, tmp, seen)
            else:
                out += _ent_pts(vm, tmp)
        finally:
            del vm.entdata[tmp]
    return out


def _insert_pts(vm, e, seen=None):
    """An INSERT's extents: its definition's geometry scaled, rotated
    and moved onto the insertion point.  Reading only group 10 -- which
    is what the generic branch below would do -- collapses every block
    reference to a point, and a bounding box measured that way reports
    a zero-size pad as happily as a real one."""
    name = _dxf(vm, e, 2)
    pts = _block_pts(vm, str(name), seen)
    if not pts:
        return []
    ip = pt(_dxf(vm, e, 10))
    xs = _dxf(vm, e, 41)
    ys = _dxf(vm, e, 42)
    xs = num(xs) if isinstance(xs, (int, float)) else 1.0
    ys = num(ys) if isinstance(ys, (int, float)) else 1.0
    rot = _dxf(vm, e, 50)
    rot = num(rot) if isinstance(rot, (int, float)) else 0.0
    c, s = math.cos(rot), math.sin(rot)
    out = []
    for x, y in pts:
        x, y = x * xs, y * ys
        out.append((ip[0] + x * c - y * s, ip[1] + x * s + y * c))
    return out


def _ent_pts(vm, e):
    """Points whose extents are the entity's bounding box.  Text is
    reduced to its insertion point -- the VM has no font metrics, so a
    box around an MTEXT would be a guess dressed as a measurement."""
    t = _dxf(vm, e, 0)
    if t == 'INSERT':
        return _insert_pts(vm, e)
    if t == 'LWPOLYLINE':
        vs = [pt(v) for v in _all_dxf(vm, e, 10)]
        bs = [num(b) for b in _all_dxf(vm, e, 42)]
        if not vs:
            return []
        out = [v[:2] for v in vs]
        n = len(vs)
        last = n if _closed_p(vm, e) else n - 1
        for i in range(last):
            b = bs[i] if i < len(bs) else 0.0
            if b:
                out += _bulge_arc_pts(vs[i], vs[(i + 1) % n], b)
        return out
    if t == 'CIRCLE':
        c, r = pt(_dxf(vm, e, 10)), num(_dxf(vm, e, 40))
        return [(c[0] - r, c[1] - r), (c[0] + r, c[1] + r)]
    if t == 'ARC':
        c, r = pt(_dxf(vm, e, 10)), num(_dxf(vm, e, 40))
        a0 = math.radians(num(_dxf(vm, e, 50) or 0.0))
        a1 = math.radians(num(_dxf(vm, e, 51) or 0.0))
        return _arc_pts(c[0], c[1], r, a0, a1)
    if t == 'ELLIPSE':
        c = pt(_dxf(vm, e, 10))
        mj = pt(_dxf(vm, e, 11))            # major axis, relative to centre
        ratio = num(_dxf(vm, e, 40) or 1.0)
        aa = math.hypot(mj[0], mj[1])
        bb = aa * ratio
        th = math.atan2(mj[1], mj[0])
        dx = math.hypot(aa * math.cos(th), bb * math.sin(th))
        dy = math.hypot(aa * math.sin(th), bb * math.cos(th))
        return [(c[0] - dx, c[1] - dy), (c[0] + dx, c[1] + dy)]
    out = []
    for code in (10, 11, 13, 14):
        v = _dxf(vm, e, code)
        if isinstance(v, list) and len(v) >= 2:
            out.append(pt(v)[:2])
    return out


@bi('vla-getboundingbox')
def _vla_getboundingbox(vm, a):
    """(vla-getboundingbox obj 'll 'ur) -- sets the two symbols to the
    corners and returns nothing, exactly as the real one does.  An
    entity with no usable geometry raises, so the vl-catch-all-apply
    wrapper every caller puts around it does what it is there for."""
    e = a[0]
    pts = _ent_pts(vm, e) if isinstance(e, Ent) and e not in vm.deleted else []
    if not pts:
        raise LispError(f"vla-getboundingbox: no geometry on {e!r}", vm)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    vm.set(a[1], [min(xs), min(ys), 0.0])
    vm.set(a[2], [max(xs), max(ys), 0.0])
    return NIL


@bi('findfile')
def _findfile(vm, a):
    """(findfile name) -- the full path, or nil when the support path
    does not hold it.  Nil is the answer a test wants nearly always: it
    is what sends a routine down its "the file is not installed"
    branch, which is the branch a drafter without the shared drive
    takes.  A suite that needs a hit defines its own findfile, and a
    defun shadows this the way AutoLISP's does.

    Without it PADDLE could not run at all: paddle--ensure-block asks
    for the pad drawing before it does anything else, so c:PADDLE and
    c:TUTORIALPADDLE both died on an undefined function and no suite
    could execute either."""
    name = a[0]
    if not isinstance(name, str) or not name:
        return NIL
    # a file this VM wrote counts as existing.  Without it lzd:free
    # could never see the report it had just written, and two failures
    # in one second took the same name -- the second overwriting the
    # first, with the drafter sending one file believing it was both.
    if name in vm.files:
        return name
    return os.path.abspath(name) if os.path.isfile(name) else NIL


class FileHandle:
    """What (open ...) hands back.  AutoLISP calls the type FILE and
    prints it as #<file "...">; nothing here looks inside one, it is
    only ever passed straight back to write-line / read-line / close."""

    def __init__(self, path, mode):
        self.path = path
        self.mode = mode
        self.lines = []
        self.pos = 0
        self.closed = False

    def __repr__(self):
        return '#<file "%s">' % self.path


def _dirname(p):
    p = str(p).replace('/', '\\')
    i = p.rfind('\\')
    return p[:i] if i > 0 else NIL


@bi('open')
def _open(vm, a):
    """(open path mode) -- a file handle, or NIL when it cannot be
    opened.  The nil is the half that matters: LAZDIAG picks a folder to
    write its report into by trying each candidate and taking the first
    that opens, so a test drives that walk by marking folders read-only
    (vm.readonly_dirs) rather than by chmod on a real one."""
    path = str(a[0])
    mode = str(a[1]).lower() if len(a) > 1 else 'r'
    if mode.startswith('r'):
        if path not in vm.files:
            return NIL
        fh = FileHandle(path, 'r')
        fh.lines = vm.files[path].split('\n')
        if fh.lines and fh.lines[-1] == '':
            fh.lines.pop()
        return fh
    d = _dirname(path)
    if d is not NIL and d in vm.readonly_dirs:
        return NIL
    if mode.startswith('a') and path in vm.files:
        fh = FileHandle(path, 'a')
        fh.lines = vm.files[path].split('\n')
        if fh.lines and fh.lines[-1] == '':
            fh.lines.pop()
        return fh
    return FileHandle(path, 'w')


@bi('write-line')
def _write_line(vm, a):
    """(write-line s [file]) -- with no file it goes to the screen, the
    way princ does; with one it is a line of the file being built."""
    s = a[0] if isinstance(a[0], str) else str(a[0])
    if len(a) < 2 or a[1] is NIL:
        vm.printed.append(s + "\n")
        return a[0]
    fh = a[1]
    if not isinstance(fh, FileHandle) or fh.closed:
        raise LispError("write-line: not an open file handle", vm)
    fh.lines.append(s)
    # visible before the close, so a test that never closes (a report
    # cut short by a second error) still sees what got as far as the file
    vm.files[fh.path] = "\n".join(fh.lines) + "\n"
    return a[0]


@bi('read-line')
def _read_line(vm, a):
    """(read-line file) -- the next line, NIL at the end."""
    fh = a[0] if a else NIL
    if not isinstance(fh, FileHandle):
        return NIL
    if fh.pos >= len(fh.lines):
        return NIL
    fh.pos += 1
    return fh.lines[fh.pos - 1]


@bi('close')
def _close(vm, a):
    fh = a[0] if a else NIL
    if isinstance(fh, FileHandle):
        if fh.mode != 'r':
            vm.files[fh.path] = ("\n".join(fh.lines) + "\n"
                                 if fh.lines else "")
        fh.closed = True
    return NIL


@bi('vl-filename-directory')
def _vl_filename_directory(vm, a):
    d = _dirname(a[0])
    return d if d is not NIL else ""


@bi('vl-filename-base')
def _vl_filename_base(vm, a):
    p = str(a[0]).replace('/', '\\')
    p = p[p.rfind('\\') + 1:]
    i = p.rfind('.')
    return p[:i] if i > 0 else p


@bi('vl-filename-extension')
def _vl_filename_extension(vm, a):
    p = str(a[0]).replace('/', '\\')
    p = p[p.rfind('\\') + 1:]
    i = p.rfind('.')
    return p[i:] if i > 0 else NIL


@bi('vl-mkdir')
def _vl_mkdir(vm, a):
    """(vl-mkdir dir) -- T when it was made or is already there, nil
    when it could not be.  A read-only parent refuses, which is what
    sends LAZDIAG on to the next candidate folder."""
    d = str(a[0]).rstrip('\\/')
    if _dirname(d) in vm.readonly_dirs or d in vm.readonly_dirs:
        return NIL
    vm.dirs.add(d)
    return T


@bi('vl-file-directory-p')
def _vl_file_directory_p(vm, a):
    d = str(a[0]).rstrip('\\/')
    return T if d in vm.dirs else NIL


@bi('vl-file-size')
def _vl_file_size(vm, a):
    """(vl-file-size path) -- bytes, or nil when there is no such file.
    Reads vm.files for the same reason findfile does: the log LAZDIAG
    rolls when it outgrows its cap is a file the VM itself wrote, and a
    size of nil would mean it never rolled."""
    name = str(a[0]) if a else ""
    if name in vm.files:
        return len(vm.files[name].encode("utf-8", "replace"))
    try:
        return os.path.getsize(name)
    except OSError:
        return NIL


@bi('vl-file-systime')
def _vl_file_systime(vm, a):
    return NIL


@bi('getenv')
def _getenv(vm, a):
    """(getenv name) -- an AutoCAD environment string, nil when unset.
    Per-VM, not the process environment: a test must not read whatever
    the machine running it happens to have exported."""
    return vm.env.get(str(a[0]), NIL)


@bi('setenv')
def _setenv(vm, a):
    """(setenv name value) -- stores it, and returns the value the way
    the real one does.  Values are always strings in AutoCAD, so a
    number written here reads back as its printed form, which is the
    round-trip a routine that stores a setting depends on."""
    v = a[1]
    vm.env[str(a[0])] = v if isinstance(v, str) else _rtos_default(v)
    return v


def _rtos_default(v):
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


@bi('*push-error-using-command*')
def _push_error_using_command(vm, a):
    vm.error_mode_depth += 1
    return T


@bi('*pop-error-mode*')
def _pop_error_mode(vm, a):
    if vm.error_mode_depth <= 0:
        vm.error_mode_underflow += 1
    else:
        vm.error_mode_depth -= 1
    return T


# The blackboard: vl-bb-ref / vl-bb-set are the one namespace every
# document of an AutoCAD session shares (LISP globals are per document).
# Module-level on purpose, so it survives a fresh VM() the way it
# survives a second drawing being opened -- a test that stands for a
# NEW session calls reset_blackboard() first.
BLACKBOARD = {}


def reset_blackboard():
    BLACKBOARD.clear()


@bi('vl-bb-ref')
def _vl_bb_ref(vm, a):
    return BLACKBOARD.get(a[0], NIL)


@bi('vl-bb-set')
def _vl_bb_set(vm, a):
    BLACKBOARD[a[0]] = a[1]
    return a[1]


# The document, its undo marks, the layer collection and the entity
# properties the cleanup tools drive through ActiveX.  A vla-object is
# still the ename (or the layer's table record), so a property put
# lands in the same alist entget reads.
ACAD_OBJECT = '<acad-object>'
ACTIVE_DOCUMENT = '<active-document>'
LAYER_COLLECTION = '<layers>'
DIMSTYLE_COLLECTION = '<dimstyles>'

BUILTINS[Sym('vlax-get-acad-object')] = lambda vm, a: ACAD_OBJECT


@bi('vla-get-activedocument')
def _vla_get_activedocument(vm, a):
    if a[0] != ACAD_OBJECT:
        raise LispError('vla-get-ActiveDocument: not the application '
                        f'object: {a[0]!r}', vm)
    return ACTIVE_DOCUMENT


def _doc(vm, a, who):
    if not a or a[0] != ACTIVE_DOCUMENT:
        raise LispError(f'{who}: not the active document: '
                        f'{a[0] if a else None!r}', vm)


@bi('vla-startundomark')
def _vla_startundomark(vm, a):
    _doc(vm, a, 'vla-StartUndoMark')
    vm.undo_marks += 1
    vm.undo_log.append('start')
    return NIL


@bi('vla-endundomark')
def _vla_endundomark(vm, a):
    """Closing a mark nothing opened is the ActiveX error a handler
    trips over when the failure came before StartUndoMark -- so it
    throws here, and a handler that does not guard the close fails
    the test instead of the drafter."""
    _doc(vm, a, 'vla-EndUndoMark')
    if vm.undo_marks <= 0:
        raise LispError('vla-EndUndoMark: no undo mark is open', vm)
    vm.undo_marks -= 1
    vm.undo_log.append('end')
    return NIL


@bi('vla-get-layers')
def _vla_get_layers(vm, a):
    _doc(vm, a, 'vla-get-Layers')
    return LAYER_COLLECTION


@bi('vla-get-dimstyles')
def _vla_get_dimstyles(vm, a):
    _doc(vm, a, 'vla-get-DimStyles')
    return DIMSTYLE_COLLECTION


@bi('vla-put-activedimstyle')
def _vla_put_activedimstyle(vm, a):
    """(vla-put-ActiveDimStyle doc style) -- the way a routine makes a
    style whose name CONTAINS A SPACE current, which -DIMSTYLE cannot
    be typed to do (the space reads as ENTER).  It lands in the same
    DIMSTYLE sysvar and the same log as the command form, so a test
    sees the two spellings alike."""
    _doc(vm, a, 'vla-put-ActiveDimStyle')
    name = a[1][1] if isinstance(a[1], tuple) else a[1]
    name = str(name)
    if name not in vm.tables['DIMSTYLE']:
        raise LispError(f'vla-put-ActiveDimStyle: no dim style {name!r}', vm)
    vm.sysvars['DIMSTYLE'] = name
    vm.dimstyle_log.append(name)
    return NIL


@bi('vla-item')
def _vla_item(vm, a):
    """(vla-Item layers name) -- the layer's table record, the same one
    tblobjname hands out, so a Lock put here shows in group 70 there.
    A name the table does not hold throws, as the real collection's
    Key-not-found does."""
    if a[0] == DIMSTYLE_COLLECTION:
        # the DimStyles collection answers with the style itself, and
        # a style is nothing but its name here
        if str(a[1]) not in vm.tables['DIMSTYLE']:
            raise LispError(f'vla-Item: no dim style named {a[1]!r}', vm)
        return (DIMSTYLE_COLLECTION, str(a[1]))
    if a[0] == BLOCK_COLLECTION:
        # the Blocks collection answers with the DEFINITION, not with
        # anything in the drawing -- what PADDLE deletes to drop the
        # throwaway definition its file import leaves behind
        if str(a[1]) not in vm.tables.get('BLOCK', set()):
            raise LispError(f'vla-Item: no block named {a[1]!r}', vm)
        return BlockDef(str(a[1]))
    if a[0] != LAYER_COLLECTION:
        raise LispError(f'vla-Item: unsupported collection {a[0]!r}', vm)
    rec = _tblobjname(vm, ['LAYER', a[1]])
    if rec is NIL:
        raise LispError(f'vla-Item: no layer named {a[1]!r}', vm)
    return rec


def _alist_of(vm, e, who):
    data = vm.entdata.get(e, vm.recdata.get(e)) if isinstance(e, Ent) \
        else None
    if data is None or e in vm.deleted:
        raise LispError(f'{who}: not an entity: {e!r}', vm)
    return data


def _dxf_put(vm, e, code, val, who):
    data = _alist_of(vm, e, who)
    for i, g in enumerate(data):
        if isinstance(g, Dot) and g.a == code:
            data[i] = Dot(code, val)
            return val
        if isinstance(g, list) and g and g[0] == code:
            data[i] = Dot(code, val)
            return val
    data.append(Dot(code, val))
    return val


def _group(vm, e, code, who):
    """One DXF group off an entity OR a table record -- _dxf reads the
    drawing only, and a layer's lock bit lives in its record."""
    for g in _alist_of(vm, e, who):
        if isinstance(g, Dot) and g.a == code:
            return g.b
        if isinstance(g, list) and g and g[0] == code:
            return g[1] if len(g) == 2 else g[1:]
    return NIL


def _flags(vm, e, who):
    v = _group(vm, e, 70, who)
    return v if isinstance(v, int) else 0


@bi('vla-get-lock')
def _vla_get_lock(vm, a):
    _alist_of(vm, a[0], 'vla-get-Lock')
    return Sym(':vlax-true') if _flags(vm, a[0], 'vla-get-Lock') & 4 \
        else Sym(':vlax-false')


@bi('vla-put-lock')
def _vla_put_lock(vm, a):
    f = _flags(vm, a[0], 'vla-put-Lock')
    on = a[1] == Sym(':vlax-true')
    _dxf_put(vm, a[0], 70, (f | 4) if on else (f & ~4), 'vla-put-Lock')
    name = _group(vm, a[0], 2, 'vla-put-Lock')
    vm.lock_log.append((str(name).upper(), on))
    return NIL


#: The layout, its block (model space) and the block-definition
#: collection.  PADDLE is the one tool that reaches the drawing through
#: this path instead of entmake: it asks the layout for its block and
#: hands that to vla-InsertBlock.  Without these the whole routine --
#: c:PADDLE and c:TUTORIALPADDLE both -- was unrunnable here, which is
#: why tests/test_cancel_paths.py had to carry a NEEDS_ACTIVEX exemption
#: for it and no suite ever executed either command.
LAYOUT_OBJECT = '<active-layout>'
MODEL_SPACE = '<model-space>'
BLOCK_COLLECTION = '<blocks>'


class BlockDef:
    """One entry of the Blocks collection.  vla-Item hands it out and
    vla-Delete drops the definition it names."""
    __slots__ = ('name',)

    def __init__(self, name):
        self.name = name

    def __repr__(self):
        return f"<block {self.name!r}>"


@bi('vla-get-activelayout')
def _vla_get_activelayout(vm, a):
    _doc(vm, a, 'vla-get-ActiveLayout')
    return LAYOUT_OBJECT


@bi('vla-get-block')
def _vla_get_block(vm, a):
    """(vla-get-Block layout) -- the block a layout draws into, i.e.
    model space when TILEMODE is on.  Only the layout has one; asking
    the document is the mistake that reads as nil in AutoLISP and then
    fails one call later, so it throws here instead."""
    if not a or a[0] != LAYOUT_OBJECT:
        raise LispError('vla-get-Block: not a layout: '
                        f'{a[0] if a else None!r}', vm)
    return MODEL_SPACE


@bi('vla-get-blocks')
def _vla_get_blocks(vm, a):
    _doc(vm, a, 'vla-get-Blocks')
    return BLOCK_COLLECTION


@bi('vla-add')
def _vla_add(vm, a):
    """(vla-Add layers name) -- the collection's Add.  AutoCAD hands
    back the EXISTING record when the name is already taken rather than
    erroring, so a routine that adds a layer it may already have does
    not need to look first."""
    if not a or a[0] != LAYER_COLLECTION:
        raise LispError(f'vla-Add: unsupported collection '
                        f'{a[0] if a else None!r}', vm)
    name = str(a[1])
    rec = _tblobjname(vm, ['LAYER', name])
    if rec is not NIL:
        return rec
    _entmake(vm, [[Dot(0, 'LAYER'), Dot(100, 'AcDbSymbolTableRecord'),
                   Dot(100, 'AcDbLayerTableRecord'), Dot(2, name),
                   Dot(70, 0), Dot(62, 7), Dot(6, 'Continuous')]])
    return _tblobjname(vm, ['LAYER', name])


@bi('vla-insertblock')
def _vla_insertblock(vm, a):
    """(vla-InsertBlock space point name xs ys zs rot) -- one INSERT in
    model space, returned as its ename so a vla-put-Layer lands in the
    same alist entget reads.  A name the block table does not hold
    throws, exactly as the real call's "Key not found" does: inserting a
    block that was never defined is the failure paddle--ensure-block
    exists to prevent, and swallowing it here would hide that."""
    if not a or a[0] != MODEL_SPACE:
        raise LispError('vla-InsertBlock: not a space: '
                        f'{a[0] if a else None!r}', vm)
    ip = pt(a[1])
    name = str(a[2])
    if name not in vm.tables.get('BLOCK', set()):
        raise LispError(f'vla-InsertBlock: no block named {name!r}', vm)
    xs, ys, zs = (num(a[3]), num(a[4]), num(a[5])) if len(a) > 5 \
        else (1.0, 1.0, 1.0)
    rot = num(a[6]) if len(a) > 6 else 0.0
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(2, name), Dot(8, vm.sysvars['CLAYER']),
                     [10, ip[0], ip[1], ip[2] if len(ip) > 2 else 0.0],
                     Dot(41, xs), Dot(42, ys), Dot(43, zs),
                     Dot(50, rot), Dot(66, 0)]
    return e


@bi('vla-delete')
def _vla_delete(vm, a):
    """Erase an entity, or drop a block definition.  Unlike entdel this
    one does not toggle: a second Delete on the same object is the
    ActiveX error a caller wraps in vl-catch-all-apply."""
    o = a[0]
    if isinstance(o, BlockDef):
        if o.name not in vm.tables.get('BLOCK', set()):
            raise LispError(f'vla-Delete: block {o.name!r} is already gone', vm)
        vm.tables['BLOCK'].discard(o.name)
        vm.blocks.pop(o.name, None)
        return NIL
    if isinstance(o, Ent) and o in vm.entdata and o not in vm.deleted:
        vm.deleted.add(o)
        return NIL
    raise LispError(f'vla-Delete: not a live object: {o!r}', vm)


@bi('vlax-3d-point')
def _vlax_3d_point(vm, a):
    """(vlax-3d-point x y [z]) or (vlax-3d-point pt).  The real one
    returns a variant; every caller here feeds it straight back to an
    ActiveX method, so the point itself stands in for it."""
    if len(a) == 1:
        p = pt(a[0])
        return [num(p[0]), num(p[1]), num(p[2]) if len(p) > 2 else 0.0]
    return [num(a[0]), num(a[1]), num(a[2]) if len(a) > 2 else 0.0]


#: entity property -> DXF group, for the generic get/put pairs
VLA_PROPS = {
    'layer': 8, 'color': 62, 'linetype': 6, 'lineweight': 370,
    'stylename': 7, 'height': 40, 'rotation': 50, 'textstring': 1,
}


def _vla_getter(prop, code):
    def get(vm, a):
        v = _group(vm, a[0], code, 'vla-get-' + prop)
        if v is NIL or v is None:
            # the defaults AutoCAD reports for a group the alist omits
            v = {8: '0', 62: 256, 6: 'ByLayer', 370: -1, 7: 'Standard',
                 40: 0.0, 50: 0.0, 1: ''}[code]
        return v
    return get


def _vla_putter(prop, code):
    def put(vm, a):
        who = 'vla-put-' + prop
        val = a[1]
        if code == 8:
            if val not in vm.tables['LAYER'] and val != '0':
                raise LispError(f'{who}: no layer named {val!r}', vm)
        if code == 7:
            names = {x.upper() for x in vm.tables.get('STYLE', set())}
            if str(val).upper() not in names:
                raise LispError(f'{who}: no text style named {val!r}', vm)
        _dxf_put(vm, a[0], code, val, who)
        return NIL
    return put


for _prop, _code in VLA_PROPS.items():
    BUILTINS[Sym('vla-get-' + _prop)] = _vla_getter(_prop, _code)
    BUILTINS[Sym('vla-put-' + _prop)] = _vla_putter(_prop, _code)


# vl-sort / vl-sort-i live with the other vl- builtins above.  A second
# registration used to sit here that KEPT items comparing equal --
# BUILTINS is a plain dict, so it silently won over the faithful one,
# and the one test that cared had to patch the VM.  There is exactly one
# vl-sort now, and it drops EQ duplicates like AutoCAD's.
