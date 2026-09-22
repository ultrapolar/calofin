"""callib.decomment, held to the character loop it replaced.

decomment blanks every ``;`` comment to spaces and leaves the rest of
the text -- string literals included -- exactly where it was.  Every
static check that reads a rule ABOUT a string (check_lisp's house
rules, check_osnap, check_color, check_perf, the span finder under
them) indexes the result with offsets taken from the source, so the
one thing it may never do is move a character.

It was a character loop, and is now one regex scan.  The loop is kept
here, verbatim, as the reference, and the two are made to agree on:

1. the awkward shapes -- a trailing backslash, an unterminated string,
   a backslash-newline inside a string, an escaped quote with a ``;``
   after it, CRLF line ends, a lone ``"\\``, a lone ``;``;
2. a few thousand random strings over the characters that matter
   (fixed seed, so a failure reproduces);
3. every .lsp in lisp/ and shared/parts/.

Neither version knows AutoLISP's ``;| ... |;`` inline comment; that
limitation is the loop's and is kept.

Run: python3 tests/test_decomment.py
"""

import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
from callib import LISP_DIR, PARTS_DIR, decomment, lsp_files, read  # noqa: E402

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print("  ok   %s" % label)
    else:
        print("  FAIL %s%s" % (label, ('  -- ' + detail) if detail else ''))
        FAILS.append(label)


def decomment_loop(src):
    """The character loop callib.decomment was until the regex -- the
    reference.  Do not "fix" it: it is what the regex has to match."""
    out = list(src)
    i, n = 0, len(src)
    instr = False
    while i < n:
        ch = src[i]
        if instr:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == '"':
                instr = False
            i += 1
            continue
        if ch == '"':
            instr = True
            i += 1
            continue
        if ch == ";":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
            continue
        i += 1
    return "".join(out)


print("== 1. the awkward shapes ==")

CASES = [
    ("empty text", ''),
    ("a lone ;", ';'),
    ('a lone "', '"'),
    ('a lone "\\', '"\\'),
    ("a lone backslash", '\\'),
    ("a trailing backslash inside a string", '(princ "abc\\'),
    ("a trailing backslash outside a string", '(princ x)\\'),
    ("an unterminated string", '(princ "abc ; not a comment\n(foo)'),
    ("an unterminated string ending in a newline", '"abc\n'),
    ("a backslash-newline inside a string", '(princ "a\\\nb") ; gone\n(x)'),
    ("an escaped quote followed by ;", '(princ "a\\";b") ; c\n'),
    ("an escaped backslash, then the close, then ;",
     '(princ "a\\\\") ; comment "with a quote\n(y)'),
    ("CRLF line ends", '(setq a 1) ; one\r\n(setq b "x;y") ; two\r\n'),
    ("a comment holding a quote", '; he said "hi\n(princ "still code")'),
    ("a comment at end of text, no newline", '(a) ;; last'),
    ("a comment holding a backslash", '(a) ; dir\\path\\\n(b)'),
    ("two strings back to back", '"a""b";c\n"d"'),
    ("an empty string then ;", '""; c\n'),
    ("a ;| inline |; comment", '(a ;| inline |; b)\n'),
    ("non-ASCII in a comment and a string", '(princ "\u00e9;\u2014") ; \u2014 x\n'),
    ("a tab and a form feed in a comment", '(a) ;\tx\fy\n(b)'),
    ("a lone CR in a comment", '(a) ; x\ry\n(b)'),
    ("a string spanning lines", '(princ "line one\nline two ; kept")\n; gone'),
]

for label, src in CASES:
    want = decomment_loop(src)
    got = decomment(src)
    check("%s: %r" % (label, src), got == want,
          "want %r, got %r" % (want, got))
    check("%s keeps every offset" % label, len(got) == len(src))

print()
print("== 2. random text over the characters that matter ==")

ALPHABET = ['"', '\\', ';', '\n', '\r', 'a', ' ', '(', ')', '|']
rng = random.Random(20260922)
bad = []
for k in range(4000):
    src = "".join(rng.choice(ALPHABET) for _ in range(rng.randint(0, 40)))
    if decomment(src) != decomment_loop(src):
        bad.append(src)
check("4000 random strings agree", not bad, repr(bad[:3]))

print()
print("== 3. every .lsp in lisp/ and shared/parts/ ==")

files = lsp_files(LISP_DIR) + lsp_files(PARTS_DIR)
check("found the tree (%d files)" % len(files), len(files) > 100)
bad = [p for p in files if decomment(read(p)) != decomment_loop(read(p))]
check("all %d files decomment identically" % len(files), not bad,
      ", ".join(str(p) for p in bad[:5]))

print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("ALL DECOMMENT CHECKS PASSED (%d shapes, %d files)"
      % (len(CASES), len(files)))
