# SPDX-License-Identifier: GPL-3.0-or-later
"""The three windows: pick the area, check the dots, confirm each one.

Tk only, because tkinter ships with Python and this has to run on a
drafting machine where installing a package is a conversation with IT.
Tk cannot open a screenshot from memory, so every picture goes out as a
PPM -- a nine-byte header in front of the bytes -- and comes back as a
PhotoImage.  ``PhotoImage.zoom`` does the magnifier's enlargement,
nearest-neighbour, which is the right kind for looking at pixels.

Nothing here imports winio.  The screen grab arrives as a callable and
the keystrokes arrive as tuples, so the windows can be reasoned about
(and the run driven) without a Windows API in the room.

WHY THE WINDOWS SIT WHERE THEY DO
---------------------------------
The picker and the review window are borderless and positioned exactly
over the pixels they show, at 1:1.  That is not decoration: it makes
the picture on screen indistinguishable from the screen, so a click in
the review window is a click at the coordinate it appears to be at, and
the operator is looking at their own photo rather than a shrunken copy
of it in a dialog.

The magnifier is the opposite -- it must never cover what it is asking
about -- so it goes to whichever corner is furthest from the anchor and
moves if the anchor comes near it.
"""

import os
import tempfile
import time
import tkinter as tk

import ordering
import pixmap

#: Tk keysyms are not the names the rest of the program uses, and the
#: keyboard hook speaks a third language (virtual key codes).  Both get
#: normalised to these.
_KEYSYMS = {
    "Return": "enter", "KP_Enter": "enter", "Escape": "escape",
    "space": "space", "BackSpace": "backspace", "Left": "left",
    "Right": "right", "Up": "up", "Down": "down",
}

DOT_COLOR = {"red": "#ff4628", "blue": "#00e5ff"}


class Overlay(object):
    """The Tk root, a scratch directory for PPMs, and the key queue."""

    def __init__(self):
        self.root = tk.Tk()
        self.root.withdraw()
        self.keys = []
        self._scratch = tempfile.mkdtemp(prefix="ariel-anchors-")
        self._serial = 0
        self._alive = []            # PhotoImages Tk would otherwise collect
        self.root.bind_all("<Key>", self._on_key)

    # ------------------------------------------------------------- plumbing

    def _on_key(self, event):
        name = _KEYSYMS.get(event.keysym)
        if name is None:
            if len(event.char) == 1 and event.char.isalpha():
                name = event.char.lower()
            else:
                return
        self.keys.append((name, bool(event.state & 0x1)))

    def photo(self, img):
        """A PhotoImage of an Image, via a PPM that is gone a line later."""
        self._serial += 1
        path = os.path.join(self._scratch, "f%d.ppm" % self._serial)
        pixmap.write_ppm(path, img)
        try:
            handle = tk.PhotoImage(master=self.root, file=path)
        finally:
            try:
                os.unlink(path)
            except OSError:
                pass
        self._alive.append(handle)
        return handle

    def forget_photos(self):
        """Drop the images a closed window was holding open."""
        self._alive = []

    def keep_recent(self, count):
        """Hold only the last few images -- the magnifier makes one a keypress."""
        self._alive = self._alive[-count:]

    def next_key(self, feed=None, poll=0.01):
        """Block until a key arrives, from Tk or from `feed`.

        `feed` is the keyboard hook, drained on every turn of the pump.
        Tk's own bindings only fire when one of these windows has the
        focus, and during a run it deliberately does not -- Ariel does.
        """
        while True:
            self.root.update()
            if feed:
                self.keys.extend(feed())
            if self.keys:
                return self.keys.pop(0)
            time.sleep(poll)

    def flush_keys(self):
        self.keys = []

    def close(self):
        """Tear down Tk and take the scratch directory with it.

        A run makes one PPM per magnifier refresh, so leaving them behind
        would fill %TEMP% a keystroke at a time.  They are normally gone
        already -- photo() unlinks each one the moment Tk has read it --
        and this is the path where something threw before it could.
        """
        try:
            self.root.destroy()
        except tk.TclError:
            pass
        try:
            for name in os.listdir(self._scratch):
                os.unlink(os.path.join(self._scratch, name))
            os.rmdir(self._scratch)
        except OSError:
            pass

    def bare_window(self, x, y, width, height):
        win = tk.Toplevel(self.root)
        win.overrideredirect(True)
        win.geometry("%dx%d+%d+%d" % (width, height, x, y))
        win.attributes("-topmost", True)
        return win

    # --------------------------------------------------------- the picker

    def pick_region(self, shot, origin):
        """Drag out the part of the screen to search.  Screen coordinates.

        Returns (x, y, w, h), or the whole shot on Enter, or None on Esc.
        """
        win = self.bare_window(origin[0], origin[1], shot.width, shot.height)
        canvas = tk.Canvas(win, width=shot.width, height=shot.height,
                           highlightthickness=0, bd=0, cursor="crosshair")
        canvas.pack()
        canvas.create_image(0, 0, anchor="nw", image=self.photo(shot))
        state = {"from": None, "rect": None, "result": None}

        def shade(box):
            canvas.delete("shade")
            width, height = shot.width, shot.height
            if box is None:
                spans = [(0, 0, width, height)]
            else:
                left, top, right, bottom = box
                spans = [(0, 0, width, top), (0, bottom, width, height),
                         (0, top, left, bottom), (right, top, width, bottom)]
            for (x0, y0, x1, y1) in spans:
                if x1 > x0 and y1 > y0:
                    canvas.create_rectangle(x0, y0, x1, y1, fill="black",
                                            stipple="gray50", outline="",
                                            tags="shade")

        def box_now(event):
            x0, y0 = state["from"]
            return (min(x0, event.x), min(y0, event.y),
                    max(x0, event.x), max(y0, event.y))

        def press(event):
            state["from"] = (event.x, event.y)

        def move(event):
            if not state["from"]:
                return
            left, top, right, bottom = box_now(event)
            shade((left, top, right, bottom))
            canvas.delete("band")
            canvas.create_rectangle(left, top, right, bottom, outline="#00e5ff",
                                    width=2, tags="band")
            canvas.delete("size")
            canvas.create_text(left + 4, max(10, top - 10), anchor="w",
                               text="%d x %d" % (right - left, bottom - top),
                               fill="#00e5ff",
                               font=("Segoe UI", 10, "bold"), tags="size")

        def release(event):
            if not state["from"]:
                return
            left, top, right, bottom = box_now(event)
            if right - left < 8 or bottom - top < 8:
                state["from"] = None            # a stray click, not a drag
                shade(None)
                canvas.delete("band", "size")
                return
            state["result"] = (origin[0] + left, origin[1] + top,
                               right - left, bottom - top)
            win.destroy()

        def whole(_event=None):
            state["result"] = (origin[0], origin[1], shot.width, shot.height)
            win.destroy()

        shade(None)
        canvas.create_text(
            shot.width // 2, 26, fill="#00e5ff", font=("Segoe UI", 13, "bold"),
            text="Drag the area holding the anchor dots"
                 "     •  Enter = whole screen  •  Esc = cancel")
        canvas.bind("<ButtonPress-1>", press)
        canvas.bind("<B1-Motion>", move)
        canvas.bind("<ButtonRelease-1>", release)
        win.bind("<Return>", whole)
        win.bind("<KP_Enter>", whole)
        win.bind("<Escape>", lambda _e: win.destroy())
        win.focus_force()
        self.root.wait_window(win)
        self.flush_keys()
        self.forget_photos()
        return state["result"]

    # --------------------------------------------------------- the review

    def review(self, region_img, origin, dots, order):
        """Show the found dots, numbered, and let them be corrected.

        The window sits exactly over the region at 1:1, so it reads as
        the operator's own screen with the numbers drawn on -- the same
        picture they would mark up by hand.  Clicking removes a dot or
        adds one; right-clicking says which dot is number 1; o, x and c
        change the order and renumber immediately, which is the only
        honest way to choose between three orderings.

        Returns (points, order) with points in SCREEN coordinates, or
        None if the run was cancelled.
        """
        win = self.bare_window(origin[0], origin[1],
                               region_img.width, region_img.height)
        canvas = tk.Canvas(win, width=region_img.width,
                           height=region_img.height,
                           highlightthickness=0, bd=0, cursor="crosshair")
        canvas.pack()
        canvas.create_image(0, 0, anchor="nw", image=self.photo(region_img))
        state = {
            "points": [(float(d.x), float(d.y)) for d in dots],
            "colors": {(float(d.x), float(d.y)): d.color for d in dots},
            "order": dict(order),
            "start": None,
            "ok": False,
        }

        def sequenced():
            return ordering.sequence(
                state["points"], state["order"]["mode"],
                state["order"]["corner"], state["order"]["clockwise"],
                state["start"])

        def draw():
            canvas.delete("mark")
            points = sequenced()
            for index, point in enumerate(points):
                x, y = point
                color = DOT_COLOR.get(state["colors"].get(point, "blue"),
                                      DOT_COLOR["blue"])
                canvas.create_oval(x - 7, y - 7, x + 7, y + 7, outline=color,
                                   width=2, tags="mark")
                canvas.create_text(x + 11, y - 9, anchor="w",
                                   text=str(index + 1), fill=color,
                                   font=("Segoe UI", 11, "bold"), tags="mark")
                if index:
                    previous = points[index - 1]
                    canvas.create_line(previous[0], previous[1], x, y,
                                       fill=color, width=1, dash=(2, 4),
                                       tags="mark")
            canvas.delete("hud")
            canvas.create_rectangle(0, 0, region_img.width, 44, fill="black",
                                    stipple="gray75", outline="", tags="hud")
            canvas.create_text(
                12, 22, anchor="w", fill="#00e5ff",
                font=("Segoe UI", 11, "bold"), tags="hud",
                text="%d dots  •  %s, %s from %s   "
                     "[Enter] place   [click] add/remove   "
                     "[right-click] make #1   [o]rder  direction[x]  "
                     "[c]orner   [Esc] cancel"
                     % (len(points), state["order"]["mode"],
                        "clockwise" if state["order"]["clockwise"]
                        else "anticlockwise", state["order"]["corner"]))

        def nearest_point(x, y, within=12.0):
            best, best_d = None, within * within
            for point in state["points"]:
                d = (point[0] - x) ** 2 + (point[1] - y) ** 2
                if d <= best_d:
                    best, best_d = point, d
            return best

        def toggle(event):
            hit = nearest_point(event.x, event.y)
            if hit is not None:
                state["points"].remove(hit)
                if state["start"] == hit:
                    state["start"] = None
            else:
                point = (float(event.x), float(event.y))
                state["points"].append(point)
                state["colors"][point] = "blue"
            draw()

        def make_first(event):
            hit = nearest_point(event.x, event.y)
            if hit is not None:
                state["start"] = hit
                draw()

        def cycle_mode(_event=None):
            modes = ordering.MODES
            at = modes.index(state["order"]["mode"])
            state["order"]["mode"] = modes[(at + 1) % len(modes)]
            draw()

        def cycle_corner(_event=None):
            corners = ordering.CORNERS
            at = corners.index(state["order"]["corner"])
            state["order"]["corner"] = corners[(at + 1) % len(corners)]
            state["start"] = None
            draw()

        def flip(_event=None):
            state["order"]["clockwise"] = not state["order"]["clockwise"]
            draw()

        def go(_event=None):
            state["ok"] = True
            win.destroy()

        canvas.bind("<ButtonPress-1>", toggle)
        canvas.bind("<ButtonPress-3>", make_first)
        for key, action in (("<Return>", go), ("<KP_Enter>", go),
                            ("<o>", cycle_mode), ("<c>", cycle_corner),
                            ("<x>", flip)):
            win.bind(key, action)
        win.bind("<Escape>", lambda _e: win.destroy())
        draw()
        win.focus_force()
        self.root.wait_window(win)
        self.flush_keys()
        self.forget_photos()
        if not state["ok"]:
            return None
        points = [(x + origin[0], y + origin[1]) for (x, y) in sequenced()]
        return points, state["order"]


class Magnifier(object):
    """The confirm window: this anchor, enlarged, out of the way.

    Rebuilt from a fresh grab every time it is shown, so in click-first
    mode it shows what Ariel actually drew rather than what was there
    before the click.  That is the whole point of the step -- the
    operator is checking the software's result, not the detector's
    guess.
    """

    PAD = 10

    def __init__(self, overlay, grab, screen, view=48, zoom=8):
        self.overlay = overlay
        self.grab = grab
        self.screen = screen                 # (x, y, w, h) of the desktop
        self.view = max(8, int(view))
        self.zoom = max(1, int(zoom))
        self.win = None
        self.canvas = None
        self.side = self.view * self.zoom

    def _build(self):
        height = self.side + 54
        self.win = self.overlay.bare_window(0, 0, self.side + 2 * self.PAD,
                                            height)
        self.win.configure(bg="#101418")
        self.canvas = tk.Canvas(self.win, width=self.side + 2 * self.PAD,
                                height=height, highlightthickness=0, bd=0,
                                bg="#101418")
        self.canvas.pack()

    def _place(self, point):
        """Park in the corner furthest from the anchor being confirmed."""
        sx, sy, sw, sh = self.screen
        width = self.side + 2 * self.PAD
        height = self.side + 54
        left = sx + 24 if point[0] > sx + sw / 2.0 else sx + sw - width - 24
        top = sy + 24 if point[1] > sy + sh / 2.0 else sy + sh - height - 24
        self.win.geometry("%dx%d+%d+%d" % (width, height, int(left),
                                           int(top)))

    def show(self, point, heading, hint):
        if self.win is None:
            self._build()
        self._place(point)
        half = self.view // 2
        left = max(self.screen[0], min(point[0] - half,
                                       self.screen[0] + self.screen[2]
                                       - self.view))
        top = max(self.screen[1], min(point[1] - half,
                                      self.screen[1] + self.screen[3]
                                      - self.view))
        crop = self.grab(left, top, self.view, self.view)
        photo = self.overlay.photo(crop).zoom(self.zoom)
        self.overlay.keep_recent(4)
        self.canvas.delete("all")
        self.canvas.create_image(self.PAD, self.PAD, anchor="nw", image=photo)
        self._photo = photo                  # the canvas does not own it
        # Where the anchor actually is inside the crop, magnified.
        cx = self.PAD + (point[0] - left) * self.zoom + self.zoom // 2
        cy = self.PAD + (point[1] - top) * self.zoom + self.zoom // 2
        arm = self.side // 2
        for (x0, y0, x1, y1) in ((cx - arm, cy, cx - 12, cy),
                                 (cx + 12, cy, cx + arm, cy),
                                 (cx, cy - arm, cx, cy - 12),
                                 (cx, cy + 12, cx, cy + arm)):
            self.canvas.create_line(x0, y0, x1, y1, fill="#00e5ff", width=1)
        self.canvas.create_oval(cx - 11, cy - 11, cx + 11, cy + 11,
                                outline="#00e5ff", width=2)
        self.canvas.create_rectangle(self.PAD, self.PAD, self.PAD + self.side,
                                     self.PAD + self.side, outline="#2b3540")
        self.canvas.create_text(self.PAD, self.side + self.PAD + 10,
                                anchor="nw", text=heading, fill="#ffffff",
                                font=("Segoe UI", 11, "bold"))
        self.canvas.create_text(self.PAD, self.side + self.PAD + 30,
                                anchor="nw", text=hint, fill="#9fb0c0",
                                font=("Segoe UI", 9))
        self.win.deiconify()
        self.win.lift()
        self.overlay.root.update()

    def focus(self):
        """Take the keyboard.  Only when the global hook could not be had."""
        if self.win is not None:
            self.win.focus_force()

    def hide(self):
        if self.win is not None:
            self.win.withdraw()
            self.overlay.root.update()
