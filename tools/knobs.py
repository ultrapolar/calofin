# SPDX-License-Identifier: GPL-3.0-or-later
"""The tunables of every tool, read off their blocks.

A tool's knobs are the ``(setq prefix:*name* LITERAL)`` lines inside the
block at the top of its file -- ruled off as ``tunables``, ``TUNABLES``
or (AutoDim's spelling) ``SETTINGS``, or under one of the older names
STANDARDS.md leaves alone: ``configuration``, ``settings``, ``the
knobs``, ``adjustable constants`` -- and tests/test_tunables.py is what
keeps that true for the files it lists.  This reads the same blocks for
a different reason: LAZTUNE lets a drafter set their own value for any
knob without editing the file, and needs to know every knob's name, its
shipped value ("Alec's choice") and what changing it does.
tools/gen_knobs.py writes that catalog into LAZPANEL.lsp from what this
returns, and tests/test_knobs.py pins each header spelling to a file
that uses it.

Nothing here decides anything: a knob is what the block says it is,
and its meaning is the comment the block already carries.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import LISP_DIR, ROOT, lsp_files, read  # noqa: E402

#: how a block opens: the three header spellings STANDARDS.md asks new
#: work for, at the start of a line.  The first one found in a file
#: wins, and a file that has one is read by nothing else.
HEAD = re.compile(r'^;;; -------------------- tunables |^;;;  TUNABLES|^;;;  SETTINGS',
                  re.M)
#: ...and the older names STANDARDS.md says are "the same block under an
#: older name and fine to leave": a rule line (two or three semicolons,
#: dashes or equals) that names the block -- ABFIND's `configuration`,
#: PADDLE's `settings`, LINGUTTER's `the knobs`, POOLSIDE's `adjustable
#: constants`, MOHAMADDLE's own `tunables` on a two-semicolon rule --
#: and the title-case `;;;  Tunables` banner UPADOVER and PERPMARK rule
#: theirs off with.  Read only when HEAD finds nothing, so the files it
#: already covered read exactly as before.  A candidate is taken only if
#: its block holds a setq: CDCREATE's header prose says ";;;  Tunables:"
#: forty lines above its real banner, and a header with no knob under
#: it is prose, not a block.
OLDER = re.compile(r'^;;;? ?[-=]{3,}[^\n]*\b(?:tunables|settings|configuration|knobs|'
                   r'adjustable constants)\b[^\n]*|^;;;  Tunables\b', re.M | re.I)
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
#: the GUARDED spelling: the three step routines share one set of
#: settings, so each declares a knob only if no sibling already has --
#: ``(if (not (boundp '*cs-x*)) (setq *cs-x* 0.125))``.  It is a knob
#: like any other (a literal, explained, at the top of the file); it
#: simply cannot be a bare setq without the first file loaded winning
#: over a value the drafter set before loading.  Read here, and
#: catalogued ONCE -- see catalog().
GUARD = re.compile(r'^\(if \(not \(boundp \'(' + NAME + r')\)\) \(setq \1\s',
                   re.M | re.I)


def knob_starts(block):
    """[(offset of the (setq ...), name it guards or None)] for every
    knob declaration in BLOCK, in the order they are written."""
    out = [(m.start(), None) for m in SETQ.finditer(block)]
    for m in GUARD.finditer(block):
        i = block.find('(setq ', m.start())
        if i > 0:
            out.append((i, m.group(1)))
    return sorted(out)


def _block_at(src, m):
    """The block a header match M opens: to the explicit end line, else
    the next ;;; rule, else the first defun."""
    i = m.start()
    e = EXPLICIT.search(src, m.end())
    if not e:
        e = RULE.search(src, m.end())
    j = e.start() if e else src.find('\n(defun ', i)
    block = src[i:j] if j > 0 else src[i:]
    if not (SETQ.search(block) or GUARD.search(block)) and e \
            and not EXPLICIT.match(src, e.start()):
        # STOCKCOVER rules its header prose off with a bare line and
        # puts the knobs UNDER it: read on to the next rule or defun
        k = j + 1
        e2 = RULE.search(src, k + 1)
        j2 = e2.start() if e2 else src.find('\n(defun ', k)
        block = src[i:j2] if j2 > 0 else src[i:]
    return block


def block_of(src):
    """(block text, header spelling) or (None, None).

    A HEAD spelling wins outright, first one in the file.  Failing that,
    the first OLDER header whose block actually holds a setq -- so a
    line of prose that happens to say "Tunables" (CDCREATE's file
    comment, HONEFILLET's) is passed over for the banner under it, or
    for nothing."""
    m = HEAD.search(src)
    if m:
        return _block_at(src, m), m.group(0).strip()
    for m in OLDER.finditer(src):
        block = _block_at(src, m)
        # a setq that is not the version banner: LINGUTTER's file
        # comment says "Tunables" too, and reading on from it reaches
        # (setq *lingutter-version* ...) before the real rule does.
        # Every pair of a setq counts -- AUTOBEAD's one setq names its
        # banner first and its knobs after it
        if any('version' not in name.lower()
               for off, _ in knob_starts(block)
               for name, _ in pairs_of(block, off)):
            return block, m.group(0).strip()
    return None, None


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
    setq may set several: (setq *x-record* t *x-app* "X").  M is a match
    or a plain offset."""
    start = m if isinstance(m, int) else m.start()
    end = sexp_end(block, start)
    inner = block[start + len('(setq '):end - 1]
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
    for off, guarded in knob_starts(block):
        # a guarded knob's comment sits over the (if ...), not the (setq
        anchor = block.rfind('\n(if ', 0, off) + 1 if guarded else off
        li = starts.get(block.rfind('\n', 0, anchor) + 1, 0)
        why = why_of(lines, li)
        for name, lit in pairs_of(block, off):
            if 'version' in name.lower():
                continue                  # a banner, not a setting
            out.append((name, lit, why))
    return out


def catalog(lisp_dir=LISP_DIR):
    """[(file relative to the repo, [(name, literal, meaning), ...]), ...]
    for every file with a block, in path order; files with none are
    left out."""
    out = []
    seen = set()
    for p in lsp_files(lisp_dir):
        if 'standards_checker' in p.parts or 'lisplab' in p.parts:
            continue
        # A knob SHARED between files -- the step routines' *cs-* set,
        # declared in all three under the boundp guard -- is one knob a
        # drafter sets once, and the override is keyed by its name
        # alone, so it is catalogued under the first file that declares
        # it and skipped in the rest.  Listing it three times would
        # offer the same setting under three tools and fail the
        # uniqueness that keying by name depends on.
        ks = [k for k in knobs_of(p) if k[0].lower() not in seen]
        seen.update(k[0].lower() for k in ks)
        if ks:
            out.append((str(p.relative_to(ROOT)), ks))
    return out


if __name__ == '__main__':
    total = 0
    for f, ks in catalog():
        print('%-45s %3d' % (f, len(ks)))
        total += len(ks)
    print('%d knobs' % total)
