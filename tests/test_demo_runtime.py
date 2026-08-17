"""Runtime smoke tests for the two companion files that ship beside
POOL.LSP: POOLDEMO.LSP (install-check reference sheet) and
TUTORIALPOOL.LSP (guided walkthrough).  Neither has geometry logic of
its own to mirror in Python -- they only call into POOL.LSP's already-
verified helpers with hardcoded numbers -- so the real AutoLISP VM is
the whole net here: does the real c:* entrypoint actually run, does
its "is POOL.LSP loaded?" guard actually work, and do sysvars come
back the way c:POOL's own error handling promises?
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lispvm import VM, LispError  # noqa: E402

HERE = os.path.dirname(__file__)
POOL_LSP = os.path.join(HERE, '..', 'pool_layout_lisp', 'POOL.LSP')
DEMO_LSP = os.path.join(HERE, '..', 'pool_layout_lisp', 'POOLDEMO.LSP')
TUTORIAL_LSP = os.path.join(HERE, '..', 'pool_layout_lisp', 'TUTORIALPOOL.LSP')


def drawn_count(vm):
    return len([e for e in vm.entities if e not in vm.deleted])


print("== D1. c:POOLDEMO runs for real (the atoms-family guard passes) ==")
vm = VM()
vm.load(POOL_LSP)
vm.load(DEMO_LSP)
try:
    vm.run('c:POOLDEMO', [])
except LispError as e:
    raise AssertionError(f"c:POOLDEMO failed: {e}") from None
assert drawn_count(vm) > 200, drawn_count(vm)
assert any('POOLDEMO complete' in s for s in vm.output), vm.output
assert not any('is not loaded' in s for s in vm.output), vm.output
print(f"   {drawn_count(vm)} entities across all 12 cells")

print("== D2. c:POOLDEMO's install-check guard fires when POOL.LSP is absent ==")
vm = VM()
vm.load(DEMO_LSP)   # POOLDEMO only -- POOL.LSP never loaded
vm.run('c:POOLDEMO', [])
assert drawn_count(vm) == 0
assert any('is not loaded' in s for s in vm.output), vm.output
print("   correctly refuses to run without POOL.LSP")

print("== D3. c:TUTORIALPOOL runs for real, all nine topics, sysvars restored ==")
vm = VM()
vm.load(POOL_LSP)
vm.load(TUTORIAL_LSP)
try:
    vm.run('c:TUTORIALPOOL', [""] * 8)   # Enter through all 8 pauses
except LispError as e:
    raise AssertionError(f"c:TUTORIALPOOL failed: {e}") from None
out = "\n".join(vm.output)
for heading in ["1. WELCOME", "2. THE GUIDED INPUT",
                "3. IN-SQUARE vs OUT-OF-SQUARE", "4. CORNER TREATMENTS",
                "5. THE POOL BOTTOM (HOPPER)", "6. VALIDATION",
                "7. DIMENSION STYLES", "8. THE REPORT TABLE",
                "9. THAT'S THE TOUR"]:
    assert heading in out, f"missing topic heading: {heading}"
assert drawn_count(vm) > 30, drawn_count(vm)
# sysvars come back to what they were before the command ran
assert vm.sysvars['OSMODE'] == 4133, vm.sysvars['OSMODE']
assert vm.sysvars['CMDECHO'] == 1, vm.sysvars['CMDECHO']
assert vm.sysvars['LUNITS'] == 2, vm.sysvars['LUNITS']
print(f"   {drawn_count(vm)} entities across 9 topics; sysvars restored")

print("== D4. checklist topic (6) actually lists what the routine checks ==")
for phrase in ["floored positive", "held true over its CORNER letter",
               "can never overlap and fold a wall",
               "D must beat C",
               "checked and flagged if it does not close",
               "W can't exceed G", "held like a WALL",
               "stays exactly parallel", "Back works from anywhere"]:
    assert phrase in out, f"checklist missing: {phrase!r}"
print("   every safety-check bullet made it into the printed checklist")

print("== D5. Q quits early -- later topics and sysvar restore still run ==")
vm = VM()
vm.load(POOL_LSP)
vm.load(TUTORIAL_LSP)
vm.run('c:TUTORIALPOOL', ["", "", "Q"])   # stop after topic 3
out = "\n".join(vm.output)
assert "3. IN-SQUARE vs OUT-OF-SQUARE" in out
assert "4. CORNER TREATMENTS" not in out
assert "9. THAT'S THE TOUR" not in out
assert vm.sysvars['OSMODE'] == 4133, "quitting early must still restore sysvars"
print("   early quit stops the tour but still cleans up")

print("== D6. TUTORIALPOOL's install-check guard fires when POOL.LSP is absent ==")
vm = VM()
vm.load(TUTORIAL_LSP)   # TUTORIALPOOL only -- POOL.LSP never loaded
vm.run('c:TUTORIALPOOL', [])
assert drawn_count(vm) == 0
assert any('is not loaded' in s for s in vm.output), vm.output
print("   correctly refuses to run without POOL.LSP")

print("== D7. POOLVERSION prints the loaded version on demand, and only then ==")
vm = VM()
vm.load(POOL_LSP)
assert not any('REV' in s for s in vm.output), \
    "loading POOL.LSP must not print a version banner unsolicited"
vm.run('c:POOLVERSION', [])
assert any('REV' in s for s in vm.output), vm.output
print("   silent at load, on-demand via POOLVERSION")

print("\nALL DEMO/TUTORIAL RUNTIME SCENARIOS PASSED")
