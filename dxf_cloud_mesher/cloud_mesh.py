# SPDX-License-Identifier: GPL-3.0-or-later
"""Geometry planning for filling DXF point-cloud objects.

Pure-Python module (no ``bpy``): the Blender operator feeds it
world-space vertex positions and gets back vertex indices, so it can be
unit tested outside Blender (see ``tests/test_cloud_mesher.py``).

Pipeline
--------
classify_objects()
    Decide which objects may be filled: everything whose points stay
    within the height tolerance on Z, plus the lowest object (ground)
    even when it exceeds the tolerance.
plan_fill()
    For one object, produce either a single n-gon over the boundary of
    the point cloud, or -- only when that face would overlap vertices
    lying inside it -- a Delaunay triangulation using every point.

Inside Blender the fast C implementation ``mathutils.geometry.
delaunay_2d_cdt`` is used; outside (tests) a pure-Python Bowyer-Watson
fallback produces the same kind of Delaunay triangulation.
"""

try:
    from mathutils import Vector
    from mathutils.geometry import delaunay_2d_cdt
except ImportError:  # running outside Blender
    Vector = None
    delaunay_2d_cdt = None


# ---------------------------------------------------------------------------
# Object classification


def classify_objects(z_bounds, height_limit, fill_lowest=True):
    """Decide which objects can be filled.

    z_bounds: {key: (z_min, z_max)} in world space.
    Returns {key: (fill, reason)}.

    An object is fillable when its points vary on Z by no more than
    ``height_limit``; an object exceeding that is still fillable when it
    is the lowest one of the group (its lowest point is the lowest of
    all objects) -- that object is treated as the ground.
    """
    result = {}
    lowest_key = None
    if z_bounds:
        lowest_key = min(z_bounds, key=lambda k: (z_bounds[k][0], str(k)))
    for key, (z_min, z_max) in z_bounds.items():
        z_range = z_max - z_min
        if z_range <= height_limit:
            result[key] = (True, "height variation %.4g within tolerance"
                           % z_range)
        elif fill_lowest and key == lowest_key:
            result[key] = (True, "height variation %.4g exceeds tolerance "
                           "but object is the lowest (ground)" % z_range)
        else:
            result[key] = (False, "height variation %.4g exceeds tolerance "
                           "and object is not the lowest" % z_range)
    return result


# ---------------------------------------------------------------------------
# Fill planning


def plan_fill(points):
    """Plan how to fill one point cloud.

    points: [(x, y, z), ...] world-space positions; index order must
    match the object's vertex order.

    Returns one of:
      ('NGON', [i0, i1, ...])          boundary loop for a single face
      ('TRIANGLES', [(i, j, k), ...])  Delaunay triangles
      (None, reason)                   object cannot be filled
    """
    if len(points) < 3:
        return None, "fewer than 3 vertices"

    pts = [(p[0], p[1]) for p in points]
    min_x = min(p[0] for p in pts)
    max_x = max(p[0] for p in pts)
    min_y = min(p[1] for p in pts)
    max_y = max(p[1] for p in pts)
    diag = ((max_x - min_x) ** 2 + (max_y - min_y) ** 2) ** 0.5
    if diag <= 0.0:
        return None, "all vertices coincide in the XY plane"
    eps = diag * 1e-6

    unique = _dedupe_indices(pts, eps)
    if len(unique) < 3:
        return None, "fewer than 3 distinct vertices"

    hull = _convex_hull(pts, unique)
    if len(hull) < 3:
        return None, "vertices are collinear"

    boundary, interior = _boundary_with_collinear(pts, hull, unique, eps)
    if not interior:
        # The face touches every (distinct) vertex: no triangulation.
        return 'NGON', boundary

    # The single face would overlap vertices inside it: triangulate so
    # every point becomes part of the surface.
    triangles = _delaunay(pts, unique)
    if not triangles:
        return None, "triangulation failed"
    return 'TRIANGLES', triangles


def _dedupe_indices(pts, eps):
    """Indices of the first occurrence of each distinct XY position."""
    grid = {}
    unique = []
    for i, (x, y) in enumerate(pts):
        key = (round(x / eps), round(y / eps))
        duplicate = False
        for dx in (0, -1, 1):
            for dy in (0, -1, 1):
                for j in grid.get((key[0] + dx, key[1] + dy), ()):
                    if abs(pts[j][0] - x) <= eps and abs(pts[j][1] - y) <= eps:
                        duplicate = True
                        break
                if duplicate:
                    break
            if duplicate:
                break
        if not duplicate:
            grid.setdefault(key, []).append(i)
            unique.append(i)
    return unique


def _cross(points, o, a, b):
    ox, oy = points[o]
    return ((points[a][0] - ox) * (points[b][1] - oy)
            - (points[a][1] - oy) * (points[b][0] - ox))


def _convex_hull(points, indices):
    """Strict convex hull (no collinear points), counter-clockwise."""
    order = sorted(indices, key=lambda i: points[i])
    if len(order) <= 2:
        return order
    lower = []
    for i in order:
        while len(lower) >= 2 and _cross(points, lower[-2], lower[-1], i) <= 0:
            lower.pop()
        lower.append(i)
    upper = []
    for i in reversed(order):
        while len(upper) >= 2 and _cross(points, upper[-2], upper[-1], i) <= 0:
            upper.pop()
        upper.append(i)
    return lower[:-1] + upper[:-1]


def _boundary_with_collinear(points, hull, candidates, eps):
    """Split non-hull points into on-boundary and interior.

    Points sitting on a hull edge become n-gon vertices (inserted in
    order along the edge); everything else is strictly inside the hull.
    Returns (boundary_loop, interior_indices).
    """
    hull_set = set(hull)
    count = len(hull)
    on_edge = [[] for _ in range(count)]
    interior = []
    eps_sq = eps * eps

    for i in candidates:
        if i in hull_set:
            continue
        px, py = points[i]
        placed = False
        for k in range(count):
            ax, ay = points[hull[k]]
            bx, by = points[hull[(k + 1) % count]]
            dx, dy = bx - ax, by - ay
            length_sq = dx * dx + dy * dy
            if length_sq <= 0.0:
                continue
            t = ((px - ax) * dx + (py - ay) * dy) / length_sq
            if t <= 0.0 or t >= 1.0:
                continue
            ex = ax + t * dx - px
            ey = ay + t * dy - py
            if ex * ex + ey * ey <= eps_sq:
                on_edge[k].append((t, i))
                placed = True
                break
        if not placed:
            interior.append(i)

    boundary = []
    for k in range(count):
        boundary.append(hull[k])
        boundary.extend(i for _t, i in sorted(on_edge[k]))
    return boundary, interior


# ---------------------------------------------------------------------------
# Delaunay triangulation


def _delaunay(points, indices):
    """Delaunay triangles (CCW index triples) of a subset of points."""
    if delaunay_2d_cdt is not None:
        try:
            return _delaunay_blender(points, indices)
        except Exception:
            pass  # fall back to the pure-Python implementation
    return _delaunay_pure(points, indices)


def _delaunay_blender(points, indices):
    coords = [Vector(points[i]) for i in indices]
    result = delaunay_2d_cdt(coords, [], [], 0, 1e-12)
    faces_out = result[2]
    orig_verts = result[3]
    triangles = []
    for face in faces_out:
        if len(face) != 3:
            continue
        mapped = []
        for vi in face:
            orig = orig_verts[vi]
            if not orig:
                mapped = None
                break
            mapped.append(indices[orig[0]])
        if mapped:
            triangles.append(tuple(mapped))
    return triangles


def _delaunay_pure(points, indices):
    """Bowyer-Watson Delaunay triangulation (used outside Blender)."""
    n = len(indices)
    if n < 3:
        return []

    # Normalise into a unit box for numerical stability.
    min_x = min(points[i][0] for i in indices)
    max_x = max(points[i][0] for i in indices)
    min_y = min(points[i][1] for i in indices)
    max_y = max(points[i][1] for i in indices)
    span = max(max_x - min_x, max_y - min_y) or 1.0
    coords = [((points[i][0] - min_x) / span, (points[i][1] - min_y) / span)
              for i in indices]

    # Super-triangle (counter-clockwise) far outside the unit box.
    coords = coords + [(-100.0, -100.0), (100.0, -100.0), (0.5, 200.0)]
    triangles = [(n, n + 1, n + 2)]

    for pi in range(n):
        px, py = coords[pi]
        bad = [t for t in triangles if _in_circumcircle(coords, t, px, py)]
        if not bad:
            continue
        directed = set()
        for t in bad:
            directed.add((t[0], t[1]))
            directed.add((t[1], t[2]))
            directed.add((t[2], t[0]))
        boundary = [e for e in directed if (e[1], e[0]) not in directed]
        bad_set = set(bad)
        triangles = [t for t in triangles if t not in bad_set]
        for a, b in boundary:
            # Cavity boundary edges run CCW, so (a, b, pi) is CCW too.
            triangles.append((a, b, pi))

    result = []
    for t in triangles:
        if t[0] < n and t[1] < n and t[2] < n:
            result.append((indices[t[0]], indices[t[1]], indices[t[2]]))
    return result


def _in_circumcircle(coords, tri, px, py):
    """Point strictly inside the circumcircle of a CCW triangle."""
    ax, ay = coords[tri[0]]
    bx, by = coords[tri[1]]
    cx, cy = coords[tri[2]]
    adx, ady = ax - px, ay - py
    bdx, bdy = bx - px, by - py
    cdx, cdy = cx - px, cy - py
    ad = adx * adx + ady * ady
    bd = bdx * bdx + bdy * bdy
    cd = cdx * cdx + cdy * cdy
    det = (adx * (bdy * cd - bd * cdy)
           - ady * (bdx * cd - bd * cdx)
           + ad * (bdx * cdy - bdy * cdx))
    return det > 1e-12


# ---------------------------------------------------------------------------
# Helpers shared with the tests


def loop_area(points, loop):
    """Signed area of an index loop over 2D points (CCW positive)."""
    area = 0.0
    for i in range(len(loop)):
        x0, y0 = points[loop[i]][0], points[loop[i]][1]
        x1, y1 = (points[loop[(i + 1) % len(loop)]][0],
                  points[loop[(i + 1) % len(loop)]][1])
        area += x0 * y1 - x1 * y0
    return 0.5 * area
