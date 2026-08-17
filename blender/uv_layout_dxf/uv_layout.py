# SPDX-License-Identifier: GPL-3.0-or-later
"""UV island analysis for the DXF exporter.

Pure geometry/topology module: it deliberately imports no ``bpy`` so the
whole pipeline can be unit tested outside Blender (see ``tests/``).

Pipeline
--------
build_islands()
    Group faces into UV islands, detect mirrored islands from face
    winding (normal data) and build the island adjacency graph.
orient_islands()
    Un-mirror flipped islands, pick a base island per connected group
    and rotate every other island so shared seam edges line up.
build_outlines()
    Extract only the perimeter loops of each island (interior edges are
    never emitted).
freestyle_scale_reference()
    Derive the UV -> real-world scale factor from Freestyle-marked edges.
repack_islands()
    Optional simple shelf packing so re-oriented islands cannot overlap.
"""

import math
from collections import defaultdict, deque

from mathutils import Matrix, Vector

# Two UV corners closer than this (in UV units) count as welded.
WELD_EPS = 1e-6


class Island:
    """A UV island: a set of faces connected through welded UV edges."""

    __slots__ = (
        "index",
        "faces",
        "face_set",
        "centroid",
        "flipped",
        "transform",
        "neighbors",
        "area_3d",
        "loops_2d",
    )

    def __init__(self, index, faces):
        self.index = index
        self.faces = faces
        self.face_set = {f.index for f in faces}
        self.centroid = Vector((0.0, 0.0))
        self.flipped = False
        self.transform = Matrix.Identity(3)  # 2D affine transform
        self.neighbors = {}  # Island -> [shared BMEdge, ...]
        self.area_3d = 0.0
        self.loops_2d = []  # closed outlines, filled by build_outlines()


# ---------------------------------------------------------------------------
# Small 2D affine helpers (3x3 matrices acting on (x, y, 1))


def _translation(tx, ty):
    m = Matrix.Identity(3)
    m[0][2] = tx
    m[1][2] = ty
    return m


def _mirror_u_about(cx):
    """Mirror U (horizontally) about the vertical axis x = cx."""
    m = Matrix.Identity(3)
    m[0][0] = -1.0
    m[0][2] = 2.0 * cx
    return m


def _rotation_about(angle, pivot):
    return (
        _translation(pivot.x, pivot.y)
        @ Matrix.Rotation(angle, 3, 'Z')
        @ _translation(-pivot.x, -pivot.y)
    )


def _apply(mat, p):
    q = mat @ Vector((p.x, p.y, 1.0))
    return Vector((q.x, q.y))


def _apply_dir(mat, v):
    """Transform a direction vector (linear part only, no translation)."""
    return Vector((
        mat[0][0] * v.x + mat[0][1] * v.y,
        mat[1][0] * v.x + mat[1][1] * v.y,
    ))


# ---------------------------------------------------------------------------
# Island detection


def _uv_welded(la, lb, uv, eps=WELD_EPS):
    """True when two radial loops of the same mesh edge have matching UVs."""
    a0 = la[uv].uv
    a1 = la.link_loop_next[uv].uv
    b0 = lb[uv].uv
    b1 = lb.link_loop_next[uv].uv
    if lb.vert is la.vert:
        return (a0 - b0).length <= eps and (a1 - b1).length <= eps
    return (a0 - b1).length <= eps and (a1 - b0).length <= eps


def _is_uv_boundary(loop, uv):
    """A loop's edge is a UV boundary when no radial neighbour is welded."""
    for other in loop.edge.link_loops:
        if other is loop or other.face is loop.face:
            continue
        if _uv_welded(loop, other, uv):
            return False
    return True


def build_islands(bm, uv):
    """Group faces into UV islands and build the island adjacency graph.

    Two faces belong to the same island when they share a mesh edge whose
    corner UVs coincide on both sides (the edge is "welded" in UV space).
    """
    parent = list(range(len(bm.faces)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for edge in bm.edges:
        loops = edge.link_loops
        for i in range(len(loops)):
            for j in range(i + 1, len(loops)):
                la, lb = loops[i], loops[j]
                if la.face is lb.face:
                    continue
                if _uv_welded(la, lb, uv):
                    ra, rb = find(la.face.index), find(lb.face.index)
                    if ra != rb:
                        parent[rb] = ra

    groups = defaultdict(list)
    for face in bm.faces:
        if len(face.loops) >= 3:
            groups[find(face.index)].append(face)

    islands = []
    for faces in sorted(groups.values(), key=lambda fs: min(f.index for f in fs)):
        isl = Island(len(islands), faces)
        signed_area = 0.0
        centroid = Vector((0.0, 0.0))
        n_corners = 0
        for face in faces:
            pts = [loop[uv].uv for loop in face.loops]
            for k in range(len(pts)):
                p = pts[k]
                q = pts[(k + 1) % len(pts)]
                signed_area += p.x * q.y - q.x * p.y
            for p in pts:
                centroid = centroid + p
            n_corners += len(pts)
            isl.area_3d += face.calc_area()
        # Blender face loops wind counter-clockwise when seen from the
        # front (normal side) of the face; a negative UV area therefore
        # means the island is mirrored relative to the 3D surface.
        isl.flipped = signed_area < 0.0
        isl.centroid = centroid / n_corners
        islands.append(isl)

    _build_adjacency(bm, islands)
    return islands


def _build_adjacency(bm, islands):
    face_island = {}
    for isl in islands:
        for index in isl.face_set:
            face_island[index] = isl
    for edge in bm.edges:
        faces = edge.link_faces
        if len(faces) != 2:  # ignore open borders and non-manifold edges
            continue
        ia = face_island.get(faces[0].index)
        ib = face_island.get(faces[1].index)
        if ia is None or ib is None or ia is ib:
            continue
        ia.neighbors.setdefault(ib, []).append(edge)
        ib.neighbors.setdefault(ia, []).append(edge)


# ---------------------------------------------------------------------------
# Orientation fixing


def orient_islands(islands, uv):
    """Fix mirroring and rotation of every island.

    Mirrored islands are detected from normal data: a face's loops run
    counter-clockwise when viewed from the normal side, so an island whose
    UV winding is clockwise (negative area) is flipped and gets un-mirrored.

    For every connected group of islands (connected through shared mesh
    edges) a base island is chosen, preferring islands that share edges
    with exactly ONE other island (islands touching two or more other
    islands are excluded from the candidate pool).  The remaining islands
    are rotated, breadth-first from the base island, so that each shared
    edge points the same way as it does in the already-oriented neighbour.

    Returns the list of base islands (one per connected group).
    """
    for isl in islands:
        if isl.flipped:
            isl.transform = _mirror_u_about(isl.centroid.x) @ isl.transform

    seen = set()
    base_islands = []
    for isl in islands:
        if isl in seen or not isl.neighbors:
            continue
        component = []
        stack = [isl]
        seen.add(isl)
        while stack:
            current = stack.pop()
            component.append(current)
            for neighbor in current.neighbors:
                if neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)

        # Base island: only islands sharing edges with exactly one other
        # island qualify; fall back to the whole component when the graph
        # has no such "leaf" island (e.g. a closed ring of islands).
        leaves = [c for c in component if len(c.neighbors) == 1]
        pool = leaves if leaves else component
        base = max(pool, key=lambda c: c.area_3d)
        base_islands.append(base)
        _propagate_rotation(base, uv)

    return base_islands


def _propagate_rotation(base, uv):
    done = {base}
    queue = deque([base])
    while queue:
        current = queue.popleft()
        for neighbor in current.neighbors:
            if neighbor in done:
                continue
            angle = _match_angle(neighbor, done, uv)
            if angle is not None:
                pivot = _apply(neighbor.transform, neighbor.centroid)
                neighbor.transform = (
                    _rotation_about(angle, pivot) @ neighbor.transform
                )
            done.add(neighbor)
            queue.append(neighbor)


def _match_angle(isl, done, uv):
    """Rotation aligning `isl`'s shared edges with its oriented neighbours.

    When two islands were welded along a seam edge, the edge would have the
    same direction (by mesh-vertex correspondence) in both; so the angle
    that rotates each shared edge of `isl` onto the matching edge of the
    already-oriented neighbour is accumulated and averaged.
    """
    sum_cos = 0.0
    sum_sin = 0.0
    for other, edges in isl.neighbors.items():
        if other not in done:
            continue
        for edge in edges:
            vectors = _edge_uv_vectors(edge, isl, other, uv)
            if vectors is None:
                continue
            vec_here, vec_there = vectors
            b = _apply_dir(isl.transform, vec_here)
            a = _apply_dir(other.transform, vec_there)
            sum_cos += b.x * a.x + b.y * a.y
            sum_sin += b.x * a.y - b.y * a.x
    if sum_cos == 0.0 and sum_sin == 0.0:
        return None
    return math.atan2(sum_sin, sum_cos)


def _edge_uv_vectors(edge, isl, other, uv):
    """UV direction of a shared mesh edge in both islands.

    Returns (vector in `isl`, vector in `other`), both measured in raw
    (untransformed) UV space and pointing between the same mesh vertices.
    """
    loop_here = loop_there = None
    for loop in edge.link_loops:
        if loop.face.index in isl.face_set:
            if loop_here is None:
                loop_here = loop
        elif loop.face.index in other.face_set:
            if loop_there is None:
                loop_there = loop
    if loop_here is None or loop_there is None:
        return None

    a0 = loop_here[uv].uv
    a1 = loop_here.link_loop_next[uv].uv
    b0 = loop_there[uv].uv
    b1 = loop_there.link_loop_next[uv].uv
    vec_here = a1 - a0
    # Match mesh-vertex order across the seam.
    if loop_there.vert is loop_here.vert:
        vec_there = b1 - b0
    else:
        vec_there = b0 - b1
    return vec_here, vec_there


# ---------------------------------------------------------------------------
# Perimeter extraction


def build_outlines(islands, uv, include_holes=True):
    """Fill ``island.loops_2d`` with the island's closed perimeter loops.

    Only UV boundary edges are used, so any edge lying inside the island
    perimeter (interior topology) is never exported.  With
    ``include_holes`` disabled only the largest loop per island survives.
    """
    for isl in islands:
        segments = []
        for face in isl.faces:
            for loop in face.loops:
                if not _is_uv_boundary(loop, uv):
                    continue
                p0 = _apply(isl.transform, loop[uv].uv)
                p1 = _apply(isl.transform, loop.link_loop_next[uv].uv)
                if (p1 - p0).length > 1e-12:
                    segments.append((p0, p1))

        loops = _chain_segments(segments)
        if not include_holes and len(loops) > 1:
            loops = [max(loops, key=lambda pts: abs(_loop_area(pts)))]
        isl.loops_2d = loops


def _chain_segments(segments, quant=WELD_EPS):
    """Chain directed segments into closed loops by matching endpoints."""

    def key(p):
        return (round(p.x / quant), round(p.y / quant))

    start_lookup = defaultdict(list)
    for i, (p0, _p1) in enumerate(segments):
        start_lookup[key(p0)].append(i)

    used = [False] * len(segments)

    def find_unused(k):
        # Exact cell first, then neighbours (guards against float rounding
        # straddling a quantisation boundary).
        for dx in (0, -1, 1):
            for dy in (0, -1, 1):
                for i in start_lookup.get((k[0] + dx, k[1] + dy), ()):
                    if not used[i]:
                        return i
        return None

    loops = []
    for start in range(len(segments)):
        if used[start]:
            continue
        used[start] = True
        first_key = key(segments[start][0])
        points = [segments[start][0]]
        end = segments[start][1]
        for _ in range(len(segments)):
            k = key(end)
            if k == first_key:
                break
            follower = find_unused(k)
            if follower is None:
                break
            used[follower] = True
            points.append(segments[follower][0])
            end = segments[follower][1]

        cleaned = [points[0]]
        for p in points[1:]:
            if (p - cleaned[-1]).length > 1e-9:
                cleaned.append(p)
        if len(cleaned) > 1 and (cleaned[0] - cleaned[-1]).length <= 1e-9:
            cleaned.pop()
        if len(cleaned) >= 3:
            loops.append(cleaned)
    return loops


def _loop_area(points):
    area = 0.0
    for i in range(len(points)):
        p = points[i]
        q = points[(i + 1) % len(points)]
        area += p.x * q.y - q.x * p.y
    return 0.5 * area


# ---------------------------------------------------------------------------
# Freestyle scale reference


def freestyle_edge_indices(mesh):
    """Indices of Freestyle-marked edges on a Mesh datablock.

    Reads the generic "freestyle_edge" boolean attribute (Blender 4.0+)
    and falls back to the legacy MeshEdge.use_freestyle_mark property.
    """
    indices = set()
    attributes = getattr(mesh, "attributes", None)
    if attributes is not None:
        attr = attributes.get("freestyle_edge")
        if attr is not None and getattr(attr, "domain", 'EDGE') == 'EDGE':
            try:
                for i, item in enumerate(attr.data):
                    if item.value:
                        indices.add(i)
                return indices
            except (AttributeError, TypeError):
                indices.clear()
    for edge in mesh.edges:
        if getattr(edge, "use_freestyle_mark", False):
            indices.add(edge.index)
    return indices


def freestyle_scale_reference(obj, mesh, bm, uv, unit_factor=1.0, scene_scale=1.0):
    """UV -> DXF scale factor from Freestyle-marked reference edges.

    Compares the real (world-space) length of every marked edge with its
    length in the UV layout and returns ``(scale, edge_count)`` such that
    ``uv_length * scale == 3d_length * unit_factor``.  Multiple marked
    edges are combined as a length-weighted average.  Returns None when
    no usable marked edge exists.
    """
    marked = freestyle_edge_indices(mesh)
    if not marked:
        return None

    matrix = obj.matrix_world
    sum_3d = 0.0
    sum_uv = 0.0
    used = 0
    for index in sorted(marked):
        if index >= len(bm.edges):
            continue
        edge = bm.edges[index]
        uv_lengths = []
        for loop in edge.link_loops:
            length = (loop[uv].uv - loop.link_loop_next[uv].uv).length
            if length > 1e-12:
                uv_lengths.append(length)
        if not uv_lengths:
            continue
        v0, v1 = edge.verts
        length_3d = ((matrix @ v0.co) - (matrix @ v1.co)).length * scene_scale
        sum_3d += length_3d
        sum_uv += sum(uv_lengths) / len(uv_lengths)
        used += 1

    if used == 0 or sum_uv <= 1e-12:
        return None
    return (sum_3d * unit_factor) / sum_uv, used


# ---------------------------------------------------------------------------
# Optional overlap-free packing


def repack_islands(islands, margin_ratio=0.05):
    """Arrange island outlines into simple shelves so nothing overlaps."""
    boxes = []
    for isl in islands:
        pts = [p for outline in isl.loops_2d for p in outline]
        if not pts:
            continue
        min_x = min(p.x for p in pts)
        max_x = max(p.x for p in pts)
        min_y = min(p.y for p in pts)
        max_y = max(p.y for p in pts)
        boxes.append((isl, min_x, min_y, max_x - min_x, max_y - min_y))
    if not boxes:
        return

    mean_dim = sum(b[3] + b[4] for b in boxes) / (2 * len(boxes))
    margin = (mean_dim or 1.0) * margin_ratio
    boxes.sort(key=lambda b: (-b[4], b[0].index))

    total_area = sum((b[3] + margin) * (b[4] + margin) for b in boxes)
    row_width = max(math.sqrt(total_area) * 1.15,
                    max(b[3] for b in boxes) + margin)

    x = y = row_height = 0.0
    for isl, min_x, min_y, width, height in boxes:
        if x > 0.0 and x + width > row_width:
            x = 0.0
            y += row_height
            row_height = 0.0
        dx = x - min_x
        dy = y - min_y
        for outline in isl.loops_2d:
            for p in outline:
                p.x += dx
                p.y += dy
        x += width + margin
        row_height = max(row_height, height + margin)
