#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read ONE form out of a .lsp instead of the whole file.

The tools here run to four thousand lines.  Opening `abhd.lsp` to change
one helper costs more than the change does, and most of what comes back
is prose about a part of the tool nobody is touching.  So this prints a
map of a file, or a single top-level form out of it, by paren balance.

    lspshow.py --map lisp/pool/POOL.LSP        # every top-level form,
                                               # one line each
    lspshow.py pool:askkw                      # the defun, wherever it is
    lspshow.py pool:askkw lisp/pool/POOL.LSP   # the defun, from that file
    lspshow.py --callers cal:ink               # every call site, file:line
    lspshow.py --cmd SQUAREUP                  # the c:SQUAREUP defun

A form comes back with its leading ;;-comment block, which is where the
reason for it is written, and with line numbers so an Edit can be
anchored without a second read.
"""

import argparse
import os
import pathlib
import re
import signal
import sys

# This gets piped into `head` more often than not -- die quietly when the
# reader closes, rather than printing a traceback over the output.
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):       # no SIGPIPE on Windows
    pass

ROOT = pathlib.Path(__file__).resolve().parents[4]
SEARCH = ("lisp", "shared/parts", "wip")


def lsp_files(roots=SEARCH):
    for r in roots:
        d = ROOT / r
        if not d.is_dir():
            continue
        for p in sorted(d.rglob("*")):
            if p.is_file() and p.suffix.lower() == ".lsp":
                yield p


def read(p):
    return pathlib.Path(p).read_text(encoding="utf-8", errors="replace")


def top_span(src, opener, name):
    """(start, end) of a top-level (OPENER NAME ...), by paren balance,
    taking the ;;-comment block immediately above it with it.

    Lifted from tools/mirror_shared.py so the two agree about where a
    form begins and ends -- that is the whole point of reading one."""
    # re.I: AutoLISP symbols are case-insensitive -- POOL:ASKKW IS
    # pool:askkw, and c:abcdef is the command ABCDEF
    m = re.search(r"^\(" + opener + r"\s+" + re.escape(name) + r"(?=[\s()])",
                  src, re.M | re.I)
    if not m:
        return None
    i = m.start()
    depth, instr, j = 0, False, i
    while j < len(src):
        c = src[j]
        if instr:
            if c == "\\":
                j += 2
                continue
            if c == '"':
                instr = False
        elif c == '"':
            instr = True
        elif c == ";":
            while j < len(src) and src[j] != "\n":
                j += 1
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    while j < len(src) and src[j] in " \t":
        j += 1
    if j < len(src) and src[j] == ";":
        while j < len(src) and src[j] != "\n":
            j += 1
    # take the ;; block above it -- the reason lives there
    while i > 0:
        nl = src.rfind("\n", 0, i - 1)
        line = src[nl + 1:i]
        s = line.lstrip()
        if s.startswith(";;") and not s.startswith(";;;"):
            i = nl + 1
        else:
            break
    return i, j


def emit(path, src, span):
    start = src.count("\n", 0, span[0]) + 1
    body = src[span[0]:span[1]].rstrip("\n")
    rel = os.path.relpath(path, ROOT)
    print("== %s:%d ==" % (rel, start))
    for n, line in enumerate(body.split("\n"), start):
        print("%5d\t%s" % (n, line))
    print()


TOP = re.compile(r"^\((defun|setq)\s+(\S+)", re.M)


def do_map(paths):
    for path in paths:
        src = read(path)
        rel = os.path.relpath(path, ROOT)
        print("== %s (%d lines) ==" % (rel, src.count("\n") + 1))
        for m in TOP.finditer(src):
            ln = src.count("\n", 0, m.start()) + 1
            kind, name = m.group(1), m.group(2).rstrip("(")
            args = ""
            if kind == "defun":
                a = re.match(r"[^(]*(\([^)]*\))", src[m.end():])
                if a:
                    args = " " + " ".join(a.group(1).split())
            print("%5d  %-6s %s%s" % (ln, kind, name, args))
        print()


def do_show(name, paths):
    openers = ("defun", "setq")
    hits = 0
    for path in paths:
        src = read(path)
        for op in openers:
            span = top_span(src, op, name)
            if span:
                emit(path, src, span)
                hits += 1
                break
    if not hits:
        print("lspshow: no top-level (defun %s ...) or (setq %s ...) found"
              % (name, name), file=sys.stderr)
        return 1
    return 0


def do_callers(name, paths):
    pat = re.compile(r"[('](" + re.escape(name) + r")(?=[\s)])", re.I)
    total = 0
    for path in paths:
        src = read(path)
        rel = os.path.relpath(path, ROOT)
        for n, line in enumerate(src.split("\n"), 1):
            s = line.split(";", 1)[0]
            if pat.search(s):
                print("%s:%d:%s" % (rel, n, line.rstrip()))
                total += 1
    print("\n%d call site(s)" % total, file=sys.stderr)
    return 0 if total else 1


def main(argv):
    ap = argparse.ArgumentParser(
        description="Read one form, or a map, out of a .lsp file.")
    ap.add_argument("name", nargs="?", help="symbol to show")
    ap.add_argument("files", nargs="*", help="files to read (default: all)")
    ap.add_argument("--map", action="store_true",
                    help="list every top-level form in the file(s)")
    ap.add_argument("--callers", metavar="SYM",
                    help="every call site of SYM, as file:line")
    ap.add_argument("--cmd", metavar="NAME",
                    help="show the c:NAME command defun")
    a = ap.parse_args(argv)

    # --map, --callers and --cmd take no symbol positional, so in those
    # modes whatever argparse bound to `name` is really the first FILE.
    # (Dropping it searched the whole tree for `--callers SYM FILE`.)
    first = [a.name] if (a.map or a.callers or a.cmd) and a.name else []
    given = [pathlib.Path(f) for f in first + a.files]
    paths = given or list(lsp_files())

    if a.map:
        if not given:
            ap.error("--map needs a file")
        return do_map(given)
    if a.callers:
        return do_callers(a.callers, paths)
    if a.cmd:
        return do_show("c:" + a.cmd.upper(), paths) or 0
    if not a.name:
        ap.error("give a symbol, --map FILE, --callers SYM or --cmd NAME")
    return do_show(a.name, paths)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
