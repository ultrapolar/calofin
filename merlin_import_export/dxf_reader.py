# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal ASCII DXF reader for AutoCAD drawings.

Pure-Python module (no ``bpy``): it turns the ENTITIES section of an
ASCII DXF file into per-layer mesh data (vertices, edges, faces) that
the Blender import operator feeds to ``Mesh.from_pydata``, so it can be
unit tested outside Blender (see ``tests/test_dxf_reader.py``).

Supported entities
------------------
POINT, LINE, LWPOLYLINE (with bulge arcs), POLYLINE/VERTEX/SEQEND
(2D and 3D polylines with bulges, polyface meshes, polygon meshes),
3DFACE, SOLID, CIRCLE, ARC, ELLIPSE and SPLINE (sampled).  Everything
else (TEXT, INSERT, HATCH, DIMENSION, ...) is counted and skipped.

Curved entities are sampled into straight segments; the number of
segments used for a full circle is the ``arc_segments`` argument.
"""

import math


BINARY_SENTINEL = b"AutoCAD Binary DXF"

# Entity types that never contribute mesh geometry; anything not listed
# here or in the handlers is reported as unsupported all the same, this
# set just exists so common annotation entities get a friendlier report.
_KNOWN_NON_GEOMETRY = frozenset({
    "TEXT", "MTEXT", "INSERT", "HATCH", "DIMENSION", "LEADER",
    "MULTILEADER", "MLEADER", "ATTDEF", "ATTRIB", "VIEWPORT", "IMAGE",
    "WIPEOUT", "XLINE", "RAY", "TOLERANCE", "TRACE", "SHAPE",
})

_DEFAULT_LAYER = "0"


# ---------------------------------------------------------------------------
# Per-layer geometry accumulator


class LayerGeometry:
    """Vertices/edges/faces collected for one DXF layer.

    Coincident vertices (within a rounding epsilon) are merged so lines
    that share endpoints produce connected geometry.
    """

    def __init__(self):
        self.verts = []
        self.edges = []
        self.faces = []
        self._vert_map = {}
        self._edge_set = set()

    def vertex(self, point):
        key = (round(point[0], 9), round(point[1], 9), round(point[2], 9))
        index = self._vert_map.get(key)
        if index is None:
            index = len(self.verts)
            self._vert_map[key] = index
            self.verts.append((point[0], point[1], point[2]))
        return index

    def add_point(self, point):
        self.vertex(point)

    def add_edge(self, i, j):
        if i == j:
            return
        key = (i, j) if i < j else (j, i)
        if key not in self._edge_set:
            self._edge_set.add(key)
            self.edges.append(key)

    def add_path(self, points, closed=False):
        indices = [self.vertex(p) for p in points]
        for a, b in zip(indices, indices[1:]):
            self.add_edge(a, b)
        if closed and len(indices) > 2:
            self.add_edge(indices[-1], indices[0])

    def add_face(self, points):
        indices = []
        for p in points:
            i = self.vertex(p)
            if i not in indices:
                indices.append(i)
        if len(indices) >= 3:
            self.faces.append(tuple(indices))
            for k in range(len(indices)):
                self.add_edge(indices[k], indices[(k + 1) % len(indices)])
        elif len(indices) == 2:
            self.add_edge(indices[0], indices[1])

    @property
    def empty(self):
        return not self.verts


# ---------------------------------------------------------------------------
# Tag stream


def _tags(text):
    """Yield (group_code, value) pairs from ASCII DXF text."""
    lines = text.splitlines()
    for k in range(0, len(lines) - 1, 2):
        code_line = lines[k].strip()
        if not code_line:
            continue
        try:
            code = int(code_line)
        except ValueError:
            continue
        yield code, lines[k + 1].strip()


def _float(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _group_entities(tags):
    """Split a tag stream into (type, [(code, value), ...]) entities."""
    entities = []
    current = None
    for code, value in tags:
        if code == 0:
            current = (value.upper(), [])
            entities.append(current)
        elif current is not None:
            current[1].append((code, value))
    return entities


def _fields(entity_tags):
    """Collect entity tags into {code: [values...]} (order preserved)."""
    fields = {}
    for code, value in entity_tags:
        fields.setdefault(code, []).append(value)
    return fields


def _first(fields, code, default=None):
    values = fields.get(code)
    return values[0] if values else default


def _layer_of(fields):
    name = _first(fields, 8, _DEFAULT_LAYER) or _DEFAULT_LAYER
    return name


def _xyz(fields, x_code, y_code, z_code, index=0):
    def pick(code):
        values = fields.get(code)
        if values and index < len(values):
            return _float(values[index])
        return 0.0
    return (pick(x_code), pick(y_code), pick(z_code))


# ---------------------------------------------------------------------------
# Curve sampling


def _segments_for(angle, arc_segments):
    """Segment count for a swept angle, scaled from a full circle."""
    return max(2, int(math.ceil(arc_segments * abs(angle) / (2.0 * math.pi))))


def bulge_points(p1, p2, bulge, arc_segments=32):
    """Intermediate points of a bulge arc between two polyline vertices.

    A DXF bulge is tan(theta/4) of the included angle; positive bulges
    sweep counter-clockwise from p1 to p2.  Endpoints are not returned.
    """
    if not bulge:
        return []
    theta = 4.0 * math.atan(bulge)
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    chord = math.hypot(dx, dy)
    if chord <= 0.0:
        return []
    radius = chord * (1.0 + bulge * bulge) / (4.0 * abs(bulge))
    # Angle from p1 towards the arc centre.
    gamma = (math.pi - abs(theta)) / 2.0
    direction = math.atan2(dy, dx) + (gamma if bulge > 0 else -gamma)
    cx = p1[0] + radius * math.cos(direction)
    cy = p1[1] + radius * math.sin(direction)
    start = math.atan2(p1[1] - cy, p1[0] - cx)
    steps = _segments_for(theta, arc_segments)
    points = []
    for k in range(1, steps):
        a = start + theta * (k / steps)
        z = p1[2] + (p2[2] - p1[2]) * (k / steps)
        points.append((cx + radius * math.cos(a),
                       cy + radius * math.sin(a), z))
    return points


def _expand_bulged_path(vertices, bulges, closed, arc_segments):
    """Insert sampled arc points between bulged polyline vertices."""
    count = len(vertices)
    if count < 2:
        return list(vertices)
    points = []
    last = count if closed else count - 1
    for i in range(last):
        p1 = vertices[i]
        p2 = vertices[(i + 1) % count]
        points.append(p1)
        points.extend(bulge_points(p1, p2, bulges[i], arc_segments))
    if not closed:
        points.append(vertices[-1])
    return points


# ---------------------------------------------------------------------------
# Entity handlers


def _handle_point(layer, fields, arc_segments):
    layer.add_point(_xyz(fields, 10, 20, 30))


def _handle_line(layer, fields, arc_segments):
    layer.add_path([_xyz(fields, 10, 20, 30), _xyz(fields, 11, 21, 31)])


def _handle_lwpolyline(layer, entity_tags, arc_segments):
    elevation = 0.0
    closed = False
    vertices = []
    bulges = []
    for code, value in entity_tags:
        if code == 38:
            elevation = _float(value)
        elif code == 70:
            closed = bool(_int(value) & 1)
        elif code == 10:
            vertices.append([_float(value), 0.0])
            bulges.append(0.0)
        elif code == 20 and vertices:
            vertices[-1][1] = _float(value)
        elif code == 42 and vertices:
            bulges[-1] = _float(value)
    points = [(x, y, elevation) for x, y in vertices]
    if len(points) < 2:
        for p in points:
            layer.add_point(p)
        return
    expanded = _expand_bulged_path(points, bulges, closed, arc_segments)
    layer.add_path(expanded, closed=closed)


def _handle_circle(layer, fields, arc_segments):
    cx, cy, cz = _xyz(fields, 10, 20, 30)
    radius = _float(_first(fields, 40))
    if radius <= 0.0:
        layer.add_point((cx, cy, cz))
        return
    steps = max(3, arc_segments)
    points = [(cx + radius * math.cos(2.0 * math.pi * k / steps),
               cy + radius * math.sin(2.0 * math.pi * k / steps), cz)
              for k in range(steps)]
    layer.add_path(points, closed=True)


def _handle_arc(layer, fields, arc_segments):
    cx, cy, cz = _xyz(fields, 10, 20, 30)
    radius = _float(_first(fields, 40))
    start = math.radians(_float(_first(fields, 50)))
    end = math.radians(_float(_first(fields, 51)))
    if radius <= 0.0:
        layer.add_point((cx, cy, cz))
        return
    while end <= start:
        end += 2.0 * math.pi
    sweep = end - start
    steps = _segments_for(sweep, arc_segments)
    points = [(cx + radius * math.cos(start + sweep * k / steps),
               cy + radius * math.sin(start + sweep * k / steps), cz)
              for k in range(steps + 1)]
    layer.add_path(points)


def _handle_ellipse(layer, fields, arc_segments):
    cx, cy, cz = _xyz(fields, 10, 20, 30)
    mx, my, mz = _xyz(fields, 11, 21, 31)  # major axis endpoint, relative
    ratio = _float(_first(fields, 40), 1.0)
    start = _float(_first(fields, 41), 0.0)
    end = _float(_first(fields, 42), 2.0 * math.pi)
    while end <= start:
        end += 2.0 * math.pi
    sweep = end - start
    closed = abs(sweep - 2.0 * math.pi) < 1e-9
    # Minor axis: major rotated 90 degrees (in the XY plane), scaled.
    nx, ny = -my * ratio, mx * ratio
    steps = _segments_for(sweep, arc_segments)
    count = steps if closed else steps + 1
    points = []
    for k in range(count):
        t = start + sweep * k / steps
        c, s = math.cos(t), math.sin(t)
        points.append((cx + mx * c + nx * s,
                       cy + my * c + ny * s,
                       cz + mz * c))
    layer.add_path(points, closed=closed)


def _handle_face(layer, fields, arc_segments):
    corners = [_xyz(fields, 10, 20, 30), _xyz(fields, 11, 21, 31),
               _xyz(fields, 12, 22, 32)]
    fourth = _xyz(fields, 13, 23, 33)
    if 13 in fields and fourth != corners[2]:
        corners.append(fourth)
    layer.add_face(corners)


def _handle_solid(layer, fields, arc_segments):
    # SOLID stores its corners in a Z order: 3rd and 4th are swapped.
    corners = [_xyz(fields, 10, 20, 30), _xyz(fields, 11, 21, 31)]
    fourth = _xyz(fields, 13, 23, 33)
    third = _xyz(fields, 12, 22, 32)
    if 13 in fields and fourth != third:
        corners.extend([fourth, third])
    else:
        corners.append(third)
    layer.add_face(corners)


def _handle_spline(layer, fields, arc_segments):
    closed = bool(_int(_first(fields, 70)) & 1)
    fit = [(_float(x), _float(y), _float(z)) for x, y, z in
           zip(fields.get(11, ()), fields.get(21, ()), fields.get(31, ()))]
    if len(fit) >= 2:
        layer.add_path(fit, closed=closed)
        return
    control = [(_float(x), _float(y), _float(z)) for x, y, z in
               zip(fields.get(10, ()), fields.get(20, ()), fields.get(30, ()))]
    if len(control) < 2:
        for p in control:
            layer.add_point(p)
        return
    degree = max(1, _int(_first(fields, 71), 3))
    knots = [_float(v) for v in fields.get(40, ())]
    points = _sample_bspline(control, degree, knots,
                             samples=max(len(control) * 4, arc_segments))
    layer.add_path(points, closed=closed)


def _sample_bspline(control, degree, knots, samples):
    """Uniformly sample an (unweighted) B-spline via de Boor's algorithm."""
    n = len(control)
    p = min(degree, n - 1)
    expected = n + p + 1
    if len(knots) != expected:
        # Malformed/missing knot vector: fall back to a clamped uniform one.
        interior = n - p - 1
        knots = ([0.0] * (p + 1)
                 + [(k + 1.0) / (interior + 1.0) for k in range(interior)]
                 + [1.0] * (p + 1))
    lo, hi = knots[p], knots[n]
    if hi <= lo:
        return list(control)
    points = []
    for s in range(samples + 1):
        u = lo + (hi - lo) * s / samples
        points.append(_de_boor(u, p, knots, control, n))
    return points


def _de_boor(u, p, knots, control, n):
    # Find the knot span k with knots[k] <= u < knots[k + 1].
    k = max(p, min(n - 1, _find_span(u, knots, p, n)))
    d = [list(control[j]) for j in range(k - p, k + 1)]
    for r in range(1, p + 1):
        for j in range(p, r - 1, -1):
            i = j + k - p
            denominator = knots[i + p - r + 1] - knots[i]
            alpha = 0.0 if denominator == 0.0 else (u - knots[i]) / denominator
            d[j] = [(1.0 - alpha) * d[j - 1][axis] + alpha * d[j][axis]
                    for axis in range(3)]
    return tuple(d[p])


def _find_span(u, knots, p, n):
    if u >= knots[n]:
        return n - 1
    lo, hi = p, n
    while lo < hi:
        mid = (lo + hi) // 2
        if knots[mid] <= u < knots[mid + 1]:
            return mid
        if u < knots[mid]:
            hi = mid
        else:
            lo = mid + 1
    return lo


def _handle_polyline(layer, fields, vertex_entities, arc_segments):
    flags = _int(_first(fields, 70))
    geometry = []   # (point, bulge)
    face_records = []
    for vfields in vertex_entities:
        point = _xyz(vfields, 10, 20, 30)
        vflags = _int(_first(vfields, 70))
        indices = [_int(_first(vfields, code)) for code in (71, 72, 73, 74)
                   if code in vfields]
        if indices and any(indices):
            face_records.append([abs(i) for i in indices if i != 0])
        elif not (vflags & 16):  # skip spline-frame control points
            geometry.append((point, _float(_first(vfields, 42))))

    if flags & 64 and face_records:  # polyface mesh
        for record in face_records:
            corners = [geometry[i - 1][0] for i in record
                       if 1 <= i <= len(geometry)]
            if len(corners) >= 3:
                layer.add_face(corners)
            elif len(corners) == 2:
                layer.add_path(corners)
        return

    if flags & 16:  # M x N polygon mesh
        m = _int(_first(fields, 71))
        n = _int(_first(fields, 72))
        points = [g[0] for g in geometry]
        if m >= 1 and n >= 1 and m * n <= len(points):
            indices = [[layer.vertex(points[i * n + j]) for j in range(n)]
                       for i in range(m)]
            closed_m = bool(flags & 1)
            closed_n = bool(flags & 32)
            for i in range(m):
                for j in range(n):
                    if j + 1 < n or closed_n:
                        layer.add_edge(indices[i][j], indices[i][(j + 1) % n])
                    if i + 1 < m or closed_m:
                        layer.add_edge(indices[i][j], indices[(i + 1) % m][j])
        else:
            for point in points:
                layer.add_point(point)
        return

    points = [g[0] for g in geometry]
    bulges = [g[1] for g in geometry]
    if len(points) < 2:
        for p in points:
            layer.add_point(p)
        return
    closed = bool(flags & 1)
    expanded = _expand_bulged_path(points, bulges, closed, arc_segments)
    layer.add_path(expanded, closed=closed)


_SIMPLE_HANDLERS = {
    "POINT": _handle_point,
    "LINE": _handle_line,
    "CIRCLE": _handle_circle,
    "ARC": _handle_arc,
    "ELLIPSE": _handle_ellipse,
    "3DFACE": _handle_face,
    "SOLID": _handle_solid,
    "SPLINE": _handle_spline,
}


# ---------------------------------------------------------------------------
# Main entry point


def parse_dxf(text, arc_segments=32):
    """Parse ASCII DXF text.

    Returns ``(layers, stats)``:

    * ``layers``: {layer_name: LayerGeometry} for layers that produced
      geometry, insertion-ordered.
    * ``stats``: {"handled": {type: count}, "skipped": {type: count}}.
    """
    entities = _group_entities(_tags(text))

    # Restrict to ENTITIES sections (ignore blocks, tables, header).
    in_entities = False
    stats = {"handled": {}, "skipped": {}}
    layers = {}

    def layer_for(fields):
        name = _layer_of(fields)
        if name not in layers:
            layers[name] = LayerGeometry()
        return layers[name]

    index = 0
    while index < len(entities):
        etype, entity_tags = entities[index]
        index += 1
        if etype == "SECTION":
            name = next((v for c, v in entity_tags if c == 2), "")
            in_entities = name.upper() == "ENTITIES"
            continue
        if etype == "ENDSEC":
            in_entities = False
            continue
        if not in_entities or etype == "EOF":
            continue

        if etype == "POLYLINE":
            vertex_entities = []
            while index < len(entities) and entities[index][0] == "VERTEX":
                vertex_entities.append(_fields(entities[index][1]))
                index += 1
            if index < len(entities) and entities[index][0] == "SEQEND":
                index += 1
            _handle_polyline(layer_for(_fields(entity_tags)),
                             _fields(entity_tags), vertex_entities,
                             arc_segments)
            stats["handled"]["POLYLINE"] = \
                stats["handled"].get("POLYLINE", 0) + 1
            continue

        if etype == "LWPOLYLINE":
            _handle_lwpolyline(layer_for(_fields(entity_tags)), entity_tags,
                               arc_segments)
            stats["handled"]["LWPOLYLINE"] = \
                stats["handled"].get("LWPOLYLINE", 0) + 1
            continue

        handler = _SIMPLE_HANDLERS.get(etype)
        if handler is not None:
            fields = _fields(entity_tags)
            handler(layer_for(fields), fields, arc_segments)
            stats["handled"][etype] = stats["handled"].get(etype, 0) + 1
        else:
            stats["skipped"][etype] = stats["skipped"].get(etype, 0) + 1

    layers = {name: geo for name, geo in layers.items() if not geo.empty}
    return layers, stats


# ---------------------------------------------------------------------------
# Scene-planning helpers (used by the import operator, tested standalone)


def pick_parent(layers):
    """Name of the layer with the most vertices (ties: first by name)."""
    if not layers:
        return None
    return max(sorted(layers), key=lambda name: len(layers[name].verts))


def center_of_mass(verts):
    """Arithmetic mean of a vertex list (the point cloud's mass centre)."""
    count = len(verts)
    if not count:
        return (0.0, 0.0, 0.0)
    return (sum(v[0] for v in verts) / count,
            sum(v[1] for v in verts) / count,
            sum(v[2] for v in verts) / count)
