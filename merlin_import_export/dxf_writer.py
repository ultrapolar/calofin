# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal DXF R12 (AC1009) writer with block support.

R12 is the most widely supported DXF flavour: every AutoCAD release
since 1992 reads it.  This writer emits a HEADER with the version and
drawing extents, an LTYPE and LAYER table, one BLOCK per export group
(FLOOR, WALL, STEPS, ...) containing 3D LINE entities on the marking
layers, and one INSERT per block so the groups arrive in AutoCAD as
three separate, selectable objects.  With ``use_blocks=False`` the
lines are written straight into ENTITIES instead (layers only, no
grouping).
"""

_NAME_CHARS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-$")


def sanitize_name(name, fallback="LAYER"):
    """Restrict a symbol name to what DXF R12 allows (31 chars, A-Z 0-9 _-$)."""
    cleaned = "".join(
        ch if ch in _NAME_CHARS else "_" for ch in str(name).upper()
    )
    return cleaned[:31] or fallback


def write_dxf(filepath, layers, groups, use_blocks=True):
    """Write grouped 3D line segments to an AutoCAD R12 DXF file.

    ``layers``
        Sequence of ``(layer_name, aci_color)`` tuples; every layer is
        written to the LAYER table even when it has no entities, so the
        receiving drawing always shows the full layer set.
    ``groups``
        Sequence of ``(block_name, segments_by_layer)`` tuples where
        ``segments_by_layer`` maps a layer name to a list of
        ``((x, y, z), (x, y, z))`` line segments.
    ``use_blocks``
        When True each group becomes a BLOCK definition plus an INSERT
        (one AutoCAD object per group); when False all lines are
        written directly into the ENTITIES section.
    """
    layers = [(sanitize_name(name), int(color)) for name, color in layers]
    groups = [
        (sanitize_name(name, fallback="GROUP"),
         {sanitize_name(layer): [
             (tuple(a), tuple(b)) for a, b in segments]
          for layer, segments in by_layer.items()})
        for name, by_layer in groups
    ]

    rows = []

    def tag(code, value):
        rows.append(str(code))
        rows.append(value if isinstance(value, str) else str(value))

    def coord(value):
        return "%.6f" % value

    def line(layer, a, b):
        tag(0, "LINE")
        tag(8, layer)
        tag(10, coord(a[0]))
        tag(20, coord(a[1]))
        tag(30, coord(a[2]))
        tag(11, coord(b[0]))
        tag(21, coord(b[1]))
        tag(31, coord(b[2]))

    points = [p for _n, by_layer in groups
              for segments in by_layer.values()
              for segment in segments for p in segment]
    extmin = [min((p[i] for p in points), default=0.0) for i in range(3)]
    extmax = [max((p[i] for p in points), default=0.0) for i in range(3)]

    # HEADER
    tag(0, "SECTION")
    tag(2, "HEADER")
    tag(9, "$ACADVER")
    tag(1, "AC1009")
    tag(9, "$EXTMIN")
    tag(10, coord(extmin[0]))
    tag(20, coord(extmin[1]))
    tag(30, coord(extmin[2]))
    tag(9, "$EXTMAX")
    tag(10, coord(extmax[0]))
    tag(20, coord(extmax[1]))
    tag(30, coord(extmax[2]))
    tag(0, "ENDSEC")

    # TABLES: one linetype, the full layer set
    tag(0, "SECTION")
    tag(2, "TABLES")

    tag(0, "TABLE")
    tag(2, "LTYPE")
    tag(70, 1)
    tag(0, "LTYPE")
    tag(2, "CONTINUOUS")
    tag(70, 64)
    tag(3, "Solid line")
    tag(72, 65)
    tag(73, 0)
    tag(40, "0.0")
    tag(0, "ENDTAB")

    tag(0, "TABLE")
    tag(2, "LAYER")
    tag(70, len(layers))
    for name, color in layers:
        tag(0, "LAYER")
        tag(2, name)
        tag(70, 64)
        tag(62, color)
        tag(6, "CONTINUOUS")
    tag(0, "ENDTAB")

    tag(0, "ENDSEC")

    # BLOCKS: one block per group
    if use_blocks:
        tag(0, "SECTION")
        tag(2, "BLOCKS")
        for name, by_layer in groups:
            tag(0, "BLOCK")
            tag(8, "0")
            tag(2, name)
            tag(70, 0)
            tag(10, coord(0.0))
            tag(20, coord(0.0))
            tag(30, coord(0.0))
            tag(3, name)
            for layer, segments in by_layer.items():
                for a, b in segments:
                    line(layer, a, b)
            tag(0, "ENDBLK")
            tag(8, "0")
        tag(0, "ENDSEC")

    # ENTITIES: one INSERT per block, or the raw lines
    tag(0, "SECTION")
    tag(2, "ENTITIES")
    if use_blocks:
        for name, _by_layer in groups:
            tag(0, "INSERT")
            tag(8, "0")
            tag(2, name)
            tag(10, coord(0.0))
            tag(20, coord(0.0))
            tag(30, coord(0.0))
    else:
        for _name, by_layer in groups:
            for layer, segments in by_layer.items():
                for a, b in segments:
                    line(layer, a, b)
    tag(0, "ENDSEC")

    tag(0, "EOF")

    with open(filepath, "w", encoding="ascii", errors="replace", newline="") as f:
        f.write("\r\n".join(rows))
        f.write("\r\n")
