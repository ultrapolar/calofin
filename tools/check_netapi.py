# SPDX-License-Identifier: GPL-3.0-or-later
"""The two .NET surfaces against AutoCAD's OWN assemblies.

``tools/check_vb.py`` reads the palette as code -- balanced blocks,
resolved members of the assembly's own types, imports for the framework
types it names bare.  What it cannot know is whether
``RibbonPanelSource`` has an ``Image``, or which DLL
``IExtensionApplication`` lives in, because those answers are inside
Autodesk's reference assemblies and this tree has no compiler and no
copy of them.

That gap was not theoretical.  Both questions above had the wrong answer
in this repo at once: the ribbon hung the category icon on
``RibbonPanelSource.Image``, which does not exist on that type at all,
and NEITHER project referenced ``AutoCAD.NET.Model`` -- the package that
carries ``AcDbMgd.dll``, and with it ``IExtensionApplication`` (the
ribbon) and the whole of ``Autodesk.AutoCAD.DatabaseServices`` (the
palette).  ``make check`` was green and 121 tests passed throughout.

So this reads the assemblies themselves: the PE header, the CLI header,
the ECMA-335 metadata root and the ``#~`` tables, far enough to answer
"does type T define, or inherit, a member called M".  Pure stdlib, like
everything else here.

**It is opt-in, because the assemblies are not in this tree and must not
be.**  Point it at any folder holding them and it walks it:

    python3 tools/check_netapi.py --refs "C:\\Program Files\\Autodesk\\AutoCAD 2024"
    python3 tools/check_netapi.py --refs ~/nuget/autocad.net/24.3.0/lib/net47

With no ``--refs`` (and no ``CALOFIN_ACAD_REFS`` in the environment) it
says what it would have checked and exits 0, so it is safe to leave in a
script that runs where AutoCAD is not installed.  That is why ``make
check`` does not run it: a check that cannot run on this machine cannot
be allowed to fail the build, and one that silently passes is worse than
none.  Run it on a machine that HAS AutoCAD, before a build.

The manifest below is hand-written -- it is what our code calls -- and
it is held to the source the one way that matters: every type named here
must actually appear in the file it is listed under, so an entry cannot
survive the code that needed it.
"""

import argparse
import glob
import os
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from callib import ROOT, read  # noqa: E402

RIBBON = "ui/calofin_ribbon/RibbonExtensionApplication.cs"
PALETTE = "ui/calofin_net"

W = "Autodesk.Windows"
AS = "Autodesk.AutoCAD.ApplicationServices"
RT = "Autodesk.AutoCAD.Runtime"
DB = "Autodesk.AutoCAD.DatabaseServices"
AW = "Autodesk.AutoCAD.Windows"

#: {source file or folder: [(namespace, type, [member, ...]), ...]}
#: What our code names, and what it asks of each.  A member is looked up
#: on the type AND up its base chain, which is where most of the ribbon's
#: live -- Orientation and CommandHandler are RibbonCommandItem's, Size
#: and ShowText are RibbonItem's.
#:
#: A fourth element is how the type APPEARS in the source, when that is
#: not its own name: an attribute loses its suffix ([CommandMethod]), and
#: a type reached only as another's return value is never spelled at all
#: (DocumentManager hands back a DocumentCollection).  The drift guard
#: looks for that instead.
SURFACES = {
    RIBBON: [
        (W, "RibbonControl", ["Tabs"]),
        (W, "RibbonTab", ["Title", "Id", "Panels", "IsActive"]),
        (W, "RibbonPanel", ["Source", "CollapsedPanelImage"]),
        (W, "RibbonPanelSource", ["Title", "Items"]),
        (W, "RibbonRowPanel", ["Items"]),
        (W, "RibbonRowBreak", []),
        (W, "RibbonButton", ["Text", "ShowText", "ShowImage", "Size",
                             "Orientation", "ToolTip", "CommandParameter",
                             "CommandHandler", "Image", "LargeImage"]),
        (W, "RibbonSplitButton", ["Text", "ShowText", "ShowImage", "Size",
                                  "Orientation", "IsSplit", "Current",
                                  "IsSynchronizedWithCurrentItem", "Items",
                                  "Image", "LargeImage"]),
        (W, "RibbonToolTip", ["Command", "Title", "Content",
                              "IsHelpEnabled"]),
        (W, "RibbonItemSize", ["Large", "Standard"]),
        (W, "ComponentManager", ["Ribbon"]),
        (AS, "Application", ["Idle", "SystemVariableChanged",
                             "DocumentManager"]),
        (AS, "DocumentCollection", ["MdiActiveDocument"], "DocumentManager"),
        (AS, "Document", ["SendStringToExecute"]),
        (AS, "SystemVariableChangedEventArgs", ["Name"]),
        (RT, "IExtensionApplication", ["Initialize", "Terminate"]),
        (RT, "CommandMethodAttribute", [], "CommandMethod"),
    ],
    PALETTE: [
        (AW, "PaletteSet", ["AddVisual", "MinimumSize", "Style", "Visible"]),
        (AW, "PaletteSetStyles", []),
        (AS, "Application", ["DocumentManager", "GetSystemVariable",
                             "Invoke"]),
        (AS, "DocumentCollection", ["MdiActiveDocument"], "DocumentManager"),
        (AS, "Document", ["SendStringToExecute"]),
        (DB, "ResultBuffer", []),
        (DB, "TypedValue", []),
        (RT, "LispDataType", ["Text"]),
        (RT, "CommandMethodAttribute", [], "CommandMethod"),
    ],
}


# ------------------------------------------------- ECMA-335, the thin slice

U1, U2, U4, U8, STR, GUID, BLOB = 'u1', 'u2', 'u4', 'u8', 'str', 'guid', 'blob'


def _t(n):
    return ('tbl', n)


def _c(n):
    return ('cod', n)


CODED = {
    'TypeDefOrRef': (2, [0x02, 0x01, 0x1B]),
    'HasConstant': (2, [0x04, 0x08, 0x17]),
    'HasCustomAttribute': (5, [0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A,
                               0x00, 0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B,
                               0x20, 0x23, 0x26, 0x27, 0x28, 0x2A, 0x2C,
                               0x2B]),
    'HasFieldMarshal': (1, [0x04, 0x08]),
    'HasDeclSecurity': (2, [0x02, 0x06, 0x20]),
    'MemberRefParent': (3, [0x02, 0x01, 0x1A, 0x06, 0x1B]),
    'HasSemantics': (1, [0x14, 0x17]),
    'MethodDefOrRef': (1, [0x06, 0x0A]),
    'MemberForwarded': (1, [0x04, 0x06]),
    'Implementation': (2, [0x26, 0x23, 0x27]),
    'CustomAttributeType': (3, [0x06, 0x0A]),
    'ResolutionScope': (2, [0x00, 0x1A, 0x23, 0x01]),
    'TypeOrMethodDef': (1, [0x02, 0x06]),
}

SCHEMA = {
    0x00: [U2, STR, GUID, GUID, GUID],
    0x01: [_c('ResolutionScope'), STR, STR],
    0x02: [U4, STR, STR, _c('TypeDefOrRef'), _t(0x04), _t(0x06)],
    0x03: [_t(0x04)], 0x04: [U2, STR, BLOB], 0x05: [_t(0x06)],
    0x06: [U4, U2, U2, STR, BLOB, _t(0x08)],
    0x07: [_t(0x08)], 0x08: [U2, U2, STR],
    0x09: [_t(0x02), _c('TypeDefOrRef')],
    0x0A: [_c('MemberRefParent'), STR, BLOB],
    0x0B: [U1, U1, _c('HasConstant'), BLOB],
    0x0C: [_c('HasCustomAttribute'), _c('CustomAttributeType'), BLOB],
    0x0D: [_c('HasFieldMarshal'), BLOB],
    0x0E: [U2, _c('HasDeclSecurity'), BLOB],
    0x0F: [U2, U4, _t(0x02)], 0x10: [U4, _t(0x04)], 0x11: [BLOB],
    0x12: [_t(0x02), _t(0x14)], 0x13: [_t(0x14)],
    0x14: [U2, STR, _c('TypeDefOrRef')],
    0x15: [_t(0x02), _t(0x17)], 0x16: [_t(0x17)], 0x17: [U2, STR, BLOB],
    0x18: [U2, _t(0x06), _c('HasSemantics')],
    0x19: [_t(0x02), _c('MethodDefOrRef'), _c('MethodDefOrRef')],
    0x1A: [STR], 0x1B: [BLOB],
    0x1C: [U2, _c('MemberForwarded'), STR, _t(0x1A)],
    0x1D: [U4, _t(0x04)],
    0x20: [U4, U2, U2, U2, U2, U4, BLOB, STR, STR],
    0x21: [U4], 0x22: [U4, U4, U4],
    0x23: [U2, U2, U2, U2, U4, BLOB, STR, STR, BLOB],
    0x24: [U4, _t(0x23)], 0x25: [U4, U4, U4, _t(0x23)],
    0x26: [U4, STR, BLOB],
    0x27: [U4, U4, STR, STR, _c('Implementation')],
    0x28: [U4, U4, STR, _c('Implementation')],
    0x29: [_t(0x02), _t(0x02)],
    0x2A: [U2, U2, _c('TypeOrMethodDef'), STR],
    0x2B: [_c('MethodDefOrRef'), BLOB], 0x2C: [_t(0x2A), _c('TypeDefOrRef')],
}


class Assembly(object):
    """One managed DLL, far enough in to name its types and members."""

    def __init__(self, path):
        self.path = path
        d = self.d = open(path, 'rb').read()
        if d[:2] != b'MZ':
            raise ValueError("not a PE file")
        pe = struct.unpack_from('<I', d, 0x3C)[0]
        if d[pe:pe + 4] != b'PE\0\0':
            raise ValueError("no PE signature")
        nsec, = struct.unpack_from('<H', d, pe + 6)
        optsz, = struct.unpack_from('<H', d, pe + 20)
        opt = pe + 24
        magic, = struct.unpack_from('<H', d, opt)
        ddir = opt + (96 if magic == 0x10B else 112)
        cli_rva, = struct.unpack_from('<I', d, ddir + 14 * 8)
        if not cli_rva:
            raise ValueError("native, not managed")
        self.secs = []
        for i in range(nsec):
            o = opt + optsz + i * 40
            va, rawsz, raw = struct.unpack_from('<III', d, o + 12)
            self.secs.append((va, rawsz, raw))
        cli = self._off(cli_rva)
        md_rva, = struct.unpack_from('<I', d, cli + 8)
        md = self._off(md_rva)
        if d[md:md + 4] != b'BSJB':
            raise ValueError("no metadata root")
        vlen, = struct.unpack_from('<I', d, md + 12)
        p = md + 16 + vlen + 4
        nstr, = struct.unpack_from('<H', d, p - 2)
        streams = {}
        for _ in range(nstr):
            off, size = struct.unpack_from('<II', d, p)
            p += 8
            name = b''
            while d[p] != 0:
                name += d[p:p + 1]
                p += 1
            p = (p + 4) & ~3
            streams[name.decode()] = (md + off, size)
        self.strings = streams['#Strings'][0]
        self._tables(streams.get('#~') or streams['#-'])

    def _off(self, rva):
        for va, rawsz, raw in self.secs:
            if va <= rva < va + rawsz:
                return raw + (rva - va)
        raise KeyError(rva)

    def s(self, i):
        e = self.d.index(b'\0', self.strings + i)
        return self.d[self.strings + i:e].decode('utf-8', 'replace')

    def _tables(self, tilde):
        d = self.d
        p = tilde[0]
        heap = d[p + 6]
        valid, = struct.unpack_from('<Q', d, p + 8)
        p += 24
        present = [i for i in range(64) if valid >> i & 1]
        rows = {}
        for t in present:
            rows[t], = struct.unpack_from('<I', d, p)
            p += 4
        self.rows = rows
        sizes = {STR: 4 if heap & 1 else 2,
                 GUID: 4 if heap & 2 else 2,
                 BLOB: 4 if heap & 4 else 2,
                 U1: 1, U2: 2, U4: 4, U8: 8}

        def width(col):
            if col in sizes:
                return sizes[col]
            kind, arg = col
            if kind == 'tbl':
                return 4 if rows.get(arg, 0) >= 65536 else 2
            bits, tabs = CODED[arg]
            m = max([rows.get(t, 0) for t in tabs] or [0])
            return 2 if m < (1 << (16 - bits)) else 4

        self.cols, self.base = {}, {}
        for t in present:
            if t not in SCHEMA:
                raise ValueError("unknown metadata table 0x%02X" % t)
            self.cols[t] = [width(c) for c in SCHEMA[t]]
            self.base[t] = p
            p += sum(self.cols[t]) * rows[t]

    def n(self, t):
        return self.rows.get(t, 0)

    def row(self, t, i):
        cols = self.cols[t]
        p = self.base[t] + (i - 1) * sum(cols)
        out = []
        for w in cols:
            out.append(int.from_bytes(self.d[p:p + w], 'little'))
            p += w
        return out

    def types(self):
        out = {}
        for i in range(1, self.n(0x02) + 1):
            r = self.row(0x02, i)
            out[(self.s(r[2]), self.s(r[1]))] = i
        return out

    def _listed(self, maptbl, target, td):
        for i in range(1, self.n(maptbl) + 1):
            r = self.row(maptbl, i)
            if r[0] != td:
                continue
            start = r[1]
            end = (self.row(maptbl, i + 1)[1] if i < self.n(maptbl)
                   else self.n(target) + 1)
            return range(start, end)
        return range(0)

    def _owned(self, td, tbl, col, namecol):
        start = self.row(0x02, td)[col]
        end = (self.row(0x02, td + 1)[col] if td < self.n(0x02)
               else self.n(tbl) + 1)
        return [self.s(self.row(tbl, i)[namecol]) for i in range(start, end)]

    def members(self, td):
        """Every property, event, method and field the type declares."""
        out = set(self.s(self.row(0x17, i)[1])
                  for i in self._listed(0x15, 0x17, td))
        out |= set(self.s(self.row(0x14, i)[1])
                   for i in self._listed(0x12, 0x14, td))
        out |= set(self._owned(td, 0x06, 5, 3))
        out |= set(self._owned(td, 0x04, 4, 1))
        return out

    def base_of(self, td):
        ext = self.row(0x02, td)[3]
        if not ext:
            return None
        tag, idx = ext & 3, ext >> 2
        if not idx or tag == 2:
            return None
        r = self.row(0x02 if tag == 0 else 0x01, idx)
        return (self.s(r[2]), self.s(r[1]))


# ------------------------------------------------------------------ driver

def load(refs):
    """{(namespace, type): (Assembly, typedef row)} over every DLL found."""
    index, loaded, skipped = {}, [], 0
    seen = set()
    for root in refs:
        for path in sorted(glob.glob(os.path.join(root, '**', '*.dll'),
                                     recursive=True)):
            name = os.path.basename(path).lower()
            if name in seen:
                continue
            try:
                a = Assembly(path)
            except Exception:
                skipped += 1
                continue
            seen.add(name)
            loaded.append(path)
            for key, td in a.types().items():
                index.setdefault(key, (a, td))
    return index, loaded, skipped


def resolve(index, ns, name, seen=None):
    """Members of the type and of every base we can see, or None."""
    seen = seen or set()
    if (ns, name) in seen or (ns, name) not in index:
        return None
    seen.add((ns, name))
    a, td = index[(ns, name)]
    out = a.members(td)
    b = a.base_of(td)
    if b:
        up = resolve(index, b[0], b[1], seen)
        if up:
            out = out | up
    return out


def check(refs):
    """Problems as a list of strings, empty when every call resolves."""
    problems = []

    # The manifest cannot outlive the code: a type listed under a file
    # has to be named in it.
    for where, wants in sorted(SURFACES.items()):
        target = ROOT / where
        if target.is_dir():
            src = "\n".join(read(p) for p in sorted(target.glob('*.vb')))
        else:
            src = read(target)
        for entry in wants:
            name, spelling = entry[1], entry[3] if len(entry) > 3 else entry[1]
            if spelling is not None and spelling not in src:
                problems.append(
                    "%s: the manifest lists %s (as '%s'), which that source "
                    "does not name any more - drop the entry."
                    % (where, name, spelling))

    index, loaded, _skipped = load(refs)
    if not loaded:
        problems.append(
            "no managed assemblies under: %s" % ", ".join(refs))
        return problems, 0

    checked = 0
    for where, wants in sorted(SURFACES.items()):
        for entry in wants:
            ns, name, members = entry[0], entry[1], entry[2]
            have = resolve(index, ns, name)
            checked += 1
            if have is None:
                problems.append(
                    "%s: %s.%s is in none of the reference assemblies.\n"
                    "  If it is real, the project is missing the package "
                    "that carries it - AcDbMgd.dll is AutoCAD.NET.Model, "
                    "not AutoCAD.NET." % (where, ns, name))
                continue
            for m in members:
                if m not in have:
                    problems.append(
                        "%s: %s.%s has no member '%s' (nor does any base "
                        "of it)." % (where, ns, name, m))
    return problems, checked


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--refs", action="append", default=[],
                    help="folder holding AutoCAD's managed DLLs; repeatable")
    ap.add_argument("--list", action="store_true",
                    help="print what would be checked and stop")
    args = ap.parse_args(argv)

    refs = list(args.refs)
    env = os.environ.get("CALOFIN_ACAD_REFS")
    if env:
        refs += [p for p in env.split(os.pathsep) if p]

    if args.list or not refs:
        total = sum(len(v) for v in SURFACES.values())
        for where, wants in sorted(SURFACES.items()):
            print("%s" % where)
            for entry in wants:
                ns, name, members = entry[0], entry[1], entry[2]
                print("    %s.%s%s"
                      % (ns, name,
                         ("  [" + ", ".join(members) + "]") if members else ""))
        if not refs:
            print()
            print("check_netapi: %d type(s) NOT checked - no reference "
                  "assemblies given." % total)
            print("  Pass --refs <folder> (an AutoCAD install directory, or "
                  "an unpacked")
            print("  AutoCAD.NET / AutoCAD.NET.Model lib folder), or set "
                  "CALOFIN_ACAD_REFS.")
        return 0

    problems, checked = check(refs)
    for p in problems:
        print(p)
    if problems:
        print()
        print("check_netapi: %d problem(s)" % len(problems))
        return 1
    print("check_netapi: %d type(s) resolve, every member our code calls "
          "found" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
