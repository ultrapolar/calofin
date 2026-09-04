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

The receiving end is lisp/spa/SPA.LSP's answer store -- spa:*form*,
spa:fhas / spa:ftake (consume-once), spa:run-with-answers, and the
hooks in its ask helpers -- the same store POOL carries.  Two prompts
stay interactive by design and appear in every script below: the Spa
Cover Details block pick (an entsel in the drawing) and the spillaway
loop.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, Dot, Ent, parse_all  # noqa: E402

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
    # Entity ids number a process-wide counter, and a handle can be
    # BAKED into an entity that round-trips through entget/entmod (the
    # overlap dimension does, via DIMTEDIT).  Restarting the counter
    # per run makes handles a fact about the drawing rather than about
    # how many runs came before it -- two equivalent runs then agree
    # on every group, the baked handle included.
    Ent._n = 0
    vm = VM()
    vm.load(LSP)
    vm.run('c:SPA', script)
    return vm


def by_form(form_src, script):
    Ent._n = 0                       # see by_prompts
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
           "No",                       # corners not all the same...
           "90", "90", "90", "90",     # ... so A..D, one at a time
           "No",                       # no cover size
           "No"]                       # no auto-hinge

FULL = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
            (w . 84.0) (l . 72.0)
            (cornera-ty . "90") (cornerb-ty . "90")
            (cornerc-ty . "90") (cornerd-ty . "90"))"""

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

c = by_form(PARTIAL, [None, "No", "90", "90", "90", "90", "No", "No"])
same(a, c, "partial form")
asked = [p for p, _ in c.prompts if 'Corner' in p]
assert len(asked) == 4, "expected the 4 corners to be asked, got %d" % len(asked)
assert not any('WIDTH' in p or 'LENGTH' in p for p, _ in c.prompts), \
    "a supplied overall was asked for anyway"
assert any('all four corners the same' in p for p, _ in c.prompts), \
    "the all-same gate was not asked for a form that named no corner"
print("   overalls taken from the form, the gate and all 4 corners prompted")


# --------------------------------------------------------------------
# 3.  A corner given in the form is not asked; a corner left out of the
#     same form still is.  Mixed entry has to work per field, not just
#     per block.
# --------------------------------------------------------------------
print("== 3. per-field mixing inside one block ==")

MIXED = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
             (w . 84.0) (l . 72.0)
             (cornera-ty . "90") (cornerb-ty . "90"))"""

d = by_form(MIXED, [None, "90", "90", "No", "No"])
same(a, d, "mixed form")
assert not any('all four corners the same' in p for p, _ in d.prompts), \
    "a form that filled in corner B was asked the gate anyway"
asked = [p for p, _ in d.prompts if 'Corner' in p]
assert len(asked) == 2, "expected 2 corners asked, got %d" % len(asked)
assert 'Corner C' in asked[0] and 'Corner D' in asked[1], \
    "the wrong corners were asked: %r" % asked
print("   corners A/B taken from the form, C/D prompted, gate not asked")


# --------------------------------------------------------------------
# 4.  Radius corners survive the round trip -- a treatment that carries
#     a size, not just a keyword.
# --------------------------------------------------------------------
print("== 4. a treatment carrying a size ==")

RAD_PROMPTS = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
               "No",                    # one at a time, like the form
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
        '(cornera-ty . "90") (cornerb-ty . "90") '
        '(cornerc-ty . "90") (cornerd-ty . "90")'
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
i.script = [None, (0, 0), "No", "90", "90", "90", "90", "No", "No"]
i.prompts = []
i.eval(parse_all(NIL_WIRE)[0])
same(a, i, "explicit nil")
print("   an explicit nil is taken as NA, not as a missing key")


# --------------------------------------------------------------------
# 7.  Back onto a corner the form answered.  Consume-once is what makes
#     this terminate: corner B's stored answer was used (and removed)
#     on the way forward, so Backing from C onto B PROMPTS for B
#     instead of the store instantly re-answering it and walking
#     forward again -- the deadlock ui/PLAN.md D3 exists to prevent.
# --------------------------------------------------------------------
print("== 7. Back re-opens a form-answered corner at the keyboard ==")

BACKED = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
              (w . 84.0) (l . 72.0)
              (cornerb-ty . "90"))"""

j = by_form(BACKED, [None,
                     "90",              # corner A
                     "Back",            # at corner C -- step back onto B
                     "90",              # corner B, now PROMPTED
                     "90", "90",        # corners C and D again
                     "No", "No"])
same(a, j, "back onto a consumed corner")
# SPA asks the canonical Treatment question now ("How should Corner A
# be treated?"), so the label is pulled out of the sentence rather than
# off the front of it - the ORDER is what this scenario is about
corner_seq = [re.search(r'Corner [A-D]', p).group(0)
              for p, _ in j.prompts if 'Corner' in p]
assert corner_seq == ['Corner A', 'Corner C', 'Corner B', 'Corner C',
                      'Corner D'], \
    "unexpected corner prompt order: %r" % (corner_seq,)
print("   B answered by the form going forward, prompted after Back")


# --------------------------------------------------------------------
# 8.  Round: the one-measurement shape.  A stored numeric b alone is
#     the diameter; a stored a alongside it means the two axes were
#     measured, which is the Outofround branch (b stays in the store
#     for the axis sequence to consume).
# --------------------------------------------------------------------
print("== 8. round: diameter from the form, and the out-of-round pair ==")

RND_PROMPTS = [None, "Watersedge", "ROund", (0, 0),
               96.0,                    # the diameter
               "No", "No"]
RND_FORM = """'((mode . "Watersedge") (shape . "ROund") (base 0.0 0.0)
                (b . 96.0))"""

r1 = by_prompts(RND_PROMPTS)
r2 = by_form(RND_FORM, [None, "No", "No"])
same(r1, r2, "round diameter")
assert not any('Overall diameter' in p for p, _ in r2.prompts), \
    "the diameter was asked despite the form supplying b"

OOR_PROMPTS = [None, "Watersedge", "ROund", (0, 0),
               "Outofround", 96.0, 84.0,
               "No", "No"]
OOR_FORM = """'((mode . "Watersedge") (shape . "ROund") (base 0.0 0.0)
                (b . 96.0) (a . 84.0))"""

r3 = by_prompts(OOR_PROMPTS)
r4 = by_form(OOR_FORM, [None, "No", "No"])
same(r3, r4, "out-of-round")
assert not any('Overall diameter' in p or 'overall size' in p
               for p, _ in r4.prompts), \
    "an axis was asked despite the form supplying both"
print("   b alone = the diameter; b with a = the Outofround path")


# --------------------------------------------------------------------
# 9.  Octagon: the sheet letters ride spa:askseqb, so an explicit
#     (key . nil) must land as NA -- asked of nobody -- while the
#     measured letters skip their prompts the same way.
# --------------------------------------------------------------------
print("== 9. octagon: explicit nils ride the sequence as NA ==")

OCT_PROMPTS = [None, "Watersedge", "OCtagon", (0, 0),
               96.0, 84.0,              # B, A
               24.0,                    # S2 -- the cut face
               "NA", "NA", "NA", "NA",  # T, S, S1, V
               "No", "No"]
OCT_FORM = """'((mode . "Watersedge") (shape . "OCtagon") (base 0.0 0.0)
                (b . 96.0) (a . 84.0) (s2 . 24.0)
                (tt . nil) (ss . nil) (s1 . nil) (vv . nil))"""

o1 = by_prompts(OCT_PROMPTS)
o2 = by_form(OCT_FORM, [None, "No", "No"])
same(o1, o2, "octagon nils")
assert len(o2.prompts) == 3, \
    "expected only the block pick and the two offers, got %r" \
    % [p for p, _ in o2.prompts]
print("   measured letters skipped, nil letters taken as NA unasked")


# --------------------------------------------------------------------
# 10. The cover questions: the offer of the second outline, the
#     method, the lap and the auto-hinge gate all have form keys.
#     With every one of them answered, the only interaction left is
#     the Spa Cover Details pick, which stays in the drawing by
#     design.
# --------------------------------------------------------------------
print("== 10. second / method / gap / autohinge from the form ==")

CVR_PROMPTS = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
               "No", "90", "90", "90", "90",
               "Yes",                   # draw the cover as well
               "Offset",                # take it from
               3.0,                     # the lap
               "No"]                    # no auto-hinge
CVR_FORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
                (w . 84.0) (l . 72.0)
                (cornera-ty . "90") (cornerb-ty . "90")
                (cornerc-ty . "90") (cornerd-ty . "90")
                (second . "Yes") (method . "Offset") (gap . 3.0)
                (autohinge . "No"))"""

c1 = by_prompts(CVR_PROMPTS)
c2 = by_form(CVR_FORM, [None])
same(c1, c2, "cover keys")
assert len(c2.prompts) == 1 and 'Spa Cover Details' in c2.prompts[0][0], \
    "expected only the Spa Cover Details pick, got %r" \
    % [p for p, _ in c2.prompts]
print("   both outlines from one form; only the block pick remained")


# --------------------------------------------------------------------
# 11. Grade and taper from the form: spa:askdetails finds them already
#     set, so neither the second Spa Cover Details offer nor the taper
#     getstring appears.  They are consumed BEFORE the Thermo-Light
#     branch, so a form grade behaves exactly like one read off the
#     block.  The spillaway loop stays interactive.
# --------------------------------------------------------------------
print("== 11. grade/taper from the form: no taper prompt ==")

GT_PROMPTS = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
              "No", "90", "90", "90", "90",
              "No",                     # no second outline
              "Yes",                    # auto-hinge
              "No",                     # no spillaway
              None,                     # the block, offered again -- skip
              "4-2"]                    # the taper, typed
GT_FORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
               (w . 84.0) (l . 72.0)
               (cornera-ty . "90") (cornerb-ty . "90")
               (cornerc-ty . "90") (cornerd-ty . "90")
               (second . "No") (autohinge . "Yes")
               (grade . "Standard") (taper . "4-2"))"""

g1 = by_prompts(GT_PROMPTS)
g2 = by_form(GT_FORM, [None, "No"])    # the block pick, one spillaway No
same(g1, g2, "grade+taper")
assert not any('Taper' in p for p, _ in g2.prompts), \
    "the taper was asked despite the form supplying it"
assert len([p for p, _ in g2.prompts if 'Spa Cover Details' in p]) == 1, \
    "the block should only have been offered once (up front)"
print("   hinges laid out from the form's Standard 4-2; taper never asked")


# --------------------------------------------------------------------
# 12. Answers nothing consumed still do not leak.  'method and 'gap
#     are armed but the run answers No to the second outline, so
#     neither is ever read -- the exit clear inside c:SPA itself (the
#     direct path, no run-with-answers to tidy up after it) must still
#     drop them, or they would lie in wait for the next command-line
#     SPA.
#
#     The *error*-path (spa:fclear) cannot be driven from here: the
#     VM's SCRIPT EXHAUSTED is a Python-side failure that bypasses the
#     LISP *error* handler entirely, so scenario 5 and this one pin
#     the clears on both entry paths' normal exits instead.
# --------------------------------------------------------------------
print("== 12. unread answers are dropped on the way out ==")

STALE = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
              (w . 84.0) (l . 72.0)
              (cornera-ty . "90") (cornerb-ty . "90")
              (cornerc-ty . "90") (cornerd-ty . "90")
              (method . "Offset") (gap . 3.0))"""

k = by_form(STALE, [None, "No", "No"])
same(a, k, "unread keys")
left = k.globals.get('spa:*form*')
assert not left, "unconsumed answers survived the run: %r" % (left,)
print("   method/gap never read, and gone all the same")

# --------------------------------------------------------------------
# 13. Back onto a form-answered DISTANCE must PROMPT, not self-answer.
#     The store consumes an answer as it is used; if that ever becomes
#     "mark used" the sequence below walks Back into an answer that
#     re-feeds itself and the user can never get out.
# --------------------------------------------------------------------
print("== 13. Back over a consumed distance prompts at the keyboard ==")

BACKFORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
                (w . 84.0))"""
j = by_form(BACKFORM, [None,      # skip the Spa Cover Details block
                       "Back",    # at the length: back onto the width
                       84.0,      # the width again - AT THE KEYBOARD
                       72.0,      # the length
                       "No", "90", "90", "90", "90", "No", "No"])
same(a, j, "back over a consumed answer")
wasked = [p for p, _ in j.prompts if 'WIDTH' in p]
assert len(wasked) == 1, \
    "the width should be asked exactly once (the post-Back re-ask), " \
    "got %d" % len(wasked)
print("   width form-answered, backed onto, and re-asked at the keyboard")


# --------------------------------------------------------------------
# 14. Every key the palette CAN send is one the routine reads.  The
#     alignment audit in ui/PLAN.md was true the day it was written;
#     this keeps it true: a key added to the field map that SPA never
#     consumes fails here instead of vanishing silently.
# --------------------------------------------------------------------
print("== 14. the field map sends no key the routine cannot read ==")

import json
import re as _re

FIELDMAP = os.path.join(os.path.dirname(__file__), '..', 'ui',
                        'calofin_net', 'assets', 'shapes', 'fieldmap.json')


def _map_keys(node, out):
    if isinstance(node, dict):
        if isinstance(node.get('key'), str):
            out.add(node['key'].lower())
        for v in node.values():
            _map_keys(v, out)
    elif isinstance(node, list):
        for v in node:
            _map_keys(v, out)
    return out


_fm = json.load(open(FIELDMAP))
sent = _map_keys({k: v for k, v in _fm.items()
                  if k in ('shapes', '_secondOutline')}, set())
_src = open(LSP, encoding='utf-8', errors='replace').read()
# SPA takes a keyed answer two ways, and the check has to know both or
# it rejects a legitimate key: the (list 'k 'REQ) tables that askseqb
# walks, and the ask helpers that carry their own key -- askdf, askkwf
# and friends.  Both are read off SPA.LSP rather than typed here.
readable = set(m.group(1).lower() for m in
               _re.finditer(r"\(list\s+'([a-z][a-z0-9]*)\s+'(?:REQ|NAX|ZER|SUG)",
                            _src))
readable |= set(m.group(1).lower() for m in
                _re.finditer(r"\(spa:(?:askdf|askkwf|askseqb|asknum)\s+'([a-z][a-z0-9]*)",
                             _src))
readable |= set(m.group(1).lower() for m in
                _re.finditer(r"\(spa:f(?:has|take)\s+'([a-z][a-z0-9]*)", _src))
unread = sorted(sent - readable)
assert not unread, \
    "the spa field map sends keys SPA.LSP never reads: %s" % unread
print("   %d field-map keys, every one a keyed item in SPA.LSP" % len(sent))


# --------------------------------------------------------------------
# 15. The two form surfaces ask the same questions.
#
#     SPA has two forms in front of it: LAZSPA's DCL chart and the VB
#     palette.  A question one can answer and the other cannot is not a
#     bug -- SPA just asks at the command line -- but it is a gap
#     nobody would notice, and the roster halves of these two surfaces
#     had already parted once (the palette shipped 60 of the panel's
#     67 commands).
#
#     THE FIELD MAP IS NOT THE WHOLE PALETTE.  fieldmap.json describes
#     the fields anchored to the ARTWORK plus the second-outline
#     overalls; the cover block -- mode, second, method, gap,
#     autohinge, grade, taper -- and the shape itself are carried by
#     SpaFormView.vb's own view model and never appear in the JSON.
#     Reading the map alone therefore says the palette cannot ask for
#     the cover lap, which is wrong.  So the palette's surface is read
#     from BOTH files, and the VB literals are parsed rather than
#     listed, so a key it stops sending fails here.
# --------------------------------------------------------------------
print("== 15. LAZSPA and the palette ask the same questions ==")

LAZSPA = os.path.join(os.path.dirname(__file__), '..', 'lisp', 'lazspa',
                      'LAZSPA.lsp')
VBFORM = os.path.join(os.path.dirname(__file__), '..', 'ui', 'calofin_net',
                      'SpaFormView.vb')

_vb = open(VBFORM, encoding='utf-8', errors='replace').read()
# ANY list, not just one called "pairs".  The form now builds two --
# literals, which travel as written, and measures, which are read on the
# Lisp side by the same reader the DCL charts use -- and reading only
# the first would quietly stop checking every measurement on the sheet.
vb_literal = set(m.group(1).lower() for m in _re.finditer(
    r'\w+\.Add\(LispBridge\.\w+\("([a-z0-9]+)"', _vb))
assert vb_literal, "no LispBridge pairs found - has SpaFormView.vb been reshaped?"

_lv = VM()
_lv.load(LAZSPA)
_lv.loads('(setq t:*charts* lzs:*charts*)')
_bykey = {str(c[0]).lower(): str(c[0]) for c in _lv.globals['t:*charts*']}

# the shape word is matched WITHOUT case by spa:fshape, which is why
# the map's "ROUnd" and LAZSPA's "ROund" are both right; the pairing
# here is case-insensitive for the same reason
for _sid, _sh in _fm['shapes'].items():
    _real = _bykey.get(_sh['lispShape'].lower())
    assert _real, ("the field map's %s names lispShape %r, which is no "
                   "LAZSPA chart: %s"
                   % (_sid, _sh['lispShape'], sorted(_bykey.values())))
    palette = set(vb_literal)
    for _d in _sh.get('dimensions', []):
        palette.add(_d['key'].lower())
    for _c in _sh.get('corners', []):
        palette.add(_c['typeKey'].lower())
        palette.add(_c['sizeKey'].lower())
    for _f in _fm['_secondOutline']['fields']:
        if _sid in [x.lower() for x in _f.get('shapes', [])]:
            palette.add(_f['key'].lower())

    _lv.loads('(setq t:*ch* (lzs:chart "%s"))' % _real)
    _lv.loads('(setq t:*b* (lzs:boxkeys t:*ch*))'
              '(setq t:*co* (lzs:corners t:*ch*))'
              '(setq t:*lk* (lzs:listkeys))')
    chart = set(str(x).lower() for x in (_lv.globals['t:*b*'] or []))
    chart |= set(str(x).lower() for x in (_lv.globals['t:*lk*'] or []))
    for _c in (_lv.globals['t:*co*'] or []):
        chart.add(str(_c[0]).lower() + '-ty')
        chart.add(str(_c[0]).lower() + '-sz')

    missing = sorted(chart - palette)
    assert not missing, (
        "%s: LAZSPA asks for %s and the palette has no way to answer - add "
        "the field to fieldmap.json, or to SpaFormView.vb's cover block if "
        "it is not anchored to the artwork" % (_sid, missing))
    print("   %-10s %2d questions, every one answerable on both forms"
          % (_sid, len(chart)))

# --------------------------------------------------------------------
# 16. ONE ROUND FOR ALL FOUR.  "Are all four corners the same?" <Yes>
#     asks the treatment once, of "the four corners", and hands the
#     answer to every one of them -- so it must draw the spa that four
#     identical answers draw, keyword and size alike.  A form reaches
#     the same round through samecorners, and CORNER A's boxes carry
#     it: the round is answered, and no corner is asked.
# --------------------------------------------------------------------
print("== 16. one round for all four == four identical answers ==")

ONE_ROUND = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
             "Yes",                     # all four the same...
             "90",                      # ... so the treatment is asked once
             "No", "No"]
m = by_prompts(ONE_ROUND)
same(a, m, "one round")
treated = [p for p, _ in m.prompts if 'be treated' in p]
assert len(treated) == 1, "expected ONE treatment question, got %r" % (treated,)
assert 'the four corners' in treated[0], \
    "the one round should ask about the four corners: %r" % treated[0]

# the same round, with a size on it
RAD_ROUND = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
             "Yes", "Radius", 12.0,
             "No", "No"]
n = by_prompts(RAD_ROUND)
same(e, n, "one round, sized")
sized = [p for p, _ in n.prompts if 'Radius for' in p]
assert len(sized) == 1 and 'the four corners' in sized[0], \
    "expected one size question about the four corners, got %r" % (sized,)

SAME_FORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
                 (w . 84.0) (l . 72.0)
                 (samecorners . "Yes") (cornera-ty . "90"))"""
o = by_form(SAME_FORM, [None, "No", "No"])
same(a, o, "one round from a form")
assert not any('corner' in p.lower() for p, _ in o.prompts), \
    "a corner was asked despite the form answering the round: %r" \
    % [p for p, _ in o.prompts]
print("   one keyword, and one size, covering all four corners")
print("   samecorners + corner A answer the round from a form")


print("\nALL SPA FORM SCENARIOS PASSED")
