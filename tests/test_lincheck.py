"""Drive the real LINCHECK checklist end-to-end in the AutoLISP VM.

Covers the full run, the does-not-need-a-drawing gate, the Back step
(B/U at typed prompts, Back/Undo at keyword prompts) with its report
rollback, branch re-routing after a Back, and the cross-dim entry
loop's remove-last behaviour.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'lincheck', 'lincheck.lsp')


def run(script, label):
    vm = VM()
    vm.load(LSP)
    try:
        vm.run('c:LINCHECK', script)
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def log(vm):
    v = vm.globals.get('*lin:log*'.lower())
    return [str(x) for x in (v or [])]


# A clean full run: every branch answered No, one cross dim.
FULL = [None, "Yes",                # read notes, needs a drawing
        None, "42",                 # wall ht check + value
        None, "AG",                 # GLP + bead
        None, None,                 # perimeter + orientation
        "A-C=24'6\"", None,         # one cross dim, blank to finish
        None, None,                 # corners + special mfgrs
        "No", "No", "No", "No",     # cove/ledge/depths/side view
        "No", None,                 # hopper radius + trowel
        "No",                       # fiberglass? (skips 2 items)
        "No",                       # vinyl? (skips 4 items)
        None]                       # titleblock


print("== full run, all branches No ==")
vm = run(list(FULL), 'full')
lines = log(vm)
assert "[x] Cross dimensions provided by customer:" in lines, lines
assert "    A-C=24'6\"" in lines, lines
assert "    Finished Wall Ht (single value, or \"Varies\"): 42" in lines
assert not [l for l in lines if "FGS" in l], lines
assert not [l for l in lines if "Attachment" in l], lines
print("   report has the cross dim, the wall height, and no branch items")

print("== gate: job needs no drawing ==")
vm = run([None, "No"], 'gate')
lines = log(vm)
assert ">> Job does NOT require a Tech drawing - stopping checklist." \
    in lines, lines
assert len([l for l in lines if l.startswith("[x]")]) == 2, lines
print("   checklist stops right after the gate")

print("== Back at a typed prompt rolls the report back ==")
# Answer the wall-ht check, then type "b" at the value prompt: the
# check is re-asked (now with a note) before the run continues.
script = [None, "Yes",
          None,                     # wall-ht check, first answer
          "b",                      # value prompt -> Back
          "note about walls",       # wall-ht check again, with a note
          "48"] + FULL[4:]          # value, then the rest as usual
vm = run(script, 'back-typed')
lines = log(vm)
walls = [l for l in lines if "Verify Finished Wall Ht" in l]
assert walls == ["[x] Verify Finished Wall Ht & Pool Depth"
                 " -- note about walls"], walls
assert "    Finished Wall Ht (single value, or \"Varies\"): 48" in lines
print("   one wall-ht line, carrying the second answer")

print("== Back at a keyword prompt, Undo as synonym ==")
# At "Safety Ledge?" type Undo: back to "Cove?", change it to Yes.
script = FULL[:12] + ["No", "Undo", "Yes", "No", "No", "No"] + FULL[16:]
vm = run(script, 'back-kw')
lines = log(vm)
cove = [l for l in lines if "Cove?" in l]
assert cove == ["[x] Does the shallow end have a Cove? -> Yes"], cove
print("   Undo re-asked the cove question; only the second answer kept")

print("== Back re-routes a branch ==")
# Fiberglass Yes, then Back at the FGS-note item, change to No: the
# two fiberglass items must vanish from the run and the report.
script = FULL[:18] + ["Yes", "b", "No"] + FULL[19:]
vm = run(script, 'reroute')
lines = log(vm)
fib = [l for l in lines if "Fiberglass?" in l]
assert fib == ["[x] Are steps / bench Fiberglass? -> No"], fib
assert not [l for l in lines if "FGS" in l], lines
print("   fiberglass answer flipped; its sub-items skipped")

print("== cross dims: B removes the last entry ==")
script = FULL[:8] + ["A-C=1", "B-D=2", "b", None] + FULL[10:]
vm = run(script, 'crossdim-undo')
lines = log(vm)
assert "    A-C=1" in lines and "    B-D=2" not in lines, lines
print("   B-D entry removed, A-C kept")

print("== cross dims: B with no entries backs out of the stage ==")
# Straight to the cross-dim prompt, B leaves it, orientation re-asked
# with a note, then continue.
script = FULL[:8] + ["b", "with a note", "A-C=3", None] + FULL[10:]
vm = run(script, 'crossdim-back')
lines = log(vm)
orient = [l for l in lines if "orientation" in l]
assert orient == ["[x] Verify orientation: Shallow end to the RIGHT"
                  " of page -- with a note"], orient
assert "    A-C=3" in lines, lines
print("   backed out to orientation, then re-entered the cross dims")

print("\nALL LINCHECK SCENARIOS PASSED")
