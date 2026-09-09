# SPDX-License-Identifier: GPL-3.0-or-later
"""Place Ariel's deck anchors from the dots already in the photo.

Ariel (Fisherlea) rectifies a near-nadir drone photo to deck scale, and
the operator then digitises the markers taped to the deck -- forty-odd
of them around a pool -- by finding each one and clicking it.  The
finding is mechanical and the checking is not, so this program does the
finding and leaves the checking alone:

    screenshot  ->  pick the area  ->  find the dots  ->  check the list
                ->  for each: click it, magnify it, wait for a yes

Run it with Ariel on screen and the photo where you want it:

    python ariel\\anchors.py

and off the machine, on a screenshot, to see what it would have found:

    python3 ariel/anchors.py --from-shot deck.png --annotate found.png

That second form needs no Windows and no Ariel.  It is how a job that
went wrong gets diagnosed -- save the shot with --save-shot, send it on,
and the thresholds can be worked out somewhere else.

AT EACH ANCHOR
--------------
    Enter / Space   yes, that one -- move to the next
    arrow keys      nudge it one pixel (Shift: ten)
    D               click here again
    S               skip this one
    Backspace       go back one
    P               pause -- let the keyboard through to Ariel
    Esc             stop the run here

The keys work while Ariel has the focus, not this program, because
adjusting an anchor by hand means clicking in Ariel and clicking in
Ariel takes the focus.  A low-level keyboard hook reads them and eats
them so Ariel does not act on them too; where Windows refuses the hook
the magnifier takes the focus instead and says so.

NOT A LISP TOOL
---------------
This is a Windows program, not an AutoLISP routine.  It is not in
LAZPASS.lsp, it has no shared/parts/ twin, it is not on the LAZPANEL
palette and it has no place in any of them: there is no AutoCAD in this
workflow at the point where it runs.  It sits beside the drafting tools
in this repository because it is part of the same job -- see
ariel/README.md.
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import detect        # noqa: E402
import ordering      # noqa: E402
import pixmap        # noqa: E402
import placement     # noqa: E402
import score         # noqa: E402

#: What one press of an arrow key does, before the Shift multiplier.
STEP = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}


# ------------------------------------------------------------------- setup


def build_parser():
    parser = argparse.ArgumentParser(
        prog="anchors",
        description="Find the marker dots in an Ariel photo and place an "
                    "anchor on each one, confirming every placement.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="At each anchor: Enter accept, arrows nudge (Shift x10), "
               "D re-click, S skip, Backspace back, P pause, Esc stop.")

    where = parser.add_argument_group("what to search")
    where.add_argument("--region", metavar="X,Y,W,H",
                       help="skip the picker and search this screen rectangle")
    where.add_argument("--full", action="store_true",
                       help="skip the picker and search the whole desktop")
    where.add_argument("--from-shot", metavar="PNG",
                       help="detect on a saved screenshot and stop; needs no "
                            "Windows")
    where.add_argument("--save-shot", metavar="PNG",
                       help="write the screenshot this run worked from")
    where.add_argument("--annotate", metavar="PNG",
                       help="write the screenshot with every dot ringed and "
                            "numbered")

    order = parser.add_argument_group("what order to click them in")
    order.add_argument("--order", choices=ordering.MODES, default="perimeter",
                       help="default: perimeter, clockwise round the pool")
    order.add_argument("--corner", choices=ordering.CORNERS,
                       default="top-left", help="which corner number 1 is by")
    order.add_argument("--anticlockwise", action="store_true",
                       help="walk the perimeter the other way")

    how = parser.add_argument_group("how to place them")
    how.add_argument("--confirm-first", action="store_true",
                     help="magnify and confirm BEFORE clicking, so a nudge "
                          "is a pointer move instead of a drag; use it if "
                          "Ariel will not let a placed anchor be dragged")
    how.add_argument("--dry-run", action="store_true",
                     help="walk the anchors and move the pointer, but never "
                          "click or drag")
    how.add_argument("--no-review", action="store_true",
                     help="start placing without the check-the-list step")
    how.add_argument("--no-hook", action="store_true",
                     help="do not install the global key hook; the magnifier "
                          "takes the keyboard focus instead")
    how.add_argument("--settle", type=float, default=0.12, metavar="SEC",
                     help="wait after a click before magnifying (0.12)")
    how.add_argument("--start-delay", type=float, default=0.4, metavar="SEC",
                     help="wait before the first click (0.4)")
    how.add_argument("--big", type=int, default=10, metavar="PX",
                     help="pixels a Shift+arrow nudge moves (10)")
    how.add_argument("--zoom", type=int, default=8,
                     help="magnifier enlargement (8)")
    how.add_argument("--view", type=int, default=48, metavar="PX",
                     help="pixels of screen shown in the magnifier (48)")

    tune = parser.add_argument_group("what counts as a dot")
    tune.add_argument("--colors", default="red,blue",
                      help="which markers to look for (red,blue)")
    tune.add_argument("--min-dot", type=int, default=3, metavar="PX",
                      help="smallest dot, either axis (3)")
    tune.add_argument("--max-dot", type=int, default=34, metavar="PX",
                      help="largest dot, either axis (34)")
    tune.add_argument("--red-min", type=int, default=110, metavar="N",
                      help="a red dot's red channel, at least (110)")
    tune.add_argument("--red-gap", type=int, default=45, metavar="N",
                      help="how far red leads green and blue (45)")
    tune.add_argument("--blue-min", type=int, default=95, metavar="N",
                      help="a blue dot's blue channel, at least (95)")
    tune.add_argument("--blue-gap", type=int, default=45, metavar="N",
                      help="how far blue leads red (45)")
    tune.add_argument("--fill", type=float, default=0.45, metavar="F",
                      help="how solid a dot must be, 0-1 (0.45); a circle "
                           "fills 0.78 of its box")
    tune.add_argument("--merge", type=float, default=4.0, metavar="PX",
                      help="dots closer than this are one dot (4)")

    check = parser.add_argument_group(
        "checking it against anchors you placed yourself")
    check.add_argument("--score", metavar="FILE",
                       help="compare what was found with a list of points "
                            "you trust -- what it missed, what it invented, "
                            "how far off each one is, and whether its "
                            "click order is your loop. Needs --from-shot; "
                            "exits non-zero if anything is missing or extra")
    check.add_argument("--score-tol", type=float, default=score.TOLERANCE,
                       metavar="PX",
                       help="how far apart two points can be and still be "
                            "the same anchor (%g)" % score.TOLERANCE)
    check.add_argument("--dump-points", metavar="FILE",
                       help="write the final list, in click order, as a "
                            "point file -- correct it once in the review "
                            "window and this is your answer key from then on")

    parser.add_argument("--quiet", action="store_true",
                        help="only the closing summary")
    return parser


def tuning_from(args):
    colors = tuple(c.strip().lower() for c in args.colors.split(",")
                   if c.strip())
    unknown = [c for c in colors if c not in detect.HUE]
    if unknown:
        raise SystemExit("anchors: unknown colour %s (known: %s)"
                         % (", ".join(unknown), ", ".join(sorted(detect.HUE))))
    return detect.Tuning(red_min=args.red_min, red_gap=args.red_gap,
                         blue_min=args.blue_min, blue_gap=args.blue_gap,
                         min_size=args.min_dot, max_size=args.max_dot,
                         fill=args.fill, merge=args.merge, colors=colors)


def parse_region(text):
    try:
        parts = [int(p) for p in text.replace(" ", "").split(",")]
    except ValueError:
        parts = []
    if len(parts) != 4 or parts[2] <= 0 or parts[3] <= 0:
        raise SystemExit("anchors: --region wants X,Y,W,H with a positive "
                         "width and height, got %r" % text)
    return tuple(parts)


def order_of(args):
    return {"mode": args.order, "corner": args.corner,
            "clockwise": not args.anticlockwise}


def say(args, text):
    if not args.quiet:
        print(text)
        sys.stdout.flush()


# ----------------------------------------------------------------- offline


def offline(args):
    """--from-shot: detect on a PNG, report, and optionally draw the result."""
    shot = pixmap.read_png(args.from_shot)
    origin = (0, 0)
    if args.region:
        x, y, width, height = parse_region(args.region)
        shot = shot.crop(x, y, width, height)
        origin = (x, y)
    started = time.monotonic()
    dots = detect.find_dots(shot, tuning_from(args))
    elapsed = time.monotonic() - started
    colors = {d.point: d.color for d in dots}
    points = ordering.sequence([d.point for d in dots], **order_of(args))

    say(args, "%s  %dx%d" % (args.from_shot, shot.width, shot.height))
    say(args, "%d dots in %.2fs  (%s)"
        % (len(dots), elapsed,
           ", ".join("%d %s" % (sum(1 for d in dots if d.color == name), name)
                     for name in sorted({d.color for d in dots})) or "none"))
    if points and not args.quiet:
        print("\n  #        x        y   colour   size")
        for index, point in enumerate(points):
            dot = min(dots, key=lambda d, p=point:
                      (d.x - p[0]) ** 2 + (d.y - p[1]) ** 2)
            print("  %-3d %7d  %7d   %-6s   %dx%d"
                  % (index + 1, point[0] + origin[0], point[1] + origin[1],
                     dot.color, dot.width, dot.height))
        print("\n  travel: %.0f px" % ordering.walk_length(points))
    by_index = {i: colors.get(p, "blue") for i, p in enumerate(points)}
    if args.annotate:
        pixmap.write_png(args.annotate, pixmap.annotate(shot, points,
                                                        by_index))
        say(args, "wrote %s" % args.annotate)
    placed = [(x + origin[0], y + origin[1]) for (x, y) in points]
    if args.dump_points:
        score.write_points(args.dump_points, placed, by_index,
                           "from %s, %s%s" % (args.from_shot, args.order,
                                              "" if not args.anticlockwise
                                              else " anticlockwise"))
        say(args, "wrote %s" % args.dump_points)
    if args.score:
        truth = score.read_points(args.score)
        lines, clean = score.report(truth, placed, by_index, args.score_tol)
        print("\nscored against %s (within %g px)"
              % (args.score, args.score_tol))
        print("\n".join(lines))
        return 0 if clean else 3
    return 0


# ------------------------------------------------------------------ the run


class Hands(object):
    """Performs a plan's actions, or pretends to.

    Reports whether anything was done that Ariel has to REDRAW, which is
    what the settle pause is waiting for.  A pointer move is not: paying
    a tenth of a second for one after every arrow key makes nudging feel
    broken, and nudging is the thing an operator does most.

    A dry run answers the same way it would have, so the walk paces
    itself the same and is worth watching.
    """

    def __init__(self, winio, dry_run, settle):
        self.winio = winio
        self.dry_run = dry_run
        self.settle = settle
        self.clicks = 0

    def do(self, actions):
        redraws = False
        for action in actions:
            if action[0] in ("click", "drag"):
                redraws = True
                if self.dry_run:
                    continue
                self.clicks += 1
            self.winio.perform(action, self.settle)
        return redraws


def run(args):
    """The Windows run: grab, pick, find, check, then place one at a time."""
    try:
        import winio
    except ImportError as problem:
        raise SystemExit("anchors: %s" % problem)
    import overlay

    awareness = winio.dpi_aware()
    target = winio.foreground_window()
    screen = winio.virtual_rect()
    say(args, "screen %dx%d at %d,%d  (DPI awareness: %s)"
        % (screen[2], screen[3], screen[0], screen[1], awareness))
    shot = winio.grab(*screen)
    if args.save_shot:
        pixmap.write_png(args.save_shot, shot)
        say(args, "wrote %s" % args.save_shot)

    view = overlay.Overlay()
    try:
        if args.region:
            region = parse_region(args.region)
        elif args.full:
            region = screen
        else:
            region = view.pick_region(shot, (screen[0], screen[1]))
        if region is None:
            say(args, "cancelled at the region picker")
            return 1

        patch = shot.crop(region[0] - screen[0], region[1] - screen[1],
                          region[2], region[3])
        started = time.monotonic()
        dots = detect.find_dots(patch, tuning_from(args))
        say(args, "%d dots in %.2fs over %dx%d"
            % (len(dots), time.monotonic() - started, patch.width,
               patch.height))
        if not dots:
            say(args, "nothing found -- try --min-dot 2, or --red-gap/"
                      "--blue-gap lower, or --colors blue")
            return 1

        order = order_of(args)
        if args.no_review:
            points = [(x + region[0], y + region[1]) for (x, y) in
                      ordering.sequence([d.point for d in dots], **order)]
        else:
            answer = view.review(patch, (region[0], region[1]), dots, order)
            if answer is None:
                say(args, "cancelled at the review")
                return 1
            points, order = answer
        say(args, "placing %d anchors, %s%s"
            % (len(points), order["mode"],
               "" if order["clockwise"] else " anticlockwise"))
        if args.dump_points:
            # Relative to the SCREENSHOT, not the screen.  The only thing
            # that reads this file is --score, and --score runs on a saved
            # shot -- so on a desktop whose top-left is not 0,0 (any
            # machine with a monitor to the left of the primary) screen
            # coordinates would put every anchor out by the origin and the
            # score would be nonsense.  The origin is in the header so the
            # mapping back is not lost.
            score.write_points(
                args.dump_points,
                [(x - screen[0], y - screen[1]) for (x, y) in points], None,
                "relative to the screenshot; screen origin was %d,%d. "
                "%s%s" % (screen[0], screen[1], order["mode"],
                          "" if order["clockwise"] else " anticlockwise"))
            say(args, "wrote %s" % args.dump_points)

        winio.focus_window(target)
        time.sleep(args.start_delay)
        return place(args, view, winio, overlay, points, screen)
    finally:
        view.close()


def place(args, view, winio, overlay, points, screen):
    """The confirm-every-one loop."""
    plan = placement.Plan(points, click_first=not args.confirm_first)
    hands = Hands(winio, args.dry_run, args.settle)
    magnifier = overlay.Magnifier(view, winio.grab, screen, args.view,
                                  args.zoom)

    names = {code: name for name, code in winio.VK.items()}
    hook = None
    if not args.no_hook:
        hook = winio.KeyHook([winio.VK[n] for n in
                              ("enter", "escape", "space", "backspace",
                               "left", "up", "right", "down", "s", "d", "p")],
                             always=[winio.VK["p"]])
        if not hook.install():
            hook = None
    feed = None
    if hook is not None:
        hook.armed = True

        def feed():                                  # noqa: F811
            return [(names[code], shift) for (code, shift) in hook.drain()
                    if code in names]

    keyboard = ("keys read globally -- leave the focus in Ariel"
                if hook else
                "click this window before pressing a key (no global hook)")
    say(args, keyboard)
    paused = False
    #: Which anchor has been opened.  enter() runs once per anchor and
    #: not once per keystroke: in click-first mode it moves the pointer
    #: back onto the stored point, and doing that after every key drags
    #: the pointer out from under an operator who is mid-adjustment.
    entered = -1
    try:
        while not plan.done:
            index, total = plan.progress()
            if plan.index != entered:
                entered = plan.index
                if hands.do(plan.enter()):
                    time.sleep(args.settle)
            point = plan.current
            state = "placed" if plan.current_placed else "not placed yet"
            magnifier.show(
                point, "anchor %d of %d   (%s)" % (index, total, state),
                "PAUSED -- P to resume" if paused else
                "Enter ok  •  arrows nudge  •  D re-click  •  S skip  "
                "•  Backspace back  •  Esc stop")
            if hook is None:
                magnifier.focus()
            key, shift = view.next_key(feed)
            step = args.big if shift else 1

            if key in ("enter", "space"):
                say(args, "  %3d/%d  %s" % (index, total, plan.current))
                hands.do(plan.accept())
            elif key in STEP:
                dx, dy = STEP[key]
                hands.do(plan.nudge(dx * step, dy * step))
            elif key == "d":
                hands.do(plan.place())
                time.sleep(args.settle)
            elif key == "s":
                say(args, "  %3d/%d  skipped" % (index, total))
                plan.skip()
            elif key == "backspace":
                plan.back()
            elif key == "escape":
                plan.stop()
            elif key == "p":
                paused = not paused
                if hook is not None:
                    hook.armed = not paused
    except KeyboardInterrupt:
        plan.stop()
    finally:
        magnifier.hide()
        if hook is not None:
            hook.armed = False
            hook.remove()

    tally = plan.summary()
    print("%d of %d anchors placed%s%s%s"
          % (tally["placed"], tally["total"],
             ", %d skipped" % tally["skipped"] if tally["skipped"] else "",
             ", %d not reached" % tally["untouched"] if tally["untouched"]
             else "",
             "  (dry run -- nothing was clicked)" if args.dry_run else ""))
    return 0 if not tally["untouched"] else 2


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.score and not args.from_shot:
        raise SystemExit(
            "anchors: --score compares a detection run with a list you "
            "trust, so it needs a fixed picture to run on: pass "
            "--from-shot as well. Use --save-shot on the machine to make "
            "one.")
    if args.from_shot:
        return offline(args)
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
