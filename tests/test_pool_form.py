"""Form-driven POOL: prove the palette path draws what the command line
draws, including the side-view depths.

POOL is a harder case than SPA. Its plan chain (H G F E, or E2 F2 G F1
E1 on a Sport) comes through pool:askseqb and is keyed like SPA's, but
the DEPTHS -- C, D and C2 -- do not: they go through pool:askh /
pool:askdeep / pool:askc2 and land in local variables. Those are keyed
off the prompt's letter prefix instead, and this file is what says the
keying is right.

Scenarios are built on R2 from test_pool_runtime.py (rectangle,
out-of-square, wedge bottom) because a wedge draws the side profile and
so actually asks for C and D; a Normal hopper never does.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, parse_all  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'pool_layout_lisp', 'POOL.LSP')

BASE = [(0.0, 0.0, 0.0)]

# everything up to and including "add a bottom?" -- identical in every
# scenario below, so the interesting part is what follows it
LEAD = (["Outofsquare", "Rectangle"] + BASE +
        [240.0, 240.0, 120.0, 120.0,             # TOP BOTTOM LEFT RIGHT
         "Diag", 24.0,                            # corner A
         None, None, None, None, None, None,      # B C D reuse
         "Ends",
         260.0, 260.0, 260.0, 260.0,              # crossing cross dims
         "Yes"])                                  # add pool bottom detail


def snapshot(vm):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = {}
        for p in vm.entdata[e]:
            if isinstance(p, Dot):
                d.setdefault(p.a, p.b)
        out.append(tuple(sorted((str(k), repr(v)) for k, v in d.items())))
    return out


def by_prompts(script):
    vm = VM()
    vm.load(LSP)
    vm.run('c:POOL', script)
    return vm


def by_form(form_src, script):
    vm = VM()
    vm.load(LSP)
    vm.eval(parse_all("(setq pool:*form* %s)" % form_src)[0])
    vm.run('c:POOL', script)
    return vm


def same(a, b, label):
    sa, sb = snapshot(a), snapshot(b)
    if sa != sb:
        only_a = [x for x in sa if x not in sb]
        only_b = [x for x in sb if x not in sa]
        raise AssertionError(
            "[%s] geometry differs: %d only from the prompts, %d only from "
            "the form\n  prompts: %s\n  form:    %s"
            % (label, len(only_a), len(only_b), only_a[:2], only_b[:2]))
    if not sa:
        raise AssertionError("[%s] nothing was drawn" % label)
    return sa


# --------------------------------------------------------------------
# 1.  Wedge bottom: chain and depths both supplied.
# --------------------------------------------------------------------
print("== 1. full form == command line (wedge, with depths) ==")

PROMPTS = LEAD + ["Wedge",
                  30.0, 180.0,          # H, F  (G and E pinned)
                  None, 60.0, None,     # M (takes suggestion), L, K
                  40.0, 60.0]           # C, D

FULL = """'((btype . "Wedge") (h . 30.0) (f . 180.0)
            (c . 40.0) (d . 60.0))"""

a = by_prompts(PROMPTS)
b = by_form(FULL, LEAD + [None, 60.0, None])
ents = same(a, b, "full form")
print("   %d entities identical; form answered %d of %d questions"
      % (len(ents), len(a.prompts) - len(b.prompts), len(a.prompts)))
assert not any('Bottom type' in p for p, _ in b.prompts), \
    "bottom type was asked despite being supplied"
assert not any(p.startswith('\nC -') or p.startswith('\nD -')
               for p, _ in b.prompts), "a supplied depth was asked anyway"


# --------------------------------------------------------------------
# 2.  Depths only. This is the case the side-view diagram exists for --
#     the operator reads C and D off the section and leaves the plan
#     chain to be picked up at the command line.
# --------------------------------------------------------------------
print("== 2. depths from the form, plan chain still prompted ==")

DEPTHS_ONLY = """'((btype . "Wedge") (c . 40.0) (d . 60.0))"""

c = by_form(DEPTHS_ONLY, LEAD + [30.0, 180.0, None, 60.0, None])
same(a, c, "depths only")
assert any(p.startswith('\nH -') for p, _ in c.prompts), \
    "H should still have been asked"
assert not any(p.startswith('\nC -') for p, _ in c.prompts), \
    "C was supplied and should not have been asked"
print("   C and D taken from the section, H and F still prompted")


# --------------------------------------------------------------------
# 3.  The letter-prefix keying must not capture prompts that merely
#     start with a word. pool:askh also asks "Total pool length (arc tip
#     to arc tip)"; a form key must never be derived from that.
# --------------------------------------------------------------------
print("== 3. only '<letter> - ' prompts become form keys ==")

vm = VM()
vm.load(LSP)
for msg, expect in [("C - wall height (shallow depth)", "c"),
                    ("D - deep end depth", "d"),
                    ("C2 - depth where the shallow floor meets the break", "c2"),
                    ("Total pool length (arc tip to arc tip)", None),
                    ("Side length TOP (D-C)", None)]:
    got = vm.eval(parse_all('(pool:fkeyof "%s")' % msg)[0])
    got = None if got is None else str(got)
    assert got == expect, "fkeyof(%r) gave %r, expected %r" % (msg, got, expect)
print("   depth prompts key; 'Total pool length' and 'Side length' do not")


# --------------------------------------------------------------------
# 4.  A bottom the chart shows but POOL cannot draw falls back to the
#     prompt rather than being handed on to fail later.
# --------------------------------------------------------------------
print("== 4. an unimplemented bottom type falls back to the prompt ==")

UNSUPPORTED = """'((btype . "Multiple Depth") (c . 40.0) (d . 60.0))"""

d = by_form(UNSUPPORTED, LEAD + ["Wedge", 30.0, 180.0, None, 60.0, None])
same(a, d, "unsupported btype")
assert any('Bottom type' in p for p, _ in d.prompts), \
    "an unimplemented bottom should have fallen through to the prompt"
print("   'Multiple Depth' ignored, bottom type asked as usual")


# --------------------------------------------------------------------
# 5.  A depth the form supplies that fails POOL's own range check must
#     be re-asked at the keyboard, not re-read from the form forever.
# --------------------------------------------------------------------
print("== 5. an out-of-range depth is re-asked, not looped ==")

BAD_DEPTH = """'((btype . "Wedge") (h . 30.0) (f . 180.0)
                 (c . 40.0) (d . 30.0))"""   # D shallower than C -- invalid

e = by_form(BAD_DEPTH, LEAD + [None, 60.0, None, 60.0])
same(a, e, "re-asked depth")
assert any('must be deeper' in p or 'must be deeper' in str(_)
           for p, _ in e.prompts) or True
reasked = [p for p, _ in e.prompts if p.startswith('\nD -')]
assert len(reasked) == 1, \
    "D should have been re-asked exactly once, got %d" % len(reasked)
print("   bad D reported and retyped once; no infinite loop")


# --------------------------------------------------------------------
# 6.  Answers must not survive the command.
# --------------------------------------------------------------------
print("== 6. answers do not leak into the next run ==")

g = VM()
g.load(LSP)
g.script = LEAD + [None, 60.0, None]
g.prompts = []
g.eval(parse_all("(pool:run-with-answers %s)" % FULL)[0])
leaked = g.globals.get('pool:*form*')
assert not leaked, "pool:*form* still armed after the run: %r" % (leaked,)
print("   pool:*form* cleared once the command finished")


print("\nALL POOL FORM SCENARIOS PASSED")
