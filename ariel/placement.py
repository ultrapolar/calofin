# SPDX-License-Identifier: GPL-3.0-or-later
"""What the run does at each anchor, with nothing that touches a screen.

The loop is small but it is the part that can go wrong expensively: a
mis-stepped index clicks the wrong place in someone's live drawing.  So
it lives here, as a plain object over a list of points, and the caller
does the clicking.  Every command returns the ACTIONS it wants
performed rather than performing them, which is what lets the whole
sequence be driven and checked without Windows, without Ariel and
without a mouse:

    ("click", x, y)              press and release the left button there
    ("drag", x0, y0, x1, y1)     press at one point, release at another
    ("move", x, y)               move the pointer, press nothing

TWO ORDERS OF EVENTS, AND WHY BOTH EXIST
----------------------------------------
Click first, then confirm (the default) is the operator's own
description of the job: the anchor lands, Ariel draws it, and the zoom
window asks whether that is where it should be.  A nudge then has to
MOVE something that already exists, which is a drag, and that only
works if Ariel lets an anchor be dragged.

Confirm first, then click inverts it: the zoom window opens on bare
photo, the nudge is a pointer move over pixels, and the click happens
on Enter.  Nothing has to be undone if the detector was a few pixels
out, and nothing has to be draggable.  It is the mode to fall back to
if dragging fights the software.

The distinction is one boolean here and one flag on the command line,
and everything else about the two runs is identical.

Going back is deliberately NOT an undo.  ``back`` re-opens the previous
anchor so it can be looked at and nudged; the click that placed it has
already happened and this program does not pretend otherwise.  Undo
belongs to Ariel, and quietly sending it a Ctrl+Z would be a guess
about someone else's undo stack.
"""


class Plan(object):
    """An ordered anchor list, a cursor into it, and what happened."""

    def __init__(self, points, click_first=True):
        self.points = [(int(round(x)), int(round(y))) for x, y in points]
        self.click_first = bool(click_first)
        self.placed = [False] * len(self.points)
        self.skipped = [False] * len(self.points)
        self.index = 0
        self.stopped = False

    # ------------------------------------------------------------ queries

    def __len__(self):
        return len(self.points)

    @property
    def done(self):
        return self.stopped or self.index >= len(self.points)

    @property
    def current(self):
        """The point being worked on, or None once the run is over."""
        if self.done:
            return None
        return self.points[self.index]

    @property
    def current_placed(self):
        return not self.done and self.placed[self.index]

    def progress(self):
        """(this one's number, how many there are) -- 1-based, for people."""
        return (min(self.index + 1, len(self.points)), len(self.points))

    def summary(self):
        return {
            "total": len(self.points),
            "placed": sum(1 for p in self.placed if p),
            "skipped": sum(1 for s in self.skipped if s),
            "untouched": sum(1 for i in range(len(self.points))
                             if not self.placed[i] and not self.skipped[i]),
            "stopped": self.stopped,
        }

    # ----------------------------------------------------------- commands

    def enter(self):
        """Open the current anchor.  Clicks it now in click-first mode."""
        if self.done:
            return []
        x, y = self.points[self.index]
        if self.click_first and not self.placed[self.index]:
            self.placed[self.index] = True
            self.skipped[self.index] = False
            return [("click", x, y)]
        return [("move", x, y)]

    def nudge(self, dx, dy):
        """Shift this anchor.  Drags it if it is already on the drawing."""
        if self.done:
            return []
        x, y = self.points[self.index]
        moved = (x + dx, y + dy)
        self.points[self.index] = moved
        if self.placed[self.index]:
            return [("drag", x, y, moved[0], moved[1])]
        return [("move", moved[0], moved[1])]

    def place(self):
        """Click the current point (again, if it has been clicked before)."""
        if self.done:
            return []
        x, y = self.points[self.index]
        self.placed[self.index] = True
        self.skipped[self.index] = False
        return [("click", x, y)]

    def accept(self):
        """Confirm this anchor and step on.  Clicks it if it has not been."""
        if self.done:
            return []
        actions = []
        if not self.placed[self.index]:
            actions = self.place()
        self.index += 1
        return actions

    def skip(self):
        """Step on without placing.  A dot the detector should not have found."""
        if self.done:
            return []
        if not self.placed[self.index]:
            self.skipped[self.index] = True
        self.index += 1
        return []

    def back(self):
        """Re-open the previous anchor.  Does NOT undo its click."""
        if self.index > 0:
            self.index -= 1
        self.stopped = False
        return []

    def stop(self):
        """End the run here, leaving everything after it untouched."""
        self.stopped = True
        return []
