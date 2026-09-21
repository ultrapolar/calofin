"""Runtime tests: load the real DRONOTE.lsp into the AutoLISP VM and
drive c:DRONOTE with scripted answers.  AutoLISP cannot run outside
AutoCAD, so this is where a wrong arity, an unbound function or a nil
reaching (strcat ...) has to die.

Script values answer the interactive calls in order: one getkword for
the note choice ("Board" / "Anchors" / "Slide"), then one getpoint per
placement (None = Enter, done; "Back" = step back).  A callable in the
script is called at its prompt -- that is how a scenario presses Esc.
Run: python3 tests/test_dronote.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_dronote.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError, Dot  # noqa: E402

ROOT = os.environ.get('CALOFIN_LISP_ROOT', 'lisp')
LSP = (os.path.join(os.path.dirname(__file__), '..', 'shared', 'parts',
                    'DRONOTE.lsp')
       if ROOT == 'shared' else
       os.path.join(os.path.dirname(__file__), '..', 'lisp', 'dronote',
                    'DRONOTE.lsp'))
LIB = os.path.join(os.path.dirname(__file__), '..', 'shared', 'parts',
                   'CALOFIN-LIB.lsp')

BOARD = "How far is the diving board base from water's edge?"
ANCHORS = "Some anchors are not visible in the drone photo provided."
SLIDE = ("Please provide a detailed sketch to locate slide base for"
        " proper cover treatment.")
HEADER = "*All listed issues must be resolved to proceed with design*"


def written(note, header=HEADER, bullet="- "):
    """What the drafter's drawing reads: the standing header, then the
    note bulleted on the line under it.  \\P is MTEXT's paragraph
    break."""
    return (header + "\\P" + bullet + note) if header else bullet + note


# ---- drawing scaffolding ---------------------------------------------

def newvm():
    vm = VM()
    if ROOT == 'shared':
        vm.load(LIB)
    vm.load(LSP)
    return vm


def run(vm, script, label):
    try:
        vm.run('c:DRONOTE', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def esc(vm):
    """The drafter presses Esc at this prompt."""
    raise LispError('Function cancelled', vm)


def _alist_dict(alist):
    d = {}
    for p in alist:
        if isinstance(p, Dot):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def made(vm, etype):
    out = []
    for e in vm.entities:
        if e in vm.deleted:
            continue
        d = _alist_dict(vm.entdata[e])
        if d.get(0) == etype and 40 in d:
            out.append(d)
    return out


def undo_calls(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def layer_rec(vm, name):
    return _alist_dict(vm.recdata[vm.tablerecs['LAYER'][name.upper()]])


# ---- tests -------------------------------------------------------------

def test_board_note():
    vm = newvm()
    run(vm, ["Board", (12.0, 34.0), None], 'board')
    texts = made(vm, 'MTEXT')
    assert len(texts) == 1, texts
    assert texts[0][1] == written(BOARD), texts
    assert texts[0][8] == 'TEXT' and texts[0][40] == 9.5, texts
    assert texts[0][10][:2] == [12.0, 34.0], texts
    assert any('1 note placed on layer TEXT' in p for p in vm.printed), \
        vm.printed
    print("ok  Board       -> the diving-board note under the header, on"
          " TEXT")


def test_anchors_note():
    vm = newvm()
    run(vm, ["Anchors", (0.0, 0.0), None], 'anchors')
    texts = made(vm, 'MTEXT')
    assert texts[0][1] == written(ANCHORS), texts
    print("ok  Anchors     -> the hidden-anchors note")


def test_slide_note():
    vm = newvm()
    run(vm, ["Slide", (0.0, 0.0), None], 'slide')
    texts = made(vm, 'MTEXT')
    assert texts[0][1] == written(SLIDE), texts
    print("ok  Slide       -> the slide-sketch note, joined back into one"
          " string")


def test_header_and_text_properties():
    """The note reads as the shop's own: the standing header on the
    first line, the note bulleted under it, and the MTEXT carrying the
    properties their note blocks carry -- the Attributes style at 9.5
    on layer TEXT, attached TOP LEFT at the picked point, ByLayer,
    upright, wrapped at the block width, lines spaced "at least"."""
    vm = newvm()
    run(vm, ["Anchors", (984.1963270657014, 497.8080130614497), None],
        'properties')
    t = made(vm, 'MTEXT')[0]
    assert t[1] == HEADER + "\\P" + "- " + ANCHORS, t
    assert t[1].split("\\P") == [HEADER, "- " + ANCHORS], t
    assert t[8] == 'TEXT', t                    # layer
    assert 62 not in t, t                       # colour: ByLayer
    assert t[7] == 'Attributes', t              # text style
    assert t[40] == 9.5, t                      # height
    assert t[41] == 440.1875, t                 # wrap width
    assert t[71] == 1, t                        # attachment: top left
    assert t[72] == 5, t                        # direction: by style
    assert t[73] == 1, t                        # line spacing: at least
    assert t[44] == 1.0, t                      # ... factor
    assert t[50] == 0.0, t                      # rotation
    assert t[10][:2] == [984.1963270657014, 497.8080130614497], t
    print("ok  properties  -> header, Attributes 9.5 on TEXT, top left at"
          " the picked point")


def test_style_made_when_the_drawing_lacks_it():
    """A drawing without the Attributes style gets a plain one of that
    name made from dn:*style-font*, and is told so; a drawing that has
    one keeps it untouched -- the note asks for nothing but the name."""
    vm = newvm()
    run(vm, ["Board", (0.0, 0.0), None], 'style made')
    assert 'ATTRIBUTES' in {s.upper() for s in vm.tables['STYLE']}, \
        vm.tables['STYLE']
    assert any('text style Attributes was not in this drawing' in p
               for p in vm.printed), vm.printed
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "STYLE")'
             ' \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbTextStyleTableRecord") \'(2 . "Attributes")'
             ' \'(70 . 0) \'(40 . 9.5) \'(3 . "arialbd.ttf")))')
    run(vm, ["Board", (0.0, 0.0), None], 'style kept')
    assert not any('text style' in p for p in vm.printed), vm.printed
    assert made(vm, 'MTEXT')[0][7] == 'Attributes'
    print("ok  style       -> Attributes made when missing, left alone when"
          " the drawing has it")


def test_header_can_be_emptied():
    """A shop whose notes read differently empties dn:*header*: the
    bullet line is then the whole note, and nothing else moves."""
    vm = newvm()
    vm.loads('(setq dn:*header* "")')
    run(vm, ["Board", (0.0, 0.0), None], 'no header')
    t = made(vm, 'MTEXT')[0]
    assert t[1] == "- " + BOARD, t
    vm = newvm()
    vm.loads('(setq dn:*header* "RFI" dn:*bullet* "* ")')
    run(vm, ["Board", (0.0, 0.0), None], 'own header')
    assert made(vm, 'MTEXT')[0][1] == "RFI\\P* " + BOARD, made(vm, 'MTEXT')
    print("ok  header knob -> emptied leaves the bullet alone, and both are"
          " read at run time")


def test_multiple_placements():
    vm = newvm()
    run(vm, ["Board", (0.0, 0.0), (10.0, 0.0), (20.0, 0.0), None],
        'multiple')
    texts = made(vm, 'MTEXT')
    assert len(texts) == 3, texts
    assert all(t[1] == written(BOARD) for t in texts), texts
    assert any('3 notes placed on layer TEXT' in p for p in vm.printed), \
        vm.printed
    print("ok  repeat      -> the same note dropped at three points, one"
          " run")


def test_back_removes_last_placement():
    vm = newvm()
    run(vm, ["Anchors", (0.0, 0.0), (10.0, 0.0), "Back", None], 'back')
    texts = made(vm, 'MTEXT')
    assert len(texts) == 1, texts
    assert texts[0][10][:2] == [0.0, 0.0], texts
    assert any('Last note removed' in p for p in vm.printed), vm.printed
    assert any('1 note placed on layer TEXT' in p for p in vm.printed), \
        vm.printed
    print("ok  Back        -> un-places the last note, keeps the first")


def test_back_before_any_placement_reopens_note_choice():
    """Back at the point prompt with nothing placed yet steps back to
    the note choice instead of un-placing anything -- there is nothing
    to un-place."""
    vm = newvm()
    run(vm, ["Board", "Back", "Slide", (5.0, 5.0), None], 're-choose')
    texts = made(vm, 'MTEXT')
    assert len(texts) == 1, texts
    assert texts[0][1] == written(SLIDE), texts
    assert any('Back to the note choice' in p for p in vm.printed), \
        vm.printed
    print("ok  Back/choice -> Back with nothing placed re-asks which note")


def test_knobs_reach_the_output():
    vm = newvm()
    vm.loads('(setq dn:*layer* "RFI" dn:*text-hgt* 4.0 dn:*text-width* 48.0'
             ' dn:*style* "ROMANS" dn:*line-space* 1.5)')
    run(vm, ["Board", (0.0, 0.0), None], 'knobs')
    t = made(vm, 'MTEXT')[0]
    assert t[8] == 'RFI' and t[40] == 4.0 and t[41] == 48.0, t
    assert t[7] == 'ROMANS' and t[44] == 1.5, t
    assert any('1 note placed on layer RFI' in p for p in vm.printed), \
        vm.printed
    print("ok  knobs       -> layer, style, height, width and line spacing"
          " all read at run time")


def test_layer_repaired_and_coloured():
    """TEXT frozen, locked and off is thawed, unlocked and switched on
    before the first note, and the run says so; a missing TEXT is
    created in dn:*layer-color*."""
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "TEXT")'
             ' \'(70 . 5) \'(62 . -3) \'(6 . "Continuous")))')
    run(vm, ["Board", (0.0, 0.0), None], 'repair')
    rec = layer_rec(vm, 'TEXT')
    assert rec[70] == 0 and rec[62] == 3, rec
    assert len(made(vm, 'MTEXT')) == 1
    assert any('was off, frozen or locked' in p for p in vm.printed), \
        vm.printed
    vm = newvm()
    run(vm, ["Board", (0.0, 0.0), None], 'default colour')
    assert layer_rec(vm, 'TEXT')[62] == 4, layer_rec(vm, 'TEXT')
    vm = newvm()
    vm.loads('(setq dn:*layer-color* 2)')
    run(vm, ["Board", (0.0, 0.0), None], 'colour knob')
    assert layer_rec(vm, 'TEXT')[62] == 2, layer_rec(vm, 'TEXT')
    print("ok  layer       -> TEXT repaired when unusable, created in the"
          " knob's colour")


def test_no_placements():
    vm = newvm()
    run(vm, ["Board", None], 'no placements')
    assert made(vm, 'MTEXT') == []
    assert any('0 notes placed on layer TEXT' in p for p in vm.printed), \
        vm.printed
    print("ok  no picks    -> nothing drawn")


def test_undo_group_wraps_the_run():
    vm = newvm()
    run(vm, ["Board", (0.0, 0.0), None], 'undo group')
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    print("ok  undo group  -> one _Begin before the notes, one _End after")


def test_undo_off():
    """UNDOCTL with bit 1 clear: no group is opened -- and none is
    closed either."""
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    run(vm, ["Board", (0.0, 0.0), None], 'undo off')
    assert undo_calls(vm) == [], vm.commands
    assert len(made(vm, 'MTEXT')) == 1
    print("ok  undo off    -> no _.UNDO at all, the note still drawn")


def test_esc_mid_run():
    """Esc at the point prompt, and Esc at the note-choice prompt of a
    second run: the handler closes the group it opened, prints nothing
    about an error, and the command hands the session back clean."""
    vm = newvm()
    vm.handle_errors = True
    run(vm, ["Board", (0.0, 0.0), esc], 'Esc at a point')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert not any('error' in p.lower() for p in vm.printed), vm.printed
    assert len(made(vm, 'MTEXT')) == 1
    vm = newvm()
    vm.handle_errors = True
    run(vm, [esc], 'Esc at the note choice')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert made(vm, 'MTEXT') == []
    print("ok  Esc         -> handler closes the group and stays silent, at"
          " the note choice and at a point")


def test_no_local_shadows_a_function():
    """No local any defun here declares may be named after a function
    the file calls -- an AutoLISP local shadows the built-in of the
    same name for the whole call (the BPCALLOUT v1.0 lesson)."""
    import re
    src = open(LSP).read()
    src = re.sub(r';[^\n]*', '', src)             # strip comments
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)   # and string literals
    arglists = re.findall(r'\(defun\s+[^\s()]+\s*\(([^)]*)\)', src)
    bodies = re.sub(r'\(defun\s+[^\s()]+\s*\([^)]*\)', '(defun', src)
    bodies = re.sub(r'\(lambda\s*\([^)]*\)', '(lambda', bodies)
    called = set(re.findall(r'\(\s*([a-zA-Z][\w:*<>=+/-]*)', bodies))
    bad = []
    for arglist in arglists:
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow   -> no local hides a function the file calls")


if __name__ == '__main__':
    test_board_note()
    test_anchors_note()
    test_slide_note()
    test_header_and_text_properties()
    test_style_made_when_the_drawing_lacks_it()
    test_header_can_be_emptied()
    test_multiple_placements()
    test_back_removes_last_placement()
    test_back_before_any_placement_reopens_note_choice()
    test_knobs_reach_the_output()
    test_layer_repaired_and_coloured()
    test_no_placements()
    test_undo_group_wraps_the_run()
    test_undo_off()
    test_esc_mid_run()
    test_no_local_shadows_a_function()
    print("all DRONOTE tests passed")
