"""Values AutoCAD does not promise, pinned against what AutoCAD answers.

Four builtins used to answer more kindly than AutoCAD, and each kind
answer is a place a tool could be wrong in the drawing and right here:

  rtos     read no system variable at all.  AutoCAD's spells feet and
           inches after DIMZIN -- at 0 (acad.dwt), 2 or 8 a whole foot
           is 15', not 15'-0", and at 0 or 3 six inches is 6", not
           0'-6" -- trims a decimal's trailing zeros at DIMZIN 8 and its
           leading zero at 4, and takes its mode and precision from
           LUNITS / LUPREC when the call leaves them out.  The VM wrote
           15'-0" at every DIMZIN, and mode 3 came out as plain decimal.
  distof   is rtos's complement, so it reads back what rtos now writes
           -- 1.7500E+01 in mode 1, 17 1/2 in mode 5 -- and a mode left
           out is LUNITS, as for rtos.  The VM read the leading number
           (1.75, 17) and assumed mode 2.
  vl-sort  dropped every item that compared EQUAL to its neighbour.
           AutoCAD's drops only EQ duplicates -- two equal integers --
           and keeps two equal reals and two equal lists, so a sort of
           points by X that the VM thinned was whole in AutoCAD, and a
           dedupe that leaned on vl-sort for reals held only here.
  entmod / entdel
           wrote through a LOCKED layer.  AutoCAD's answer nil and
           change nothing for an entity on a layer whose record has
           bit 4 of group 70 set; the record itself stays writable,
           which is how a routine unlocks the layer.

Each pin names the source it relies on.  Where AutoCAD's behaviour is
not documented the VM does not model it and nothing here pins it:
DIMZIN's leading/trailing bits on the decimal inches of mode 3, on
mode 1 and on mode 5; UNITMODE 1's spelling; the sign of a value that
rounds to zero; zero at DIMZIN 2 or 3; whether vl-sort drops two
references to the ONE list or string object (the VM keeps both);
whether an entmod may move an entity ONTO a locked layer (the VM lets
it); an entdel that UN-erases on a locked layer (the VM lets it); an
entity inside a block definition (never refused); an entity with no
group 8 at all (the VM refuses nothing for it -- AutoCAD's entmake puts
one on CLAYER, which the VM's entmake does not record); whether distof
reads one mode's spelling in another (mode 2 keeps its lenient
leading-number read); and angtos, which still reads no system variable
-- DIMZIN, AUNITS and AUPREC all ignored.

The file imports nothing the old VM lacks, so it runs against an older
tests/lispvm.py too and names the pins that VM fails.

Run: python3 tests/test_lispvm_values.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lispvm import VM, Sym, NIL, Dot  # noqa: E402

# ---------------------------------------------------------------- sources
DIMZIN_DOC = ("AutoCAD DIMZIN system variable reference: '0 Suppresses zero "
              "feet and precisely zero inches; 1 Includes zero feet and "
              "precisely zero inches; 2 Includes zero feet and suppresses "
              "zero inches; 3 Includes zero inches and suppresses zero "
              "feet' -- and 'DIMZIN also affects real-to-string "
              "conversions performed by the AutoLISP rtos and angtos "
              "functions'")
DIMZIN_DEC = ("AutoCAD DIMZIN reference: '4 Suppresses leading zeros in "
              "decimal dimensions (for example, 0.5000 becomes .5000); 8 "
              "Suppresses trailing zeros in decimal dimensions (for "
              "example, 12.5000 becomes 12.5); 12 Suppresses both "
              "(0.5000 becomes .5)'")
REPO_FTIN = ("lisp/dimcheck/dimcheck.lsp dchk:dist: 'rtos spells those "
             "after DIMZIN: at 0 (the acad.dwt setting), 2 or 8 a whole "
             "foot came out 15''")
REPO_CDATE = ("lisp/spacheck/SPACHECK.lsp: CDATE through rtos 'is trimmed "
              "by DIMZIN 8'; lisp/lazdiag/LAZDIAG.lsp: 'rtos under DIMZIN 8 "
              "writes 12.0 as \"12\"'")
RTOS_DOC = ("AutoLISP Reference, rtos: 'returns a string that is the "
            "representation of number according to the settings of mode, "
            "precision, and the AutoCAD UNITMODE, DIMZIN, LUNITS, and "
            "LUPREC system variables'; mode and precision default to "
            "LUNITS and LUPREC when omitted")
RTOS_EX = ("AutoLISP Developer's Guide, String Conversions: with x = 17.5, "
           "(rtos x 1 4) '1.7500E+01', (rtos x 2 2) '17.50', (rtos x 3 2) "
           "'1''-5.50\"', (rtos x 4 2) '1''-5 1/2\"', (rtos x 5 2) '17 1/2'")
LUPREC_SEED = "acad.dwt: LUPREC 4, LUNITS 2"
DISTOF_DOC = ("AutoLISP Reference, distof: 'The distof and rtos functions "
              "are complementary.  If you pass distof a string created by "
              "rtos, distof is guaranteed to return a valid value, and "
              "vice versa (assuming the mode values are the same)'; the "
              "mode 'corresponds to the values allowed for LUNITS' and, "
              "omitted, is the current LUNITS")
CARRY = ("the notation itself: inches run 0 to under 12, so a value that "
         "rounds up to twelve inches is the next foot (cal:ftin rounds "
         "the whole value the same way)")
SORT_DOC = ("AutoLISP Reference, vl-sort: 'Duplicate elements may be "
            "eliminated from the list' -- (vl-sort '(3 2 1 3) '<) returns "
            "(1 2 3)")
SORT_REALS = ("CADTutor, 'vl-sort kinda sucks': 'Only lists of plain "
              "integers with duplicate numbers can fall victim to losing "
              "those items.  Lists of reals like '(3.0 2.0 1.0 1.0 1.0) and "
              "complex lists return all their items'")
SORT_EQ = ("inference from SORT_REALS: two reals that compare equal both "
           "survive, so the drop is not comparator equality -- it is EQ, "
           "which two different integers never are")
ENTMOD_DOC = ("AutoLISP Reference, entmod: 'If entmod is unable to modify "
              "the specified entity, the function returns nil'; Autodesk "
              "forum 'entmod fails to update attrib' -- solved by "
              "'Unlock the layer that the attribute is on'; "
              "tests/test_covercheck.py: 'on a LOCKED layer, where "
              "AutoCAD's entmod answers nil and changes nothing'")
ENTDEL_REPO = ("tests/test_cdcreate.py C28: 'entdel answers nil on a locked "
               "layer and the line stays'; test_fix_review_a.py: 'entdel "
               "refuses for an entity on a layer whose table record "
               "carries bit 4'")
RECORD_OK = ("tests/test_fix_review_a.py: 'The record itself stays writable "
             "(that is how a layer is unlocked), and entmake is not "
             "touched -- AutoCAD creates on a locked layer'")
LOCK_BIT = ("DXF reference, LAYER group 70: '4 = Layer is locked'; "
            "vla-put-Lock writes that bit (lispvm _vla_put_lock)")
CONTRACT = "lispvm test API, kept"


# ---------------------------------------------------------------- driving
def ev(src, **sysvars):
    vm = VM()
    vm.sysvars.update(sysvars)
    return vm.loads(src)


def rtos(v, mode=None, prec=None, **sysvars):
    args = ' '.join(str(x) for x in (mode, prec) if x is not None)
    return ev('(rtos %r %s)' % (float(v), args), **sysvars)


def plain(x):
    return list(x) if isinstance(x, list) else x


LAYER = ('(entmake (list \'(0 . "LAYER") \'(2 . "%s") (cons 70 %d) '
         '\'(62 . 7) \'(6 . "Continuous")))')
LINE = ('(entmake (list \'(0 . "LINE") \'(8 . "%s") \'(10 0.0 0.0 0.0) '
        '\'(11 1.0 0.0 0.0)))')


def drawing(*layers):
    """A VM with each (name, flags) layer made and one LINE on each."""
    vm = VM()
    ents = {}
    for name, flags in layers:
        vm.loads(LAYER % (name, flags))
        vm.loads(LINE % name)
        ents[name] = vm.entities[-1]
    return vm, ents


def end_x(vm, e):
    for g in vm.entdata[e]:
        if isinstance(g, list) and g and g[0] == 11:
            return g[1]
    return None


def layer_of(vm, e):
    for g in vm.entdata[e]:
        if isinstance(g, Dot) and g.a == 8:
            return g.b
    return None


MOVE = '(entmod (subst (list 11 9.0 0.0 0.0) (assoc 11 (entget e)) (entget e)))'


def modify(vm, e, src=MOVE):
    vm.globals[Sym('e')] = e
    return vm.loads(src)


PINS = []


def pin(pid, rule, source):
    def wrap(fn):
        PINS.append((pid, rule, source, fn))
        return fn
    return wrap


# ================================================================== rtos
@pin('R1', "mode 4 at DIMZIN 0: a whole foot is 15', six inches is 6\"",
     DIMZIN_DOC + '; ' + REPO_FTIN)
def _r1():
    got = (rtos(180, 4, 4, DIMZIN=0), rtos(6, 4, 4, DIMZIN=0))
    return got == ("15'", '6"'), got


@pin('R2', "mode 4 at DIMZIN 1: both zeros kept -- 15'-0\" and 0'-6\"",
     DIMZIN_DOC)
def _r2():
    got = (rtos(180, 4, 4, DIMZIN=1), rtos(6, 4, 4, DIMZIN=1))
    return got == ("15'-0\"", "0'-6\""), got


@pin('R3', "mode 4 at DIMZIN 2: zero feet kept, zero inches dropped",
     DIMZIN_DOC)
def _r3():
    got = (rtos(180, 4, 4, DIMZIN=2), rtos(6, 4, 4, DIMZIN=2))
    return got == ("15'", "0'-6\""), got


@pin('R4', "mode 4 at DIMZIN 3: zero inches kept, zero feet dropped",
     DIMZIN_DOC)
def _r4():
    got = (rtos(180, 4, 4, DIMZIN=3), rtos(6, 4, 4, DIMZIN=3))
    return got == ("15'-0\"", '6"'), got


@pin('R5', "mode 4 at DIMZIN 8 (the low bits are 0): a whole foot is 15'",
     DIMZIN_DOC + '; ' + REPO_FTIN)
def _r5():
    got = rtos(180, 4, 4, DIMZIN=8)
    return got == "15'", got


@pin('R6', "mode 4 with feet, inches and a fraction is the same at any "
     "DIMZIN: 1'-5 1/2\", 25'-6 1/2\"", RTOS_EX)
def _r6():
    got = [rtos(v, 4, p, DIMZIN=dz) for dz in (0, 1, 8)
           for v, p in ((17.5, 2), (306.5, 4))]
    return got == ["1'-5 1/2\"", "25'-6 1/2\""] * 3, got


@pin('R7', "mode 4 with feet and a fraction under an inch keeps the whole "
     "inch: 1'-0 1/2\" at DIMZIN 0", DIMZIN_DOC + " ('precisely zero "
     "inches' -- 0 1/2 is not)")
def _r7():
    got = rtos(12.5, 4, 4, DIMZIN=0)
    return got == "1'-0 1/2\"", got


@pin('R8', "mode 4 at DIMZIN 0: zero is 0\", a negative foot is -15'",
     DIMZIN_DOC)
def _r8():
    got = (rtos(0, 4, 4, DIMZIN=0), rtos(-180, 4, 4, DIMZIN=0))
    return got == ('0"', "-15'"), got


@pin('R9', "mode 3 is engineering feet and decimal inches, not decimal: "
     "1'-5.50\"", RTOS_EX)
def _r9():
    got = rtos(17.5, 3, 2, DIMZIN=0)
    return got == "1'-5.50\"", got


@pin('R10', "mode 3 follows DIMZIN's feet/inch bits too: 15' at 0, "
     "15'-0.00\" at 1, 6.00\" at 0", DIMZIN_DOC + " ('Values 0-3 affect "
     "feet-and-inch dimensions')")
def _r10():
    got = (rtos(180, 3, 2, DIMZIN=0), rtos(180, 3, 2, DIMZIN=1),
           rtos(6, 3, 2, DIMZIN=0))
    return got == ("15'", "15'-0.00\"", '6.00"'), got


@pin('R11', "a value that rounds up to twelve inches is the next foot",
     CARRY)
def _r11():
    got = (rtos(191.99, 4, 0, DIMZIN=1), rtos(191.999, 3, 2, DIMZIN=1))
    return got == ("16'-0\"", "16'-0.00\""), got


@pin('R12', "mode 2 at DIMZIN 8 trims trailing zeros, and the point with "
     "them: 14.3, 12", DIMZIN_DEC + '; ' + REPO_CDATE)
def _r12():
    got = (rtos(14.3, 2, 2, DIMZIN=8), rtos(12, 2, 4, DIMZIN=8),
           rtos(12.5, 2, 4, DIMZIN=8))
    return got == ('14.3', '12', '12.5'), got


@pin('R13', "mode 2 at DIMZIN 4 drops the leading zero, at 12 both: "
     ".50, .5, -.25", DIMZIN_DEC)
def _r13():
    got = (rtos(0.5, 2, 2, DIMZIN=4), rtos(0.5, 2, 4, DIMZIN=12),
           rtos(-0.25, 2, 2, DIMZIN=4))
    return got == ('.50', '.5', '-.25'), got


@pin('R14', "mode 2 at DIMZIN 0 keeps every digit: 17.50, 0.5000",
     RTOS_EX)
def _r14():
    got = (rtos(17.5, 2, 2, DIMZIN=0), rtos(0.5, 2, 4, DIMZIN=0))
    return got == ('17.50', '0.5000'), got


@pin('R15', "CDATE through (rtos d 2 6) is trimmed at DIMZIN 8",
     REPO_CDATE)
def _r15():
    got = (rtos(20260821.143, 2, 6, DIMZIN=8),
           rtos(20260821.143, 2, 6, DIMZIN=0))
    return got == ('20260821.143', '20260821.143000'), got


@pin('R16', "modes 1 and 5: 1.7500E+01 and 17 1/2", RTOS_EX)
def _r16():
    got = (rtos(17.5, 1, 4, DIMZIN=0), rtos(17.5, 5, 2, DIMZIN=0),
           rtos(0.5, 5, 2, DIMZIN=0), rtos(-17.5, 5, 2, DIMZIN=0))
    return got == ('1.7500E+01', '17 1/2', '1/2', '-17 1/2'), got


@pin('R17', "(rtos v) with no mode or precision reads LUNITS and LUPREC",
     RTOS_DOC)
def _r17():
    got = (rtos(47.8, LUNITS=2, LUPREC=1, DIMZIN=0),
           rtos(47.8, LUNITS=4, LUPREC=0, DIMZIN=0),
           rtos(47.8, LUNITS=4, LUPREC=0, DIMZIN=1),
           rtos(2.0, 2, LUPREC=1, DIMZIN=0))
    return got == ('47.8', "4'", "4'-0\"", '2.0'), got


@pin('R18', "LUPREC is seeded at acad.dwt's 4, so (rtos 1.0) is 1.0000",
     LUPREC_SEED)
def _r18():
    got = (ev('(getvar "LUPREC")'), ev('(rtos 1.0)'))
    return got == (4, '1.0000'), got


# ================================================================ distof
@pin('D1', "mode 1 reads rtos's scientific spelling back: 1.7500E+01 is 17.5",
     DISTOF_DOC + '; ' + RTOS_EX)
def _d1():
    got = (ev('(distof "1.7500E+01" 1)'), ev('(distof "-2.5E-01" 1)'))
    return got == (17.5, -0.25), got


@pin('D2', "mode 5 reads rtos's fractional spelling back: 17 1/2, 1/2, 17",
     DISTOF_DOC + '; ' + RTOS_EX)
def _d2():
    got = (ev('(distof "17 1/2" 5)'), ev('(distof "1/2" 5)'),
           ev('(distof "17" 5)'), ev('(distof "-17 1/2" 5)'))
    return got == (17.5, 0.5, 17.0, -17.5), got


@pin('D3', "a mode left out is LUNITS: 2'-6\" is 30 in a LUNITS 4 drawing",
     DISTOF_DOC)
def _d3():
    got = (ev('(distof "2\'-6\\"")', LUNITS=4),
           ev('(distof "30.5")', LUNITS=2))
    return got == (30.0, 30.5), got


@pin('D4', "(distof (rtos x m 2) m) is x again, in every mode 1 to 5",
     DISTOF_DOC + '; ' + RTOS_EX)
def _d4():
    got = [ev('(distof (rtos 17.5 %d 2) %d)' % (m, m)) for m in range(1, 6)]
    return got == [17.5] * 5, got


# =============================================================== vl-sort
@pin('S1', "two equal INTEGERS: one is dropped", SORT_DOC)
def _s1():
    got = plain(ev("(vl-sort '(3 2 1 3) '<)"))
    return got == [1, 2, 3], got


@pin('S2', "equal REALS all stay", SORT_REALS)
def _s2():
    got = plain(ev("(vl-sort '(3.0 2.0 1.0 1.0 1.0) '<)"))
    return got == [1.0, 1.0, 1.0, 2.0, 3.0], got


@pin('S3', "points that tie on the key all stay", SORT_REALS)
def _s3():
    got = plain(ev("(vl-sort '((1.0 2.0) (1.0 5.0) (0.0 0.0) (1.0 2.0))"
                   " '(lambda (a b) (< (car a) (car b))))"))
    return (len(got or []) == 4 and got[0] == [0.0, 0.0]
            and sorted(map(tuple, got[1:])) == [(1.0, 2.0), (1.0, 2.0),
                                                (1.0, 5.0)]), got


@pin('S4', "equal strings all stay", SORT_REALS)
def _s4():
    got = plain(ev("(vl-sort '(\"deck\" \"pool\" \"deck\") '<)"))
    return got == ['deck', 'deck', 'pool'], got


@pin('S5', "two integers that only COMPARE equal (sorted by abs) both "
     "stay: the drop is EQ, not the comparator", SORT_EQ)
def _s5():
    got = plain(ev("(vl-sort '(2 -1 1) '(lambda (a b) (< (abs a) (abs b))))"))
    return (len(got or []) == 3 and sorted(got) == [-1, 1, 2]
            and got[-1] == 2), got


@pin('S6', "vl-sort-i drops nothing", SORT_DOC)
def _s6():
    got = plain(ev("(vl-sort-i '(3 2 1 3) '<)"))
    return got in ([2, 1, 0, 3], [2, 1, 3, 0]), got


# ======================================================== entmod / entdel
@pin('E1', "entmod on an entity on a LOCKED layer answers nil and changes "
     "nothing", ENTMOD_DOC + '; ' + LOCK_BIT)
def _e1():
    vm, ents = drawing(('LK', 4))
    r = modify(vm, ents['LK'])
    return r is NIL and end_x(vm, ents['LK']) == 1.0, (r, end_x(vm, ents['LK']))


@pin('E2', "entmod on an unlocked layer (frozen/off bits too) still writes",
     ENTMOD_DOC)
def _e2():
    vm, ents = drawing(('OPEN', 0), ('COLD', 1))
    r1, r2 = modify(vm, ents['OPEN']), modify(vm, ents['COLD'])
    return (r1 is not NIL and r2 is not NIL and end_x(vm, ents['OPEN']) == 9.0
            and end_x(vm, ents['COLD']) == 9.0), (r1, r2)


@pin('E3', "the locked layer's own RECORD is writable: unlock it by entmod, "
     "and the entity's entmod then lands", RECORD_OK)
def _e3():
    vm, ents = drawing(('LK', 4))
    rec = vm.loads('(entmod (subst (cons 70 0) (assoc 70 (entget '
                   '(tblobjname "LAYER" "LK"))) (entget (tblobjname '
                   '"LAYER" "LK"))))')
    r = modify(vm, ents['LK'])
    return (rec is not NIL and r is not NIL
            and end_x(vm, ents['LK']) == 9.0), (rec, r)


@pin('E4', "an entmod that would move an entity OFF a locked layer is "
     "refused: it is the entity's layer now that counts", ENTMOD_DOC)
def _e4():
    vm, ents = drawing(('LK', 4), ('OPEN', 0))
    r = modify(vm, ents['LK'], '(entmod (subst (cons 8 "OPEN") '
               '(assoc 8 (entget e)) (entget e)))')
    return r is NIL and layer_of(vm, ents['LK']) == 'LK', (
        r, layer_of(vm, ents['LK']))


@pin('E5', "a layer locked by vla-put-Lock refuses too", LOCK_BIT)
def _e5():
    vm, ents = drawing(('LK', 0))
    vm.loads('(vla-put-Lock (vlax-ename->vla-object (tblobjname "LAYER" '
             '"LK")) :vlax-true)')
    r = modify(vm, ents['LK'])
    return r is NIL and end_x(vm, ents['LK']) == 1.0, r


@pin('E6', "entdel on a LOCKED layer answers nil and the entity stays",
     ENTDEL_REPO)
def _e6():
    vm, ents = drawing(('LK', 4), ('OPEN', 0))
    vm.globals[Sym('a')] = ents['LK']
    vm.globals[Sym('b')] = ents['OPEN']
    r1, r2 = vm.loads('(entdel a)'), vm.loads('(entdel b)')
    return (r1 is NIL and ents['LK'] not in vm.deleted
            and r2 is ents['OPEN'] and ents['OPEN'] in vm.deleted), (r1, r2)


@pin('E7', "an attributed INSERT on a locked layer: entdel refuses, and "
     "its ATTRIBs stay with it", ENTDEL_REPO)
def _e7():
    vm = VM()
    vm.loads(LAYER % ('TB', 4))
    vm.loads('(entmake (list \'(0 . "INSERT") \'(8 . "TB") \'(2 . "T") '
             '\'(66 . 1) \'(10 0.0 0.0 0.0)))')
    ins = vm.entities[-1]
    vm.loads('(entmake (list \'(0 . "ATTRIB") \'(8 . "TB") \'(2 . "D") '
             '\'(1 . "x") \'(10 0.0 0.0 0.0)))')
    att = vm.entities[-1]
    vm.loads('(entmake (list \'(0 . "SEQEND") \'(8 . "TB")))')
    vm.globals[Sym('a')] = ins
    r = vm.loads('(entdel a)')
    return r is NIL and ins not in vm.deleted and att not in vm.deleted, r


@pin('E8', "entmake onto a locked layer still creates", RECORD_OK)
def _e8():
    vm, ents = drawing(('LK', 4))
    return ents['LK'] in vm.entdata and vm.loads('(entlast)') is ents['LK'], \
        None


@pin('E9', "a refusal is named in vm.lock_refusals, (builtin, ename)",
     CONTRACT)
def _e9():
    vm, ents = drawing(('LK', 4))
    modify(vm, ents['LK'])
    vm.globals[Sym('a')] = ents['LK']
    vm.loads('(entdel a)')
    got = getattr(vm, 'lock_refusals', None)
    return got == [('entmod', ents['LK']), ('entdel', ents['LK'])], got


def main():
    fails = []
    for pid, rule, source, fn in PINS:
        try:
            ok, detail = fn()
        except Exception as x:          # a pin must report, never crash
            ok, detail = False, 'raised %s: %s' % (
                type(x).__name__, str(x).splitlines()[0])
        print('  %-4s %-4s %s' % ('ok' if ok else 'FAIL', pid, rule))
        if not ok:
            print('            got: %r' % (detail,))
            print('            source: %s' % source)
            fails.append(pid)
    if fails:
        print('\n%d of %d values pins FAILED: %s'
              % (len(fails), len(PINS), ' '.join(fails)))
        sys.exit(1)
    print('\nALL %d VALUES PINS PASSED' % len(PINS))


if __name__ == '__main__':
    main()
