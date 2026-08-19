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

Interaction is scripted: getdist / getkword / getpoint / getreal pop
answers from a queue.  Numbers are distances, strings are keywords,
None is Enter.  Running out of script, or ending with script left
over, is a test failure -- the prompt log tells you where.
"""

import math
import re


class LispError(Exception):
    def __init__(self, msg, vm=None):
        if vm is not None and vm.prompts:
            msg += "\n  last prompts:\n    " + "\n    ".join(
                f"{p!r} -> {a!r}" for p, a in vm.prompts[-8:])
        super().__init__(msg)


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
        self.script = []
        self.prompts = []        # (prompt, answer) log
        self.commands = []       # every (command ...) call
        self.dimstyle_log = []   # every dim style made current, in order
        self.entities = []       # Ent -> alist, in creation order
        self.entdata = {}
        self.deleted = set()
        self.initget_kws = ""
        self.initget_bits = 0
        self.sysvars = {
            'CMDECHO': 1, 'OSMODE': 4133, 'CLAYER': '0', 'LUNITS': 2,
            'LTSCALE': 1.0, 'UNDOCTL': 5, 'MIRRTEXT': 1,
            'DIMSTYLE': 'STANDARD',
        }
        self.tables = {'LAYER': set(), 'LTYPE': {'CONTINUOUS'},
                       'DIMSTYLE': {'STANDARD'}}

    # ---------------- scripted input
    def pop_script(self, prompt, kind):
        if not self.script:
            raise LispError(f"SCRIPT EXHAUSTED at {kind} prompt: {prompt!r}",
                            self)
        v = self.script.pop(0)
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
        try:
            r = NIL
            for form in body:
                r = self.eval(form)
            return r
        finally:
            self.stack.pop()

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
        self.loads(open(path).read())

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
        r = self.call_defun(Sym(name.lower()), fn, [])
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
            'while', 'repeat', 'foreach', 'defun']}


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


def _cmp(op, args):
    for x, y in zip(args, args[1:]):
        if isinstance(x, str) and isinstance(y, str):
            if not op(x, y):
                return NIL
        elif x is NIL or y is NIL:
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
BUILTINS[Sym('=')] = lambda vm, a: _cmp(lambda x, y: x == y, a)
BUILTINS[Sym('/=')] = lambda vm, a: _cmp(lambda x, y: x != y, a)
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
BUILTINS[Sym('logand')] = lambda vm, a: (int(a[0]) & int(a[1])
                                         if len(a) == 2 else 0)
BUILTINS[Sym('gcd')] = lambda vm, a: math.gcd(int(a[0]), int(a[1]))
BUILTINS[Sym('distance')] = lambda vm, a: math.dist(pt(a[0])[:2],
                                                    pt(a[1])[:2])
BUILTINS[Sym('angle')] = lambda vm, a: math.atan2(
    pt(a[1])[1] - pt(a[0])[1], pt(a[1])[0] - pt(a[0])[0]) % (2 * math.pi)
BUILTINS[Sym('polar')] = lambda vm, a: [pt(a[0])[0] + a[2] * math.cos(a[1]),
                                        pt(a[0])[1] + a[2] * math.sin(a[1])]

# strings
BUILTINS[Sym('strcat')] = lambda vm, a: ''.join(a)
BUILTINS[Sym('strlen')] = lambda vm, a: len(a[0]) if a else 0
BUILTINS[Sym('itoa')] = lambda vm, a: str(int(num(a[0])))
BUILTINS[Sym('atoi')] = lambda vm, a: int(a[0]) if re.match(r'^[+-]?\d+',
                                                            a[0]) else 0
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


@bi('rtos')
def _rtos(vm, a):
    v = num(a[0])
    prec = int(a[2]) if len(a) > 2 else 4
    return f"{v:.{prec}f}"


BUILTINS[Sym('angtos')] = lambda vm, a: f"{num(a[0]):.6f}"

# io
BUILTINS[Sym('princ')] = lambda vm, a: (a[0] if a else NIL)
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
    table, name = a[0].upper(), a[1].upper()
    if name in {x.upper() for x in vm.tables.get(table, set())}:
        return [[0, table], [2, name]]
    return NIL


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
        return alist
    if etype == 'LTYPE':
        vm.tables['LTYPE'].add(d[2])
        return alist
    if etype in ('LINE', 'ARC', 'TEXT', 'CIRCLE', 'ELLIPSE'):
        lay = d.get(8, '0')
        if lay != '0' and lay not in vm.tables['LAYER']:
            raise LispError(f"entmake on missing layer {lay!r}", vm)
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return vm.entdata[e]


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
    # follows back to the entity after subst/append have rebuilt it
    return [Dot(-1, e)] + vm.entdata[e]


@bi('entmod')
def _entmod(vm, a):
    alist = a[0]
    for g in alist or []:
        if isinstance(g, Dot) and g.a == -1 and isinstance(g.b, Ent):
            if g.b in vm.deleted:
                return NIL
            vm.entdata[g.b] = [x for x in alist
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


@bi('ssget')
def _ssget(vm, a):
    """(ssget [mode] [pt] [filter]) -- scripted, like every other bit of
    interaction here: the answer is the list of entities the user
    highlighted, or None for "nothing" (Enter, or no pickfirst set when
    the routine asks for "_I").  A DXF filter list is honoured, so a
    routine that lets AutoCAD keep only the LINEs gets only LINEs here.
    Returns nil for an empty result, exactly as AutoLISP does."""
    mode = ' '.join(x for x in a if isinstance(x, str))
    filt = None
    for x in a:
        if isinstance(x, list) and x and isinstance(x[0], (Dot, list)):
            filt = x
            break
    v = vm.pop_script(('ssget ' + mode).strip(), 'ssget')
    if v is None:
        return NIL
    if isinstance(v, Ent):
        v = [v]
    ents = [e for e in v if e not in vm.deleted]
    if filt:
        pairs = []
        for g in filt:
            if isinstance(g, Dot):
                pairs.append((g.a, g.b))
            elif isinstance(g, list) and len(g) >= 2:
                pairs.append((g[0], g[1]))
        ents = [e for e in ents
                if all(_dxf(vm, e, c) == val for c, val in pairs)]
    return ['<ss>'] + ents if ents else NIL


@bi('trans')
def _trans(vm, a):
    """(trans pt from to [disp]) -- the VM's world is flat: WCS, UCS and
    every entity's OCS coincide, so this is the identity.  It still
    type-checks the point, which is the failure it exists to catch: nil
    reaching a coordinate transform dies here as it would in AutoCAD."""
    return list(pt(a[0]))


# command + input
@bi('command')
def _command(vm, a):
    vm.commands.append(list(a))
    # -DIMSTYLE Restore really does change the current dim style, and
    # code that saves/restores it round-trips through getvar, so the
    # VM has to model it or a wrong-style restore would go unnoticed
    if a and a[0] == '_.-DIMSTYLE' and len(a) >= 3 and a[1] == '_Restore':
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
        vm.entdata[e] = [Dot(0, 'DIMENSION'), Dot(8, lay),
                         Dot(3, vm.sysvars.get('DIMSTYLE', 'STANDARD'))] + \
            [[code] + [float(v) for v in p] for code, p in zip((13, 14, 10), pts)]
    return NIL


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
            raise LispError(f"getdist: keyword {v!r} not among "
                            f"{vm.initget_kws!r} at {prompt!r}", vm)
        return kw
    v = float(v)
    if v == 0 and vm.initget_bits & 2:
        raise LispError(f"getdist: zero not allowed at {prompt!r}", vm)
    if v < 0 and vm.initget_bits & 4:
        raise LispError(f"getdist: negative not allowed at {prompt!r}", vm)
    return v


@bi('getpoint')
def _getpoint(vm, a):
    prompt = a[-1] if a and isinstance(a[-1], str) else ""
    v = vm.pop_script(prompt, 'getpoint')
    if v is None:
        return NIL
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
    return list(v)


def _wc_re(pat):
    """AutoCAD wcmatch pattern -> regex. Covers the constructs SPA.LSP
    uses (* ? , ~ # @ .) plus ` escaping; enough for the taper/grade
    string sniffing, not a full DWG-name matcher."""
    out, i = [], 0
    while i < len(pat):
        c = pat[i]
        if c == '`' and i + 1 < len(pat):
            out.append(re.escape(pat[i + 1])); i += 2; continue
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


BUILTINS[Sym('logior')] = lambda vm, a: _logop(a, lambda x, y: x | y, 0)
BUILTINS[Sym('logand')] = lambda vm, a: _logop(a, lambda x, y: x & y, -1)


def _logop(args, op, unit):
    out = unit
    for v in args:
        out = op(out, int(num(v, 'logop')))
    return out


BUILTINS[Sym('getreal')] = _getdist
BUILTINS[Sym('getint')] = lambda vm, a: vm.pop_script(
    a[0] if a else "", 'getint')
BUILTINS[Sym('exit')] = lambda vm, a: (_ for _ in ()).throw(
    LispError("exit called", vm))
BUILTINS[Sym('atoms-family')] = lambda vm, a: []
BUILTINS[Sym('vl-load-com')] = lambda vm, a: NIL
