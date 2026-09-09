# SPDX-License-Identifier: GPL-3.0-or-later
"""Double-click launcher for anchors.py, for a desktop shortcut.

A .pyw runs under pythonw.exe, which has no console -- which is what
makes it a sensible shortcut and also means sys.stdout can be None and
every print() in the program an AttributeError.  So the output goes to a
log file beside the temp directory and a failure gets a message box,
because a shortcut that does nothing visible when it breaks is worse
than no shortcut.

Arguments are passed through, so a shortcut can carry its own, e.g.

    pythonw ArielAnchors.pyw --confirm-first --colors blue
"""

import os
import sys
import tempfile
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

LOG = os.path.join(tempfile.gettempdir(), "ariel-anchors.log")


def main():
    with open(LOG, "w", encoding="utf-8", buffering=1) as log:
        sys.stdout = sys.stderr = log
        try:
            import anchors
            return anchors.main(sys.argv[1:])
        except SystemExit as stop:
            log.write("\n%s\n" % stop)
            return _tell("Ariel Anchors stopped", str(stop))
        except Exception:                              # noqa: BLE001
            traceback.print_exc(file=log)
            return _tell("Ariel Anchors failed",
                         "Something went wrong.  The details are in\n\n%s"
                         % LOG)


def _tell(title, message):
    """Say it in a box, since there is no console to say it in."""
    try:
        import ctypes
        ctypes.windll.user32.MessageBoxW(None, message, title, 0x10)
    except Exception:                                  # noqa: BLE001
        pass
    return 1


if __name__ == "__main__":
    sys.exit(main())
