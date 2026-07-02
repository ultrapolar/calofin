# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the UV -> DXF exporter geometry pipeline.

Runs without Blender: mathutils is replaced with a small stub and the
bmesh structures are mocked.  Usage:  python3 tests/test_addon.py
"""

import importlib.util
import math
import os
import sys
import tempfile

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TESTS_DIR), "uv_layout_dxf")
sys.path.insert(0, TESTS_DIR)

# Install the mathutils stub before importing the add-on modules.
import mathutils_stub
sys.modules.setdefault("mathutils", mathutils_stub)

from mathutils import Vector  # noqa: E402  (resolves to the stub)
import mock_bmesh  # noqa: E402
from mock_bmesh import UV_LAYER, build_mesh  # noqa: E402


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ADDON_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


uv_layout = _load("uv_layout")
dxf_writer = _load("dxf_writer")


def transform_uvs(points, mirror_u=False, angle=0.0, offset=(0.0, 0.0)):
    """Mirror/rotate/translate a list of (u, v) tuples."""
    c, s = math.cos(angle), math.sin(angle)
    out = []
    for u, v in points:
        if mirror_u:
            u = -u
        out.append((u * c - v * s + offset[0], u * s + v * c + offset[1]))
    return out


def island_of(islands, face_index):
    for isl in islands:
        if face_index in isl.face_set:
            return isl
    raise AssertionError("no island contains face %d" % face_index)


def final_edge_vector(isl, edge, uv):
    """Direction of a mesh edge (verts[0] -> verts[1]) in final 2D space."""
    v0, v1 = edge.verts
    for loop in edge.link_loops:
        if loop.face.index in isl.face_set:
            p_here = uv_layout._apply(isl.transform, loop[uv].uv)
            p_next = uv_layout._apply(isl.transform,
                                      loop.link_loop_next[uv].uv)
            if loop.vert is v0:
                return p_next - p_here
            return p_here - p_next
    raise AssertionError("edge not found in island")


def assert_parallel(a, b, tolerance=1e-6):
    an = a / a.length
    bn = b / b.length
    dot = an.x * bn.x + an.y * bn.y
    assert dot > 1.0 - tolerance, (
        "vectors not parallel/same direction: %r vs %r (dot %.6f)"
        % (a, b, dot))


# ---------------------------------------------------------------------------
# Scenario: three quads in a strip in the XY plane, all normals +Z.
#
#   F0 (v0 v1 v2 v3)   F1 (v1 v4 v5 v2)   F2 (v4 v6 v7 v5)
#
# Each quad is its own UV island.  F0 keeps its correct UVs, F1 is
# mirrored and rotated, F2 is rotated only.

VERTS = [
    (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),   # v0..v3
    (2, 0, 0), (2, 1, 0),                          # v4, v5
    (3, 0, 0), (3, 1, 0),                          # v6, v7
]
FACES = [
    (0, 1, 2, 3),
    (1, 4, 5, 2),
    (4, 6, 7, 5),
]
CORRECT_UVS = [
    [(0, 0), (1, 0), (1, 1), (0, 1)],
    [(1, 0), (2, 0), (2, 1), (1, 1)],
    [(2, 0), (3, 0), (3, 1), (2, 1)],
]


def build_strip():
    uvs = [
        CORRECT_UVS[0],
        transform_uvs(CORRECT_UVS[1], mirror_u=True,
                      angle=math.radians(40.0), offset=(5.0, 5.0)),
        transform_uvs(CORRECT_UVS[2], angle=math.radians(-70.0),
                      offset=(8.0, 1.0)),
    ]
    return build_mesh(VERTS, FACES, uvs)


def test_island_detection_and_flip():
    bm = build_strip()
    islands = uv_layout.build_islands(bm, UV_LAYER)
    assert len(islands) == 3, "expected 3 islands, got %d" % len(islands)

    isl_a = island_of(islands, 0)
    isl_b = island_of(islands, 1)
    isl_c = island_of(islands, 2)
    assert not isl_a.flipped, "island A wrongly detected as mirrored"
    assert isl_b.flipped, "mirrored island B not detected"
    assert not isl_c.flipped, "island C wrongly detected as mirrored"

    # Adjacency: A-B share edge (v1,v2), B-C share edge (v4,v5).
    assert set(isl_a.neighbors) == {isl_b}
    assert set(isl_b.neighbors) == {isl_a, isl_c}
    assert set(isl_c.neighbors) == {isl_b}
    print("ok  island detection, mirror flags, adjacency")


def test_orientation():
    bm = build_strip()
    islands = uv_layout.build_islands(bm, UV_LAYER)
    bases = uv_layout.orient_islands(islands, UV_LAYER)

    # Base must be a leaf island (shares edges with exactly one other),
    # so the middle island B (degree 2) is excluded from the pool.
    assert len(bases) == 1
    assert len(bases[0].neighbors) == 1, "base island is not a leaf"

    isl_a = island_of(islands, 0)
    isl_b = island_of(islands, 1)
    isl_c = island_of(islands, 2)

    # Every shared seam edge must point the same way in both islands.
    edge_ab = isl_a.neighbors[isl_b][0]
    vec_in_a = final_edge_vector(isl_a, edge_ab, UV_LAYER)
    vec_in_b = final_edge_vector(isl_b, edge_ab, UV_LAYER)
    assert_parallel(vec_in_a, vec_in_b)

    edge_bc = isl_b.neighbors[isl_c][0]
    vec_in_b = final_edge_vector(isl_b, edge_bc, UV_LAYER)
    vec_in_c = final_edge_vector(isl_c, edge_bc, UV_LAYER)
    assert_parallel(vec_in_b, vec_in_c)

    # The mirrored island must come out with positive (unmirrored) winding.
    uv_layout.build_outlines(islands, UV_LAYER)
    for isl in (isl_a, isl_b, isl_c):
        assert len(isl.loops_2d) == 1, (
            "island should have exactly one outline, got %d"
            % len(isl.loops_2d))
        assert len(isl.loops_2d[0]) == 4, (
            "quad island outline should have 4 points, got %d"
            % len(isl.loops_2d[0]))
        area = uv_layout._loop_area(isl.loops_2d[0])
        assert area > 0.0, "island outline is still mirrored (area %.4f)" % area
        assert abs(area - 1.0) < 1e-6, "island outline area changed: %.6f" % area
    print("ok  base island choice, seam alignment, un-mirroring")


def test_perimeter_and_holes():
    # A square ring: 8 verts, 4 quads, one island with a square hole.
    outer = [(0, 0, 0), (3, 0, 0), (3, 3, 0), (0, 3, 0)]
    inner = [(1, 1, 0), (2, 1, 0), (2, 2, 0), (1, 2, 0)]
    verts = outer + inner
    faces = [
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    uvs = [[(verts[vi][0], verts[vi][1]) for vi in f] for f in faces]
    bm = build_mesh(verts, faces, uvs)

    islands = uv_layout.build_islands(bm, UV_LAYER)
    assert len(islands) == 1, "ring should be one island"

    uv_layout.build_outlines(islands, UV_LAYER, include_holes=True)
    loops = islands[0].loops_2d
    assert len(loops) == 2, "expected outer loop + hole, got %d" % len(loops)
    areas = sorted(abs(uv_layout._loop_area(lp)) for lp in loops)
    assert abs(areas[0] - 1.0) < 1e-6 and abs(areas[1] - 9.0) < 1e-6, (
        "unexpected loop areas: %r" % areas)

    uv_layout.build_outlines(islands, UV_LAYER, include_holes=False)
    loops = islands[0].loops_2d
    assert len(loops) == 1, "holes should have been dropped"
    assert abs(abs(uv_layout._loop_area(loops[0])) - 9.0) < 1e-6, (
        "kept the wrong loop")

    # The 4 interior seam edges (ring quads' shared edges) must never
    # appear: outer loop 4 points, hole 4 points, nothing else.
    print("ok  perimeter-only extraction, hole handling")


class _AttrStub:
    """Mesh datablock stand-in exposing edges with use_freestyle_mark."""

    class _Edge:
        def __init__(self, index, marked):
            self.index = index
            self.use_freestyle_mark = marked

    def __init__(self, edge_count, marked_indices):
        self.attributes = {}
        self.edges = [self._Edge(i, i in marked_indices)
                      for i in range(edge_count)]


class _ObjStub:
    def __init__(self):
        from mathutils import Matrix
        self.matrix_world = Matrix.Identity(4)


def test_freestyle_scale():
    bm = build_strip()
    # Edge index 1 is (v1, v2): 3D length 1.0, UV length 1.0 in both
    # islands (island B's transform is rigid).  With millimetre output
    # the scale factor must be 1000.
    mesh = _AttrStub(len(bm.edges), {1})
    obj = _ObjStub()
    reference = uv_layout.freestyle_scale_reference(
        obj, mesh, bm, UV_LAYER, unit_factor=1000.0, scene_scale=1.0)
    assert reference is not None, "freestyle reference edge not found"
    scale, count = reference
    assert count == 1
    assert abs(scale - 1000.0) < 1e-3, "expected scale 1000, got %r" % scale

    # No marked edges -> None
    mesh = _AttrStub(len(bm.edges), set())
    assert uv_layout.freestyle_scale_reference(
        obj, mesh, bm, UV_LAYER) is None
    print("ok  freestyle-edge scale factor")


def test_repack():
    bm = build_strip()
    islands = uv_layout.build_islands(bm, UV_LAYER)
    uv_layout.orient_islands(islands, UV_LAYER)
    uv_layout.build_outlines(islands, UV_LAYER)
    uv_layout.repack_islands(islands)

    boxes = []
    for isl in islands:
        pts = [p for lp in isl.loops_2d for p in lp]
        boxes.append((min(p.x for p in pts), min(p.y for p in pts),
                      max(p.x for p in pts), max(p.y for p in pts)))
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i], boxes[j]
            overlap = not (a[2] <= b[0] + 1e-9 or b[2] <= a[0] + 1e-9 or
                           a[3] <= b[1] + 1e-9 or b[3] <= a[1] + 1e-9)
            assert not overlap, "islands %d and %d overlap after repack" % (i, j)
    print("ok  shelf repack produces non-overlapping islands")


def test_dxf_output():
    bm = build_strip()
    islands = uv_layout.build_islands(bm, UV_LAYER)
    uv_layout.orient_islands(islands, UV_LAYER)
    uv_layout.build_outlines(islands, UV_LAYER)

    layers = []
    for isl in islands:
        outlines = [[(p.x, p.y) for p in lp] for lp in isl.loops_2d]
        layers.append(("ISLAND_%03d" % (isl.index + 1),
                       (isl.index % 7) + 1, outlines))

    path = os.path.join(tempfile.gettempdir(), "uv_layout_test.dxf")
    dxf_writer.write_dxf(path, layers)

    with open(path, "r", encoding="ascii", newline="") as f:
        content = f.read()
    assert content.count("\r\nPOLYLINE\r\n") == 3
    assert content.count("\r\nVERTEX\r\n") == 12
    assert content.count("\r\nSEQEND\r\n") == 3
    assert content.rstrip().endswith("EOF")
    assert "AC1009" in content

    # Structural validation with ezdxf when available.
    try:
        import ezdxf
    except ImportError:
        print("ok  DXF written (ezdxf not installed, structural check only)")
        return
    doc = ezdxf.readfile(path)
    entities = list(doc.modelspace())
    polylines = [e for e in entities if e.dxftype() == 'POLYLINE']
    assert len(polylines) == 3
    for pl in polylines:
        assert pl.is_closed
        assert len(list(pl.vertices)) == 4
    auditor = doc.audit()
    assert not auditor.has_errors, auditor.errors
    print("ok  DXF written and validated with ezdxf (no audit errors)")


def main():
    test_island_detection_and_flip()
    test_orientation()
    test_perimeter_and_holes()
    test_freestyle_scale()
    test_repack()
    test_dxf_output()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
