"""Form-driven SPA: prove the palette path draws exactly what the
command line draws.

The palette hands SPA.LSP an answers alist instead of typing at the
prompts.  The claim that makes that safe is equivalence -- same job in,
same geometry out -- so every scenario below runs the SAME spa twice,
once through the prompts and once through a form, and compares every
entity the command left in the drawing.

Also covers the half-filled form, which is the point of the feature: a
key that is absent still gets prompted for, so a user can fill in the
measurements they have and answer the rest at the command line.

KNOWN FAILING as of the branch consolidation: this file was written
against calofin_net's forked copy of SPA.LSP. lisp/spa/SPA.LSP is now
the canonical, actively-developed version instead (see the repo
README), and its prompt sequence has since diverged from what the
palette's LispBridge expects. Expect this to fail until the palette is
reconciled with the canonical SPA.LSP - that's tracked work, not a
regression from the restructure.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, parse_all  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..', 'lisp', 'spa', 'SPA.LSP')


def snapshot(vm):
    """Every entity still in the drawing, reduced to comparable data."""
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
    vm.run('c:SPA', script)
    return vm


def by_form(form_src, script):
    vm = VM()
    vm.load(LSP)
    vm.eval(parse_all("(setq spa:*form* %s)" % form_src)[0])
    vm.run('c:SPA', script)
    return vm


def same(a, b, label):
    sa, sb = snapshot(a), snapshot(b)
    if sa != sb:
        only_a = [x for x in sa if x not in sb]
        only_b = [x for x in sb if x not in sa]
        raise AssertionError(
            "[%s] geometry differs: %d entities only from the prompts, "
            "%d only from the form\n  prompts: %s\n  form:    %s"
            % (label, len(only_a), len(only_b),
               only_a[:2], only_b[:2]))
    if not sa:
        raise AssertionError("[%s] nothing was drawn at all" % label)
    return sa


# --------------------------------------------------------------------
# 1.  A fully specified form draws the same spa as the prompts, and
#     asks nothing it was given.
# --------------------------------------------------------------------
print("== 1. full form == command line ==")

PROMPTS = [None,                       # skip the Spa Cover Details block
           "Watersedge", "Rectangle", (0, 0),
           84.0, 72.0,                 # overall width / length
           "Square", "Square", "Square", "Square",     # corners A..D
           "No",                       # no cover size
           "No"]                       # no auto-hinge

FULL = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
            (w . 84.0) (l . 72.0)
            (cornera-ty . "Square") (cornerb-ty . "Square")
            (cornerc-ty . "Square") (cornerd-ty . "Square"))"""

a = by_prompts(PROMPTS)
b = by_form(FULL, [None, "No", "No"])
ents = same(a, b, "full form")
print("   %d entities identical; form answered %d of %d questions"
      % (len(ents), len(a.prompts) - len(b.prompts), len(a.prompts)))
assert len(b.prompts) < len(a.prompts), "form did not remove any prompts"


# --------------------------------------------------------------------
# 2.  A half-filled form: the overalls are known, the corners are not.
#     The corners must still be asked, and the result must be the same
#     spa as if everything had been typed.
# --------------------------------------------------------------------
print("== 2. half-filled form still prompts for what is missing ==")

PARTIAL = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
               (w . 84.0) (l . 72.0))"""

c = by_form(PARTIAL, [None, "Square", "Square", "Square", "Square", "No", "No"])
same(a, c, "partial form")
asked = [p for p, _ in c.prompts if 'Corner' in p]
assert len(asked) == 4, "expected the 4 corners to be asked, got %d" % len(asked)
assert not any('WIDTH' in p or 'LENGTH' in p for p, _ in c.prompts), \
    "a supplied overall was asked for anyway"
print("   overalls taken from the form, all 4 corners still prompted")


# --------------------------------------------------------------------
# 3.  A corner given in the form is not asked; a corner left out of the
#     same form still is.  Mixed entry has to work per field, not just
#     per block.
# --------------------------------------------------------------------
print("== 3. per-field mixing inside one block ==")

MIXED = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
             (w . 84.0) (l . 72.0)
             (cornera-ty . "Square") (cornerb-ty . "Square"))"""

d = by_form(MIXED, [None, "Square", "Square", "No", "No"])
same(a, d, "mixed form")
asked = [p for p, _ in d.prompts if 'Corner' in p]
assert len(asked) == 2, "expected 2 corners asked, got %d" % len(asked)
assert 'Corner C' in asked[0] and 'Corner D' in asked[1], \
    "the wrong corners were asked: %r" % asked
print("   corners A/B taken from the form, C/D prompted")


# --------------------------------------------------------------------
# 4.  Radius corners survive the round trip -- a treatment that carries
#     a size, not just a keyword.
# --------------------------------------------------------------------
print("== 4. a treatment carrying a size ==")

RAD_PROMPTS = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
               "Radius", 12.0, "Radius", 12.0,
               "Radius", 12.0, "Radius", 12.0,
               "No", "No"]
RAD_FORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
                (w . 84.0) (l . 72.0)
                (cornera-ty . "Radius") (cornera-sz . 12.0)
                (cornerb-ty . "Radius") (cornerb-sz . 12.0)
                (cornerc-ty . "Radius") (cornerc-sz . 12.0)
                (cornerd-ty . "Radius") (cornerd-sz . 12.0))"""

e = by_prompts(RAD_PROMPTS)
f = by_form(RAD_FORM, [None, "No", "No"])
same(e, f, "radius corners")
print("   12\" radius corners identical from both paths")


# --------------------------------------------------------------------
# 5.  The form must not survive the command.  A form run followed by a
#     plain SPA has to ask everything again, or the palette would
#     silently poison the next command-line run.
# --------------------------------------------------------------------
print("== 5. answers do not leak into the next run ==")

g = VM()
g.load(LSP)
g.script = [None, "No", "No"]      # what the form did not answer
g.prompts = []
g.eval(parse_all("(spa:run-with-answers %s)" % FULL)[0])
leaked = g.globals.get('spa:*form*')
assert not leaked, "spa:*form* still armed after the run: %r" % (leaked,)
print("   spa:*form* cleared once the command finished")


# --------------------------------------------------------------------
# 6.  The wire format.
#
#     The palette cannot be compiled or run here, so the one thing that
#     CAN be pinned down is the text it puts on the wire.  These are the
#     exact strings LispBridge builds -- quoted alist, invariant-culture
#     decimals, a point as a plain list rather than a dotted pair -- fed
#     to the real SPA.LSP.  If the bridge's format is wrong, this breaks.
# --------------------------------------------------------------------
print("== 6. the exact expression the palette sends ==")

WIRE = ("(spa:run-with-answers '("
        '(mode . "Watersedge") (shape . "Rectangle") '
        "(w . 84.0) (l . 72.0) "
        '(cornera-ty . "Square") (cornerb-ty . "Square") '
        '(cornerc-ty . "Square") (cornerd-ty . "Square")'
        "))")

h = VM()
h.load(LSP)
# The palette deliberately does NOT send 'base: the insertion point is
# still picked in the drawing, where the user's own snaps are live.
h.script = [None, (0, 0), "No", "No"]
h.prompts = []
h.eval(parse_all(WIRE)[0])
same(a, h, "wire format")
picked = [p for p, _ in h.prompts if 'base point' in p]
assert len(picked) == 1, "the insertion point should still be picked"
print("   palette's literal parses and draws the same spa")
print("   insertion point still picked in the drawing, as intended")

# a blank field goes out as an explicit nil, and must be accepted as NA
# rather than crashing or being mistaken for a missing key
NIL_WIRE = ("(spa:run-with-answers '("
            '(mode . "Watersedge") (shape . "Rectangle") '
            "(w . 84.0) (l . 72.0) (cornera-sz . nil)"
            "))")
i = VM()
i.load(LSP)
i.script = [None, (0, 0), "Square", "Square", "Square", "Square", "No", "No"]
i.prompts = []
i.eval(parse_all(NIL_WIRE)[0])
same(a, i, "explicit nil")
print("   an explicit nil is taken as NA, not as a missing key")


print("\nALL SPA FORM SCENARIOS PASSED")
