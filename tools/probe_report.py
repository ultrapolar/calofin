#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Replay a LAZDIAG failure report in the test VM, then vary its inputs.

A report says what the drafter answered, what the tool was handed, and
where it died.  It does not say WHICH answer mattered.  This does: it
loads the tool the report names, at the version it names, hands it the
report's geometry and its transcript, and confirms the failure comes
back.  Then it changes one answer at a time -- the radius that was 0
becomes 1, half, double, 1000; the point moves a unit -- and runs again,
and again, and tabulates what happened.  Three outcomes are worth
having before anyone opens the tool's source:

  * the failure is the same at every value tried -- the input is
    innocent, look at the code path, not the arithmetic;
  * any other value runs clean -- the failure is tied to exactly this
    value, and the fix is a guard on it;
  * a boundary: fails up to X, passes from Y -- the tool has a range it
    never checks for, and the table says where it is.

The replay is a REPLAY: nothing is drawn into anybody's drawing, no
AutoCAD is needed, and the drafter's file is never opened.  The tool
runs in tests/lispvm.py exactly as the test suite runs it, on the
geometry the report copied and the answers the report wrote down.
Where the VM cannot follow -- a file dialog, a whole-drawing sweep the
report could not carry -- the control run does not reproduce and this
SAYS SO rather than probing a failure that is not the one reported.

Run:  python3 tools/probe_report.py Downloads/POOL-v2.7-error-2026-09-14.dxf
      python3 tools/probe_report.py REPORT.dxf --max 40 --json
      python3 tools/probe_report.py REPORT.dxf --tool lisp/pool/POOL.LSP

Writes REPORT.probe.txt beside the report (and .probe.json with --json).
Exit 0 when the control reproduced and the probes ran, 2 when it did
not reproduce, 1 on a report that cannot be read.
"""

import json
import math
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
sys.path.insert(0, str(REPO / "tests"))
sys.path.insert(0, str(HERE))

from lispvm import (VM, LispError, Sym, T, Ent, Dot,  # noqa: E402
                    Unanswerable, NotModelled, MISS)
from callib import COMMAND, LISP_DIR, RELEASES_DIR, NOT_A_TOOL, lsp_files  # noqa: E402

ERRLAYER = "CALOFIN-ERROR"
PICKLAYER = "CALOFIN-PICKS"

#: the file-dialog and environment answers a bare VM cannot give; a run
#: that reached a dialog in AutoCAD cannot be followed here, and the
#: control run says so by not reproducing
STUBS = '''
  (defun getfiled (title dflt ext flags) nil)
  (defun vl-file-directory-p (d) nil)
'''

DEFAULT_MAX = 60


# ------------------------------------------------------------ the DXF

def read_pairs(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for i in range(0, len(lines) - 1, 2):
        code = lines[i].strip()
        if not code.lstrip("-").isdigit():
            raise ValueError("not a DXF: line %d is %r, not a group code"
                             % (i + 1, lines[i]))
        yield int(code), lines[i + 1]


def read_dxf(path):
    """(layers, entities) out of the R12 file LAZDIAG writes.  An entity
    is {"type", "layer", "g": [(code, value), ...]}; a POLYLINE carries
    its VERTEX records under "verts" and its SEQEND is dropped."""
    layers, ents = [], []
    section, cur, poly = None, None, None
    pending = None
    for code, val in read_pairs(pathlib.Path(path).read_text()):
        if code == 0 and val == "SECTION":
            pending = "section"
            continue
        if pending == "section":
            if code == 2:
                section = val
            pending = None
            continue
        if code == 0 and val == "ENDSEC":
            section = None
            cur = poly = None
            continue
        if section == "TABLES":
            if code == 0 and val == "LAYER":
                pending = "layer"
            elif pending == "layer" and code == 2:
                layers.append(val)
                pending = None
            continue
        if section != "ENTITIES":
            continue
        if code == 0:
            if val == "VERTEX" and poly is not None:
                cur = {"type": "VERTEX", "layer": "0", "g": []}
                poly["verts"].append(cur)
            elif val == "SEQEND":
                cur = poly = None
            else:
                cur = {"type": val, "layer": "0", "g": []}
                if val == "POLYLINE":
                    cur["verts"] = []
                    poly = cur
                ents.append(cur)
            continue
        if cur is None:
            continue
        if code == 8:
            cur["layer"] = val
        cur["g"].append((code, val))
    return layers, ents


def num(v):
    try:
        return float(v)
    except ValueError:
        return 0.0


def point(ent, base):
    g = dict(ent["g"])
    return (num(g.get(base, 0)), num(g.get(base + 10, 0)),
            num(g.get(base + 20, 0)))


def first(ent, code, dflt=None):
    for c, v in ent["g"]:
        if c == code:
            return v
    return dflt


# -------------------------------------------------------- the report

def report_lines(ents):
    """The report's text, top to bottom: LAZDIAG writes it as TEXT on
    its own layer, one line per entity, in reading order."""
    return [first(e, 1, "") for e in ents
            if e["type"] == "TEXT" and e["layer"] == ERRLAYER]


HEADER_KEYS = ("tool", "build", "lazdiag", "message", "last step",
               "entities", "selected", "picked points", "run started",
               "failed at")
ASK = re.compile(r"^\s*\? (.*?)\s{2,}-> (.*)$")
SELECTED = re.compile(r"(\d+) entities handed to the run = the first (\d+) ")
#: "POOL v2.7", "POOL 082726 REV17" (the older dated banner) or
#: "POOL (no version banner)"
TOOL = re.compile(r"^(\S+)\s+(v[\d.]+|\d{6} REV\d+|\(no version banner\))")
BANNER = re.compile(r'-version\*\s+"(v[\d.]+)"|\*version\*\s+"(\d{6} REV\d+)"')


def banner_of(path):
    """The version a tool file announces, in either spelling."""
    m = BANNER.search(pathlib.Path(path).read_text())
    return (m.group(1) or m.group(2)) if m else None


def rev_of(version):
    """v2.7 -> 27; 082726 REV17 -> 17: the REV a released twin carries."""
    if version.startswith("v"):
        return version[1:].replace(".", "")
    return version.rsplit("REV", 1)[-1]


class Answer:
    """One transcript line: what was asked, and what came back."""

    def __init__(self, label, enc):
        self.label = label
        self.enc = enc
        self.value = decode(enc)
        self.selection = enc.startswith("<selection of")

    def __repr__(self):
        return "Answer(%r -> %s)" % (self.label, self.enc)


def parse_report(lines):
    """The header pairs and the transcript, out of the report's text."""
    head = {}
    answers = []
    in_run = False
    for l in lines:
        if not in_run:
            for k in HEADER_KEYS:
                if l.startswith("  " + k + " ") and k not in head:
                    head[k] = l[2 + len(k):].strip()
                    break
        if l.startswith("THE RUN, PROMPT BY PROMPT"):
            in_run = True
            continue
        if in_run and re.match(r"^[A-Z][A-Z ,'-]+$", l):
            # the next section title -- WHAT ELSE HAS RUN, whose log
            # records carry prompt lines of their own shape.  The
            # transcript's own "--- POOL started" line is not one.
            in_run = False
        m = ASK.match(l) if in_run else None
        if m:
            answers.append(Answer(m.group(1).strip(), m.group(2)))
    tool, version = None, None
    m = TOOL.match(head.get("tool", ""))
    if m:
        tool = m.group(1)
        version = None if m.group(2).startswith("(") else m.group(2)
    nsel, nselp = 0, 0
    m = SELECTED.search(head.get("selected", ""))
    if m:
        nsel, nselp = int(m.group(1)), int(m.group(2))
    return {"tool": tool, "version": version, "head": head,
            "message": head.get("message", ""), "answers": answers,
            "nsel": nsel, "nselp": nselp,
            "selected_known": "selected" in head}


# ------------------------------------------- the transcript's encoding
# lzd:enc, read back: nil, T, 12, 12.5, "text" (quotes escaped \"),
# (x y z), <ent>, (<ent> (x y z)), 'SYM, (a b c).

class EntPick:
    """An entsel answer: the entity nearest the recorded click, chosen
    at replay time among the entities the report carried.  Callable,
    because the VM calls a scripted answer that is a function with
    itself at the moment the prompt is reached -- which is the only
    time the recreated entities have names."""

    def __init__(self, pt):
        self.pt = pt

    def __call__(self, vm):
        cands = [e for e in getattr(vm, "selection", []) if e not in vm.deleted]
        if not cands:
            cands = [e for e in vm.entities if e not in vm.deleted]
        if not cands:
            return None
        if self.pt is None:
            return [cands[0], [0.0, 0.0, 0.0]]
        best = min(cands, key=lambda e: ent_distance(vm, e, self.pt))
        return [best, list(self.pt)]

    def __repr__(self):
        return "<ent at %s>" % (fmt(self.pt) if self.pt else "?")


ENT = object()


def tokenize(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c.isspace():
            i += 1
        elif c in "()":
            out.append(c)
            i += 1
        elif c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\":
                    j += 2
                    continue
                if s[j] == '"':
                    break
                j += 1
            out.append(s[i:j + 1])
            i = j + 1
        else:
            j = i
            while j < n and not s[j].isspace() and s[j] not in "()":
                j += 1
            out.append(s[i:j])
            i = j
    return out


def number(t):
    if re.match(r"^-?\d+$", t):
        return int(t)
    if re.match(r"^-?(\d+\.\d*|\.\d+)([eE][-+]?\d+)?$", t):
        return float(t)
    return None


def decode(enc):
    toks = tokenize(enc)
    pos = [0]

    def parse():
        if pos[0] >= len(toks):
            return None
        t = toks[pos[0]]
        pos[0] += 1
        if t == "(":
            items = []
            while pos[0] < len(toks) and toks[pos[0]] != ")":
                items.append(parse())
            pos[0] += 1
            if items and items[0] is ENT:
                pt = items[1] if len(items) > 1 and isinstance(items[1], tuple) else None
                return EntPick(pt)
            if (2 <= len(items) <= 3
                    and all(isinstance(x, (int, float)) for x in items)):
                pt = tuple(float(x) for x in items)
                return pt if len(pt) == 3 else pt + (0.0,)
            return items
        if t == ")":
            return None
        if t == "nil":
            return None
        if t == "<miss>":
            # a click on nothing (LAZDIAG writes it for a nil with
            # ERRNO 7): replayed as one, so the tool's miss branch --
            # not its Enter branch -- is the one the replay takes
            return MISS
        if t == "T":
            return T
        if t == "<ent>":
            return ENT
        if t.startswith('"'):
            return re.sub(r"\\(.)", r"\1", t[1:-1])
        if t.startswith("'"):
            return Sym(t[1:])
        v = number(t)
        return t if v is None else v

    v = parse()
    return EntPick(None) if v is ENT else v


def fmt(v):
    if v is None:
        return "Enter"
    if isinstance(v, tuple):
        return "(%s)" % " ".join(fmt(x) for x in v)
    if isinstance(v, float):
        s = "%.6g" % v
        return s if ("." in s or "e" in s) else s + ".0"
    if isinstance(v, str) and not isinstance(v, Sym):
        return '"%s"' % v
    if isinstance(v, list):
        return "(%s)" % " ".join(fmt(x) for x in v)
    return str(v)


# --------------------------------------------------------- which tool

def command_files():
    out = {}
    for p in lsp_files(LISP_DIR):
        if NOT_A_TOOL in p.parts:
            continue
        for c in COMMAND.findall(p.read_text()):
            out.setdefault(c.upper(), p)
    return out


def find_tool(command, version, override=None):
    """(path, note) -- the file to replay from.  The released twin of
    the version the report names when there is one, the lisp/ file
    otherwise, and a note whenever the two are not the same version."""
    if override:
        return pathlib.Path(override), "replaying %s as given" % override
    files = command_files()
    src = files.get(command.upper())
    if src is None:
        raise LookupError("no tool defines c:%s under lisp/" % command)
    if version:
        rev = rev_of(version)
        pat = re.compile(re.escape(src.stem) + r"_(\d{6})_REV" + re.escape(rev)
                         + r"\.lsp$", re.I)
        twins = [(m.group(1)[4:] + m.group(1)[:4], p)
                 for p in RELEASES_DIR.glob("*")
                 for m in [pat.match(p.name)] if m]
        if twins:
            twins.sort()
            return twins[-1][1], "released twin of %s %s" % (command, version)
        have = banner_of(src) or "(no banner)"
        if have == version:
            return src, "lisp/ copy, at the report's version %s" % version
        return src, ("NOTE: the report is %s %s and no released twin of it is "
                     "here; replaying the lisp/ copy at %s instead"
                     % (command, version, have))
    return src, "lisp/ copy (the report names no version)"


# ------------------------------------------------------------ the VM

def lisp_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def p3(p):
    return "(%r %r %r)" % (float(p[0]), float(p[1]), float(p[2]))


def entmake_form(ent):
    """The (entmakex ...) that rebuilds one of the report's entities in
    the VM -- the R12 shapes LAZDIAG writes, and nothing else."""
    ty, lay = ent["type"], ent["layer"]
    base = ["'(0 . \"%s\")" % ty, "'(8 . %s)" % lisp_str(lay)]
    if ty == "LINE":
        base += ["'(10 %s" % p3(point(ent, 10))[1:],
                 "'(11 %s" % p3(point(ent, 11))[1:]]
    elif ty == "CIRCLE":
        base += ["'(10 %s" % p3(point(ent, 10))[1:],
                 "'(40 . %r)" % num(first(ent, 40, 1))]
    elif ty == "ARC":
        base += ["'(10 %s" % p3(point(ent, 10))[1:],
                 "'(40 . %r)" % num(first(ent, 40, 1)),
                 "'(50 . %r)" % math.radians(num(first(ent, 50, 0))),
                 "'(51 . %r)" % math.radians(num(first(ent, 51, 0)))]
    elif ty == "POINT":
        base += ["'(10 %s" % p3(point(ent, 10))[1:]]
    elif ty == "TEXT":
        base += ["'(10 %s" % p3(point(ent, 10))[1:],
                 "'(40 . %r)" % num(first(ent, 40, 1)),
                 "'(1 . %s)" % lisp_str(first(ent, 1, "")),
                 "'(50 . %r)" % math.radians(num(first(ent, 50, 0)))]
    elif ty == "POLYLINE":
        verts = ent.get("verts", [])
        if len(verts) < 2:
            return None
        base = ["'(0 . \"LWPOLYLINE\")", "'(8 . %s)" % lisp_str(lay),
                "'(90 . %d)" % len(verts),
                "'(70 . %d)" % int(num(first(ent, 70, 0)))]
        for v in verts:
            x, y, _ = point(v, 10)
            base.append("'(10 %r %r)" % (x, y))
            b = num(first(v, 42, 0))
            if b:
                base.append("'(42 . %r)" % b)
    else:
        return None
    return "(entmakex (list %s))" % " ".join(base)


def groups(data):
    for g in data:
        if isinstance(g, Dot):
            yield g.a, g.b
        elif isinstance(g, list) and g:
            yield g[0], (g[1:] if len(g) > 2 else g[1])


def ent_distance(vm, e, pt):
    """How far a click is from an entity: the nearest of its defining
    points, and for a circle or an arc the distance to its rim."""
    d = vm.entdata.get(e, [])
    g = dict(groups(d))
    best = float("inf")
    r = g.get(40)
    if g.get(0) in ("CIRCLE", "ARC") and isinstance(g.get(10), list):
        c = g[10]
        best = abs(math.hypot(pt[0] - c[0], pt[1] - c[1]) - float(r or 0))
    for code, v in groups(d):
        if code in (10, 11, 13, 14) and isinstance(v, list) and len(v) >= 2:
            best = min(best, math.hypot(pt[0] - v[0], pt[1] - v[1]))
    return best


class ReplayVM(VM):
    """The VM with a selection to hand back: a tool that ssgets is
    answered with the entities the report carried as the run's input,
    whatever position in the transcript that happens at."""

    def __init__(self):
        super().__init__()
        self.selection = []
        self.asked = []

    def pop_script(self, prompt, kind):
        self.asked.append((kind, prompt))
        if kind == "ssget":
            ents = [e for e in self.selection if e not in self.deleted]
            self.lastprompt = prompt
            self.prompts.append((prompt, ents))
            return list(ents) if ents else None
        return super().pop_script(prompt, kind)


class Outcome:
    OK, FAIL, DIVERGED, CRASH = "ok", "FAIL", "DIVERGED", "CRASH"

    def __init__(self, kind, message="", asked=0):
        self.kind, self.message, self.asked = kind, message, asked

    def same_as(self, other):
        return (self.kind == other.kind == Outcome.FAIL
                and norm(self.message) == norm(other.message))

    def __str__(self):
        return self.kind + (": " + self.message if self.message else "")


def norm(msg):
    return re.sub(r"\s+", " ", (msg or "").strip().lower())


def build_vm(tool_path, layers, ents, nselp, with_output):
    vm = ReplayVM()
    vm.loads(STUBS)
    vm.load(str(tool_path))
    vm.tables["LAYER"].update(l for l in layers if l)
    vm.tables["LAYER"].update(e["layer"] for e in ents)
    n = 0
    for e in ents:
        if e["layer"] in (ERRLAYER, PICKLAYER):
            continue
        n += 1
        is_input = n <= nselp
        if not is_input and not with_output:
            continue
        form = entmake_form(e)
        if not form:
            continue
        before = len(vm.entities)
        try:
            vm.loads(form)
        except LispError:
            continue
        if is_input and len(vm.entities) > before:
            vm.selection.append(vm.entities[-1])
    if vm.selection:
        vm.pickfirst = ["<ss>"] + list(vm.selection)
    vm.handle_errors = True
    vm.printed.clear()
    return vm


def run_once(tool_path, command, layers, ents, nselp, answers, with_output):
    vm = build_vm(tool_path, layers, ents, nselp, with_output)
    script = [a.value for a in answers if not a.selection]
    try:
        vm.run("c:" + command, script)
    except (Unanswerable, NotModelled) as e:
        # the VM refused an answer rather than guess at it: a replayed
        # answer that cannot be typed where the run now is (a varied
        # value that landed a prompt early or late, a spaced word at a
        # getpoint), or one it has no model of.  The run went somewhere
        # the report's did not -- that is a divergence, not a crash of
        # the probe, and the probe goes on to the next variant
        return Outcome(Outcome.DIVERGED, "the transcript's answer cannot be "
                       "given at the prompt the replay reached: %s"
                       % str(e).splitlines()[0], len(vm.prompts))
    except LispError as e:
        msg = str(e).splitlines()[0]
        if "SCRIPT EXHAUSTED" in msg:
            return Outcome(Outcome.DIVERGED, "asked more than the transcript "
                           "holds, at %s" % msg.split("prompt:", 1)[-1].strip(),
                           len(vm.prompts))
        if "scripted answers left over" in msg:
            return Outcome(Outcome.DIVERGED, "ended early, with %s"
                           % msg.split(":", 1)[0].strip(), len(vm.prompts))
        if "is not defined" in msg:
            return Outcome(Outcome.CRASH, msg, len(vm.prompts))
        return Outcome(Outcome.FAIL, msg + " (not through the handler)",
                       len(vm.prompts))
    if vm.handled_errors:
        msg = vm.handled_errors[0]
        if "SCRIPT EXHAUSTED" in msg:
            return Outcome(Outcome.DIVERGED, "asked more than the transcript "
                           "holds, at %s" % msg.split("prompt:", 1)[-1].strip(),
                           len(vm.prompts))
        return Outcome(Outcome.FAIL, msg, len(vm.prompts))
    return Outcome(Outcome.OK, "", len(vm.prompts))


# --------------------------------------------------------- the probes

def variants(v):
    """The other values to try in one answer's place.  Numbers get the
    ones that find a guard that is missing -- 1, 0, half, double, a
    step either side, ten times, a thousand -- and a point gets moved a
    unit each way, ten units, to the origin and twice as far out."""
    out = []
    if isinstance(v, bool) or v is None:
        return out
    if isinstance(v, int):
        out = [1, 0, v // 2, v * 2, v + 1, v - 1, v * 10, 1000]
    elif isinstance(v, float):
        out = [1.0, 0.0, v / 2, v * 2, v + 1, v - 1, v * 10, 1000.0]
    elif isinstance(v, tuple) and len(v) == 3:
        x, y, z = v
        out = [(x + 1, y, z), (x, y + 1, z), (x + 10, y + 10, z),
               (0.0, 0.0, z), (x * 2, y * 2, z), (x - 1, y - 1, z)]
    seen, uniq = set(), []
    for w in out:
        key = fmt(w)
        if key != fmt(v) and key not in seen:
            seen.add(key)
            uniq.append(w)
    return uniq


def plan(answers, cap):
    """[(index, variant)] -- every answer's variants, trimmed round-robin
    to CAP so a long transcript does not turn into an afternoon."""
    per = [(i, variants(a.value)) for i, a in enumerate(answers)
           if not a.selection]
    per = [(i, vs) for i, vs in per if vs]
    out, k = [], 0
    while len(out) < cap and any(k < len(vs) for _, vs in per):
        for i, vs in per:
            if k < len(vs) and len(out) < cap:
                out.append((i, vs[k]))
        k += 1
    return out


def verdict(control, rows):
    """One line on one answer, from what its variants did."""
    if not rows:
        return "not varied"
    same = [v for v, o in rows if o.same_as(control)]
    ok = [v for v, o in rows if o.kind == Outcome.OK]
    other = [(v, o) for v, o in rows
             if o.kind == Outcome.FAIL and not o.same_as(control)]
    div = [(v, o) for v, o in rows if o.kind == Outcome.DIVERGED]
    n = len(rows)
    if len(same) == n:
        return ("NOT this value: the same failure at all %d values tried, so "
                "look at the code path, not at this input" % n)
    if len(ok) == n:
        return ("THIS value: every other value tried (%s) runs clean, so the "
                "failure is tied to exactly what was given"
                % ", ".join(fmt(v) for v in ok))
    parts = []
    nums = [v for v, _ in rows if isinstance(v, (int, float))]
    if nums and len(nums) == n and (same or ok):
        fails = sorted(v for v in same)
        passes = sorted(v for v in ok)
        if fails and passes and max(fails) < min(passes):
            parts.append("fails up to %s and passes from %s: a lower bound "
                         "the tool never checks" % (fmt(max(fails)),
                                                    fmt(min(passes))))
        elif fails and passes and min(fails) > max(passes):
            parts.append("passes up to %s and fails from %s: an upper bound "
                         "the tool never checks" % (fmt(max(passes)),
                                                    fmt(min(fails))))
    if not parts:
        if same:
            parts.append("same failure at %s" % ", ".join(fmt(v) for v in same))
        if ok:
            parts.append("clean at %s" % ", ".join(fmt(v) for v in ok))
    if other:
        parts.append("a DIFFERENT failure at %s (%s)"
                     % (", ".join(fmt(v) for v, _ in other),
                        "; ".join(sorted({o.message[:60] for _, o in other}))))
    if div:
        parts.append("a different path at %s (%s)"
                     % (", ".join(fmt(v) for v, _ in div),
                        "; ".join(sorted({o.message[:60] for _, o in div}))))
    return "; ".join(parts)


# ------------------------------------------------------------- driver

class Result:
    def __init__(self):
        self.lines = []
        self.data = {}

    def say(self, s=""):
        self.lines.append(s)

    @property
    def text(self):
        return "\n".join(self.lines) + "\n"


def probe(report_path, tool_path=None, cap=DEFAULT_MAX, with_output=False,
          anyway=False, control_only=False):
    """The whole job, as a Result: its .text is what the drafter or the
    developer reads, its .data what a script does."""
    res = Result()
    report_path = pathlib.Path(report_path)
    layers, ents = read_dxf(report_path)
    rep = parse_report(report_lines(ents))
    if not rep["tool"]:
        raise ValueError("%s carries no 'tool' line: not a LAZDIAG report"
                         % report_path)
    command, version = rep["tool"], rep["version"]
    path, note = find_tool(command, version, tool_path)
    answers = rep["answers"]
    nselp = rep["nselp"]
    if not rep["selected_known"]:
        # a report from before the count was written: every copied
        # entity is handed over, output included, and the note says so
        nselp = sum(1 for e in ents if e["layer"] not in (ERRLAYER, PICKLAYER))
        note += "; an older report, so the run's own output is loaded too"
    res.data.update(report=str(report_path), tool=command, version=version,
                    source=str(path), note=note, message=rep["message"],
                    answers=[{"label": a.label, "value": a.enc}
                             for a in answers if not a.selection],
                    selection_entities=nselp)

    res.say("PROBE  %s" % report_path.name)
    res.say("  tool      %s %s" % (command, version or "(no version banner)"))
    res.say("  from      %s" % path.relative_to(REPO) if REPO in path.parents
            else "  from      %s" % path)
    res.say("  note      %s" % note)
    res.say("  failure   %s" % rep["message"])
    res.say("  handed    %d input entities%s, %d answers%s"
            % (nselp, " (+ the run's output)" if with_output else "",
               sum(1 for a in answers if not a.selection),
               (" and %d selection(s)" % sum(1 for a in answers if a.selection))
               if any(a.selection for a in answers) else ""))
    res.say()
    res.say("THE ANSWERS, AS RECORDED")
    k = 0
    for a in answers:
        if a.selection:
            res.say("       %-40s %s" % ("(selection)", a.enc))
            continue
        k += 1
        res.say("  %3d  %-40s %s" % (k, a.label[:40], fmt(a.value)))
    res.say()

    common = (path, command, layers, ents, nselp)
    control = run_once(*common, answers, with_output)
    res.data["control"] = {"kind": control.kind, "message": control.message,
                           "asked": control.asked}
    res.say("THE CONTROL RUN (the answers exactly as recorded)")
    if control.same_as(Outcome(Outcome.FAIL, rep["message"])):
        res.say("  REPRODUCED: %s" % control.message)
        reproduced = True
    elif control.kind == Outcome.FAIL:
        res.say("  fails, but not the same way: %s" % control.message)
        res.say("  (the report said: %s)" % rep["message"])
        reproduced = True
    elif control.kind == Outcome.OK:
        res.say("  DID NOT REPRODUCE: the run went clean here, through %d "
                "prompt(s)" % control.asked)
        res.say("  The VM has no drawing beyond what the report carried, so a "
                "tool that sweeps the")
        res.say("  drawing, reads a dialog, or depends on a setting the report "
                "does not hold cannot be")
        res.say("  followed here.  The failure is real; it is not one this can "
                "vary.")
        reproduced = False
    else:
        res.say("  DID NOT REPRODUCE: %s" % control)
        res.say("  The tool took a different path through its prompts than the "
                "transcript recorded, so")
        res.say("  either the transcript is incomplete or the VM cannot follow "
                "this tool that far.")
        reproduced = False
    res.data["reproduced"] = reproduced
    res.say()
    if control_only or (not reproduced and not anyway):
        res.data["probes"] = []
        return res

    todo = plan([a for a in answers if not a.selection], cap)
    plain = [a for a in answers if not a.selection]
    rows = {}
    res.say("THE PROBES (one answer changed at a time, %d runs)" % len(todo))
    probes = []
    for i, w in todo:
        varied = list(plain)
        varied[i] = Answer(plain[i].label, plain[i].enc)
        varied[i].value = w
        # the selection markers keep their places for the replay's sake
        replay, j = [], 0
        for a in answers:
            if a.selection:
                replay.append(a)
            else:
                replay.append(varied[j])
                j += 1
        out = run_once(*common, replay, with_output)
        rows.setdefault(i, []).append((w, out))
        probes.append({"answer": i + 1, "label": plain[i].label,
                       "value": fmt(w), "kind": out.kind,
                       "message": out.message})
        res.say("  %3d  %-30s = %-14s %s"
                % (i + 1, plain[i].label[:30], fmt(w),
                   ("same failure" if out.same_as(control) else str(out))[:70]))
    res.data["probes"] = probes
    res.say()
    res.say("WHAT THAT SAYS")
    verdicts = []
    for i, a in enumerate(plain):
        if i not in rows:
            continue
        v = verdict(control, rows[i])
        verdicts.append({"answer": i + 1, "label": a.label, "verdict": v})
        res.say("  %3d  %s = %s" % (i + 1, a.label[:40], fmt(a.value)))
        res.say("       %s" % v)
    if not verdicts:
        res.say("  (nothing to vary: no numeric or point answer in the "
                "transcript)")
    res.data["verdicts"] = verdicts
    return res


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    opts = {a for a in argv if a.startswith("--") and "=" not in a}
    kv = dict(a[2:].split("=", 1) for a in argv if a.startswith("--") and "=" in a)
    if not args:
        print(__doc__)
        return 1
    tool = kv.get("tool")
    if "--tool" in argv:
        i = argv.index("--tool")
        tool = argv[i + 1] if i + 1 < len(argv) else None
        args = [a for a in args if a != tool]
    cap = int(kv.get("max", DEFAULT_MAX))
    if "--max" in argv:
        i = argv.index("--max")
        cap = int(argv[i + 1])
        args = [a for a in args if a != argv[i + 1]]
    try:
        res = probe(args[0], tool_path=tool, cap=cap,
                    with_output="--with-output" in opts,
                    anyway="--anyway" in opts,
                    control_only="--control-only" in opts)
    except (ValueError, LookupError, OSError) as e:
        print("probe_report: %s" % e)
        return 1
    sys.stdout.write(res.text)
    out = pathlib.Path(args[0]).with_suffix(".probe.txt")
    if "--no-write" not in opts:
        out.write_text(res.text)
        print("written: %s" % out)
        if "--json" in opts:
            j = out.with_suffix(".json")
            j.write_text(json.dumps(res.data, indent=2))
            print("written: %s" % j)
    return 0 if res.data.get("reproduced") else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
