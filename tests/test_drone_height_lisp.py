#!/usr/bin/env python3
"""Verify DroneHeightGPS.lsp logic:
1. Paren/quote balance lint of the .lsp source.
2. Transliteration of the byte-parsing algorithms (identical arithmetic)
   tested against synthetic DJI-style images: JPEG (APP1 EXIF + APP1 XMP),
   PNG (eXIf chunk + iTXt XMP, front- or tail-of-file), bare TIFF; XMP in
   both attribute and element serialisation; LE and BE byte orders.
3. JSON number extractor tested against real-world response shapes.
"""
import os, struct, sys, zlib

LSP = os.path.join(os.path.dirname(__file__), "..",
                   "drone_height_lisp", "DroneHeightGPS.lsp")

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

# Mirror of ddg-xmp-text: anchor chain <x:xmpmeta -> APP1 URI -> drone-dji:
def xmp_text(lst):
    rest = scan_to(lst, [ord(c) for c in "<x:xmpmeta"])
    if rest is None:
        rest = scan_to(lst, [ord(c) for c in "ns.adobe.com/xap/1.0/"])
    if rest is None:
        rest = scan_to(lst, [ord(c) for c in "drone-dji:"])
    return grab_text(rest, 6144) if rest is not None else ""

# Mirror of ddg-xmp-attr: attribute form Tag="..." then element form <Tag>...<
def xmp_attr(txt, tag):
    pos = txt.find(tag + '="')
    if pos >= 0:
        rest = txt[pos + len(tag) + 2:]      # LISP substr (+ pos (strlen tag) 3), 1-based
        end = rest.find('"')
        return rest[:end] if end >= 0 else None
    pos = txt.find(tag + ">")
    if pos >= 0:
        rest = txt[pos + len(tag) + 1:]      # LISP substr (+ pos (strlen tag) 2), 1-based
        end = rest.find("<")
        return rest[:end] if end >= 0 else None
    return None

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

# Mirror of ddg-tiff-at
def tiff_at(rest):
    b0, b1 = bb(rest, 0), bb(rest, 1)
    if b0 == 73 and b1 == 73 and bb(rest, 2) == 42 and bb(rest, 3) == 0:
        return rest
    if b0 == 77 and b1 == 77 and bb(rest, 2) == 0 and bb(rest, 3) == 42:
        return rest
    return None

# Mirror of ddg-find-tiff: bare TIFF, JPEG "Exif\0\0", PNG eXIf chunk;
# false matches without a valid TIFF magic are skipped
def find_tiff(lst):
    tif = tiff_at(lst)
    rest = lst
    while tif is None:
        rest = scan_to(rest, [ord(c) for c in "Exif"])
        if rest is None: break
        if bb(rest, 0) == 0 and bb(rest, 1) == 0:
            tif = tiff_at(rest[2:])
    rest = lst
    while tif is None:
        rest = scan_to(rest, [ord(c) for c in "eXIf"])
        if rest is None: break
        tif = tiff_at(rest)
    return tif

def exif_gps(lst):
    lat = lon = altm = None
    tif = find_tiff(lst)
    if tif is not None:
        le = bb(tif, 0) == 73
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
    return (lat, lon, altm, tif is not None)   # 4th: EXIF block found at all?

# Mirror of ddg-read-meta: XMP first, EXIF fills the gaps; the flags say
# whether each metadata container was present at all
def read_meta(lst):
    t = xmp_text(lst)
    xmpf = len(t) > 0
    tiff = None
    absm = xmp_num(t, "AbsoluteAltitude")
    relm = xmp_num(t, "RelativeAltitude")
    lat = xmp_num(t, "GpsLatitude")
    lon = xmp_num(t, "GpsLongitude")
    if lon is None: lon = xmp_num(t, "GpsLongtitude")
    if lat is None or lon is None or absm is None:
        e = exif_gps(lst)
        if lat is None: lat = e[0]
        if lon is None: lon = e[1]
        if absm is None: absm = e[2]
        tiff = e[3]
    return (absm, relm, lat, lon, xmpf, tiff)

def read_meta4(lst):
    return read_meta(lst)[:4]

# Mirror of DDGPS's failure-classification cond (step 2b in the command)
def classify(absm, relm, lat, lon, xmpf, tiff):
    if (lat is None or lon is None) and not xmpf and not tiff:
        return "NO_METADATA"
    if lat is None or lon is None:
        return "NO_GPS_DATA"
    if abs(lat - 0.0) < 1e-9 and abs(lon - 0.0) < 1e-9:
        return "NO_FIX"
    if abs(lat) > 90.0 or abs(lon) > 180.0:
        return "BAD_GPS"
    if absm is None and relm is None:
        return "NO_ALTITUDE"
    return "OK"

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

# -------------------------------------------- synthetic DJI images ----------
# 32 42' 56.6568" N,  117 09' 39.9016" W, 123.456 m
LAT = 32 + 42/60 + 56.6568/3600
LON = -(117 + 9/60 + 39.9016/3600)

def build_tiff(le=True, with_gps=True):
    E = "<" if le else ">"
    order = b"II" if le else b"MM"

    def ent(tag, typ, cnt, val4):
        return struct.pack(E + "HHI", tag, typ, cnt) + val4

    ifd0_off = 8
    ifd0_n = 2 if with_gps else 1
    gps_ifd_off = ifd0_off + 2 + ifd0_n * 12 + 4          # 38 when with_gps
    gps_n = 7
    data_off = gps_ifd_off + 2 + gps_n * 12 + 4           # 128 when with_gps

    def rat_bytes(pairs):
        return b"".join(struct.pack(E + "II", n, d) for n, d in pairs)

    lat_off = data_off                                     # 3 rationals = 24 B
    lon_off = lat_off + 24
    alt_off = lon_off + 24

    ifd0 = struct.pack(E + "H", ifd0_n)
    ifd0 += ent(0x0110, 2, 4, b"DJI\x00")                  # Model, inline
    if with_gps:
        ifd0 += ent(0x8825, 4, 1, struct.pack(E + "I", gps_ifd_off))
    ifd0 += struct.pack(E + "I", 0)                        # next-IFD ptr
    if not with_gps:                                       # EXIF without GPS
        return order + struct.pack(E + "H", 42) + struct.pack(E + "I", ifd0_off) + ifd0

    gps = struct.pack(E + "H", gps_n)
    gps += ent(0, 1, 4, b"\x02\x03\x00\x00")               # GPSVersionID
    gps += ent(1, 2, 2, b"N\x00\x00\x00")                  # LatRef
    gps += ent(2, 5, 3, struct.pack(E + "I", lat_off))     # Lat: 3 rationals
    gps += ent(3, 2, 2, b"W\x00\x00\x00")                  # LonRef
    gps += ent(4, 5, 3, struct.pack(E + "I", lon_off))     # Lon
    gps += ent(5, 1, 1, b"\x00\x00\x00\x00")               # AltRef: above sea
    gps += ent(6, 5, 1, struct.pack(E + "I", alt_off))     # Alt: 1 rational
    gps += struct.pack(E + "I", 0)

    data = rat_bytes([(32, 1), (42, 1), (566568, 10000)])
    data += rat_bytes([(117, 1), (9, 1), (399016, 10000)])
    data += rat_bytes([(123456, 1000)])

    return order + struct.pack(E + "H", 42) + struct.pack(E + "I", ifd0_off) + ifd0 + gps + data

def xmp_packet(element_form=False, lon_tag="GpsLongtitude", gps=True, alts=True,
               lat_s=b"+32.7157380", lon_s=b"-117.1610838"):
    lt = lon_tag.encode()
    head = (b'<?xpacket begin="\xef\xbb\xbf" id="W5M0MpCehiHzreSzNTczkc9d"?>'
            b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
            b'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">')
    tail = b"</rdf:RDF></x:xmpmeta><?xpacket end=\"w\"?>"
    if element_form:
        body = (b'<rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/">'
                b"<drone-dji:AbsoluteAltitude>+123.45</drone-dji:AbsoluteAltitude>"
                b"<drone-dji:RelativeAltitude>+30.50</drone-dji:RelativeAltitude>"
                b"<drone-dji:GpsLatitude>+32.7157380</drone-dji:GpsLatitude>"
                b"<drone-dji:" + lt + b">-117.1610838</drone-dji:" + lt + b">"
                b"</rdf:Description>")
    else:
        parts = [b'<rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"']
        if alts:
            parts.append(b'drone-dji:AbsoluteAltitude="+123.45"')
            parts.append(b'drone-dji:RelativeAltitude="+30.50"')
        if gps:
            parts.append(b'drone-dji:GpsLatitude="' + lat_s + b'"')
            parts.append(b'drone-dji:' + lt + b'="' + lon_s + b'"')
        parts.append(b'drone-dji:GimbalPitchDegree="-89.90"/>')
        body = b" ".join(parts)
    return head + body + tail

def build_jpg(with_xmp=True, le=True, lon_tag="GpsLongtitude"):
    body = b"Exif\x00\x00" + build_tiff(le)
    out = b"\xff\xd8" + b"\xff\xe1" + struct.pack(">H", len(body) + 2) + body
    if with_xmp:
        xmp = b"http://ns.adobe.com/xap/1.0/\x00" + xmp_packet(lon_tag=lon_tag)
        out += b"\xff\xe1" + struct.pack(">H", len(xmp) + 2) + xmp
    # junk incl. 0x1A bytes (kills text-mode reads) and a decoy FF E1
    out += b"\xff\xdb" + struct.pack(">H", 6) + b"\x1a\x00\x1a\x00"
    out += b"\xff\xe1" + struct.pack(">H", 8) + b"NOPE\x1a\x00"
    out += bytes(range(256)) * 4
    return out

def png_chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

def build_png(with_xmp=True, with_exif=True, element_form=False, meta_at_end=False,
              exif_with_gps=True, **xmpkw):
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = png_chunk(b"IHDR", struct.pack(">IIBBBBB", 640, 480, 8, 2, 0, 0, 0))
    meta = b""
    if with_xmp:
        itxt = b"XML:com.adobe.xmp\x00\x00\x00\x00\x00" + xmp_packet(element_form, **xmpkw)
        meta += png_chunk(b"iTXt", itxt)
    if with_exif:
        meta += png_chunk(b"eXIf", build_tiff(le=True, with_gps=exif_with_gps))
    # compressed-looking junk with DECOY anchors: a bare "Exif" not followed by
    # \0\0+TIFF and a bare "eXIf" not followed by a TIFF magic - the parser
    # must skip both and still find the real chunks that come AFTER
    junk = b"\x1a\x00Exif??junk\x1a\xffeXIfNOPE" + bytes(range(256)) * 8
    idat = png_chunk(b"IDAT", junk)
    iend = png_chunk(b"IEND", b"")
    if meta_at_end:
        big = png_chunk(b"IDAT", bytes(300000))   # pushes meta past 256 KB
        return sig + ihdr + idat + big + meta + iend
    return sig + ihdr + idat + meta + iend        # decoys BEFORE real chunks

def approx(a, b, tol=1e-6):
    return a is not None and abs(a - b) < tol

def main():
    lint(LSP)
    failures = []

    def check(name, ok):
        print(("PASS  " if ok else "FAIL  ") + name)
        if not ok: failures.append(name)

    # --- JPEG: XMP route (with DJI's GpsLongtitude typo) ---
    lst = list(build_jpg())
    t = xmp_text(lst)
    check("jpg xmp AbsoluteAltitude", approx(xmp_num(t, "AbsoluteAltitude"), 123.45))
    check("jpg xmp RelativeAltitude", approx(xmp_num(t, "RelativeAltitude"), 30.50))
    check("jpg xmp GpsLatitude", approx(xmp_num(t, "GpsLatitude"), 32.7157380))
    check("jpg xmp GpsLongitude absent -> None", xmp_num(t, "GpsLongitude") is None)
    v = xmp_num(t, "GpsLongitude")
    if v is None: v = xmp_num(t, "GpsLongtitude")
    check("jpg xmp longitude via typo fallback", approx(v, -117.1610838))

    # --- JPEG: correctly-spelt variant ---
    t2 = xmp_text(list(build_jpg(lon_tag="GpsLongitude")))
    check("jpg xmp GpsLongitude (correct spelling)", approx(xmp_num(t2, "GpsLongitude"), -117.1610838))

    # --- JPEG: EXIF route (no XMP in file) ---
    lst3 = list(build_jpg(with_xmp=False, le=True))
    check("jpg no-XMP -> xmp_text empty", xmp_text(lst3) == "")
    la, lo, al, tf = exif_gps(lst3)
    check("jpg exif LE latitude", approx(la, LAT))
    check("jpg exif LE longitude (W negative)", approx(lo, LON))
    check("jpg exif LE altitude", approx(al, 123.456))

    la, lo, al, tf = exif_gps(list(build_jpg(with_xmp=False, le=False)))
    check("jpg exif BE lat/lon/alt", approx(la, LAT) and approx(lo, LON) and approx(al, 123.456))

    la, lo, al, tf = exif_gps(lst)
    check("jpg exif parse with XMP present", approx(la, LAT) and approx(lo, LON))

    # --- signed-byte input (some ADODB builds return signed) ---
    lst5 = [b - 256 if b > 127 else b for b in build_jpg()]
    check("signed bytes: xmp still parses", approx(xmp_num(xmp_text(lst5), "AbsoluteAltitude"), 123.45))
    la, lo, al, tf = exif_gps([b - 256 if b > 127 else b for b in build_jpg(with_xmp=False)])
    check("signed bytes: exif still parses", approx(la, LAT) and approx(al, 123.456))

    # --- truncated file: must return Nones, not crash ---
    la, lo, al, tf = exif_gps(list(build_jpg(with_xmp=False))[:80])
    check("truncated file -> graceful Nones", lo is None and al is None)

    # --- PNG: XMP route via iTXt (no APP1 URI marker in PNGs) ---
    png = list(build_png())
    tp = xmp_text(png)
    check("png xmp AbsoluteAltitude", approx(xmp_num(tp, "AbsoluteAltitude"), 123.45))
    check("png xmp RelativeAltitude", approx(xmp_num(tp, "RelativeAltitude"), 30.50))
    check("png xmp GpsLatitude", approx(xmp_num(tp, "GpsLatitude"), 32.7157380))
    v = xmp_num(tp, "GpsLongitude")
    if v is None: v = xmp_num(tp, "GpsLongtitude")
    check("png xmp longitude", approx(v, -117.1610838))

    # --- PNG: eXIf chunk route, decoy "Exif"/"eXIf" strings skipped ---
    la, lo, al, tf = exif_gps(list(build_png(with_xmp=False)))
    check("png eXIf latitude (decoys skipped)", approx(la, LAT))
    check("png eXIf longitude", approx(lo, LON))
    check("png eXIf altitude", approx(al, 123.456))

    # --- PNG: element-form XMP (re-serialised by some converters) ---
    te = xmp_text(list(build_png(element_form=True, with_exif=False)))
    check("png element-form AbsoluteAltitude", approx(xmp_num(te, "AbsoluteAltitude"), 123.45))
    check("png element-form GpsLatitude", approx(xmp_num(te, "GpsLatitude"), 32.7157380))
    ve = xmp_num(te, "GpsLongitude")
    if ve is None: ve = xmp_num(te, "GpsLongtitude")
    check("png element-form longitude", approx(ve, -117.1610838))

    # --- PNG: metadata parked after >256 KB of image data (tail window) ---
    data = build_png(meta_at_end=True)
    front = read_meta(list(data[:262144]))
    check("png tail-meta: front window finds nothing",
          front[0] is None and front[2] is None and front[3] is None)
    tailm = read_meta(list(data[-262144:]))
    # merge exactly like DDGPS does: tail fills whatever the front left nil
    absm, relm, lat, lon = front[:4]
    if absm is None: absm = tailm[0]
    if relm is None: relm = tailm[1]
    if lat is None: lat = tailm[2]
    if lon is None: lon = tailm[3]
    check("png tail-meta: tail window recovers everything",
          approx(absm, 123.45) and approx(relm, 30.50)
          and approx(lat, 32.7157380) and approx(lon, -117.1610838))

    # --- bare TIFF file (header at byte 0), both byte orders ---
    la, lo, al, tf = exif_gps(list(build_tiff(le=True)))
    check("bare TIFF LE", approx(la, LAT) and approx(lo, LON) and approx(al, 123.456))
    la, lo, al, tf = exif_gps(list(build_tiff(le=False)))
    check("bare TIFF BE", approx(la, LAT) and approx(lo, LON) and approx(al, 123.456))

    # --- read_meta prefers XMP, EXIF fills gaps ---
    absm, relm, lat, lon = read_meta4(list(build_png(with_xmp=False)))
    check("read_meta from eXIf only", approx(lat, LAT) and approx(lon, LON) and approx(absm, 123.456)
          and relm is None)

    # --- failure classification (mirrors DDGPS's loud-failure decision) ---
    def cls(data):
        return classify(*read_meta(list(data)))
    check("classify normal jpg -> OK", cls(build_jpg()) == "OK")
    check("classify normal png -> OK", cls(build_png()) == "OK")
    check("classify stripped png -> NO_METADATA",
          cls(build_png(with_xmp=False, with_exif=False)) == "NO_METADATA")
    check("classify EXIF without GPS IFD -> NO_GPS_DATA",
          cls(build_png(with_xmp=False, exif_with_gps=False)) == "NO_GPS_DATA")
    check("classify XMP without GPS tags -> NO_GPS_DATA",
          cls(build_png(with_exif=False, gps=False)) == "NO_GPS_DATA")
    check("classify 0,0 position -> NO_FIX",
          cls(build_png(with_exif=False, lat_s=b"+0.0000000", lon_s=b"+0.0000000")) == "NO_FIX")
    check("classify latitude 99 -> BAD_GPS",
          cls(build_png(with_exif=False, lat_s=b"+99.0000000")) == "BAD_GPS")
    check("classify coords but no altitude -> NO_ALTITUDE",
          cls(build_png(with_exif=False, alts=False)) == "NO_ALTITUDE")

    # --- JSON extractor against real response shapes ---
    epqs = '{"location":{"x":-117.161,"y":32.7157,"spatialReference":{"wkid":4326,"latestWkid":4326}},"locationId":0,"value":"296.606","rasterId":68360,"resolution":1}'
    check("json EPQS quoted value", approx(json_num(epqs, "value"), 296.606))
    check("json EPQS bare value", approx(json_num('{"value": 57.99, "rasterId": 1}', "value"), 57.99))
    check("json EPQS no-data sentinel parses (range filter rejects later)",
          approx(json_num('{"value": "-1000000", "rasterId": 1}', "value"), -1000000.0))
    otd = '{"results": [{"dataset": "ned10m", "elevation": 89.5, "location": {"lat": 32.7157, "lng": -117.161}}], "status": "OK"}'
    check("json OpenTopoData elevation", approx(json_num(otd, "elevation"), 89.5))
    otd_null = '{"results": [{"dataset": "ned10m", "elevation": null, "location": {}}], "status": "OK"}'
    check("json null elevation -> None", json_num(otd_null, "elevation") is None)
    oel = '{"results": [{"latitude": 32.7157, "longitude": -117.161, "elevation": 88.0}]}'
    check("json Open-Elevation", approx(json_num(oel, "elevation"), 88.0))
    check("json missing key -> None", json_num(oel, "value") is None)

    print()
    if failures:
        print(f"{len(failures)} FAILURES: {failures}")
        sys.exit(1)
    print("ALL CHECKS PASSED")

if __name__ == "__main__":
    main()
