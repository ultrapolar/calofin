#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The Excel sheet reader in ABCDEF, ALTABCDEF and XYPLOT, against a fake
Excel -- the one part of those tools the rest of their tests step round
("the sheet reader is Excel COM and file I/O").

All three carry the same reader, and until ABCDEF v5.9 / ALTABCDEF v1.9
/ XYPLOT v1.9 all three did two things to a drafter's machine that no
test could see:

  * WITH EXCEL ALREADY OPEN it attached to the drafter's own Excel, set
    it invisible, and -- because Workbooks.Open hands back a workbook
    that is already open rather than a second copy -- closed the sheet
    the drafter had open, WITHOUT SAVING.  The tape readings typed since
    the last save were gone, and the Excel window with them.
  * WITH EXCEL CLOSED it could not import at all: vlax-get-object
    answers nil, not an error, when nothing is running, so the branch
    that starts one never ran and every .xlsx import said "Could not
    start Excel (is it installed?)".

The fake is Python builtins standing in for the vlax- calls, so the
Lisp under test is the file as shipped.  Each case says what the reader
may and may not do to Excel: which workbook it closes, whether it hides
anything, whether it quits.

Run: python3 tests/test_excel_reader.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_excel_reader.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, Sym  # noqa: E402

HERE = os.path.dirname(__file__)
REPO = os.path.abspath(os.path.join(HERE, '..'))

READERS = [
    ('ABCDEF', os.path.join(REPO, 'lisp', 'abcdef', 'abcdef.lsp'),
     '(abcdef:read-excel t:*file* 600.0)'),
    ('ALTABCDEF', os.path.join(REPO, 'lisp', 'altabcdef', 'ALTABCDEF.lsp'),
     '(altabcdef:read-excel t:*file* 600.0)'),
    ('XYPLOT', os.path.join(REPO, 'lisp', 'xyplot', 'XYPLOT.lsp'),
     '(xyp:read-excel t:*file*)'),
]

FILE = 'C:\\Jobs\\Smith\\tape.xlsx'
FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + str(detail)) if detail else ''}")
        FAILS.append(label)


class FakeExcel:
    """One Excel.Application: RUNNING says whether vlax-get-object finds
    it, OPEN the full names of the workbooks the drafter has open.  Every
    call that changes anything is logged in CALLS."""

    def __init__(self, running, open_books=(), alias=None):
        self.running = running
        self.books = [Sym('WB%d' % i) for i, _ in enumerate(open_books)]
        self.names = dict(zip(self.books, open_books))
        #: the book Open hands back because it is ALREADY open -- the
        #: same file under another spelling of its path -- or None
        self.alias = alias
        self.calls = []

    # -- the vlax- surface, as builtins taking (vm, args) ---------------
    def get_object(self, vm, a):
        return Sym('XL') if self.running else None

    def create_object(self, vm, a):
        self.calls.append(('create',))
        return Sym('XL')

    def put_property(self, vm, a):
        self.calls.append(('put', str(a[0]), a[1]))
        return None

    def get_property(self, vm, a):
        obj, prop = str(a[0]), a[1]
        if obj == 'XL' and prop == 'Workbooks':
            return Sym('WBS')
        if obj == 'WBS' and prop == 'Count':
            return len(self.books)
        if obj == 'WBS' and prop == 'Item':
            return self.books[a[2] - 1]
        if obj in self.names:
            if prop == 'FullName':
                return self.names[Sym(obj)]
            if prop == 'ActiveSheet':
                return Sym('SHEET')
        if obj == 'SHEET' and prop == 'UsedRange':
            return Sym('USED')
        if obj == 'SHEET' and prop == 'Cells':
            return Sym('CELLS')
        if obj == 'USED' and prop in ('Rows', 'Columns'):
            return Sym('USED-' + prop.upper())
        if obj == 'USED-ROWS' and prop == 'Count':
            return 2                        # a header and one point
        if obj == 'USED-COLUMNS' and prop == 'Count':
            return 3
        if obj == 'CELLS' and prop == 'Item':
            return Sym('CELL-%d-%d' % (a[2], a[3]))
        if obj.startswith('CELL-') and prop == 'Text':
            r, c = obj.split('-')[1:]
            if r == '1':
                return ['Name', 'X', 'Y'][int(c) - 1]
            return ['P1', '12', '34'][int(c) - 1]
        raise lispvm.LispError('fake Excel: no %s.%s' % (obj, prop), vm)

    def invoke_method(self, vm, a):
        obj, meth = str(a[0]), a[1]
        self.calls.append(('invoke', obj, meth))
        if obj == 'WBS' and meth == 'Open':
            if self.alias is not None:
                return self.books[self.alias]   # the count does not move
            self.books.append(Sym('NEWBOOK'))
            self.names[Sym('NEWBOOK')] = FILE
            return Sym('NEWBOOK')
        return None

    def install(self):
        for name, fn in (('vlax-get-object', self.get_object),
                         ('vlax-create-object', self.create_object),
                         ('vlax-put-property', self.put_property),
                         ('vlax-get-property', self.get_property),
                         ('vlax-invoke-method', self.invoke_method),
                         ('vlax-release-object', lambda vm, a: None),
                         ('vlax-variant-value', lambda vm, a: a[0])):
            lispvm.BUILTINS[Sym(name)] = fn


def run(path, form, xl):
    xl.install()
    vm = VM()
    vm.load(path)
    vm.loads('(setq t:*file* "%s")' % FILE.replace('\\', '\\\\'))
    rows = vm.loads(form)
    return rows, xl.calls


def names(calls, kind):
    return [c for c in calls if c[0] == kind]


for tool, path, form in READERS:
    print(f"\n{tool}: reading a sheet through Excel")

    # 1. Excel closed: start a private one, hide it, open, close, quit
    rows, calls = run(path, form, FakeExcel(running=False))
    check("with Excel closed it starts one instead of giving up",
          ('create',) in calls and rows, calls)
    check("...hides the Excel it started",
          ('put', 'XL', 'Visible') in [c[:3] for c in calls], calls)
    check("...and closes the book and quits the Excel it started",
          ('invoke', 'NEWBOOK', 'Close') in calls
          and ('invoke', 'XL', 'Quit') in calls, calls)

    # 2. the drafter has THIS sheet open: read it where it stands
    xl = FakeExcel(running=True, open_books=['C:\\Jobs\\Other.xlsx',
                                             FILE.upper()])
    rows, calls = run(path, form, xl)
    check("with the sheet already open it reads that workbook", rows, calls)
    check("...never opens a second copy",
          ('invoke', 'WBS', 'Open') not in calls, calls)
    check("...never closes the drafter's workbook",
          not [c for c in names(calls, 'invoke') if c[2] == 'Close'], calls)
    check("...never hides or silences the drafter's Excel",
          not names(calls, 'put'), calls)
    check("...and never quits it", ('invoke', 'XL', 'Quit') not in calls,
          calls)
    check("...and starts nothing", ('create',) not in calls, calls)

    # 3. Excel open, this sheet not: open ours, close ours, leave Excel
    xl = FakeExcel(running=True, open_books=['C:\\Jobs\\Other.xlsx'])
    rows, calls = run(path, form, xl)
    check("with Excel open on another book it opens the sheet", rows
          and ('invoke', 'WBS', 'Open') in calls, calls)
    check("...closes only the book it opened",
          [c for c in names(calls, 'invoke') if c[2] == 'Close']
          == [('invoke', 'NEWBOOK', 'Close')], calls)
    check("...leaves the drafter's Excel visible and running",
          not names(calls, 'put')
          and ('invoke', 'XL', 'Quit') not in calls, calls)

    # 4. the sheet IS open, under another spelling of its path (a
    #    mapped drive against its UNC name): the name check misses it
    #    and Open hands the drafter's own book back -- which must not
    #    then be closed as if it were ours
    xl = FakeExcel(running=True,
                   open_books=['\\\\server\\jobs\\Smith\\tape.xlsx'],
                   alias=0)
    rows, calls = run(path, form, xl)
    check("a book Open hands back already open is read", rows, calls)
    check("...and never closed",
          not [c for c in names(calls, 'invoke') if c[2] == 'Close'], calls)

if FAILS:
    print(f"\n{len(FAILS)} FAILED")
    sys.exit(1)
print("\nall Excel reader checks passed")
