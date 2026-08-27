#!/usr/bin/env python3
"""Scope check: locals used without being declared, and case collisions.

AutoLISP scoping makes both easy to ship: a ``setq`` onto an undeclared
name quietly creates a global, a ``foreach`` variable persists after the
loop, and symbols are case-insensitive so ``sP`` silently IS ``sp`` (the
bug class that broke NORMIESTEP's side lines and ABCDEF's corners).

Findings, per defun:

  setq         a setq target neither a parameter nor a declared local
  setq-global  an own-prefix *global* assigned but never declared at top
               level in this file
  foreach      a foreach variable not in the arglist (it survives the loop)
  case-dup     two spellings of one name declared in one arglist
  case-mix     a declared local also written in another case in the body

Much of the ``setq`` class is deliberate module-level state, so known
findings live in tools/scope_baseline.txt and do not fail the check --
only NEW findings do.  After deciding a new finding is intentional,
refresh the baseline with:

    python3 tools/check_scope.py --update-baseline

Exit 0 when every finding is baselined, 1 otherwise.
"""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from callib import LISP_DIR, PARTS_DIR, ROOT, lsp_files, read, strip

BASELINE = pathlib.Path(__file__).resolve().parent / "scope_baseline.txt"
SYM = re.compile(r"[A-Za-z_:*][\w:*+/<>=!?-]*")
QUOTED = re.compile(r"'[A-Za-z_][\w:*+/<>=!?-]*")


def top_forms(clean):
    """(offset, text) of every top-level form."""
    forms = []
    depth, start = 0, None
    for i, ch in enumerate(clean):
        if ch == "(":
            if depth == 0:
                start = i
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0 and start is not None:
                forms.append((start, clean[start:i + 1]))
                start = None
    return forms


def setq_elements(body, start):
    """Top-level elements of the (setq ...) opening at ``start``:
    (offset, token-or-None) -- None stands for a nested form."""
    i = body.index("(", start) + 1
    i += len("setq")
    depth = 1
    elems = []
    n = len(body)
    while i < n and depth:
        ch = body[i]
        if ch == "(":
            if depth == 1:
                elems.append((i, None))
            depth += 1
            i += 1
        elif ch == ")":
            depth -= 1
            i += 1
        elif ch in " \t\r\n'":
            i += 1
        elif ch == '"':
            if depth == 1:
                elems.append((i, '"'))
            i += 1
        elif depth == 1:
            j = i
            while j < n and body[j] not in " \t\r\n()'\"":
                j += 1
            elems.append((i, body[i:j]))
            i = j
        else:
            i += 1
    return elems


def check_file(path):
    """List of (line, defun, kind, detail) findings."""
    src = read(path)
    clean, _ = strip(src)
    findings = []

    prefixes = sorted(set(re.findall(r"\(defun\s+([a-zA-Z][\w-]*):", clean)))
    globals_declared = set(
        g.lower() for g in
        re.findall(r"\(setq\s+([a-zA-Z][\w-]*:\*[\w*-]+)", clean))

    for pos, f in top_forms(clean):
        m = re.match(r"\(defun\s+([^\s()]+)\s*\(([^)]*)\)", f, re.S)
        if not m:
            continue
        name = m.group(1)
        arglist = m.group(2)
        toks = arglist.replace("/", " / ").split()
        if "/" in toks:
            k = toks.index("/")
            declared = set(toks[:k]) | set(toks[k + 1:])
        else:
            declared = set(toks)
        declared_low = {d.lower() for d in declared}
        body = f[m.end():]
        base = clean[:pos].count("\n") + 1

        def line_at(off):
            return base + f[:off].count("\n")

        for fv in re.finditer(r"\(foreach\s+([^\s()]+)", body):
            v = fv.group(1)
            if v.lower() not in declared_low:
                findings.append((line_at(m.end() + fv.start()), name,
                                 "foreach", v))

        for sq in re.finditer(r"\(setq[\s(]", body):
            elems = setq_elements(body, sq.start())
            for idx in range(0, len(elems), 2):
                off, tok = elems[idx]
                if tok is None or tok == '"':
                    continue
                v = tok
                ln = line_at(m.end() + off)
                if re.match(r"^[a-zA-Z][\w-]*:\*", v):
                    if v.lower() not in globals_declared:
                        findings.append((ln, name, "setq-global", v))
                    continue
                if (v.lower() not in declared_low
                        and not any(v.startswith(p + ":") for p in prefixes)
                        and v.lower() not in ("nil", "t")):
                    findings.append((ln, name, "setq", v))

        # ---- case collisions -------------------------------------------
        folded = {}
        for v in toks:
            if v == "/":
                continue
            lv = v.lower()
            if lv in folded:
                findings.append((base, name, "case-dup",
                                 "%s / %s declared in one arglist"
                                 % (folded[lv], v)))
            folded.setdefault(lv, v)
        # quoted symbols are data ('SIG as an alist key is not the
        # variable sig) -- drop them before comparing spellings
        body_novq = QUOTED.sub(" ", body)
        spellings = {}
        for t in SYM.findall(body_novq):
            spellings.setdefault(t.lower(), set()).add(t)
        for lv, first in folded.items():
            others = spellings.get(lv, set()) - {first}
            if others and lv not in ("t", "nil", "pi"):
                findings.append((base, name, "case-mix",
                                 "local %s also written as %s"
                                 % (first, ", ".join(sorted(others)))))
    return findings


def key_of(rel, finding):
    _, defun, kind, detail = finding
    return "%s|%s|%s|%s" % (rel, defun.lower(), kind, detail.lower())


def load_baseline():
    if not BASELINE.is_file():
        return set()
    return {ln.strip() for ln in BASELINE.read_text(encoding="utf-8")
            .splitlines() if ln.strip() and not ln.startswith("#")}


def main(argv):
    update = "--update-baseline" in argv
    argv = [a for a in argv if a != "--update-baseline"]
    files = [pathlib.Path(f) for f in argv]
    if not files:
        files = lsp_files(LISP_DIR) + lsp_files(PARTS_DIR)

    baseline = load_baseline()
    fresh, keys, suppressed = {}, [], 0
    for path in files:
        try:
            rel = str(path.resolve().relative_to(ROOT))
        except ValueError:
            rel = str(path)
        for finding in check_file(path):
            k = key_of(rel, finding)
            keys.append(k)
            if k in baseline:
                suppressed += 1
            else:
                # one report per variable per defun - the first occurrence
                fresh.setdefault(k, (rel, finding))

    if update:
        lines = ["# One line per accepted finding: file|defun|kind|detail",
                 "# Regenerate with: python3 tools/check_scope.py"
                 " --update-baseline"]
        lines += sorted(set(keys))
        BASELINE.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("check_scope: baseline updated - %d finding(s) accepted"
              % len(set(keys)))
        return 0

    for rel, (line, name, kind, detail) in sorted(fresh.values()):
        print("%s: line %5d  %-22s %-12s %s" % (rel, line, name, kind, detail))
    if fresh:
        print("check_scope: %d NEW finding(s) (%d baselined) - declare the "
              "variable, or accept it with --update-baseline"
              % (len(fresh), suppressed))
        return 1
    print("check_scope: clean (%d baselined finding(s))" % suppressed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
