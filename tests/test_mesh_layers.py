# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the Merlin layered CAD mesh exporter classification.

Runs without Blender (mesh_layers.py is pure Python).
Usage:  python3 tests/test_mesh_layers.py
"""

import importlib.util
import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TESTS_DIR), "blender", "merlin_import_export")


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ADDON_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mesh_layers = _load("mesh_layers")


def test_layer_precedence():
    L = mesh_layers
    assert L.layer_for_edge() == L.LAYER_WIRE
    assert L.layer_for_edge(seam=True) == L.LAYER_BASELINE
    assert L.layer_for_edge(freestyle=True) == L.LAYER_SLICE
    assert L.layer_for_edge(sharp=True) == L.LAYER_PERIMETER
    # Sharp beats freestyle beats seam when several are marked.
    assert L.layer_for_edge(seam=True, freestyle=True) == L.LAYER_SLICE
    assert L.layer_for_edge(seam=True, freestyle=True,
                            sharp=True) == L.LAYER_PERIMETER
    print("ok  edge marking precedence sharp > freestyle > seam > none")


def test_group_for_material():
    L = mesh_layers
    assert L.group_for_material("Floor.001") == L.GROUP_FLOOR
    assert L.group_for_material("MyWall") == L.GROUP_WALL
    assert L.group_for_material("step_stone") == L.GROUP_STEPS
    assert L.group_for_material(None) == L.GROUP_UNGROUPED
    assert L.group_for_material("") == L.GROUP_UNGROUPED
    # First keyword in (floor, wall, step) order wins.
    assert L.group_for_material("floor wall") == L.GROUP_FLOOR
    # Unknown material keeps its own sanitized name (nothing dropped).
    assert L.group_for_material("Brick #2") == "BRICK__2"
    print("ok  material -> group keyword mapping and passthrough")


def test_sanitize_name():
    L = mesh_layers
    assert L.sanitize_name("floor slab!") == "FLOOR_SLAB_"
    assert L.sanitize_name("") == L.GROUP_UNGROUPED
    assert L.sanitize_name("x" * 40) == "X" * 31, "must clamp to 31 chars"
    print("ok  DXF-safe name sanitisation")


def test_collect_segments_ordering_and_sharing():
    L = mesh_layers
    a, b, c = (0, 0, 0), (1, 0, 0), (1, 1, 0)
    records = [
        # wall perimeter (sharp)
        (a, b, False, False, True, {L.GROUP_WALL}),
        # floor wire
        (b, c, False, False, False, {L.GROUP_FLOOR}),
        # edge shared between floor and wall, marked seam -> BASELINE in both
        (c, a, True, False, False, {L.GROUP_FLOOR, L.GROUP_WALL}),
        # a custom material group
        (a, c, False, True, False, {"BRICK"}),
        # face edge with no material
        (b, a, False, False, False, {L.GROUP_UNGROUPED}),
    ]
    grouped = L.collect_segments(records)

    # Known groups first (FLOOR, WALL, STEPS order), extras alpha, UNGROUPED last.
    assert list(grouped) == ["FLOOR", "WALL", "BRICK", "UNGROUPED"], list(grouped)

    # Shared seam edge appears in BOTH floor and wall on BASELINE.
    assert L.LAYER_BASELINE in grouped["FLOOR"]
    assert L.LAYER_BASELINE in grouped["WALL"]
    assert len(grouped["FLOOR"][L.LAYER_BASELINE]) == 1
    assert len(grouped["WALL"][L.LAYER_BASELINE]) == 1

    # Wall also has its sharp perimeter edge.
    assert grouped["WALL"][L.LAYER_PERIMETER] == [(a, b)]
    # Floor wire edge.
    assert grouped["FLOOR"][L.LAYER_WIRE] == [(b, c)]
    # Custom group slice edge.
    assert grouped["BRICK"][L.LAYER_SLICE] == [(a, c)]

    # Within a group, layers follow LAYERS precedence order (perimeter..wire).
    order = [name for name, _c in L.LAYERS]
    for by_layer in grouped.values():
        seen = [lyr for lyr in by_layer]
        assert seen == [lyr for lyr in order if lyr in by_layer], seen
    print("ok  segment grouping: shared edges duplicated, deterministic order")


def test_collect_segments_defaults_to_ungrouped():
    L = mesh_layers
    # An edge with an empty group set falls back to UNGROUPED.
    grouped = L.collect_segments([((0, 0, 0), (1, 0, 0),
                                   False, False, False, set())])
    assert list(grouped) == ["UNGROUPED"]
    assert grouped["UNGROUPED"][L.LAYER_WIRE] == [((0, 0, 0), (1, 0, 0))]
    print("ok  edges with no group fall back to UNGROUPED")


def main():
    test_layer_precedence()
    test_group_for_material()
    test_sanitize_name()
    test_collect_segments_ordering_and_sharing()
    test_collect_segments_defaults_to_ungrouped()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
