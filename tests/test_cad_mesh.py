# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the layered CAD mesh DXF exporter.

Runs without Blender: the classification and writer modules are pure
Python.  Usage:  python3 tests/test_cad_mesh.py
"""

import importlib.util
import os
import sys
import tempfile

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TESTS_DIR), "cad_mesh_dxf")
sys.path.insert(0, TESTS_DIR)


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ADDON_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mesh_layers = _load("mesh_layers")
dxf_writer = _load("dxf_writer")


def test_layer_precedence():
    cases = (
        (dict(), "WIRES"),
        (dict(seam=True), "BASELINE"),
        (dict(freestyle=True), "SLICE"),
        (dict(sharp=True), "PERIMETER"),
        (dict(seam=True, freestyle=True), "SLICE"),
        (dict(seam=True, sharp=True), "PERIMETER"),
        (dict(seam=True, freestyle=True, sharp=True), "PERIMETER"),
    )
    for kwargs, expected in cases:
        got = mesh_layers.layer_for_edge(**kwargs)
        assert got == expected, (
            "markings %r: expected %s, got %s" % (kwargs, expected, got))
    print("ok  edge marking -> layer precedence")


def test_material_grouping():
    cases = (
        ("Floor", "FLOOR"),
        ("concrete floor 02", "FLOOR"),
        ("WALL_paint", "WALL"),
        ("Steps", "STEPS"),
        ("step.001", "STEPS"),
        ("floor+wall", "FLOOR"),       # first keyword in order wins
        ("Glass Railing", "GLASS_RAILING"),
        (None, "UNGROUPED"),
        ("", "UNGROUPED"),
    )
    for name, expected in cases:
        got = mesh_layers.group_for_material(name)
        assert got == expected, (
            "material %r: expected %s, got %s" % (name, expected, got))
    print("ok  material name -> group mapping")


def _sample_records():
    """Six edges spread over the three groups and four layers."""
    a, b, c, d = (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 1)
    return [
        (a, b, False, False, False, {"FLOOR"}),          # WIRES
        (b, c, True, False, False, {"FLOOR"}),           # BASELINE
        (c, d, False, True, False, {"WALL"}),            # SLICE
        (d, a, False, False, True, {"WALL"}),            # PERIMETER
        (a, c, False, False, True, {"STEPS"}),           # PERIMETER
        (b, d, True, False, False, {"FLOOR", "WALL"}),   # shared edge
    ]


def test_collect_segments():
    grouped = mesh_layers.collect_segments(_sample_records())
    assert list(grouped) == ["FLOOR", "WALL", "STEPS"], (
        "unexpected group order: %r" % list(grouped))

    floor = grouped["FLOOR"]
    wall = grouped["WALL"]
    # The shared floor/wall edge must land in both groups.
    assert len(floor["BASELINE"]) == 2, floor
    assert len(wall["BASELINE"]) == 1, wall
    assert len(floor["WIRES"]) == 1
    assert len(wall["SLICE"]) == 1
    assert len(wall["PERIMETER"]) == 1
    assert len(grouped["STEPS"]["PERIMETER"]) == 1

    # Layers inside a group follow the precedence order.
    assert list(wall) == ["PERIMETER", "SLICE", "BASELINE"], list(wall)

    # Records without a group fall back to UNGROUPED, sorted last.
    grouped = mesh_layers.collect_segments(
        _sample_records()
        + [((5, 5, 5), (6, 6, 6), False, False, False, set()),
           ((5, 5, 5), (6, 6, 5), False, False, False, {"GLASS"})])
    assert list(grouped) == ["FLOOR", "WALL", "STEPS", "GLASS", "UNGROUPED"]
    print("ok  segment collection, shared edges, group ordering")


def test_dxf_blocks_output():
    grouped = mesh_layers.collect_segments(_sample_records())
    path = os.path.join(tempfile.gettempdir(), "cad_mesh_test.dxf")
    dxf_writer.write_dxf(path, layers=mesh_layers.LAYERS,
                         groups=list(grouped.items()), use_blocks=True)

    with open(path, "r", encoding="ascii", newline="") as f:
        content = f.read()
    assert content.count("\r\nBLOCK\r\n") == 3
    assert content.count("\r\nENDBLK\r\n") == 3
    assert content.count("\r\nINSERT\r\n") == 3
    # 6 records, one duplicated into two groups -> 7 lines.
    assert content.count("\r\nLINE\r\n") == 7
    for layer_name, _color in mesh_layers.LAYERS:
        assert "\r\n%s\r\n" % layer_name in content, (
            "layer %s missing from output" % layer_name)
    assert content.rstrip().endswith("EOF")
    assert "AC1009" in content

    try:
        import ezdxf
    except ImportError:
        print("ok  block DXF written (ezdxf not installed, "
              "structural check only)")
        return
    doc = ezdxf.readfile(path)
    inserts = [e for e in doc.modelspace() if e.dxftype() == 'INSERT']
    assert sorted(i.dxf.name for i in inserts) == ["FLOOR", "STEPS", "WALL"]
    for block_name, expected_lines in (("FLOOR", 3), ("WALL", 3),
                                       ("STEPS", 1)):
        block = doc.blocks.get(block_name)
        lines = [e for e in block if e.dxftype() == 'LINE']
        assert len(lines) == expected_lines, (
            "block %s: expected %d lines, got %d"
            % (block_name, expected_lines, len(lines)))
    assert {"WIRES", "BASELINE", "SLICE", "PERIMETER"} <= {
        layer.dxf.name for layer in doc.layers}
    auditor = doc.audit()
    assert not auditor.has_errors, auditor.errors
    print("ok  block DXF written and validated with ezdxf (no audit errors)")


def test_dxf_flat_output():
    grouped = mesh_layers.collect_segments(_sample_records())
    path = os.path.join(tempfile.gettempdir(), "cad_mesh_flat_test.dxf")
    dxf_writer.write_dxf(path, layers=mesh_layers.LAYERS,
                         groups=list(grouped.items()), use_blocks=False)

    with open(path, "r", encoding="ascii", newline="") as f:
        content = f.read()
    assert content.count("\r\nBLOCK\r\n") == 0
    assert content.count("\r\nINSERT\r\n") == 0
    assert content.count("\r\nLINE\r\n") == 7
    # 3D coordinates must survive: vertex d is at z == 1.
    assert "\r\n1.000000" in content
    print("ok  flat (no blocks) DXF output")


def main():
    test_layer_precedence()
    test_material_grouping()
    test_collect_segments()
    test_dxf_blocks_output()
    test_dxf_flat_output()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
