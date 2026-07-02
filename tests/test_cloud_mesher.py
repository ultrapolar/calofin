# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the DXF point-cloud mesher geometry pipeline.

Runs without Blender (cloud_mesh.py is pure Python and falls back to
its own Delaunay implementation).  Usage:  python3 tests/test_cloud_mesher.py
"""

import importlib.util
import os
import sys

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TESTS_DIR), "dxf_cloud_mesher")


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ADDON_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cloud_mesh = _load("cloud_mesh")

FOUR_INCHES = 0.1016


def triangle_area(points, tri):
    (ax, ay), (bx, by), (cx, cy) = (points[i][:2] for i in tri)
    return 0.5 * ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))


def test_flat_ngon_with_collinear_points():
    # 2x2 pad: 4 corners plus a midpoint on every edge, small z noise.
    points = [
        (0, 0, 0.00), (2, 0, 0.05), (2, 2, 0.02), (0, 2, 0.04),  # corners
        (1, 0, 0.01), (2, 1, 0.03), (1, 2, 0.00), (0, 1, 0.02),  # midpoints
    ]
    kind, data = cloud_mesh.plan_fill(points)
    assert kind == 'NGON', "flat outline should become one n-gon, got %r" % kind
    assert len(data) == 8, "all 8 boundary points must be used, got %d" % len(data)
    assert sorted(data) == list(range(8)), "every vertex must appear once"
    area = cloud_mesh.loop_area(points, data)
    assert abs(area - 4.0) < 1e-9, "boundary loop is misordered (area %.4f)" % area
    print("ok  single n-gon, collinear edge points kept in order, no triangulation")


def test_interior_point_forces_triangulation():
    # Same square, but one point in the middle: an n-gon would overlap it.
    points = [(0, 0, 5.0), (2, 0, 5.0), (2, 2, 5.1), (0, 2, 5.0), (1, 1, 5.05)]
    kind, data = cloud_mesh.plan_fill(points)
    assert kind == 'TRIANGLES', "interior vertex must force triangulation"
    assert len(data) == 4, "square + centre should give 4 triangles, got %d" % len(data)
    used = {i for tri in data for i in tri}
    assert used == {0, 1, 2, 3, 4}, "every vertex must be part of the surface"
    for tri in data:
        assert 4 in tri, "centre point should appear in every fan triangle"
        assert triangle_area(points, tri) > 0.0, "triangle not CCW: %r" % (tri,)
    total = sum(triangle_area(points, tri) for tri in data)
    assert abs(total - 4.0) < 1e-9, "triangles must cover the hull (area %.4f)" % total
    print("ok  interior point triggers Delaunay fan covering the hull")


def test_concave_outline_triangulates():
    # L-shape outline: the reflex corner lies inside the convex hull, so
    # a single hull n-gon would overlap it -> triangulation.
    points = [(0, 0, 0), (2, 0, 0), (2, 1, 0), (1, 1, 0), (1, 2, 0), (0, 2, 0)]
    kind, data = cloud_mesh.plan_fill(points)
    assert kind == 'TRIANGLES'
    used = {i for tri in data for i in tri}
    assert 3 in used, "reflex corner must be part of the triangulation"
    total = sum(triangle_area(points, tri) for tri in data)
    assert abs(total - 3.5) < 1e-9, "expected hull coverage 3.5, got %.4f" % total
    print("ok  concave/reflex points handled via triangulation")


def test_duplicates_do_not_force_triangulation():
    points = [(0, 0, 0), (2, 0, 0), (2, 2, 0), (0, 2, 0), (2, 0, 0)]  # dup corner
    kind, data = cloud_mesh.plan_fill(points)
    assert kind == 'NGON', "a duplicated corner is not an interior point"
    assert len(data) == 4
    print("ok  duplicate points merged, n-gon still preferred")


def test_degenerate_inputs():
    assert cloud_mesh.plan_fill([(0, 0, 0), (1, 0, 0)])[0] is None
    assert cloud_mesh.plan_fill(
        [(i, i, 0) for i in range(5)])[0] is None, "collinear cloud must be rejected"
    assert cloud_mesh.plan_fill([(1, 1, 0)] * 4)[0] is None
    print("ok  degenerate clouds rejected with a reason")


def test_classification():
    z_bounds = {
        "pad":    (10.00, 10.05),  # flat -> fill
        "ground": (0.00, 2.00),    # varies 2 m but lowest -> fill
        "wall":   (5.00, 8.00),    # varies 3 m, not lowest -> skip
    }
    decisions = cloud_mesh.classify_objects(z_bounds, FOUR_INCHES)
    assert decisions["pad"][0] is True
    assert decisions["ground"][0] is True, "lowest object must be fillable"
    assert decisions["wall"][0] is False
    assert "lowest" in decisions["ground"][1]

    decisions = cloud_mesh.classify_objects(z_bounds, FOUR_INCHES,
                                            fill_lowest=False)
    assert decisions["ground"][0] is False, "fill_lowest=False must disable it"

    # Exactly at the limit counts as within tolerance.
    decisions = cloud_mesh.classify_objects({"edge": (0.0, FOUR_INCHES)},
                                            FOUR_INCHES)
    assert decisions["edge"][0] is True
    print("ok  height-tolerance and lowest-object (ground) classification")


def test_larger_tin():
    # A 5x5 grid of points with bumpy z: boundary + 9 interior points.
    points = []
    for gy in range(5):
        for gx in range(5):
            points.append((float(gx), float(gy), 0.1 * ((gx * gy) % 3)))
    kind, data = cloud_mesh.plan_fill(points)
    assert kind == 'TRIANGLES'
    # Euler: 2n - h - 2 triangles for n points with h on the hull.
    n, h = 25, 16
    assert len(data) == 2 * n - h - 2, (
        "expected %d triangles, got %d" % (2 * n - h - 2, len(data)))
    used = {i for tri in data for i in tri}
    assert used == set(range(25)), "every grid point must be used"
    total = sum(triangle_area(points, tri) for tri in data)
    assert abs(total - 16.0) < 1e-9
    for tri in data:
        assert triangle_area(points, tri) > 0.0, "triangle not CCW"
    print("ok  25-point grid becomes a complete CCW TIN (%d triangles)" % len(data))


def main():
    test_flat_ngon_with_collinear_points()
    test_interior_point_forces_triangulation()
    test_concave_outline_triangulates()
    test_duplicates_do_not_force_triangulation()
    test_degenerate_inputs()
    test_classification()
    test_larger_tin()
    print("\nall tests passed")


if __name__ == "__main__":
    main()
