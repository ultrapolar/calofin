#!/usr/bin/env python3
"""Verify DroneHeightGPS.lsp logic:
1. Paren/quote balance lint of the .lsp source.
2. Transliteration of the byte-parsing algorithms (identical arithmetic)
   tested against a synthetic DJI-style JPEG (XMP + EXIF GPS IFD, LE and BE).
3. JSON number extractor tested against real-world response shapes.
"""
import struct, sys

LSP = __import__("os").path.join(__import__("os").path.dirname(__file__), "..", "drone_height_lisp", "DroneHeightGPS.lsp")

# ---------------------------------------------------------------- lint ------
def lint(path):
    depth = 0
    in_str = False
    in_comment = False
    line = 1
    src = open(path, encoding="ascii").read()  # also asserts pure-ASCII
    i = 0
    while i < len(src):
        ch = src[i]
        if ch == "\n":
            line += 1
            in_comment = False
        elif in_comment:
            pass
        elif in_str:
            if ch == "\\":
                i += 1
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == ";":
            in_comment = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                raise SystemExit(f"LINT FAIL: extra ')' at line {line}")
        i += 1
    if in_str:
        raise SystemExit("LINT FAIL: unterminated string")
    if depth != 0:
        raise SystemExit(f"LINT FAIL: {depth} unclosed '('")
    print("lint: parens/strings balanced, pure ASCII  OK")

# ------------------------------------------------- LISP mirrors -------------
# Mirror of ddg-scan-to (state machine incl. its reset rule)
def scan_to(lst, tgt):
    tlen, m = len(tgt), 0
    i = 0
    n = len(lst)
    while i < n and m < tlen:
        b = lst[i]; i += 1
        if b < 0: b += 256
        if b == tgt[m]:
            m += 1
        else:
            m = 1 if b == tgt[0] else 0
    return lst[i:] if m == tlen else None

def grab_text(lst, n):
    out = []
    for b in lst[:n]:
        if b < 0: b += 256
        out.append(chr(b) if 31 < b < 127 else " ")
    return "".join(out)

def xmp_text(lst):
    rest = scan_to(lst, [ord(c) for c in "ns.adobe.com/xap/1.0/"])
    return grab_text(rest, 6144) if rest is not None else ""

def xmp_attr(txt, tag):
    pos = txt.find(tag + '="')
    if pos < 0: return None
    rest = txt[pos + len(tag) + 2:]          # LISP substr (+ pos (strlen tag) 3), 1-based
    end = rest.find('"')
    return rest[:end] if end >= 0 else None

def numstr(s):
    s = s.strip(" ")
    if s.startswith("+"): s = s[1:]
    if not s: return None
    try: return float(s)
    except ValueError: return None

def xmp_num(txt, tag):
    s = xmp_attr(txt, tag)
    return numstr(s) if s is not None else None

def bb(lst, off):
    if 0 <= off < len(lst):
        b = lst[off]
        return b + 256 if b < 0 else b
    return None            # (nth off lst) -> nil past the end

def u16(lst, off, le):
    a, b = bb(lst, off), bb(lst, off + 1)
    if a is None or b is None: return None
    return a + 256 * b if le else 256 * a + b

def u32(lst, off, le):
    a, b, c, d = (bb(lst, off), bb(lst, off+1), bb(lst, off+2), bb(lst, off+3))
    if None in (a, b, c, d): return None
    return float(a + 256*b + 65536*c + 16777216*d) if le else float(d + 256*c + 65536*b + 16777216*a)

def u32i(lst, off, le):
    r = u32(lst, off, le)
    return int(r) if r is not None and r < 1.0e9 else None

def rat(lst, off, le):
    if off is None: return None
    n, d = u32(lst, off, le), u32(lst, off + 4, le)
    if n is None or d is None or d == 0.0: return None
    return n / d

def ifd_find(lst, ifd, le, tag):
    n = u16(lst, ifd, le)
    if n is None: return None
    for i in range(n):
        e = ifd + 2 + 12 * i
        if u16(lst, e, le) == tag:
            return e
    return None

def gps_coord(lst, ent, le):
    off = u32i(lst, ent + 8, le)
    if off is None: return None
    d, m, s = rat(lst, off, le), rat(lst, off + 8, le), rat(lst, off + 16, le)
    if None in (d, m, s): return None
    return d + m / 60.0 + s / 3600.0

def exif_gps(lst):
    lat = lon = altm = None
    tif = scan_to(lst, [ord(c) for c in "Exif"])
    if tif is not None and bb(tif, 0) == 0 and bb(tif, 1) == 0:
        tif = tif[2:]
        b0, b1 = bb(tif, 0), bb(tif, 1)
        ord_ = "LE" if (b0 == 73 and b1 == 73) else ("BE" if (b0 == 77 and b1 == 77) else None)
        if ord_:
            le = ord_ == "LE"
            ifd0 = u32i(tif, 4, le)
            ent = ifd_find(tif, ifd0, le, 0x8825) if ifd0 is not None else None
            gps = u32i(tif, ent + 8, le) if ent is not None else None
            if gps is not None:
                ent = ifd_find(tif, gps, le, 2)
                if ent is not None: lat = gps_coord(tif, ent, le)
                ent = ifd_find(tif, gps, le, 1)
                if lat is not None and ent is not None and bb(tif, ent + 8) == 83:
                    lat = -lat
                ent = ifd_find(tif, gps, le, 4)
                if ent is not None: lon = gps_coord(tif, ent, le)
                ent = ifd_find(tif, gps, le, 3)
                if lon is not None and ent is not None and bb(tif, ent + 8) == 87:
                    lon = -lon
                ent = ifd_find(tif, gps, le, 6)
                if ent is not None: altm = rat(tif, u32i(tif, ent + 8, le), le)
                ent = ifd_find(tif, gps, le, 5)
                if altm is not None and ent is not None and bb(tif, ent + 8) == 1:
                    altm = -altm
    return (lat, lon, altm)

def json_num(txt, key):
    pos = txt.find('"' + key + '"')
    if pos < 0: return None
    rest = txt[pos + len(key) + 2:]          # LISP: (substr txt (+ pos (strlen key) 3))
    i = 0
    while i < len(rest) and rest[i] in ' :"\t':
        i += 1
    num = ""
    while i < len(rest) and rest[i] in "-+.0123456789eE":
        num += rest[i]; i += 1
    return numstr(num) if num else None

# -------------------------------------------- synthetic DJI JPEG ------------
def build_exif_app1(le=True):
    E = "<" if le else ">"
    order = b"II" if le else b"MM"

    def ent(tag, typ, cnt, val4):
        return struct.pack(E + "HHI", tag, typ, cnt) + val4

    # TIFF header (8) + IFD0 + GPS IFD + data area; all offsets from TIFF start
    ifd0_off = 8
    ifd0_n = 2
    gps_ifd_off = ifd0_off + 2 + ifd0_n * 12 + 4          # 38
    gps_n = 7
    data_off = gps_ifd_off + 2 + gps_n * 12 + 4           # 128

    def rat_bytes(pairs):
        return b"".join(struct.pack(E + "II", n, d) for n, d in pairs)

    lat_off = data_off                                     # 3 rationals = 24 B
    lon_off = lat_off + 24
    alt_off = lon_off + 24

    ifd0 = struct.pack(E + "H", ifd0_n)
    ifd0 += ent(0x0110, 2, 4, b"DJI\x00")                  # Model, inline
    ifd0 += ent(0x8825, 4, 1, struct.pack(E + "I", gps_ifd_off))
    ifd0 += struct.pack(E + "I", 0)                        # next-IFD ptr

    gps = struct.pack(E + "H", gps_n)
    gps += ent(0, 1, 4, b"\x02\x03\x00\x00")               # GPSVersionID
    gps += ent(1, 2, 2, b"N\x00\x00\x00")                  # LatRef
    gps += ent(2, 5, 3, struct.pack(E + "I", lat_off))     # Lat: 3 rationals
    gps += ent(3, 2, 2, b"W\x00\x00\x00")                  # LonRef
    gps += ent(4, 5, 3, struct.pack(E + "I", lon_off))     # Lon
    gps += ent(5, 1, 1, b"\x00\x00\x00\x00")               # AltRef: above sea
    gps += ent(6, 5, 1, struct.pack(E + "I", alt_off))     # Alt: 1 rational
    gps += struct.pack(E + "I", 0)

    # 32 42' 56.6568" N,  117 09' 39.9016" W, 123.456 m
    data = rat_bytes([(32, 1), (42, 1), (566568, 10000)])
    data += rat_bytes([(117, 1), (9, 1), (399016, 10000)])
    data += rat_bytes([(123456, 1000)])

    tiff = order + struct.pack(E + "H", 42) + struct.pack(E + "I", ifd0_off) + ifd0 + gps + data
    body = b"Exif\x00\x00" + tiff
    return b"\xff\xe1" + struct.pack(">H", len(body) + 2) + body

def build_xmp_app1(lon_tag="GpsLongtitude"):
    xmp = (b"http://ns.adobe.com/xap/1.0/\x00"
           b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
           b'<rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" '
           b'drone-dji:AbsoluteAltitude="+123.45" '
           b'drone-dji:RelativeAltitude="+30.50" '
           b'drone-dji:GpsLatitude="+32.7157380" '
           b'drone-dji:' + lon_tag.encode() + b'="-117.1610838" '
           b'drone-dji:GimbalPitchDegree="-89.90"/></rdf:RDF></x:xmpmeta>')
    return b"\xff\xe1" + struct.pack(">H", len(xmp) + 2) + xmp

def build_jpg(with_xmp=True, le=True, lon_tag="GpsLongtitude"):
    out = b"\xff\xd8" + build_exif_app1(le)
    if with_xmp:
        out += build_xmp_app1(lon_tag)
    # junk incl. 0x1A bytes (kills text-mode reads) and a decoy FF E1
    out += b"\xff\xdb" + struct.pack(">H", 6) + b"\x1a\x00\x1a\x00"
    out += b"\xff\xe1" + struct.pack(">H", 8) + b"NOPE\x1a\x00"
    out += bytes(range(256)) * 4
    return out

def approx(a, b, tol=1e-6):
    return a is not None and abs(a - b) < tol

def main():
    lint(LSP)
    failures = []

    def check(name, ok):
        print(("PASS  " if ok else "FAIL  ") + name)
        if not ok: failures.append(name)

    LAT = 32 + 42/60 + 56.6568/3600          # 32.715738
    LON = -(117 + 9/60 + 39.9016/3600)       # -117.16108...

    # --- XMP route (with DJI's GpsLongtitude typo) ---
    lst = list(build_jpg())
    t = xmp_text(lst)
    check("xmp AbsoluteAltitude", approx(xmp_num(t, "AbsoluteAltitude"), 123.45))
    check("xmp RelativeAltitude", approx(xmp_num(t, "RelativeAltitude"), 30.50))
    check("xmp GpsLatitude", approx(xmp_num(t, "GpsLatitude"), 32.7157380))
    check("xmp GpsLongitude absent -> None", xmp_num(t, "GpsLongitude") is None)
    v = xmp_num(t, "GpsLongitude")
    if v is None: v = xmp_num(t, "GpsLongtitude")
    check("xmp longitude via typo fallback", approx(v, -117.1610838))

    # --- correctly-spelt variant ---
    lst2 = list(build_jpg(lon_tag="GpsLongitude"))
    t2 = xmp_text(lst2)
    check("xmp GpsLongitude (correct spelling)", approx(xmp_num(t2, "GpsLongitude"), -117.1610838))

    # --- EXIF route, little-endian (no XMP in file) ---
    lst3 = list(build_jpg(with_xmp=False, le=True))
    check("no-XMP file -> xmp_text empty", xmp_text(lst3) == "")
    la, lo, al = exif_gps(lst3)
    check("exif LE latitude", approx(la, LAT))
    check("exif LE longitude (W negative)", approx(lo, LON))
    check("exif LE altitude", approx(al, 123.456))

    # --- EXIF route, big-endian ---
    lst4 = list(build_jpg(with_xmp=False, le=False))
    la, lo, al = exif_gps(lst4)
    check("exif BE latitude", approx(la, LAT))
    check("exif BE longitude", approx(lo, LON))
    check("exif BE altitude", approx(al, 123.456))

    # --- EXIF parse also works when XMP present (fallback never harms) ---
    la, lo, al = exif_gps(lst)
    check("exif parse with XMP present", approx(la, LAT) and approx(lo, LON))

    # --- signed-byte input (some ADODB builds return signed) ---
    lst5 = [b - 256 if b > 127 else b for b in build_jpg()]
    t5 = xmp_text(lst5)
    check("signed bytes: xmp still parses", approx(xmp_num(t5, "AbsoluteAltitude"), 123.45))
    la, lo, al = exif_gps([b - 256 if b > 127 else b for b in build_jpg(with_xmp=False)])
    check("signed bytes: exif still parses", approx(la, LAT) and approx(al, 123.456))

    # --- truncated file: must return Nones, not crash ---
    la, lo, al = exif_gps(list(build_jpg(with_xmp=False))[:80])
    check("truncated file -> graceful Nones", lo is None and al is None)

    # --- JSON extractor against real response shapes ---
    epqs = '{"location":{"x":-117.161,"y":32.7157,"spatialReference":{"wkid":4326,"latestWkid":4326}},"locationId":0,"value":"296.606","rasterId":68360,"resolution":1}'
    check("json EPQS quoted value", approx(json_num(epqs, "value"), 296.606))
    epqs2 = '{"value": 57.99, "rasterId": 1}'
    check("json EPQS bare value", approx(json_num(epqs2, "value"), 57.99))
    epqs3 = '{"value": "-1000000", "rasterId": 1}'
    check("json EPQS no-data sentinel parses (range filter rejects later)",
          approx(json_num(epqs3, "value"), -1000000.0))
    otd = '{"results": [{"dataset": "ned10m", "elevation": 89.5, "location": {"lat": 32.7157, "lng": -117.161}}], "status": "OK"}'
    check("json OpenTopoData elevation", approx(json_num(otd, "elevation"), 89.5))
    otd_null = '{"results": [{"dataset": "ned10m", "elevation": null, "location": {}}], "status": "OK"}'
    check("json null elevation -> None", json_num(otd_null, "elevation") is None)
    oel = '{"results": [{"latitude": 32.7157, "longitude": -117.161, "elevation": 88.0}]}'
    check("json Open-Elevation", approx(json_num(oel, "elevation"), 88.0))
    check("json missing key -> None", json_num(oel, "value") is None)

    # --- height math sanity ---
    absft = 123.45 * 3.280839895
    gft = 296.606
    hgps = absft - gft
    check("height math example", approx(hgps, 123.45 * 3.280839895 - 296.606))

    print()
    if failures:
        print(f"{len(failures)} FAILURES: {failures}")
        sys.exit(1)
    print("ALL CHECKS PASSED")

if __name__ == "__main__":
    main()
