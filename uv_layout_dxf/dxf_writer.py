# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal DXF R12 (AC1009) writer.

R12 with classic POLYLINE/VERTEX entities is the most widely supported
DXF flavour: every AutoCAD release since 1992 reads it, as do LibreCAD,
QCAD, Inkscape and most laser/CNC toolchains.  Only what AutoCAD needs
is emitted: a HEADER with the version and drawing extents, an LTYPE and
LAYER table, and closed 2D polylines in the ENTITIES section.
"""

_LAYER_NAME_CHARS = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-$")


def sanitize_layer_name(name, fallback="UVLAYOUT"):
    """Restrict a layer name to what DXF R12 allows (31 chars, A-Z 0-9 _-$)."""
    cleaned = "".join(
        ch if ch in _LAYER_NAME_CHARS else "_" for ch in name.upper()
    )
    return cleaned[:31] or fallback


def write_dxf(filepath, layers):
    """Write closed outlines to an AutoCAD R12 DXF file.

    ``layers`` is a sequence of ``(layer_name, aci_color, outlines)``
    tuples, where each outline is a sequence of ``(x, y)`` points
    describing one closed polygon.
    """
    layers = [
        (sanitize_layer_name(name), int(color), [list(o) for o in outlines])
        for name, color, outlines in layers
    ]

    rows = []

    def tag(code, value):
        rows.append(str(code))
        rows.append(value if isinstance(value, str) else str(value))

    def coord(value):
        return "%.6f" % value

    points = [p for _n, _c, outlines in layers for o in outlines for p in o]
    min_x = min((p[0] for p in points), default=0.0)
    min_y = min((p[1] for p in points), default=0.0)
    max_x = max((p[0] for p in points), default=0.0)
    max_y = max((p[1] for p in points), default=0.0)

    # HEADER
    tag(0, "SECTION")
    tag(2, "HEADER")
    tag(9, "$ACADVER")
    tag(1, "AC1009")
    tag(9, "$EXTMIN")
    tag(10, coord(min_x))
    tag(20, coord(min_y))
    tag(30, coord(0.0))
    tag(9, "$EXTMAX")
    tag(10, coord(max_x))
    tag(20, coord(max_y))
    tag(30, coord(0.0))
    tag(0, "ENDSEC")

    # TABLES: one linetype, one layer per entry in `layers`
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
    for name, color, _outlines in layers:
        tag(0, "LAYER")
        tag(2, name)
        tag(70, 64)
        tag(62, color)
        tag(6, "CONTINUOUS")
    tag(0, "ENDTAB")

    tag(0, "ENDSEC")

    # ENTITIES: one closed POLYLINE per outline
    tag(0, "SECTION")
    tag(2, "ENTITIES")
    for name, _color, outlines in layers:
        for outline in outlines:
            tag(0, "POLYLINE")
            tag(8, name)
            tag(66, 1)  # vertices follow
            tag(70, 1)  # closed polyline
            for x, y in outline:
                tag(0, "VERTEX")
                tag(8, name)
                tag(10, coord(x))
                tag(20, coord(y))
                tag(30, coord(0.0))
            tag(0, "SEQEND")
            tag(8, name)
    tag(0, "ENDSEC")

    tag(0, "EOF")

    with open(filepath, "w", encoding="ascii", errors="replace", newline="") as f:
        f.write("\r\n".join(rows))
        f.write("\r\n")
