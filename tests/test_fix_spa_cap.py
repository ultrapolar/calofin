#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""SPA's 30-ft cap holds for a FORM answer exactly as for a typed one.

A size over 360 in is refused at every typed distance prompt: it is
almost always millimetres, typed with a space ("1524 mm" -> 1524
INCHES) or typed into a box that reads inches.  The form's takes did
not know that bound -- spa:fok (the measurement sequences), spa:askdf
(the lap), a corner's size and the round diameter each took any
positive number -- so a sheet carrying 1524 drew a 127-ft spa that the
same 1524 typed would have been refused as (STANDARDS 7.5: validate at
the take exactly as the prompt would).

Each scenario runs the same spa twice -- once all typed, once from a
form whose one oversize value has to fall through to the prompt -- and
the two must leave the same drawing, with the refused question asked
at the keyboard and the reason said.

Run: python3 tests/test_fix_spa_cap.py
"""

import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TESTS_DIR)
from lispvm import VM, Dot, Ent, LispError, parse_all  # noqa: E402

LSP = os.path.join(TESTS_DIR, '..', 'lisp', 'spa', 'SPA.LSP')

REFUSED = 'longer than any spa'


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


def drive(form_src, script, label):
    Ent._n = 0                   # handles are a fact about the drawing
    vm = VM()
    vm.load(LSP)
    if form_src:
        vm.eval(parse_all("(setq spa:*form* %s)" % form_src)[0])
    try:
        vm.run('c:SPA', script)
    except LispError as e:
        raise AssertionError("[%s] %s" % (label, e)) from None
    return vm


def same(a, b, label):
    sa, sb = snapshot(a), snapshot(b)
    assert sa, "[%s] nothing was drawn at all" % label
    only_a = [x for x in sa if x not in sb]
    only_b = [x for x in sb if x not in sa]
    assert not only_a and not only_b, \
        "[%s] geometry differs: %d only typed, %d only from the form" \
        "\n  typed: %s\n  form:  %s" % (label, len(only_a), len(only_b),
                                          only_a[:2], only_b[:2])


def asked(vm, word):
    return [p for p, _ in vm.prompts if word in p]


def said(vm):
    return ''.join(vm.printed)


# ------------------------------------------------ the measurement block

RECT_TYPED = [None,                       # no Spa Cover Details block
              "Watersedge", "Rectangle", (0, 0),
              84.0, 72.0,
              "No", "90", "90", "90", "90",
              "No", "No"]
RECT_FORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
                 (w . %s) (l . %s)
                 (cornera-ty . "90") (cornerb-ty . "90")
                 (cornerc-ty . "90") (cornerd-ty . "90"))"""


def test_an_oversize_form_width_is_asked_at_the_keyboard():
    """spa:fok on a REQ question: W = 1524 off the sheet.  The store's
    w is the ACROSS overall (worded LENGTH, as POOL words it) and l the
    UP one, so the prompts are found by their direction."""
    typed = drive(None, RECT_TYPED, 'typed')
    vm = drive(RECT_FORM % ('1524.0', '72.0'), [None, 84.0, "No", "No"],
               'form w=1524')
    same(typed, vm, 'form w=1524')
    assert len(asked(vm, 'across (A-B)')) == 1, [p for p, _ in vm.prompts]
    assert not asked(vm, 'up (A-D)'), "the length was given and asked"
    assert REFUSED in said(vm), said(vm)


def test_an_oversize_form_length_is_asked_at_the_keyboard():
    """spa:fok on a SUG question: L = 1524, Enter then takes the width
    it offers -- a square spa, as the typed run with Enter at L."""
    typed = drive(None, RECT_TYPED[:5] + [None] + RECT_TYPED[6:], 'typed')
    vm = drive(RECT_FORM % ('84.0', '1524.0'), [None, None, "No", "No"],
               'form l=1524')
    same(typed, vm, 'form l=1524')
    assert len(asked(vm, 'up (A-D)')) == 1, [p for p, _ in vm.prompts]
    assert REFUSED in said(vm), said(vm)


def test_a_form_value_under_the_cap_is_still_taken_unasked():
    """The bound is 30 ft, not a spa's usual size: 360 itself stands."""
    vm = drive(RECT_FORM % ('360.0', '72.0'), [None, "No", "No"],
               'form w=360')
    assert not asked(vm, 'across (A-B)'), [p for p, _ in vm.prompts]
    assert REFUSED not in said(vm), said(vm)


# ------------------------------------------------------ round diameter

def test_an_oversize_form_diameter_is_asked_at_the_keyboard():
    typed = drive(None, [None, "Watersedge", "ROund", (0, 0), 96.0,
                         "No", "No"], 'typed')
    vm = drive("""'((mode . "Watersedge") (shape . "ROund")
                    (base 0.0 0.0) (b . 1524.0))""",
               [None, 96.0, "No", "No"], 'form b=1524')
    same(typed, vm, 'form b=1524')
    assert len(asked(vm, 'Overall diameter')) == 1, \
        [p for p, _ in vm.prompts]
    assert REFUSED in said(vm), said(vm)


# ------------------------------------------------------------- the lap

def test_an_oversize_form_lap_is_asked_at_the_keyboard():
    cover = ["Yes", "Offset", 3.0]
    typed = drive(None, RECT_TYPED[:-1] + cover, 'typed')
    vm = drive("""'((mode . "Watersedge") (shape . "Rectangle")
                    (base 0.0 0.0) (w . 84.0) (l . 72.0)
                    (cornera-ty . "90") (cornerb-ty . "90")
                    (cornerc-ty . "90") (cornerd-ty . "90")
                    (second . "Yes") (method . "Offset") (gap . 1524.0)
                    (autohinge . "No"))""",
               [None, 3.0], 'form gap=1524')
    same(typed, vm, 'form gap=1524')
    assert len(asked(vm, 'lap')) == 1, [p for p, _ in vm.prompts]
    assert REFUSED in said(vm), said(vm)


# ------------------------------------------------------ a corner's size

RAD_TYPED = [None, "Watersedge", "Rectangle", (0, 0), 84.0, 72.0,
             "No", "Radius", 12.0, "Radius", 12.0,
             "Radius", 12.0, "Radius", 12.0,
             "No", "No"]
RAD_FORM = """'((mode . "Watersedge") (shape . "Rectangle") (base 0.0 0.0)
                (w . 84.0) (l . 72.0)
                (cornera-ty . "Radius") (cornera-sz . %s)
                (cornerb-ty . "Radius") (cornerb-sz . 12.0)
                (cornerc-ty . "Radius") (cornerc-sz . 12.0)
                (cornerd-ty . "Radius") (cornerd-sz . 12.0))"""


def test_an_oversize_form_corner_is_refused_as_typed_would_be():
    """The walls cap caught this one already -- no corner over 30 ft
    fits a spa under it -- so it never reached the drawing; but it was
    refused as too big for these walls, not as the millimetres it
    almost certainly is.  It is refused now exactly as spa:askd refuses
    it typed, beside the size prompt it goes to."""
    typed = drive(None, RAD_TYPED, 'typed')
    vm = drive(RAD_FORM % '1524.0', [None, 12.0, "No", "No"],
               'form cornera-sz=1524')
    same(typed, vm, 'form cornera-sz=1524')
    sizes = [p for p, _ in vm.prompts if 'radius' in p.lower()
             and 'Corner A' in p]
    assert len(sizes) == 1, [p for p, _ in vm.prompts]
    assert REFUSED in said(vm), said(vm)
    assert 'Too large for this corner' not in said(vm), said(vm)
    # and a SQUARE corner carrying the same stray size says nothing:
    # no size is asked, so there is nothing to refuse it beside
    sq = RAD_FORM.replace('(cornera-ty . "Radius")', '(cornera-ty . "90")')
    vm = drive(sq % '1524.0', [None, "No", "No"], 'form square+1524')
    assert REFUSED not in said(vm), said(vm)


TESTS = [test_an_oversize_form_width_is_asked_at_the_keyboard,
         test_an_oversize_form_length_is_asked_at_the_keyboard,
         test_a_form_value_under_the_cap_is_still_taken_unasked,
         test_an_oversize_form_diameter_is_asked_at_the_keyboard,
         test_an_oversize_form_lap_is_asked_at_the_keyboard,
         test_an_oversize_form_corner_is_refused_as_typed_would_be]


def main():
    fails = 0
    for t in TESTS:
        try:
            t()
            print("  ok   %s" % t.__name__)
        except AssertionError as e:
            fails += 1
            print("  FAIL %s\n       %s" % (t.__name__, str(e)[:600]))
    if fails:
        print("\n%d FAILED" % fails)
        return 1
    print("\nALL FORM-CAP CHECKS PASSED")
    return 0


if __name__ == '__main__':
    sys.exit(main())
