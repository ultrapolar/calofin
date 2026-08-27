#!/usr/bin/env python3
"""Drive a command in the AutoLISP VM and print its prompt script.

The form tests pin scripted answers against the live prompt sequence of
POOL.LSP / SPA.LSP, and every prompt change makes those scripts stale.
Re-deriving them by hand against a 3,000-line file is where a day goes;
this makes it mechanical:

    python3 tests/record_prompts.py SPA  None Watersedge Rectangle 0,0 \\
                                         84 72 90 90 90 90 No No
    python3 tests/record_prompts.py POOL --script my_answers.py

Each argument is one scripted answer: numbers are numbers, x,y is a
point, None (or Enter) is a bare Enter, anything else is keyword/text.
With --script, the file's ANSWERS list (a Python literal) is used
instead - handy for long runs.

Output: the (prompt, answer) log the run consumed, numbered, plus a
ready-to-paste PROMPTS = [...] block.  A run that dies mid-script still
prints everything up to the failure - the traceback names the prompt
that did not match, which is normally the exact edit the test needs.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
ROOT = os.environ.get("CALOFIN_LISP_ROOT", "lisp")

#: command -> the file(s) to load.  Anything else: use --file/--command.
KNOWN = {
    "POOL": ["pool/POOL.LSP"],
    "POOLCOVER": ["pool/POOL.LSP"],
    "SPA": ["spa/SPA.LSP"],
    "OASIS": ["oasis/OASIS.lsp"],
    "FITABHD": ["fitabhd/FITABHD.lsp"],
}


def parse_answer(tok):
    if tok in ("None", "Enter", "enter"):
        return None
    if "," in tok:
        try:
            parts = [float(x) for x in tok.split(",")]
            return tuple(parts)
        except ValueError:
            pass
    try:
        return int(tok)
    except ValueError:
        pass
    try:
        return float(tok)
    except ValueError:
        pass
    return tok


def source_path(rel):
    if ROOT == "shared":
        name = os.path.basename(rel)
        stem, _ = os.path.splitext(name)
        return os.path.join(HERE, "..", "shared", "parts", stem + ".lsp")
    return os.path.join(HERE, "..", "lisp", rel)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("command", help="POOL, SPA, ... or any C: name with --file")
    ap.add_argument("answers", nargs="*")
    ap.add_argument("--file", action="append", default=[],
                    help="a .lsp to load (relative to lisp/); repeatable")
    ap.add_argument("--script", help="python file whose ANSWERS list to use")
    args = ap.parse_args(argv)

    cmd = args.command.upper()
    files = args.file or KNOWN.get(cmd)
    if not files:
        ap.error("unknown command %s - pass the source with --file" % cmd)

    if args.script:
        ns = {}
        with open(args.script, encoding="utf-8") as f:
            exec(compile(f.read(), args.script, "exec"), ns)  # noqa: S102
        script = list(ns["ANSWERS"])
    else:
        script = [parse_answer(t) for t in args.answers]

    vm = VM()
    for rel in files:
        vm.load(source_path(rel))
    err = None
    try:
        vm.run("c:" + cmd, list(script))
    except LispError as e:
        err = e

    print("prompt log (%s tier):" % ("shared" if ROOT == "shared" else "lisp"))
    for i, (prompt, answer) in enumerate(vm.prompts, 1):
        print("%3d  %-58r -> %r" % (i, prompt.strip(), answer))

    print("\nready to paste:")
    print("PROMPTS = [")
    for prompt, answer in vm.prompts:
        note = prompt.strip().replace("\n", " ")
        if len(note) > 46:
            note = note[:43] + "..."
        print("    %-16s # %s" % (repr(answer) + ",", note))
    print("]")

    if err is not None:
        print("\nrun DIED before the script ran out:")
        print("  %s" % err)
        return 1
    if vm.script:
        print("\n%d scripted answer(s) left over: %r"
              % (len(vm.script), vm.script))
        return 1
    print("\nscript and prompts agree - %d answers consumed" % len(vm.prompts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
