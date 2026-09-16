# SPDX-License-Identifier: GPL-3.0-or-later
"""The tunables of every tool, read off their blocks.

A tool's knobs are the ``(setq prefix:*name* LITERAL)`` lines inside the
block at the top of its file -- ruled off as ``tunables``, ``TUNABLES``
or (AutoDim's spelling) ``SETTINGS`` -- and tests/test_tunables.py is
what keeps that true.  This reads the same blocks for a different
reason: LAZTUNE lets a drafter set their own value for any knob without
editing the file, and needs to know every knob's name, its shipped
value ("Alec's choice") and what changing it does.  tools/gen_knobs.py
writes that catalog into LAZPANEL.lsp from what this returns.

Nothing here decides anything: a knob is what the block says it is,
and its meaning is the comment the block already carries.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import LISP_DIR, ROOT, lsp_files, read  # noqa: E402

#: how a block opens: the three header spellings the tree uses, at the
#: start of a line.  The first one found in a file wins.
HEAD = re.compile(r'^;;; -------------------- tunables |^;;;  TUNABLES|^;;;  SETTINGS',
                  re.M)
#: how it closes.  An explicit end line wins wherever it sits -- abhd
#: rules its groups off with bare dashes INSIDE the block and says
#: "end of tunables" where it really ends -- and only a block with no
#: such line ends at the next ;;; rule, which is the rule
#: tests/test_tunables.py reads by.  Neither: the first defun.
EXPLICIT = re.compile(r'\n;;;? ?-{3,} ?end of tunables|\n;;;  END TUNABLES'
                      r'|\n;;; ={10,} end of SETTINGS', re.I)
RULE = re.compile(r'\n;;; -{3,}|\n;;; ={3,}')

#: a knob name: prefix:*name* is the rule; four of the check tools spell
#: theirs *tool-name*, and abhd's are *PF-NAME* -- the same block
#: discipline covers all three
NAME = r'(?:[a-z0-9]+:\*[a-z0-9-]+\*|\*[a-z][a-z0-9-]+\*)'
SETQ = re.compile(r'^\(setq (' + NAME + r')\s', re.M | re.I)


def block_of(src):
    """(block text, header spelling) or (None, None)."""
    m = HEAD.search(src)
    if not m:
        return None, None
    i = m.start()
    e = EXPLICIT.search(src, m.end())
    if not e:
        e = RULE.search(src, m.end())
    j = e.start() if e else src.find('\n(defun ', i)
    block = src[i:j] if j > 0 else src[i:]
    if not SETQ.search(block) and e and not EXPLICIT.match(src, e.start()):
        # STOCKCOVER rules its header prose off with a bare line and
        # puts the knobs UNDER it: read on to the next rule or defun
        k = j + 1
        e2 = RULE.search(src, k + 1)
        j2 = e2.start() if e2 else src.find('\n(defun ', k)
        block = src[i:j2] if j2 > 0 else src[i:]
    return block, m.group(0).strip()


def sexp_end(text, start):
    """Index just past the s-expression opening at TEXT[start] == '('."""
    depth, instr, i = 0, False, start
    while i < len(text):
        c = text[i]
        if instr:
            if c == '\\':
                i += 1
            elif c == '"':
                instr = False
        elif c == '"':
            instr = True
        elif c == ';':
            i = text.find('\n', i)
            if i < 0:
                return len(text)
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def tokens(text):
    """The top-level items of TEXT: atoms, strings and parenthesised
    forms, each as source text."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in ' \t\n':
            i += 1
        elif c == ';':
            i = text.find('\n', i)
            if i < 0:
                break
        elif c == '(':
            j = sexp_end(text, i)
            out.append(text[i:j])
            i = j
        elif c == "'" and i + 1 < n and text[i + 1] == '(':
            j = sexp_end(text, i + 1)
            out.append(text[i:j])
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            j = i
            while j < n and text[j] not in ' \t\n();"':
                j += 1
            out.append(text[i:j])
            i = j
    return out


def pairs_of(block, m):
    """[(name, literal)] a (setq ...) at M sets -- one per pair, since a
    setq may set several: (setq *x-record* t *x-app* "X")."""
    end = sexp_end(block, m.start())
    inner = block[m.start() + len('(setq '):end - 1]
    toks = tokens(inner)
    out = []
    for k in range(0, len(toks) - 1, 2):
        if re.fullmatch(NAME, toks[k], re.I):
            out.append((toks[k], ' '.join(toks[k + 1].split())))
    return out


def why_of(lines, i):
    """What line I of a block says about its knob: the ; remark after the
    value, the ; lines continuing under it, and the ;; paragraph over
    the run of setqs it sits in -- the same three places
    tests/test_tunables.py reads."""
    parts = []
    ln, j, q = lines[i], 0, False
    while j < len(ln):
        if ln[j] == '"':
            q = not q
        elif ln[j] == ';' and not q:
            parts.append(ln[j:].strip('; ').strip())
            break
        j += 1
    k = i + 1
    while k < len(lines) and lines[k].lstrip().startswith(';'):
        parts.append(lines[k].strip().lstrip(';').strip())
        k += 1
    k = i - 1
    while k >= 0 and lines[k].startswith('(setq '):
        k -= 1
    why = []
    while k >= 0 and lines[k].lstrip().startswith(';'):
        why.insert(0, lines[k].strip().lstrip(';').strip())
        k -= 1
    parts.extend(why)
    return ' '.join(p for p in parts if p).strip()


def knobs_of(path):
    """[(name, literal, meaning)] for one file, in block order."""
    src = read(path)
    block, _ = block_of(src)
    if not block:
        return []
    lines = block.splitlines()
    starts = {}
    pos = 0
    for n, ln in enumerate(lines):
        starts[pos] = n
        pos += len(ln) + 1
    out = []
    for m in SETQ.finditer(block):
        li = starts.get(block.rfind('\n', 0, m.start()) + 1, 0)
        why = why_of(lines, li)
        for name, lit in pairs_of(block, m):
            if 'version' in name.lower():
                continue                  # a banner, not a setting
            out.append((name, lit, why))
    return out


def catalog(lisp_dir=LISP_DIR):
    """[(file relative to the repo, [(name, literal, meaning), ...]), ...]
    for every file with a block, in path order; files with none are
    left out."""
    out = []
    for p in lsp_files(lisp_dir):
        if 'standards_checker' in p.parts or 'lisplab' in p.parts:
            continue
        ks = knobs_of(p)
        if ks:
            out.append((str(p.relative_to(ROOT)), ks))
    return out


if __name__ == '__main__':
    total = 0
    for f, ks in catalog():
        print('%-45s %3d' % (f, len(ks)))
        total += len(ks)
    print('%d knobs' % total)
