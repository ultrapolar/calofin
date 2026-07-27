#!/usr/bin/env python3
"""Reference check for abcdef.lsp.

AutoLISP can't run outside AutoCAD, so this script mirrors the parsing and
multilateration logic of abcdef.lsp line-for-line and asserts, against the
shipped template.csv, the behaviour the LISP is supposed to have:

  1. feet-inch parsing, including the dirty-data repairs (split fractions
     like "1 /4", missing foot marks, "/" scanned as "1", ...);
  2. every point in template.csv fits the 36'-5 1/4" x 22'-0 1/4" rectangle
     to within quarter-inch rounding under the documented corner layout
     (A top-left, B top-right, C bottom-LEFT, D bottom-RIGHT);
  3. the C/D swap detector fires when (and only when) a sheet labels the
     bottom corners the other way round.

Run:  python3 verify_abcdef.py
"""
import csv
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- parsing --

def scrub(s):
    for old, new in (("_", "-"), ("O", "0"), ("o", "0"), ("I", "1"),
                     ("l", "1"), ("|", "1"), ("–", "-"), ("—", "-"),
                     ("’", "'"), ("′", "'"), ("”", '"'),
                     ("″", '"')):
        s = s.replace(old, new)
    return s


def parseable(s):
    return all(c.isdigit() or c in " \"'-./" for c in s)


def defrac(tok):
    # all-digit run whose "/" was scanned as a "1": 314 -> 3/4
    for k, ch in enumerate(tok):
        if ch == "1":
            num, den = tok[:k], tok[k + 1:]
            if num.isdigit() and den.isdigit():
                ni, di = int(num), int(den)
                if di in (2, 4, 8, 16, 32) and 0 < ni < di:
                    return f"{num}/{den}"
    return None


def mergefrac(toks):
    # "1 /4", "1/ 4", "1 / 4" -> "1/4"
    out = []
    toks = list(toks)
    while toks:
        tok = toks.pop(0)
        if toks and tok.endswith("/"):
            toks.insert(0, tok + toks.pop(0))
        elif out and len(tok) > 1 and tok.startswith("/"):
            out[-1] += tok
        else:
            out.append(tok)
    return out


def ftin_to_in(raw, maxd=None):
    """Mirror of abcdef:ftin->in (returns None for blank/unreadable)."""
    s = scrub(raw.strip())
    if not s:
        return None
    if not parseable(s):
        return None
    neg = s.startswith("-")
    if neg:
        s = s[1:].strip()
    p = s.find("'")
    ftstr = ""
    if p >= 0:
        ftstr = s[:p].strip()
        feet = float(ftstr.replace(" ", "") or 0)
        rest = s[p + 1:].strip()
    elif "-" in s:
        dp = s.find("-")
        ftstr = s[:dp].strip().replace(" ", "")
        feet = float(ftstr or 0)
        rest = s[dp + 1:].strip()
    else:
        feet, rest = 0.0, s
    if rest.startswith("-"):
        rest = rest[1:].strip()
    rest = rest.replace('"', "").replace("'", "").replace("-", " ").strip()
    inch = 0.0
    for tok in mergefrac(rest.split()):
        if "/" not in tok and len(tok) >= 3 and tok.isdigit():
            df = defrac(tok)
            if df:
                tok = df
        if "/" in tok:
            num, den = tok.split("/", 1)
            try:
                num_v = float(num) if num else 0.0
                den_v = float(den) if den else 0.0
            except ValueError:
                num_v = den_v = 0.0
            if den_v:
                inch += num_v / den_v
        else:
            try:
                inch += float(tok)
            except ValueError:
                pass
    val = feet * 12.0 + inch
    if (maxd and p < 0 and val > maxd * 1.05
            and len(ftstr) > 1 and ftstr.endswith("1")):
        feet = float(ftstr[:-1])
        val = feet * 12.0 + inch
    if neg:
        val = -val
    if val <= 0.0 or (maxd and val > maxd * 1.1):
        return None
    return val


# ----------------------------------------------------------------- solver --

def solve(corners, dists, seed):
    """Mirror of abcdef:solve - linear seed + Gauss-Newton."""
    x, y = seed
    n = len(corners)
    if n >= 3:
        (xr, yr), dr = corners[0], dists[0]
        saa = sab = sbb = sac = sbc = 0.0
        for (cx, cy), d in list(zip(corners, dists))[1:]:
            a, b = 2.0 * (cx - xr), 2.0 * (cy - yr)
            cc = (cx * cx + cy * cy - xr * xr - yr * yr) - (d * d - dr * dr)
            saa += a * a; sab += a * b; sbb += b * b
            sac += a * cc; sbc += b * cc
        det = saa * sbb - sab * sab
        if abs(det) > 1e-9:
            x = (sac * sbb - sbc * sab) / det
            y = (saa * sbc - sab * sac) / det
    for _ in range(60):
        jaa = jab = jbb = ga = gb = 0.0
        for (cx, cy), d in zip(corners, dists):
            dx, dy = x - cx, y - cy
            r = max(math.hypot(dx, dy), 1e-9)
            jx, jy, f = dx / r, dy / r, r - d
            jaa += jx * jx; jab += jx * jy; jbb += jy * jy
            ga += jx * f; gb += jy * f
        det = jaa * jbb - jab * jab
        if abs(det) < 1e-12:
            break
        ddx = -(ga * jbb - gb * jab) / det
        ddy = -(jaa * gb - jab * ga) / det
        x += ddx; y += ddy
        if abs(ddx) < 1e-7 and abs(ddy) < 1e-7:
            break
    rms = math.sqrt(sum((math.hypot(x - cx, y - cy) - d) ** 2
                        for (cx, cy), d in zip(corners, dists)) / n)
    return x, y, rms


# ------------------------------------------------------------------ tests --

def check(desc, cond):
    print(("  ok   " if cond else "  FAIL ") + desc)
    return cond


def main():
    ok = True
    print("parser unit checks:")
    for raw, want in [
        ("12'-3 1/2\"", 147.5),
        ("34'-4 1 /4", 412.25),      # split fraction: space before "/"
        ("13'-0 1 /4", 156.25),
        ("20'-7 1/ 4\"", 247.25),    # split fraction: space after "/"
        ("20'-7 1 / 4\"", 247.25),   # split fraction: spaces both sides
        ("26' -8\"", 320.0),
        ("20'-7 114\"", 247.25),     # "/" scanned as "1"
        ("28-7\"", 343.0),           # missing foot mark
        ("9'", 108.0),
        ("3 1/2\"", 3.5),
    ]:
        got = ftin_to_in(raw, maxd=600.0)
        ok &= check(f"{raw!r} -> {got}", got is not None and abs(got - want) < 1e-9)
    got = ftin_to_in("101-10\"", maxd=514.0)   # foot mark scanned as a "1"
    ok &= check(f"'101-10\"' (maxd 514) -> {got}", got == 130.0)

    # ---- template.csv against the documented rectangle -------------------
    W, H = 437.25, 264.25            # 36'-5 1/4"  x  22'-0 1/4"
    diag = math.hypot(W, H)
    A, B = (0.0, 0.0), (W, 0.0)
    C, D = (0.0, -H), (W, -H)        # C below A, D below B (the "Z" layout)
    seed = (W / 2.0, -H / 2.0)

    rows = []
    with open(os.path.join(HERE, "template.csv"), newline="") as fp:
        rdr = csv.reader(fp)
        next(rdr)                    # header
        for rec in rdr:
            if rec and rec[0].strip():
                rows.append((rec[0].strip(),
                             [ftin_to_in(v, diag) for v in rec[1:5]]))

    print("\ntemplate.csv fit (C=bottom-left, D=bottom-right):")
    ok &= check(f"{len(rows)} rows parsed", len(rows) == 9)
    ok &= check("no unreadable cells",
                all(d is not None for _, ds in rows for d in ds))
    tot_z = tot_cw = 0.0
    pts = {}
    for nm, ds in rows:
        x, y, rms = solve([A, B, C, D], ds, seed)
        pts[nm] = (x, y)
        tot_z += rms
        _, _, rms_cw = solve([A, B, D, C], ds, seed)
        tot_cw += rms_cw
        ok &= check(f"{nm:3s} at ({x:8.2f},{y:8.2f})  rms {rms:.3f}\"",
                    rms < 0.15)

    # T and U are the same offsets measured from mirrored corners, so they
    # must land mirror-symmetric about the rectangle's vertical centreline.
    (xT, yT), (xU, yU) = pts["T"], pts["U"]
    ok &= check("T/U mirror pair symmetric",
                abs((W - xT) - xU) < 0.1 and abs(yT - yU) < 0.1)
    ok &= check("T on left edge, U on right edge",
                abs(xT) < 0.5 and abs(xU - W) < 0.5)

    # ---- C/D swap detector ------------------------------------------------
    n3 = len(rows)
    print(f"\nswap detector (totals: as-labelled {tot_z:.2f}\", swapped {tot_cw:.2f}\"):")
    fire_z = tot_z > 0.5 * n3 and tot_cw < 0.25 * tot_z
    ok &= check("does NOT fire on a correctly-labelled sheet", not fire_z)
    # a clockwise-labelled sheet = same data with C/D columns exchanged
    fire_cw = tot_cw > 0.5 * n3 and tot_z < 0.25 * tot_cw
    ok &= check("DOES fire on a clockwise-labelled sheet", fire_cw)

    print("\n" + ("ALL CHECKS PASSED" if ok else "*** FAILURES ***"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
