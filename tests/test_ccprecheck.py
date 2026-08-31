"""Drive the real CCPRECHECK flowchart walker end-to-end in the
AutoLISP VM: straight runs down several branches, plus Back-stress -
backing out of a sub-branch into the question that opened it, changing
an answer to re-route the walk, and the summary rollback that goes
with it.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), '..',
                   'lisp', 'ccprecheck', 'ccprecheck.lsp')


def run(script, label):
    vm = VM()
    vm.load(LSP)
    try:
        vm.run('c:CCPRECHECK', script)
    except LispError as e:
        raise AssertionError(f"[{label}] {e}") from None
    return vm


def log(vm):
    v = vm.globals.get('*chk:log*'.lower())
    return [str(x) for x in (v or [])]


print("== spa cover / thermolight, with a typed confirm value ==")
vm = run(["SpaCover", "ThermoLight", "52x52"], 'thermo')
lines = log(vm)
assert "CONFIRMED: Cover Size is for water's edge = 52x52" in lines, lines
assert "NOTE: No need to worry about spillways" in lines, lines
print("   confirm value recorded, thermolight notes logged")

print("== liner / pool, no steps ==")
vm = run(["Liner", "Pool", None, None, None, "No"], 'liner-pool')
lines = log(vm)
assert "CONFIRMED: Pool Corners" in lines, lines
assert "NOTE: No need to show any step info" in lines, lines
print("   three confirms and the no-steps note")

print("== spa cover / safety, not raised, joined wall ==")
vm = run(["SpaCover", "SafetyCover", "No", "No", "No", "Yes"], 'safety')
lines = log(vm)
assert "NOTE: No obstructions - do nothing" in lines, lines
assert "NOTE: Pad the wall" in lines, lines
print("   joined-wall branch reached")

print("== Back out of a sub-branch into its opening question ==")
# At "Liner for" type Back: the product question is re-asked, and the
# walk re-routes into Spa Cover; no Liner trace may remain.
vm = run(["Liner", "Back", "SpaCover", "ThermoLight", None], 'backout')
lines = log(vm)
assert "Product type -> SpaCover" in lines, lines
assert not [l for l in lines if "Liner" in l], lines
print("   product answer replaced; the Liner line dropped")

print("== deep obstruction Back re-routes the branch ==")
# ZeroToOverlap, secured No, then Back at the 36-inch question and
# change secured to Yes: the cable note appears, the 36-inch question
# vanishes from the walk.
vm = run(["PoolCover", "Freeform", None, "Yes",
          "ZeroToOverlap", "No", "Back", "Yes",
          "Concrete", "GreaterThan18in"], 'obstruction')
lines = log(vm)
sec = [l for l in lines if "secured to the obstruction" in l]
assert sec == ["Can the cover be secured to the obstruction? -> Yes"], sec
assert "NOTE: Most of the time Cable, unless stated otherwise" in lines
assert not [l for l in lines if "36" in l], lines
print("   secured flipped to Yes; 36-inch question gone")

print("== Back at a typed confirm re-asks the keyword before it ==")
# Steps Yes -> Fiberglass, then B at the step-face confirm, change the
# step type to VinylOver: no fiberglass trace may remain.
vm = run(["Liner", "Pool", None, None, None,
          "Yes", "Fiberglass", "b", "VinylOver", None, None], 'reroute')
lines = log(vm)
kind = [l for l in lines if "Step type" in l]
assert kind == ["Step type -> VinylOver"], kind
assert not [l for l in lines if "Fiberglass" in l or "step face" in l], lines
assert "CONFIRMED: Step Back Corners" in lines, lines
print("   step type flipped; fiberglass items dropped")

print("== Undo works as a synonym for Back ==")
vm = run(["SpaCover", "SafetyCover", "Yes", "Undo", "No",
          "No", "No", "No"], 'undo-syn')
lines = log(vm)
spill = [l for l in lines if l.startswith("Spillway?")]
assert spill == ["Spillway? -> No"], spill
assert not [l for l in lines if "Pad & dimension" in l], lines
print("   Undo re-asked the spillway question")

print("== a re-run offers last time's answers as defaults ==")
# Same VM, run twice: the second run Enters through both keyword
# questions and only retypes the confirm value (getstring prompts
# take no defaults).  The two summaries must come out identical.
vm = VM()
vm.load(LSP)
vm.run('c:CCPRECHECK', ["SpaCover", "ThermoLight", "52x52"])
first = log(vm)
vm.run('c:CCPRECHECK', [None, None, "52x52"])
assert log(vm) == first, (first, log(vm))
assert any(p.endswith(" <SpaCover>: ") for p, _ in vm.prompts), \
    [p for p, _ in vm.prompts]
print("   Enter repeated both keyword answers; summaries identical")

print("== the first run of a session stays fully explicit ==")
vm = VM()
vm.load(LSP)
try:
    vm.run('c:CCPRECHECK', [None])
    raise AssertionError("Enter was accepted on a first-run question")
except LispError:
    pass
print("   Enter rejected while no previous answer exists")

print("\nALL CCPRECHECK SCENARIOS PASSED")
