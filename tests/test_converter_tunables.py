"""The three converters' knobs: all at the top, all explained, none stray.

XFTCONV, SOCONV and VSCONV are the tools a shop retunes rather than
rewrites -- a survey exporter renames a layer, a template uses another
block, a job wants the import's own colours kept.  Every one of those
answers is a global at the top of the file, and this is what keeps that
true, because a block that is merely tidy today is a block someone adds
the next knob underneath.

STANDARDS 5 is the rule; `tests/test_tunables.py` holds it for the four
GUI files.  It cannot hold it for these three: its parser reads one
`setq` per line with a scalar after it, and the converters' central
knobs are multi-line tables (`*soconv-map*` is seven rows) whose default
cannot be written in a README cell.  So the checks below walk the forms
with a paren walk instead, and check 5 asks that every knob HAS a
README row rather than comparing the default in it.

  1. Each file has one tunables block, under the canonical rule, after
     the version banner and before the first defun -- a knob defined
     after the code that reads it is nil while that code loads.
  2. Every knob in it says what CHANGING it does: a paragraph above the
     setq, or a remark after the value.
  3. Every knob is a literal nothing re-assigns.  A state variable
     hoisted in by mistake would read as a setting when it is really an
     initial value, and setting it would look like it worked.
  4. No knob-shaped global lives OUTSIDE the block.  The version banner
     is the one exception, and it is checked to be exactly that.
  5. Every knob is a row in its README's Tunables table.

Run: python3 tests/test_converter_tunables.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


#: (tool, source, version banner, README)
FILES = [
    ('XFTCONV', ('lisp', 'xftconv', 'xftconv.lsp'), '*xft-version*',
     ('lisp', 'xftconv', 'README.md')),
    ('SOCONV', ('lisp', 'soconv', 'SOCONV.lsp'), '*soconv-version*',
     ('lisp', 'soconv', 'README.md')),
    ('VSCONV', ('lisp', 'vsconv', 'VSCONV.lsp'), '*vsconv-version*',
     ('lisp', 'vsconv', 'README.md')),
]

RULE = ';;; -------------------- tunables '
GLOBAL = r'\*[a-z][a-z0-9-]*\*'


def end_of_form(src, i):
    """Offset just past the form whose opening paren is at I - 1,
    stepping over strings and comments so a paren inside either does
    not close it."""
    depth = 1
    while i < len(src) and depth:
        c = src[i]
        if c == '"':
            i += 1
            while i < len(src) and src[i] != '"':
                i += 2 if src[i] == '\\' else 1
        elif c == ';':
            while i < len(src) and src[i] != '\n':
                i += 1
            continue
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        i += 1
    return i


def assignments(src):
    """[(global, start, end)] -- every earmuffed name a setq WRITES,
    with the extent of the setq form that writes it.

    A paren walk rather than a line regex, because the tables are
    multi-line: a line-based reader sees `(setq *soconv-map*` with no
    closing paren and drops the file's most important knob.  Names are
    taken at paren depth 0 inside the form, which is where a setq's
    targets sit and where a list value's contents do not.
    """
    out = []
    for m in re.finditer(r'\(setq\b', src):
        end = end_of_form(src, m.end())
        body, depth = src[m.end():end], 0
        for t in re.finditer(r'[()"; \n]|' + GLOBAL, body):
            s = t.group(0)
            if s == '(':
                depth += 1
            elif s == ')':
                depth -= 1
            elif s.startswith('*') and depth == 0:
                out.append((s, m.start(), end))
    return out


def why(src, start):
    """What the file says about changing the knob whose setq starts at
    START: the ;; paragraph directly above it, or a remark after the
    value.  '' when neither is there."""
    line_end = src.index('\n', start) if '\n' in src[start:] else len(src)
    tail = src[start:line_end]
    if ';' in tail.split('"')[-1] and re.search(r';\s*\S', tail):
        return tail[tail.index(';'):].strip('; ').strip()
    said, i = [], src.rfind('\n', 0, start)
    while i > 0:
        j = src.rfind('\n', 0, i)
        line = src[j + 1:i].strip()
        if not line.startswith(';'):
            break
        said.insert(0, line.lstrip(';').strip())
        i = j
    return ' '.join(said).strip()


def table_names(readme):
    """The globals named in the README's Tunables table."""
    m = re.search(r'^## Tunables\b.*?(?=^## |\Z)', readme, re.M | re.S)
    if not m:
        return None
    return set(re.findall(r'^\| `(' + GLOBAL + r')` \|', m.group(0), re.M))


print("== 1. one tunables block, after the banner and before the code ==")

BLOCKS = {}
for tool, path, banner, _readme in FILES:
    src = read(*path)
    check("%s has a tunables block" % tool, src.count(RULE) == 1,
          "%d found" % src.count(RULE))
    if src.count(RULE) != 1:
        continue
    i = src.index(RULE)
    j = src.index('\n;;; ---', i + len(RULE))
    BLOCKS[tool] = (src, src[i:j], src[:i] + src[j:])
    check("%s: it comes before the first defun" % tool,
          i < src.index('\n(defun '),
          "a knob defined after the code that reads it is nil while "
          "that code loads")
    check("%s: the version banner is above it, not in it" % tool,
          0 < src.index('(setq ' + banner) < i,
          repr((src.index('(setq ' + banner), i)))

print("== 2. every knob says what changing it does ==")

KNOBS = {}
for tool, path, banner, _readme in FILES:
    if tool not in BLOCKS:
        continue
    src, block, _rest = BLOCKS[tool]
    at = src.index(RULE)
    names = [(n, s) for n, s, _e in assignments(block)]
    KNOBS[tool] = [n for n, _s in names]
    check("%s: %d knob(s) in the block" % (tool, len(names)), len(names) > 0)
    for name, start in names:
        said = why(block, start)
        check("%s %s is explained" % (tool, name), len(said) > 20,
              repr(said[:60]))

print("== 3. a knob is a literal nothing re-assigns ==")

for tool, path, banner, _readme in FILES:
    if tool not in BLOCKS:
        continue
    src, _block, _rest = BLOCKS[tool]
    writes = {}
    for name, start, _end in assignments(src):
        writes.setdefault(name, []).append(start)
    for name in KNOBS[tool]:
        check("%s %s is written once" % (tool, name),
              len(writes.get(name, [])) == 1,
              "written at %r -- state, not a setting?" % (writes.get(name),))

print("== 4. no knob-shaped global outside the block ==")

for tool, path, banner, _readme in FILES:
    if tool not in BLOCKS:
        continue
    _src, _block, rest = BLOCKS[tool]
    stray = [n for n, _s, _e in assignments(rest) if n != banner]
    check("%s: nothing settable outside it" % tool, not stray, repr(stray))
    check("%s: and the banner outside it is the version" % tool,
          [n for n, _s, _e in assignments(rest)] == [banner],
          repr([n for n, _s, _e in assignments(rest)]))

print("== 5. every knob is a row in the README's Tunables table ==")

for tool, path, banner, readme in FILES:
    if tool not in BLOCKS:
        continue
    named = table_names(read(*readme))
    check("%s: the README has a Tunables table" % tool, named is not None)
    if named is None:
        continue
    missing = [n for n in KNOBS[tool] if n not in named]
    check("%s: every knob has a row" % tool, not missing, repr(missing))
    extra = [n for n in named if n not in KNOBS[tool]]
    check("%s: and the table names no knob the file has not got" % tool,
          not extra, repr(extra))

print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("all CONVERTER TUNABLES checks passed")
