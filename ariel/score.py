# SPDX-License-Identifier: GPL-3.0-or-later
"""Hold a detection run against points a person placed by hand.

The reference for this program is a pair of screenshots: a deck photo,
and the same photo after an operator has clicked all forty-four anchors
into Ariel.  The second one is an answer key -- it says where a human
decided each anchor goes -- and an answer key is worth more than an
opinion about whether the output "looks right".

So: a point file is a list of the anchors somebody trusts, the detector
produces its own list, and this module says how far apart the two are.
Three separate questions, because they fail separately and are fixed by
different knobs:

**Did it find them?**  Matched, missed, invented.  A miss is a threshold
(--red-gap, --blue-min, --min-dot); an invention is usually the opposite
one, or --max-dot letting something large through.

**Did it find them in the right PLACE?**  The offset in pixels between
each pair.  Recall can be perfect while every centroid sits two pixels
low, which is the kind of thing nobody notices by eye and everybody
notices in the finished drawing.

**Did it find them in the right ORDER?**  Compared as a CYCLE, not a
list.  A perimeter walk that starts at a different dot is the same walk
-- the operator's number 1 is a preference, not a fact -- so reporting
that as forty-four errors would bury the one thing that IS an error:
going round the pool the other way, or not going round it at all.

The matching is greedy on distance rather than optimal.  With markers
metres apart on a deck the two agree, and a greedy pass is short enough
to read.
"""

import math

#: How far apart two points can be and still be the same anchor.  Eight
#: pixels is about a marker and a half at the zoom these photos are
#: worked at: close enough that nothing pairs with its neighbour, loose
#: enough that a centroid landing on the other side of a dot still
#: counts as found.
TOLERANCE = 8.0


def read_points(path):
    """Read a point file: `x,y` or `x y` a line, optional colour third.

    `#` starts a comment, anywhere.  Blank lines are skipped.  A line
    that is not two numbers is an error naming its number, because a
    silently dropped anchor makes the score better and the answer wrong.
    """
    points = []
    with open(path, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            text = line.split("#", 1)[0].replace(",", " ").strip()
            if not text:
                continue
            parts = text.split()
            try:
                x, y = float(parts[0]), float(parts[1])
            except (IndexError, ValueError):
                raise ValueError("%s line %d: expected `x, y[, colour]`, "
                                 "got %r" % (path, number, line.strip()))
            points.append((x, y, parts[2].lower() if len(parts) > 2 else None))
    return points


def write_points(path, points, colors=None, note=None):
    """Write a point file in the order given -- that order is the answer.

    Written so a run that came out right can be frozen as the answer key
    for the next one: correct the list in the review window once, dump
    it, and from then on --score says whether anything moved.
    """
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("# ariel anchor points\n")
        if note:
            handle.write("# %s\n" % note)
        handle.write("# x, y, colour -- in click order\n")
        for index, (x, y) in enumerate(points):
            color = (colors or {}).get(index) or (colors or {}).get((x, y))
            handle.write("%d, %d%s\n" % (int(round(x)), int(round(y)),
                                         ", " + color if color else ""))


def match(truth, found, tolerance=TOLERANCE):
    """Pair up two point lists.  (pairs, missed, extra), all by index.

    `pairs` is (truth index, found index, distance), nearest first.
    """
    # Both lists are read as (x, y, ...): a point file carries a colour
    # third and the detector's own points do not, and neither caller
    # should have to strip it before asking the question.
    candidates = []
    for ti, target in enumerate(truth):
        tx, ty = target[0], target[1]
        for fi, point in enumerate(found):
            gap = math.hypot(point[0] - tx, point[1] - ty)
            if gap <= tolerance:
                candidates.append((gap, ti, fi))
    candidates.sort()
    pairs = []
    used_truth = set()
    used_found = set()
    for gap, ti, fi in candidates:
        if ti in used_truth or fi in used_found:
            continue
        used_truth.add(ti)
        used_found.add(fi)
        pairs.append((ti, fi, gap))
    pairs.sort()
    missed = [i for i in range(len(truth)) if i not in used_truth]
    extra = [i for i in range(len(found)) if i not in used_found]
    return pairs, missed, extra


def cycle_match(order):
    """How well a permutation is a rotation of 0..n-1, either way round.

    `order` is the truth index of each point in the order the detector
    would click them.  Returns (direction, agreeing): `agreeing` counts
    the positions that land where the best-fitting rotation says they
    should, so n of n means the two walks are the same loop and anything
    less is a real disagreement about the route.

    Where the walk STARTS is not asked about here -- that is order[0],
    and it is a preference rather than a mistake.
    """
    count = len(order)
    if count < 3:
        return ("same", count)
    best = ("same", -1)
    for name, walk in (("same", order), ("reversed", list(reversed(order)))):
        for start in range(count):
            agreeing = sum(1 for i, value in enumerate(walk)
                           if value == (start + i) % count)
            if agreeing > best[1]:
                best = (name, agreeing)
    return best


def report(truth, found, colors=None, tolerance=TOLERANCE, limit=12):
    """The whole comparison as lines of text, and whether it was clean."""
    pairs, missed, extra = match(truth, found, tolerance)
    gaps = sorted(gap for _t, _f, gap in pairs)
    lines = ["  truth %d   found %d   matched %d   missed %d   invented %d"
             % (len(truth), len(found), len(pairs), len(missed), len(extra))]

    if gaps:
        middle = gaps[len(gaps) // 2]
        worst = max(pairs, key=lambda p: p[2])
        lines.append("  offset: mean %.1f px, median %.1f, worst %.1f "
                     "(your #%d)"
                     % (sum(gaps) / len(gaps), middle, worst[2], worst[0] + 1))

    told = [t[2] if len(t) > 2 else None for t in truth]
    if colors and any(told):
        agree = sum(1 for ti, fi, _g in pairs
                    if told[ti] and told[ti] == colors.get(fi))
        named = sum(1 for ti, _f, _g in pairs if told[ti])
        lines.append("  colour: %d of %d agree" % (agree, named))

    if len(pairs) == len(truth) == len(found) and len(truth) >= 3:
        order = [ti for ti, fi, _g in sorted(pairs, key=lambda p: p[1])]
        direction, agreeing = cycle_match(order)
        if agreeing == len(order):
            lines.append("  order: your loop%s, starting at your #%d"
                         % ("" if direction == "same"
                            else " walked BACKWARDS", order[0] + 1))
        else:
            lines.append("  order: NOT your loop -- %d of %d positions "
                         "agree with the closest rotation"
                         % (agreeing, len(order)))
    elif len(truth) >= 3:
        lines.append("  order: not compared -- the two lists are not the "
                     "same set of points")

    for name, indices, source in (("missed (yours, not found)", missed, truth),
                                  ("invented (found, not yours)", extra,
                                   found)):
        if not indices:
            continue
        lines.append("")
        lines.append("  %s:" % name)
        for index in indices[:limit]:
            point = source[index]
            lines.append("    #%-3d %d, %d" % (index + 1, round(point[0]),
                                               round(point[1])))
        if len(indices) > limit:
            lines.append("    ... and %d more" % (len(indices) - limit))

    return lines, not missed and not extra
