#!/usr/bin/env python3
"""Static per-file check for the calofin .lsp sources.

For each file given (default: every .lsp under lisp/ and shared/parts/):

  hard failures (exit 1):
    * unbalanced parentheses / an extra ')'
    * an unterminated string literal
    * a bare atom or string at top level -- a torn edit that AutoLISP
      would silently evaluate and swallow (a real drift in a hand-copied
      twin shipped exactly this way)
    * special forms with the wrong shape: (if ...) with more than three
      arguments, (setq ...) with an odd argument count -- both parse
      fine and die at the AutoCAD command line
    * a call to an undefined function in the file's own namespace
    * a quoted 'tool:fn reference to a function the file never defines
      -- the dispatch-table typo no runtime path may ever reach

  advisories (printed, never fatal -- cross-file references make them
  unreliable for the multi-file tools):
    * reads of an own-prefix *global* the file never setqs
    * defuns nothing in the file calls or quotes

Each file is checked on its own; results are prefixed with the filename
when more than one is given.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import (LISP_DIR, PARTS_DIR, ROOT, decomment, lsp_files,
                    read, strip, top_level_forms)


def parse(text):
    """TEXT as nested lists.  A string literal is the token '"'; a
    quoted expression arrives as ['quote', expr]."""
    top = []
    stack = []            # (enclosing list, was the new list quoted?)
    cur = top
    quote_next = False
    i, n = 0, len(text)

    def emit(elem, quoted):
        if quoted:
            cur.append(["quote", elem])
        else:
            cur.append(elem)

    while i < n:
        ch = text[i]
        if ch == '"':
            emit('"', quote_next)
            quote_next = False
            i += 1
        elif ch == "'":
            quote_next = True
            i += 1
        elif ch == "(":
            stack.append((cur, quote_next))
            quote_next = False
            cur = []
            i += 1
        elif ch == ")":
            if stack:
                done = cur
                cur, q = stack.pop()
                if q:
                    cur.append(["quote", done])
                else:
                    cur.append(done)
            i += 1
        elif ch in " \t\r\n":
            i += 1
        else:
            j = i
            while j < n and text[j] not in " \t\r\n()'\"":
                j += 1
            emit(text[i:j], quote_next)
            quote_next = False
            i = j
    return top


class Analysis:
    def __init__(self):
        self.defined = set()      # defun names, lowercased
        self.called = set()       # list heads reached as calls
        self.quoted = set()       # symbols under quote ('tool:fn refs)
        self.setq_targets = set() # every setq target, lowercased
        self.arity = []           # bad special-form shapes


def sym(x):
    return isinstance(x, str) and x != '"'


def walk(form, a):
    """Collect calls/definitions/arity from one expression form."""
    if not isinstance(form, list) or not form:
        return
    head = form[0] if sym(form[0]) else None
    h = head.lower() if head else None

    if h == "quote":
        collect_quoted(form[1] if len(form) > 1 else None, a)
        return
    if h in ("defun", "defun-q"):
        if len(form) > 1 and sym(form[1]):
            a.defined.add(form[1].lower())
        for sub in form[3:]:          # skip the name and the arglist
            walk(sub, a)
        return
    if h == "lambda":
        for sub in form[2:]:          # skip the arglist
            walk(sub, a)
        return
    if h == "setq":
        if (len(form) - 1) % 2:
            a.arity.append("(setq ...) takes pairs, got %d arguments"
                           % (len(form) - 1))
        for k in range(1, len(form), 2):
            if sym(form[k]):
                a.setq_targets.add(form[k].lower())
        for k in range(2, len(form), 2):
            walk(form[k], a)
        return
    if h == "cond":
        # a clause's own head is a TEST -- a bare symbol there is a
        # variable read, not a call
        for clause in form[1:]:
            if isinstance(clause, list):
                for sub in clause:
                    walk(sub, a)
        return
    if h == "if" and len(form) > 4:
        a.arity.append("(if ...) takes 2 or 3 arguments, got %d"
                       % (len(form) - 1))

    if head is not None:
        a.called.add(h)
    for sub in form[1:] if head is not None else form:
        walk(sub, a)


def collect_quoted(x, a):
    if sym(x):
        a.quoted.add(x.lower())
    elif isinstance(x, list):
        for sub in x:
            collect_quoted(sub, a)


def balance(clean):
    """(problems, advisory) from a raw depth scan with line numbers."""
    problems = []
    depth, line = 0, 1
    starts = []
    for ch in clean:
        if ch == "\n":
            line += 1
        elif ch == "(":
            depth += 1
            starts.append(line)
        elif ch == ")":
            if depth == 0:
                problems.append("line %d: extra ')'" % line)
                continue
            depth -= 1
            starts.pop()
    if depth:
        problems.append("unclosed '(' opened at line(s): %s"
                        % ", ".join(str(x) for x in starts[:10]))
    return problems


def stray_top_level(lit):
    """Bare atoms/strings at top level -- always a torn edit here."""
    by_line = {}
    depth, line, i, n = 0, 1, 0, len(lit)
    while i < n:
        ch = lit[i]
        if ch == "\n":
            line += 1
            i += 1
        elif ch == "(":
            depth += 1
            i += 1
        elif ch == ")":
            depth = max(0, depth - 1)
            i += 1
        elif ch in " \t\r'":
            i += 1
        elif depth == 0:
            j = i
            while j < n and lit[j] not in " \t\r\n()'\"":
                j += 1
            tok = lit[i:j] or lit[i]
            if not tok.strip():
                tok = '"'
                j = i + 1
            by_line.setdefault(line, []).append(
                "a string literal" if tok.startswith('"') else repr(tok))
            i = max(j, i + 1)
        else:
            i += 1
    return ["line %d: %s stray at top level - a torn edit AutoLISP would "
            "silently swallow" % (line, ", ".join(toks))
            for line, toks in sorted(by_line.items())]


#: Files that carry no tool banner and answer to no command -- the
#: library and the loader.  Every OTHER .lsp in both tiers is a tool.
LIBRARY_FILES = {"CALOFIN-LIB.lsp", "CALOFIN-LOADER.lsp"}

VERSION_SYM = re.compile(r"\(setq\s+((?:\*|[a-z]+:\*)[\w:-]*version\*)\s")
ERR_DEFUN = re.compile(r"\(defun\s+\*error\*\s")
ERR_SETQ = re.compile(r"\(setq\s+\*error\*\s")


def _form_at(src, i):
    """(start, end) of the parenthesised form opening at or after I."""
    while i < len(src) and src[i] != "(":
        i += 1
    depth, j, instr = 0, i, False
    while j < len(src):
        ch = src[j]
        if instr:
            if ch == "\\":
                j += 2
                continue
            if ch == '"':
                instr = False
        elif ch == '"':
            instr = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return (i, j + 1)
        j += 1
    return (i, len(src))


def house_rules(path, src, problems):
    """The conventions the tree keeps by hand, kept by construction.

    Each of these was a real defect somewhere before it was a rule, and
    each was at zero violations tree-wide when it was written -- a rule
    is added to hold a line already reached, never to declare a backlog.
    """
    body = decomment(src)                 # rules ABOUT strings need them
    name = pathlib.Path(path).name

    # 1. (command ...) inside *error* needs a push declaration, because
    #    AutoCAD 2015+ refuses one otherwise.  command-s does not, which
    #    is why most handlers use it (STANDARDS 5).
    if "*push-error-using-command*" not in body:
        for m in list(ERR_DEFUN.finditer(body)) + list(ERR_SETQ.finditer(body)):
            a, b = _form_at(body, m.start())
            if re.search(r"\(command[\s)]", body[a:b]):
                problems.append(
                    "line %d: *error* calls (command ...) without a "
                    "*push-error-using-command* declaration (STANDARDS 5: "
                    "use command-s, or declare the push)"
                    % (src[:a].count("\n") + 1))

    # 2. A pickfirst probe must come BEFORE the undo group: opening one
    #    is itself a command, and a command clears the pickfirst set.
    for a, b in top_level_forms(body):
        form = body[a:b]
        if not re.match(r"\(defun\s+[cC]:", form):
            continue
        probe = form.find('(ssget "_I"')
        begin = form.find('"_Begin"')
        if -1 < probe and -1 < begin < probe:
            problems.append(
                "line %d: the pickfirst probe comes after the undo group "
                "opens, which clears the selection it looks for"
                % (src[:a + begin].count("\n") + 1))

    # 3. Every undo group asks whether undo is recording first.
    for a, b in top_level_forms(body):
        form = body[a:b]
        if '"_Begin"' in form and "UNDOCTL" not in form:
            problems.append(
                "line %d: (command \"_.UNDO\" \"_Begin\") with no UNDOCTL "
                "guard - it errors out of the command when undo is off"
                % (src[:a + form.find('"_Begin"')].count("\n") + 1))

    # 4. A tool announces itself on load, after its last defun, naming
    #    its own banner -- that line is how a user says which build they
    #    are running.
    if name not in LIBRARY_FILES:
        vm = VERSION_SYM.search(body)
        if vm:
            spans = top_level_forms(body)
            last = max((i for i, (a, b) in enumerate(spans)
                        if body[a:b].startswith("(defun")), default=-1)
            tail = [body[a:b] for a, b in spans[last + 1:]]
            if not any(t.startswith("(princ") and vm.group(1) in t
                       for t in tail):
                problems.append(
                    "no load banner: nothing after the last defun princ's "
                    "%s (a tool says which build it is on load)"
                    % vm.group(1))


def check_file(path):
    """(hard problems, advisories) for one file."""
    src = read(path)
    clean, unterminated = strip(src)
    lit, _ = strip(src, keep_strings=True)

    problems = balance(clean)
    house_rules(path, src, problems)

    # STANDARDS 5: sources are ASCII ("--", never em dashes) - comments
    # included, since the generated tiers carry them verbatim.  The
    # deprecated acady matcher is exempt (STANDARDS 8) and keeps its em
    # dashes and plus-minus signs.
    if "standards_checker" not in pathlib.Path(path).parts:
        bad = sorted({i + 1 for i, line in enumerate(src.splitlines())
                      if any(ord(ch) > 127 for ch in line)})
        for ln in bad[:5]:
            problems.append("line %d: non-ASCII character "
                            "(STANDARDS 5: ASCII only, use --)" % ln)
        if len(bad) > 5:
            problems.append("... and %d more non-ASCII line(s)"
                            % (len(bad) - 5))
    if unterminated:
        problems.append("unterminated string literal")
    problems += stray_top_level(lit)

    a = Analysis()
    for form in parse(lit):
        if isinstance(form, list):
            walk(form, a)
    problems += sorted(set(a.arity))

    # namespace prefixes come FROM THE FILE, never hardcoded, so every
    # tool gets these checks (STANDARDS 7.5).  c: is the command
    # convention, not a namespace.
    prefixes = sorted({d.split(":")[0] for d in a.defined
                       if ":" in d and not d.startswith("c:")})

    def own(name):
        return any(name.startswith(p + ":") for p in prefixes)

    # a "call" of an earmuffed name is a cond-test of a global, not a
    # missing function
    undef_calls = sorted(x for x in a.called
                         if own(x) and "*" not in x and x not in a.defined)
    for x in undef_calls:
        problems.append("undefined function %s is called" % x)

    undef_quoted = sorted(x for x in a.quoted
                          if own(x) and "*" not in x and x not in a.defined
                          and x not in a.called)
    for x in undef_quoted:
        problems.append("undefined function %s is quoted - a dispatch "
                        "table entry no test may ever reach" % x)

    advisories = []
    glob_reads = set(m.group(0).lower() for m in
                     re.finditer(r"[a-zA-Z][\w-]*:\*[\w*-]+", clean))
    undef_globals = sorted(g for g in glob_reads
                           if own(g) and g not in a.setq_targets)
    if undef_globals:
        advisories.append("globals read but never set here: "
                          + ", ".join(undef_globals))
    unused = sorted(d for d in a.defined
                    if d not in a.called and d not in a.quoted
                    and not d.startswith("c:") and d != "*error*")
    if unused:
        advisories.append("defuns nothing here calls or quotes: "
                          + ", ".join(unused))
    return problems, advisories


def main(argv):
    files = [pathlib.Path(f) for f in argv]
    if not files:
        files = lsp_files(LISP_DIR) + lsp_files(PARTS_DIR)
    tag = len(files) > 1
    bad = 0
    for path in files:
        try:
            problems, advisories = check_file(path)
        except OSError as e:
            print("%s: %s" % (path, e))
            bad += 1
            continue
        rel = path
        try:
            rel = path.resolve().relative_to(ROOT)
        except ValueError:
            pass
        prefix = ("%s: " % rel) if tag else ""
        for line in problems:
            print(prefix + line)
        for line in advisories:
            print(prefix + "note: " + line)
        bad += len(problems)
    if tag or bad:
        print("check_lisp: %d file(s), %d problem(s)" % (len(files), bad))
    elif not bad:
        print("check_lisp: clean")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
