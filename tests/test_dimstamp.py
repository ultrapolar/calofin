"""Runtime tests: load the real DIMSTAMP.lsp into the AutoLISP VM and
drive c:DIMSTAMP with scripted clicks and answers.  AutoLISP cannot run
outside AutoCAD, so this is where a wrong arity, an unbound function or
a parse that silently drifted has to die.

Script values answer the interactive calls in order: one getpoint per
click (None = Enter, done).  After the first click the text is a
getstring (the very first placement).  Every later prompt is ONE
getpoint that stands in for three things at once: a point that is not
on the ruler (a tuple) stamps there; a point that lands on one of the
ruler's rows adopts that row's value instead of stamping; a string
answers the same prompt's typed-text fallback and is parsed as a brand
new value.  A callable in the script is called at its prompt -- that
is how a scenario presses Esc.

The ruler is pinned to the VIEW, so where its rows are depends on
VIEWCTR / VIEWSIZE / SCREENSIZE.  A scenario that clicks one asks
ds:draw-ruler itself where the rows went (probe_ruler below) rather
than hard-coding coordinates that a knob would rot.
Run: python3 tests/test_dimstamp.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_dimstamp.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'dimstamp', 'DIMSTAMP.lsp')

#: well clear of the ruler's strip, whatever knob moves it -- a stamp
#: click that must not be read as a row pick
FAR = (300.0, 300.0)

#: the height code every drawn fraction is wrapped in at the default
#: knob -- 1.0000x, the size of the text around it
FULL = '{\\H1.0000x;'

#: and the alignment code the line carrying it opens with, centred --
#: the pair the shop's own dimension text carries
MID = '\\A1;'


def newvm():
    vm = VM()
    vm.load(LSP)
    return vm


def run(vm, script, label):
    try:
        vm.run('c:DIMSTAMP', list(script))
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def probe_ruler(value, family, **sysvars):
    """Where the ruler for this value lands, read off the routine
    itself in a throwaway VM: (spine-x, box, rows).  FAMILY is the tag
    ds:parse hands back beside the value -- None or True for a
    measurement in inches or in feet, 'letter' for a label."""
    vm = newvm()
    vm.sysvars.update(sysvars)
    fam = ("(quote letter)" if family == 'letter'
           else ('t' if family else 'nil'))
    _, box, rows = vm.loads('(ds:draw-ruler %d %s)' % (value, fam))
    return (box[0] + box[1]) / 2.0, box, rows


def _alist_dict(alist):
    d = {}
    for p in alist:
        if hasattr(p, 'a'):
            d.setdefault(p.a, p.b)
        elif isinstance(p, list) and p:
            d.setdefault(p[0], p[1] if len(p) == 2 else p[1:])
    return d


def live_entities(vm):
    return [_alist_dict(vm.entdata[e])
            for e in vm.entities if e not in vm.deleted]


def stamps(vm):
    """The MTEXT left in the drawing on the stamp layer -- what the
    tool exists to produce, as against the ruler's scratch labels."""
    return [d for d in live_entities(vm)
            if d.get(0) == 'MTEXT' and d.get(8) == 'TEXT']


def by_type(vm):
    from collections import Counter
    c = Counter()
    for d in live_entities(vm):
        c[d.get(0)] += 1
    return c


def undo_calls(vm):
    return [c[1] for c in vm.commands if c and c[0] == '_.UNDO']


def esc(vm):
    """The drafter presses Esc at this prompt."""
    raise LispError('Function cancelled', vm)


# ---- parsing / formatting / tiering / suggestions, called directly ----

def test_parse_and_format_round_trip():
    vm = newvm()
    cases = [
        ('34"', 272, None),
        ("3'-4\"", 320, 't'),
        ('34 1/2"', 276, None),
        ("3'-4 1/2\"", 324, 't'),
    ]
    for s, eighths, hasfeet in cases:
        esc_s = s.replace('"', '\\"')
        got = vm.loads(f'(ds:parse "{esc_s}")')
        assert got == [eighths, hasfeet], (s, got)
        back = vm.loads(f'(ds:format {eighths} {"t" if hasfeet else "nil"})')
        assert back == s, (s, back)
    print("ok  parse/format -> all four canonical forms round-trip")


def test_reads_the_lazy_spellings():
    """Nobody types a dimension carefully twice.  The inch mark is
    optional (or two apostrophes), the dash after the feet mark is
    optional, inches may be decimal, a fraction may be spaced or
    dashed -- and whatever comes in, the CANONICAL spelling comes
    back out."""
    vm = newvm()
    same = {
        "4'-4 1/2\"": ["4'4.5", "4'-4 1/2\"", "4' 4-1/2", "4'4 1/2",
                        "4'-4.5\"", "  4'4.5  ", "4'4.50"],
        "4'-4\"":      ["4'4", "4'-4\"", "4'4''"],
        "4'-0\"":      ["4'"],
        '44"':         ['44', '44"', "44''", '44.0'],
        '44 1/2"':     ['44.5', '44 1/2', '44-1/2', '44 1/2"'],
    }
    for canon, spellings in same.items():
        for s in spellings:
            esc_s = s.replace('"', '\\"')
            got = vm.loads(f'(ds:read "{esc_s}")')
            assert got == canon, (s, got, canon)
    # feet spelled means feet written; bare inches stay bare inches
    assert vm.loads('(ds:read "52.5")') == '52 1/2"'
    assert vm.loads("(ds:read \"4.5'\")") == "4'-6\""
    print("ok  lazy input   -> 4'4.5, 4' 4-1/2, 44.5 and the rest all"
          " read, canonically")


def test_two_spellings_plain_and_stacked():
    """One value, two spellings.  The PLAIN one spaces its fraction off
    the inches, for a command line that cannot stack.  The DRAWN one
    stacks it through AutoCAD's \\S code with NO space in front -- the
    stack is the separation -- and that is the only one that reaches an
    MTEXT."""
    vm = newvm()
    for eighths, hasfeet, plain, drawn in [
            (272, 'nil', '34"', '34"'),                 # no fraction: same
            (276, 'nil', '34 1/2"', f'{MID}34{FULL}\\S1/2;}}"'),
            (320, 't', "3'-4\"", "3'-4\""),             # no fraction: same
            (396, 't', "4'-1 1/2\"", f"{MID}4'-1{FULL}\\S1/2;}}\""),
            (398, 't', "4'-1 3/4\"", f"{MID}4'-1{FULL}\\S3/4;}}\"")]:
        assert vm.loads(f'(ds:format {eighths} {hasfeet})') == plain
        assert vm.loads(f'(ds:stacked {eighths} {hasfeet})') == drawn
    # and ds:drawn is the door between them, taking the plain spelling
    assert (vm.loads('(ds:drawn "4\'-1 1/2\\"")')
            == f"{MID}4'-1{FULL}\\S1/2;}}\"")
    # no space survives anywhere in a drawn fraction
    assert ' ' not in vm.loads('(ds:stacked 396 t)')
    print("ok  stacked      -> the drawn fraction is \\S-stacked and"
          " space-free; the echoed one stays readable")


def test_the_stacked_fraction_is_the_size_of_the_text_around_it():
    """A stack AutoCAD sizes itself comes out at 70% of the text it sits
    in, which drew the half in 34 1/2" a size down from the 34.  So the
    drawn spelling carries its own \\H height code, at ds:*stack-hgt*
    -- 1.0, the size of the number beside it -- and the BRACES close
    that height at the end of the stack, so the inch mark after it is
    back at the stamp's own size."""
    vm = newvm()
    assert vm.loads('ds:*stack-hgt*') == 1.0, 'full size by default'
    assert (vm.loads('(ds:stacked 276 nil)')
            == '\\A1;34{\\H1.0000x;\\S1/2;}"')
    # the height code opens INSIDE the group and the group closes
    # before the inch mark -- the " is not part of the fraction
    assert vm.loads('(ds:stacked 276 nil)').endswith(';}"')
    # a value with no fraction has no height code to carry
    assert '\\H' not in vm.loads('(ds:stacked 272 nil)')
    # the knob is the factor, and it reaches the drawing
    vm.loads('(setq ds:*stack-hgt* 0.75)')
    assert (vm.loads('(ds:stacked 276 nil)')
            == '\\A1;34{\\H0.7500x;\\S1/2;}"')
    # and nil hands the sizing back to AutoCAD: the bare \\S spelling
    vm.loads('(setq ds:*stack-hgt* nil)')
    assert vm.loads('(ds:stacked 276 nil)') == '\\A1;34\\S1/2;"'
    print("ok  stack height -> the fraction is drawn the size of the"
          " text around it, and the \" after it is not")


def test_the_stacked_fraction_sits_on_its_line():
    """The other half of drawing a full-height stack: sized back up and
    left on the baseline, a fraction towers over the number it belongs
    to.  So a line with a stack on it opens with an \\A alignment code,
    at ds:*stack-align* -- 1, centred, which is what the shop's own
    dimension text carries (\\A1;33'-2{\\H1x;\\S1/2;}" out of one of
    these drawings)."""
    vm = newvm()
    assert vm.loads('ds:*stack-align*') == 1, 'centred by default'
    # the code opens the WHOLE line, ahead of the whole inches -- \A
    # applies from where it stands, and it is the line being aligned
    assert vm.loads('(ds:stacked 396 t)').startswith('\\A1;4\'-1{')
    # a line with no fraction on it has nothing to align
    assert vm.loads('(ds:stacked 320 t)') == "3'-4\""
    # the knob is the value: 0 bottom, 1 centred, 2 top
    vm.loads('(setq ds:*stack-align* 2)')
    assert vm.loads('(ds:stacked 276 nil)').startswith('\\A2;34{')
    # and nil writes no alignment code at all
    vm.loads('(setq ds:*stack-align* nil)')
    assert vm.loads('(ds:stacked 276 nil)') == '34{\\H1.0000x;\\S1/2;}"'
    # the plain spelling carries neither code, whatever the knobs say
    assert vm.loads('(ds:format 276 nil)') == '34 1/2"'
    print("ok  stack line   -> a line with a stack on it is centred on"
          " itself, the way the shop's own text is")


def test_the_stack_separator_is_a_knob():
    vm = newvm()
    vm.loads('(setq ds:*stack* "#")')     # the diagonal form
    assert vm.loads('(ds:stacked 396 t)') == f"{MID}4'-1{FULL}\\S1#2;}}\""
    print("ok  stack knob   -> ds:*stack* picks bar, diagonal or"
          " tolerance stacking")


def test_letters_are_a_family_of_their_own():
    """The survey points are named in letters, so a letter is the other
    thing this tool stamps.  A is 1, Z is 26, AA is 27 -- a
    spreadsheet's columns -- and ds:parse tags it 'letter, which is
    what every other part reads the family off."""
    vm = newvm()
    for n, name in [(1, 'A'), (2, 'B'), (26, 'Z'), (27, 'AA'),
                    (28, 'AB'), (52, 'AZ'), (53, 'BA'), (702, 'ZZ')]:
        assert vm.loads(f'(ds:letter-name {n})') == name
        assert vm.loads(f'(ds:letter-index "{name}")') == n
    # case does not matter going in; what comes out is upper case
    assert vm.loads('(ds:letter-index "b")') == 2
    assert vm.loads('(ds:read "b")') == 'B'
    # the family rides along in the parse, beside the two measurement ones
    assert vm.loads('(ds:parse "A")') == [1, 'letter']
    assert vm.loads('(ds:parse "AB")') == [28, 'letter']
    assert vm.loads('(ds:parse "34 1/2\\"")') == [276, None]
    # nothing in a label stacks: the drawn spelling IS the plain one
    assert vm.loads('(ds:drawn "A")') == 'A'
    assert vm.loads('(ds:stacked 1 (quote letter))') == 'A'
    print("ok  letters      -> A, B ... Z, AA: a family of their own,"
          " parsed and spelled as one")


def test_a_word_is_not_a_label():
    """A label is one or two letters.  A longer run of them is a word
    somebody typed by mistake, and being told beats finding NOPE
    stamped on a sheet."""
    vm = newvm()
    assert vm.loads('(ds:letter-index "nope")') is None
    assert vm.loads('(ds:parse "nope")') is None
    assert vm.loads('(ds:letter-index "4A")') is None, 'digits are not a label'
    assert vm.loads('(ds:letter-index "")') is None
    # ...and how long is a knob
    vm.loads('(setq ds:*letter-max* 4)')
    assert vm.loads('(ds:letter-index "nope")') == 256625
    print("ok  not a label  -> a word is refused, and the length is"
          " ds:*letter-max*")


def test_the_ruler_offers_letters_when_the_value_is_one():
    """What is near A is B, not 1/8\": the ruler offers the letters
    either side instead of the eighths, all one tier because every
    letter is one whole step, and nothing before A."""
    vm = newvm()
    ents, box, rows = vm.loads("(ds:draw-ruler 3 (quote letter))")   # C
    # four either side, plus the current row
    assert [v for v, y in rows] == [1, 2, 3, 4, 5, 6, 7], rows
    labels = sorted(d[1] for d in live_entities(vm) if d.get(0) == 'MTEXT')
    assert labels == ['A', 'B', 'C', 'D', 'E', 'F', 'G'], labels
    # no row before A, however near the front of the sequence it starts
    _, _, rows = vm.loads("(ds:draw-ruler 1 (quote letter))")        # A
    assert [v for v, y in rows] == [1, 2, 3, 4, 5], rows
    # every letter row is the same size -- there is no eighth of a letter
    heights = {d.get(40) for d in live_entities(vm) if d.get(0) == 'MTEXT'}
    assert len(heights) == 1, heights
    # and how many is a knob
    vm.loads('(setq ds:*letters-either-side* 2)')
    _, _, rows = vm.loads("(ds:draw-ruler 10 (quote letter))")
    assert len(rows) == 5, rows
    print("ok  letter ruler -> the letters either side, one tier, none"
          " before A")


def test_a_letter_moves_on_as_it_is_stamped():
    """The whole of stamping a lot of letters: a run of labels is A, B,
    C and never A, A, A, so the value steps by one as it lands and the
    next click stamps the next letter."""
    vm = newvm()
    run(vm, [(0.0, 0.0), 'A', (10.0, 0.0), (20.0, 0.0), (30.0, 0.0),
             None], 'a lot of letters')
    t = stamps(vm)
    assert [x[1] for x in t] == ['A', 'B', 'C', 'D'], t
    assert [tuple(x[10][:2]) for x in t] == [(0.0, 0.0), (10.0, 0.0),
                                             (20.0, 0.0), (30.0, 0.0)], t
    # the line back says which one is next, so a run reads off the
    # command line without looking at the ruler
    assert [p for p in vm.printed if p.startswith(' Next:')] == \
        [' Next: B.', ' Next: C.', ' Next: D.', ' Next: E.'], vm.printed
    # a MEASUREMENT stays put -- stamping 34" in three places is what
    # dimensioning is
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', (10.0, 0.0), (20.0, 0.0), None], 'measure')
    assert [x[1] for x in stamps(vm)] == ['34"', '34"', '34"']
    assert not any(p.startswith(' Next:') for p in vm.printed), vm.printed
    # ...and the moving on is a knob
    vm = newvm()
    vm.loads('(setq ds:*letter-advance* nil)')
    run(vm, [(0.0, 0.0), 'A', (10.0, 0.0), None], 'no advance')
    assert [x[1] for x in stamps(vm)] == ['A', 'A']
    print("ok  letter run   -> A, B, C off three clicks; a measurement"
          " stays put")


def test_a_letter_picked_off_the_ruler_carries_on_from_there():
    """Adopting a letter works the way adopting a measurement does, and
    the run carries on from the letter picked.  Note where the ruler
    is by then: stamping C moved the value on to D, so the ruler has
    already re-centred on D and it is D's rows a click lands on --
    the ruler follows the advance rather than the letter just
    stamped."""
    vm = newvm()
    # D, with four either side: nothing before A, so A..H
    spine, box, rows = probe_ruler(4, 'letter')
    assert [v for v, y in rows] == [1, 2, 3, 4, 5, 6, 7, 8], rows
    run(vm, [(0.0, 0.0), 'C',           # stamps C, moves on to D
             (spine, rows[-1][1]),      # pick the top row, H
             (10.0, 0.0),               # stamp it
             (20.0, 0.0),               # and the next letter after it
             None], 'adopt a letter')
    assert [x[1] for x in stamps(vm)] == ['C', 'H', 'I'], stamps(vm)
    print("ok  letter pick  -> adopted off the ruler, and the run"
          " carries on from there")


def test_rounds_to_the_nearest_eighth():
    vm = newvm()
    assert vm.loads('(ds:read "44.6")') == '44 5/8"', 'nearest eighth'
    assert vm.loads('(ds:read "44.05")') == '44"', 'nearest eighth'
    assert vm.loads('(ds:read "44.44")') == '44 1/2"', 'nearest eighth'
    print("ok  rounding     -> a decimal lands on the nearest eighth")


def test_rejects_what_is_not_a_measurement():
    vm = newvm()
    bad = ['abc', '', '"', 'nope', "4'x", '44 1/0', '0', '0"', '-',
           '4/', '1/2/3']
    for s in bad:
        esc_s = s.replace('"', '\\"')
        assert vm.loads(f'(ds:parse "{esc_s}")') is None, s
    print("ok  reject       -> text that is not a measurement parses to"
          " nil, zero included")


def test_tier_grading():
    vm = newvm()
    got = [vm.loads(f'(ds:tier {i})') for i in range(1, 9)]
    assert got == ['eighth', 'quarter', 'eighth', 'half',
                   'eighth', 'quarter', 'eighth', 'jump'], got
    assert [vm.loads(f'(ds:tier {-i})') for i in range(1, 9)] == got
    print("ok  tier         -> eighth/quarter/half/jump graded by offset")


def test_suggestions_span_an_inch_either_side():
    """44" offers every eighth from 43" to 45" -- the inch BEFORE as
    well as the inch after -- each row tagged by tier for the ruler to
    grade.  ds:suggestions itself is unsorted (ds:draw-ruler sorts once
    it also has the current row to place), so compare as a set."""
    vm = newvm()
    sugg = vm.loads('(ds:suggestions 352 nil)')       # 352 eighths = 44"
    rendered = {vm.loads(f'(ds:format {v} nil)'): t for v, t in sugg}
    assert len(rendered) == 16, rendered              # 8 each side
    assert rendered['43"'] == 'jump' and rendered['45"'] == 'jump', rendered
    assert rendered['43 1/2"'] == 'half', rendered
    assert rendered['44 1/2"'] == 'half', rendered
    assert rendered['43 7/8"'] == 'eighth', rendered
    assert rendered['44 1/4"'] == 'quarter', rendered
    assert '44"' not in rendered, rendered   # the current row, added by
    print("ok  suggest 44\"  -> 43\" through 45\" by eighths, graded")   # the ruler


def test_suggestions_feet_combine_quarter_and_eighth():
    """3'-4" -- feet involved -- gets BOTH quarter and eighth steps
    together (told apart by tier, not by switching granularity) for an
    inch either side, plus the 2" and 3" jumps beyond that."""
    vm = newvm()
    sugg = vm.loads("(ds:suggestions 320 t)")
    assert len(sugg) == 20, sugg
    rendered = {vm.loads(f'(ds:format {v} t)'): t for v, t in sugg}
    assert rendered['3\'-4 1/4"'] == 'quarter', rendered
    assert rendered['3\'-4 1/8"'] == 'eighth', rendered
    assert rendered['3\'-4 1/2"'] == 'half', rendered
    assert rendered['3\'-3 1/8"'] == 'eighth', rendered   # the inch below
    assert rendered['3\'-5"'] == 'jump' and rendered['3\'-3"'] == 'jump', \
        rendered
    assert rendered['3\'-7"'] == 'jump', rendered          # +3"
    assert rendered['3\'-1"'] == 'jump', rendered          # -3"
    print("ok  suggest 3'-4\" -> quarter AND eighth steps together, graded,"
          " plus the 2\"/3\" jumps")


def test_suggestions_never_go_non_positive():
    vm = newvm()
    sugg = vm.loads('(ds:suggestions 2 t)')
    assert all(v > 0 for v, t in sugg), sugg
    print("ok  near zero    -> non-positive suggestions dropped")


# ---- the stamp's own properties ---------------------------------------

def test_stamp_carries_the_shop_mtext_properties():
    """The whole point of the stamp: an MTEXT on the TEXT layer in the
    Attributes style, 6" high, attached top left at the click,
    unwrapped, upright, ByLayer."""
    vm = newvm()
    run(vm, [(12.0, 34.0), "3'-4\"", None], 'properties')
    t = stamps(vm)
    assert len(t) == 1, t
    d = t[0]
    assert d[0] == 'MTEXT', d
    assert d[8] == 'TEXT', d                  # layer
    assert d[7] == 'Attributes', d            # text style
    assert d[40] == 6.0, d                    # text height
    assert d[41] == 0.0, d                    # defined width: no wrap
    assert d[71] == 1, d                      # attachment: top left
    assert d[72] == 5, d                      # direction: by style
    assert d[73] == 1, d                      # line spacing: at least
    assert d[44] == 1.0, d                    # line space factor
    assert d[50] == 0.0, d                    # rotation
    assert 62 not in d, d                     # colour: ByLayer
    assert d[10][:2] == [12.0, 34.0], d       # top left AT the click
    assert d[1] == "3'-4\"", d
    print("ok  properties   -> MTEXT on TEXT, Attributes, 6\", top left,"
          " no wrap, ByLayer")


def test_missing_text_style_is_made_and_reported():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'style made')
    assert 'ATTRIBUTES' in {s.upper() for s in vm.tables['STYLE']}, \
        vm.tables['STYLE']
    assert any('text style Attributes was not in this drawing' in p
               for p in vm.printed), vm.printed
    print("ok  style        -> made when the drawing has not got it, and"
          " said so")


def test_existing_text_style_is_left_alone():
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "STYLE")'
             ' \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbTextStyleTableRecord") \'(2 . "Attributes")'
             ' \'(70 . 0) \'(40 . 0.0) \'(3 . "arial.ttf")))')
    run(vm, [(0.0, 0.0), '34"', None], 'style kept')
    assert not any('text style' in p for p in vm.printed), vm.printed
    print("ok  style kept   -> a drawing that already has it keeps its"
          " own font")


# ---- the ruler, pinned to the view ------------------------------------

def test_draw_ruler_geometry():
    """The ruler: a spine, one tick+label row per suggestion plus a
    circled CURRENT row, sizes graded by tier."""
    vm = newvm()
    ents, box, rows = vm.loads('(ds:draw-ruler 352 nil)')   # 44"
    assert len(rows) == 17         # 16 suggestions + the current row
    assert [v for v, y in rows] == list(range(344, 361)), rows  # 43"-45"
    kinds = by_type(vm)
    assert kinds['LINE'] == 18     # 17 ticks + 1 spine
    assert kinds['MTEXT'] == 17    # one label per row
    assert kinds['CIRCLE'] == 1    # the current row, circled
    heights = sorted({d.get(40) for d in live_entities(vm)
                      if d.get(0) == 'MTEXT'})
    assert len(heights) == 4, heights          # four tiers, four sizes
    assert heights[0] < heights[-1], heights
    print("ok  ruler        -> spine + graded ticks/labels + one ringed"
          " current row")


def test_the_current_row_is_drawn_as_a_stamp_not_as_a_ruler():
    """Every row you can PICK is the ruler's: its scratch layer, its
    colour.  The row you are ON is not an option, so tick, label and
    ring alike go on the STAMP's layer at the stamp's colour --
    ByLayer -- which is what makes it stand out from the pickable
    rows and read as the thing it would stamp."""
    vm = newvm()
    vm.loads('(ds:draw-ruler 352 nil)')            # 44", 17 rows
    ruler = [d for d in live_entities(vm) if d.get(8) == 'DIMSTAMP RULER']
    mine = [d for d in live_entities(vm) if d.get(8) == 'TEXT']
    # 16 option ticks + the spine, 16 option labels, all in the ruler's
    # colour
    assert len(ruler) == 33, len(ruler)
    assert all(d.get(62) == 3 for d in ruler), ruler
    # the current row: its tick, its label and its ring, all ByLayer
    assert sorted(d.get(0) for d in mine) == ['CIRCLE', 'LINE', 'MTEXT'], mine
    assert all(62 not in d for d in mine), mine
    assert [d[1] for d in mine if d.get(0) == 'MTEXT'] == ['44"'], mine
    print("ok  current row  -> drawn as a stamp (stamp layer, ByLayer),"
          " not as one of the ruler's options")


def test_the_ring_is_bigger_than_it_was_and_is_a_knob():
    vm = newvm()
    _, _, rows = vm.loads('(ds:draw-ruler 352 nil)')
    gap = rows[1][1] - rows[0][1]
    ring = [d.get(40) for d in live_entities(vm) if d.get(0) == 'CIRCLE'][0]
    assert abs(ring / gap - 0.26) < 1e-9, (ring, gap)   # was 0.18
    # ...and it is the knob that says so
    vm = newvm()
    vm.loads('(setq ds:*ring-frac* 0.4)')
    _, _, rows = vm.loads('(ds:draw-ruler 352 nil)')
    gap = rows[1][1] - rows[0][1]
    ring = [d.get(40) for d in live_entities(vm) if d.get(0) == 'CIRCLE'][0]
    assert abs(ring / gap - 0.4) < 1e-9, (ring, gap)
    print("ok  ring         -> bigger than a tick's reach, and"
          " ds:*ring-frac* sets it")


def test_the_ruler_holds_the_right_edge_of_the_view():
    """The strip is scratch over somebody's drawing, so it sits where
    there is least of it: a spine near the RIGHT edge, with every tick
    and label reaching back INWARD from it.  Hung the other way they
    would be drawn past the edge of the screen the ruler is pinned
    to -- unreadable, and a pan away from being pickable."""
    vm = newvm()
    _, box, rows = vm.loads('(ds:draw-ruler 352 nil)')
    vx, vy, vw, vh = vm.loads('(ds:view)')
    spine = vx + vw * 0.88
    assert vm.loads('ds:*ruler-screen-x*') == 0.88, 'pinned right'
    live = live_entities(vm)
    ticks = [d for d in live if d.get(0) == 'LINE']
    labels = [d for d in live if d.get(0) == 'MTEXT']
    # every tick's far end and every label's insertion is inboard of
    # the spine, and the whole ruler is inside the view
    assert all(d[11][0] <= spine + 1e-9 for d in ticks), ticks
    assert all(d[10][0] <= spine + 1e-9 for d in labels), labels
    assert all(d[10][0] > vx for d in labels), labels
    assert spine < vx + vw, (spine, vx + vw)
    # a label on a row that reaches left is hung by its RIGHT edge, so
    # it grows away from the spine instead of back across it
    assert {d.get(71) for d in labels} == {3}, labels
    # and the reserved strip runs inward from the spine too
    assert box[0] < box[1] <= spine + vh * 0.042, box
    print("ok  right edge   -> spine at the right of the view, rows"
          " reaching inward, all of it on screen")


def test_the_side_is_a_knob_and_the_rows_turn_round_with_it():
    """ds:*ruler-screen-x* is still the whole placement knob: put the
    spine back on the left and the rows reach RIGHT again, labels hung
    by their left edge, because a ruler always runs toward the middle
    of the view rather than off its nearest edge."""
    vm = newvm()
    vm.loads('(setq ds:*ruler-screen-x* 0.12)')
    _, box, rows = vm.loads('(ds:draw-ruler 352 nil)')
    vx, vy, vw, vh = vm.loads('(ds:view)')
    spine = vx + vw * 0.12
    live = live_entities(vm)
    ticks = [d for d in live if d.get(0) == 'LINE']
    labels = [d for d in live if d.get(0) == 'MTEXT']
    assert all(d[11][0] >= spine - 1e-9 for d in ticks), ticks
    assert all(d[10][0] >= spine - 1e-9 for d in labels), labels
    assert {d.get(71) for d in labels} == {1}, labels
    assert box[1] > box[0] >= spine - vh * 0.042, box
    # the direction is derived from the side, not set beside it
    assert vm.loads('(ds:ruler-dir)') == 1.0
    vm.loads('(setq ds:*ruler-screen-x* 0.88)')
    assert vm.loads('(ds:ruler-dir)') == -1.0
    print("ok  ruler side   -> the knob moves it, and the rows turn"
          " round to keep reaching inward")


def test_ruler_is_pinned_to_the_view_and_scales_with_it():
    """The ruler holds the same strip of SCREEN at any zoom: centred on
    the view, sized as a fraction of it.  Zoom in 5x and every measure
    comes in 5x smaller, around the new centre."""
    _, wide_box, wide_rows = probe_ruler(352, False)
    assert abs(wide_rows[8][1] - 0.0) < 1e-9, wide_rows   # view centre
    _, near_box, near_rows = probe_ruler(
        352, False, VIEWSIZE=20.0, VIEWCTR=[500.0, 300.0, 0.0])
    assert abs(near_rows[8][1] - 300.0) < 1e-9, near_rows
    wide_span = wide_rows[-1][1] - wide_rows[0][1]
    near_span = near_rows[-1][1] - near_rows[0][1]
    assert abs(wide_span / near_span - 5.0) < 1e-9, (wide_span, near_span)
    assert abs(wide_box[2] / near_box[2] - 5.0) < 1e-9, (wide_box, near_box)
    print("ok  pinned       -> same strip of screen, scaled to the view,"
          " at any zoom")


# ---- the command, end to end ------------------------------------------

def test_first_placement_has_no_ruler_yet():
    """The very first click has nothing to build a ruler around -- a
    plain validated getstring, no ruler until after it lands."""
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'first only')
    t = stamps(vm)
    assert len(t) == 1 and t[0][1] == '34"', t
    print("ok  first click  -> plain text prompt, ruler drawn only after")


def test_ruler_is_cleaned_up_at_the_end():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'ruler cleanup')
    assert by_type(vm) == {'MTEXT': 1}, by_type(vm)
    print("ok  cleanup      -> only the stamped MTEXT survives; the ruler"
          " is erased")


def test_click_elsewhere_stamps_the_current_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', FAR, None], 'stamp again')
    t = stamps(vm)
    assert [x[1] for x in t] == ['34"', '34"'], t
    assert t[1][10][:2] == list(FAR), t[1]
    print("ok  click empty  -> stamps the current text there")


def test_click_a_ruler_row_adopts_without_stamping():
    """Click the ruler's top row -- 35" for a current 34" -- and it is
    adopted, with nothing stamped until the next empty-space click."""
    spine, box, rows = probe_ruler(272, False)
    top = rows[-1]
    assert top[0] == 280, rows                # 280 eighths = 35"
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             (spine, top[1]),                 # the 35" row -- adopt only
             FAR,                             # now stamp, with 35"
             None], 'ruler pick')
    t = stamps(vm)
    assert [x[1] for x in t] == ['34"', '35"'], t
    print("ok  ruler pick   -> adopts the row's value, stamps nothing"
          " until the next click")


def test_a_click_just_off_the_ruler_stamps_instead():
    """The strip is reserved, and only the strip: a click past the end
    of its reach is a stamp, not a row pick.  Either end of it -- the
    inboard one is the side the labels run and the side the drawing
    is on, the outboard one is the sliver beyond the spine."""
    spine, box, rows = probe_ruler(272, False)
    for x, where in [(box[0] - 1.0, 'inboard'), (box[1] + 1.0, 'outboard')]:
        vm = newvm()
        run(vm, [(0.0, 0.0), '34"',
                 (x, rows[-1][1]),            # same row, just outside
                 None], 'off the strip ' + where)
        t = stamps(vm)
        assert [y[1] for y in t] == ['34"', '34"'], (where, t)
    print("ok  off the strip -> a click past either end of the ruler's"
          " reach stamps")


def test_typed_text_at_the_unified_prompt_is_adopted():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             "3'-6\"",               # typed at the unified prompt
             FAR,                    # stamps with the new value
             None], 'typed adopt')
    t = stamps(vm)
    assert [x[1] for x in t] == ['34"', "3'-6\""], t
    print("ok  typed text   -> adopted the same way a ruler pick is")


def test_a_lazy_answer_is_stamped_canonically_and_echoed():
    """Type it lazily at either prompt and the CANONICAL spelling is
    what lands in the drawing -- and the run says what it read, so a
    mis-type is caught by eye."""
    vm = newvm()
    run(vm, [(0.0, 0.0), "4'4.5",    # lazy, at the first prompt
             "52.5",                 # lazy again, at the unified one
             FAR,
             None], 'lazy')
    t = stamps(vm)
    assert [x[1] for x in t] == [f"{MID}4'-4{FULL}\\S1/2;}}\"",
                                 f'{MID}52{FULL}\\S1/2;}}"'], t
    said = [p for p in vm.printed if 'read as' in p]
    assert len(said) == 2, said
    assert "4'-4 1/2\"" in said[0] and '52 1/2"' in said[1], said
    # and a spelling that was ALREADY canonical says nothing extra
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'canonical already')
    assert not any('read as' in p for p in vm.printed), vm.printed
    print("ok  lazy answer  -> stamped canonically, and echoed as what it"
          " was read as")


def test_chained_adoption():
    """Whatever the last click or type landed on becomes what the
    following stamp uses, repeatedly."""
    spine, box, rows = probe_ruler(272, False)
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"',
             (spine, rows[-1][1]),   # adopt 35" off the ruler
             "3'-2\"",                # then type something else entirely
             FAR,                    # stamp with 3'-2"
             None], 'chained')
    t = stamps(vm)
    assert [x[1] for x in t] == ['34"', "3'-2\""], t
    print("ok  chaining     -> a ruler pick or typed value carries"
          " forward to the next stamp")


def test_reprompts_on_malformed_typed_text():
    vm = newvm()
    run(vm, [(0.0, 0.0), 'not a measurement', '34"', None], 'bad first')
    t = stamps(vm)
    assert [x[1] for x in t] == ['34"'], t
    assert any('is not a measurement' in p for p in vm.printed)

    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', 'nope', "3'-4\"", FAR, None],
        'bad at unified prompt')
    t = stamps(vm)
    assert [x[1] for x in t] == ['34"', "3'-4\""], t
    print("ok  bad text     -> re-prompts instead of placing garbage")


def test_no_clicks():
    vm = newvm()
    run(vm, [None], 'no clicks')
    assert stamps(vm) == []
    print("ok  no clicks    -> nothing drawn")


def test_undo_group_wraps_the_run():
    vm = newvm()
    run(vm, [(0.0, 0.0), '34"', None], 'undo group')
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    print("ok  undo group   -> one _Begin before the stamp, one _End"
          " after")


def test_undo_off():
    vm = newvm()
    vm.sysvars['UNDOCTL'] = 0
    run(vm, [(0.0, 0.0), '34"', None], 'undo off')
    assert undo_calls(vm) == [], vm.commands
    assert len(stamps(vm)) == 1
    print("ok  undo off     -> no _.UNDO at all, the stamp still drawn")


def test_esc_mid_run_cleans_up_the_ruler_too():
    vm = newvm()
    vm.handle_errors = True
    run(vm, [(0.0, 0.0), esc], 'Esc at the first text prompt')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    assert not any('error' in p.lower() for p in vm.printed), vm.printed
    assert stamps(vm) == []

    vm = newvm()
    vm.handle_errors = True
    run(vm, [(0.0, 0.0), '34"', esc], 'Esc at the unified prompt')
    assert vm.handled_errors == ['Function cancelled'], vm.handled_errors
    assert undo_calls(vm) == ['_Begin', '_End'], vm.commands
    # the stamp already placed survives; the ruler scratch does not
    assert by_type(vm) == {'MTEXT': 1}, by_type(vm)
    print("ok  Esc          -> handler closes the group, stays silent,"
          " and sweeps the ruler away either way")


def test_layer_repaired_and_coloured():
    vm = newvm()
    vm.loads('(entmake (list \'(0 . "LAYER") \'(100 . "AcDbSymbolTableRecord")'
             ' \'(100 . "AcDbLayerTableRecord") \'(2 . "TEXT")'
             ' \'(70 . 5) \'(62 . -3) \'(6 . "Continuous")))')
    run(vm, [(0.0, 0.0), '34"', None], 'repair')
    rec = _alist_dict(vm.recdata[vm.tablerecs['LAYER']['TEXT']])
    assert rec[70] == 0 and rec[62] == 3, rec
    assert any('was off, frozen or locked' in p for p in vm.printed), \
        vm.printed
    print("ok  layer        -> TEXT repaired when unusable")


def test_knobs_reach_the_output():
    vm = newvm()
    vm.loads('(setq ds:*layer* "MyDims" ds:*text-hgt* 9.0'
             ' ds:*style* "MyStyle" ds:*text-width* 40.0)')
    run(vm, [(0.0, 0.0), '34"', None], 'knobs')
    t = [d for d in live_entities(vm)
         if d.get(0) == 'MTEXT' and d.get(8) == 'MyDims']
    assert len(t) == 1, t
    assert t[0][40] == 9.0 and t[0][7] == 'MyStyle' and t[0][41] == 40.0, t
    print("ok  knobs        -> layer, height, style and wrap width all"
          " read at run time")


def test_no_local_shadows_a_function():
    import re
    src = open(LSP).read()
    src = re.sub(r';[^\n]*', '', src)
    src = re.sub(r'"(\\.|[^"\\])*"', '""', src)
    arglists = re.findall(r'\(defun\s+[^\s()]+\s*\(([^)]*)\)', src)
    bodies = re.sub(r'\(defun\s+[^\s()]+\s*\([^)]*\)', '(defun', src)
    # a lambda's parameter list is parenthesised too -- ((lambda (v)
    # ...) (getpoint ...)) is how LAZDIAG records an input read in place
    bodies = re.sub(r'\(lambda\s*\([^)]*\)', '(lambda', bodies)
    called = set(re.findall(r'\(\s*([a-zA-Z][\w:*<>=+/-]*)', bodies))
    bad = []
    for arglist in arglists:
        for name in arglist.replace('/', ' ').split():
            if name.lower() in called:
                bad.append(name)
    assert not bad, f"locals shadowing functions they call: {sorted(set(bad))}"
    print("ok  no shadow    -> no local hides a function the file calls")


if __name__ == '__main__':
    test_parse_and_format_round_trip()
    test_reads_the_lazy_spellings()
    test_two_spellings_plain_and_stacked()
    test_the_stacked_fraction_is_the_size_of_the_text_around_it()
    test_the_stacked_fraction_sits_on_its_line()
    test_the_stack_separator_is_a_knob()
    test_letters_are_a_family_of_their_own()
    test_a_word_is_not_a_label()
    test_the_ruler_offers_letters_when_the_value_is_one()
    test_a_letter_moves_on_as_it_is_stamped()
    test_a_letter_picked_off_the_ruler_carries_on_from_there()
    test_rounds_to_the_nearest_eighth()
    test_rejects_what_is_not_a_measurement()
    test_tier_grading()
    test_suggestions_span_an_inch_either_side()
    test_suggestions_feet_combine_quarter_and_eighth()
    test_suggestions_never_go_non_positive()
    test_stamp_carries_the_shop_mtext_properties()
    test_missing_text_style_is_made_and_reported()
    test_existing_text_style_is_left_alone()
    test_draw_ruler_geometry()
    test_the_current_row_is_drawn_as_a_stamp_not_as_a_ruler()
    test_the_ring_is_bigger_than_it_was_and_is_a_knob()
    test_the_ruler_holds_the_right_edge_of_the_view()
    test_the_side_is_a_knob_and_the_rows_turn_round_with_it()
    test_ruler_is_pinned_to_the_view_and_scales_with_it()
    test_first_placement_has_no_ruler_yet()
    test_ruler_is_cleaned_up_at_the_end()
    test_click_elsewhere_stamps_the_current_text()
    test_click_a_ruler_row_adopts_without_stamping()
    test_a_click_just_off_the_ruler_stamps_instead()
    test_typed_text_at_the_unified_prompt_is_adopted()
    test_a_lazy_answer_is_stamped_canonically_and_echoed()
    test_chained_adoption()
    test_reprompts_on_malformed_typed_text()
    test_no_clicks()
    test_undo_group_wraps_the_run()
    test_undo_off()
    test_esc_mid_run_cleans_up_the_ruler_too()
    test_layer_repaired_and_coloured()
    test_knobs_reach_the_output()
    test_no_local_shadows_a_function()
    print("all DIMSTAMP tests passed")
