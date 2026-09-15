# calofin changelog

Per-tool version banners (`POOL 082726 REV17`, `DIMCHECK v1.4`, ...) say
what changed in one file and drive its `releases/` twin. This file says
which set of them shipped together. The release name lives in
`RELEASE` at the top of `tools/build_shared_bundle.py`, so
`shared/LAZPASS.lsp` announces it on load and cannot drift from it.

## v3.15 -- 2026-09-15

**...and they are LIVE at the picks that need them.**  OASIS v9.0, SPA
091526 REV24, PERPPTS/CPERPPTS v0.15.  "My snaps got cleared" is also
what a drafter says when snaps are off where they expect them on, and
the sweep found both directions of that.

`PERPPTS` and `CPERPPTS` were the first shape again, one level down:
the whole handler is `(perp:finish)`, and the bad ordering was INSIDE
that helper -- the bare `(command)` drain at the top, the OSMODE
restore fourteen forms below it.  `check_osnap.py` had not seen it,
because it read only the handler's own statements and saw one call that
both restores and can throw.  It now splices a called helper's
statements in where the call sits, and catches it.  The cleanup puts
the settings back first in both files.

`SPA`'s base point -- the one pick that places the whole spa -- was made
with snaps already off.  `spa:readblock` runs before SPA's three opening
questions and ends on `spa:osdown` like every ask helper here, so OSMODE
was 0 by the time the prompt came up, thirty lines before the
`(setvar "OSMODE" 0)` that was supposed to be what dropped them.  The
comment at that prompt has always said the pick is made with the
drafter's own snaps live; the `spa:osup` that makes it true is new, and
POOL and POOLSIDE have always held them at the identical prompt.

`OASIS` had the inverse: its `oasis:osup` window wrapped the whole
`oasis:askbottom` call, but that defun does not stop at questions -- it
goes on to `oasis:drawbottom`, which feeds computed points to three
`DIMALIGNED` calls and a hopper-offset cross dim.  Those four were the
only dimensions of the run laid down with running osnap live, free to
be pulled onto whatever the outline passed near.  Snaps drop between
the asking and the drawing now.

Neither of these last two moves OSMODE at the END of a run, which is
why `check_osnap.py` stayed green through both: it checks what the
drafter is left with, not what the tool works under.  Which prompt
ought to snap is an editorial question, so it stays with the reviewer.

**...and they come back even when the cleanup itself fails.**  OASIS
v8.9, AUTOBEAD v1.9, XFTCONV/XFTRECONV v1.17, SPA 091526 REV23.  The
first pass proved every command HAS an OSMODE restore in its `*error*`
handler.  It could not see whether that restore is ever REACHED.  An
error raised inside `*error*` aborts the handler, so a restore sitting
behind a form that can throw is a restore that does not run on the one
path it was written for.

Four handlers had them the wrong way round.  OASIS opened with
`oasis:dimstyrestore`, the one unwrapped `-DIMSTYLE` restore in the
standalone tier -- and it sat ABOVE the pending-command valve whose own
comment says an Esc part-way through a dimension leaves that command
pending and anything below would be read as answers to it.  So on
exactly that Esc, the style restore was fed into the pending command
and took `oasis:sysrestore` down with it.  AUTOBEAD, XFTCONV and
XFTRECONV each put their bare-`(command)` drain ahead of the only
OSMODE restore they have; XFTCONV's also pops the error mode, so a
throw there stranded the pop and refused `command-s` inside every later
handler for the rest of the session.  The settings now go back first in
all four -- putting back a value the run captured itself is pure
`setvar` and cannot throw -- and OASIS's `-DIMSTYLE` is wrapped in
`vl-catch-all-apply`, the shape its six siblings already used and the
shape the grouped build got right via `cal:dimstyrestore`.

`spa:sysrestore` had the mirror-image bug: its
`(setq spa:*sysold* nil)` sat BEHIND a bare `-DIMSTYLE`.  OSMODE came
back, but a throw left the snapshot standing -- and `spa:syssave`
refuses to overwrite a snapshot that exists, because a second save
mid-run would capture the zeroed OSMODE and restore 0 for ever.  So one
failed SPA run froze the drafter's snaps at that run's value for the
rest of the session, silently undoing anything they ticked in Drafting
Settings afterwards.  The snapshot is dropped before the command now,
and the command is wrapped.

`tools/check_osnap.py` grew both rules, so neither shape can come back:
no throwable form ahead of the OSMODE restore in a handler, and no
snapshot drop behind one.  Run against the pre-fix source it names all
five sites.

**The drafter's object snaps come back from a failed run too.**
COVERCHECK v1.18, DIMCHECK v1.21, LINFINCHECK v2.17, and a new
`tools/check_osnap.py` in `make check`. Forty-three commands here mute
`OSMODE` while they feed computed points to `(command ...)`, so a
running osnap cannot pull a pick onto nearby geometry. Forty of them
already put it back on both the clean exit and the one that throws --
either directly from a local of the command, which the nested `*error*`
handler can see, or through the `tool:sysrestore` snapshot that leads
with OSMODE.

Three did not, and they were the three check tutorials. `cchk:tut-build`,
`dchk:tut-dim` and `lfc:tut-dim` each save OSMODE into a local of their
OWN, zero it round a `DIMLINEAR` and put it back inline -- correct as
far as it goes, and out of reach of the command's handler, which is the
only code that runs when the drafter hits Esc. `TUTORIALCOVERCHECK`
already held ATTDIA/ATTREQ/FILEDIA itself for exactly that reason; all
three now hold OSMODE the same way, restored FIRST in the handler
before anything below it can throw. Snaps left off are not a failure
that looks like the tool's: the drafter meets it two commands later,
when a line drawn by eye refuses to snap to an endpoint.

`check_osnap.py` is what keeps it answered. It reads each command's
whole reach across the tier -- POOLDEMO's restore is POOL's
`pool:sysrestore`, in another file -- and fails one that can change
OSMODE without restoring it on the way out, or without restoring it
from its `*error*` handler. `--list` prints all forty-three and how each
puts it back.

**A failure report can be replayed, and its inputs varied, without
AutoCAD.**  A report said what the drafter answered and where the tool
died; it did not say WHICH answer mattered.  Three things changed so
that it can:

* **Every input is in the transcript, typed.**  `check_lazdiag --fix`
  reached only the ask helpers before -- 97 of the tree's 410 input
  sites.  It now records every `get*` and `entsel`: after a
  `(setq v (getX ...))` that is a body statement, and wrapped as
  `((lambda (v) (if lzd:ask (lzd:ask "prompt" v) v)) (getX ...))`
  where the answer is read in place -- a `while`'s test, a keyword
  inside `(= ...)`, the `getstring` that only pauses -- so the `nil`
  that ends a loop is written down like any other answer.  The codemod
  tells a body statement from a value something reads, because a
  record dropped in after a `while`'s test would have run only when
  the test passed.  The answers are typed on the way out (`nil`,
  `12.5`, `"Yes"`, `(x y z)`, `(<ent> (x y z))`; a real keeps its
  point whatever DIMZIN does to `rtos`), a selection gets a line of
  its own at the step it was taken, and the report says how many of
  the entities it copied were the run's INPUT and where they sit in
  the file.  311 sites wired; a second `--fix` is a no-op.
* **THE INPUTS, AND WHAT IS ODD ABOUT THEM.**  A new report section
  reads the answers against each other: a zero, a negative, a tiny or
  a huge number, two lengths that are the same number, two picks on
  one spot -- and says when nothing stands out, because ordinary
  inputs point at the code.
* **`tools/probe_report.py REPORT.dxf`.**  Loads the tool the report
  names at the version it names (its `releases/` twin when there is
  one) into the test VM, hands it the report's geometry and answers,
  and confirms the same failure comes back.  Then one answer at a time
  -- 1, 0, half, double, a step either side, ten times, a thousand; a
  point moved -- and a verdict per answer: NOT this value (the same
  failure whatever it is), THIS value (any other runs clean), or a
  boundary (fails up to 4, passes from 20: a range the tool never
  checks).  A tool that selects is handed the copied input back at
  its `ssget`, without the output the failed run drew beside it.  When
  the control run does not reproduce -- a whole-drawing sweep the
  report could not carry, a file dialog -- it says so rather than
  probing.  Writes `REPORT.probe.txt` beside the report, `.probe.json`
  with `--json`.

LAZDIAG v1.3.  `tests/test_lazdiag_probe.py` makes reports the way real
ones are made -- fixture tools wired by the codemod, run beside
LAZDIAG, failed -- and probes them; `tests/test_lazdiag.py` covers the
codemod's placement rules and the oddities section.  Two VM fixes on
the way: `LASTPROMPT` is what AutoCAD showed last, not a setting a run
can be said to have changed, and a division by zero is an AutoLISP
error -- "divide by zero" -- that reaches the handler for a real as
much as for an int, rather than a Python one.

**LINGUTTER keeps a radius call-out on the perimeter, and asks before
it spares a cross dim.** LINGUTTER v2.6. A corner radius under a foot
lands in `STANDARD INCHES` the same as any other short measurement --
which is not in `lg:*perimstyles*`, so the very call-out for the corner
`PADDLE` was about to pad used to be the thing erased. A RADIUS or
DIAMETER dimension on the perimeter is now kept regardless of its
style, judged on its one attachment point (DXF 10) the way
`lg:*perimstyles*` dims are judged on 13/14.

`CROSS DIM*` dims stop being kept unconditionally: LINGUTTER now asks
"Keep CROSS DIMENSIONS?" once, and a Yes spares only the ones that
belong to the pool just gutted -- every attachment point either inside
the traced perimeter or within `lg:*ontol*` of it, so a cross dim
answering to a second pool sitting in the same highlight is no longer
swept up with it. Answered No, those dims get no exemption at all and
are judged, and counted, like any other style. Neither question is a
confirmation to erase -- LINGUTTER still never asks that.

**Every AB note leads with a bullet.** `ABMOVE` and `ABPCREATE` leave a
note per point on one layer, and a run that settles several of them
leaves a column -- which read as loose text rather than as a list.
`abf:*note-prefix*` (`- `) goes on inside `abf:note`, so every note
carries it and one worded later cannot quietly miss it: one call is one
TEXT is one line.  Set it to `""` for the bare wording.


**A themeable colour space for what KIND of thing is drawn, not just
the screen it's drawn on.** COVERCHECK v1.17, DIMCHECK v1.20,
LINFINCHECK v2.16, LAZPANEL v3.30. `cal:ink` already answered "what ACI
suits this background" for four roles (`fade`/`guide`/`dim`/`hi`); it
did not know anything about what KIND of thing was being marked. Three
review tools had separately hand-picked the answer to that question
eight times over: `flag`/`arc`/`olap`/`orig`/`sugg`/`point`/`constr`/
`report`, the same ACI numbers, copied byte-for-byte into COVERCHECK,
DIMCHECK and LINFINCHECK, with nothing to stop the three copies from
drifting apart the next time one of them changed.

`cal:ink` (and each of the three tools' standalone `:ink` copies) now
carries those eight roles too, resolved the same way a screen-aware
role is -- `'auto` for the table, a number for exactly that number --
except there is no dark/light spread to measure, since these are the
same ordinary ACI colours on any background the review tools have ever
drawn on. What IS new is `CalofinInk-<ROLE>` in the AutoCAD profile: a
per-role override, on any of the twelve roles now, that beats the
table but never a knob left as a plain number. `CALSET` grew an
`Itemcolors` menu to write it, so a drafter who wants COVERCHECK's
"flagged" markup in a different colour no longer edits three `.lsp`
files by hand to get it consistently.

**A line of dimensions is one dimension.**  `CLEARDIM` v3.0.  Where
several dimension lines are the same straight line -- what
`DIMCONTINUE` lays down by the handful and `AUTODIM` lays whole
perimeters out as -- they are a RUN now: one continuous dimension with
breaks in it.  Three things follow, and all three are what a drafter
would do.

**A run's text stays in its own segment.**  AutoCAD centres each text
between its own extension lines, and one shuffled past them reads as
the dimension for the span next door.  So a run member has LESS room
along the track than a lone dimension, not more -- which is the thing
that was quietly wrong before: a chain of short dimensions came out
with its texts slid two segments along, each one sitting over somebody
else's span.

**A run's own skeleton is its own.**  Its dimension line and its
extension lines belong to one dimension, not several: a continued chain
does not merely have extension lines near each other, it SHARES them --
the line at the end of one segment is the line at the start of the
next.  While a run is straight this changes nothing, because every
member's line already IS its own line.  It is what makes a staggered
run possible at all: without it, the step of a staggered dimension's
line and its lengthened extension lines land on the neighbour's text
and there is nowhere left to go.

**When one member has to stand further off the work, they all go.**
Moving one dimension off a wall and leaving its neighbours behind
trades a crowded dimension for a crooked run.

And when a run's own members are what crowd each other -- four segments
thirty wide with text forty wide, where there is nowhere along the
track to go because every text overhangs its own segment whatever it
does -- the run is STAGGERED: every other dimension stands a row
further off the work, its own dimension line with it, and every text
stays centred where it belongs.  Which of the two happens is decided by
WHO is in the way: run-mates alone means stagger, anything else means
the whole run goes.  A row is `cd:*row-f*` text heights, the unit
AUTODIM already stands its own chains off the work in
(`ad:*text-offsets*`).

Only a linear or aligned dimension joins a run: a radius keeps the
CENTRE of its circle in group 10 and an ordinate its feature, so there
is no dimension line there to be collinear with, and pushing one "out"
would move the dimension onto a different circle rather than clear of
an obstacle.

The new move is a real one -- group 10 and group 11 together, the
definition points left alone so the extension lines stretch and the
dimension goes on measuring exactly what it measured.  A run only ever
stands FURTHER off the work, never nearer; there is no version of
"clear of an obstacle" that runs toward the thing being measured.

`tests/test_cleardim.py` is at 77 and runs at both tiers.

**The text box was thirty times too small, so CLEARDIM did nothing.**
v2.1.  A drawing came back with two `CROSS DIMENSIONS` diagonals
printing on top of each other in the middle of a rectangle, and
`CLEARDIM` had reported the sheet "6 already clear - left alone".

The measurement was wrong, three times over, and the first one was
fatal:

* **A text style with a fixed height beats DIMTXT.**  A dimension style
  is entitled to leave DIMTXT at its 0.18 DXF default and keep the real
  height on the text style it points at through DIMTXSTY (group 340) --
  and every style in that drawing did.  Reading DIMTXT alone made a
  6-unit text measure 0.18.  Every box was a speck, nothing could
  overlap anything, and the whole sheet was "clear".  The fixed height
  is used exactly as it stands, DIMSCALE included: that drawing keeps
  STANDARD at DIMSCALE 1.5 pointing at an 8-unit style, and the MTEXT
  in the dimension's own block is 8.0 high, not 12.
* **Markup is not letters.**  150 of the 152 MTEXTs in it carry
  formatting, and counting `\A1;2{\H1.000000x;\S3/4;}"` as 26 glyphs
  instead of about 4 does not err on the safe side -- it fills a sheet
  with obstacles that are not there and leaves every dimension with
  nowhere clear to go.  `%%d` codes, `\A;` `\H;` `\f;` `{}` markup,
  the `\L` `\O` `\K` toggles and a stacked `\S1/2;` (as wide as its
  longer half) are all read for what they DRAW now.  An MTEXT split
  across group 3 chunks is measured whole rather than by its tail.
* **A measurement is spelled the way its STYLE says**, off DIMLUNIT
  (277) and DIMDEC (271), not the drawing's LUNITS and LUPREC.  That
  drawing reads 1/8" off its styles and 1/16" off its header, and
  `33'-3"` is half the width of `33'-2 15/16"`.  The text style's own
  width factor is read too.

Against that drawing's model space the answer is now four dimensions
left alone and the two diagonals slid apart, which is the whole of what
was wanted.  Every string the tool works out for those six dimensions
matches the MTEXT in the dimension's own block character for character
-- which is the check that says the units reading is right and not just
different.  `tests/test_cleardim.py` is at 66, the last of them that
drawing's own geometry, groups and all.

**Every dimension has a track now, not just the straight ones.**
`CLEARDIM` v2.0. v1.0 moved linear and aligned text and counted the
other four families in the report as "on a track that is not a straight
dimension line" -- true, and not much use to a drafter whose angular
callout is the one sitting on a wall. All four have a track; none of
them is a straight dimension line:

| Family | Its track |
| --- | --- |
| angular, 2-line and 3-point | the dimension ARC, about the angle's vertex |
| radius, diameter | the radial line it is measured along |
| ordinate | the leader, along the axis it reads |

The track is an abstraction now rather than a base point and a
direction, and its parameter is a DISTANCE in every case -- an arc
length round an arc rather than an angle. That is what lets
`cd:*step-f*` and `cd:*reach-f*` go on meaning the same thing on a
dimension arc as on a straight dimension line, instead of needing a
second pair of knobs kept in step with the first. What "stays on its
track" means differs by shape and is the same in substance: a linear
text keeps its offset above the dimension line to the last decimal, an
angular one keeps the RADIUS it rides at, and the box TURNS as it goes
round, because text set along a dimension arc turns with it unless
`DIMTIH` holds it upright.

The vertex is the one thing that has to be right, and the two kinds of
angular dimension keep it in different places: a 3-point one writes it
into group 15 outright, while a 2-line one keeps no vertex at all -- it
is where the two measured lines cross, on the INFINITE lines rather than
the drawn segments. So it is checked before it is trusted: the sweep
between the two rays IS the angle the dimension measures, and group 42
is what it measured, so a vertex those two disagree about is refused and
the dimension is left alone. A track guessed wrong does not move text
along the dimension, it moves it OFF it, which is the one thing this
tool exists not to do. Parallel lines, a missing leader end and a
missing text point are refused the same way, and every refusal is
counted in the report.

The radius and diameter layouts are the repo's own: `AutoDim`'s
`ad:raddimpts` already says a radius dimension puts the CENTRE in group
10 and a point on the circle in 15, while a diameter writes the two ENDS
of the diameter and has no centre of its own.

The ordinate is the one family whose text does not travel alone. Its
leader ends where the text is, so group 14 moves the same step and the
feature point never moves; writing group 11 by itself would leave the
text off the end of its own leader. Its preferred direction is simply
further out, because a leader is made longer to get its text clear and
never shorter back onto the work.

Two families needed a floor putting under them, which the straight
ones never did: an ordinate's text slid back past the point it is
reading turns its leader round the other way, and a radius dimension's
text on the far side of the centre is measuring from nowhere. A
diameter's is welcome either side, which is what its centre being the
MIDDLE of its two points means, and an arc needs no floor at all -- a
text at a fixed radius can never reach the vertex.

One bug found on the way in: a dimension's own ink was tagged to it by
first element, which works for a dimension line and not for an arc --
tagging only the first chord would have had every angular dimension
fleeing the other thirty-one. What a text RIDES is its own list now,
separate from what the dimension merely draws.

`tests/test_cleardim.py` is at 66 and runs at both tiers.

**Dimension text that is hard to read, slid until it is not.**
`CLEARDIM` is new. A dimension's text has one track -- the dimension
line it belongs to -- and moving along it is free: the dimension still
measures what it measured and nothing about the drawing changes.
Moving it OFF the line is not, so `CLEARDIM` never does; the
across-the-track offset a text goes in with is the one it comes out
with. Hard to read is anything under the letters -- another
dimension's text, a wall line, a polyline edge, an arc, a circle, a
`TEXT` or `MTEXT`, and the dimension lines and extension lines of the
other dimensions in the sweep, plus its own extension lines, which
cross its track at right angles. Its own dimension line is the one
thing that is not ink, because AutoCAD breaks that around the text.

The rule that decides who gives way is the one a drafter would use:
**the one that is already good does not move.** Text that cannot move
goes down first and keeps its spot; then text already clear of
everything fixed keeps its spot too; only then is the text that is on
something routed around all of it. Each pass runs in reading order, so
two texts that are each clear of the drawing but not of each other come
out the same way every run -- the first one read keeps its spot, the
second slides -- and nothing moves that did not have to. A text that
must move goes to the nearest clear spot, stepped outward and then
bisected back so the move is the smallest one that works, trying the
way back toward the middle of its own dimension line first. A text with
nowhere clear inside `cd:*reach-f*` is left exactly where it was and
named in the report: a text parked somewhere arbitrary is worse than
one the drafter can still see sitting on a line.

Angular, radius, diameter and ordinate dimensions are counted by kind
and left alone -- their tracks are an arc, a radial line and a leader,
not the straight dimension line this file knows how to walk -- and so
is a dimension on a locked layer or with its text suppressed. All of
them are still ink everything else has to clear. `CLEARDIMSCAN` is the
same analysis with the writing left out, and the whole run is one undo
group.

**A created point says so on the sheet.** `ABPCREATE` plots a point the
survey never placed, and until now the drawing could not tell one from
a point the field sheet put there.  It gets the note a moved point
gets, on the same layer -- `Created Pt.23 - A 16'-8", B 15'-0"` -- and
where the two readings could not cross and one had to be changed to
make them, the note carries that too: `Created Pt.23 - A 25'-0" held,
B from 20'-10" to 27'-10"`, which is the half somebody will want to
check back against the sheet.  Where it goes is not asked: ABMOVE asks
about its own because that one sits at the spot the point came off,
away from the point and beside a ring, and because ABMOVE settles one
point and ends -- a created point's note has one place to be, and
ABPCREATE is a loop.

**The drone's altitude is not sea level.** `DDGPS` refused every
low-lying site with `ALTITUDE DOES NOT MAKE SENSE` and a negative
"photo altitude", and it was right about the number and wrong about
what it meant: a DJI `AbsoluteAltitude` is the WGS84 ellipsoid height
(or a barometric estimate seeded from it), which across the United
States sits 50-115 ft BELOW mean sea level -- so a drone 100 ft over a
Tampa deck records -12 ft, and "altitude minus ground" came out short
by the same 50-115 ft everywhere else, silently. v1.2 trusted the XMP
figure as sea level outright. `DDGPS` v1.3 reads the `RelativeAltitude`
beside it -- barometric, above the take-off point, good to a foot or
two -- asks the take-off-vs-deck offset as `DDALT` does (Enter = it
took off from the deck), and never touches the elevation services for
a file that has it; the ground-elevation route is kept for files with
no `RelativeAltitude`, labelled rough, with the datum named in the
failure. Three more things the audit turned up in the same file: the
last-256-KB scan for PNGs that park their metadata after the image
took `car` of a byte list it had already been handed and died on "bad
argument type" (it had never once worked); an `SRATIONAL`
`GPSAltitude` read as unsigned came out at 4,294,963 m; and the byte
scanner's restart rule missed a pattern whose real start sat inside a
false one. `tests/test_ddgps_runtime.py` drives the command end to end
in the VM over synthetic DJI files -- the first runtime coverage
`DDGPS` has had -- and `DDGPS` leaves `check_registry`'s UNTESTED list.

**A miss too small to print is a crossing.** `ABPCREATE` decides
whether two readings meet by arithmetic, and the arithmetic finds gaps
the drawing cannot print: a pair that missed touching by a
ten-thousandth of an inch was answered `the two arcs fall 0" short of
each other` and a table of readings to replace a pair that does meet.
Worse, `abf:circint` takes a square root that has gone a hair negative
there, so the crossing came back `nil` and the line after it would have
taken `(car nil)`. `abf:*touch*` (1/32", half the 1/16" the readings
print to) is the band, and `abf:closest` solves the touch point on the
line through the stakes for any pair inside it. Three more from the
same audit: a label fan with no room inside its own arc hangs outside
it instead of scattering round the circle; `Pt`, `#` and a line of
spaces no longer offer to create a point with no number to be looked up
by; and `abf:click-side` tests a distance rather than a cross product,
so "on the A-B line" means the same thing at any stake spacing. Where
v1.13 put the AB-line question in front of the first reading, `Back`
there re-asks it rather than saying there is nothing behind it.

**Which way the screen reads.** Every colour a tool draws in is an ACI
number, and a number is only right against one background. ACI `8` was
serving two OPPOSITE intents across thirteen tools: the review tools
(`COVERCHECK`, `DIMCHECK`, `LINFINCHECK`) used it to make everything
not under review recede -- which it does on the stock near-black model
space and the exact opposite of on a white one -- while `POOL`, `SPA`,
`OASIS`, `POOLSIDE`, `LOBF`, `ABFIND` and `CONSTELLATION` used the same
number for guide geometry that has to be READ while it is answered,
which works on white and very nearly disappears on the stock dark
grey. Nothing in the tree had ever asked which background it was
drawing onto: 84 colour knobs, zero reads of `COLORTHEME` or the model
background.

Those knobs say `'auto` now and resolve per role -- `fade`, `guide`,
`dim`, `hi` -- against the measured background (the drawing's, for ink
that lands in it; AutoCAD's interface theme for the chart tiles, which
are drawn beside a dialog's own `-15` and `-16` and were following it
halfway). **A knob left as a number is used exactly as given**, and a
session that cannot measure gets the numbers the tree always used, so
nothing changes for anyone the feature cannot help. `CALSET` writes a
`CalofinTheme` override for a screen the measurement reads wrong, into
the profile for the Lisp side and beside the pins for the VB palette.

Three more surfaces were half-themed and are not: the chart tiles'
dimension arrows and focus box (`-16` adapted, `8` and `5` did not),
the toolbar button's icon (a `.bmp` has no alpha, so the square around
the hexagon is painted -- and it was painted dark-theme grey for
everybody, in every light toolbar, from the day it shipped), and the
palette's entry boxes (`SystemColors` ink over hard-coded white).

**The load says one line.** A Startup Suite entry runs in every
drawing opened, and every tool announcing itself was 83 lines and
6,681 characters of scrollback before the drafter had done anything.
`LAZPASS.lsp` and `CALOFIN-LOADER.lsp` set `*calofin-quiet*` while
they load their members; a file APPLOADed alone still greets you.
`tools/check_lisp.py` requires the guard, so this cannot come back.

**Three commands that answer what the build knows.** `CALVER` reports
every calofin file loaded and its version -- no table, because each
tool sets its own banner global and the session IS the table, which is
why a newer single file loaded over the build shows its own number.
`CALHELP` prints what a command is, searching names AND captions the
way the panel's Find page does; until now the captions were readable
in one place only, the panel, on whichever page the tool was filed on.
`CALSET` shows the settings calofin keeps in the AutoCAD profile --
the one place a setting survives a rebuild, since `releases/` and
`LAZPASS.lsp` are generated.

## v3.14 -- 2026-09-14

A report is written when something breaks. That is one moment, and a
moment does not tell you whether a bug is rare, constant, or only ever
after SPA. **Every run is logged now**, and the log answers what a
report cannot: how often a tool fails against how many clean runs, what
the drafter ran in the ten minutes before, and which prompt they quietly
back out of over and over -- because backing out is not a bug, it is a
question somebody could not answer.

One line per run, into `<profile>\calofin\calofin-YYYY-MM.log`:

    2026-09-14 14:30:02  ok     POOL v2.7  LAZPASS  job1234.dwg
    2026-09-14 14:31:40  quit   SPA v1.4  LAZPASS  job1234.dwg
        step  How should the deep end be treated?
    2026-09-14 14:33:07  FAIL   ABHD 091026 REV18  LAZPASS  job1234.dwg
        step  Maximum curves
        err   bad argument type: numberp: nil
        file  C:\Users\dm\Downloads\ABHD-...-error-....dxf
        ? Maximum curves   -> 6

The record's size follows what anybody will want from it: a clean run is
a count, not a story; a quit is the prompt they stopped at; a FAIL is
the error, the report it wrote and the last prompts, in caps so it greps
out of a month of runs.

**It needed no new wiring.** Every command already calls `lzd:begin` at
the top and `lzd:report` from its handler, so the log rides on those.
The one call added is `lzd:end`, before a command's trailing `(princ)` --
which catches every clean exit, because AutoLISP has no early return:
a command either falls out of the bottom of its defun or raises, and
raising is the handler's business. A command that ends some other way
is closed out by the lazy flush at the next `lzd:begin` instead.

**Every failure report now carries the runs around it.** What the
drafter did before a crash is often the cause and is otherwise gone the
moment AutoCAD closes; it rides in the one file they were already told
to send, so nobody has to ask them for a second one. `LAZLOG` shows the
log and names the file.

Four things the edge tests found, all of them paths a real machine takes:

* a broken log destroyed the REPORT. `lzd:report-lines` asked the log
  for its tail, the tail raised on a read-only folder, and the outer
  catch turned a diagnosable failure into "could not be written". The
  log is a convenience; the report is the thing the drafter was told to
  send, and it does not depend on the log working any more.
* a cancel was logged twice, once as the `quit` it was and once as a
  clean run it was not -- `lzd:end` logs, and the cancel path was
  calling it.
* the one command that never appeared in the log was `LAZDIAG`, whose
  whole job is the log: its self test threw away the context `c:LAZDIAG`
  had just opened.
* a tool with a handler in two places (`c:COVERCHECK` and `cchk:scan`)
  would have logged one run as two.

## v3.13 -- 2026-09-14

An audit of the two passes above, and what it turned up.

**Nothing was broken, and the way it was safe was luck.** The 95
`lzd:watch` calls went in straight after a `(setq ss (ssget ...))`,
which in this tree is very often the last form of a `(progn ...)` that
is the then-branch of an `(if (null ss) ...)`. Thirty of them landed
exactly there. Every one happened to sit where the value is discarded --
LINGUTTER's `lg:highlight` ends with a bare `ss`, POINTRENAMER's and
wcalst's are `cond` clauses with more forms after them -- so nothing
misbehaved. That is not safety, it is the absence of an accident.
`lzd:watch` returns its argument now and the injected form carries an
else branch, `(if lzd:watch (lzd:watch ss) ss)`, so the whole insertion
evaluates to the variable whether LAZDIAG is loaded or not. The same for
`lzd:ask`. `check_lazdiag` grew the audit that found it, so a future
injection cannot land in an `(and ...)`, as an `(if ...)` else branch,
or last in a body without failing `make check`.

**`enclosing_call` answered 0 for two different questions** -- "the
enclosing form starts at byte 0" and "there is no enclosing form" -- and
the new audit read the second meaning, silently skipping any form inside
a defun that opened at the first byte of a file. It returns -1 for "none"
now. The audit missed a planted fault until it did.

Four in the engine, each one a path a real drawing can take:

* an LWPOLYLINE with no vertices became a POLYLINE with no VERTEX
  between it and its SEQEND -- not a degenerate shape, a file AutoCAD
  argues with. Dropped instead.
* two failures inside one second took the same file name, and the second
  report overwrote the first: the drafter would send one file believing
  it was both. `lzd:free` walks to `-2`, `-3` and so on. (The VM's
  `findfile` could not see a file the VM itself had written, so the
  guard could not have been tested either.)
* `lzd:gather` walks the drawing from an ename snapshotted before the
  run, and a tool that erased that entity on its way past left `entnext`
  walking from something gone. Caught per-walk, so a drawing that will
  not walk costs the geometry and not the whole report.
* an MTEXT with no group 1 at all reached `(strlen nil)` and was lost to
  the catch for no reason.

The DXF gained a **STYLE table**. Every TEXT in a report names STANDARD
by leaving group 7 off, and this file exists to be opened on somebody
else's machine by somebody who was told to send it; ten lines so it
cannot argue about a style it never defined. The last resort gained an
**undo group**, so sixty lines of text placed in a drawing come back out
with one U rather than sixty.

**`tests/test_lazdiag_sweep.py` is the verification that matters.**
`check_lazdiag` reads the tree and says the calls are there, which is a
claim about the text. The sweep drives 63 headline commands to their
first prompt, hands each a genuine error instead of an answer, and
checks a DXF came back that parses end to end, carries that error, told
the drafter to send it, and left no undo group, error mode or entity
behind. At both tiers. The roster is computed and the exclusions are
read out of `test_cancel_paths.py`, so a command added later is swept
by construction.

## v3.12 -- 2026-09-11

**A dialog that does not fit does not open.** DCL does not scroll in
either direction: a page wider or taller than the screen is not
clipped and is not scrolled -- AutoCAD refuses it outright, with
`Dialog too large to fit on screen. Requested Size = (436, 1085)
Maximum Size = (1920, 1080)`, and the command dies where it stands.
LAZPANEL's **Rest** page had reached exactly that, so clicking Rest did
nothing but raise the error. Rest is the page that could least afford
it: it is COMPUTED -- every tool not on Pool, Cover or Spa lands there
-- so the page that stopped opening is the page every newly registered
tool joins, and it would have broken again at the next one regardless.

Nothing in the tree could have caught it, because a dialog's size is
written down nowhere: it is the sum of whatever the generator emitted.
So it is computed now. `tools/dclsize.py` reads generated DCL as a tile
tree and measures it; its constants are fitted to the report above and
reproduce both of that report's numbers exactly. `tools/check_dcl.py`
drives every generator to its tallest REACHABLE state -- pins and
recents full, every chart, every step count -- and fails the build on
anything within 60px of the limit. It is in `make check`, and
`tests/test_dcl_size.py` puts the same measurement in `make test`.

Five dialogs were over, only one of which anyone had clicked:

- **Rest** (1085px) and **Layout** (1189px) now wrap into balanced
  columns at `lzp:*colbudget*`, captions and all -- a category page is
  where you go to find out what a tool IS, so losing the captions to
  gain the width would have cost the page its purpose.
- **LAZFORM's Roman and Grecian** charts (1141px each) pack the boxes
  beside the picture into two columns instead of one stack. Four more
  charts were within 20px of the line and came down with them. The
  picture is only ~260px tall, so the room was always there, sideways.
- **LAZASCII** (1557px), whose whole job is to be looked at, lays its
  five sections out in three columns.

And the two strips whose height a DRAFTER sets are capped. The note
beside the pinned row said "pin thirty tools and you get a tall panel,
never a broken one"; that was true at 56 tools in three columns and is
not true at 82 -- thirty pins is 1053px, 27px under the wall, and the
next pin goes through it. Pinned is held to `lzp:*pinrowmax*` rows, at
the tick and again on the way in from the registry, where a list stored
by an older build has never been through the cap. Recent was capped
only as it was WRITTEN, so a stored value that predates the limit came
back whole onto every page at once; it is trimmed on read as well.

The pin editor had the same fault from the other end -- three fixed
columns was 28 rows at 82 tools, the same 1085px, on the one dialog
that grows every time ANY tool is added. It shares the page budget now,
so it cannot drift out of step again.

Worst page a drafter can build, pins and recents full: 941px.

## v3.11 -- 2026-09-11

Three changes to the AB perimeter fitters, all of them about the same
thing: what the drafter should have to decide, and what the drawing
already knows.

**A point numbered with an `m` is not a survey point.** ABFIND writes
`17m` when it copies Pt.17 to a position it worked out from two tape
readings off a pair of good points -- the original was a bad shot, and
the copy is where that point SHOULD be, not where anybody stood. ABHD,
ADAB, CABHD and FITABHD were all fitting it like any other shot, so a
perimeter bent to meet a deduction and the hit report then claimed it
held a point nobody measured. It is dropped as the selection is read
now, before the point list exists, which is what makes it true of
everything downstream at once: not ordered into the loop, not fitted,
not held, not counted against the miss allowance, and never ringed or
listed as one the line missed. The original it came from is still in.
Each command says how many it left out, so a survey that comes up
short is explained rather than mysterious. In CABHD this is NOT the
cutoff and NOT the omit list: both of those keep a point and decide
about it, and a moved point is not in the survey to be decided about.
LHD is deliberately not in this list -- it fits laser scans, where an
`m` in a label is as likely to be metres as a moved point.

**ABHD's recommended answers now describe an AB survey.** The miss
share Enter offers goes from 15% to **20%**: a fifth of the points an
inch off is what a built shell actually measures like, and at 15% the
fitter ran out of allowance early in the loop and paid for the rest of
it in short arcs. The curve cap gains a third state, **`Auto`**, which
is what a fresh session now starts on: one curve per `*PF-ARC-DIV*`
(3) survey points, rounded to the nearest whole curve. A pool edge
reads as long overarching arcs with three or so points under each, not
one curve per shot. `Auto` cannot be a number at the prompt -- the cap
is asked at step 3 and the points are not selected until step 7 -- so
it is a RULE that becomes a number once the survey is in hand, and
every reader of the cap goes through `pf:cap-for` so it becomes one in
exactly one place. `None` still lifts the cap entirely. CABHD carries
both, because it promises the same fit as ABHD, rule for rule; LHD
keeps its own 15% and gains no recommendation, because a laser scan is
a finer instrument than a tape and a rod, and a cap of a third of a
scan's points is not a cap.

**SIMPABHD: the same fit, with nothing to decide first.** ABHD's first
three questions are the ones that stop a run before it starts -- how
far off may the line sit, what share may be off, how many curves --
and none of them can honestly be answered from the command line,
because the answer IS the shape they produce. That is why ABHD draws
three and lets you point at one. SIMPABHD takes it the rest of the
way: it asks NONE of the three and draws FIVE. Two are ABHD's own ends
of the trade (the least error there is, and the fewest curves that
still hold an inch), so whatever a typed answer could have produced
sits between them; the three in the middle are ready-made answers -- a
share, a distance and a curve cap TOGETHER, which is how they actually
behave -- printed beside each outline: 10% off by an inch with a third
as many curves as points, all but the 3 worst points held with half as
many, and 20% off by half an inch with a third as many.

It is not a copy of ABHD. Both commands walk one `pf:fit-session`,
lifted out of `c:ABHD` unchanged, so the same straight walls, sharp
corners and held points are declared, the same selection is read, the
same table is printed, the same pick keeps one, the same points are
ringed and the same pool bottom is offered. SIMPABHD enters that chain
at step 4 and its steps print as 1 to 4; `Back` at the first of them
re-opens it rather than falling out of the run. `pf:compare` grew one
argument and serves both tables. What a second copy would have had to
keep in step is not the fitter but every promise the run makes around
it, and those are the ones that rot quietly.

## v3.10 -- 2026-09-11

v3.9 made a failure write itself out as a DXF. This is the pass that
makes that true of EVERY command rather than of most of them, and makes
it stay true for the tool written next year.

**Three of the largest tools here were reporting nothing.** A handler
comes in two spellings -- the `(defun *error* ...)` of STANDARDS
section 5, and the `(setq *error* (lambda (m) ...))` that saves and
restores the previous one -- and the wiring only ever looked for the
first. So ABHD, ABHDCOVER, ADAB, TUTORIALABHD, CABHD and LHD were
invisible to it: not unwired, *unseen*, which is the failure mode a
check is supposed to make impossible. Both spellings are read now, and
a lambda handler's `lzd:begin` lands outside the `setq` that holds it
rather than becoming another argument to it.

**Seven commands had no handler at all**, so there was nothing to wire.
DDALT, DDCAL, DDSET, DDELEV, DDTEST, STOCKCOVER-CFG and XFTCONV-SETUP
prompt and save a setting; none of them opens an undo group or changes
a sysvar, so each has the minimal handler -- say it, report it, return.
DDINFO, LAZBUTTON and LAZICON followed for the same reason.

`check_lazdiag` now names a command that can reach **no** handler, its
own or one in a helper it calls, and that is the rule that makes this
de facto: a tool written later fails `make check` until it has one.
What counts as needing one is computed from what the body does, never
from the name -- so a `*VER` reporter is exempt and stops being exempt
the day it grows a prompt. It reads the code with strings and comments
masked out, because ABFINDVER prints the line `(commands: ABFIND,
ABMOVE, ABPCREATE)` and `(commands:` matched `(command`. What `--fix`
will not do is write the handler: which sysvars to put back and whether
an undo group is open is the editorial part, and a handler that
restores the wrong thing is a bug the drafter meets in the *next*
command they run.

**A report now carries the geometry a run was HANDED**, not only what
it drew. `lzd:watch` existed and nothing called it, so a tool that fell
over while walking a selection produced a report with the selection
missing -- the one thing the failure was about. 95 selection sites
record themselves now. Whole-database scans (`ssget "_X"`) are skipped
on purpose: a checking tool sweeps thousands of entities, and copying
them would bury the failure in the drawing rather than showing it.
`lzd:gather` caps the whole list, input included, so a big selection
cannot produce a DXF nobody can open.

The rule is written where it will be read: the session-start hook's
"Rules that bite", a stated requirement in STANDARDS section 5 with the
four call sites in a table, CLAUDE.md's new-tool checklist, and
`make check`.

## v3.9 -- 2026-09-11

A failure used to say one line and stop:

    POOL error: bad argument type: numberp: nil

True, and nearly useless. It does not say which of POOL's forty prompts
had been answered, what was typed into them, what was on screen, or
what the drawing looked like when it happened. The drafter shrugs and
tries again; if it fails twice they report that "POOL is broken", and
the diagnosis starts from nothing.

**Every calofin command now writes its failure out as a file you can
send in.** The same crash prints that same line, and then:

    [calofin] POOL v2.7 has FAILED -- this is a bug, not
    [calofin] something you did wrong.  An error report has been
    [calofin] written to
    [calofin]     C:\Users\dm\Downloads\POOL-v2.7-error-2026-09-11-143207.dxf
    [calofin] SEND THAT FILE IN FOR DIAGNOSIS.

and that DXF holds a copy of the geometry the run drew, whatever it had
been handed to work on, every point that was clicked labelled with the
prompt it answered, the transcript prompt by prompt from the start of
the run, the error text, the last step reached, and AutoCAD's own
`ERRNO` / `CMDNAMES` / `LASTPROMPT` and sysvars. It is written by hand
as R12 DXF -- the oldest there is, which every AutoCAD since reads, and
which needs no handles and no bookkeeping to get wrong inside an error
handler, where `(command)` is refused and `DXFOUT` is out of reach.

**Nothing is asked and the open drawing is not touched.** An earlier
shape of this put the report into the current drawing and asked the
user to click somewhere clear of their work. That is worse in every
direction: it asks somebody who has just been told their command
crashed to make a careful decision, it writes into the file they care
about at the moment they trust it least, "somewhere clear" lands on a
viewport as often as not, and what they then have to send is the whole
job drawing. The click-in path survives as a LAST RESORT -- type
`LAZDIAG` after a report that no folder would take -- and nothing
reaches it automatically.

`LAZDIAG` typed by hand writes the last failure's report again, which
is the answer when the folder was read-only the first time. With
nothing to report it writes a **self test** to the folder a real report
would go to instead of saying nothing, so a drafter can find out that
reports will reach them BEFORE the day they need one.

Esc is not a failure and writes nothing: somebody who backs out of POOL
twenty times a day must not find twenty DXFs in Downloads.

The wiring is not remembered, it is checked. `tools/check_lazdiag.py`
owns the two lines each command carries -- `lzd:begin` at the top,
`lzd:report` in the handler, after the sysvar restore and before the
trailing `(princ)` -- and the one line each ask helper carries to
record the prompt it just put up; `--fix` inserts what is missing and
`make check` fails a command that has neither, so the tool added next
year cannot be the one whose failures stay silent. 93 handlers and 74
ask helpers were wired by it. Both guards are `(if lzd:report ...)`
form: an unbound symbol is nil in AutoLISP, so a standalone file
APPLOADed alone runs them as no-ops and behaves exactly as before.

What it does not do, and says so in the report rather than pretending
otherwise: AutoLISP hands an error handler a message and nothing else
-- no stack, no file, no line number. The breadcrumb and the transcript
are what stand in for one, and between them they name the prompt the
run died at, which is the question a line number would have answered.

## v3.8 -- 2026-09-10

`Same` was already the way to repeat a step tread, and `S` already
typed it -- STANDARDS section 2 has said "capitals are the hotkey"
since the beginning. Nobody could tell, because the prompt read
`[Back/Same] <Enter = done>` and stopped there. It reads
`[Back/Same] <Enter = done, Same = 24>` now, in all three step tools:
the letter comes from the bracket, and the number says what pressing it
will do.

**The step WIDTH gained it too**, which is where the gap actually was.
At a tread prompt Enter means *done*; at a width prompt it means *fit
to the walls*. Neither can also mean "the last one", so repeating a
width meant retyping it every step. `Same` (S) does it now, in
CORNERSTP and in HEMISTEP's curve modes, and the prompt names the
number: `[Same] <Enter = fit to walls, Same = 30>`.

Only a width you GAVE is one `Same` repeats -- a step fitted to the
walls has no typed number behind it, so `Same` after one goes back to
the last width you actually entered, and the prompt says which.

**Where Enter already repeats the last value, `Same` is not offered.**
PERPPTS' point lengths, the three side-profile depth ladders and
HEMISTEP's widths in base-line mode all show `<Enter = 24>` already;
adding a second word for one answer is a worse prompt, not a kinder
one. That rule, and the two conditions that have to hold before `Same`
appears at all, are now in STANDARDS' keyword table beside Yes/No and
the rest -- it had been an ad-hoc word in three files until now.

## v3.7 -- 2026-09-10

One pass, one idea: a question you can answer is a question you should
be able to un-answer. `Back` (with `U` for `Undo` beside it) was already
the repo-wide convention and already worked at most measurement
prompts -- but a lot of the questions that decide what a run even IS
were still one-way. Getting the pool shape wrong meant quitting POOL;
mistyping ABHD's miss percentage meant quitting ABHD; picking the wrong
side to bead meant Escape and a re-selection.

**Every question chain that had a predecessor now has a way back to
it.** ABHD, CABHD and LHD walk their settings chains (seven, eight and
six announced steps) in both directions, declaration loops included --
Back there takes back the wall, corner or held point declared last,
dashed marker and all, and off the first item it re-opens the Yes/No
that started the loop. CORNERSTP's six options do the same, and because
two of them are only asked when the corner has a diagonal, the chain
carries a DIRECTION: a question this run never put is stepped over on
the way back rather than stopped on. POOL, SPA and POOLSIDE open with
their shape and their base point as one chain. PERPPTS and CPERPPTS
grew Back at the width amount, the join and the dimension style;
NORMIESTEP at its corner-treatment sizes; the three step tools at their
bead questions; DIMCHECK, COVERCHECK and LINFINCHECK at the Move/Keep/
Pick pick and their reference sheet; AUTOBEAD at its clicked steps;
ABCURCHECK at its declarations; BPCALLOUT at its callout text;
STOCKCOVER at "which one?".

**A first question that opens a sub-block backs out of it.** FITABHD's
pool bottom asks for the deep end and then four measurements; the four
stepped backwards through each other and the pick did not, so a Yes you
did not mean was Escape or nothing. It re-opens the "add the bottom?"
question now, and the first break re-opens the pick. CORNERSTP's
outside-in runs ask a width for the outermost step - a setting, not a
tread - and it moved in front of the undo group to join the option
chain, where Back at it lands on the dimension question (outside in
never asks about a bench, so that step is passed over).

**A question straight after a selection re-opens that selection.**
`WCALST`, `XFTCONV`, `AUTOBEAD` and `AUTODIM` already did this; CABHD's
point cutoff and LHD's output height do it now, which means the two
questions that decide what a fit even IS are reachable again without
quitting. Nothing is drawn at that point and the classifier rebuilds
every list it fills, so the second pass starts clean. HEMISTEP's width
at the wall was in the same position for a different reason -- it was
asked after the undo group opened -- so it moved in front of it and
now re-opens the dimension question.

**Two more pairs closed on the way out.** ABFIND ties two stakes and
asks for them in order; Back at the second re-asks the first, but only
when the first was CLICKED - a drawing that numbers it makes the
re-ask find the same point and walk forward, which is a deadlock rather
than a way back. DIMCHECK's and LINFINCHECK's reference sheet is three
questions and now chains all three.

**What still has no Back has a reason, and the reasons are written
down.** The root `README.md` names four: a selection cannot be typed
at, a question past committed geometry answers to the draw-as-you-go
rule instead (Back at the prompt inside the loop takes the last step
back, drawing and all), a re-ask that is itself the correction of a
failed range check, and a question the run would answer the same way
twice. Of 338 prompt sites in the tree, the 119 that offer no Back all
fall into one of those, plus the pauses, the demos and the first
question of each command.

**`U` works wherever `B` does**, which was already true and is now
proven rather than trusted: `tests/test_back_nav.py` reads every `.lsp`
in the tier for the invariant the prompt text cannot show you -- Undo
beside every Back in every `initget` list, the typed `B`/`BACK`/`U`/
`UNDO` predicate spelled the same way everywhere and matched case-
folded, and no file that accepts the keyword and then only tests for
`"Back"`. The other half of the same test walks each threaded chain
backwards through the interpreter, at both tiers.

## v3.6 -- 2026-09-08

Two passes that landed together, and they are the same idea twice: a
value somebody has to be able to reach has to be somewhere they can find
it. One pass put every tool's settings in a block at the top of its
file; the other gave every converter a way back that survives a save,
which is the same thing said about a conversion.

Every converter gains a reverter. `XFTCONV`, `SOCONV` and `VSCONV` each
read somebody else's export and turn it into a drawing this office can
work on; until now the only way back was `U`, which is good for as long
as the session lasts and no longer. A conversion is found out to be
wrong the week after -- the survey was converted twice, the wrong file
was opened, the sheet has to go back to whoever exported it -- and by
then `U` is gone.

So each converter now **writes down what it did**, in xdata on the
objects it touched, and each has a command that reads that back:
`XFTRECONV`, `SORECONV`, `VSRECONV`. The record is the whole idea: an
undo that works from the drawing alone cannot survive a save, because
what a conversion destroys (an erased marker, an overwritten property,
a stripped override block) is not in the drawing any more to be read.

Alongside that, the three converters were read through together:
every knob a shop might turn is at the top of its file with an
explanation beside it, under the tunables rule (STANDARDS 5) that
landed in this same release, and the contingencies a survey brings
in run in the VM at both tiers.

`CONSTELLATION` gets the same pass, and joins the tunables rule with
`AUTODIM` and the two point plotters: every knob gathered into a block
at the top and explained, the paths a clean run never takes driven under
test, and the four defects that turned up on the way closed.

### Added

- **`SPA` puts the corner letters on a mini-model, and turns a quarter
  turn to get its hinges clear of a spillway** (`SPA.LSP` 090826 REV16,
  `TUTORIALSPA.LSP` 090826 REV11). Two moves `POOL` had already made,
  written for SPA on the one August branch the consolidation had passed
  over (`spa-mini-version-layout`, 26 August): its corner-vocabulary
  half was re-done on the trunk the next day, and its other half never
  arrived. It is ported here by hand, against the tunables block and
  the form store SPA has grown since.

  The corner letters no longer sit on the corners of the full-size
  drawing, where they crowd the dimensions, the corner callouts and the
  hinge labels. They go on a small copy of the outline beside the
  report table, with the treatments in place -- a radius corner is an
  arc on it, a cut is its face -- so the report's rows still read back
  against a picture of the shape. Rectangle, octagon and round all get
  one; a round spa has no corners, so its carries no letters and is
  there to say which way round it lies. `spa:*map-gap*` and
  `spa:*map-size*` place it, and it lives on `SPA-NOTES` with the rest
  of the annotation.

  Hinges run north-south, so a spillway on the top or the bottom wall
  stands in the way of every one of them, while the same spillway on a
  side wall cannot touch any. When the spa laid out the way the
  long-overall rule wants cannot get a hinge clear and the other way
  round can, the spillway wins and the spa is turned -- scored on the
  same three things the hinge layout is scored on (dodging every zone,
  fitting the foam length, an acceptable piece count), so the turn is
  never taken at the price of a hinge that overruns the foam. The
  drawing says which turn it took and why, and the spillway's report
  row is named as it was measured with where it ended up added:
  `SPILLWAY TOP WALL (DRAWN RIGHT)`.

  That is why the hinge questions -- the offer, the spillaways, the
  grade and taper -- are now asked as soon as the spa is measured,
  BEFORE a line is drawn: nothing already on the screen can be turned.
  The hinges themselves are still drawn at the end, on whichever
  outline they belong to. The form keys are unchanged and keyed, so
  `LAZSPA` and the palette need nothing; the scripted tests answer in
  the new order. A `NotGiven` corner's report row now reads N/A in both
  columns, as `POOL`'s does.

- **`XFTRECONV`** (`lisp/xftconv/`, with `XFTCONV` at v1.14) puts a
  converted survey back: the marker and the name text the swap erased,
  the leftover text the purge took, the `ab_pt` block off again, and
  the x12 undone by one `SCALE` of 1/12 about the base point the
  conversion used.

  Each block carries the record of what it replaced -- the erased
  entities group by group, plus the scale and the WCS base point, which
  are the two numbers no object in the drawing carries. Coordinates go
  in through `rtos` at 8 decimals, so a round trip is exact to 1e-8 of
  a drawing unit (a hundredth of a micron on a survey in inches) rather
  than to the last bit of the float; `tests/test_xftconv.py` measures
  that on the site-trace sample, whose coordinates carry more decimals
  than the record writes.

  **A highlight holding two conversions is refused by name.** They were
  scaled about different base points, and one scale back cannot undo
  both -- so it says so rather than half-reverting one of them.

- **`SORECONV`** (`lisp/soconv/`, with `SOCONV` at v1.2) moves an
  import back onto the export's own layers. The record keeps the layer
  each object came off, that layer's own colour, and -- only when
  `*soconv-force-bylayer*` was on, since that is the only time the
  conversion overwrites anything else -- the colour, linetype and
  lineweight the forcing replaced.

  A source layer `PURGE`d on the tool's own advice is re-created with
  the colour the record kept, so taking that advice does not close the
  way back.

- **`VSRECONV`** (`lisp/vsconv/`, with `VSCONV` at v1.2) does the same
  for a VS export, and undoes **both halves of the dimension step**:
  the style name back in group 3, and the `ACAD`/`DSTYLE` override
  block back on the dimension, kept verbatim as the xdata items it
  already was. A revert that restored the style name and left the
  overrides off would leave the dimensions drawing in a style they
  never had, which is the same trap the conversion itself exists to
  avoid from the other side.

  Its scope carries no layer filter where `VSCONV`'s does: a converted
  object sits on `POOL` / `POINTS` / `DIMENSION`, where this office's
  own drawing lives too, so the record is what says which objects came
  from an export.

### Fixed

- **`XFTCONV`** (v1.14) died in a drawing with undo recording switched
  off (`UNDO` `Control` `None`). The `_.UNDO _Begin` was already behind
  a check of `UNDOCTL`, but the `_End` on the success path was not, so
  the run swapped every point and then errored out through its handler
  on the group it never opened. Both ends of the group sit behind the
  one flag now, as the handler's close always did.
- **`VSCONV`** (v1.2) created every destination layer -- `POOL`,
  `POINTS`, `DIMENSION` -- before it had looked at the selection, so an
  export with nothing dimensioned left an empty `DIMENSION` behind and a
  highlight of the anchors alone created `POOL` for nothing. It plans
  the run first now, the way `SOCONV` always did: only the destinations
  the selection reaches are created, and only the source layers it takes
  from are unlocked. The same plan fixed the done line's `now empty`
  list, which walked every VS layer present rather than the ones the run
  took objects off -- so that already-empty `4 Dimensions` was named as
  something to purge by a run that never touched it.

- **A complex top-right placement can nest the corner bulge**, and
  OASIS drew nothing rather than saying so. The file argued the case
  away: the gap between a corner bulge's centre and a side bulge's is
  never *less* than their radii differ by. Never less -- but it can be
  *equal*, and equal is an internal tangency, the one pair no tangent
  radius bridges. It takes a corner bulge at exactly half the Y bound
  and the two centres sharing an X, both of which the placement is free
  to arrange: a 40' x 20' with a 10' corner bulge and a 9' right bulge
  shifted a foot out. Every question answered, and then "those radii do
  not make a closed outline -- nothing drawn", which is the one thing
  the routine's header promises never happens. It is refused at the
  placement question now, against both side bulges, and a tie reaches
  the same check -- at its own floor a tie stands the corner bulge
  straight above the right one, which is exactly the shared X.

- **Esc inside the pool-bottom flow left its tangency marks behind.**
  They are scaffolding, like the preview, but they were a local of
  `oasis:askbottom`, which the command's own error handler cannot see
  -- so cancelling there left every numbered mark, in red, over a pool
  that was otherwise finished and worth keeping. They are
  `oasis:*marks*` now and the handler clears them beside the preview.

- OASIS's header banner still described **four families** and listed
  four, having never heard about the NXT cloud; the prompt offers five
  and `oasis:names` builds seven rings, not six. The file STANDARDS.md
  calls the source of truth was the one place describing the tool as it
  was two shapes ago.

- **BPCALLOUT could not ring two points closer than twice its ring
  radius.** A click was read against the rings already down even when
  it had snapped to a survey point, so with the 5" default and two
  points 8" apart, clicking the second landed inside the first's ring
  and un-ringed it -- the run reported "nothing picked" and drew
  nothing. Only a click with NO survey point under it is read against
  the rings now; a click that snapped is the point it snapped to.

- **`CDCALLOUT` and `CDCREATE` closed an undo group they had never
  opened.** Both guard the `_.UNDO _Begin` behind the `UNDOCTL` check
  -- `_Begin` with undo off errors out of the command -- and then
  closed unconditionally, so in a drawing with undo switched off the
  run ended on a stray `_End`. Both close only a group they opened,
  which is what the flag was already there to say.

- **`WCALST` closed one it had never opened either** -- the third of
  that pair, found the same week and the same way. It drew both of its
  layouts first, so with undo off the run died on its own last command
  with the drawing already full and no `U` to take it back.

- **A closed ring made `WCALST` walk for four minutes.** The
  straightest continuation round a ring is always the next segment, so
  tracing a long side lapped it until the 5,000-segment backstop and
  reported a developed length of 694,662 -- about a thousand laps of a
  band 1,250 long. The walk stops at a node it has already stood on,
  taking the segment that closes the lap, so a ring develops as itself
  in under half a second. The README claimed rings were unsupported;
  they are handled, cut open at the segment you clicked.

- **A line touching a long side was counted as a rung.** A datum line
  or a cut mark crosses the chain as steeply as a rung does, and
  counted as one it moved the median width, the vote for which side
  the far edge is on, and -- through the middle rung, which is where
  the far side is picked up -- which layer the far side was taken to
  be on, redrawing the whole far side as loose reference marks. Only
  segments leaving on the majority side are rungs now.

- **The median rung was not the median.** `vl-sort` drops items that
  compare equal (LISPLAB's lesson 2, met in production), so a band
  flared at one end read its width off the deduped list: five 20s and
  two 30s sort to `(20 30)`, whose median is the flare -- 50% wide, and
  the width scales every cut, every filter and the whole layout.
  `vl-sort-i` keeps them.

- **With a tile height, a shallow band was cut through.** The apex rule
  is tile + clearance below the straightened edge, but a clearance
  clear of the foot; on a band shallower than the clearance itself both
  halves go negative and the dart was drawn with its apex ABOVE the
  straightened edge -- a V cut clean through the strip. It is held at
  `wc:*apex-min-f*` of the local depth instead, which is what the
  README had always claimed happened.

- **`CONSTELLATION` closed an undo group it never opened** -- the same
  defect `XFTCONV` had above, found independently in the same release.
  With UNDO off (`UNDOCTL` bit 1 clear) `cst:undobegin` rightly opens
  nothing, but the success path called `cst:undoend` unconditionally, so
  every run in such a drawing ended in the error handler. Guarded on
  `undo-open`, the way the handler already was. Two files carrying one
  mistake is the argument for the library idiom, not for two fixes.

- **`CONSTELLATION`'s handler closed the group with plain `command`.**
  STANDARDS section 5: AutoCAD 2015+ rejects `(command)` inside `*error*`
  unless the error mode was pushed, so an Esc could leave the group open.
  The handler now closes it through `command-s` under
  `vl-catch-all-apply`, as SMARTFILLET and CUSTBLOCK do. (The VM treats
  the two alike, so the cancel sweep passed either way; the library's
  own `cal:undoend` idiom still carries the plain form.)

- **Back from the arcs into a full chart bounced straight back out.** A
  full chart closes itself so the walk needs no final `D` -- and did so
  on re-entry too, so the one reason to Back into it (a dim to change)
  was unreachable. A chart that is already full on the way in now waits
  for `D`, like a fix pass; one that fills up under the operator still
  closes itself.

- **A local named `fix` shadowed the AutoLISP builtin of that name.**
  `c:CONSTELLATION` held the answer to "What needs changing?" in a local
  called `fix`; AutoLISP locals are dynamically scoped, so for the whole
  of that command -- and everything it calls -- `(fix ...)` found a
  string where the function should be. Harmless while nothing called it,
  and found the moment something did: the clamp added to `cst:askcount`
  above. The local is `tofix` now, with a comment saying why.

- **`TUTORIALABHD`'s demo never created the layer it drew on.** Its
  captions, its three candidate outlines and their labels all go on
  `POOL-FIT`, and `entmake` onto a layer the drawing does not have
  fails -- so on a first-time drawing, which is exactly who runs a
  tutorial, the tour drew nothing at all. It gates the layer now, the
  way `pf:compare` always has.

- **A swept ABHD demo left a line on the `POOL` layer.** The walk that
  re-registers the bottom's output as scaffolding started *after* the
  two break lines, and `pf:bottom-draw` takes those out of the registry
  along with its own output -- so the shallow break line was dropped
  and never picked back up, and "Swept -- the drawing is as it was" was
  not quite true. The walk starts behind them now.

- **The pool bottom's dimensions were the one thing ABHD drew without
  its own stamp**, against the rule in its own header that everything
  it creates carries one and only stamped objects are ever erased.

### Changed

- **OASIS puts every knob at the top** -- all forty of them, in one
  tunables block with a sentence each on what changing it does, and
  joins `tests/test_tunables.py` so it stays that way. Fourteen were
  already there; the other twenty-six were spelled out where they were
  read, among them the dimension stand-off's `12` and `18` (POOL's own
  rule, and now a knob that says it has to move with POOL's), the
  preview's `0.6` joiners and `1.25` clearance, the `1.7` a radius
  label sits out from its arc, the `1e-8` the check drawing dedupes
  ties with, two loop guards and a bare `48.0` in the middle of the
  kidney provisionals. Values are unchanged throughout: this renames,
  it does not retune, and `test_the_tunables_are_live` sets one knob
  out of each group on a loaded file and makes the drawing follow it.

  **`oasis:*hopoff*` was not a knob.** The hopper question wrote it, so
  an accepted offset became the session's default -- which is wanted,
  but it meant a pool quietly edited the configuration it had been
  given, and an office that set `24` in a startup file would find it
  saying something else an hour later. The setting and the memory are
  two names now: `oasis:*hopoff*` says where a fresh session starts and
  is never written, `oasis:*hopoff-last*` holds what this session last
  accepted. What a user sees is unchanged.

- **`POOL` and `SPA` join the tunables rule** (`POOL.LSP` 090826 REV24,
  `SPA.LSP` 090826 REV15), the two biggest files in the tree and the
  last of the drawing tools outside it. 72 knobs in POOL and 82 in SPA
  by `tests/test_tunables.py`'s count, each written once, grouped by
  topic, each saying what changing it does, each a row in its README's
  Tunables table. Both files are in that test's `FILES` now, so neither
  block can quietly grow a number back beside the code that reads it.

  What moved up: the output layers and the colour each is created with
  (POOL had `"POOL"`, `"POOL-NOTES"` and `"DIMENSION"` spelled out 67
  times between them), the linetype patterns, the `doff`/`th` rules
  every flow sizes its furniture with, the corner-mark proportions, the
  report and mini-model layout, the guide colours and nominal rings,
  the fitting engine's sweep counts and scan steps, and the suggestion
  and fallback rules. In SPA that also brought up the two tables the
  whole hinge pass is built on -- `spa:*foamtab*` and `spa:*hardtab*`,
  the shop's own foam-sheet and hardware data, which sat 1,200 lines
  down.

  `spa:*lay-hinge*` names the layer the hinges are drawn on, which was
  the literal `"COVER"` inside the draw loop (default unchanged), and
  `pool:*lts*` is gone -- a global nothing had read since the
  per-entity linetype scale replaced it.

  Registering the two turned up a real bug in the checker itself: in
  `assigned()` a STRING value did not take a slot, so every name/value
  pair AFTER a string in the same `setq` was read one position out.
  `spa:setmode` is one long `setq` with `"WATER'S EDGE"` in the middle
  of it, so the three knobs past that string -- read there, never
  written -- came back as writes and check 3 called three settings
  state. Strings count like any other atom now, which is what the
  function's own docstring already claimed.

- `vsconv:restyle-dim` strips the `ACAD` application's xdata and leaves
  every other application's where it is. In AutoCAD that is what it
  always did (an `entget` with an application list carries only that
  application), so nothing about a conversion changes; it is now true
  of the repo's VM as well, which is what lets a tool keep a record of
  its own on an object whose xdata it is editing.

- `entdel` in `tests/lispvm.py` takes an attributed `INSERT`'s
  `ATTRIB`s and `SEQEND` with it, as AutoCAD does -- attributes are
  owned by the block reference. Erasing a point block used to leave its
  number attribute behind as a live entity for the next sweep to trip
  over.

- **The three callout/create tools put every knob at the top**, in one
  tunables block with a sentence each on what changing it does, and
  join `tests/test_tunables.py` so it stays that way. Each had kept
  some settings in a block and the rest inline. New knobs, all
  defaulting to today's behaviour: `bp:*layer-color*`, `bp:*text-gap*`
  (the callout's default spot, which used to be twice the ring radius,
  so shrinking the ring moved the text too), the callout's own wording
  (`bp:*pt-prefix*`, `bp:*tail-one*`, `bp:*tail-many*`, `bp:*unknown*`
  -- seven string literals over four functions until now),
  `cdo:*layer-color*`, `cdo:*exact-eps*` and `cdc:*layer-color*`.

  Two renames come with it, both under STANDARDS 8.4's "only if the
  file is otherwise being reworked": BPCALLOUT's `*BP-LAYER*` family
  takes the file's `bp:` prefix, and CDCALLOUT's three point-classifier
  globals take `cdo:` -- that file already spelled its other knobs
  `cdo:*style*` and `cdo:*layer*`, so it had two schemes for its own
  settings. Both READMEs name the old spellings for anyone whose
  startup file sets them.

- **`WCALST` puts its 38 numbers at the top** (v1.8), the same rule
  again on the tool that needed it most: the dart cap lived in the
  emitter, the cut stop line in the drawing loop, the layer names at
  the `entmake`, and the 1% target was written out four times over
  1,240 lines. The prompt default and both variant summaries read the
  knobs now, so retuning `wc:*maxfeat*` or `wc:*target*` cannot leave
  the question or the sheet quoting the old figure, and the tool
  README carries every one of them in a table. It joins
  `tests/test_tunables.py`; `tests/test_wcalst.py` keeps the half that
  file cannot see, retuning three knobs and checking what the run drew.

- **Every knob at the top, explained.** `XFTCONV`'s settings block is
  rewritten one setting per form with a paragraph each -- what it is,
  when to change it, what depends on it -- and three values that were
  buried in the code joined it: `*xft-block-layer-color*` (the `6` that
  a missing `POINTS` was created with, in two places), `*xft-strip-prefix*`
  (the Leica flavour's letter strip, hard-wired `T` where the trace
  flavour had a switch) and `*xft-column-tol*` (the half text height
  that decides "same column" in the name matching). `VSCONV` gained
  `*vsconv-force-bylayer*` (default `T`), the switch `SOCONV` already
  had with the opposite default -- each tool's default is what its
  sample export does, and the two files now say so about each other.
  `SOCONV`'s block, already complete, has the same header and its
  default colour explained. The per-tool READMEs' tables follow.
- The three headers say precisely what happens to a locked layer: a
  locked **source** is unlocked for the run and re-locked, on the error
  path too; a destination is an output layer, repaired for good with a
  line saying so (STANDARDS 5). The READMEs and tests had it right; the
  headers claimed re-locking for both.

- **A corner treatment sized at exactly its cap was refused, and the
  maximum the prompt then printed failed the same test** (`POOL.LSP`,
  `SPA.LSP`). A treatment is capped at half the shorter wall it sits
  on, so two of them can never overlap and fold the perimeter -- but
  the cap is compared against a setback the routine WORKS OUT rather
  than the number that was typed. A radius becomes `r / tan(angle/2)`,
  and at a true 90-degree corner `cos(45)/sin(45)` is
  `1.0000000000000002` in floating point, not `1`.

  So a 120" radius on a 240"-wide pool -- the full-round end a crew
  really does draw -- measured `120.00000000000003` against a cap of
  `120`, was rejected as too large, and the prompt answered with
  `max 120.0000`: type that back and it is rejected again. A question
  that cannot be satisfied by the figure it shows you, on an input a
  shop actually enters.

  Both files gained a `*capfuzz*` of a millionth of an inch on that
  comparison -- float noise and nothing else, orders below the 1/16" a
  tape reads, so no real measurement changes hands and a treatment
  still cannot overrun its wall. `test_pool_runtime.py` R36/R36b and
  two new cases in `test_spa_runtime.py` pin both halves: the exact-cap
  size draws its four arcs, and a genuinely oversized one is still
  refused exactly once and then takes the maximum it printed.

- **BPCALLOUT could not ring two points closer than twice its ring
  radius.** A click was read against the rings already down even when
  it had snapped to a survey point, so with the 5" default and two
  points 8" apart, clicking the second landed inside the first's ring
  and un-ringed it -- the run reported "nothing picked" and drew
  nothing. Only a click with NO survey point under it is read against
  the rings now; a click that snapped is the point it snapped to.

- **`CONSTELLATION` v1.4 joins the tunables rule** (STANDARDS.md
  section 5), with 38 knobs in a block at the top and a row apiece in
  its README. Five layer colours came out of `cst:preview` and
  `cst:draw`, where they were literal ACI numbers; the label and marker
  floors out of `cst:texth` and `cst:dotr`; the Levenberg-Marquardt
  damping factors out of `cst:lm`; the outline default out of
  `cst:ask`; the overhang threshold out of the report. `cst:*maxpts*`
  is read off the label string instead of being a second number to keep
  in step with it, and `cst:*defcount*` is clamped into range at the
  ask, since the README invites setting it after loading. The golden
  angle is named once for its two users and carries a `NOT A KNOB:`
  marker, since spreading the scattered start evenly is what it does
  and no other value does it. The block closes with the other numbers
  that look tunable and are not -- where `A` sits, the `ab_pt`
  geometry, the float guards, the library helpers the grouped build
  swaps away. `tests/test_tunables.py` carries the file now, so the
  next knob cannot land underneath the block.

- **ABHD puts every knob at the top too** (`abhd.lsp` at 090826
  REV15), in one tunables block of 53 settings in three groups --
  drawing setup, fitter tuning, guards -- each with a sentence on what
  moving it does. A dozen were bare numbers in the body: the
  on-the-shape share of the tolerance (`*PF-ON-FRAC*`), the curve cap's
  relaxing refits and their bound (`*PF-CAP-RELAX*`, `*PF-CAP-TRIES*`),
  what a floating arc and a written-off point each have to buy
  (`*PF-FLOAT-GAIN*`, `*PF-DROP-GAIN*`), the bulge clamp
  (`*PF-BULGE-CLAMP*`), the layer colours, the marker linetypes
  (`*PF-MARK-LTYPE*`, `*PF-STUB-LTYPE*`), the pick-warning multiple,
  the label height, the slow-survey note, the default fit and the
  radius past which an arc is straight. Every value is unchanged.

  What a run WRITES is state, not a knob, and moved out of the block
  the way OASIS's hopper offset did: `*PF-TOL*`, `*PF-MAX-ARCS*` and
  `*PF-HOP-OFF*` are the answers a session remembers, and they sit in a
  `session memory and run state` section under it. `*PF-DEFAULT-FIT*`
  is corrected to `"2"` if it is set to anything but 1, 2 or 3 --
  otherwise a slip there would leave Enter keeping no fit at all,
  silently.

  The same constants land in `LHD` (v2.0) and `CABHD` (v1.9) at the
  same values: those two carry ABHD's span fitter word for word and
  `tests/test_laser_fit.py` and `tests/test_cabhd.py` compare it code
  for code, so a fitter knob changed in one has to change in all three.
  ABHD is not in `tests/test_tunables.py` yet: its knobs are spelled
  `*PF-NAME*` rather than `pf:*name*`, and that rename is a coordinated
  pass over three tools and four suites (the block says so, at the top,
  where someone looking for the omission will be).

### Checks and tests

- `tests/test_xftconv.py` honours `CALOFIN_LISP_ROOT` -- its docstring
  promised a shared-tier run from the start, but the path was hard-wired
  to `lisp/`, so the grouped twin was only ever load-checked. `make
  parity` now runs the converter at both tiers like its two siblings.
- `tests/test_converter_tunables.py` holds the tunables rule for these
  three the way `tests/test_tunables.py` holds it for the four GUI
  files. It could not simply extend that one: its parser reads a knob
  as one `setq` per line with a scalar after it, and the converters'
  central knobs are multi-line tables (`*soconv-map*` is seven rows)
  whose default cannot be written in a README cell. So the block is
  walked by parens instead, and the README check asks that every knob
  HAS a row rather than comparing the default in it. It was worth
  writing: it caught `XFTCONV` explaining each knob *below* its `setq`
  where every other file in the tree explains it above.
- Contingency sections in all three suites: undo switched off, an
  import already in inches, a plain `POINT` for a marker, MTEXT and
  justified names, each settings switch in its non-default position, a
  frozen and switched-off destination repaired rather than drawn onto
  blind, the attribute style falling back to `TEXTSTYLE`, an error
  mid-run through `XFTCONV`'s handler, both flavours in one highlight,
  `XFTCONV-SETUP`; `VSCONV`'s and `SOCONV`'s retuned tables and default
  colour, `VSCONV`'s `*vsconv-dim-xdata*` `nil`, an export with nothing
  dimensioned, and a `SOCONV` highlight carrying nothing of the
  export's.

- `tests/test_constellation.py` grows fifteen contingency tests -- 73
  assertions on top of the 113 already there, 186 in all: Esc mid-chart
  and at the last question, Back at every question in the chain and back
  into a full chart, the count floor and ceiling and a clamped default,
  zero and negative measurements at every distance prompt, pair and run
  names that are not ones, a pair given twice, the three-point floor,
  the layer colours and an existing layer keeping its own, a frozen and
  switched-off layer restored, the block made once, UNDO off, an arc
  named out of ring order and one with an impossible radius, and each
  knob at the top moved and shown to move what it says. Both tiers.
- `tests/test_tunables.py` takes `CONSTELLATION` into `FILES`, which is
  what holds its block and its README table together from here on.

- `tests/test_abhd_contingencies.py` drives `ABHD`, `ABHDCOVER` and
  `ADAB` through the paths a bad drawing takes -- no points, two
  points, five duplicates, a gap, a `SPLINE`, a tilted UCS, a distance
  past the ceiling, a percentage over 100, a pick nowhere near a survey
  point, a break picked twice on one point, a bottom cancelled halfway,
  a `Redo` that omits a point and puts it back -- and runs
  `TUTORIALABHD`, which nothing had ever executed. 65 checks in 13
  sections, at both tiers, each reading the message the path prints and
  what it left in the drawing. The last section holds the block itself.

- Two gaps in `tests/lispvm.py` the suite could not have been honest
  without. `ssget` ignored the `-4` grouping operators, so ADAB's
  automatic point sweep -- an `<OR` of three `<AND` groups -- matched
  nothing at all; and `distof` read only the leading number, so `3'6`
  came back as **3** in every feet-and-inches answer in the tree,
  `LAZFORM`'s and `LAZSTEP`'s included, which is the whole reason they
  try mode 4 before mode 2.

### Notes

- Each reverter is on the panel under its converter, in the same
  `Converters` column: a `RECONV` is looked for in exactly one
  situation, and the place it is looked for is where the converter was.
- All three records can be switched off (`*xft-record*`,
  `*soconv-record*`, `*vsconv-record*`). With one off its converter
  runs exactly as it did before, says so in its done line rather than
  promising a revert, and its reverter says there is nothing to work
  from.
- **One thing a revert spells out rather than restores**: an object
  that arrived carrying no colour, linetype or lineweight of its own
  comes back carrying the explicit ByLayer (`256`, `"ByLayer"`, `-1`)
  that means the same thing. It draws and plots identically. Nothing
  else about a round trip is approximate.

- `lisp/lazpanel/README.md`'s page tables are rewritten from the
  panel's own tables. Four of them had drifted: the `Cover` page was
  missing `LINGUTTER` and `LINGUTTERSCAN`, `Layout` was missing
  `POOLSIDE`, `LAZSPA` and `LAZSTEP`, `Points` was missing
  `POINTRENAMER`, `CONSTELLATION` and `TYLERDRONESUITE`, and `Checking`
  was missing `ABPCHECK`.

A pass over the ten live checkers, one at a time: every value a drafter
might want to change moved to a `TUNABLES` block at the top of its file,
each with a comment saying what it controls, its units, and what raising
or lowering it does. Three of them were bugs rather than untidiness.

### Changed -- the ten checkers

- **Every checker now opens with one tunables block** -- `CHECK` (v1.7),
  `DIMCHECK` (v1.13), `LINFINCHECK` (v2.9), `COVERCHECK` (v1.12),
  `SPACHECK` (v1.13), `ABPCHECK` (v1.5), `ABCURCHECK` (v1.4),
  `LINCHECK` (v1.4), `LINTXTCHK` (v1.5), `CCPRECHECK` (v1.4) -- and each
  suite asserts three things about it: no knob is set anywhere else in
  the file, none is missing an explanation, and the README's Tunables
  table names them all. Those tables are generated off the block itself,
  headings and prose included, so the two cannot disagree.

  The block also states the contract the files never used to: every knob
  is read when the command RUNS, so a `setq` typed at the command line
  takes effect on the next run. The suites drive that -- a raised
  tolerance forgiving the gap it used to shift, a renamed report layer,
  feet-and-inches distances, a widened planarity gate auditing a tilted
  arc, a direction bucket narrowed under a pair's 0.2 degrees.

- **`DIMCHECK`, `LINFINCHECK` and `COVERCHECK` share one shape.** The
  three are siblings (~40 helper names and 1,200-1,400 identical lines
  pairwise), so the same values were buried in the same helpers: the
  report-sizing cluster, the reading-order row band, the marker size,
  the overlap direction bucket and entity list, the distance format and
  three numerical guards. The sizing constants were typed twice in each
  file -- once in the review command, once in the scan -- so a report
  that came out the wrong size had to be fixed in two places or in
  neither.

- **Colour words follow the colour knobs.** The reports said "recolored
  red" and "(magenta)" whatever the knobs held. `DIMCHECK`'s attention
  pattern matched on the word MAGENTA, which is what forced it; it
  matches on ENDPOINT(S) MOVED now -- what the line means rather than
  what colour it came out -- so every colour word in the review, the
  report and the tutorial is the colour actually used.

- **`SPACHECK`'s grade, taper and short-name vocabularies are tables.**
  Three `cond`s spelling out words that have to agree with the foam and
  hardware tables above them; a shop whose blocks say "Deluxe FRP" adds
  a row instead of editing a cond.

### Fixed -- three of those were bugs, not untidiness

- **`SPACHECK` could pass a sheet with no border.** The title-block
  finding was decided by looking for the word `OK` in its own sentence,
  and the "NO BORDER found on layer 'X'" sentence names the layer -- so
  a border layer called `TB-OK` read as a pass. `spachk:title-verdict`
  returns a flag beside its sentence now and the audit reads the flag.

- **`ABCURCHECK`'s `Remove` ignored `acc:*snap-dist*`.** It dropped the
  declaration nearest the pick however far away that pick landed, so a
  stray click anywhere in the drawing removed one. It honours the snap
  distance, as the declare pick always did. Its index also prints its
  weights' actual sum rather than a typed `/ 100`.

- **`LINTXTCHK`'s layout parameters could not be changed either way.**
  The README said they were "set near the top of `LINTXTCHK.lsp` and are
  easy to tweak"; they were locals of the command, so editing one meant
  a trip inside the defun and a `setq` typed at the command line was
  overwritten the moment the command started. Height, spacing, indent,
  the bullet and the 26-line checklist are globals now, and the done
  message names the height it actually used.

  Six of the ten join `tests/test_tunables.py`, the repo-wide rule the
  same release introduced, so one test now holds them to it: every knob
  inside its block, none stray outside it, none re-assigned, each saying
  what changing it does, and each a row in its README's table carrying
  the default it really has -- 304 knobs over 13 files. The four that
  cannot join yet are the ones still spelling their globals
  `*tool-name*` rather than `tool:*name*`, which that test's namespace
  pattern cannot see; their own suites carry the same assertions.

  Two knobs had to stop being two things at once to get there.
  `abp:*limit*` was a default the command overwrote with whatever you
  last answered, so it read as a setting while being state; the knob is
  the default now and `abp:*asked*` is the answer. `SPACHECK`'s three
  demo/sysvar globals moved out of the block for the same reason.

### Not changed, on purpose

- The questions `LINCHECK` and `CCPRECHECK` ask. For those two the
  wording, the order and which answer opens which follow-up are one
  thing, held in the code; a table of prompts split from the branching
  that reads them would be two places to keep in step instead of one.
  Their blocks carry how each walk TALKS -- the tick, the separators,
  the report's box, the Back synonyms each file had written out twice.
- The deprecated acady matcher (`lisp/standards_checker/`), which
  `STANDARDS.md` keeps as-is.

## v3.5 -- 2026-09-02

`SOCONV`'s sibling, written the same way: from a before/after the shop
supplied rather than from a description. `vsconv.dxf` holds a VS survey
export and a by-hand conversion of it side by side in one drawing,
labelled "before" and "after", and pairing the two halves on geometry is
what the rules below are.

### Added

- **`VSCONV`** (`lisp/vsconv/`, v1.0) converts a VS survey export onto
  the shop's layers: `1 Perimeter`, `2 Coping` and `3 Features` onto
  `POOL`, `3.1 Anchors` onto `POINTS`, `4 Dimensions` onto `DIMENSION`,
  with color, linetype and lineweight forced BYLAYER so the moved
  geometry takes the destination layer's appearance rather than carrying
  the export's over. The map is a table (`*vsconv-map*`), so an export
  that names its layers differently is retuned in one place.

  **The dimensions need more than the layer move, and that is the half
  worth having.** The export writes text height, arrow size and decimal
  places into every dimension as an `ACAD`/`DSTYLE` xdata block, and an
  override outranks the style it sits on -- so a dimension merely
  renamed to `STANDARD` would still draw itself in the export's
  2.5-unit text. The sample's after-half carries no xdata at all, which
  is what says the overrides go with the rename. Replaying the sample's
  55 before-entities through the routine reproduces its after-half
  exactly: layer, dimension style and xdata, entity for entity.

  Scope is the highlight, or Enter for every VS layer in the drawing;
  only the layers in the table are touched, so a sheet already carrying
  converted work cannot be converted twice, and a drawing with none of
  them is told so rather than prompted over. As in `SOCONV`, the
  emptied source layers are named in the done line rather than purged,
  so one `U` backs the whole run out.

  Where `SOCONV` is a layer remap and only a layer remap -- because that
  is all its sample does -- this one restyles as well, because that is
  what ITS sample does. The two exports are different tools' output and
  the two routines say so.

## v3.4 -- 2026-09-02

One command, written from a before/after the shop supplied rather than
from a description: `SOconv.dxf` holds an SO site-survey export and a
by-hand conversion of it side by side in one drawing, and pairing the
two halves on geometry is what the rules below are.

### Added

- **`SOCONV`** (`lisp/soconv/`, v1.0) puts an SO site-survey export onto
  the shop's layers: `Pool Perimeter` and `Obstacles` onto `POOL`, the
  Leica points and `Existing Anchorss` onto `POINTS`, and the export's
  one `Dimensions` layer split in two -- its notes onto `TEXT`, its
  dimensions and anything else left there onto `DIMENSION`. The rules
  are a table read in order, first match winning, so the split is
  ordering rather than special-casing and a shop whose export names
  things differently retunes in one place.

  **It is a layer remap and only a layer remap** -- no restyle, no
  forced BYLAYER, no rotate, nothing erased and nothing drawn. That is
  what the sample does: pairing its two halves matches 316 objects and
  the only DXF group that differs on all of them is group 8. So the 161
  Leica points keep the explicit magenta they arrive with, and the notes
  keep their height, style and text. `*soconv-force-bylayer*` is the one
  line that turns it into the cleanup `DRONE` and `TYDRN` do.

  Two things the sample shows that are deliberately NOT in the tool: its
  after side is one dimension short (the drafter dropped a linear dim
  while making it -- an edit, not a rule), and the export's now-empty
  layers are left in the drawing for `-PURGE` rather than deleted
  behind the drafter's back. The done-line names them.

## v3.3 -- 2026-09-02

Two commands the trunk had never seen, brought over from the one branch
that shares no history with it. The constellation branch was written
against a base this tree diverged from 222 commits ago, so nothing here
was cherry-picked: the files were taken one by one and fitted to the
trunk's tooling, which is what the mirror map, the loader manifest, the
panel roster and the derived counts all had to be told about.

### Added

- **`CONSTELLATION`** (`lisp/constellation/`, v1.3) places labelled
  survey points when the sheet gives only the distances BETWEEN them and
  never says where any of them is -- the one survey shape no other
  importer here can read. Stress-majorization sweeps find the answer and
  damped Gauss-Newton lands on it exactly, so a set of tape readings
  that cannot all be true still gets the layout that misses by least,
  and the report names the single dim worth re-measuring instead of
  starring nine innocent ones. Arcs, a self-crossing warning, and a
  fix-and-redraw loop, because a number typed wrong is invisible on the
  chart and obvious on the drawing.
- **`TYLERDRONESUITE`** (`lisp/tydrn/`, TYDRN v1.5) runs the whole drone
  trace in one: `TYDRN`, then `PADDLE`, then the shop's own `CDIM`, in
  the order the work has to happen in. One highlight is carried through
  every stage and grows by what each stage draws; each stage keeps its
  own undo group, so a stage that went well is not undone to get at one
  that did not; the calofin stages are checked before any of them runs.

### Fixed on the way in

- **`CONSTELLATION`'s own copies of two library helpers were behind the
  library.** `cst:syssave` skipped the whole save when a snapshot was
  already pending -- the defect v3.1 fixed in `cal:syssave` -- and
  `cst:undobegin` opened its group without the `UNDOCTL` guard, so a
  `_Begin` in a drawing with UNDO off would have errored out of the
  command. Both are the library bodies now, which is what lets the
  mirror map swap all 28 helpers away and leave the twin a rename.
- **`TYLERDRONESUITE` installed its handler by swapping the global
  `*error*`** through a pair of globals, and held PICKFIRST in one of
  them -- the class rule 1b and `handler-free-var` were added to reject
  in v3.1 and v3.2. `*error*` and the saved PICKFIRST are locals of the
  command now. Inside a stage the stage's own handler is still the one
  AutoCAD calls, which is why each stage cleans up after itself; the
  README says so where it used to promise more.

### Checks and tests

- `tests/test_constellation.py` (36 assertions) and
  `tests/test_tydrn_suite.py` run at both tiers; `CONSTELLATION` joins
  the cancel sweep by construction, and `TYLERDRONESUITE` is named in
  its `NO_PROMPT` roster with the reason -- its pre-flight check runs
  before its first question.
- The VM seeds `PICKFIRST` at AutoCAD's own default of 1, so a test that
  watches it come back has to turn it off first to prove anything.

## v3.2 -- 2026-09-02

The second stability pass. It reconciled the branches first, then closed
the classes of defect that only show up in the NEXT command a drafter
runs, and left the tree able to prove every one of them stays closed.

### Branches

- Four branches carried work the trunk had never seen -- LAZPANEL's Find
  page, OASIS's top-right bulge bound to the top wall, POOL's rectangle
  corner questions and its grecian taped-face defaults -- and each was
  ported onto the trunk by cherry-pick with its tiers regenerated. The
  POOLDEMO sample sheet was found calling `pool:muttend` with ten
  arguments where the ported commit wanted twelve; only a test noticed.
- `.claude/hooks/session-start.sh` puts a session on the trunk: a clean
  tree elsewhere is switched, a dirty one or a branch carrying unmerged
  commits stops the session with the commands to land them. CLAUDE.md
  carries the real count of historical branches (some sixty) and the
  end-of-session push that keeps the trunk in step.

### Fixed

- **`LAZPANEL v3.4` stopped re-installing itself on every drawing
  open.** With the build in the Startup Suite, every drawing paid two
  icon writes into the first support-path folder and a walk of the CUI.
  The button work is marked done on the blackboard, the one namespace
  every document shares, and icons already on disk are left alone.
- **Five tools left AutoCAD's error mode stacked after every clean
  run** -- `XFTCONV`, `PERPPTS`, `CPERPPTS`, `AUTOBEAD` (and so the
  three step routines that bead) and `OASIS` pushed it for their handler
  and popped it only from the handler. A stacked mode refuses `command-s`
  inside every later handler, so the next tool's Esc left its undo group
  open without a word. Each pops on every exit now, as POOL always did.
- **Four tools kept their undo-group flag in a global** shared with
  their demo and tutorial -- `POOL`, `SPA`, `POOLSIDE`, `SPACHECK` -- so
  a run that died between its last dim and the close had the next
  command's handler close a group it never opened. The flag is a local
  of the command that opened the group, and the grouped build swaps the
  helper pairs for `cal:undobegin` / `cal:undoend`.
- **Handlers that restored less than the run changed.** The step
  routines put CLAYER back (an Esc mid-dimension left the drafter on
  DIMENSION); the check family's entity cleanup goes through the catch so
  a throw can no longer skip the undo close; the three RESCUE commands,
  TUTORIALCOVERCHECKCLEAN and TUTORIALPADDLE gained the handler and the
  one undo group they never had; LAZTXT and LAZPIN unload their dialog
  from a handler and every dialog file deletes its temp `.dcl` when
  `load_dialog` refuses it; TUTORIALCOVERCHECK holds ATTDIA, ATTREQ and
  FILEDIA itself; AUTOBEAD's command gained a cancel-aware handler.
- **The multi-file loader asked its one-time question on every drawing**
  on a machine whose HKCU is read-only: `vl-registry-write` answers a
  denial with nil, not an error. The answer is kept in the profile
  (`setenv`) as well.

### The checks got stricter

- `check_lisp`: a pushed error mode must be popped outside the handler
  (rule 1c); an undo group opened in a defun is closed on its success
  path and from its handler (rule 5).
- `check_scope`: `handler-free-var` names a variable a handler reads
  that is neither its own nor a local of its command.
- `check_registry`: a test census -- every command is invoked by a suite
  or excused in `UNTESTED` with the reason, and an excused command a
  suite catches up with fails the check.
- The bundle verifies every `cal:` helper the tools call against the
  library at build time and again at load, and clears the build flag it
  set so a later solo library load still warns. `tests/test_shared.py`
  pins the loader's order.
- The VM counts undo groups and the error mode, refuses to return from
  a command that left either behind, runs `prompt` output through the
  same log as `princ`, seeds every system variable the tree touches at
  AutoCAD's default and answers an unknown one with nil. New suites:
  `test_autobead.py`, `test_cancel_paths.py` (every headline command
  cancelled at its first prompt), `test_loader.py`.

## v3.1 -- 2026-09-01

A stability pass over the one-file build. Nothing new to type; what was
there fails less, and two of the ways it could have failed the NEXT tool
in the session are closed.

### Fixed

- **`DRONE v1.3` / `TYDRN v1.3` no longer install their error handler by
  swapping the global `*error*`.** Both saved the global, set their own,
  and put it back on each exit -- so one exit missed (a throw inside the
  handler's own `EndUndoMark`, say) left that tool's cleanup live for
  every command run afterwards in the loaded-together build: closing an
  undo mark it never opened, re-locking layers it never touched. The
  handler is local to the command now, as the skeleton in STANDARDS 5
  has always said, sees the run's state through dynamic scope rather
  than through `*drone-doc*` / `*drone-unlocked*` globals, and closes
  only a mark the run actually opened.
- **`PADDLE v1.9`'s handler closed an undo mark it might never have
  opened.** An Esc at the perimeter prompt comes before
  `StartUndoMark`; the handler's unconditional `EndUndoMark` then threw
  from inside `*error*`, where nothing catches it. It tracks the mark now
  and closes it through `vl-catch-all-apply`.
- **`CALOFIN-LIB v1.5`: the shared sysvar snapshot merges instead of
  skipping.** Every tool in the grouped build shares `cal:*sysold*`, and
  the tools list different variables. After a run cut short, the next
  tool's `cal:syssave` used to save NOTHING -- so a variable the dead run
  never listed (`CLAYER`, `CMDECHO`) was changed and never put back. A
  variable already pending keeps its true value exactly as before; one
  the snapshot lacks is added. `tests/test_calofin_lib.py` pins both
  halves.

### The checks got stricter

- `check_lisp` fails a `(defun *error* ...)` or `(setq *error* ...)`
  whose enclosing command does not declare `*error*` local, and a
  handler at top level. Zero findings tree-wide once the two above were
  fixed; the deprecated acady matcher keeps its swap idiom.
- The VM can now run `*error*` (`vm.handle_errors = True`): a failure
  outside `vl-catch-all-apply` reaches the handler the failing code can
  see, with every frame still live, and the command is then aborted the
  way AutoCAD aborts it. It also carries just enough ActiveX -- the
  document, its undo marks, the layer collection with `Lock`, and the
  entity properties the cleanup tools put -- for `DRONE` and `TYDRN` to
  run under test for the first time: `tests/test_drone.py` drives the
  happy path, an error mid-run and an Esc at the prompt, at both tiers.

## v3.0 -- 2026-08-27

The release that made the whole toolset drivable from a filled-in chart,
and made the tree able to prove it is in step with itself.

### Zero-install GUI: fill the chart in, press Insert

- **`LAZSPA`** (new) -- `LAZFORM`'s argument applied to `SPA`: three
  charts (Rectangle, Octagon, Round), the boxes wedged into the
  dimension rows, and the spa drawn from what you typed.
- **`LAZSTEP`** (new) -- say how many steps, and the drawing is built
  for that count: N treads with their widths, N risers and N+1 drops,
  every dimension carrying its letter until you type over it.
- **`LAZFORM v2.5`** -- one authority decides what is greyed, and the
  letters it was missing are there.
- All three are plain DCL the file writes for itself, so there is no
  DLL to `NETLOAD` and no artwork to ship.

### The routines take answers from a form

`POOL`, `SPA` and the three step routines each carry an answer store the
ask helpers read before they prompt, so a filled-in chart drives the run
and a half-filled one shortens it. One contract everywhere: a key that
is absent is asked for as usual, `(key . nil)` answers NA without a
prompt, `(key . 84.0)` answers the measurement -- and **an answer is
removed as it is used**, which is what stops `Back` deadlocking on a
question the form already answered.

- `pool:*form*`, `spa:*form*`, `*cs-form*` / `*hs-form*` / `*ns-form*`,
  each with its own `run-with-answers`, cleared on both exits.
- POOL's gate questions and the step routines' count take form answers
  too -- the count is a question the step tools never had before.
- The VB palette caught up with what `SPA` actually asks, and its
  catalog with the tree.

### FITABHD fits the oasis pools too

- **`FITABHD v2.0`** -- the type list gains `OAsis`, and the survey of a
  continuous-tangent pool is fitted with **`OASIS`'s own ring solver**,
  carried into `FITABHD.lsp` under its own prefix so the two files
  cannot draw different pools from the same numbers.
  `test_oasis_ring_is_oasis_lsp_s_own` runs both through the VM and
  compares them element by element.
- Step 2, which has no corners to ask about on an oasis, asks which of
  OASIS's five families it is instead -- in OASIS's own words
  (`Center/TopRight/CLoud/Kidney/NXTcloud`). Steps 5 and 6 are skipped
  the way they are for a Round pool: neither shape has a wall to swing
  or to bow.
- **Everything else about the shape is measured.** An oasis has no walls
  for the edge vote to find a rotation from, so the frame is swept right
  round the pool and the best few placements fitted properly; the
  envelope then falls out of the bounding box, because every bulge is
  tangent to a bound.
- **A cloud's flat bottom is found, not declared.** Every joiner is
  carried as `U = h / (h + R)` rather than as a radius, so the straight
  run -- the reverse arc with an infinite radius -- is just `U = 0`,
  with no special case at either end. The report names the shape
  `straight-bottom cloud` or `rounded-bottom cloud` from what came out.
  Which way a kidney was given is settled the same way: both
  parameterisations are fitted and the points choose, with the freer one
  held to the both-ends evidence margin.
- The report prints every fitted radius under OASIS's own question
  wording, and all of them snap under the *feature* rule -- a measured
  radius, never a design dimension.
- An oasis wants at least 12 survey points, and its hopper is square to
  the envelope rather than to a wall, so all four bounds are offered as
  ends.

### Fixed

- **Output layers are repaired, not just created.** `POOL`, `SPA` and
  the four check tools drew onto a frozen or switched-off layer and
  reported success while producing nothing visible.
- **`LITELINFINSCAN` silently dropped the steps rule** -- a sheet with an
  obvious staircase reported "no step patterns detected" and lost its
  rise-vs-wall-height comparison. The one a drafter would have been
  burned by.
- **`Back` un-counted a defpoint move it could not undo**, so the report
  claimed "points adjusted: 0" over a drawing whose points had moved.
- **Scan findings never rendered red**, on the report whose whole job is
  to make problems findable.
- One canonical cancel test repo-wide (a `*break,` typo had already been
  copy-pasted into a second file), and every living tool now has an
  `*error*` handler that puts back what it changed -- including
  `AUTOBEAD`, which closed an undo group it might never have opened, and
  `PADDLE`, whose block import could leave `CMDECHO` and `ATTREQ`
  clobbered.
- `SPA` speaks the canonical `Square / Radius / Cut / NotGiven`
  treatment, with the sheet-legend words (`90`, `Diagonal`) still
  accepted and normalised -- so `LAZSPA`'s dropdown keeps the drafter's
  vocabulary while the routine keeps the standard's.
- Brackets a click can actually send, one tutorial selector, one pause
  spelling, `ROUnd` everywhere.

### The tree can now prove it is in step

- `mirror_shared.py`, `release_lisp.py` and `build_shared_bundle.py`
  each grew a `--check` mode, and `check_standards.py` runs all three:
  a hand-edited generated twin, an orphaned release or a stale bundle
  body now fails a check instead of shipping.
- `check_lisp.py` exited 0 on the unbalanced parens it advertised;
  `check_scope.py` had no exit code at all. Both gate now, with their
  false-positive classes fixed and a baseline so new findings surface.
- **47 of the 51 grouped twins are generated** (was 14), which is what
  stops the drift class that put two defects into `LAZPASS.lsp`.
- `tools/run_tests.py` + a `Makefile`: `make check`, `make test`,
  `make parity`. The canonical test list was prose in four documents and
  two files had already fallen out of it; the runner globs the directory.
- End-to-end tests for `DIMCHECK`, `LINFINCHECK` and `COVERCHECK` -- the
  three largest tools that had none -- plus `LAZSPA`, `LAZSTEP` and the
  step form suites.
- Nothing is expected to fail on a clean checkout: `EXPECTED_FAILURES`
  in `tools/run_tests.py` is empty, and a test that starts passing there
  fails the run until its entry goes.

### Deliberately deferred

Recorded in `STANDARDS.md` section 8 with reasons rather than left as
silent gaps: the uppercase `.LSP` filenames, SPA's spillaway corner-pick
keywords, `cal:askkw`'s signature (pinned by every generated twin at
once), the `prefix-` naming styles, and the VB palette's button catalog
(it cannot be compiled or tested here).
