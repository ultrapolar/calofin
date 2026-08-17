# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for the Mesh Dewrangler core logic.

Runs without Blender (refine.py is pure Python).
Usage:  python3 tests/test_dewrangler.py
"""

import importlib.util
import math
import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TESTS_DIR), "blender", "mesh_dewrangler")


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(ADDON_DIR, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


refine = _load("refine")


# ---------------------------------------------------------------------------
# derive_settings

def test_full_preservation_is_cleanup_only():
    s = refine.derive_settings(1.0)
    assert s["smooth_iterations"] == 0, "100% preservation must not smooth"
    assert s["collapse_ratio"] == 1.0, "100% preservation must not decimate"
    assert s["dissolve_angle"] == 0.0, "100% preservation must not dissolve"
    print("ok  preservation 100% leaves geometry untouched (cleanup only)")


def test_zero_preservation_hits_the_extremes():
    s = refine.derive_settings(0.0)
    assert s["smooth_iterations"] == refine.MAX_SMOOTH_ITERATIONS
    assert abs(s["collapse_ratio"] - 0.01) < 1e-12, \
        "0% preservation should keep ~1%% of triangles, got %r" \
        % s["collapse_ratio"]
    expected = math.radians(refine.MAX_DISSOLVE_ANGLE_DEG)
    assert abs(s["dissolve_angle"] - expected) < 1e-12
    print("ok  preservation 0% maps to the most aggressive settings")


def test_settings_monotonic_and_clamped():
    previous = None
    for step in range(11):
        p = step / 10.0
        s = refine.derive_settings(p)
        assert 0 <= s["smooth_iterations"] <= refine.MAX_SMOOTH_ITERATIONS
        assert refine.MIN_COLLAPSE_RATIO <= s["collapse_ratio"] <= 1.0
        if previous is not None:
            assert s["smooth_iterations"] <= previous["smooth_iterations"]
            assert s["collapse_ratio"] >= previous["collapse_ratio"]
            assert s["dissolve_angle"] <= previous["dissolve_angle"]
        previous = s
    # Out-of-range input is clamped, not propagated.
    assert refine.derive_settings(2.0) == refine.derive_settings(1.0)
    assert refine.derive_settings(-1.0) == refine.derive_settings(0.0)
    print("ok  every stage strengthens monotonically as preservation drops")


def test_halfway_preservation_is_one_order_of_magnitude():
    s = refine.derive_settings(0.5)
    assert abs(s["collapse_ratio"] - 0.1) < 1e-12, \
        "half slider should keep 10%% of triangles, got %r" \
        % s["collapse_ratio"]
    print("ok  collapse ratio decays exponentially (50% -> keep 10%)")


# ---------------------------------------------------------------------------
# auto_weld_distance

def test_auto_weld_distance_scales_with_the_mesh():
    small = refine.auto_weld_distance((0, 0, 0), (1, 1, 1))
    large = refine.auto_weld_distance((0, 0, 0), (100, 100, 100))
    assert abs(small - math.sqrt(3) * refine.WELD_FRACTION) < 1e-15
    assert abs(large - 100 * small) < 1e-12, \
        "weld distance must scale linearly with mesh size"
    assert refine.auto_weld_distance((5, 5, 5), (5, 5, 5)) == 0.0
    print("ok  weld distance is proportional to the bounding-box diagonal")


# ---------------------------------------------------------------------------
# taubin_smooth

def _grid(n, z):
    """(n+1)x(n+1) unit grid with per-vertex heights from z(i, j)."""
    positions = []
    for j in range(n + 1):
        for i in range(n + 1):
            positions.append((i / n, j / n, z(i, j)))
    neighbours = [[] for _ in positions]
    for j in range(n + 1):
        for i in range(n + 1):
            k = j * (n + 1) + i
            if i < n:
                neighbours[k].append(k + 1)
                neighbours[k + 1].append(k)
            if j < n:
                neighbours[k].append(k + n + 1)
                neighbours[k + n + 1].append(k)
    boundary = {j * (n + 1) + i
                for j in range(n + 1) for i in range(n + 1)
                if i in (0, n) or j in (0, n)}
    return positions, neighbours, boundary


def _roughness(positions, neighbours):
    total = 0.0
    for i, adjacent in enumerate(neighbours):
        for j in adjacent:
            if j > i:
                total += (positions[i][2] - positions[j][2]) ** 2
    return total


def test_smoothing_reduces_noise_and_respects_locks():
    # Deterministic high-frequency jitter on a 12x12 grid.
    noise = lambda i, j: 0.05 * math.sin(12.9898 * i + 78.233 * j)
    positions, neighbours, boundary = _grid(11, noise)
    smoothed = refine.taubin_smooth(positions, neighbours, 10,
                                    locked=boundary)
    assert len(smoothed) == len(positions)
    before = _roughness(positions, neighbours)
    after = _roughness(smoothed, neighbours)
    assert after < before * 0.5, \
        "10 passes must halve the roughness (%.4f -> %.4f)" % (before, after)
    for k in boundary:
        assert smoothed[k] == positions[k], "locked vertex %d moved" % k
    print("ok  Taubin smoothing denoises the interior, boundary stays put")


def test_smoothing_preserves_volume_better_than_laplacian():
    # A tent: interior raised, boundary at z=0.  Plain Laplacian
    # smoothing flattens it fast; Taubin must keep most of the height.
    tent = lambda i, j: 0.5 * min(i, j, 11 - i, 11 - j) / 5.0
    positions, neighbours, boundary = _grid(11, tent)
    taubin = refine.taubin_smooth(positions, neighbours, 10,
                                  locked=boundary)
    laplace = refine.taubin_smooth(positions, neighbours, 10,
                                   lam=0.5, mu=0.0, locked=boundary)
    peak = max(p[2] for p in positions)
    taubin_peak = max(p[2] for p in taubin)
    laplace_peak = max(p[2] for p in laplace)
    assert taubin_peak > laplace_peak, \
        "Taubin must shrink less than plain Laplacian"
    assert taubin_peak > 0.7 * peak, \
        "Taubin lost too much volume: %.3f of %.3f" % (taubin_peak, peak)
    print("ok  Taubin smoothing keeps the shape (%.0f%% of peak height, "
          "Laplacian only %.0f%%)"
          % (100 * taubin_peak / peak, 100 * laplace_peak / peak))


def test_smoothing_edge_cases():
    positions = [(0.0, 0.0, 0.0), (1.0, 0.0, 1.0)]
    neighbours = [[1], [0]]
    assert refine.taubin_smooth(positions, neighbours, 0) == positions, \
        "zero iterations must be a no-op"
    lonely = refine.taubin_smooth([(1.0, 2.0, 3.0)], [[]], 5)
    assert lonely == [(1.0, 2.0, 3.0)], "isolated vertices must not move"
    print("ok  zero iterations and isolated vertices are no-ops")


# ---------------------------------------------------------------------------
# reduction_percent

def test_reduction_percent():
    assert refine.reduction_percent(1000, 10) == 99.0
    assert refine.reduction_percent(0, 0) == 0.0
    assert refine.reduction_percent(10, 20) == 0.0, \
        "growth must read as 0%% reduction"
    print("ok  reduction percentage is well-behaved")


if __name__ == "__main__":
    test_full_preservation_is_cleanup_only()
    test_zero_preservation_hits_the_extremes()
    test_settings_monotonic_and_clamped()
    test_halfway_preservation_is_one_order_of_magnitude()
    test_auto_weld_distance_scales_with_the_mesh()
    test_smoothing_reduces_noise_and_respects_locks()
    test_smoothing_preserves_volume_better_than_laplacian()
    test_smoothing_edge_cases()
    test_reduction_percent()
    print("\nall mesh dewrangler tests passed")
