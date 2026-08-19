"""Runtime tests: load the real BPCALLOUT.lsp into the AutoLISP VM and
drive c:BPCALLOUT with scripted clicks.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (distance ...) has to die.

Script values answer the interactive calls in order: the "_X" point
sweep (ssget), then one getpoint per click (None = Enter, done), then
one getpoint for the text location (None = take the default spot).
Run: python3 tests/test_bpcallout.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Ent, Dot, Sym, BUILTINS, NIL  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'bpcallout', 'BPCALLOUT.lsp')


# ---- builtins the shared VM does not carry yet ------------------------
# entmakex: entmake that returns the new entity name; distof: string ->
# float; tblobjname: entity name of a table record; ssget: the stock one
# filters by exact DXF equality, but BPCALLOUT filters on the AutoCAD
# comma list (0 . "INSERT,POINT"), so type matching must split on commas.

def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def _entmakex(vm, a):
    alist = a[0]
    d = _alist_dict(alist)
    if d.get(0) in ('LAYER', 'LTYPE'):
        vm.tables[d[0]].add(d[2])
        rec = Ent()
        vm.entdata[rec] = list(alist)
        vm.layer_records[d[2].upper()] = rec
        return rec
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = list(alist)
    return e


def _distof(vm, a):
    try:
        return float(a[0])
    except (TypeError, ValueError):
        return NIL


def _tblobjname(vm, a):
    return vm.layer_records.get(a[1].upper(), NIL)


def _ssget(vm, a):
    mode = ' '.join(x for x in a if isinstance(x, str))
    filt = None
    for x in a:
        if isinstance(x, list) and x and isinstance(x[0], (Dot, list)):
            filt = x
            break
    v = vm.pop_script(('ssget ' + mode).strip(), 'ssget')
    if v is None:
        return NIL
    ents = [e for e in v if e not in vm.deleted]
    if filt:
        d = _alist_dict(filt)
        if 0 in d:
            allowed = set(d[0].upper().split(','))
            ents = [e for e in ents
                    if _alist_dict(vm.entdata[e]).get(0, '').upper()
                    in allowed]
    return ['<ss>'] + ents if ents else NIL


BUILTINS[Sym('entmakex')] = _entmakex
BUILTINS[Sym('distof')] = _distof
BUILTINS[Sym('tblobjname')] = _tblobjname
BUILTINS[Sym('ssget')] = _ssget


# ---- drawing scaffolding ---------------------------------------------

def newvm():
    vm = VM()
    vm.layer_records = {}
    vm.load(LSP)
    return vm


def ab_pt(vm, x, y, number, layer='POINTS'):
    """An ab_pt INSERT followed by its number ATTRIB, as in a drawing."""
    e = Ent()
    vm.entities.append(e)
    vm.entdata[e] = [Dot(0, 'INSERT'), Dot(8, layer), Dot(2, 'ab_pt'),
                     [10, float(x), float(y), 0.0]]
    if number is not None:
        att = Ent()
        vm.entities.append(att)
        vm.entdata[att] = [Dot(0, 'ATTRIB'), Dot(2, 'number'),
                           Dot(1, str(number))]
    return e


def run(vm, script, label):
    try:
        vm.run('c:BPCALLOUT', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def made(vm, etype):
    out = []
    for e in vm.entities:
        d = _alist_dict(vm.entdata[e])
        if d.get(0) == etype and 40 in d:
            out.append(d)
    return out


def centers(circles):
    return sorted((round(c[10][0], 6), round(c[10][1], 6))
                  for c in circles)


# ---- tests -----------------------------------------------------------

def test_three_points():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 12), ab_pt(vm, 100, 0, 15),
           ab_pt(vm, 100, 100, 20)]
    # clicks land near, not on, each point: the ring must snap to the
    # point itself
    run(vm, [pts,
             (3.0, 4.0), (98.0, 2.0), (101.0, 99.0), None,
             (50.0, 50.0)], 'three points')
    circles = made(vm, 'CIRCLE')
    assert len(circles) == 3, circles
    assert all(c[8] == 'FGStep' and c[40] == 5.0 for c in circles), circles
    assert centers(circles) == [(0.0, 0.0), (100.0, 0.0), (100.0, 100.0)]
    texts = made(vm, 'TEXT')
    assert len(texts) == 1, texts
    assert texts[0][1] == 'Pt.12, Pt.15 and Pt.20 are bad', texts
    assert texts[0][8] == 'FGStep'
    assert texts[0][10][:2] == [50.0, 50.0]
    print("ok  three points -> three rings + 'Pt.12, Pt.15 and Pt.20"
          " are bad'")


def test_one_point():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 7)]
    run(vm, [pts, (1.0, 1.0), None, (10.0, 10.0)], 'one point')
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.7 is bad', texts
    print("ok  one point   -> 'Pt.7 is bad'")


def test_two_points():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 3), ab_pt(vm, 50, 0, 4)]
    run(vm, [pts, (0.0, 0.0), (50.0, 0.0), None, (25.0, 25.0)], 'two')
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.3 and Pt.4 are bad', texts
    print("ok  two points  -> 'Pt.3 and Pt.4 are bad'")


def test_far_click_is_unknown():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 9)]
    # 30 away from the only point: farther than the 12" snap, so the
    # ring goes where clicked and the point reads as "?"
    run(vm, [pts, (30.0, 0.0), None, (10.0, 10.0)], 'far click')
    circles = made(vm, 'CIRCLE')
    assert centers(circles) == [(30.0, 0.0)], circles
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.? is bad', texts
    print("ok  far click   -> ring at the pick, 'Pt.? is bad'")


def test_duplicate_click_skipped():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 5), ab_pt(vm, 50, 0, 6)]
    run(vm, [pts, (1.0, 0.0), (0.0, 1.0), (50.0, 0.0), None,
             (25.0, 25.0)], 'duplicate')
    circles = made(vm, 'CIRCLE')
    assert len(circles) == 2, circles
    texts = made(vm, 'TEXT')
    assert texts[0][1] == 'Pt.5 and Pt.6 are bad', texts
    print("ok  duplicate   -> second click on Pt.5 skipped")


def test_default_text_spot():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 2)]
    # Enter at the text prompt: the callout tucks beside the last ring
    run(vm, [pts, (0.0, 0.0), None, None], 'default spot')
    texts = made(vm, 'TEXT')
    assert texts[0][10][:2] == [10.0, -10.0], texts
    print("ok  Enter       -> text beside the last ring")


def test_no_clicks():
    vm = newvm()
    pts = [ab_pt(vm, 0, 0, 1)]
    run(vm, [pts, None], 'no clicks')
    assert made(vm, 'CIRCLE') == [] and made(vm, 'TEXT') == []
    print("ok  no clicks   -> nothing drawn")


def test_no_local_shadows_a_function():
    """The bug that shipped in v1.0: c:BPCALLOUT declared a local named
    "last", which in AutoLISP shadows the built-in for the whole call,
    so (last picked) died with "no function definition: LAST" the
    moment a run got as far as placing the text.  Every name any defun
    here declares must stay clear of the functions the file calls."""
    import re
    src = open(LSP).read()
    src = re.sub(r';[^\n]*', '', src)            # strip comments
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)  # and string literals
    arglists = re.findall(r'\(defun\s+[^\s()]+\s*\(([^)]*)\)', src)
    # the arglists themselves are parenthesised, so they have to come
    # out before heads-of-lists are read as the functions being called
    bodies = re.sub(r'\(defun\s+[^\s()]+\s*\([^)]*\)', '(defun', src)
    called = set(re.findall(r'\(\s*([a-zA-Z][\w:*<>=+/-]*)', bodies))
    bad = []
    for arglist in arglists:
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow   -> no local hides a function the file calls")


def test_empty_drawing():
    vm = newvm()
    run(vm, [None, (5.0, 5.0), None, (0.0, 0.0)], 'empty drawing')
    circles = made(vm, 'CIRCLE')
    assert centers(circles) == [(5.0, 5.0)], circles
    assert made(vm, 'TEXT')[0][1] == 'Pt.? is bad'
    print("ok  no points   -> ring at the pick, 'Pt.? is bad'")


if __name__ == '__main__':
    test_three_points()
    test_one_point()
    test_two_points()
    test_far_click_is_unknown()
    test_duplicate_click_skipped()
    test_default_text_spot()
    test_no_clicks()
    test_empty_drawing()
    test_no_local_shadows_a_function()
    print("all BPCALLOUT tests passed")
