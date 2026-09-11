"""How big a generated DCL dialog comes out, in pixels.

WHY THIS EXISTS.  DCL does not scroll.  A dialog wider or taller than
the screen does not clip and it does not scroll -- AutoCAD refuses to
open it at all, with

    Dialog too large to fit on screen.
    Requested Size = (436, 1085)   Maximum Size = (1920, 1080)

and the command dies on the spot.  LAZPANEL's "Rest" page reached 1085
pixels the moment it held 28 captioned buttons, so the page every
newly registered tool lands on was the page that stopped opening.
Height is generated here -- a page is as tall as its longest column --
so it can be measured here, and a column that has grown too long can be
wrapped before anybody ships it.

THE MODEL, AND WHERE ITS NUMBERS COME FROM.  AutoCAD lays DCL out in
character cells and reports the result in pixels; the conversion is the
display's, not ours, so these constants are FITTED, not derived.  They
are fitted to the report above -- the only exact measurement of a real
AutoCAD we have -- and they reproduce BOTH of its numbers:

    width   the "status" text is `width = 60` and is the widest tile on
            the page, so 60*CELL_W + DLG_H = 60*7 + 16 = 436          ok
    height  status text, two tab rows, one pinned row, the 28-button
            boxed column, a spacer and Close is 33 stacked rows inside
            four boxes, so DLG_V + SPACER_H + 4*BOX_V + 33*ROW_H
            = 95 + 12 + 120 + 858 = 1085                              ok

Two independent equations, both exact, is the most confidence a single
report can buy.  Treat the absolute pixels as approximate anyway -- a
different DPI or dialog font moves every one of them -- which is why
the budget these are checked against (tools/check_dcl.py) keeps a
margin rather than allowing right up to 1080.
"""

import re

CELL_W = 7      # px per character cell
ROW_H = 26      # px for one stacked tile: button, text, toggle, edit_box
BOX_V = 30      # px a boxed_* container adds vertically (border + label)
BOX_H = 12      # px a boxed_* container adds horizontally
SPACER_H = 12   # px for a bare `spacer;`
DLG_V = 95      # px of dialog frame: title bar, margins
DLG_H = 16      # px of dialog frame, left + right
BTN_PAD = 16    # px of button chrome around its label
TGL_PAD = 20    # px of toggle chrome: the tick box and its gap

# Tiles that stack their children vertically, and those that lay them
# out side by side.  Everything else is a leaf.
COLUMNS = ("column", "boxed_column", "dialog")
ROWS = ("row", "boxed_row", "concatenation", "radio_row")


class Tile(object):
    def __init__(self, kind, name=None):
        self.kind = kind
        self.name = name
        self.attrs = {}
        self.kids = []


def _unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1]
    return s


def parse(text):
    """Every `name : dialog { ... }` in TEXT, as Tile trees.

    A character scanner rather than a line reader: the generators emit
    a whole `: row { ... : button { ... } }` on one line in places, and
    a line reader would need the same brace counting anyway.  Quoted
    strings are stepped over so a caption holding a brace or a
    semicolon cannot end a tile early.
    """
    out, stack, buf, i, n = [], [], "", 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j = text.find('"', i + 1)
            if j < 0:
                j = n - 1
            buf += text[i:j + 1]
            i = j + 1
            continue
        if ch == "{":
            head = buf.strip()
            buf = ""
            m = re.match(r'^(?:([A-Za-z0-9_]+)\s*)?:\s*([A-Za-z_]+)$', head)
            if m:
                t = Tile(m.group(2), m.group(1))
            else:
                t = Tile("column", None)      # shouldn't happen; stay soft
            if stack:
                stack[-1].kids.append(t)
            stack.append(t)
        elif ch == "}":
            buf = ""
            if stack:
                t = stack.pop()
                if not stack:
                    out.append(t)
        elif ch == ";":
            item = buf.strip()
            buf = ""
            if not item or not stack:
                pass
            elif "=" in item:
                k, _, v = item.partition("=")
                stack[-1].attrs[k.strip()] = _unquote(v)
            else:
                # a bare tile: `spacer;`, `spacer_0;`, `ok_cancel;`
                stack[-1].kids.append(Tile(item.split()[0]))
        else:
            buf += ch
        i += 1
    return [t for t in out if t.kind == "dialog"]


def _num(t, key, default=0):
    try:
        return float(t.attrs.get(key, default))
    except (TypeError, ValueError):
        return default


def leaf_size(t):
    """(width, height) in px for a tile with no children."""
    label = t.attrs.get("label", "")
    kind = t.kind
    if kind in ("spacer", "spacer_0", "spacer_1"):
        return (0, SPACER_H)
    if kind == "text":
        w = _num(t, "width") * CELL_W or len(label) * CELL_W
        return (w, ROW_H)
    if kind == "button":
        w = max(len(label) * CELL_W + BTN_PAD, _num(t, "width") * CELL_W)
        return (w, ROW_H)
    if kind == "toggle":
        return (len(label) * CELL_W + TGL_PAD, ROW_H)
    if kind == "edit_box":
        w = (len(label) + _num(t, "edit_width")) * CELL_W + BTN_PAD
        return (w, ROW_H)
    if kind == "list_box":
        rows = _num(t, "height", 3)
        return (_num(t, "width") * CELL_W, rows * ROW_H)
    if kind in ("image", "image_button"):
        # DCL sizes a picture by width and ASPECT_RATIO (height over
        # width), not by a height attribute -- reading only `height`
        # scores every chart tile as nothing at all.
        w = _num(t, "width") * CELL_W
        if "aspect_ratio" in t.attrs:
            return (w, w * _num(t, "aspect_ratio", 1))
        return (w, _num(t, "height") * ROW_H)
    if kind == "ok_cancel":
        return (2 * (8 * CELL_W + BTN_PAD), ROW_H)
    if kind in ("radio_button", "popup_list"):
        return (len(label) * CELL_W + TGL_PAD, ROW_H)
    return (len(label) * CELL_W, ROW_H)


def size(t):
    """(width, height) in px for any tile, children included."""
    if not t.kids:
        return leaf_size(t)
    sizes = [size(k) for k in t.kids]
    if t.kind in ROWS:
        w = sum(s[0] for s in sizes)
        h = max(s[1] for s in sizes)
    else:
        w = max(s[0] for s in sizes)
        h = sum(s[1] for s in sizes)
    if t.kind.startswith("boxed_"):
        w += BOX_H
        h += BOX_V
    if t.kind == "dialog":
        w += DLG_H
        h += DLG_V
    return (w, h)


def measure(text):
    """[(dialog name, width, height), ...] for every dialog in TEXT."""
    return [(d.name, int(round(size(d)[0])), int(round(size(d)[1])))
            for d in parse(text)]
