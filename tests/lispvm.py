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
  * integer / is integer division; floats propagate.

Interaction is scripted: getdist / getint / getkword / getpoint / getreal pop
answers from a queue.  Numbers are distances, strings are keywords,
None is Enter.  Running out of script, or ending with script left
over, is a test failure -- the prompt log tells you where.
"""

import functools
import math
import os
import re


class LispError(Exception):
    def __init__(self, msg, vm=None):
        if vm is not None and getattr(vm, 'calls', None):
            msg += "\n  in: " + " > ".join(vm.calls[-8:])
        if vm is not None and vm.prompts:
            msg += "\n  last prompts:\n    " + "\n    ".join(
                f"{p!r} -> {a!r}" for p, a in vm.prompts[-8:])
        super().__init__(msg)


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


def parse_all(src):
    tokens = tokenize(src)
    out, k = [], 0
    while k < len(tokens):
        node, k = parse(tokens, k)
        out.append(node)
    return out


def truthy(v):
    return v is not NIL


class VM:
    def __init__(self):
        self.globals = {}
        self.stack = []          # list of dicts (dynamic scope frames)
        self.calls = []          # defun names currently on the stack
        self._entmakex = False   # entmake returning an ename, not a list
        self._blockdef = None    # name of the block being defined, if any
        self.blocks = {}         # block name -> its definition entities
        self.script = []
        self.prompts = []        # (prompt, answer) log
        self.printed = []        # everything princ'd, in order
        self.commands = []       # every (command ...) call
        self.dimstyle_log = []   # every dim style made current, in order
        self.entities = []       # Ent -> alist, in creation order
        self.entdata = {}
        self.deleted = set()
        self.pickfirst = None    # the implied selection sssetfirst
                                 # left for the next command's "_I"
        self.initget_kws = ""
        self.initget_bits = 0
        self.sysvars = {
            'CMDECHO': 1, 'OSMODE': 4133, 'CLAYER': '0', 'LUNITS': 2,
            'LTSCALE': 1.0, 'UNDOCTL': 5, 'MIRRTEXT': 1,
            'DIMSTYLE': 'STANDARD', 'INSUNITS': 1, 'ATTREQ': 1,
            'ATTDIA': 0, 'CMDACTIVE': 0,
            # CDATE is YYYYMMDD.HHMMSS.  A fixed one, not the wall
            # clock: a routine that stamps the date into its output
            # must produce the same output on every run, or the test
            # asserting on it would pass today and fail tomorrow.
            'CDATE': 20260821.143000, 'DATE': 2461274.5,
        }
        # *error* dispatch is OPT-IN (vm.handle_errors = True): with it
        # on, a LispError raised outside vl-catch-all-apply runs the
        # *error* the failing code can see -- dynamically, with every
        # frame still live, so a handler reads its command's locals the
        # way AutoCAD's does -- and then aborts the command, which run()
        # reports as a normal return.  Off, the error propagates as it
        # always has, so the suites that assert on a raised LispError
        # keep their footing.
        self.handle_errors = False
        self.handled_errors = []   # the messages *error* was handed
        self._catch_depth = 0      # inside vl-catch-all-apply: no dispatch
        self._in_handler = False   # a throw inside *error* is not re-handled
        self.undo_marks = 0        # StartUndoMark / EndUndoMark balance
        self.undo_log = []         # 'start' / 'end', in order
        self.lock_log = []         # (layer name, locked?) per vla-put-Lock
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
        if not self.script:
            raise LispError(f"SCRIPT EXHAUSTED at {kind} prompt: {prompt!r}",
                            self)
        v = self.script.pop(0)
        if callable(v):
            # A scripted answer that is a function is CALLED here, with
            # the VM, at the moment the prompt is reached.  That is the
            # only way to answer a prompt about something the run itself
            # drew: a preview a command makes and then asks you to click
            # has no entity name until the command has made it.
            v = v(self)
        self.prompts.append((prompt, v))
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
            special = getattr(self, 'sf_' + head.replace(':', '_')
                              .replace('-', '_').replace('*', '_')
                              .replace('+', 'plus').replace('/', 'slash')
                              .replace('=', 'eq').replace('<', 'lt')
                              .replace('>', 'gt'), None)
            if special is not None and head in SPECIAL:
                return special(x[1:])
            fn = self.get(head)
            if isinstance(fn, tuple) and fn[0] == 'defun':
                return self.call_defun(head, fn,
                                       [self.eval(a) for a in x[1:]])
            # A LOCAL SHADOWS THE FUNCTION OF THE SAME NAME.  Declaring
            # "last" in a defun's local list makes (last ...) inside
            # that call "no function definition: LAST" in AutoCAD, even
            # though last is a built-in -- the local binding is what the
            # name resolves to.  Without this the VM would happily call
            # the built-in and a routine that dies at the command line
            # would pass its tests.
            if self.bound_local(head):
                raise LispError(
                    f"no function definition: {head.upper()} -- it is "
                    f"declared as a local variable (or argument) of the "
                    f"defun being run, which shadows the function",
                    self)
            b = BUILTINS.get(head)
            if b is not None:
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
            # AutoCAD runs *error* at the point of failure, before any
            # frame unwinds -- that is how the handler sees the locals
            # (undo-open, the doc, the layers it unlocked) it has to
            # put right.  The innermost defun is that point; the ones
            # above see the error already handled and just unwind.
            if (self.handle_errors and not self._catch_depth
                    and not self._in_handler
                    and not getattr(e, 'handled', False)):
                h = self.get(Sym('*error*'))
                if (isinstance(h, tuple) and h[0] == 'defun') or (
                        isinstance(h, list) and h and h[0] == 'lambda'):
                    e.handled = True
                    msg = str(e).split('\n')[0]
                    self.handled_errors.append(msg)
                    self._in_handler = True
                    try:
                        self.call_value(h if isinstance(h, list)
                                        else Sym('*error*'), [msg])
                    finally:
                        self._in_handler = False
            raise
        finally:
            self.stack.pop()
            self.calls.pop()

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

    def sf_and(self, a):
        v = T
        for f in a:
            v = self.eval(f)
            if not truthy(v):
                return NIL
        return v

    def sf_or(self, a):
        for f in a:
            v = self.eval(f)
            if truthy(v):
                return v
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
        try:
            r = self.call_defun(Sym(name.lower()), fn, [])
        except LispError as e:
            # the command went through its handler and was aborted --
            # what the user sees is a prompt back, not a crash
            if self.handle_errors and getattr(e, 'handled', False):
                return NIL
            raise
        if self.script:
            raise LispError(
                f"{len(self.script)} scripted answers left over: "
                f"{self.script[:6]!r}", self)
        return r

    def layer_of(self, e):
        for pair in self.entdata.get(e, []):
            if isinstance(pair, Dot) and pair.a == 8:
                return pair.b
            if isinstance(pair, list) and pair and pair[0] == 8:
                return pair[1]
        return NIL


SPECIAL = {Sym(s) for s in
           ['quote', 'function', 'setq', 'if', 'progn', 'cond', 'and', 'or',
            'while', 'repeat', 'foreach', 'defun', 'lambda']}


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
    if isinstance(a, int) and isinstance(b, int):
        if b == 0:
            raise LispError("divide by zero")
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


BUILTINS[Sym('null')] = lambda vm, a: T if a[0] is NIL else NIL
BUILTINS[Sym('not')] = lambda vm, a: T if a[0] is NIL else NIL
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
        return Sym('list')
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
BUILTINS[Sym('read')] = lambda vm, a: parse_all(a[0])[0] if a[0] else NIL

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
BUILTINS[Sym('rem')] = lambda vm, a: num(a[0]) % num(a[1])
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
    quietly stringifying itself."""
    for i, x in enumerate(a):
        if not isinstance(x, str):
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


@bi('distof')
def _distof(vm, a):
    """(distof string [mode]) -- nil when the text is not a distance."""
    try:
        m = re.match(r'\s*[-+]?(\d+\.?\d*|\.\d+)', str(a[0]))
        return float(m.group(0)) if m else NIL
    except (TypeError, ValueError):
        return NIL


@bi('rtos')
def _rtos(vm, a):
    v = num(a[0])
    mode = int(a[1]) if len(a) > 1 else 2
    prec = int(a[2]) if len(a) > 2 else 4
    if mode == 4:
        # architectural: F'-I" with the fraction at 1/2^prec inches,
        # matching AutoCAD's 25'-6 1/2" formatting
        neg = v < 0
        v = abs(v)
        den = 2 ** prec
        total = round(v * den)
        inches, frac = divmod(total, den)
        feet, whole = divmod(inches, 12)
        s = f"{feet}'"
        if frac:
            g = math.gcd(frac, den)
            s += f"-{whole} {frac // g}/{den // g}\""
        else:
            s += f"-{whole}\""
        return ('-' if neg else '') + s
    return f"{v:.{prec}f}"


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
BUILTINS[Sym('prin1')] = lambda vm, a: (a[0] if a else NIL)
BUILTINS[Sym('print')] = lambda vm, a: (a[0] if a else NIL)
BUILTINS[Sym('terpri')] = lambda vm, a: NIL
BUILTINS[Sym('prompt')] = lambda vm, a: NIL


# sysvars, tables
@bi('getvar')
def _getvar(vm, a):
    return vm.sysvars.get(a[0].upper(), 0)


@bi('setvar')
def _setvar(vm, a):
    name = a[0].upper()
    if name == 'CLAYER' and a[1] not in vm.tables['LAYER'] and a[1] != '0':
        raise LispError(f"setvar CLAYER: layer does not exist: {a[1]!r}", vm)
    vm.sysvars[name] = a[1]
    return a[1]


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


@bi('entmod')
def _entmod(vm, a):
    alist = a[0]
    for g in alist or []:
        if isinstance(g, Dot) and g.a == -1 and isinstance(g.b, Ent):
            if g.b in vm.deleted:
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
    e = a[0]
    if isinstance(e, Ent):
        if e in vm.deleted:
            vm.deleted.discard(e)
        else:
            vm.deleted.add(e)
    return e


@bi('entnext')
def _entnext(vm, a):
    if not a or a[0] is NIL:
        for e in vm.entities:
            if e not in vm.deleted:
                return e
        return NIL
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


BUILTINS[Sym('sslength')] = lambda vm, a: len(a[0]) - 1
BUILTINS[Sym('ssname')] = lambda vm, a: a[0][int(a[1]) + 1]


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


def _filt_hit(vm, e, pairs):
    """Does one entity pass a DXF filter list?  String values match the
    way AutoCAD's do -- case-insensitively and through wcmatch, so a
    layer filter of "border" finds an entity on "BORDER" and "COVER*"
    finds them all.  Everything else compares straight."""
    for code, want in pairs:
        got = _dxf(vm, e, code)
        if isinstance(want, str):
            if not isinstance(got, str):
                return False
            if _wcmatch(vm, [got.upper(), want.upper()]) is NIL:
                return False
        elif got != want:
            return False
    return True


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


# command + input
@bi('command')
def _command(vm, a):
    vm.commands.append(list(a))
    # -DIMSTYLE Restore really does change the current dim style, and
    # code that saves/restores it round-trips through getvar, so the
    # VM has to model it or a wrong-style restore would go unnoticed
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
    # FILLET leaves the arc it cut behind as the last entity, which is
    # how a routine gets hold of what it just made.  The VM does NOT do
    # fillet geometry: the two lines are left exactly as they were and
    # the arc's centre is a stand-in, halfway between the two picks.
    # What IS real is the radius on it -- the FILLETRAD that reached
    # AutoCAD -- because a routine that sets FILLETRAD and then trusts
    # (entlast) has to be held to both halves of that.
    if a and a[0] == '_.FILLET':
        picks = [x[1] for x in a[1:]
                 if isinstance(x, list) and len(x) == 2
                 and isinstance(x[0], Ent) and isinstance(x[1], list)]
        if len(picks) >= 2:
            p1, q1 = pt(picks[0]), pt(picks[1])
            c = [0.5 * (p1[i] + q1[i]) for i in range(2)]
            e = Ent()
            vm.entities.append(e)
            vm.entdata[e] = [Dot(0, 'ARC'),
                             Dot(8, vm.sysvars.get('CLAYER', '0')),
                             [10] + c + [0.0],
                             Dot(40, float(num(vm.sysvars.get('FILLETRAD',
                                                              0))))]
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
            if loc:
                vm.entdata[e].append([11] + [float(v) for v in loc[0]])
            for i, x in enumerate(a[:-1]):
                if isinstance(x, str) and x.upper() in ('_T', 'T', '_TEXT') \
                        and isinstance(a[i + 1], str):
                    vm.entdata[e].append(Dot(1, a[i + 1]))
                    break
    return NIL


BUILTINS[Sym('command-s')] = BUILTINS[Sym('command')]


@bi('initget')
def _initget(vm, a):
    vm.initget_bits = a[0] if a and isinstance(a[0], (int, float)) else 0
    kws = [x for x in a if isinstance(x, str)]
    vm.initget_kws = kws[0] if kws else ""
    return NIL


def _match_kw(vm, v):
    """Match scripted keyword input against the current initget list."""
    for kw in vm.initget_kws.split():
        caps = ''.join(c for c in kw if c.isupper()) or kw
        if v.upper() == kw.upper() or v.upper() == caps.upper():
            return kw
    return None


@bi('getkword')
def _getkword(vm, a):
    prompt = a[0] if a else ""
    v = vm.pop_script(prompt, 'getkword')
    if v is None:
        if vm.initget_bits & 1:
            raise LispError(f"getkword: Enter not allowed at {prompt!r}", vm)
        return NIL
    kw = _match_kw(vm, str(v))
    if kw is None:
        raise LispError(f"getkword: {v!r} not among "
                        f"{vm.initget_kws!r} at {prompt!r}", vm)
    return kw


@bi('getdist')
def _getdist(vm, a):
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = vm.pop_script(prompt, 'getdist')
    if v is None:
        if vm.initget_bits & 1:
            raise LispError(f"getdist: Enter not allowed at {prompt!r}", vm)
        return NIL
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is None:
            # initget bit 128 = arbitrary input: unmatched text comes
            # back as the string itself instead of being rejected
            if vm.initget_bits & 128:
                return v
            raise LispError(f"getdist: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    v = float(v)
    if v == 0 and vm.initget_bits & 2:
        raise LispError(f"getdist: zero not allowed at {prompt!r}", vm)
    if v < 0 and vm.initget_bits & 4:
        raise LispError(f"getdist: negative not allowed at {prompt!r}", vm)
    return v


@bi('getint')
def _getint(vm, a):
    # (getint [prompt]) -- a whole number, honouring the same initget
    # bits and keywords getdist does
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = vm.pop_script(prompt, 'getint')
    if v is None:
        if vm.initget_bits & 1:
            raise LispError(f"getint: Enter not allowed at {prompt!r}", vm)
        return NIL
    if isinstance(v, str):
        kw = _match_kw(vm, v)
        if kw is None:
            raise LispError(f"getint: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    v = int(v)
    if v == 0 and vm.initget_bits & 2:
        raise LispError(f"getint: zero not allowed at {prompt!r}", vm)
    if v < 0 and vm.initget_bits & 4:
        raise LispError(f"getint: negative not allowed at {prompt!r}", vm)
    return v


@bi('getpoint')
def _getpoint(vm, a):
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = vm.pop_script(prompt, 'getpoint')
    if v is None:
        return NIL
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


@bi('getstring')
def _getstring(vm, a):
    # (getstring [cr] [prompt]) -- Enter gives "", never nil
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = vm.pop_script(prompt, 'getstring')
    return "" if v is None else str(v)


@bi('entsel')
def _entsel(vm, a):
    # (entsel [prompt]) -- nil when the user just presses Enter,
    # otherwise (ename point) as AutoLISP returns it.
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = vm.pop_script(prompt, 'entsel')
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
            raise LispError(f"entsel: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    return list(v)


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
BUILTINS[Sym('logand')] = lambda vm, a: _logop(vm, a, lambda x, y: x & y, -1)


def _logop(vm, args, op, unit):
    out = unit
    for v in args:
        if not isinstance(v, (int, float)):
            raise LispError(f"logop: bad argument type: numberp {v!r}", vm)
        out = op(out, int(v))
    return out


BUILTINS[Sym('getreal')] = _getdist
# getint is the validated @bi('getint') above -- it honours initget
# bits and keywords exactly as getdist does
BUILTINS[Sym('exit')] = lambda vm, a: (_ for _ in ()).throw(
    LispError("exit called", vm))
BUILTINS[Sym('atoms-family')] = lambda vm, a: []
# (regapp name) -- registers an xdata application, returns the name.
# Re-registering an app already there is not an error in AutoCAD, so it
# is not one here either.
BUILTINS[Sym('regapp')] = lambda vm, a: (
    vm.tables.setdefault('APPID', set()).add(a[0]) or a[0])
BUILTINS[Sym('vl-load-com')] = lambda vm, a: NIL


def _sort_lt(vm, fn, x, y):
    return truthy(vm.call_value(fn, [x, y]))


@bi('vl-sort')
def _vl_sort(vm, a):
    """(vl-sort lst less) -- sorted, with items that compare equal to
    the one before them DROPPED, exactly as the real one does.  Routines
    here lean on that to dedupe as they sort - so the VM has to drop
    them too or a deduping sort would look like it kept everything.
    (LISPLAB's lesson 2 teaches exactly this trap, and its test drives
    this implementation.)"""
    fn = a[1]
    ordered = sorted(list(a[0] or []), key=functools.cmp_to_key(
        lambda x, y: -1 if _sort_lt(vm, fn, x, y)
        else (1 if _sort_lt(vm, fn, y, x) else 0)))
    out = []
    for v in ordered:
        if out and not _sort_lt(vm, fn, out[-1], v) \
               and not _sort_lt(vm, fn, v, out[-1]):
            continue                      # equal to its predecessor
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


def _ent_pts(vm, e):
    """Points whose extents are the entity's bounding box.  Text is
    reduced to its insertion point -- the VM has no font metrics, so a
    box around an MTEXT would be a guess dressed as a measurement."""
    t = _dxf(vm, e, 0)
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


# The document, its undo marks, the layer collection and the entity
# properties the cleanup tools drive through ActiveX.  A vla-object is
# still the ename (or the layer's table record), so a property put
# lands in the same alist entget reads.
ACAD_OBJECT = '<acad-object>'
ACTIVE_DOCUMENT = '<active-document>'
LAYER_COLLECTION = '<layers>'

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


@bi('vla-item')
def _vla_item(vm, a):
    """(vla-Item layers name) -- the layer's table record, the same one
    tblobjname hands out, so a Lock put here shows in group 70 there.
    A name the table does not hold throws, as the real collection's
    Key-not-found does."""
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
# vl-sort now, and it drops equal items like AutoCAD's.
