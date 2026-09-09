# SPDX-License-Identifier: GPL-3.0-or-later
"""Everything that touches Windows: the screen, the mouse, the keyboard.

ctypes against user32 and gdi32, no packages.  Four jobs:

**Be honest about pixels.**  ``dpi_aware`` runs first, before anything
asks how big the screen is.  On a scaled display a process that has not
said otherwise is told the screen is 1707x960 when it is 2560x1440, and
Windows silently stretches its windows to match.  Detection would then
find a dot at one coordinate and the click would land somewhere else --
the failure that looks like a broken detector and is not.

**Grab the screen once.**  ``grab`` BitBlts into a 32-bit DIB section
and hands back the bytes.  One grab feeds the region picker, the
detector and the review overlay, so what the operator selects is
provably the same pixels that were searched: no window can open, no
tooltip can appear and nothing can scroll between the picture and the
answer.

**Move and click.**  ``SendInput`` rather than ``mouse_event``, absolute
coordinates over the whole virtual desktop rather than the primary
monitor, and the position is read back and corrected after the move
because the absolute form is a 0..65535 fraction of the desktop and the
rounding is regularly a pixel out.  A pixel is a third of a marker.

**Hear a key without stealing the window.**  This is the awkward one.
The operator has to be able to reach into Ariel and drag an anchor
themselves, which means Ariel keeps the keyboard focus, which means a
normal Tk binding never sees the Enter that says "yes, that one is
right".  A WH_KEYBOARD_LL hook sees it anyway, and returning 1 from the
callback swallows it so Ariel does not also act on it.  The callback
does nothing but push a code onto a deque -- Windows quietly drops a
low-level hook that takes too long to answer, and a hook that has been
dropped fails by simply never firing again.

The hook is the one part that can be refused outright (group policy,
another process, a mismatched integrity level).  ``install`` returns
False instead of raising, and the caller falls back to a focused
window; the status line says which of the two is running, because
"press Enter" is bad advice if Enter is going somewhere else.
"""

import collections
import ctypes
import sys
import time
from ctypes import wintypes

from detect import Image

if sys.platform != "win32":                        # pragma: no cover
    raise ImportError(
        "ariel.winio drives the Windows screen and needs to run there. "
        "The detector does not: use --from-shot to work on a saved PNG.")

user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

ULONG_PTR = wintypes.WPARAM
LRESULT = ctypes.c_ssize_t

SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN = 76, 77
SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN = 78, 79
SRCCOPY, CAPTUREBLT, DIB_RGB_COLORS, BI_RGB = 0x00CC0020, 0x40000000, 0, 0

INPUT_MOUSE = 0
MOUSEEVENTF_MOVE, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP = 0x1, 0x2, 0x4
MOUSEEVENTF_ABSOLUTE, MOUSEEVENTF_VIRTUALDESK = 0x8000, 0x4000

WH_KEYBOARD_LL = 13
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x100, 0x101, 0x104, 0x105

VK = {
    "enter": 0x0D, "escape": 0x1B, "space": 0x20, "backspace": 0x08,
    "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
    "s": 0x53, "d": 0x44, "p": 0x50, "shift": 0x10,
}


# ----------------------------------------------------------------- structs


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG),
                ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]


class INPUT(ctypes.Structure):
    #: The real INPUT is a union of three event structs and MOUSEINPUT is
    #: the largest, so a union of one has the size SendInput checks.
    _fields_ = [("type", wintypes.DWORD), ("mi", MOUSEINPUT)]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG),
                ("biHeight", wintypes.LONG), ("biPlanes", wintypes.WORD),
                ("biBitCount", wintypes.WORD),
                ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD),
                ("biXPelsPerMeter", wintypes.LONG),
                ("biYPelsPerMeter", wintypes.LONG),
                ("biClrUsed", wintypes.DWORD),
                ("biClrImportant", wintypes.DWORD)]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER),
                ("bmiColors", wintypes.DWORD * 3)]


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [("vkCode", wintypes.DWORD), ("scanCode", wintypes.DWORD),
                ("flags", wintypes.DWORD), ("time", wintypes.DWORD),
                ("dwExtraInfo", ULONG_PTR)]


HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM,
                              wintypes.LPARAM)

#: Handles are pointers.  Left at the default restype ctypes truncates
#: them to a 32-bit int on a 64-bit build, which turns a perfectly good
#: DC into a handle that belongs to nothing.
user32.GetDC.restype = wintypes.HDC
user32.GetDC.argtypes = [wintypes.HWND]
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
user32.GetForegroundWindow.restype = wintypes.HWND
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.SetWindowsHookExW.restype = wintypes.HHOOK
user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC,
                                     wintypes.HINSTANCE, wintypes.DWORD]
user32.CallNextHookEx.restype = LRESULT
user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int,
                                  wintypes.WPARAM, wintypes.LPARAM]
user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT),
                             ctypes.c_int]
#: GetAsyncKeyState answers in a SHORT; read as an int the sign bit lands
#: somewhere else and the shift test silently never fires.
user32.GetAsyncKeyState.restype = ctypes.c_short
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.GetCursorPos.argtypes = [ctypes.POINTER(wintypes.POINT)]
user32.SetCursorPos.argtypes = [ctypes.c_int, ctypes.c_int]
user32.GetSystemMetrics.argtypes = [ctypes.c_int]
user32.GetSystemMetrics.restype = ctypes.c_int
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateDIBSection.restype = wintypes.HBITMAP
gdi32.CreateDIBSection.argtypes = [wintypes.HDC, ctypes.POINTER(BITMAPINFO),
                                   wintypes.UINT,
                                   ctypes.POINTER(ctypes.c_void_p),
                                   wintypes.HANDLE, wintypes.DWORD]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteDC.argtypes = [wintypes.HDC]
gdi32.BitBlt.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int,
                         ctypes.c_int, ctypes.c_int, wintypes.HDC,
                         ctypes.c_int, ctypes.c_int, wintypes.DWORD]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE
kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]


# -------------------------------------------------------------------- DPI


def dpi_aware():
    """Ask for real pixels, by whichever call this Windows understands.

    Per-monitor v2 (1703 and later) first, then the 8.1 call, then the
    Vista one.  Returns the name of the one that took, for the log --
    on the oldest path a secondary monitor at a different scale is
    still virtualised and it is worth being able to see that in a
    report.
    """
    try:
        # -4 is DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 -- the constant
        # IS the handle, a small negative number cast to a pointer.
        user32.SetProcessDpiAwarenessContext.restype = wintypes.BOOL
        user32.SetProcessDpiAwarenessContext.argtypes = [ctypes.c_void_p]
        if user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4)):
            return "per-monitor-v2"
    except AttributeError:
        pass
    try:
        if ctypes.WinDLL("shcore").SetProcessDpiAwareness(2) == 0:
            return "per-monitor"
    except (AttributeError, OSError):
        pass
    try:
        if user32.SetProcessDPIAware():
            return "system"
    except AttributeError:
        pass
    return "none"


def virtual_rect():
    """(x, y, width, height) of every monitor together, top-left may be < 0."""
    return (user32.GetSystemMetrics(SM_XVIRTUALSCREEN),
            user32.GetSystemMetrics(SM_YVIRTUALSCREEN),
            user32.GetSystemMetrics(SM_CXVIRTUALSCREEN),
            user32.GetSystemMetrics(SM_CYVIRTUALSCREEN))


# ------------------------------------------------------------------- grab


def grab(x, y, width, height):
    """A screen rectangle, as an Image.  Screen coordinates, cursor not in it.

    BitBlt does not draw the pointer, which is exactly what is wanted:
    the magnifier would otherwise show the arrow parked on top of the
    dot it is being asked about.
    """
    if width <= 0 or height <= 0:
        raise ValueError("grab of a %dx%d rectangle" % (width, height))
    screen = user32.GetDC(None)
    memory = bitmap = None
    info = BITMAPINFO()
    info.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    info.bmiHeader.biWidth = width
    info.bmiHeader.biHeight = -height          # negative: top-down rows
    info.bmiHeader.biPlanes = 1
    info.bmiHeader.biBitCount = 32
    info.bmiHeader.biCompression = BI_RGB
    bits = ctypes.c_void_p()
    try:
        memory = gdi32.CreateCompatibleDC(screen)
        bitmap = gdi32.CreateDIBSection(memory, ctypes.byref(info),
                                        DIB_RGB_COLORS, ctypes.byref(bits),
                                        None, 0)
        if not bitmap:
            raise OSError("CreateDIBSection failed for %dx%d" % (width, height))
        previous = gdi32.SelectObject(memory, bitmap)
        if not gdi32.BitBlt(memory, 0, 0, width, height, screen, x, y,
                            SRCCOPY | CAPTUREBLT):
            raise OSError("BitBlt failed at %d,%d" % (x, y))
        raw = ctypes.string_at(bits, width * height * 4)
        gdi32.SelectObject(memory, previous)
    finally:
        # Every handle, on every path: a GDI leak in a loop that runs
        # once per keystroke is a slow crash rather than a fast one.
        if bitmap:
            gdi32.DeleteObject(bitmap)
        if memory:
            gdi32.DeleteDC(memory)
        user32.ReleaseDC(None, screen)
    return Image.from_bgra(width, height, raw)


# ------------------------------------------------------------------ mouse


def _send(flags, nx=0, ny=0):
    event = INPUT(type=INPUT_MOUSE,
                  mi=MOUSEINPUT(dx=nx, dy=ny, mouseData=0, dwFlags=flags,
                                time=0, dwExtraInfo=0))
    if not user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(INPUT)):
        raise OSError("SendInput refused (error %d)"
                      % ctypes.get_last_error())


def cursor_pos():
    point = wintypes.POINT()
    user32.GetCursorPos(ctypes.byref(point))
    return (point.x, point.y)


def move_to(x, y):
    """Put the pointer on a screen pixel, and check that it got there.

    The absolute form of SendInput takes a 0..65535 fraction of the
    virtual desktop, so the pixel it lands on is the fraction rounded
    back -- off by one often enough to matter when the target is a
    six-pixel dot.  SetCursorPos speaks pixels and settles it.
    """
    left, top, width, height = virtual_rect()
    nx = int(round((x - left) * 65535.0 / max(1, width - 1)))
    ny = int(round((y - top) * 65535.0 / max(1, height - 1)))
    _send(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK,
          nx, ny)
    if cursor_pos() != (x, y):
        user32.SetCursorPos(int(x), int(y))


def click(x, y, settle=0.03):
    move_to(x, y)
    time.sleep(settle)
    _send(MOUSEEVENTF_LEFTDOWN)
    time.sleep(0.02)
    _send(MOUSEEVENTF_LEFTUP)


def drag(x0, y0, x1, y1, settle=0.03, steps=6):
    """Press at one point and release at another, moving in between.

    The intermediate moves are not decoration: software that tracks a
    drag by watching the pointer treats a single jump as a click and a
    teleport, and lets go of whatever it was carrying.
    """
    move_to(x0, y0)
    time.sleep(settle)
    _send(MOUSEEVENTF_LEFTDOWN)
    for step in range(1, steps + 1):
        move_to(int(round(x0 + (x1 - x0) * step / float(steps))),
                int(round(y0 + (y1 - y0) * step / float(steps))))
        time.sleep(0.01)
    time.sleep(settle)
    _send(MOUSEEVENTF_LEFTUP)


def perform(action, settle=0.03):
    """Run one action from placement.Plan."""
    kind = action[0]
    if kind == "click":
        click(action[1], action[2], settle)
    elif kind == "drag":
        drag(action[1], action[2], action[3], action[4], settle)
    elif kind == "move":
        move_to(action[1], action[2])
    else:
        raise ValueError("unknown action %r" % (action,))


# ----------------------------------------------------------------- windows


def foreground_window():
    return user32.GetForegroundWindow()


def focus_window(handle):
    """Hand the keyboard back to the window that had it when we started.

    Windows refuses this from a process that is not already in the
    foreground, which is precisely why it is called while our own
    overlay still is.
    """
    if handle:
        try:
            return bool(user32.SetForegroundWindow(handle))
        except OSError:
            return False
    return False


# ---------------------------------------------------------------- keyboard


class KeyHook(object):
    """A low-level keyboard hook that swallows the keys it is given.

    ``armed`` gates it, so the run can let a keystroke through -- the
    pause key exists so the operator can type in Ariel without this
    program eating it.  Nothing here blocks: ``drain`` returns what has
    arrived since it was last asked.
    """

    def __init__(self, keys, always=()):
        self.keys = set(keys)
        #: Swallowed even while disarmed -- otherwise the key that turns
        #: the hook back on is the one key it is no longer listening for.
        self.always = set(always)
        self.armed = False
        self.queue = collections.deque()
        self._handle = None
        self._proc = None            # kept alive: Windows holds the pointer
        self._down = set()

    def install(self):
        """True if the hook took.  False is a fallback, not a crash."""
        self._proc = HOOKPROC(self._callback)
        self._handle = user32.SetWindowsHookExW(
            WH_KEYBOARD_LL, self._proc, kernel32.GetModuleHandleW(None), 0)
        if not self._handle:
            self._proc = None
            return False
        return True

    def remove(self):
        if self._handle:
            user32.UnhookWindowsHookEx(self._handle)
            self._handle = None
        self._proc = None

    def drain(self):
        """Every (key, shift) seen since the last call, oldest first."""
        out = []
        while self.queue:
            out.append(self.queue.popleft())
        return out

    def _callback(self, code, message, data):
        # Short, always.  A low-level hook that takes longer than the
        # system timeout is removed without being told, and the only
        # symptom is that keys stop arriving.
        if code >= 0:
            key = KBDLLHOOKSTRUCT.from_address(data).vkCode
            if message in (WM_KEYDOWN, WM_SYSKEYDOWN):
                if key in self.keys and (self.armed or key in self.always):
                    shift = bool(user32.GetAsyncKeyState(VK["shift"]) & 0x8000)
                    self.queue.append((key, shift))
                    self._down.add(key)
                    return 1
            elif message in (WM_KEYUP, WM_SYSKEYUP) and key in self._down:
                # Swallow the release of a key whose press we ate, or the
                # foreground app sees half an keystroke it never got.
                self._down.discard(key)
                return 1
        return user32.CallNextHookEx(None, code, message, data)
