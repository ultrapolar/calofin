# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the Merlin DXF reader and scene-planning helpers.

Runs without Blender (dxf_reader.py is pure Python).
Usage:  python3 tests/test_dxf_reader.py
"""

import importlib.util
import math
import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TESTS_DIR), "merlin_import_export")


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ADDON_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


dxf_reader = _load("dxf_reader")


def dxf(*tags):
    """Build ASCII DXF text: an ENTITIES section around the given tags."""
    rows = ["0", "SECTION", "2", "ENTITIES"]
    for code, value in tags:
        rows.append(str(code))
        rows.append(str(value))
    rows += ["0", "ENDSEC", "0", "EOF"]
    return "\n".join(rows) + "\n"


def point_tags(layer, x, y, z=0.0):
    return ((0, "POINT"), (8, layer), (10, x), (20, y), (30, z))


def test_points_split_by_layer():
    tags = (point_tags("GROUND", 0, 0)
            + point_tags("GROUND", 1, 0, 2)
            + point_tags("GROUND", 0, 1)
            + point_tags("PAD", 5, 5)
            + point_tags("PAD", 6, 5))
    layers, stats = dxf_reader.parse_dxf(dxf(*tags))
    assert sorted(layers) == ["GROUND", "PAD"], sorted(layers)
    assert len(layers["GROUND"].verts) == 3
    assert len(layers["PAD"].verts) == 2
    assert layers["GROUND"].verts[1] == (1.0, 0.0, 2.0)
    assert not layers["GROUND"].edges and not layers["GROUND"].faces
    assert stats["handled"]["POINT"] == 5
    print("ok  POINT entities split into per-layer vertex clouds")


def test_lines_share_endpoints():
    tags = ((0, "LINE"), (8, "WALLS"),
            (10, 0), (20, 0), (30, 0), (11, 1), (21, 0), (31, 0),
            (0, "LINE"), (8, "WALLS"),
            (10, 1), (20, 0), (30, 0), (11, 1), (21, 1), (31, 0))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags))
    walls = layers["WALLS"]
    assert len(walls.verts) == 3, "shared endpoint must be merged"
    assert len(walls.edges) == 2
    print("ok  LINE endpoints merged into connected geometry")


def test_lwpolyline_closed_square():
    tags = ((0, "LWPOLYLINE"), (8, "PLAN"), (90, 4), (70, 1), (38, 2.5),
            (10, 0), (20, 0), (10, 4), (20, 0), (10, 4), (20, 4),
            (10, 0), (20, 4))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags))
    plan = layers["PLAN"]
    assert len(plan.verts) == 4
    assert len(plan.edges) == 4, "closed polyline must close the loop"
    assert all(v[2] == 2.5 for v in plan.verts), "elevation must be applied"
    print("ok  closed LWPOLYLINE with elevation")


def test_lwpolyline_bulge_sampling():
    # Two vertices with bulge 1.0: a half circle from (0,0) to (2,0).
    tags = ((0, "LWPOLYLINE"), (8, "ARCS"), (90, 2),
            (10, 0), (20, 0), (42, 1.0), (10, 2), (20, 0))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags), arc_segments=32)
    arcs = layers["ARCS"]
    assert len(arcs.verts) > 2, "bulge must be sampled into segments"
    # Every sampled point must sit on the circle centred (1,0) radius 1.
    for x, y, _z in arcs.verts:
        r = math.hypot(x - 1.0, y)
        assert abs(r - 1.0) < 1e-9, "point off the bulge arc (r=%.6f)" % r
    # Positive bulge sweeps counter-clockwise: from (0,0) to (2,0) the
    # semicircle bows down through (1,-1).
    bottom = min(y for _x, y, _z in arcs.verts)
    assert abs(bottom + 1.0) < 0.02, "positive bulge must sweep CCW"
    print("ok  LWPOLYLINE bulge sampled onto the correct arc")


def test_polyline_3d_and_closed():
    tags = ((0, "POLYLINE"), (8, "TIN"), (66, 1), (70, 9),  # closed + 3D
            (0, "VERTEX"), (8, "TIN"), (10, 0), (20, 0), (30, 0),
            (0, "VERTEX"), (8, "TIN"), (10, 1), (20, 0), (30, 1),
            (0, "VERTEX"), (8, "TIN"), (10, 1), (20, 1), (30, 2),
            (0, "SEQEND"), (8, "TIN"))
    layers, stats = dxf_reader.parse_dxf(dxf(*tags))
    tin = layers["TIN"]
    assert len(tin.verts) == 3
    assert len(tin.edges) == 3, "closed flag must close the polyline"
    assert tin.verts[2] == (1.0, 1.0, 2.0)
    assert stats["handled"]["POLYLINE"] == 1
    print("ok  classic 3D POLYLINE/VERTEX/SEQEND")


def test_polyface_mesh_faces():
    tags = [(0, "POLYLINE"), (8, "ROOF"), (66, 1), (70, 64),
            (71, 4), (72, 1)]
    corners = [(0, 0, 0), (2, 0, 0), (2, 2, 1), (0, 2, 1)]
    for x, y, z in corners:
        tags += [(0, "VERTEX"), (8, "ROOF"), (70, 192),
                 (10, x), (20, y), (30, z)]
    tags += [(0, "VERTEX"), (8, "ROOF"), (70, 128),
             (10, 0), (20, 0), (30, 0),
             (71, 1), (72, 2), (73, 3), (74, -4)]  # negative: hidden edge
    tags += [(0, "SEQEND"), (8, "ROOF")]
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags))
    roof = layers["ROOF"]
    assert len(roof.verts) == 4
    assert len(roof.faces) == 1 and len(roof.faces[0]) == 4
    print("ok  polyface mesh becomes real faces")


def test_3dface_and_solid():
    tags = ((0, "3DFACE"), (8, "F"),
            (10, 0), (20, 0), (30, 0), (11, 1), (21, 0), (31, 0),
            (12, 1), (22, 1), (32, 0), (13, 1), (23, 1), (33, 0),  # tri (dup)
            # SOLID stores a unit square in zig-zag order: 3rd/4th swapped.
            (0, "SOLID"), (8, "S"),
            (10, 0), (20, 0), (30, 0), (11, 1), (21, 0), (31, 0),
            (12, 0), (22, 1), (32, 0), (13, 1), (23, 1), (33, 0))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags))
    assert len(layers["F"].faces) == 1 and len(layers["F"].faces[0]) == 3
    solid = layers["S"]
    assert len(solid.faces) == 1 and len(solid.faces[0]) == 4
    # The reader must un-zigzag the corners into a non-crossing quad.
    face_points = [solid.verts[i] for i in solid.faces[0]]
    assert abs(abs(_loop_area_xy(face_points)) - 1.0) < 1e-9, \
        "SOLID quad must not be self-crossing"
    print("ok  3DFACE triangle and SOLID corner un-zigzag")


def _loop_area_xy(points):
    area = 0.0
    for i in range(len(points)):
        x0, y0 = points[i][0], points[i][1]
        x1, y1 = points[(i + 1) % len(points)][0], points[(i + 1) % len(points)][1]
        area += x0 * y1 - x1 * y0
    return 0.5 * area


def test_circle_and_arc_sampling():
    tags = ((0, "CIRCLE"), (8, "C"), (10, 0), (20, 0), (30, 0), (40, 2),
            (0, "ARC"), (8, "A"), (10, 0), (20, 0), (30, 0), (40, 1),
            (50, 0), (51, 90))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags), arc_segments=16)
    circle = layers["C"]
    assert len(circle.verts) == 16
    assert len(circle.edges) == 16, "circle must be a closed loop"
    for x, y, _z in circle.verts:
        assert abs(math.hypot(x, y) - 2.0) < 1e-9
    arc = layers["A"]
    assert len(arc.edges) == len(arc.verts) - 1, "arc must stay open"
    xs = [v[0] for v in arc.verts]
    ys = [v[1] for v in arc.verts]
    assert abs(max(xs) - 1.0) < 1e-9 and abs(max(ys) - 1.0) < 1e-9
    assert min(xs) > -1e-9 and min(ys) > -1e-9, "arc must stay in quadrant I"
    print("ok  CIRCLE closed loop and ARC quarter sweep")


def test_spline_fit_points_and_unsupported_skipped():
    tags = ((0, "SPLINE"), (8, "SP"), (70, 0), (71, 3),
            (11, 0), (21, 0), (31, 0),
            (11, 1), (21, 1), (31, 0),
            (11, 2), (21, 0), (31, 0),
            (0, "TEXT"), (8, "NOTES"), (10, 0), (20, 0), (1, "hello"),
            (0, "MTEXT"), (8, "NOTES"), (10, 0), (20, 0), (1, "world"),
            (0, "TEXT"), (8, "NOTES"), (10, 1), (20, 1), (1, "again"))
    layers, stats = dxf_reader.parse_dxf(dxf(*tags))
    assert "NOTES" not in layers, "annotation-only layers must not appear"
    assert len(layers["SP"].verts) == 3
    assert len(layers["SP"].edges) == 2
    assert stats["skipped"] == {"TEXT": 2, "MTEXT": 1}
    print("ok  SPLINE fit points used; TEXT/MTEXT counted as skipped")


def test_spline_control_points_sampled():
    tags = ((0, "SPLINE"), (8, "SP"), (70, 0), (71, 2),
            (40, 0), (40, 0), (40, 0), (40, 1), (40, 1), (40, 1),
            (10, 0), (20, 0), (30, 0),
            (10, 1), (20, 2), (30, 0),
            (10, 2), (20, 0), (30, 0))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags), arc_segments=8)
    sp = layers["SP"]
    assert len(sp.verts) >= 8, "control-point spline must be sampled"
    first, last = sp.verts[0], sp.verts[-1]
    assert first == (0.0, 0.0, 0.0) and last == (2.0, 0.0, 0.0), \
        "clamped B-spline must hit its end control points"
    ys = [v[1] for v in sp.verts]
    assert 0.9 < max(ys) <= 1.0 + 1e-9, \
        "quadratic peak should be ~1.0, got %.4f" % max(ys)
    print("ok  SPLINE control points sampled with de Boor")


def test_geometry_outside_entities_ignored():
    text = ("0\nSECTION\n2\nBLOCKS\n"
            "0\nPOINT\n8\nBLK\n10\n9\n20\n9\n30\n0\n"
            "0\nENDSEC\n"
            + dxf(*point_tags("REAL", 1, 2, 3)))
    layers, _stats = dxf_reader.parse_dxf(text)
    assert "BLK" not in layers, "BLOCKS section must be ignored"
    assert list(layers) == ["REAL"]
    print("ok  only the ENTITIES section is imported")


def test_pick_parent_and_center_of_mass():
    tags = (point_tags("SMALL", 0, 0)
            + point_tags("BIG", 0, 0) + point_tags("BIG", 4, 0, 2)
            + point_tags("BIG", 2, 6, 4)
            + point_tags("ALSO3", 0, 0) + point_tags("ALSO3", 1, 0)
            + point_tags("ALSO3", 2, 0))
    layers, _stats = dxf_reader.parse_dxf(dxf(*tags))
    # BIG and ALSO3 tie on 3 points: first by name wins deterministically.
    parent = dxf_reader.pick_parent(layers)
    assert parent == "ALSO3", parent
    del layers["ALSO3"]
    assert dxf_reader.pick_parent(layers) == "BIG"
    com = dxf_reader.center_of_mass(layers["BIG"].verts)
    assert com == (2.0, 2.0, 2.0), com
    assert dxf_reader.center_of_mass([]) == (0.0, 0.0, 0.0)
    assert dxf_reader.pick_parent({}) is None
    print("ok  parent picking (most points) and centre of mass")


def test_windows_line_endings_and_case():
    text = dxf(*point_tags("mixed", 1, 1)).replace("\n", "\r\n")
    layers, _stats = dxf_reader.parse_dxf(text)
    assert list(layers) == ["mixed"]
    print("ok  CRLF files and lowercase layer names")


def main():
    test_points_split_by_layer()
    test_lines_share_endpoints()
    test_lwpolyline_closed_square()
    test_lwpolyline_bulge_sampling()
    test_polyline_3d_and_closed()
    test_polyface_mesh_faces()
    test_3dface_and_solid()
    test_circle_and_arc_sampling()
    test_spline_fit_points_and_unsupported_skipped()
    test_spline_control_points_sampled()
    test_geometry_outside_entities_ignored()
    test_pick_parent_and_center_of_mass()
    test_windows_line_endings_and_case()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
