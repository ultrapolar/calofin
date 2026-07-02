# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal mock of the bmesh data structures used by the exporter.

Builds vert/edge/loop/face networks with the same attribute names and
semantics as bmesh (link_loops, link_faces, link_loop_next, loop[uv].uv)
so uv_layout.py can be exercised without Blender.
"""

from mathutils import Vector

# Sentinel object standing in for the bmesh UV layer key.
UV_LAYER = object()


class MockUV:
    __slots__ = ("uv",)

    def __init__(self, u, v):
        self.uv = Vector((u, v))


class MockVert:
    __slots__ = ("index", "co")

    def __init__(self, index, co):
        self.index = index
        self.co = Vector(co)


class MockEdge:
    __slots__ = ("index", "verts", "link_loops", "link_faces")

    def __init__(self, index, verts):
        self.index = index
        self.verts = verts
        self.link_loops = []
        self.link_faces = []


class MockLoop:
    __slots__ = ("vert", "face", "edge", "link_loop_next", "_layers")

    def __init__(self, vert, face):
        self.vert = vert
        self.face = face
        self.edge = None
        self.link_loop_next = None
        self._layers = {}

    def __getitem__(self, layer):
        return self._layers[layer]


class MockFace:
    __slots__ = ("index", "loops", "verts")

    def __init__(self, index, loops):
        self.index = index
        self.loops = loops
        self.verts = [l.vert for l in loops]

    def calc_area(self):
        # Fan triangulation from the first vertex (planar faces).
        origin = self.verts[0].co
        area = 0.0
        for i in range(1, len(self.verts) - 1):
            a = self.verts[i].co - origin
            b = self.verts[i + 1].co - origin
            cx = a.y * b.z - a.z * b.y
            cy = a.z * b.x - a.x * b.z
            cz = a.x * b.y - a.y * b.x
            area += 0.5 * (cx * cx + cy * cy + cz * cz) ** 0.5
        return area


class MockBMesh:
    __slots__ = ("verts", "edges", "faces")

    def __init__(self):
        self.verts = []
        self.edges = []
        self.faces = []


def build_mesh(vert_coords, faces, face_uvs):
    """Build a mock bmesh.

    vert_coords: [(x, y, z), ...]
    faces:       [(vert_index, ...), ...] loops in winding order
    face_uvs:    [[(u, v), ...], ...] one UV per loop, same order as faces
    """
    bm = MockBMesh()
    bm.verts = [MockVert(i, co) for i, co in enumerate(vert_coords)]
    edge_map = {}

    for face_index, vert_ids in enumerate(faces):
        loops = [MockLoop(bm.verts[vi], None) for vi in vert_ids]
        face = MockFace(face_index, loops)
        count = len(loops)
        for k, loop in enumerate(loops):
            loop.face = face
            loop.link_loop_next = loops[(k + 1) % count]
            u, v = face_uvs[face_index][k]
            loop._layers[UV_LAYER] = MockUV(u, v)
        for k in range(count):
            a, b = vert_ids[k], vert_ids[(k + 1) % count]
            key = (min(a, b), max(a, b))
            edge = edge_map.get(key)
            if edge is None:
                edge = MockEdge(len(edge_map), (bm.verts[a], bm.verts[b]))
                edge_map[key] = edge
            loops[k].edge = edge
            edge.link_loops.append(loops[k])
            if face not in edge.link_faces:
                edge.link_faces.append(face)
        bm.faces.append(face)

    bm.edges = sorted(edge_map.values(), key=lambda e: e.index)
    return bm
