# SPDX-License-Identifier: GPL-3.0-or-later
"""Edge classification for the layered CAD mesh DXF exporter.

Pure logic module: it deliberately imports no ``bpy`` so the whole
pipeline can be unit tested outside Blender (see ``tests/``).

The exporter splits a mesh into named groups (FLOOR / WALL / STEPS,
matched from material names) and routes every edge onto one of four
fixed AutoCAD layers based on its Blender edge markings:

=============  ==================  ============================
DXF layer      Blender marking     Meaning in the CAD process
=============  ==================  ============================
PERIMETER      Mark Sharp          outer boundary of a piece
SLICE          Mark Freestyle Edge cut lines
BASELINE       Mark Seam           fold / reference lines
WIRE           (no marking)        plain wireframe geometry
=============  ==================  ============================

When an edge carries several markings the highest layer in the table
wins (sharp beats freestyle beats seam).
"""

from collections import OrderedDict

# (layer name, AutoCAD color index) in precedence order, strongest first.
LAYER_PERIMETER = "PERIMETER"
LAYER_SLICE = "SLICE"
LAYER_BASELINE = "BASELINE"
LAYER_WIRE = "WIRE"

LAYERS = (
    (LAYER_PERIMETER, 3),   # green
    (LAYER_SLICE, 1),       # red
    (LAYER_BASELINE, 5),    # blue
    (LAYER_WIRE, 8),        # dark grey
)

# The three groups of the company design process, in output order.
GROUP_FLOOR = "FLOOR"
GROUP_WALL = "WALL"
GROUP_STEPS = "STEPS"
GROUP_UNGROUPED = "UNGROUPED"

KNOWN_GROUPS = (GROUP_FLOOR, GROUP_WALL, GROUP_STEPS)

# Substrings (matched case-insensitively, in this order) that map a
# material name onto one of the known groups.
_GROUP_KEYWORDS = (
    ("floor", GROUP_FLOOR),
    ("wall", GROUP_WALL),
    ("step", GROUP_STEPS),
)

_NAME_CHARS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-$")


def sanitize_name(name, fallback=GROUP_UNGROUPED):
    """Restrict a name to what DXF R12 allows (31 chars, A-Z 0-9 _-$)."""
    cleaned = "".join(
        ch if ch in _NAME_CHARS else "_" for ch in str(name).upper()
    )
    return cleaned[:31] or fallback


def layer_for_edge(seam=False, freestyle=False, sharp=False):
    """DXF layer name for an edge given its Blender markings.

    Precedence: sharp (PERIMETER) > freestyle (SLICE) > seam (BASELINE);
    an unmarked edge lands on WIRE.
    """
    if sharp:
        return LAYER_PERIMETER
    if freestyle:
        return LAYER_SLICE
    if seam:
        return LAYER_BASELINE
    return LAYER_WIRE


def group_for_material(material_name):
    """Map a material name onto an export group.

    Material names containing ``floor`` / ``wall`` / ``step`` (any case,
    first match in that order wins) map to the FLOOR / WALL / STEPS
    groups.  Any other material becomes its own group named after the
    material, so no geometry is silently merged or dropped.  ``None``
    (no material assigned) maps to UNGROUPED.
    """
    if not material_name:
        return GROUP_UNGROUPED
    lowered = material_name.lower()
    for keyword, group in _GROUP_KEYWORDS:
        if keyword in lowered:
            return group
    return sanitize_name(material_name)


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


def collect_segments(edge_records):
    """Sort edge records into ``{group: {layer: [segment, ...]}}``.

    ``edge_records`` is an iterable of
    ``(point_a, point_b, seam, freestyle, sharp, groups)`` tuples where
    the points are ``(x, y, z)`` coordinates and ``groups`` is the set
    of group names of the faces using the edge.  An edge shared between
    two groups (e.g. where a wall meets the floor) is written into both.

    Returns an OrderedDict: FLOOR, WALL, STEPS first (only when they
    have content), then extra material groups alphabetically, UNGROUPED
    last.  Layers within a group follow the LAYERS precedence order.
    """
    collected = {}
    for point_a, point_b, seam, freestyle, sharp, groups in edge_records:
        layer = layer_for_edge(seam=seam, freestyle=freestyle, sharp=sharp)
        segment = (tuple(point_a), tuple(point_b))
        for group in (groups or (GROUP_UNGROUPED,)):
            collected.setdefault(group, {}).setdefault(layer, []).append(
                segment)

    extras = sorted(g for g in collected
                    if g not in KNOWN_GROUPS and g != GROUP_UNGROUPED)
    order = [g for g in KNOWN_GROUPS if g in collected] + extras
    if GROUP_UNGROUPED in collected:
        order.append(GROUP_UNGROUPED)

    result = OrderedDict()
    for group in order:
        by_layer = collected[group]
        result[group] = OrderedDict(
            (name, by_layer[name]) for name, _color in LAYERS
            if name in by_layer
        )
    return result
