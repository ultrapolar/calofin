#!/usr/bin/env python3
"""Generate the DIMCHECK test drawings.

Writes one minimal DXF per scenario into ./dxf/. Each drawing isolates
one rule so a DIMSCAN report can be checked against a known answer --
see expected.md for what each one should say.

    python3 make_test_dxfs.py

No dependencies; the DXF is written by hand (R12-style entities, which
every AutoCAD release and accoreconsole reads).
"""

import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dxf")

# ---------------------------------------------------------------- DXF bits


def _pairs(*items):
    return "".join(f"{code}\n{value}\n" for code, value in items)


def line(p1, p2, layer="0"):
    return _pairs((0, "LINE"), (8, layer),
                  (10, p1[0]), (20, p1[1]), (30, 0.0),
                  (11, p2[0]), (21, p2[1]), (31, 0.0))


def lwpolyline(pts, layer="0", closed=False):
    out = _pairs((0, "LWPOLYLINE"), (8, layer), (100, "AcDbEntity"),
                 (100, "AcDbPolyline"), (90, len(pts)), (70, 1 if closed else 0))
    for x, y in pts:
        out += _pairs((10, x), (20, y))
    return out


def arc(c, r, a1, a2, layer="0"):
    return _pairs((0, "ARC"), (8, layer),
                  (10, c[0]), (20, c[1]), (30, 0.0),
                  (40, r), (50, a1), (51, a2))


def dim_rotated(p13, p14, meas, style="STANDARD", angle=0.0, text=""):
    """A rotated/linear dimension measuring along `angle`."""
    return _pairs((0, "DIMENSION"), (8, "DIMENSION"),
                  (2, "*D1"), (3, style),
                  (10, p14[0]), (20, p14[1]), (30, 0.0),
                  (11, (p13[0] + p14[0]) / 2), (21, (p13[1] + p14[1]) / 2), (31, 0.0),
                  (70, 32), (1, text),
                  (13, p13[0]), (23, p13[1]), (33, 0.0),
                  (14, p14[0]), (24, p14[1]), (34, 0.0),
                  (50, angle), (42, meas))


def dxf(entities, layers=("DIMENSION", "0")):
    tables = _pairs((0, "SECTION"), (2, "TABLES"), (0, "TABLE"), (2, "LAYER"),
                    (70, len(layers)))
    for lay in layers:
        tables += _pairs((0, "LAYER"), (2, lay), (70, 0), (62, 7), (6, "CONTINUOUS"))
    tables += _pairs((0, "ENDTAB"), (0, "ENDSEC"))
    ent = _pairs((0, "SECTION"), (2, "ENTITIES")) + entities + _pairs((0, "ENDSEC"))
    return tables + ent + _pairs((0, "EOF"))


# ------------------------------------------------------------- the drawings

CASES = {}


def case(name):
    def deco(fn):
        CASES[name] = fn
        return fn
    return deco


@case("dim_stray_point")
def _():
    """A dim whose definition point floats off the geometry."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + dim_rotated((0.0, 0.0), (100.0, 25.0), 100.0, style="STANDARD"))


@case("dim_attached_ok")
def _():
    """A dim whose points both sit on the line - the all-clear case."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + dim_rotated((0.0, 0.0), (100.0, 0.0), 100.0, style="STANDARD"))


@case("dim_shared_anchor")
def _():
    """Two dims measuring to the same floating corner - the hypotenuse
    case. The shared point is an anchor and must NOT be reported; the
    third dim's point really is a stray and must be."""
    corner = (100.0, 0.0)
    return dxf(line((0.0, 0.0), (60.0, 0.0))              # bottom run
               + line((100.0, 40.0), (100.0, 100.0))      # right-hand run
               + dim_rotated((0.0, 0.0), corner, 100.0, style="STANDARD")
               + dim_rotated((100.0, 100.0), corner, 100.0, style="STANDARD",
                             angle=90.0)
               + dim_rotated((10.0, 0.0), (40.0, 15.0), 30.0,
                             style="STANDARD"))


@case("arc_unattached")
def _():
    """An arc whose ends attach to nothing."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + arc((50.0, 60.0), 20.0, 0.0, 180.0))


@case("arc_attached_ok")
def _():
    """An arc whose ends both land on other objects' ends."""
    return dxf(line((0.0, 0.0), (0.0, 30.0))
               + line((100.0, 0.0), (100.0, 30.0))
               + arc((50.0, 30.0), 50.0, 180.0, 0.0))


@case("overlap_lines")
def _():
    """Two collinear lines running over each other -> one overlap pair."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + line((60.0, 0.0), (180.0, 0.0))
               + line((0.0, 50.0), (100.0, 50.0)))   # a clean line, no pair


@case("overlap_touching_ok")
def _():
    """End-to-end lines only touch -> must NOT be reported."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + line((100.0, 0.0), (200.0, 0.0)))


@case("overlap_polyline_edges")
def _():
    """The overlap runs through one side of an LWPOLYLINE - segment
    decomposition must catch it exactly like a plain LINE would."""
    return dxf(lwpolyline([(0.0, 0.0), (100.0, 0.0), (100.0, 50.0), (0.0, 50.0)],
                          closed=True)
               + line((60.0, 0.0), (140.0, 0.0)))


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in sorted(CASES.items()):
        path = os.path.join(OUT, name + ".dxf")
        with open(path, "w", newline="\n") as fh:
            fh.write(fn())
        print("wrote", os.path.relpath(path, os.path.dirname(OUT)))
    print(f"\n{len(CASES)} test drawings in {OUT}")


if __name__ == "__main__":
    main()
