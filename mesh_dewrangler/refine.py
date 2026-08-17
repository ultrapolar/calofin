# SPDX-License-Identifier: GPL-3.0-or-later
"""Pure-Python core of the Mesh Dewrangler add-on.

Everything in this module runs without ``bpy`` so it can be unit
tested outside Blender:

* :func:`derive_settings` turns the single user-facing *detail
  preservation* factor into the concrete strengths of every
  simplification stage (smoothing iterations, collapse ratio,
  planar-dissolve angle).
* :func:`auto_weld_distance` picks a merge threshold relative to the
  size of the mesh, so welding behaves the same on a coin and on a
  terrain scan.
* :func:`taubin_smooth` is a volume-preserving denoiser (Taubin
  lambda/mu smoothing).  Unlike plain Laplacian smoothing it barely
  shrinks the mesh, which is what makes it safe to run before
  decimation.
"""

import math

# Stage strengths at preservation = 0 (the most aggressive setting).
MAX_SMOOTH_ITERATIONS = 10
MAX_DISSOLVE_ANGLE_DEG = 15.0
MIN_COLLAPSE_RATIO = 0.01

# Classic Taubin coefficients: a positive (shrinking) step followed by
# a slightly larger negative (inflating) step keeps the volume stable.
TAUBIN_LAMBDA = 0.5
TAUBIN_MU = -0.53

# Weld threshold as a fraction of the bounding-box diagonal.
WELD_FRACTION = 1e-4


def clamp(value, low, high):
    return max(low, min(high, value))


def derive_settings(preservation):
    """Map the 0..1 *detail preservation* factor to stage strengths.

    ``preservation = 1.0`` means "clean up only": no smoothing, no
    decimation, no planar dissolve.  ``preservation = 0.0`` is the most
    aggressive simplification.  Returns a dict with:

    ``smooth_iterations``
        Taubin denoising passes (0 .. MAX_SMOOTH_ITERATIONS).
    ``collapse_ratio``
        Target triangle ratio for collapse decimation (1.0 = keep all).
        Decays exponentially so the slider feels linear: half the
        slider is one order of magnitude of reduction.
    ``dissolve_angle``
        Planar-dissolve angle limit in **radians** (0 = skip).
    """
    p = clamp(float(preservation), 0.0, 1.0)
    aggression = 1.0 - p
    return {
        "smooth_iterations": int(round(aggression * MAX_SMOOTH_ITERATIONS)),
        "collapse_ratio": clamp(10.0 ** (-2.0 * aggression),
                                MIN_COLLAPSE_RATIO, 1.0),
        "dissolve_angle": math.radians(aggression * MAX_DISSOLVE_ANGLE_DEG),
    }


def auto_weld_distance(bbox_min, bbox_max, fraction=WELD_FRACTION):
    """Weld threshold scaled to the mesh: *fraction* of the bounding-box
    diagonal, so duplicate vertices merge without eating real detail."""
    diagonal = math.sqrt(sum((hi - lo) ** 2
                             for lo, hi in zip(bbox_min, bbox_max)))
    return diagonal * fraction


def _average_step(positions, neighbours, factor, locked, out):
    for i, pos in enumerate(positions):
        adjacent = neighbours[i]
        if i in locked or not adjacent:
            out[i] = pos
            continue
        n = float(len(adjacent))
        ax = sum(positions[j][0] for j in adjacent) / n
        ay = sum(positions[j][1] for j in adjacent) / n
        az = sum(positions[j][2] for j in adjacent) / n
        out[i] = (pos[0] + factor * (ax - pos[0]),
                  pos[1] + factor * (ay - pos[1]),
                  pos[2] + factor * (az - pos[2]))
    return out


def taubin_smooth(positions, neighbours, iterations,
                  lam=TAUBIN_LAMBDA, mu=TAUBIN_MU, locked=frozenset()):
    """Taubin lambda/mu smoothing.

    ``positions``
        Sequence of ``(x, y, z)`` tuples.
    ``neighbours``
        ``neighbours[i]`` lists the vertex indices connected to vertex
        ``i`` by an edge.
    ``locked``
        Indices that must not move (typically boundary vertices, so an
        open mesh keeps its outline).

    Returns a new list of positions; the input is left untouched.
    """
    if iterations <= 0:
        return list(positions)
    current = list(positions)
    scratch = [None] * len(current)
    locked = frozenset(locked)
    for _ in range(iterations):
        current = list(_average_step(current, neighbours, lam,
                                     locked, scratch))
        current = list(_average_step(current, neighbours, mu,
                                     locked, scratch))
    return current


def reduction_percent(before, after):
    """Human-readable size reduction, e.g. ``97.3``.  Zero when the
    mesh grew or was empty."""
    if before <= 0 or after >= before:
        return 0.0
    return (1.0 - after / float(before)) * 100.0
