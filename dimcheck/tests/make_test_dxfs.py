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


def line(p1, p2, layer="POOL"):
    return _pairs((0, "LINE"), (8, layer),
                  (10, p1[0]), (20, p1[1]), (30, 0.0),
                  (11, p2[0]), (21, p2[1]), (31, 0.0))


def lwpolyline(pts, layer="POOL", closed=False):
    out = _pairs((0, "LWPOLYLINE"), (8, layer), (100, "AcDbEntity"),
                 (100, "AcDbPolyline"), (90, len(pts)), (70, 1 if closed else 0))
    for x, y in pts:
        out += _pairs((10, x), (20, y))
    return out


def arc(c, r, a1, a2, layer="POOL"):
    return _pairs((0, "ARC"), (8, layer),
                  (10, c[0]), (20, c[1]), (30, 0.0),
                  (40, r), (50, a1), (51, a2))


def dim_rotated(p13, p14, meas, style="STANDARD INCHES", angle=0.0, text=""):
    """A rotated/linear dimension measuring along `angle`."""
    return _pairs((0, "DIMENSION"), (8, "DIMENSION"),
                  (2, "*D1"), (3, style),
                  (10, p14[0]), (20, p14[1]), (30, 0.0),
                  (11, (p13[0] + p14[0]) / 2), (21, (p13[1] + p14[1]) / 2), (31, 0.0),
                  (70, 32), (1, text),
                  (13, p13[0]), (23, p13[1]), (33, 0.0),
                  (14, p14[0]), (24, p14[1]), (34, 0.0),
                  (50, angle), (42, meas))


def insert(name, p, attribs=None, layer="0"):
    out = _pairs((0, "INSERT"), (8, layer),
                 (66, 1 if attribs else 0), (2, name),
                 (10, p[0]), (20, p[1]), (30, 0.0))
    for tag, val in (attribs or []):
        out += _pairs((0, "ATTRIB"), (8, layer),
                      (10, p[0]), (20, p[1]), (30, 0.0), (40, 1.0),
                      (1, val), (2, tag), (70, 0))
    if attribs:
        out += _pairs((0, "SEQEND"), (8, layer))
    return out


def block(name, body):
    return (_pairs((0, "BLOCK"), (8, "0"), (2, name), (70, 0),
                   (10, 0.0), (20, 0.0), (30, 0.0), (3, name), (1, ""))
            + body + _pairs((0, "ENDBLK"), (8, "0")))


def dxf(entities, blocks="", layers=("POOL", "DIMENSION", "Bead Track", "border", "0")):
    tables = _pairs((0, "SECTION"), (2, "TABLES"), (0, "TABLE"), (2, "LAYER"),
                    (70, len(layers)))
    for lay in layers:
        tables += _pairs((0, "LAYER"), (2, lay), (70, 0), (62, 7), (6, "CONTINUOUS"))
    tables += _pairs((0, "ENDTAB"), (0, "ENDSEC"))
    blk = _pairs((0, "SECTION"), (2, "BLOCKS")) + blocks + _pairs((0, "ENDSEC"))
    ent = _pairs((0, "SECTION"), (2, "ENTITIES")) + entities + _pairs((0, "ENDSEC"))
    return tables + blk + ent + _pairs((0, "EOF"))


# ------------------------------------------------------------- the drawings

def staircase(x=0.0, y=0.0, treads=3, rise=10.0, run=12.0, as_polyline=False):
    """Side-view profile: risers and treads, drawn top-down like the real one."""
    pts = [(x + run * treads, y + rise * (treads + 1))]
    cx, cy = pts[0]
    for _ in range(treads):
        cy -= rise
        pts.append((cx, cy))
        cx -= run
        pts.append((cx, cy))
    cy -= rise
    pts.append((cx, cy))
    if as_polyline:
        return lwpolyline(pts), pts
    out = "".join(line(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    return out, pts


def liner_blocks():
    return (block("Liner Material", _pairs((0, "TEXT"), (8, "0"),
                                           (10, 0.0), (20, 0.0), (40, 1.0),
                                           (1, "Liner Material")))
            + block("Liner Material with Step",
                    _pairs((0, "TEXT"), (8, "0"), (10, 0.0), (20, 0.0), (40, 1.0),
                           (1, "Liner Material with Step")))
            + block("Tech Title", _pairs((0, "TEXT"), (8, "0"),
                                         (10, 0.0), (20, 0.0), (40, 1.0),
                                         (1, "Tech Title")))
            + block("Step Attachment", _pairs((0, "TEXT"), (8, "0"),
                                              (10, 0.0), (20, 0.0), (40, 1.0),
                                              (1, "Step Attachment")))
            + block("Bead Step Attachment",
                    _pairs((0, "TEXT"), (8, "0"), (10, 0.0), (20, 0.0), (40, 1.0),
                           (1, "Bead Step Attachment")))
            + block("8' Straight FG Step",
                    _pairs((0, "TEXT"), (8, "0"), (10, 0.0), (20, 0.0), (40, 1.0),
                           (1, "FG Step"))))


def liner(at=(100.0, -40.0), wall="", floor="", step=None, with_step=False):
    """A liner pattern block with fillable WALL / FLOOR / STEP fields."""
    attribs = [("WALL", wall), ("FLOOR", floor)]
    if step is not None:
        attribs.append(("STEP", step))
    return insert("Liner Material with Step" if with_step else "Liner Material",
                  at, attribs)


def text(s, at=(0.0, 0.0), h=3.0):
    return _pairs((0, "TEXT"), (8, "0"), (10, at[0]), (20, at[1]), (30, 0.0),
                  (40, h), (1, s))


def title(wallht, at=(200.0, 0.0)):
    return insert("Tech Title", at, [("WallHt", wallht)])


CASES = {}


def case(name):
    def deco(fn):
        CASES[name] = fn
        return fn
    return deco


@case("stairs_ok")
def _():
    """Side view + correct 40" dim + matching WallHt + liner with step."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo
               + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 40\"")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("stairs_height_mismatch")
def _():
    """Same drawing, but the title block says 45" -> dim must be flagged."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo
               + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 45\"")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("stairs_polyline")
def _():
    """The identical side view drawn as ONE polyline."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0, as_polyline=True)
    lo, hi = pts[-1], pts[0]
    return dxf(geo
               + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 40\"")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("bench_two_treads")
def _():
    """A bench: only two treads, must still be found as a side view."""
    geo, pts = staircase(treads=2, rise=20.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo
               + dim_rotated(lo, hi, 60.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 60\"")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("wallht_varies")
def _():
    """Varies -> height not checked, nothing marked red."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo
               + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = Varies")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("wallht_multi")
def _():
    """Several heights -> report says CHECK THE WALL HEIGHT, dim left alone."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo
               + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 0\", 40\", 45\"")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("overlap_lines")
def _():
    """Two collinear lines running over each other -> one overlap pair."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + line((60.0, 0.0), (180.0, 0.0))
               + line((0.0, 50.0), (100.0, 50.0)),   # a clean line, no pair
               liner_blocks())


@case("overlap_touching_ok")
def _():
    """End-to-end lines only touch -> must NOT be reported."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + line((100.0, 0.0), (200.0, 0.0)),
               liner_blocks())


@case("dim_stray_point")
def _():
    """A dim whose definition point floats off the geometry."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + dim_rotated((0.0, 0.0), (100.0, 25.0), 100.0, style="STANDARD"),
               liner_blocks())


@case("arc_unattached")
def _():
    """An arc whose ends attach to nothing."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + arc((50.0, 60.0), 20.0, 0.0, 180.0),
               liner_blocks())


@case("liner_missing")
def _():
    """Steps drawn, no liner block at all."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 40\""),
               liner_blocks())


@case("liner_step_without_fg")
def _():
    """Steps drawn but the plain liner (no Step) is used -> warn."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 40\"")
               + insert("Liner Material", (100.0, -40.0)),
               liner_blocks())


@case("fgstep_with_liner_step")
def _():
    """A fiberglass step AND a liner carrying a Step -> warn."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 40\"")
               + insert("8' Straight FG Step", (60.0, -20.0))
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("bead_missing")
def _():
    """Bead attachment, plan-view steps, nothing on the Bead Track layer."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    plan = "".join(line((300.0 + 4 * i, 100.0 + 12.0 * i),
                        (360.0 - 4 * i, 100.0 + 12.0 * i)) for i in range(4))
    return dxf(geo + plan
               + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 40\"")
               + insert("Bead Step Attachment", (60.0, -20.0))
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


BORDER_W = 58 * 12 + 8            # 58'-8"
BORDER_H = 45 * 12 + 3 + 5 / 8    # 45'-3 5/8"


def border(scale=1.0, wscale=None, at=(0.0, 0.0)):
    """The title block frame, as a closed polyline on the border layer."""
    w = BORDER_W * (wscale if wscale is not None else scale)
    h = BORDER_H * scale
    x, y = at
    return lwpolyline([(x, y), (x + w, y), (x + w, y + h), (x, y + h)],
                      layer="border", closed=True)


@case("border_nominal")
def _():
    """Border exactly 58'-8" x 45'-3 5/8" -> OK."""
    return dxf(border(1.0) + insert("Liner Material", (100.0, 100.0)),
               liner_blocks())


@case("border_scaled_up")
def _():
    """Border at 2x -> a scaled-up multiple is fine."""
    return dxf(border(2.0) + insert("Liner Material", (100.0, 100.0)),
               liner_blocks())


@case("border_scaled_down")
def _():
    """Border at half size -> the error the report must carry."""
    return dxf(border(0.5) + insert("Liner Material", (100.0, 100.0)),
               liner_blocks())


@case("border_stretched")
def _():
    """Right height, wrong width -> out of proportion."""
    return dxf(border(1.0, wscale=1.2) + insert("Liner Material", (100.0, 100.0)),
               liner_blocks())


@case("border_missing")
def _():
    """Nothing on the border layer at all."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + insert("Liner Material", (100.0, 100.0)),
               liner_blocks())


@case("pattern_not_supplied")
def _():
    """Pattern fields reading "Not Supplied" / "#ERROR" -> wiped clean."""
    return dxf(border(1.0)
               + liner(wall="Not Supplied", floor="#ERROR", step="Tex",
                       with_step=True),
               liner_blocks())


@case("pattern_clean")
def _():
    """Real pattern names must be left exactly alone."""
    return dxf(border(1.0)
               + liner(wall="Blue Granite", floor="Mosaic Tile", step="Tex",
                       with_step=True),
               liner_blocks())


@case("wallht_zero")
def _():
    """WallHt of 0'' is nonsensical -> red, and the dim is left alone."""
    geo, pts = staircase(treads=3, rise=10.0, run=12.0)
    lo, hi = pts[-1], pts[0]
    return dxf(geo + dim_rotated(lo, hi, 40.0, angle=1.5707963267948966)
               + title("Finished Wall Ht = 0''")
               + insert("Liner Material with Step", (100.0, -40.0)),
               liner_blocks())


@case("wallht_question_asked")
def _():
    """WallHt '?' AND a 'Wall height?' note -> green, waiting on customer."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + title("Finished Wall Ht = ?\"")
               + text("Wall height?", (50.0, 60.0))
               + insert("Liner Material", (100.0, -40.0)),
               liner_blocks())


@case("wallht_question_missing")
def _():
    """WallHt '?' but nothing asks the customer -> red, add the note."""
    return dxf(line((0.0, 0.0), (100.0, 0.0))
               + title("Finished Wall Ht = ?\"")
               + insert("Liner Material", (100.0, -40.0)),
               liner_blocks())


@case("rectangle_not_sideview")
def _():
    """A small rectangle must NOT be mistaken for a side view."""
    return dxf(lwpolyline([(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)],
                          closed=True)
               + insert("Liner Material", (100.0, -40.0)),
               liner_blocks())


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
