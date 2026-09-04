# SPDX-License-Identifier: GPL-3.0-or-later
"""Static checks over the VB palette, for a repo with no VB compiler.

``Calofin.vbproj`` targets net48 against the AutoCAD.NET reference
assemblies, so nothing here can build ``ui/calofin_net/`` -- and the
whole point of the palette is that it is the surface a drafter uses.
Until now that meant every line of it was unverified: a missing
``End Sub`` or a call on a member that had been renamed would sit in
the tree until somebody opened AutoCAD, and the person who found it
would be the person who could least afford to.

This is not a compiler and does not pretend to be.  It reads the source
the way ``check_lisp.py`` reads a ``.lsp`` -- structure, not meaning --
and catches the four mistakes that actually happen when code is written
without a build:

1. **Block structure.**  Every ``Sub``/``Function``/``Property``/
   ``Class``/``If``/``For``/``Try``/... opened is closed, by the right
   closer, in the right order.  A stray ``End Sub`` or a missing
   ``End If`` is the classic result of an edit in the middle of a long
   method.
2. **Quotes and parens**, per logical line, once continuations are
   joined -- the failure a hand-written string table produces.
3. **Members of this assembly's own types.**  ``CommandCatalog.Groups``
   is checked against what ``CommandCatalog`` actually declares.  This
   is the one that matters most now that a generator writes that class:
   a rename on either side of the seam is a build error nobody here
   could otherwise see.
4. **Constructor arity** for those same types, so a generator emitting
   ``New Entry(a, b)`` against a three-argument ``Entry`` fails at
   generation time rather than in somebody's AutoCAD.

What it deliberately does NOT do is type-check.  ``Option Strict On``
rejects a narrowing conversion and nothing here can tell ``Double``
from ``Object``; claiming otherwise would make a green run mean less
than it does.  A green run here means the file is well formed and its
references to its OWN types resolve.

    python3 tools/check_vb.py [file ...]     # default: every .vb
"""

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from callib import ROOT, read  # noqa: E402

VB_DIR = ROOT / "ui" / "calofin_net"

#: Build output, if somebody has ever built this on a machine that can.
SKIP_DIRS = {"obj", "bin"}

MODS = (r"(?:(?:Public|Private|Protected|Friend|Shared|Overrides|"
        r"Overridable|NotOverridable|MustOverride|MustInherit|"
        r"NotInheritable|Partial|Default|Iterator|Async|Shadows|"
        r"ReadOnly|WriteOnly|Static|Const|Dim|WithEvents)\s+)*")

TYPE_DECL = re.compile(
    r"^" + MODS + r"(Class|Structure|Module|Enum|Interface|Namespace)\s+"
    r"([A-Za-z_]\w*)")
ROUTINE_DECL = re.compile(
    r"^" + MODS + r"(Sub|Function|Property)\s+([A-Za-z_]\w*|New)\b")
#: A multi-line lambda: the logical line ENDS with Sub / Sub(...) /
#: Function(...).  A single-line lambda has its body on the same line
#: and opens nothing, which is the distinction this leans on.
LAMBDA = re.compile(r"\b(Sub|Function)\s*(?:\([^()]*\))?\s*$")

#: Openers that are not declarations, and the closer each one wants.
BLOCKS = [
    (re.compile(r"^If\b.*\bThen\s*$", re.I), "If", "End If"),
    (re.compile(r"^For\b", re.I), "For", "Next"),
    (re.compile(r"^While\b", re.I), "While", "End While"),
    (re.compile(r"^Do\b", re.I), "Do", "Loop"),
    (re.compile(r"^Select\s+Case\b", re.I), "Select", "End Select"),
    (re.compile(r"^Try\s*$", re.I), "Try", "End Try"),
    (re.compile(r"^With\b", re.I), "With", "End With"),
    (re.compile(r"^Using\b", re.I), "Using", "End Using"),
    (re.compile(r"^SyncLock\b", re.I), "SyncLock", "End SyncLock"),
    (re.compile(r"^Get\s*$", re.I), "Get", "End Get"),
    (re.compile(r"^Set\s*(\(.*\))?\s*$", re.I), "Set", "End Set"),
]

CLOSERS = {
    "end if": "If", "next": "For", "end while": "While", "loop": "Do",
    "end select": "Select", "end try": "Try", "end with": "With",
    "end using": "Using", "end synclock": "SyncLock", "end get": "Get",
    "end set": "Set", "end sub": "Sub", "end function": "Function",
    "end property": "Property", "end class": "Class",
    "end structure": "Structure", "end module": "Module",
    "end enum": "Enum", "end interface": "Interface",
    "end namespace": "Namespace",
}

#: Never opens a block: the body lives elsewhere or nowhere.
BODYLESS = re.compile(r"\b(?:MustOverride|Declare|Delegate)\b")

#: Trailing continuation.  VB 10 and later continue implicitly after a
#: comma or a dangling binary operator, and that is how this source is
#: written -- `AddHandler b.Click,` then the lambda on the next line.
#:
#: `Then`, `As` and `New` are deliberately NOT here.  They end a line
#: all the time and continue nothing, and treating `If x Then` as
#: unfinished swallows the whole block it opens.  Nor is `>`: an
#: attribute line (`<CommandMethod("CALOFIN")>`) would glue itself to
#: the declaration below it and stop looking like one.
CONTINUES = re.compile(
    r"(?:\s_|[,&+\-*/\\^=.]|\b(?:And|AndAlso|Or|OrElse|Xor|Mod|Like|Is|"
    r"IsNot|From)\b)\s*$", re.I)

#: What a string literal is replaced by.  A PLACEHOLDER, not blanks:
#: blanking `"(" & key & " . "` leaves a line ending in `&`, which
#: reads as a continuation and swallows the `End Function` below it.
#: The token has to be something that can end an expression.
STRTOK = "_s_"


# ------------------------------------------------------------- lexing

def strip_line(line):
    """LINE with every string literal reduced to one token and any
    comment cut, plus the count of quote marks it carried.

    A paren, a brace or an apostrophe inside a string is not code and
    must not be counted as any; a doubled quote is VB's way of writing
    one and does not end the literal.
    """
    out, i, n, quotes = [], 0, len(line), 0
    while i < n:
        ch = line[i]
        if ch == '"':
            quotes += 1
            i += 1
            while i < n:
                if line[i] != '"':
                    i += 1
                    continue
                quotes += 1
                i += 1
                if i < n and line[i] == '"':   # "" is an escaped quote
                    quotes += 1
                    i += 1
                    continue
                break
            out.append(STRTOK)
            continue
        if ch == "'":
            break
        if ch in "Rr" and (i == 0 or not (line[i - 1].isalnum()
                                          or line[i - 1] == "_")):
            if re.match(r"REM\b", line[i:], re.I):   # VB's other comment
                break
        out.append(ch)
        i += 1
    return "".join(out).rstrip(), quotes


def logical_lines(src):
    """(line number, joined code, quote count) per logical line.

    Continuations are joined so a table written across forty lines is
    balanced as the one statement it is.  Both spellings count: the
    explicit `` _`` and the implicit trailing comma or open bracket
    this source actually uses.
    """
    out, buf, start, depth, quotes = [], [], None, 0, 0
    for n, raw in enumerate(src.splitlines(), 1):
        code, q = strip_line(raw)
        if not code.strip() and not buf:
            continue
        if start is None:
            start = n
        buf.append(code.strip())
        quotes += q
        depth += code.count("(") - code.count(")")
        depth += code.count("{") - code.count("}")
        depth += code.count("[") - code.count("]")
        joined = " ".join(x for x in buf if x)
        if depth > 0 or CONTINUES.search(code.rstrip()):
            continue
        out.append((start, re.sub(r"\s+_$", "", joined).strip(), quotes))
        buf, start, quotes = [], None, 0
    if buf:
        out.append((start, " ".join(buf).strip(), quotes))
    return out


# ------------------------------------------------------------- checks

def opens(line):
    """The block kind LINE opens, or None."""
    if BODYLESS.search(line) or re.match(r"^End\b", line, re.I):
        return None
    if re.match(r"^<.*>$", line):
        return None                 # an attribute on a line of its own
    m = TYPE_DECL.match(line)
    if m:
        return m.group(1).title()
    m = ROUTINE_DECL.match(line)
    if m:
        kind = m.group(1).title()
        if kind == "Property":
            # An auto-property has no body; a block one is followed by
            # Get or Set.  The declaration line is identical either
            # way, so the caller resolves it by looking ahead.
            return "Property?"
        return kind
    for rx, kind, _ in BLOCKS:
        if rx.match(line):
            return kind
    if LAMBDA.search(line):
        return "Sub" if re.search(r"\bSub\b\s*(?:\([^()]*\))?\s*$",
                                  line, re.I) else "Function"
    return None


def structure_problems(rel, lines):
    """Blocks opened and closed, in order."""
    problems, stack = [], []
    for i, (n, line, quotes) in enumerate(lines):
        if quotes % 2:
            problems.append("%s:%d: odd number of quote marks - an "
                            "unterminated string literal" % (rel, n))
        low = line.lower()
        closer = None
        for word in ("end if", "end while", "end select", "end try",
                     "end with", "end using", "end synclock", "end get",
                     "end set", "end sub", "end function", "end property",
                     "end class", "end structure", "end module", "end enum",
                     "end interface", "end namespace"):
            if low == word or low.startswith(word + " "):
                closer = word
                break
        if closer is None and (low == "next" or low.startswith("next ")):
            closer = "next"
        if closer is None and (low == "loop" or low.startswith("loop ")):
            closer = "loop"

        if closer:
            want = CLOSERS[closer]
            if not stack:
                problems.append("%s:%d: %s closes nothing"
                                % (rel, n, line.split()[0].title()))
            elif stack[-1][0] != want:
                problems.append(
                    "%s:%d: %r closes a %s, but the block open here is "
                    "the %s at line %d"
                    % (rel, n, line, want, stack[-1][0], stack[-1][1]))
                stack.pop()
            else:
                stack.pop()
            continue

        kind = opens(line)
        if kind == "Property?":
            nxt = lines[i + 1][1].strip().lower() if i + 1 < len(lines) else ""
            kind = "Property" if (nxt == "get" or nxt.startswith("set")
                                  or nxt == "set") else None
        if kind:
            stack.append((kind, n))

    for kind, n in reversed(stack):
        problems.append("%s:%d: this %s is never closed" % (rel, n, kind))
    return problems


def paren_problems(rel, lines):
    out = []
    for n, line, _ in lines:
        for opener, closer, what in (("(", ")", "paren"),
                                     ("{", "}", "brace")):
            d = line.count(opener) - line.count(closer)
            if d:
                out.append("%s:%d: %d unmatched %s%s in %r"
                           % (rel, n, abs(d), what,
                              "" if abs(d) == 1 else "s", _clip(line)))
    return out


def _clip(line, width=72):
    return line if len(line) <= width else line[:width - 3] + "..."


# ------------------------------------------------- this assembly's types

MEMBER_DECL = re.compile(
    r"^" + MODS + r"(?:(Sub|Function|Property)\s+([A-Za-z_]\w*|New)|"
    r"([A-Za-z_]\w*)\s+As\b|([A-Za-z_]\w*)\s*=)")


#: Block kinds that are a type, and therefore own what is declared
#: directly inside them.
TYPE_KINDS = ("class", "structure", "module", "enum", "interface")


def declared(files):
    """{type: {"members", "ctors", "at", "enum"}} for this assembly.

    A member is what a caller could name: declared DIRECTLY inside the
    type, with no routine in between.  "Directly" has to be measured
    against the innermost TYPE rather than against the stack's depth --
    ``Entry`` is nested inside ``CommandCatalog``, and counting stack
    depth would file its fields as somebody's locals and then report
    every use of them as a missing member.
    """
    types = {}
    for path in files:
        rel = rel_to_root(path)
        stack = []
        for n, line, _ in logical_lines(read(path)):
            low = line.lower()
            if low.startswith("end ") and low.split()[1] in (
                    TYPE_KINDS + ("namespace", "sub", "function",
                                  "property")):
                if stack and stack[-1][0] == low.split()[1]:
                    stack.pop()
                continue
            m = TYPE_DECL.match(line)
            if m and m.group(1).lower() != "namespace":
                name = m.group(2)
                types.setdefault(name, {"members": set(), "ctors": set(),
                                        "at": (rel, n), "enum": False})
                types[name]["enum"] = m.group(1).lower() == "enum"
                # a NESTED type is a member of the one around it:
                # CommandCatalog.Entry is how a caller names it, and
                # without this every such reference reads as missing
                if stack and stack[-1][0] in TYPE_KINDS:
                    types[stack[-1][1]]["members"].add(name)
                stack.append((m.group(1).lower(), name))
                continue
            #: only a declaration sitting straight inside a type counts
            inside = stack[-1] if stack and stack[-1][0] in TYPE_KINDS \
                else None
            r = ROUTINE_DECL.match(line)
            if r:
                if inside:
                    if r.group(2) == "New":
                        types[inside[1]]["ctors"].add(_arity(line))
                    else:
                        types[inside[1]]["members"].add(r.group(2))
                if r.group(1).lower() in ("sub", "function"):
                    stack.append((r.group(1).lower(),
                                  inside[1] if inside else ""))
                continue
            if not inside:
                continue
            owner = types[inside[1]]
            if owner["enum"]:
                em = re.match(r"^([A-Za-z_]\w*)", line)
                if em:
                    owner["members"].add(em.group(1))
                continue
            fm = re.match(MODS + r"([A-Za-z_]\w*)\s+As\b", line)
            if fm and not low.startswith(("dim ", "imports ")):
                owner["members"].add(fm.group(1))
    return types


def _arity(line):
    """How many parameters the New on LINE declares."""
    m = re.search(r"\bNew\s*\((.*)\)\s*$", line)
    if not m:
        return 0
    return _args(m.group(1))


def _args(text):
    """Top-level comma-separated argument count of TEXT ('' is 0)."""
    if not text.strip():
        return 0
    depth, n = 0, 1
    for ch in text:
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif ch == "," and depth == 0:
            n += 1
    return n


def reference_problems(files, types):
    """Uses of this assembly's own types, held to what they declare."""
    problems = []
    names = set(types)
    for path in files:
        rel = rel_to_root(path)
        for n, line, _ in logical_lines(read(path)):
            for m in re.finditer(r"(?<![\w.])([A-Z]\w*)\s*\.\s*(\w+)", line):
                t, member = m.group(1), m.group(2)
                if t not in names or types[t]["enum"] and False:
                    continue
                if member not in types[t]["members"]:
                    problems.append(
                        "%s:%d: %s has no member %s (it declares %s)"
                        % (rel, n, t, member,
                           ", ".join(sorted(types[t]["members"])) or "none"))
            for m in re.finditer(r"\bNew\s+([A-Z]\w*)\s*\(", line):
                t = m.group(1)
                if t not in names:
                    continue
                arity = _args(_balanced(line, m.end() - 1))
                ctors = types[t]["ctors"] or {0}
                if arity not in ctors:
                    problems.append(
                        "%s:%d: New %s(...) passes %d argument%s; %s takes "
                        "%s" % (rel, n, t, arity, "" if arity == 1 else "s",
                                t, " or ".join(str(c)
                                               for c in sorted(ctors))))
    return problems


def _balanced(line, open_at):
    """The text inside the bracket that starts at OPEN_AT."""
    depth, out = 0, []
    for ch in line[open_at:]:
        if ch in "({[":
            depth += 1
            if depth == 1:
                continue
        elif ch in ")}]":
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
    return "".join(out)


def imports_problems(rel, lines):
    """Imports must precede every declaration; VB rejects a late one."""
    out, seen = [], False
    for n, line, _ in lines:
        if re.match(r"^Imports\b", line):
            if seen:
                out.append("%s:%d: Imports after a declaration - VB wants "
                           "them all at the top of the file" % (rel, n))
        elif not re.match(r"^(Option|#)", line):
            seen = True
    return out


# -------------------------------------------------------------- driver

def vb_files(paths=None):
    if paths:
        return [pathlib.Path(p).resolve() for p in paths]
    return sorted(p for p in VB_DIR.rglob("*.vb")
                  if not SKIP_DIRS & set(p.relative_to(VB_DIR).parts))


def rel_to_root(path):
    """PATH as the tree names it, or as given when it is outside the
    tree -- a named file can be anywhere, and a crash is a poor way to
    say so."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def check(paths=None):
    files = vb_files(paths)
    problems = []
    for path in files:
        rel = rel_to_root(path)
        lines = logical_lines(read(path))
        problems += structure_problems(rel, lines)
        problems += paren_problems(rel, lines)
        problems += imports_problems(rel, lines)
    problems += reference_problems(files, declared(files))
    return files, problems


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="*", help="default: every .vb under "
                                             "ui/calofin_net")
    args = ap.parse_args(argv)

    files, problems = check(args.files or None)
    for p in problems:
        print(p)
    if problems:
        print("\ncheck_vb: %d problem(s) in %d file(s)"
              % (len(problems), len(files)))
        return 1
    print("check_vb: %d file(s), blocks balanced, own members resolve"
          % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
