"""Runtime tests for DDGPS: the command run end to end in the repo's
AutoLISP VM over synthetic DJI photos, the file reader and the HTTP
call shadowed so no ActiveX is touched.

Why this suite exists: a DJI photo's AbsoluteAltitude is NOT a
sea-level figure.  DJI writes the WGS84 ellipsoid height (or a
barometric estimate seeded from it), and across the United States
the ellipsoid sits 50-115 ft BELOW mean sea level -- so at a
low-lying site a drone 100 ft up records a NEGATIVE altitude, and
"AbsoluteAltitude - ground" comes out underground everywhere.  The
office saw exactly that: "Photo altitude: -12.5 ft" and a refusal.
The same packet carries drone-dji:RelativeAltitude, the barometric
height above the take-off point, good to a foot or two, and that is
the figure DDGPS leads with now; the ground-elevation route is kept
for files that have no RelativeAltitude.

Script notes: file dialog, point, then in the barometric route the
take-off offset (Enter = 0), the text height (Enter = keep) and the
save keyword (Enter = Yes); the GPS route puts no offset question and
asks a site elevation by hand only when the lookup fails.

Run: python3 tests/test_ddgps_runtime.py
     CALOFIN_LISP_ROOT=shared python3 tests/test_ddgps_runtime.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import lispvm  # noqa: E402
from lispvm import VM, NIL, Sym  # noqa: E402
import test_drone_height_lisp as tdh  # noqa: E402  (the photo builders)

HERE = os.path.dirname(__file__)
LSP = os.path.join(HERE, '..', 'lisp', 'drone_height', 'DroneHeightGPS.lsp')

FAILS = []


def check(label, cond, detail=''):
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label}{('  -- ' + detail) if detail else ''}")
        FAILS.append(label)


def reg(name, fn):
    lispvm.BUILTINS[Sym(name.lower())] = fn


# the per-drawing LDATA store DDGPS shares with DroneDistortion.lsp
LDATA = {}
reg('vlax-ldata-get', lambda vm, a: LDATA.get((a[0], a[1]), NIL))
reg('vlax-ldata-put',
    lambda vm, a: (LDATA.__setitem__((a[0], a[1]), a[2]), a[2])[1])

# the alert box, recorded rather than shown
ALERTS = []
reg('alert', lambda vm, a: (ALERTS.append(a[0] if a else ''), NIL)[1])

# the file dialog answers from the script; the size on disk decides
# whether the tail of the file is scanned (over 256 KB)
FSIZE = [4096]
reg('getfiled', lambda vm, a: vm.pop_script(a[0], 'getfiled') or NIL)
reg('vl-file-size', lambda vm, a: FSIZE[0])

USGS = '(list T "{\\"value\\": 296.606}")'      # a real EPQS answer, feet
OFFLINE = '(list nil "no answer (no internet)")'


def newvm(photo, reply=USGS, tail=None):
    """A VM with DDGPS loaded, the photo reader shadowed to hand back
    PHOTO's bytes (and TAIL's for the last-256-KB scan), the elevation
    service shadowed with REPLY and flagged when it is asked."""
    LDATA.clear()
    ALERTS.clear()
    FSIZE[0] = 300000 if tail is not None else 4096
    vm = VM()
    vm.load(LSP)
    vm.globals[Sym('*ddgps-test-bytes*')] = list(photo)
    vm.globals[Sym('*ddgps-test-tail*')] = list(tail) if tail else NIL
    vm.loads('(defun ddg-open-photo (file cnt) '
             '(list *ddgps-test-bytes* file nil))')
    vm.loads('(defun ddg-file-bytes (file cnt tail) *ddgps-test-tail*)')
    vm.loads('(defun ddg-http-get (url) (setq *ddgps-http-hit* T) %s)'
             % reply)
    return vm


def said(vm):
    return ''.join(vm.printed)


def asked(vm, word):
    return sum(1 for p, _ in vm.prompts if word in p)


def http_hit(vm):
    return vm.globals.get(Sym('*ddgps-http-hit*'), NIL) is not NIL


def texts(vm):
    """The TEXT strings the run left in the drawing, top to bottom."""
    return [lispvm._dxf(vm, e, 1) for e in vm.entities
            if e not in vm.deleted and lispvm._dxf(vm, e, 0) == 'TEXT']


def H():
    return LDATA.get(('DRONE_DISTORTION', 'H'))


PT = [100.0, 200.0, 0.0]
FILE = "H:/site/DJI_0001.JPG"

# -3.81 m "above sea level" = -12.5 ft; RelativeAltitude +30.00 m = 98.4 ft
LOW = tdh.build_jpg(with_xmp=True, abs_s=b"-3.81", rel_s=b"+30.00")

# ---------------------------------------------------------------------
# 1. the office's case: a DJI XMP with a negative AbsoluteAltitude
# ---------------------------------------------------------------------
print("a low-lying site: AbsoluteAltitude below zero, RelativeAltitude carries the run")

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, None, None, None])
out = said(vm)
check("no alert at all", not ALERTS, repr(ALERTS))
check("the negative altitude is printed, labelled, and not used",
      'AbsoluteAltitude : -12.5 ft' in out and 'not sea level: not used' in out,
      out[-600:])
check("RelativeAltitude is printed as the figure",
      'RelativeAltitude : 98.4 ft above the take-off point' in out)
check("Enter at the offset = took off from the deck",
      '(took off from the deck)  ->  H = 98.0 ft' in out, out[-400:])
check("H = 98 saved for DDFIX", H() == 98.0, repr(LDATA))
check("the run remembers which route it took",
      abs(LDATA.get(('DRONE_DISTORTION', 'REL_ALT'), 0) - 98.425) < 0.01
      and LDATA.get(('DRONE_DISTORTION', 'TAKEOFF_OFF')) == 0.0, repr(LDATA))
check("the elevation service was never asked", not http_hit(vm))
tx = texts(vm)
check("five lines of text placed", len(tx) == 5, repr(tx))
check("the report justifies itself",
      len(tx) == 5 and tx[0].startswith('GPS position: 32.7157380, -117.1610838')
      and tx[1] == 'RelativeAltitude: 98.4 ft above take-off (barometric)'
      and tx[2] == 'AbsoluteAltitude: -12.5 ft (DJI datum, not sea level - not used)'
      and tx[3] == 'Take-off point vs deck: +0.0 ft'
      and tx[4] == 'Height above deck: 98 ft', repr(tx))
check("the offset question offers Back",
      any('[Back] <0>:' in p for p, _ in vm.prompts if 'Take-off' in p))

# ---------------------------------------------------------------------
# 2. the take-off offset
# ---------------------------------------------------------------------
print("the take-off offset")

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, -4.0, None, None])
check("a launch 4 ft below the deck takes 4 ft off",
      H() == 94.0 and '(take-off below the deck)' in said(vm), said(vm)[-300:])
check("and the report says so",
      'Take-off point vs deck: -4.0 ft' in texts(vm)
      and 'Height above deck: 94 ft' in texts(vm), repr(texts(vm)))

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, 6.0, None, None])
check("a launch 6 ft above the deck adds 6 ft",
      H() == 104.0 and '(take-off above the deck)' in said(vm))

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, -200.0, None, None, None])
check("an offset that puts the drone underground re-asks",
      'check the offset' in said(vm) and asked(vm, 'Take-off') == 2
      and H() == 98.0, said(vm)[-300:])

# ---------------------------------------------------------------------
# 3. Back, all the way through
# ---------------------------------------------------------------------
print("Back")

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, "Back", PT, None, "Back", -4.0, None, None])
check("Back at the offset re-opens the pick; Back at the text height re-opens the offset",
      asked(vm, 'Pick a point') == 2 and asked(vm, 'Take-off') == 3
      and H() == 94.0, repr([p for p, _ in vm.prompts]))

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, None, None, "Back", None, None])
check("Back at the save takes the placed report down and re-asks the height",
      asked(vm, 'text height') == 2 and len(texts(vm)) == 5 and H() == 98.0,
      repr(texts(vm)))

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, PT, None, None, "No"])
check("No at the save leaves H unset", H() is None and 'H unchanged' in said(vm))

vm = newvm(LOW)
vm.run('c:DDGPS', [FILE, None])
check("Enter at the pick aborts quietly",
      'Aborted - no point picked' in said(vm) and not ALERTS and not texts(vm))

# ---------------------------------------------------------------------
# 4. a shot taken before take-off
# ---------------------------------------------------------------------
print("a photo taken on the ground")

vm = newvm(tdh.build_jpg(with_xmp=True, abs_s=b"-33.20", rel_s=b"+0.20"))
vm.run('c:DDGPS', [FILE])
check("RelativeAltitude under a foot is refused loudly",
      len(ALERTS) == 1 and 'PHOTO TAKEN ON THE GROUND' in ALERTS[0]
      and not texts(vm) and H() is None, repr(ALERTS))

# ---------------------------------------------------------------------
# 5. the fallback: a file with no RelativeAltitude (EXIF only)
# ---------------------------------------------------------------------
print("the GPS route for a file with no RelativeAltitude")

# EXIF GPSAltitude 123.456 m = 405.0 ft, ground 296.6 ft -> 108 ft AGL;
# read as above-take-off it would be 405 ft, over the ceiling, so MSL
EXIF_ONLY = tdh.build_jpg(with_xmp=False)
vm = newvm(EXIF_ONLY)
vm.run('c:DDGPS', [FILE, PT, None, None])
out = said(vm)
check("the elevation service is asked", http_hit(vm))
check("no offset question on this route", asked(vm, 'Take-off') == 0)
check("altitude - ground, and it is called rough",
      '405.0 - 296.6 = 108.4 ft  ->  H = 108.0 ft' in out and 'ROUGH' in out,
      out[-500:])
check("H = 108 saved with its ground elevation",
      H() == 108.0 and abs(LDATA.get(('DRONE_DISTORTION', 'GPS_GROUND'), 0)
                           - 296.606) < 1e-6, repr(LDATA))
tx = texts(vm)
check("the report carries the datum caveat",
      len(tx) == 5 and 'rough - datum' in tx[3] and tx[4] == 'Height above grade: 108 ft',
      repr(tx))

vm = newvm(EXIF_ONLY, reply=OFFLINE)
vm.run('c:DDGPS', [FILE, PT, 296.606, None, None])
check("offline: the failure is loud and a typed elevation carries on",
      any('ELEVATION LOOKUP FAILED' in a for a in ALERTS) and H() == 108.0
      and 'entered by hand' in said(vm), said(vm)[-400:])

vm = newvm(EXIF_ONLY, reply=OFFLINE)
vm.run('c:DDGPS', [FILE, PT, None])
check("offline: Enter at the typed elevation aborts with H unchanged",
      H() is None and 'H unchanged' in said(vm))

# a DJI EXIF-only file at a low-lying site: GPSAltitudeRef says below
# sea level - the same ellipsoid figure with nothing to fall back on
vm = newvm(tdh.build_jpg(with_xmp=False, tiffkw={'alt_below': True}))
vm.run('c:DDGPS', [FILE, PT])
check("a negative EXIF altitude with no RelativeAltitude fails loudly and says why",
      len(ALERTS) == 1 and 'DOES NOT MAKE SENSE' in ALERTS[0]
      and 'ellipsoid' in ALERTS[0] and 'no RelativeAltitude' in ALERTS[0]
      and H() is None, repr(ALERTS))

# ---------------------------------------------------------------------
# 6. metadata parked past 256 KB (the tail scan)
# ---------------------------------------------------------------------
print("metadata after the image data")

# the front window: a PNG with nothing in it; the tail: the real chunks
FRONT = tdh.build_png(with_xmp=False, with_exif=False)
TAIL = tdh.build_png()
vm = newvm(FRONT, tail=TAIL)
vm.run('c:DDGPS', [FILE, PT, None, None, None])
check("the tail window is read and parsed (v1.2 took car of the byte list and died)",
      not ALERTS and H() == 100.0, repr(ALERTS) + said(vm)[-300:])

vm = newvm(FRONT)          # under 256 KB: nothing to scan, and it says so
vm.run('c:DDGPS', [FILE])
check("a stripped file is still NO CAMERA METADATA",
      len(ALERTS) == 1 and 'NO CAMERA METADATA' in ALERTS[0])

# ---------------------------------------------------------------------
print()
if FAILS:
    print(f"{len(FAILS)} FAILED: " + ", ".join(FAILS))
    sys.exit(1)
print("all DDGPS runtime checks passed")
