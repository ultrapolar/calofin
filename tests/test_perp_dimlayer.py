#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""PERPPTS and CPERPPTS put their dimensions on the shop's DIMENSION layer.

Both used to make and draw on a layer called "DIMENSIONS" -- one letter
away from the "DIMENSION" every other drawing tool in the tree uses, so
a drawing that had been through PERPPTS carried two dimension layers
and a layer filter or a plot style keyed on one missed the other.  The
owner's decision: the layer is a tunable, perp:*dimlayer* /
cperp:*dimlayer*, shipped as "DIMENSION" like the family it joins
(hn:*dimlayer*, sf:*dimlayer*, oasis:*dimlayer* ...).

What is asserted, for each routine, by RUNNING it in the VM:

  * the knob ships as "DIMENSION";
  * every dimension is drawn with CLAYER on DIMENSION, and that layer
    is the one the run made;
  * no layer called DIMENSIONS is made at all;
  * setting the knob before a run moves the dimensions to the layer it
    names -- the knob is read, not merely declared.

Run: python3 tests/test_perp_dimlayer.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lispvm import VM, Ent, Dot, Sym, BUILTINS  # noqa: E402
import test_perp_points as tpp  # noqa: E402

REPO = os.path.dirname(HERE)
PATHS = {
    'perp': os.path.join(REPO, 'lisp', 'perp_points', 'perp_points.lsp'),
    'cperp': os.path.join(REPO, 'lisp', 'perp_points', 'cperp_points.lsp'),
}
CMDS = {'perp': 'c:PERPPTS', 'cperp': 'c:CPERPPTS'}

#: the direction click, three points, three lengths, Enter at the width
#: question (Unchanged), No to another round, and the dimension style
SCRIPTS = {
    'perp': [tpp.CLICK, 3, 10.0, 12.0, 10.0, "Straight", tpp.WIDTH_OK,
             "No", "STandard"],
    'cperp': [tpp.CLICK, 3, 10.0, 12.0, 10.0, tpp.WIDTH_OK, "No",
              "STandard"],
}

failures = []


def check(label, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + label
          + (f"  -- {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(label)


def run(key, knob=None):
    """One run of the routine; KNOB, when given, is set before it.
    Returns the VM with vm.dim_layers: CLAYER at each DIMALIGNED."""
    tpp.install_entity_builtins()
    tpp.install_curve_builtins()
    tpp.install_intersect_builtins()
    vm = VM()
    tpp.install_command(vm)
    inner = BUILTINS[Sym('command')]
    vm.dim_layers = []

    def command(vm_, a):
        if a and a[0] == '._DIMALIGNED':
            vm_.dim_layers.append(vm_.sysvars.get('CLAYER'))
        return inner(vm_, a)

    BUILTINS[Sym('command')] = command
    vm.load(PATHS[key])
    if knob is not None:
        vm.loads('(setq %s:*dimlayer* "%s")' % (key, knob))
    if key == 'perp':
        src = Ent()
        vm.entities.append(src)
        vm.entdata[src] = [Dot(0, 'LINE'), Dot(8, 'WALLS'), Dot(62, 3),
                           [10, 0.0, 0.0, 0.0], [11, 100.0, 0.0, 0.0]]
    else:
        src = tpp.make_polyline(vm, [(0.0, 0.0), (100.0, 0.0)], None,
                                'WALLS', 3)
    vm.tables['LAYER'].add('WALLS')
    vm.tables['DIMSTYLE'].add('STANDARD INCHES')
    script = SCRIPTS[key]
    vm.run(CMDS[key], [src, script[0], None, None] + list(script[1:]))
    return vm


def layers(vm):
    return {n.upper() for n in vm.tables['LAYER']}


for key in ('perp', 'cperp'):
    name = CMDS[key][2:]
    print(f"{name} -- dimensions on the DIMENSION layer")
    vm = run(key)
    shipped = vm.get(Sym('%s:*dimlayer*' % key))
    check(f"{name}: {key}:*dimlayer* ships as \"DIMENSION\"",
          shipped == "DIMENSION", repr(shipped))
    check(f"{name}: it drew three dimensions", len(vm.dim_layers) == 3,
          vm.dim_layers)
    check(f"{name}: every one with CLAYER on DIMENSION",
          vm.dim_layers and all(la == "DIMENSION" for la in vm.dim_layers),
          vm.dim_layers)
    check(f"{name}: the DIMENSION layer was made",
          "DIMENSION" in layers(vm), sorted(layers(vm)))
    check(f"{name}: no DIMENSIONS layer was made",
          "DIMENSIONS" not in layers(vm), sorted(layers(vm)))
    check(f"{name}: CLAYER is the drafter's again after the run",
          vm.sysvars.get('CLAYER') != "DIMENSION", vm.sysvars.get('CLAYER'))

    print(f"{name} -- the knob moves them")
    vm = run(key, knob="SHOP-DIMS")
    check(f"{name}: with the knob set, every dimension is on SHOP-DIMS",
          len(vm.dim_layers) == 3
          and all(la == "SHOP-DIMS" for la in vm.dim_layers),
          vm.dim_layers)
    check(f"{name}: ...that layer was made, and DIMENSION was not",
          "SHOP-DIMS" in layers(vm) and "DIMENSION" not in layers(vm),
          sorted(layers(vm)))
    check(f"{name}: ...and the closing line names it",
          'dimensions on layer "SHOP-DIMS"' in "".join(vm.printed))

if failures:
    print(f"\n{len(failures)} DIMENSION-layer check(s) FAILED")
    sys.exit(1)
print("\nall DIMENSION-layer checks passed")
