;;; ======================================================================
;;; LAZPANEL.lsp  --  clickable button panel that launches the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZPANEL       open the panel
;;;            LAZBUTTON      put the LazPanel button toolbar on screen
;;;            LAZICON        report where the button picture came from
;;;            LAZPIN         choose the pinned tools
;;;            LAZHIDE        choose which tools stay off the panel
;;;            LAZSET         the settings, as a dialog
;;;            LAZNAME        your own name for a tool, and for its button
;;;            CALHELP        what a command does, at the command line
;;;            CALSET         the settings calofin keeps in the profile
;;;            LAZPANELVER    print the loaded version
;;;
;;; Every headline calofin routine as a button, on tabbed pages of two
;;; kinds -- and a FIND page in front of both, which is the one page
;;; that does not need you to know where a tool was filed: type any part
;;; of a name or of its caption and the list narrows to what matches,
;;; Enter runs the top hit.  It searches the captions as well as the
;;; names, so "survey" finds ABHD, whose name says nothing about
;;; surveys.
;;;
;;; Four JOB pages -- Pool, Cover, Spa, Rest -- hold what you
;;; reach for while doing that job, in columns that follow the work:
;;; lay the shape out, tie the points, build the steps, convert what
;;; somebody sent you, then dimension and check.  A CONVERTERS column
;;; sits SECOND TO LAST on Pool and on Cover: past the drawing work,
;;; in front of the dims-and-check column that ends every job.  XFTCONV,
;;; SOCONV, VSCONV and G2MCONV all answer "here is a drawing somebody
;;; else exported", which is how a job sometimes starts and not how
;;; most of them do, so they no longer hold the left edge in front of
;;; the tools that are reached for every time.  Spa is two columns
;;; wide, where second to last IS the first column, so it keeps the
;;; layout it had.  Cover gains the column: XFTCONV and XFTRECONV were
;;; on that page all along, filed under Shape, which a converter never
;;; was.  Five CATEGORY pages -- Layout, Points, Dimensions,
;;; Converters, Checking, the same five names the VB.NET palette in
;;; ui/calofin_net uses -- hold the whole roster filed by what each
;;; tool IS; Converters is the newest, and holds the eight that used to
;;; sit under Points.  A tool that serves two jobs is on both, so there
;;; are more buttons than commands.
;;; Clicking a button closes the panel and runs the command exactly as
;;; if its name had been typed -- the panel adds nothing in front of a
;;; tool and nothing behind it.  (The Cover page names the cover twins,
;;; POOLCOVER and friends, which is not the panel meddling: they are
;;; commands of their own and do the same thing typed.)
;;;
;;; ZERO INSTALL.  The dialog is plain DCL, and this file writes its own
;;; .dcl into the system temp folder each time the panel opens, so there
;;; is no second file to ship, no support-path entry to add and no DLL
;;; to NETLOAD.  APPLOAD this one file (or LAZPASS.lsp, which carries
;;; it), type LAZPANEL, click.
;;;
;;; THE SCREEN BUTTON.  Loading this file also puts a one-button
;;; toolbar named "LazPanel" on screen, so the panel can live as a
;;; clickable button you drag anywhere or dock, like any toolbar.  It
;;; is created through the ActiveX menu API when no toolbar of that
;;; name exists yet -- no CUI file to install -- and its icon (an
;;; orange hexagon, point to the north) is generated as two .bmp files under
;;; TEMPPREFIX and re-applied on every load, because SetBitmaps stores
;;; the path rather than the picture.  Clicking it runs LAZPANEL.  If
;;; the toolbar gets closed or lost, LAZBUTTON brings it back.  When
;;; any of this is unavailable (no COM, locked CUI, unwritable temp
;;; folder) the button is quietly skipped and the panel is untouched.
;;;
;;; The icon goes out through an ADODB.Stream in binary mode, not
;;; through write-char: AutoLISP writes text-mode files and has no NUL
;;; in its character model at all -- (chr 0) is the empty string --
;;; while a 24-bit BMP header is full of NULs before a single pixel is
;;; reached.  No arrangement of this format could be written with the
;;; language's own file output.  COM is no new dependency here: the
;;; toolbar the icon goes on is made through the same ActiveX API.
;;;
;;; A button whose command is not loaded in this session is greyed out
;;; rather than left to fail -- the same availability probe the VB
;;; palette uses (read the name, evaluate it: an unbound C: symbol is
;;; nil).  The status line across the top says how many tools the
;;; session has.  On the Find page an unloaded tool is LISTED instead,
;;; with "(not loaded)" against it and a refusal from Run: a greyed
;;; button in a grid is a dead spot you can see, but a search that
;;; silently omits what you searched for reads as the tool not
;;; existing.
;;;
;;; DCL dialogs are modal, so the panel cannot stay open while a tool
;;; runs the way a docked palette can -- but it no longer has to be
;;; reopened by hand: click, the panel closes, the tool runs to its own
;;; end, and the panel COMES BACK on the page and at the screen position
;;; it was at.  Close is the way out, and is the default button.  Beside
;;; it, on every page including Find, an OPTIONS button opens LAZSET --
;;; the settings as a DIALOG, with the theme on a dropdown, a box per
;;; item colour, the two folders and a way into the hidden list, all in
;;; front of you at once.  CALSET asks the same questions one prompt at
;;; a time and is still there for a drafter who would rather type.
;;; Neither is a roster launch: settings are not a drafting tool, so
;;; clicking Options never lands in Recent the way a real one would.
;;; Behind Names... there, or LAZNAME typed, a drafter gives a tool the
;;; name THEY type and the words THEY want its button to say; both are
;;; per machine, and neither touches the shipped tables.  A
;;; PINNED row on every page carries the handful of tools you actually
;;; run all day, remembered between sessions; Pin... or LAZPIN edits it.
;;; A RECENT row above it carries the last five you launched, newest
;;; first, kept without being asked -- minus anything already pinned,
;;; since Pinned is by definition the tools you run most and showing
;;; them twice would leave Recent saying nothing new.  It appears only
;;; once there is something in it.
;;;
;;; A tool can also be put OUT of sight altogether.  LAZHIDE (or CALSET,
;;; Hidden) opens the same kind of checklist LAZPIN does -- every tool
;;; as a toggle -- and a ticked one stops appearing anywhere the panel
;;; shows itself: no grid button, no Pinned or Recent chip, no Find hit,
;;; not counted in the status line's total.  It is not deleted or
;;; disabled, only unlisted -- typing its name still runs it, and
;;; LAZHIDE always offers the WHOLE roster, so a hidden tool can always
;;; be found again and un-hidden.
;;;
;;; The *SCAN companions are on the panel;
;;; satellites reachable from their headline tool (TUTORIAL*
;;; walkthroughs, *VER reporters, *RESCUE undo companions, -CFG /
;;; -SETUP partners) stay off on purpose, and so does the DD*
;;; drone-height toolset -- eight specialist photo-EXIF commands that
;;; are not part of the drafting flow the panel serves.
;;; tests/test_lazpanel.py pins the roster to the commands actually
;;; defined under lisp/, so a new tool without a button fails the suite
;;; instead of being quietly missing.
;;; ======================================================================

(vl-load-com)

(setq *lazpanel-version* "v3.34")

;;; -------------------- tunables ----------------------------------------
;;;  Every knob in one place.  Each is a plain literal a person changes
;;;  by hand; the reasoning behind each sits with the code that reads
;;;  it, further down, under the same name.  Nothing below this block
;;;  is meant to be edited to tune the panel.
;;;
;;;  Also editable, but living beside the code that reads them because
;;;  they ARE the panel rather than settings of it:
;;;    lzp:*captions*   one caption per command -- the only place they live
;;;    lzp:*groups*     the pages, as columns of command names -- an
;;;                     entry may be a headed run, ("Revert" "X" ...),
;;;                     which labels part of a column from inside it.
;;;                     A column is all runs or all bare commands, never
;;;                     a mix: the renderer labels the column or its
;;;                     runs, and both would be two frames saying one
;;;                     thing
;;;  tools/check_registry.py --fix maintains both; the VB palette's
;;;  catalog is generated from them (tools/gen_ui_data.py).
;;;    lzp:*blurbs*     one sentence per command, for Find's rows and
;;;                     CALHELP -- copied from ui/calofin_net/blurbs.txt,
;;;                     not written twice; tests/test_lazpanel.py holds
;;;                     the two to each other word for word.
;;;    lzp:*keywords*   search-only synonyms lzp:matches also checks, for
;;;                     a word the name, caption and blurb never use

;; The Find page's tab title.  Find is a page but not a group: it stays
;; out of lzp:*groups* -- what Rest is computed against and what
;; lzp:commands folds -- so renaming it here is safe and adding it to a
;; group is not.
(setq lzp:*findname* "Find")

;; The screen-button toolbar's name, as the CUI lists it.
(setq lzp:*tbname* "LazPanel")

;; Where the panel remembers its position between restarts: a value in
;; the AutoCAD profile (setenv), which is always writable where the
;; registry may not be.
(setq lzp:*poskey* "LazPanel_Pos")

;; Where pins and recents live: one registry key, values "Pins" and
;; "Recent", names joined with ";".  THE VB PALETTE READS THE SAME KEY
;; (ui/calofin_net/PaletteMemory.vb) so a drafter has one set of pins
;; whichever surface they pinned from.  Change it here and there
;; together, or tests/test_palette_shell.py fails.
(setq lzp:*pinkey* "HKEY_CURRENT_USER\\Software\\Calofin\\LazPanel")

;; The two per-user maps LAZNAME writes, on that same key.  Named here
;; rather than spelled at the call sites so the whole set of values this
;; file stores can be read in one place -- tests/test_palette_shell.py
;; holds the panel and the VB palette to the same list, and a value it
;; cannot see is a value that can drift.  These two are LISP-SIDE ONLY:
;; the palette has no reader for either yet.
(setq lzp:*aliasval* "Alias")
(setq lzp:*capval* "Caption")

;; The longest caption LAZNAME will let a drafter set.  A ceiling, not a
;; preference: tools/check_dcl.py measures the SHIPPED tables and can
;; never see an override, so this is the only thing standing between a
;; long rename and a page too wide to open.  40 keeps the widest
;; category page inside the budget.
(setq lzp:*capmax* 40)

;; How wide, in DCL character cells, a row of pinned or recent buttons
;; may be before the next button starts a new row.  DCL does not
;; scroll: a row past the screen's width does not clip the page, it
;; stops the dialog opening at all, so this is a ceiling and not a
;; preference.  84 fits a laptop screen.
(setq lzp:*pinbudget* 84)

;; How many captioned buttons may stack in ONE column before a page is
;; split into more columns.  The width budget above has a twin here for
;; the same reason: DCL does not scroll in EITHER direction, so a page
;; taller than the screen does not clip, it refuses to open --
;;     Dialog too large to fit on screen.
;;     Requested Size = (436, 1085)   Maximum Size = (1920, 1080)
;; which is what "Rest" did the day it reached 28 tools, and "Layout"
;; had quietly passed it at 32.  Rest is COMPUTED -- every tool that is
;; not on Pool, Cover or Spa lands there -- so the page that broke is
;; the page every newly registered tool joins, and it would have broken
;; again at the next one.  16 puts the tallest page near 770px and
;; leaves room for several rows of pins and recents on top.
(setq lzp:*colbudget* 16)

;; How many rows the Pinned strip may occupy.  Pins are the one part of
;; a page whose height the DRAFTER sets, and the note beside lzp:packrow
;; used to say "pin thirty tools and you get a tall panel, never a
;; broken one".  That was true when a page was 56 tools in three
;; columns; it is not true now.  Thirty pins is six rows, which puts the
;; tallest page at 1053px -- 27px under the limit -- and the next pin
;; breaks it.  Three rows keeps the worst page under 950px with the
;; Recent row still to come -- a whole row of slack against the budget
;; in tools/check_dcl.py, where four rows left less than one, and a
;; build sitting one row from failing its own check is a build the next
;; change breaks.  Three rows is around seventeen tools; pins are for
;; the handful run all day, so the cap is well past what they are for.
(setq lzp:*pinrowmax* 3)

;; How many recently launched tools are remembered, newest first.  The
;; palette keeps the same number (PaletteMemory.RecentLimit) and
;; tests/test_palette_shell.py holds the two together.
(setq lzp:*reclimit* 5)

;;; -------------------- the roster --------------------------------------
;;  Two tables: lzp:*captions* names every command once, and
;;  lzp:*groups* lays the pages out in columns of those names.  The
;;  rules for what belongs on the panel at all:
;;    - every headline drafting command under lisp/ gets a button;
;;    - satellites do not: TUTORIAL* walkthroughs, *VER reporters,
;;      *RESCUE undo companions, -CFG / -SETUP partners, DCE (alias of
;;      DIMCONTEND) and STOCKLIST (STOCKCOVER's listing companion);
;;    - the DD* drone-height toolset stays off as a whole: eight
;;      specialist photo-EXIF commands, not part of the drafting flow;
;;    - LISPLAB never appears: it is held back from the shared build as
;;      OMITTED (see cal:*held-back* in CALOFIN-LOADER.lsp);
;;    - the deprecated acady matcher (MATCHSTD, ACADY-*) never appears.
;;  tests/test_lazpanel.py enforces all five rules against the tree.

;;  TWO KINDS OF TAB, and a command may sit on several.
;;
;;  The first four pages are JOBS -- what the drafter is actually doing
;;  this hour: a pool, a cover, a spa, and everything those three do not
;;  reach.  They run in the order the work runs: lay the shape out, tie
;;  the points, build the steps, convert what somebody sent you, then
;;  dimension and check.  A command
;;  that serves two jobs appears on both; AUTODIM and DIMCHECK are on
;;  all three, because every job ends the same way.
;;
;;  THE END OF EVERY JOB IS TWO DIFFERENT THINGS, and the column that
;;  ends each job page says so under two labels.  A CHECK walks you
;;  through the drawing one item at a time and changes it as you
;;  answer; a SCAN reads the same drawing and reports, touching
;;  nothing.  Which one a drafter wants depends on how much time they
;;  have and whether they are ready to commit, and the names alone did
;;  not carry it -- COVERCHECK above COVERSCAN above LITECOVERSCAN in
;;  one undifferentiated run reads as three spellings of one tool.
;;  Same shape as Convert above Revert, and the same reason: the split
;;  is what the command DOES to your drawing, not which tool family it
;;  came from, so LINGUTTERSCAN files under Scan beside COVERSCAN
;;  rather than under Pads beside LINGUTTER.  The last five are
;;  the CATEGORIES -- the whole roster filed by what each tool is
;;  rather than when you reach for it -- so a tool you cannot place in
;;  a job is still one tab away.  Converters is the newest of them and
;;  holds the eight that used to be filed under Points: reading
;;  somebody else's export is not a way of making points, it is its own
;;  kind of work, and the job pages have said so with a column of that
;;  name for a while.
;;
;;  Every command therefore appears at least twice: once on a job page
;;  and once on a category page.  Keys are only required to be unique
;;  within a page, and each page is its own dialog, so this is free --
;;  but lzp:commands has to fold the repeats or the status line would
;;  count the roster twice over.
;;
;;  The job pages are laid out in COLUMNS, which is the other half of
;;  the same idea: a job is not a flat list of two dozen tools, it is
;;  four short lists in the order you reach for them.
;;
;;  "Rest" is not a hand-kept list: it is every command the Pool, Cover
;;  and Spa pages do not name, and the test recomputes that complement
;;  from the tree, so a tool added to the panel lands there by default
;;  instead of falling off the job pages unnoticed.
;;
;;  THE AB CHECKS LIVE IN "Rest" AND NOWHERE ELSE among the jobs.
;;  ABCURCHECK and its scan read the A/B survey ties themselves -- the
;;  tape rather than the pool -- so they are bench work over the
;;  numbers, not a step in laying out a pool, a cover or a spa.  Any
;;  further AB* check joins them on Rest and stays off the other three
;;  job pages; test_lazpanel.py enforces that against the tree, so a
;;  new one dropped onto Pool out of habit fails the suite instead of
;;  quietly widening a job page.  The Checking CATEGORY page still
;;  carries them: that page answers "what is this tool", which is a
;;  different question from "what am I doing this hour".

;;  ONE CAPTION PER COMMAND, here and nowhere else.  A command appears
;;  on several pages, so a caption kept beside each button would be the
;;  same words written two or three times -- and would drift the first
;;  time one copy was edited.  This is the only place they live.
(setq lzp:*captions*
  '(
    ("ABCDEF"           "Rectangle plot")
    ("ABCURCHECK"       "Perimeter continuity")
    ("ABCURCHECKSCAN"   "Perimeter continuity, no marks")
    ("ABLOBF"           "Open best-fit run")
    ("ABPCHECK"         "Survey point offsets")
    ("ABPCREATE"        "Create a missing point")
    ("ABFIND"           "A/B stake ties")
    ("ABHD"             "Survey perimeter + bottom")
    ("ABHDCOVER"        "Survey perimeter, no bottom")
    ("ABMOVE"           "Move mis-taped point")
    ("ADAB"             "Organic shape points")
    ("ALTABCDEF"        "Clockwise rectangle plot")
    ("AUTOBEAD"         "Bead offsets")
    ("AUTODIM"          "Auto dimension")
    ("AUTODIMSIDEPOV"   "Side-view dims")
    ("BPCALLOUT"        "Bad point callout")
    ("CABHD"            "Perimeter-only fit")
    ("CCPRECHECK"       "Tech flow chart")
    ("CDCALLOUT"        "Point-to-point cross dims")
    ("CDCREATE"         "Lines to cross dims")
    ("CHECK"            "Drawing check")
    ("CLEARDIM"         "Clear crowded dim text")
    ("CLEARDIMSCAN"     "Crowded dim text scan")
    ("CONSTELLATION"    "Points from cross dims")
    ("CORNERSTP"        "Corner step")
    ("COVERCHECK"       "Cover review")
    ("COVERSCAN"        "Cover scan")
    ("CPERPPTS"         "Curved perp points")
    ("CUSTBLOCK"        "Block from L/W/H")
    ("DIMARCCHECK"      "Arc endpoint check")
    ("DIMCHECK"         "Dimension review")
    ("DIMCONTEND"       "Continue dim chains")
    ("DIMSCAN"          "Dimension scan")
    ("DIMSTAMP"         "Stamp dimension text")
    ("DRONE"            "Drone cleanup")
    ("FITABHD"          "Typed template fit")
    ("FITABHDCOVER"     "Typed template fit, no bottom")
    ("FLOORDIM"         "Floor dims")
    ("G2MCONV"          "G2M plan onto shop layers")
    ("G2MRECONV"        "G2M conversion, undone")
    ("HEMISTEP"         "Hemi step")
    ("HONEFILLET"       "Corner radius, honed")
    ("LAZDIAG"          "Error report for the last failure")
    ("LAZFORM"          "Pool from a filled-in chart")
    ("LAZLOG"           "What every command has done lately")
    ("LAZSIDE"          "Side view from a filled-in section")
    ("LAZTXT"           "The same form, drawn in tiles")
    ("LAZFORMCOVER"     "Chart to pool, no bottom")
    ("LAZSPA"           "Spa from a filled-in chart")
    ("LAZSTEP"          "Steps from a filled-in drawing")
    ("LHD"              "Laser outline fit")
    ("LINCHECK"         "Line checklist")
    ("LINFINCHECK"      "Liner finish review")
    ("LINFINSCAN"       "Liner finish scan")
    ("LINTXTCHK"        "Liner checklist text")
    ("LITECOVERSCAN"    "Cover scan, no dims")
    ("LITELINFINSCAN"   "Liner scan, no dims")
    ("LITESPACHECKSCAN" "Spa scan, no dims")
    ("LOBF"             "Line of best fit")
    ("MOHAMADDLE"       "Pads, pick a size")
    ("NORMIESTEP"       "Normie step")
    ("OASIS"            "Freeform pool")
    ("LINGUTTER"        "Gut to perimeter, then pads")
    ("LINGUTTERSCAN"    "Gut scan, changes nothing")
    ("OLAUTO"           "Overlay two perimeters")
    ("PADDLE"           "Paddle pads")
    ("PERPMARK"         "Measured wall offsets")
    ("PERPPTS"          "Perpendicular points")
    ("POINTRENAMER"     "Renumber points in order")
    ("POOL"             "Pool layout")
    ("POOLCOVER"        "Pool layout, no bottom")
    ("POOLDEMO"         "Worked pool example")
    ("POOLSIDE"         "Pool side view")
    ("SIMPABHD"         "Survey perimeter, no settings")
    ("SMARTFILLET"      "Corner radius, previewed")
    ("SOCONV"           "SO survey onto our layers")
    ("SORECONV"         "SO conversion, undone")
    ("SPA"              "Spa template")
    ("SPACHECK"         "Spa sheet review")
    ("SPACHECKSCAN"     "Spa sheet scan")
    ("SPACOVCREATE"     "Spa cover from the spa")
    ("STAIRDIM"         "Stair dims")
    ("STOCKCOVER"       "Stock cover placement")
    ("TYDRN"            "Text + point tidy-up")
    ("TYLERDRONESUITE"  "Drone suite: tidy, pad, CDIM")
    ("VSCONV"           "VS export onto shop layers")
    ("VSRECONV"         "VS conversion, undone")
    ("WCALST"           "Unroll curved band")
    ("XFTCONV"          "Survey import cleanup")
    ("XFTRECONV"        "Import cleanup, undone")
    ("XYPLOT"           "X/Y offset plot")
   ))

;; The drafter's own words first, then the table's.  The override is
;; consulted HERE, in the one accessor, rather than at the five places
;; that ask -- the search, the Find row, both grid renderers and
;; CALHELP -- so renaming a button renames it everywhere the panel
;; shows it, and no call site had to change to make that true.
;;
;; lzp:*captions* stays the file's single truth and is what
;; tools/gen_ui_data.py generates the VB palette's catalog from, so a
;; drafter's caption is a LISP-SIDE rename: the palette keeps the
;; shipped words until it learns to read the same key.
(defun lzp:caption (name / p)
  (cond ((setq p (assoc name lzp:*capsof*)) (cdr p))
        ((setq p (assoc name lzp:*captions*)) (cadr p))
        (t "")))

;; What a command IS, in one sentence.  Copied in from the palette's
;; own tooltip file (ui/calofin_net/blurbs.txt) rather than written a
;; second time, so the Find page, CALHELP and the palette all say the
;; same thing about a tool instead of three editors drifting apart.
;; tests/test_lazpanel.py holds this table to that file word for word,
;; so an edited or newly registered tooltip that is not carried over
;; here fails the suite instead of quietly falling out of step.
(setq lzp:*blurbs*
  '(
    ("ABCDEF" "Plot rectangle points")
    ("ABCURCHECK" "Grades how continuous a drawn perimeter is")
    ("ABCURCHECKSCAN" "ABCURCHECK without marking the drawing")
    ("ABLOBF" "Fits an OPEN run of arcs and lines through points, between two ends you pick")
    ("ABPCHECK" "ABHD's measuring half as a checker - how far each point is off the line")
    ("ABPCREATE" "Plots a point that is not there yet from the two readings it was taped at")
    ("ABFIND" "Ties Pt.## back to the A and B survey stakes")
    ("ABHD" "Fits a pool perimeter and bottom through surveyed points")
    ("ABHDCOVER" "ABHD for a cover sheet that stops at the perimeter")
    ("ABMOVE" "Moves a point, offering every mis-read tape it could be")
    ("ADAB" "Freeform perimeter through surveyed points")
    ("ALTABCDEF" "ABCDEF with the clockwise corner order")
    ("AUTOBEAD" "Offsets selected pool lines toward a clicked side")
    ("AUTODIM" "Automatic dimensioning")
    ("AUTODIMSIDEPOV" "Dimensions a side-view flight of steps")
    ("BPCALLOUT" "Rings clicked bad points and writes the callout")
    ("CABHD" "ABHD's perimeter half, for a survey that runs past the pool")
    ("CCPRECHECK" "Walks the Tech Flow Chart decision tree")
    ("CDCALLOUT" "Cross-dimensions from Pt.## to Pt.## by typed number")
    ("CDCREATE" "Turns every highlighted line into a cross dimension")
    ("CHECK" "General drawing check")
    ("CLEARDIM" "Slides dimension text along its own dimension line until it is readable")
    ("CLEARDIMSCAN" "Names the dimension text CLEARDIM would move, and moves nothing")
    ("CONSTELLATION" "Places points from the distances between them, inside a known box")
    ("CORNERSTP" "Corner step layout")
    ("COVERCHECK" "Cover check")
    ("COVERSCAN" "Scan drawing for covers")
    ("CPERPPTS" "PERPPTS for a curved run")
    ("CUSTBLOCK" "Custom block in pictorial view from three typed sizes")
    ("DIMARCCHECK" "Dim arc endpoint check")
    ("DIMCHECK" "Guided, one-at-a-time dimension review")
    ("DIMCONTEND" "Chains a seed dimension out to every feature point")
    ("DIMSCAN" "Scan drawing for dimensions")
    ("DIMSTAMP" "Click a point, type 4'4.5 or 44.5; stamps it canonically, an on-screen ruler picks the next")
    ("DRONE" "Drone cleanup routine")
    ("FITABHD" "Fits a typed pool template through surveyed points")
    ("FITABHDCOVER" "FITABHD for a cover sheet - skips the bottom question")
    ("FLOORDIM" "Floor dimensioning")
    ("G2MCONV" "Puts a G2M architectural pool plan onto the shop's layers and styles")
    ("G2MRECONV" "Undoes a G2MCONV run - layers, appearance, text and dimension styles")
    ("HEMISTEP" "Hemi step layout")
    ("HONEFILLET" "Bracket two of SMARTFILLET's radii and hone between them at half inches")
    ("LAZDIAG" "Write the last failure out as a DXF to send in - and, with nothing to report, prove that path works")
    ("LAZFORM" "Fill the dimension chart in and draw the pool from it")
    ("LAZLOG" "Every calofin command that finished, was backed out of or FAILED - the log a report's history comes from")
    ("LAZSIDE" "Read the section, type the letters beside it, and POOLSIDE draws the side view")
    ("LAZTXT" "LAZFORM's chart built from DCL tiles instead of vectors")
    ("LAZFORMCOVER" "LAZFORM for a cover sheet - the pool-bottom gate closed")
    ("LAZSPA" "LAZFORM's argument applied to SPA - fill the chart in and the spa is drawn")
    ("LAZSTEP" "Type the step count and the drawing follows it - fill it in and the steps are drawn")
    ("LHD" "Laser-point outline fit, open or closed")
    ("LINCHECK" "Line / text check")
    ("LINFINCHECK" "Full liner-finish drawing QA, guided")
    ("LINFINSCAN" "The liner-finish QA as one scan")
    ("LINTXTCHK" "Places the vinyl-liner QA checklist as drawing text")
    ("LITECOVERSCAN" "Cover rules only - skips the dimension audit")
    ("LITELINFINSCAN" "Liner rules only - skips the dimension audit")
    ("LITESPACHECKSCAN" "Spa rules only - skips the dimension audit")
    ("LOBF" "Fits a construction line through points that should be on one line")
    ("MOHAMADDLE" "PADDLE's perimeter pads with a size pick first - 24in or 36in")
    ("NORMIESTEP" "Normie step layout")
    ("OASIS" "Continuous-tangent pool drawn live from envelope and radii")
    ("LINGUTTER" "Guts a highlighted area back to the pool, walking the outer face")
    ("LINGUTTERSCAN" "LINGUTTER's report only - reads the drawing, changes nothing")
    ("OLAUTO" "Best-fit overlay of a new perimeter on the original, worst error dimensioned")
    ("PADDLE" "Paddle perimeter pads")
    ("PERPMARK" "Name a survey point, type what it measured: circle, perpendicular, dimension")
    ("PERPPTS" "Perpendicular offset points along a line or curve")
    ("POINTRENAMER" "Hands the survey point numbers back out in perimeter order")
    ("POOL" "Full pool layout tool")
    ("POOLCOVER" "POOL for a cover sheet - the bottom question pre-answered No")
    ("POOLDEMO" "Draws a worked example pool end to end")
    ("POOLSIDE" "POOL's longitudinal section on its own, from the floor run chain")
    ("SIMPABHD" "ABHD with nothing to decide: five ready-made perimeters, keep one")
    ("SMARTFILLET" "Fillet a corner after previewing every radius that fits")
    ("SOCONV" "Puts an SO site-survey export onto the shop's layers in one pass")
    ("SORECONV" "Undoes a SOCONV run - every object back on the export's own layers")
    ("SPA" "Spa / hot-tub template layout")
    ("SPACHECK" "Audits a spa sheet against what SPA draws")
    ("SPACHECKSCAN" "The spa sheet review as one scan")
    ("SPACOVCREATE" "Offsets a selected spa outline into its cover and hinges it to the taper")
    ("STAIRDIM" "Stair dimensioning")
    ("STOCKCOVER" "Replaces a highlighted perimeter with a stock cover drawing")
    ("TYDRN" "Text, pool-point and anchor cleanup in one pass")
    ("TYLERDRONESUITE" "The whole drone trace in one - TYDRN, then PADDLE, then CDIM")
    ("VSCONV" "Remaps a VS survey export's numbered layers onto the shop's")
    ("VSRECONV" "Undoes a VSCONV run - layers, properties and the dimension overrides")
    ("WCALST" "Unrolls a curved constant-width band flat, with darts")
    ("XFTCONV" "Cleans up a Leica XFT/DXF import or a site trace")
    ("XFTRECONV" "Undoes an XFTCONV run - the markers and text back, and the scale with them")
    ("XYPLOT" "Plot an X/Y sheet, twice: points, and dimensioned")
   ))

;; No per-drafter override the way lzp:caption has one -- LAZNAME lets
;; a drafter rename a button, not rewrite what it does, so a blurb is
;; always the shipped one.  A command that somehow has no row (there is
;; always one; the test above is what keeps that true) falls back to
;; its caption rather than showing blank.
(defun lzp:blurb (name / p)
  (cond ((setq p (assoc name lzp:*blurbs*)) (cadr p))
        (t (lzp:caption name))))

;; Search-only synonyms a one-sentence blurb has no room for: the words
;; a drafter might type who does not know calofin's name or caption for
;; what they want -- LHD's blurb says "laser-scanned" but not
;; "topdown", ABHD's caption never says "tolerance" though its settings
;; are exactly that trade-off.  Never shown on screen anywhere, only
;; matched against in lzp:matches below.
(setq lzp:*keywords*
  '(
    ("ABCDEF" "tape measurement rectangle corners points plot confidence locate excel")
    ("ABCURCHECK" "continuity smooth gaps kinks crossings curvature comb grade")
    ("ABCURCHECKSCAN" "continuity smooth gaps kinks crossings report unmarked grade")
    ("ABLOBF" "polyline curve fit survey points wall coping bench step")
    ("ABPCHECK" "survey points distance offset limit report ring arcs")
    ("ABPCREATE" "point create missing tape reading plot stake survey")
    ("ABFIND" "survey stake tie dimension cross point taped move")
    ("ABHD" "perimeter bottom survey points curve fit deduced tolerance")
    ("ABHDCOVER" "perimeter survey cover sheet skip bottom fit points")
    ("ABMOVE" "taped wrong reading transposed marker note circle sweep")
    ("ADAB" "organic freeform shape survey points perimeter bottom curve")
    ("ALTABCDEF" "rectangle corners clockwise frame diagonal distances crossed plot")
    ("AUTOBEAD" "offset bead lines pool clicked side select")
    ("AUTODIM" "perimeter sides arcs radii stairs floor overall dimensions")
    ("AUTODIMSIDEPOV" "steps stairs depth side view flight dimensions inches")
    ("BPCALLOUT" "bad point circle callout mark step flag list")
    ("CABHD" "perimeter walls corners points cutoff edge last survey")
    ("CCPRECHECK" "flow chart decision tree product type summary check")
    ("CDCALLOUT" "cross dimensions points survey tie pair typed repeat")
    ("CDCREATE" "cross dimension line convert layer erase tie style")
    ("CHECK" "audit dimension point geometry stray fix drawing")
    ("CLEARDIM" "clear overlapping dimension text move readable crowded drawing")
    ("CLEARDIMSCAN" "scan report crowded overlapping dimension text readable analysis")
    ("CONSTELLATION" "distance chart solve coordinates rectangle radius arc dimension points layout")
    ("CORNERSTP" "corner step layout pool geometry select routine read")
    ("COVERCHECK" "cover review rules suggest title date update quality")
    ("COVERSCAN" "cover scan rules suggest title date outdated report")
    ("CPERPPTS" "perpendicular offset points curve segments arc resize boundary limit meet")
    ("CUSTBLOCK" "pictorial block length width height dimension inches faces")
    ("DIMARCCHECK" "audit arc endpoint geometry stray fix dimension")
    ("DIMCHECK" "dimension placement arc attachment overlapping lines review style guided")
    ("DIMCONTEND" "chain continue dimension seed feature points")
    ("DIMSCAN" "dimension placement arc attachment overlapping lines scan style report")
    ("DIMSTAMP" "dimension text stamp label mtext ruler measurement tape")
    ("DRONE" "cleanup text style height points perimeter pool spa")
    ("FITABHD" "pool template shape survey points rectangle oval roman oasis hopper")
    ("FITABHDCOVER" "pool template shape survey points cover sheet rectangle oval oasis")
    ("FLOORDIM" "floor dimensions plan alternative pads standard typical")
    ("G2MCONV" "architect plan layers styles stairs dimensions text overrides remap convert")
    ("G2MRECONV" "undo restore record layers styles dimensions report original session")
    ("HEMISTEP" "wall drop tread flat profile hemi corner step")
    ("HONEFILLET" "corner radius fillet round refine steps dimension precise")
    ("LAZDIAG" "error report failure diagnosis transcript log downloads crash")
    ("LAZFORM" "dimension chart form letters boxes corners draw pool")
    ("LAZLOG" "log monthly command quit fail rate file prompt")
    ("LAZSIDE" "section letters tabs insert base point bottom type depth recall")
    ("LAZTXT" "tiles text chart form boxed cluster hopper rectangle")
    ("LAZFORMCOVER" "cover sheet bottom gate chart form shape closed")
    ("LAZSPA" "chart form octagon round rectangle cover hinge taper")
    ("LAZSTEP" "step count dimensions tread riser beading sheet form")
    ("LHD" "laser points outline fit scan topdown closed open")
    ("LINCHECK" "checklist companion flowchart walker routine paired")
    ("LINFINCHECK" "liner finish dimensions steps wall pattern title block")
    ("LINFINSCAN" "liner finish scan report wiping updating dimension audit")
    ("LINTXTCHK" "vinyl liner checklist quality assurance inspection text")
    ("LITECOVERSCAN" "cover scan rules quality suggest title date report")
    ("LITELINFINSCAN" "liner finish scan report wiping updating skip dims")
    ("LITESPACHECKSCAN" "scan audit report outlines hinges title chart readonly")
    ("LOBF" "points straight line wall anchors stations outlier measure")
    ("MOHAMADDLE" "pads size placement default session scan engine")
    ("NORMIESTEP" "recess outside corner lines select pool sides normie")
    ("OASIS" "freeform continuous tangent cloud kidney bulge radius hopper slope bottom")
    ("LINGUTTER" "guts perimeter highlight erase interior dimensions pad outline")
    ("LINGUTTERSCAN" "perimeter highlight report unchanged question gut keep drop")
    ("OLAUTO" "overlay perimeter alignment fit bead track dimensions rigid")
    ("PADDLE" "concave perimeter features pads blocks insert find")
    ("PERPMARK" "survey points wall offsets bench ledge gutter dimension")
    ("PERPPTS" "perpendicular offset points line segments arc resize boundary limit meet")
    ("POINTRENAMER" "renumber sequence perimeter clockwise order callout survey number")
    ("POOL" "field measurements rectangle oval grecian lazy plan shape")
    ("POOLCOVER" "cover sheet bottom depth hopper corner skip plan")
    ("POOLDEMO" "worked example sample rectangle oval grecian lazy plan shape")
    ("POOLSIDE" "section length depths floor run bottom type base point")
    ("SIMPABHD" "perimeter survey points automatic preset choices error curves")
    ("SMARTFILLET" "fillet radius corner arcs preview dimension typical tangent")
    ("SOCONV" "survey export layers remap points dimensions obstacles perimeter")
    ("SORECONV" "undo layer colour xdata purge recreate record moved")
    ("SPA" "hot tub template rectangle octagon round shape")
    ("SPACHECK" "review audit outlines dimensions hinges taper title date")
    ("SPACHECKSCAN" "scan audit report outlines dimensions hinges title readonly")
    ("SPACOVCREATE" "spa cover lap taper hinge foam sheet offset")
    ("STAIRDIM" "stairs steps dimensions plan flight standard typical")
    ("STOCKCOVER" "stock cover replace perimeter drawing folder align placement")
    ("TYDRN" "drone trace cleanup text points spa layer pool tidy")
    ("TYLERDRONESUITE" "suite chain drone trace tidy pad dimension selection")
    ("VSCONV" "survey export layers perimeter coping anchors dimensions style")
    ("VSRECONV" "undo layer colour linetype lineweight dimension style override")
    ("WCALST" "unroll curved band flat darts inserts width flatten")
    ("XFTCONV" "survey import scale points blocks leica trace markers")
    ("XFTRECONV" "undo revert survey markers text scale xdata blocks")
    ("XYPLOT" "survey offset origin graph dimension chain reduced points")
   ))

;; A command with no row here searches on name, caption and blurb alone
;; -- keywords widen a search, they are not load-bearing for it.
(defun lzp:keywords (name / p)
  (cond ((setq p (assoc name lzp:*keywords*)) (cadr p))
        (t "")))

;;  THE PAGES, AS COLUMNS.  Each page is (title (heading cmd ...) ...) --
;;  one entry per COLUMN, laid out side by side across the page.  The
;;  job pages break their tools into the columns the work falls into:
;;  lay the shape out, tie the points, build the steps, convert what
;;  somebody sent you, dimension and check.  That is the grouping the
;;  drafter already carries; the columns just stop it being a single
;;  list of twenty-four.
;;
;;  A column heading of "" means the page is laid out as one plain list
;;  -- what the five category pages and Rest are.  "One list" is not
;;  "one column": a list too long to stack inside the screen is wrapped
;;  into balanced columns at lzp:*colbudget*, which is why the table
;;  below says nothing about how tall a page may be.  It is a list of
;;  what belongs together, and the fitting is done for it.
;;
;;  WHY A MULTI-COLUMN PAGE SHOWS THE NAME ALONE.  A button reading
;;  "CDCALLOUT  -  Point-to-point cross dims" is about 39 cells wide;
;;  four of those side by side is 147, and DCL will not scroll a dialog
;;  wider than the screen -- the dialog simply fails to open.  So the
;;  columns carry the meaning in their headings and the buttons carry
;;  the command name, which puts the widest page at about 64 cells.
;;  A plain-list page has the room and keeps the caption on the button,
;;  wrapped or not: the category pages stay the place to go to find out
;;  what a tool IS, and the job pages are the place to go when you
;;  know.  Wrapping one costs width rather than meaning -- two captioned
;;  columns is about 98 cells, well inside the same wall that rules four
;;  of them out.
(setq lzp:*groups*
  '(("Pool"
     ("Shape"
      "POOL"
      "POOLSIDE"
      "LAZSIDE"
      "LAZFORM"
      "LAZTXT"
      "OASIS"
      "ABHD"
      "SIMPABHD"
      "ADAB"
      "FITABHD"
      )
     ("Points"
      "ABFIND"
      "ABMOVE"
      "ABPCREATE"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      )
     ("Steps"
      "LAZSTEP"
      "CORNERSTP"
      "HEMISTEP"
      "NORMIESTEP"
      "AUTOBEAD"
      "PERPPTS"
      "CPERPPTS"
      "PERPMARK"
      )
     ("Converters"
      ("Convert"
       "XFTCONV"
       "SOCONV"
       "VSCONV"
       "G2MCONV"
       )
      ("Revert"
       "XFTRECONV"
       "SORECONV"
       "VSRECONV"
       "G2MRECONV"
       )
      )
     ("Dims & check"
      ("Dims"
       "AUTODIM"
       )
      ("Check"
       "LINFINCHECK"
       "DIMCHECK"
       )
      ("Scan"
       "LINFINSCAN"
       "LITELINFINSCAN"
       "DIMSCAN"
       )
      )
    )
     ("Cover"
     ("Shape"
      "POOLCOVER"
      "LAZFORMCOVER"
      "OASIS"
      "ABHDCOVER"
      "FITABHDCOVER"
      "STOCKCOVER"
      "CUSTBLOCK"
      )
     ("Points"
      "ABFIND"
      "ABMOVE"
      "ABPCREATE"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      )
     ("Converters"
      "XFTCONV"
      "XFTRECONV"
      )
     ("Pads, dims & check"
      ("Pads"
       "LINGUTTER"
       "PADDLE"
       )
      ("Dims"
       "AUTODIM"
       )
      ("Check"
       "COVERCHECK"
       "DIMCHECK"
       )
      ("Scan"
       "LINGUTTERSCAN"
       "COVERSCAN"
       "LITECOVERSCAN"
       "DIMSCAN"
       )
      )
    )
     ("Spa"
     ("Converters"
      ("Convert"
       "XFTCONV"
       "SOCONV"
       "VSCONV"
       "G2MCONV"
       )
      ("Revert"
       "XFTRECONV"
       "SORECONV"
       "VSRECONV"
       "G2MRECONV"
       )
      )
     ("Shape, dims & check"
      ("Shape"
       "SPA"
       "LAZSPA"
       "SPACOVCREATE"
       "CUSTBLOCK"
       )
      ("Dims"
       "AUTODIM"
       )
      ("Check"
       "SPACHECK"
       "DIMCHECK"
       )
      ("Scan"
       "SPACHECKSCAN"
       "LITESPACHECKSCAN"
       "DIMSCAN"
       )
      )
    )
     ("Rest"
     (""
      "POOLDEMO"
      "CABHD"
      "LHD"
      "SMARTFILLET"
      "HONEFILLET"
      "WCALST"
      "ABCDEF"
      "ALTABCDEF"
      "XYPLOT"
      "DRONE"
      "TYDRN"
      "AUTODIMSIDEPOV"
      "STAIRDIM"
      "FLOORDIM"
      "DIMCONTEND"
      "CHECK"
      "DIMARCCHECK"
      "ABCURCHECK"
      "ABCURCHECKSCAN"
      "ABPCHECK"
      "LINCHECK"
      "LINTXTCHK"
      "CCPRECHECK"
      "POINTRENAMER"
      "CONSTELLATION"
      "TYLERDRONESUITE"
      "LAZDIAG"
      "LOBF"
      "ABLOBF"
      "DIMSTAMP"
      "LAZLOG"
      "MOHAMADDLE"
      "OLAUTO"
      "CLEARDIM"
      "CLEARDIMSCAN"
      )
    )
     ("Layout"
     (""
      "LAZFORM"
      "LAZTXT"
      "LAZFORMCOVER"
      "LAZSIDE"
      "LAZSPA"
      "SPA"
      "SPACOVCREATE"
      "POOL"
      "POOLCOVER"
      "POOLSIDE"
      "POOLDEMO"
      "OASIS"
      "FITABHD"
      "FITABHDCOVER"
      "ABHD"
      "ABHDCOVER"
      "SIMPABHD"
      "ADAB"
      "CABHD"
      "LHD"
      "ABLOBF"
      "LINGUTTER"
      "LINGUTTERSCAN"
      "PADDLE"
      "MOHAMADDLE"
      "AUTOBEAD"
      "LAZSTEP"
      "CORNERSTP"
      "HEMISTEP"
      "NORMIESTEP"
      "SMARTFILLET"
      "HONEFILLET"
      "STOCKCOVER"
      "WCALST"
      "CUSTBLOCK"
      )
    )
     ("Points"
     (""
      "ABCDEF"
      "ALTABCDEF"
      "XYPLOT"
      "CONSTELLATION"
      "LOBF"
      "ABFIND"
      "ABMOVE"
      "ABPCREATE"
      "POINTRENAMER"
      "PERPPTS"
      "CPERPPTS"
      "PERPMARK"
      "DRONE"
      "TYDRN"
      "TYLERDRONESUITE"
      )
    )
     ("Dimensions"
     (""
      "AUTODIM"
      "AUTODIMSIDEPOV"
      "STAIRDIM"
      "FLOORDIM"
      "DIMCONTEND"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      "DIMSTAMP"
      "CLEARDIM"
      "CLEARDIMSCAN"
      )
    )
     ("Converters"
     (""
      "XFTCONV"
      "SOCONV"
      "VSCONV"
      "G2MCONV"
      "XFTRECONV"
      "SORECONV"
      "VSRECONV"
      "G2MRECONV"
      )
    )
     ("Checking"
     (""
      "CHECK"
      "DIMARCCHECK"
      "DIMCHECK"
      "DIMSCAN"
      "ABCURCHECK"
      "ABCURCHECKSCAN"
      "OLAUTO"
      "ABPCHECK"
      "LINCHECK"
      "LINFINCHECK"
      "LINFINSCAN"
      "LITELINFINSCAN"
      "COVERCHECK"
      "COVERSCAN"
      "LITECOVERSCAN"
      "SPACHECK"
      "SPACHECKSCAN"
      "LITESPACHECKSCAN"
      "LINTXTCHK"
      "CCPRECHECK"
      "LAZDIAG"
      "LAZLOG"
      )
    )))

;; How the tab strip is laid out: one DCL row per entry, in this order.
;; Find and the jobs sit on one line and the categories on the next,
;; which is both what they mean and what keeps the strip narrow -- ten
;; tabs on a single row run about 120 character cells, and DCL will not
;; scroll a dialog that is wider than the screen.  This is presentation
;; only; the pages themselves are still lzp:*groups*, plus the one
;; search page below.  The test asserts the two tables name the same
;; pages, so neither can drift.
(setq lzp:*rows*
  '(("Find, or by job" "Find" "Pool" "Cover" "Spa" "Rest")
    ("Or by category"  "Layout" "Points" "Dimensions" "Converters"
                       "Checking")))

;; The name of the search page.  It is a PAGE but not a GROUP: it has no
;; column layout and no roster of its own, it searches the whole one, so
;; it must stay out of lzp:*groups* -- which is what "Rest" is computed
;; against, what lzp:commands folds, and what lzp:dcl-one lays out.
;;  (lzp:*findname* itself is set in the TUNABLES block at the top of the file.)

(setq lzp:*pick* nil)             ; the button clicked on the last run
(setq lzp:*iconerr* nil)          ; why the last icon write failed
(setq lzp:*pos* nil)              ; where the panel was last standing
(setq lzp:*go* nil)               ; the group a tab click asked for
(setq lzp:*icontype* nil)         ; which byte-array spelling worked
(setq lzp:*iconstep* nil)         ; the COM call the icon write died on
(setq lzp:*msxmlwhy* nil)         ; what each MSXML ProgID said, newest first
(setq lzp:*iconroute* nil)        ; which route actually wrote the file
(setq lzp:*iconwrote* nil)        ; T when the last lzp:write-bmps wrote,
                                  ; nil when both files were already there
(setq lzp:*icondir* nil)          ; the folder the icons landed in
(setq lzp:*iconref* nil)          ; "name" on the support path, else "path"
(setq lzp:*page* nil)             ; the page the panel reopens on
(setq lzp:*pins* nil)             ; the pinned tools, in pin order
(setq lzp:*hidden* nil)           ; the tools put out of sight, no set order
(setq lzp:*aliases* nil)          ; (COMMAND . the name this drafter types)
(setq lzp:*capsof* nil)           ; (COMMAND . the words this drafter's button says)
(setq lzp:*aliasat* nil)          ; lzp:*aliases* as the names editor opened it
(setq lzp:*namesel* nil)          ; the tool the names editor has selected
(setq lzp:*names* nil)            ; the names editor's rows, in list order

;;; -------------------- roster access -----------------------------------

;; One page's commands, flattened out of its columns, in display order:
;; down the first column, then down the second.
;; Filtered by lzp:group-without-hidden before it is flattened, so this
;; is the roster AS SHOWN on the page -- the same list lzp:dcl-one
;; renders buttons for, which is what lets lzp:show wire actions
;; straight off it without ever naming a key the DCL does not have.
(defun lzp:group-commands (name / g col c out)
  (foreach g lzp:*groups*
    (if (= (car g) name)
        (foreach col (cdr (lzp:group-without-hidden g))
          (foreach c (lzp:col-commands col) (setq out (cons c out))))))
  (reverse out))

;; T when every entry in COL is a headed run rather than a bare command
;; -- the Converters column, and nothing else today.  Such a column
;; carries its own labels inside it, so the renderer gives it a plain
;; wrapper instead of a labelled box: "Converters" above "Convert"
;; above "Revert" is three frames saying one thing.
(defun lzp:col-runs-p (col / e out)
  (setq out (and (cdr col) T))
  (foreach e (cdr col)
    (if (not (listp e)) (setq out nil)))
  out)

;; The commands in one column, flat.
;;
;; A column entry is EITHER a command name or a headed run of them --
;; ("Revert" "XFTRECONV" ...) -- which is how the Converters column
;; carries its two halves under their own labels without becoming two
;; columns side by side (there is no width for that; see the panel
;; README).  Everything that walks a column for the commands in it goes
;; through here, so the two shapes are read in one place rather than in
;; every caller.
(defun lzp:col-commands (col / e c out)
  (foreach e (cdr col)
    (if (listp e)
      (foreach c (cdr e) (setq out (cons c out)))    ; a headed run
      (setq out (cons e out))))                      ; a plain command
  (reverse out))

;; A page's columns: (heading cmd ...) each, where a cmd may itself be
;; a headed run -- lzp:col-commands is what flattens one.
(defun lzp:group-columns (name / g out)
  (foreach g lzp:*groups*
    (if (= (car g) name) (setq out (cdr g))))
  out)

;; Folded, because a command that serves two jobs is listed on both
;; pages and the status line counts tools, not buttons.  First
;; appearance wins, so the order still reads as the panel is laid out.
(defun lzp:commands ( / g col c out)
  (foreach g lzp:*groups*
    (foreach col (cdr g)
      (foreach c (lzp:col-commands col)
        (if (not (member c out))
          (setq out (cons c out))))))
  (reverse out))

;; Every page the tab strip links to, in strip order: the eight groups
;; and the Find page.  lzp:*rows* is the authority, so a page added to
;; the strip is reachable and wired without a second list to keep.
(defun lzp:pages ( / out r g)
  (foreach r lzp:*rows*
    (foreach g (cdr r) (setq out (cons g out))))
  (reverse out))

(defun lzp:findpage (g) (= g lzp:*findname*))

;; Is C:<name> defined in this session?  An unbound symbol evaluates to
;; nil in AutoLISP, so reading the name and evaluating it is enough --
;; and it stays correct for commands loaded after this file was.
(defun lzp:has (name)
  (if (eval (read (strcat "C:" name))) t nil))

;; The subset of the roster that is loaded right now.
(defun lzp:loaded ( / n out)
  (foreach n (lzp:commands)
    (if (lzp:has n)
      (setq out (cons n out))))
  (reverse out))

;; Is NAME on the hidden list?  lzp:*hidden* is read at load time
;; (lzp:hidden-read, beside lzp:pins-read) and kept current by
;; lzp:hide-toggle while the LAZHIDE dialog is open.
(defun lzp:hidden-p (name) (if (member name lzp:*hidden*) t nil))

;; The roster minus whatever has been put out of sight -- what the
;; panel actually SHOWS: grid buttons, Find hits, Pinned and Recent
;; chips, the status line's total.  lzp:commands stays the full,
;; structural roster (tests/test_lazpanel.py pins it to the tree, and
;; the LAZHIDE dialog offers every command by name so a hidden one can
;; always be found again).
(defun lzp:visible ( / n out)
  (foreach n (lzp:commands)
    (if (not (lzp:hidden-p n)) (setq out (cons n out))))
  (reverse out))

;;; -------------------- the search --------------------------------------
;;  THE PROBLEM THE FIND PAGE SOLVES.  Sixty-seven commands laid out as
;;  a hundred and forty-eight buttons over eight pages is a lot to scan
;;  when you half-remember a name -- and the job pages carry the command
;;  name alone, so the caption that would tell you what a tool IS is on
;;  a different page from the button you want to press.  Find is the one
;;  page where both are in front of you: type any part of a name or of
;;  its caption, and the list narrows to what matches.
;;
;;  It searches the CAPTIONS as well as the names on purpose.  "cover"
;;  would have worked either way -- all eight of its hits carry the word
;;  in their names.  "survey" is the case that matters: it finds ABHD,
;;  ABHDCOVER and ABPCHECK, and not one of those three says anything
;;  about a survey in its name.  Half of knowing this toolset is knowing
;;  what the names stand for; the search is where you stop needing to.
;;
;;  A tool the session has not loaded is LISTED rather than hidden, with
;;  "(not loaded)" against it, and Run says so instead of launching.
;;  That is the opposite of the greyed button on the other pages and is
;;  the right way round here: a greyed button in a grid is a dead spot,
;;  but a search that silently omits what you searched for reads as the
;;  tool not existing.

(setq lzp:*filter* "")            ; the search text, kept across reopens
(setq lzp:*hits* nil)             ; the commands listed now, in list order
(setq lzp:*sel* nil)              ; the highlighted command

;; Substring search, written out rather than handed to wcmatch: the
;; needle is whatever the user typed, and wcmatch would read *, ?, ~,
;; [, ], @, . and # in it as pattern syntax -- so typing a "*" would
;; match everything and typing a "." would match nothing.
(defun lzp:instr (hay ned / i n m)
  (setq n (strlen hay) m (strlen ned) i 1)
  (cond
    ((= m 0) t)
    ((> m n) nil)
    (t
     (while (and (<= i (1+ (- n m))) (/= (substr hay i m) ned))
       (setq i (1+ i)))
     (<= i (1+ (- n m))))))

;; The roster narrowed to what matches, in roster order.  The typed
;; string is split into words (lzp:split on a space) and EVERY word has
;; to turn up somewhere -- an AND across words, so a two-word search
;; narrows rather than widening.  Where a word may turn up is the OR:
;; the name, the caption, the one-sentence blurb or the keyword list,
;; so "cover no bottom" finds ABHDCOVER without the drafter guessing
;; that its own caption never says "no bottom" in those words -- its
;; blurb does.  An empty search has no word left to fail on, so it
;; still matches everything, same as before.  A hidden tool is not a
;; hit: it is out of sight everywhere the panel shows itself, and Find
;; is one more place that is true.
(defun lzp:matches (s / words n cap kw bl ok w out)
  (setq words (lzp:split (strcase s) " "))
  (foreach n (lzp:visible)
    (setq cap (strcase (lzp:caption n))
          kw  (strcase (lzp:keywords n))
          bl  (strcase (lzp:blurb n))
          ok  t)
    (foreach w words
      (if (not (or (lzp:instr n w) (lzp:instr cap w)
                   (lzp:instr kw w) (lzp:instr bl w)))
        (setq ok nil)))
    (if ok (setq out (cons n out))))
  (reverse out))

;; One row of the list: the name, its caption and its one-sentence
;; blurb, joined the way the category pages join a name and its
;; caption, and NOT padded into columns: whether the dialog font is
;; fixed-pitch is exactly what LAZASCII exists to ask, so nothing here
;; may assume that spaces line up.  The caption stays first and alone
;; reachable through lzp:caption, so a drafter's own LAZNAME rename
;; still lands here exactly as it always has; the blurb is what is new.
(defun lzp:hitline (n have)
  (strcat n "  -  " (lzp:caption n) "  -  " (lzp:blurb n)
          (if (member n have) "" "   (not loaded)")))

;; The message line under the list: how much the search left, or why
;; the last Run did nothing.
(defun lzp:findmsg ( )
  (cond
    ((= lzp:*filter* "")
     (strcat (itoa (length lzp:*hits*))
             " tools - type any part of a name or a caption"))
    ((not lzp:*hits*)
     (strcat "no tool matches \"" lzp:*filter* "\""))
    (t
     (strcat (itoa (length lzp:*hits*)) " of "
             (itoa (length (lzp:visible))) " match \""
             lzp:*filter* "\""))))

;; Re-run the search and repopulate the list.  Called from the edit
;; box's action, so it runs with the dialog up, which is the only time
;; start_list is legal.
(defun lzp:fill (s / have n)
  (setq lzp:*filter* s
        lzp:*hits*   (lzp:matches s)
        have         (lzp:loaded))
  (start_list "hits")
  (foreach n lzp:*hits* (add_list (lzp:hitline n have)))
  (end_list)
  ;; the top hit is selected for you, so a search and Enter runs the
  ;; obvious thing without a click in between
  (setq lzp:*sel* (car lzp:*hits*))
  (if lzp:*hits* (set_tile "hits" "0"))
  (set_tile "msg" (lzp:findmsg))
  lzp:*sel*)

;; A click in the list.  DCL reports WHY a tile fired in $reason, and
;; 4 is the double click a list box gives on its own (1 is the ordinary
;; single-click selection) -- a double click means the same here as
;; picking the row and pressing Run.  Only 4: a single click must never
;; launch anything, since moving down the list with the mouse is how
;; you read it.
(defun lzp:hitpick (v reason)
  (setq lzp:*sel* (nth (atoi v) lzp:*hits*))
  (if (and lzp:*sel* (= reason 4)) (lzp:findrun))
  lzp:*sel*)

;; Run what is highlighted.  Unlike a button on the other pages this can
;; refuse: the list shows tools this session has not loaded, so the
;; check that greys a button happens here instead, and says so on the
;; message line rather than closing the panel.
(defun lzp:findrun ( / )
  (cond
    ((not lzp:*sel*)
     (set_tile "msg" "nothing highlighted to run"))
    ((not (lzp:has lzp:*sel*))
     (set_tile "msg" (strcat lzp:*sel* " is not loaded in this session")))
    (t
     (setq lzp:*pick* lzp:*sel*
           lzp:*pos*  (done_dialog 1)))))

;;; -------------------- the dialog --------------------------------------
;;  The DCL is built here as a list of lines and written to a temp file
;;  when the panel opens, so the whole panel travels inside this one
;;  .lsp.  Keys are the command names themselves; boxed columns carry
;;  the group labels.

(defun lzp:dlgname (group) (strcat "lazpanel_" (strcase group t)))

;; The tab strip: one button per group, laid out in the rows of
;; lzp:*rows* -- jobs on the first line, categories on the second.  DCL
;; has no tab tile, so a tab is a button that closes this page and
;; reopens the next -- and since done_dialog reports where the dialog
;; was standing, it reopens there rather than jumping back to the middle
;; of the screen.
(defun lzp:tabstrip ( / out r g)
  (foreach r lzp:*rows*
    (setq out (cons "  : boxed_row {" out))
    (setq out (cons (strcat "    label = \"" (car r) "\";") out))
    (foreach g (cdr r)
      (setq out (cons (strcat "    : button { key = \"tab_" g
                              "\"; label = \"" g "\"; }")
                      out)))
    (setq out (cons "  }" out)))
  (reverse out))

;;; -------------------- the pinned row ----------------------------------
;;  Pins are the answer to "I run four of these fifty-six all day": the
;;  tools you tick sit on EVERY page, in the order you pinned them, so
;;  the ones you actually use stop being three tabs apart.
;;
;;  A pinned button carries a "pin_" key so it cannot collide with the
;;  same tool's own button further down the page, and it is greyed by
;;  the same availability probe.
;;
;;  WIDTH.  The pinned row is generated DCL like everything else, and a
;;  handful of long names abreast -- LITESPACHECKSCAN is sixteen
;;  characters -- would push the dialog past the width DCL refuses to
;;  scroll, which does not clip the page, it stops it opening at all.
;;  So pins are packed greedily into as many rows as they need, with
;;  the Pin... button packed last like any other item -- up to
;;  lzp:*pinrowmax* rows, after which a further pin is REFUSED rather
;;  than taken: height is the same hard wall width is, and a strip that
;;  grew without limit would walk a page into it.
;;  (lzp:*pinbudget* itself is set in the TUNABLES block at the top of the file.)

(defun lzp:pin-label (n) (strcat "    : button { label = \"" n
                                 "\"; key = \"pin_" n "\"; }"))

;; (name width) for every pinned tool, then the editor button last.
;; Greedy packing into as many rows as the names need.  `extra` is one
;; item appended last whose button reads something other than its key --
;; the pin editor's, which is keyed *edit* and reads "Pin..." -- or nil
;; when there is none.  Both the pinned row and the recent row pack
;; through here, so neither can be the one that forgets the budget.
(defun lzp:packrow (names extra extralabel / out row w n cw items)
  (setq items (if extra (append names (list extra)) names) row nil w 0)
  (foreach n items
    (setq cw (+ (strlen (if (and extra (= n extra)) extralabel n)) 6))
    (if (and row (> (+ w cw) lzp:*pinbudget*))
      (setq out (cons (reverse row) out) row nil w 0))
    (setq row (cons n row) w (+ w cw)))
  (if row (setq out (cons (reverse row) out)))
  (reverse out))

;; The pinned tools that are not also hidden.  A hide wins over a pin:
;; ticking a tool off the panel drops its chip from this row even
;; though it stays pinned in storage, the same "stored but not shown"
;; bargain lzp:recshown already strikes against Pinned itself -- and
;; un-hiding it brings the chip straight back with nothing to re-pin.
(defun lzp:pinshown ( / out n)
  (foreach n lzp:*pins*
    (if (not (lzp:hidden-p n)) (setq out (cons n out))))
  (reverse out))

(defun lzp:pinrows ( ) (lzp:packrow (lzp:pinshown) "*edit*" "Pin..."))

(defun lzp:pinrow ( / out rows r n first)
  (setq rows (lzp:pinrows) first t)
  (foreach r rows
    (setq out (cons "  : boxed_row {" out))
    ;; only the first row is labelled: two boxes both saying "Pinned"
    ;; would read as two different things
    (setq out (cons (strcat "    label = \""
                            (if first "Pinned" "") "\";") out))
    (foreach n r
      (setq out
        (cons (if (= n "*edit*")
                "    : button { label = \"Pin...\"; key = \"pin_edit\"; }"
                (lzp:pin-label n))
              out)))
    (if (and first (not (lzp:pinshown)))
      (setq out (cons "    : text { label = \"nothing pinned yet\"; }" out)))
    (setq out (cons "  }" out))
    (setq first nil))
  (reverse out))

;;; -------------------- the recent row ----------------------------------
;;  Pins are what you decided you use; RECENT is what you actually just
;;  used.  It costs nothing to maintain -- no ticking, no editor -- and
;;  it is the row that answers "what was that one called" after you have
;;  come back from a tool and want it again.
;;
;;  A tool already PINNED is left out of the row.  It is stored either
;;  way, so unpinning brings it back, but showing it twice would fill
;;  Recent with the handful of tools Pinned already carries -- which are
;;  by definition the ones you run most.  So Recent is what you used
;;  that is not already on your row.
;;
;;  Keys are "rec_", which cannot collide with the same tool's "pin_"
;;  button or with its own button further down the page.

;;  (lzp:*reclimit* itself is set in the TUNABLES block at the top of the file.)
(setq lzp:*recent* nil)           ; most recent first

;; Everything remembered, minus what Pinned already shows and minus
;; anything hidden -- a tool out of sight stays out of sight here too.
(defun lzp:recshown ( / out n)
  (foreach n lzp:*recent*
    (if (and (not (member n lzp:*pins*)) (not (lzp:hidden-p n)))
      (setq out (cons n out))))
  (reverse out))

(defun lzp:recrows ( ) (lzp:packrow (lzp:recshown) nil nil))

(defun lzp:recrow ( / out rows r n first)
  (setq rows (lzp:recrows) first t)
  (foreach r rows
    (setq out (cons "  : boxed_row {" out))
    ;; only the first row is labelled, for the same reason the pinned
    ;; row labels only its first: two boxes both saying "Recent" would
    ;; read as two different things
    (setq out (cons (strcat "    label = \""
                            (if first "Recent" "") "\";") out))
    (foreach n r
      (setq out (cons (strcat "    : button { label = \"" n
                              "\"; key = \"rec_" n "\"; }")
                      out)))
    (setq out (cons "  }" out))
    (setq first nil))
  ;; and no row at all when there is nothing to put in it: a panel
  ;; opened for the first time is exactly as tall as it always was, and
  ;; DCL height is the failure mode that stops a dialog opening
  (reverse out))

;; Newest first, once each, capped.  Recorded when the tool is
;; LAUNCHED rather than when it finishes: a tool that errors out was
;; still the one you reached for, and a tool cancelled with Escape even
;; more so -- you will want it again in a moment.
(defun lzp:remember (name)
  (setq lzp:*recent*
        (cons name (vl-remove name lzp:*recent*)))
  (while (> (length lzp:*recent*) lzp:*reclimit*)
    (setq lzp:*recent* (reverse (cdr (reverse lzp:*recent*)))))
  (lzp:recent-write)
  lzp:*recent*)

;; Keep the newest lzp:*reclimit* and drop the rest.  lzp:remember caps
;; what it WRITES, so this looks redundant and is not: a value stored
;; by another build, or edited by hand, has never been through it, and
;; Recent is a row on EVERY page -- an over-long one takes all nine
;; past the screen at once, which is the one failure that cannot be
;; escaped by moving to another tab.
(defun lzp:rectrim ( )
  (while (> (length lzp:*recent*) lzp:*reclimit*)
    (setq lzp:*recent* (reverse (cdr (reverse lzp:*recent*)))))
  lzp:*recent*)

(defun lzp:recent-read ( / s)
  (setq s (vl-catch-all-apply 'vl-registry-read (list lzp:*pinkey* "Recent")))
  (setq lzp:*recent*
    (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR) (/= s ""))
      (vl-remove-if-not '(lambda (n) (member n (lzp:commands)))
                        (lzp:split s ";"))))
  (lzp:rectrim))

(defun lzp:recent-write ( / s n)
  (setq s "")
  (foreach n lzp:*recent*
    (setq s (strcat s (if (= s "") "" ";") n)))
  (vl-catch-all-apply 'vl-registry-write (list lzp:*pinkey* "Recent" s))
  lzp:*recent*)

;;; -------------------- hiding tools from sight ---------------------
;;  Pin says "always show me this"; Hide says the opposite -- ticked in
;;  LAZHIDE (or CALSET, Hidden), a tool stops being rendered anywhere
;;  the panel shows itself.  It is not deleted or disabled: lzp:has and
;;  lzp:launch never consult lzp:*hidden*, so the name still runs typed
;;  and LAZHIDE always offers the WHOLE roster as toggles, the same
;;  escape hatch a stale pin already had, so a hidden tool can always
;;  be found again.  Stored the same way Pins and Recent are -- one
;;  more value, "Hidden", on lzp:*pinkey* -- though nothing on the VB
;;  side reads it yet.

;; A name no longer on the roster is dropped on read, the same rule
;; lzp:pins-read and lzp:recent-read already apply to their own lists.
(defun lzp:hidden-read ( / s)
  (setq s (vl-catch-all-apply 'vl-registry-read (list lzp:*pinkey* "Hidden")))
  (setq lzp:*hidden*
    (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR) (/= s ""))
      (vl-remove-if-not '(lambda (n) (member n (lzp:commands)))
                        (lzp:split s ";"))))
  lzp:*hidden*)

(defun lzp:hidden-write ( / s n)
  (setq s "")
  (foreach n lzp:*hidden*
    (setq s (strcat s (if (= s "") "" ";") n)))
  (vl-catch-all-apply 'vl-registry-write (list lzp:*pinkey* "Hidden" s))
  lzp:*hidden*)

;; A tile in the LAZHIDE dialog firing.  Unlike lzp:pin-toggle there is
;; no row to overflow -- a hidden tool costs no screen space, it simply
;; is not drawn -- so ticking one can never be refused.
(defun lzp:hide-toggle (name val)
  (setq lzp:*hidden*
    (if (= val "1")
      (if (member name lzp:*hidden*) lzp:*hidden* (append lzp:*hidden* (list name)))
      (vl-remove name lzp:*hidden*)))
  (princ))

;; One page per group.  The whole roster is still one list -- the pages
;; are lzp:*groups* itself, so re-ordering or re-grouping the tools is
;; an edit to that table and nothing else.
;; NAMES split into as few BALANCED columns as the budget allows: 28
;; tools at a budget of 16 come out 14 and 14 rather than 16 and 12,
;; because a page with one full column beside a short one reads as two
;; different lists.  A page that already fits comes back as a single
;; column and is emitted exactly as it always was.
(defun lzp:wrap (names / n cols per rem want out row c)
  (setq n (length names))
  (if (<= n lzp:*colbudget*)
    (list names)
    (progn
      ;; the remainder is SHARED OUT, one to a column, rather than left
      ;; to pile up on the last one: 82 over six columns is four of 14
      ;; and two of 13, where rounding every column up the same way
      ;; gives five of 14 and a stub of 12.
      (setq cols (1+ (/ (1- n) lzp:*colbudget*))   ; columns, rounded up
            per  (/ n cols)                        ; the even share
            rem  (- n (* per cols))                ; this many get one more
            out nil row nil
            want (if (> rem 0) (1+ per) per))
      (foreach c names
        (setq row (cons c row))
        (if (= (length row) want)
          (setq out  (cons (reverse row) out)
                row  nil
                rem  (1- rem)
                want (if (> rem 0) (1+ per) per))))
      (if row (setq out (cons (reverse row) out)))
      (reverse out))))

;; LST in runs of N, in order.  lzp:wrap above answers a different
;; question -- the FEWEST balanced columns a page budget allows -- and
;; a box that wants a fixed shape, like the settings dialog's eight
;; colour boxes three to a column, cannot ask it that way.
(defun lzp:chunk (lst n / row out e)
  (foreach e lst
    (setq row (cons e row))
    (if (= (length row) n)
      (setq out (cons (reverse row) out) row nil)))
  (if row (setq out (cons (reverse row) out)))
  (reverse out))

;; A headed run (heading cmd cmd ...) with every hidden command struck
;; out of it, or nil when nothing in it is left to show -- an emptied
;; run is dropped rather than rendered as a labelled box with nothing
;; in it.
(defun lzp:strip-hidden-run (run / kept)
  (setq kept (vl-remove-if 'lzp:hidden-p (cdr run)))
  (if kept (cons (car run) kept)))

;; One column (heading entry ...), entries being bare commands or
;; headed runs, with the hidden ones gone from either shape -- or nil
;; when the whole column emptied out.
(defun lzp:strip-hidden-col (col / body e)
  (foreach e (cdr col)
    (setq body
      (cons (if (listp e) (lzp:strip-hidden-run e)
              (if (lzp:hidden-p e) nil e))
            body)))
  (setq body (vl-remove nil (reverse body)))
  (if body (cons (car col) body)))

;; A copy of one page's group -- (title (heading cmd ...) ...) -- with
;; every hidden command removed: column headings and run headings
;; untouched, but a column or run left with nothing in it is dropped
;; rather than drawn empty.  lzp:dcl-one runs this FIRST, so every
;; layout branch below it (one column, several, headed runs) never has
;; to know hiding exists at all.
(defun lzp:group-without-hidden (g / col out)
  (foreach col (cdr g)
    (if (setq col (lzp:strip-hidden-col col)) (setq out (cons col out))))
  (cons (car g) (reverse out)))

(defun lzp:dcl-one (g / out c n col cols)
  (setq g (lzp:group-without-hidden g))
  ;; consed newest-first and reversed at the end, so this seed list
  ;; reads BACKWARDS: the dialog line last here comes out first
  (setq out (list (strcat "  : text { key = \"status\"; width = 60; "
                          "alignment = centered; }")
                  (strcat "  label = \"LazPanel " *lazpanel-version*
                          "  -  " (car g) "\";")
                  (strcat (lzp:dlgname (car g)) " : dialog {")))
  (setq out (append (reverse (lzp:tabstrip)) out))
  (setq out (append (reverse (lzp:recrow)) out))
  (setq out (append (reverse (lzp:pinrow)) out))
  (cond
    ;; ONE COLUMN: the page has the width to spare, so every button
    ;; carries its caption -- this is what the category pages are for.
    ((= (length (cdr g)) 1)
     (setq cols (lzp:wrap (cdr (car (cdr g)))))
     (if (= (length cols) 1)
       ;; fits: the page it has always been, one boxed column
       (progn
         (setq out (cons "  : boxed_column {" out))
         (setq out (cons (strcat "    label = \"" (car g) "\";") out))
         (foreach c (car cols)
           (setq out (cons (strcat "    : button { label = \"" c "  -  "
                                   (lzp:caption c) "\"; key = \"" c "\"; }")
                           out)))
         (setq out (cons "  }" out)))
       ;; too tall for one column, so side by side -- and the captions
       ;; STAY: a category page is where you go to find out what a tool
       ;; is, which is the whole reason it carries them.  Plain columns
       ;; inside the one box, because a border per column would say the
       ;; halves of one list were separate things.
       (progn
         (setq out (cons "  : boxed_row {" out))
         (setq out (cons (strcat "    label = \"" (car g) "\";") out))
         (foreach col cols
           (setq out (cons "    : column {" out))
           (foreach c col
             (setq out (cons (strcat "      : button { label = \"" c "  -  "
                                     (lzp:caption c) "\"; key = \"" c "\"; }")
                             out)))
           (setq out (cons "    }" out)))
         (setq out (cons "  }" out)))))
    ;; SEVERAL COLUMNS, side by side: the heading says what the column
    ;; is for and the buttons carry the command name alone.  Four
    ;; captioned buttons abreast would be about 147 cells wide and the
    ;; dialog would not open at all.
    (t
     (setq out (cons "  : boxed_row {" out))
     (setq out (cons (strcat "    label = \"" (car g) "\";") out))
     (foreach col (cdr g)
       ;; a column that is nothing but headed runs labels itself from
       ;; the inside, so the outer box carries no name of its own
       (if (lzp:col-runs-p col)
         (setq out (cons "    : column {" out))
         (progn
           (setq out (cons "    : boxed_column {" out))
           (setq out (cons (strcat "      label = \"" (car col) "\";")
                           out))))
       (foreach c (cdr col)
         (if (listp c)
           ;; a HEADED RUN inside the column: its own labelled box, so
           ;; the Converters column can say Convert above one half and
           ;; Revert above the other without being two columns -- there
           ;; is no width on Pool for a sixth column.
           (progn
             (setq out (cons "      : boxed_column {" out))
             (setq out (cons (strcat "        label = \"" (car c) "\";")
                             out))
             (foreach n (cdr c)
               (setq out (cons (strcat "        : button { label = \"" n
                                       "\"; key = \"" n "\"; }")
                               out)))
             (setq out (cons "      }" out)))
           (setq out (cons (strcat "      : button { label = \"" c
                                   "\"; key = \"" c "\"; }")
                           out))))
       (setq out (cons "    }" out)))
     (setq out (cons "  }" out))))
  (setq out (cons "  spacer;" out))
  (setq out (cons "  : row {" out))
  (setq out (cons "    alignment = centered;" out))
  (setq out (cons (strcat "    : button { label = \"Close\"; key = \"cancel\"; "
                          "is_default = true; is_cancel = true; "
                          "fixed_width = true; }")
                  out))
  (setq out (cons (strcat "    : button { label = \"Options...\"; "
                          "key = \"options_btn\"; fixed_width = true; }")
                  out))
  (setq out (cons "  }" out))
  (reverse (cons "}" out)))

;; The pin editor: every tool on the panel as a toggle, in as many
;; columns as lzp:*colbudget* needs.  It was three FIXED columns, which
;; was fine at the fifty-six tools of the day and is not at eighty-two:
;; three columns of twenty-eight is the same 1085px that stopped "Rest"
;; opening, on the one dialog that grows every time ANY tool is added.
;; Sharing the page budget means it cannot drift out of step again.
(defun lzp:dcl-pins ( / out col c)
  (setq out (list "lazpanel_pins : dialog {"
                  "  label = \"LazPanel  -  pinned tools\";"
                  (strcat "  : text { key = \"pinmsg\"; label = \"Ticked "
                          "tools sit in the Pinned row on every page.\"; }")
                  "  : row {"))
  (foreach col (lzp:wrap (lzp:commands))
    (setq out (append out (list "    : column {")))
    (foreach c col
      (setq out (append out
        (list (strcat "      : toggle { label = \"" c
                      "\"; key = \"tg_" c "\"; }")))))
    (setq out (append out (list "    }"))))
  (append out
    (list "  }" "  spacer;"
          (strcat "  : row { alignment = centered; "
                  ": button { label = \"OK\"; key = \"accept\"; "
                  "is_default = true; fixed_width = true; } "
                  ": button { label = \"Cancel\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; } }")
          "}")))

;; The hide editor: the same shape as the pin editor, every tool as a
;; toggle in as many columns as lzp:*colbudget* needs -- the WHOLE
;; roster, hidden or not, so a hidden tool is never harder to find than
;; the day it was hidden.  Unlike pins there is no row of buttons this
;; feeds, so there is no width or height budget of its own to hold to.
(defun lzp:dcl-hidden ( / out col c)
  (setq out (list "lazpanel_hidden : dialog {"
                  "  label = \"LazPanel  -  hidden tools\";"
                  (strcat "  : text { key = \"hidemsg\"; label = \"Ticked "
                          "tools stop appearing anywhere on the panel.\"; }")
                  "  : row {"))
  (foreach col (lzp:wrap (lzp:commands))
    (setq out (append out (list "    : column {")))
    (foreach c col
      (setq out (append out
        (list (strcat "      : toggle { label = \"" c
                      "\"; key = \"hd_" c "\"; }")))))
    (setq out (append out (list "    }"))))
  (append out
    (list "  }" "  spacer;"
          (strcat "  : row { alignment = centered; "
                  ": button { label = \"OK\"; key = \"accept\"; "
                  "is_default = true; fixed_width = true; } "
                  ": button { label = \"Cancel\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; } }")
          "}")))

;; The search page.  It carries the same furniture as every other page
;; -- status line, tab strip, pinned row, Close -- so moving onto it
;; and off it does not feel like leaving the panel; what is different
;; is the middle: a box to type in, the list of what matched, and a
;; message line under it.
;;
;; Run is the default button, so Enter runs the highlighted tool.  DCL
;; fires an edit box's action BEFORE the default button's, so typing a
;; search and pressing Enter narrows the list, selects the top hit and
;; then runs that -- in that order, which is the order that makes Enter
;; safe: the selection Run reads has already been replaced by one the
;; new search produced.
(defun lzp:dcl-find ( / out)
  (setq out (list (strcat (lzp:dlgname lzp:*findname*) " : dialog {")
                  (strcat "  label = \"LazPanel " *lazpanel-version*
                          "  -  Find\";")
                  (strcat "  : text { key = \"status\"; width = 60; "
                          "alignment = centered; }")))
  (setq out (append out (lzp:tabstrip) (lzp:recrow) (lzp:pinrow)))
  (append out
    (list (strcat "  : edit_box { key = \"filter\"; "
                  "label = \"Find\"; edit_width = 30; }")
          ;; wide enough for a row's worst case -- name, caption AND a
          ;; blurb, over 100 characters for the longest of the three --
          ;; confirmed against the screen budget by tools/check_dcl.py
          (strcat "  : list_box { key = \"hits\"; width = 130; "
                  "height = 14; }")
          "  : text { key = \"msg\"; width = 60; }"
          "  spacer;"
          "  : row {"
          "    alignment = centered;"
          (strcat "    : button { label = \"Run\"; key = \"run\"; "
                  "is_default = true; fixed_width = true; }")
          (strcat "    : button { label = \"Close\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; }")
          (strcat "    : button { label = \"Options...\"; "
                  "key = \"options_btn\"; fixed_width = true; }")
          "  }"
          "}")))

;; Every page, then the pin, hide and settings editors, in one
;; generated file.  Find leads, because it is the page that does not
;; need you to know where a tool was filed.
(defun lzp:dcl-lines ( / out g)
  (setq out (append (lzp:dcl-find) (list "")))
  (foreach g lzp:*groups*
    (setq out (append out (lzp:dcl-one g) (list ""))))
  (setq out (append out (lzp:dcl-pins) (list "")))
  (setq out (append out (lzp:dcl-hidden) (list "")))
  (setq out (append out (lzp:dcl-set) (list "")))
  (append out (lzp:dcl-names) (list "")))

;; The write loop, alone so it can run under vl-catch-all-apply: if a
;; write dies half way (disk full, quota) the handle still gets closed
;; and the partial file deleted instead of being handed to load_dialog.
(defun lzp:write-lines (fh / l)
  (foreach l (lzp:dcl-lines)
    (write-line l fh)))

;; Write the dialog into the system temp folder; the path comes back,
;; or nil when the folder cannot be written to.
(defun lzp:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "lazpanel" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'lzp:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err)
         (vl-file-delete f)
         nil)
        (t f)))))

;; Run a roster command by name, exactly as if it had been typed.  The
;; probe guards the greyed-button race: a command that vanished between
;; opening the panel and clicking reports itself instead of erroring.
(defun lzp:split (s sep / i n c cur out)
  (setq i 1 n (strlen s) cur "")
  (while (<= i n)
    (setq c (substr s i 1))
    (if (= c sep)
      (progn (if (/= cur "") (setq out (cons cur out))) (setq cur ""))
      (setq cur (strcat cur c)))
    (setq i (1+ i)))
  (if (/= cur "") (setq out (cons cur out)))
  (reverse out))

;; Read the pins back, dropping any name no longer on the roster: a pin
;; left over from an older build must not put a dead button on screen,
;; and the roster is the only thing that says what is real.
;; Drop pins from the END until the strip fits lzp:*pinrowmax* rows.
;; The cap is enforced as a tool is ticked, but a list stored by a
;; build that predates the cap has never been through it -- and the
;; same sentence applies as to a dead name: what is stored must not be
;; allowed to put a page on screen that cannot open.  The last pinned
;; go first, so the row the hand has learned is the part that survives.
(defun lzp:pintrim ( )
  (while (and lzp:*pins* (> (length (lzp:pinrows)) lzp:*pinrowmax*))
    (setq lzp:*pins* (reverse (cdr (reverse lzp:*pins*)))))
  lzp:*pins*)

(defun lzp:pins-read ( / s)
  (setq s (vl-catch-all-apply 'vl-registry-read (list lzp:*pinkey* "Pins")))
  (setq lzp:*pins*
    (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR) (/= s ""))
      (vl-remove-if-not '(lambda (n) (member n (lzp:commands)))
                        (lzp:split s ";"))))
  (lzp:pintrim))

(defun lzp:pins-write ( / s n)
  (setq s "")
  (foreach n lzp:*pins*
    (setq s (strcat s (if (= s "") "" ";") n)))
  (vl-catch-all-apply 'vl-registry-write (list lzp:*pinkey* "Pins" s))
  lzp:*pins*)

;; set_tile that cannot throw.  pin-toggle runs as a dialog action, so
;; the tiles are there when a drafter clicks -- but it is also called
;; directly, by the tests and by anything restoring a stored list, and
;; set_tile outside a dialog is an error, not a no-op.
(defun lzp:settile (key val)
  (vl-catch-all-apply 'set_tile (list key val)))

;; Pin order is click order: a newly ticked tool goes on the END rather
;; than jumping into the middle of a row the hand has already learned.
(defun lzp:pin-toggle (name val / was)
  (if (= val "1")
    (if (not (member name lzp:*pins*))
      (progn
        (setq was        lzp:*pins*
              lzp:*pins* (append lzp:*pins* (list name)))
        ;; one pin too many does not make a tall panel, it makes a page
        ;; that will not open -- so put it back and say why, rather
        ;; than storing something that breaks the next page opened
        (if (> (length (lzp:pinrows)) lzp:*pinrowmax*)
          (progn
            (setq lzp:*pins* was)
            (lzp:settile (strcat "tg_" name) "0")
            (lzp:settile "pinmsg"
                         (strcat "That is as many as the Pinned row"
                                 " holds - un-tick one first."))))))
    (setq lzp:*pins* (vl-remove name lzp:*pins*)))
  (princ))

;; The toggle dialog.  Cancel re-reads the registry rather than trying
;; to undo the ticks one by one -- the stored list is the truth, so
;; going back to it is exact where unwinding would be approximate.
(defun lzp:pin-edit (dcl / n rc)
  (cond
    ((not (new_dialog "lazpanel_pins" dcl)) nil)
    (t
     (foreach n (lzp:commands)
       (set_tile (strcat "tg_" n) (if (member n lzp:*pins*) "1" "0"))
       (action_tile (strcat "tg_" n)
                    (strcat "(lzp:pin-toggle \"" n "\" $value)")))
     (action_tile "accept" "(done_dialog 1)")
     (action_tile "cancel" "(done_dialog 0)")
     (setq rc (start_dialog))
     (if (= rc 1) (lzp:pins-write) (lzp:pins-read))
     t)))

;; The hide editor, same shape as lzp:pin-edit: Cancel re-reads the
;; registry rather than unwinding ticks one by one.
(defun lzp:hide-edit (dcl / n rc)
  (cond
    ((not (new_dialog "lazpanel_hidden" dcl)) nil)
    (t
     (foreach n (lzp:commands)
       (set_tile (strcat "hd_" n) (if (lzp:hidden-p n) "1" "0"))
       (action_tile (strcat "hd_" n)
                    (strcat "(lzp:hide-toggle \"" n "\" $value)")))
     (action_tile "accept" "(done_dialog 1)")
     (action_tile "cancel" "(done_dialog 0)")
     (setq rc (start_dialog))
     (if (= rc 1) (lzp:hidden-write) (lzp:hidden-read))
     t)))

(defun lzp:launch (name / fn)
  (setq fn (read (strcat "C:" name)))
  (cond
    ((eval fn)
     (princ (strcat "\nLAZPANEL: running " name
                    " -- LAZPANEL reopens the panel."))
     ;; remembered BEFORE it runs: a tool that errors out, or that is
     ;; cancelled with Escape, was still the one you reached for
     (lzp:remember name)
     (eval (list fn)))
    (t
     (princ (strcat "\nLAZPANEL: " name
                    " is not loaded in this session.")))))

;;; -------------------- the screen button -------------------------------
;;  A one-button toolbar so the panel can sit on screen like any other
;;  toolbar button -- drag it anywhere, dock it, click it to open the
;;  panel.  Created through the ActiveX menu API, so there is no CUI
;;  file to install; the icon is an orange hexagon, point north.
;;
;;  Everything here is best effort by design.  A session without COM,
;;  with a locked CUI or an unwritable temp folder loses the button and
;;  keeps the panel -- which is why the load-time call sits inside
;;  vl-catch-all-apply and why nothing below reports its own failure.

;; Which way AutoCAD's INTERFACE reads: 'dark, 'light, or nil when the
;; release will not say (COLORTHEME arrived with 2015).  CalofinTheme
;; in the profile overrides it, which is how a drafter fixes a wrong
;; guess without editing anything.  CALOFIN-LIB.lsp's cal:ui is this
;; function; the copy is here because a standalone file loads alone.
(defun lzp:ui ( / v c)
  ;; trimmed, as cal:themeset is: " dark " typed into the profile
  ;; meaning nothing at all would be a silent no-op to stare at
  (setq v (getenv "CalofinTheme")
        v (if (and v (/= v "")) (strcase (vl-string-trim " \t" v)) "AUTO"))
  (cond ((= v "DARK") 'dark)
        ((= v "LIGHT") 'light)
        ((null (setq c (getvar "COLORTHEME"))) nil)
        ((= c 0) 'dark)
        (t 'light)))

;; The mark: a hexagon with a corner facing north.  Each size is
;; drawn at its own resolution rather than the small one doubled --
;; a hexagon doubled from 16 pixels keeps the 16-pixel staircase on
;; its diagonals, and those diagonals are the whole shape.
(setq lzp:*icon16*
  '(
    "................"
    "......XXXX......"
    ".....XXXXXX....."
    "...XXXXXXXXXX..."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    "...XXXXXXXXXX..."
    ".....XXXXXX....."
    "......XXXX......"
    "................"))

(setq lzp:*icon32*
  '(
    "................................"
    "..............XXXX.............."
    ".............XXXXXX............."
    "...........XXXXXXXXXX..........."
    ".........XXXXXXXXXXXXXX........."
    ".......XXXXXXXXXXXXXXXXXX......."
    "......XXXXXXXXXXXXXXXXXXXX......"
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "......XXXXXXXXXXXXXXXXXXXX......"
    ".......XXXXXXXXXXXXXXXXXX......."
    ".........XXXXXXXXXXXXXX........."
    "...........XXXXXXXXXX..........."
    ".............XXXXXX............."
    "..............XXXX.............."
    "................................"))

(defun lzp:le2 (n)
  (list (rem n 256) (rem (/ n 256) 256)))

(defun lzp:le4 (n)
  (append (lzp:le2 (rem n 65536)) (lzp:le2 (/ n 65536))))

;; The complete .bmp as a byte list: 24bpp, bottom-up rows (a positive
;; height means the FIRST row in the file is the BOTTOM row of the
;; image, hence the reverse).  "X" pixels are orange -- stored B,G,R,
;; so 0 165 255 -- and the rest is PANEL GREY, which is two different
;; greys: a .bmp has no alpha channel, so the square around the
;; hexagon is painted, and painting it 54 54 54 on the light theme is
;; a dark tile in a light toolbar.  It was, for every drafter not on
;; the dark theme, from the day the button shipped.  The theme is read
;; rather than assumed, and an unreadable one keeps the dark grey that
;; was always here.  Both sizes give a row width that is a multiple of
;; 4 (48 and 96), so there is no row padding to get wrong.
(defun lzp:bmp-bytes (size grid / fg bg rowbytes out row s i)
  (setq fg '(0 165 255)
        bg (if (eq (lzp:ui) 'light) '(240 240 240) '(54 54 54))
        rowbytes (* 3 size))
  (setq out (append
              (list 66 77)                      ; "BM"
              (lzp:le4 (+ 54 (* rowbytes size)))
              '(0 0 0 0)
              (lzp:le4 54)                      ; pixel data offset
              (lzp:le4 40)                      ; BITMAPINFOHEADER
              (lzp:le4 size)
              (lzp:le4 size)
              (lzp:le2 1)                       ; planes
              (lzp:le2 24)                      ; bits per pixel
              (lzp:le4 0)                       ; no compression
              (lzp:le4 (* rowbytes size))
              (lzp:le4 0) (lzp:le4 0)
              (lzp:le4 0) (lzp:le4 0)))
  ;; built by consing and reversed once: appending inside the loop
  ;; would copy the whole list per pixel, which for the 32x32 is
  ;; millions of cons cells and a visible pause on every load
  (setq out (reverse out))
  (foreach row (reverse grid)
    (setq i 1)
    (while (<= i size)
      (setq s (substr row i 1))
      (setq out (cons (caddr (if (= s "X") fg bg))
                      (cons (cadr (if (= s "X") fg bg))
                            (cons (car (if (= s "X") fg bg)) out))))
      (setq i (1+ i))))
  (reverse out))

;;  WRITING IT.  Not with write-char: AutoLISP opens files in text mode
;;  and has no NUL in its character model at all -- (chr 0) is the
;;  empty string -- while a 24-bit BMP header is full of them.  The
;;  pixel-data offset (54 0 0 0), the header size (40 0 0 0) and the
;;  five zeroed DIB fields are 43 NULs before a single pixel, and the
;;  orange itself has a zero blue channel.  There is no arrangement of
;;  this format that write-char could emit, so the bytes go out through
;;  an ADODB.Stream in binary mode instead.
;;
;;  That is no new dependency: the toolbar this icon goes on is made
;;  through the ActiveX menu API a few lines below, so a session that
;;  cannot reach COM has no button to put an icon on.  If the stream
;;  is unavailable the write fails, the caller skips SetBitmaps, and
;;  the button keeps its default face.

;; A byte array is the one piece of this that AutoLISP may refuse:
;; vlax-make-safearray's documented type constants stop at
;; vlax-vbVariant, and VT_UI1 (17) is not among them, so whether it is
;; accepted is a property of the release rather than of the code.  Both
;; spellings are tried before giving up, and which one worked is
;; recorded for LAZICON to report.
;;  BASE64, AND WHY THE ICON GOES OUT THROUGH IT.
;;
;;  ADODB.Stream's Write wants a VT_UI1 (byte) array and nothing else.
;;  AutoLISP cannot reliably make one: vlax-make-safearray's documented
;;  type constants stop at vlax-vbVariant, VT_UI1 (17) is not among
;;  them, and whether a release accepts it anyway is a property of that
;;  release.  Where it is refused the old code fell back to a
;;  vbInteger (VT_I2) array, which Write then rejected with
;;
;;      Arguments are of the wrong type, are out of acceptable range,
;;      or are in conflict with one another
;;
;;  -- reported from the field, and the reason the button had no
;;  picture at all rather than a wrong one.
;;
;;  The way round it is to stop trying to build a byte array in
;;  AutoLISP.  Base64 is a pure-ASCII encoding of arbitrary bytes --
;;  no NUL, nothing AutoLISP's character model lacks -- so the bytes
;;  can be carried in an ordinary string, and MSXML turns that string
;;  into a real VT_UI1 array on the other side.  Both components ship
;;  with Windows, and the toolbar this icon goes on already needs COM.
;;  NOT A KNOB: the alphabet is RFC 4648's, the same 64 characters on
;;  both ends of the transfer.  It is a literal nothing re-assigns, so
;;  it is shaped like a tunable and tests/test_tunables.py would ask
;;  for it in the block at the top -- but reordering a character here
;;  does not adjust anything, it decodes the icon to garbage.
(setq lzp:*b64*
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

;; Join a list of strings without the quadratic cost of strcat-ing onto
;; one accumulator: a 32x32 icon is 4168 base64 characters, and growing
;; that a chunk at a time copies the whole string every time.  Pairwise
;; merging is O(n log n) and finishes instantly.
(defun lzp:joinstr (lst / out a)
  (while (cdr lst)
    (setq out nil)
    (while lst
      (setq a (car lst) lst (cdr lst))
      (if lst
        (setq out (cons (strcat a (car lst)) out) lst (cdr lst))
        (setq out (cons a out))))
    (setq lst (reverse out)))
  (if lst (car lst) ""))

;; Bytes to base64.  Plain integer arithmetic rather than lsh/logand:
;; the shifts are all by 2, 4 and 6 bits, which is division and
;; multiplication by 4, 16 and 64, and every AutoLISP has those.
(defun lzp:b64 (bytes / out n b1 b2 b3)
  (while bytes
    (setq b1 (car bytes) bytes (cdr bytes) n 1 b2 0 b3 0)
    (if bytes (setq b2 (car bytes) bytes (cdr bytes) n 2))
    (if bytes (setq b3 (car bytes) bytes (cdr bytes) n 3))
    (setq out
      (cons
        (strcat
          (substr lzp:*b64* (1+ (/ b1 4)) 1)
          (substr lzp:*b64* (1+ (+ (* (rem b1 4) 16) (/ b2 16))) 1)
          (if (>= n 2)
            (substr lzp:*b64* (1+ (+ (* (rem b2 16) 4) (/ b3 64))) 1)
            "=")
          (if (>= n 3) (substr lzp:*b64* (1+ (rem b3 64)) 1) "="))
        out)))
  (lzp:joinstr (reverse out)))

;; The base64 string as a real byte array, via MSXML's bin.base64
;; element.  nodeTypedValue on such an element IS a VT_UI1 array, which
;; is exactly what Write will take.
;; The whole chain on one document: an element typed bin.base64, the
;; base64 text put into it, and the byte array read back out.
(defun lzp:b64-chain (doc b64 / el out)
  ;; the documented long spellings, not the vlax-get / vlax-put /
  ;; vlax-invoke shorthands: the shorthands are what the rest of this
  ;; file uses and they clearly work here, but this chain is the part
  ;; that keeps coming back empty, so it does not get to be the place
  ;; a spelling is also in question
  (setq el (vlax-invoke-method doc 'createElement "b"))
  (vlax-put-property el 'dataType "bin.base64")
  (vlax-put-property el 'text b64)
  (setq out (vlax-get-property el 'nodeTypedValue))
  (vl-catch-all-apply 'vlax-release-object (list el))
  out)

;; One ProgID, tried all the way through.  nil if this version cannot
;; carry it.
(defun lzp:whynot (id msg)
  (setq lzp:*msxmlwhy*
        (cons (strcat id ": " msg) lzp:*msxmlwhy*))
  nil)

(defun lzp:b64-try (id b64 / doc r)
  (setq r (vl-catch-all-apply 'vlax-create-object (list id)))
  (cond
    ((vl-catch-all-error-p r)
     (lzp:whynot id (vl-catch-all-error-message r)))
    ((null r) (lzp:whynot id "came back nil"))
    (t
     (setq doc r)
     (setq r (vl-catch-all-apply 'lzp:b64-chain (list doc b64)))
     (vl-catch-all-apply 'vlax-release-object (list doc))
     (cond
       ((vl-catch-all-error-p r)
        (lzp:whynot id (vl-catch-all-error-message r)))
       ((null r) (lzp:whynot id "the chain ran but gave back nothing"))
       (t (setq lzp:*icontype* (strcat "bin.base64 via " id))
          r)))))

;;  EVERY ProgID IS TRIED ALL THE WAY THROUGH, not just far enough to
;;  create.  MSXML 6.0 creates perfectly happily and then refuses
;;  dataType -- XDR schema support, of which bin.base64 is part, was
;;  removed in 6.0 -- so a version test that stops at "did the object
;;  appear?" picks 6.0, fails on the next line, and reports nothing.
;;  That is exactly what happened in the field: the report said
;;  "array: VT_UI1 safearray", meaning this returned nil and the
;;  fallback ran.
;;
;;  So 3.0 and the version-independent Microsoft.XMLDOM come first --
;;  both carry XDR -- and 6.0 stays at the back where it costs one
;;  failed attempt and nothing else.
(defun lzp:bytes-msxml (bytes / b64 out id)
  (setq lzp:*msxmlwhy* nil)
  (setq b64 (lzp:b64 bytes))
  (foreach id '("MSXML2.DOMDocument.3.0" "Microsoft.XMLDOM"
                "MSXML2.DOMDocument" "MSXML2.DOMDocument.6.0")
    (if (not out) (setq out (lzp:b64-try id b64))))
  out)

;; A byte array by whichever route this AutoCAD allows.  MSXML first
;; because it is the one that does not depend on an undocumented
;; safearray type; the two safearray spellings stay as fallbacks so a
;; machine where they DO work is no worse off.  Which route won is
;; recorded for LAZICON to report.
(defun lzp:bytearray (bytes / sa)
  (cond
    ;; lzp:b64-try has already recorded WHICH MSXML version carried it,
    ;; which is the part worth knowing; do not flatten that back to a
    ;; generic label here
    ((setq sa (lzp:bytes-msxml bytes)) sa)
    (t
     (setq sa (vl-catch-all-apply
                'vlax-make-safearray
                (list 17 (cons 0 (1- (length bytes))))))
     (if (vl-catch-all-error-p sa)
         (setq sa (vl-catch-all-apply
                    'vlax-make-safearray
                    (list vlax-vbInteger (cons 0 (1- (length bytes)))))
               lzp:*icontype* "vbInteger (VT_I2 - Write may refuse this)")
         (setq lzp:*icontype* "VT_UI1 safearray"))
     (cond
       ((vl-catch-all-error-p sa) (setq lzp:*icontype* "none - no array could be made") nil)
       (t (vlax-safearray-fill sa bytes)
          sa)))))

(defun lzp:bmp-stream (st path bytes / sa)
  (setq lzp:*icontype* nil)
  ;; each step names itself before it runs, so a failure reports WHICH
  ;; call refused rather than one COM message with no address on it
  (setq lzp:*iconstep* "building the byte array")
  (if (not (setq sa (lzp:bytearray bytes)))
      (exit))                                 ; caught by the caller
  (setq lzp:*iconstep* "Type = 1 (adTypeBinary)")
  (vlax-put st 'Type 1)
  (setq lzp:*iconstep* "Open")
  (vlax-invoke st 'Open)
  ;; Two spellings.  Write takes a Variant, and whether a raw safearray
  ;; marshals into one is another thing that varies by release -- so if
  ;; the plain call is refused, the wrapped one is tried before giving
  ;; up.  The step name says which was in play.
  (setq lzp:*iconstep* "Write")
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vlax-invoke (list st 'Write sa)))
    (progn
      (setq lzp:*iconstep* "Write (variant-wrapped)")
      (vlax-invoke st 'Write (vlax-make-variant sa))))
  (setq lzp:*iconstep* "SaveToFile")
  (vlax-invoke st 'SaveToFile path 2)         ; overwrite if present
  (setq lzp:*iconstep* "Close")
  (vlax-invoke st 'Close)
  (setq lzp:*iconstep* nil)
  t)

;;; -------------------- the route that needs no byte array ---------------
;;  Every failure so far has been about handing AutoLISP's idea of an
;;  array to COM.  VT_UI1 was accepted on the machine that reported it
;;  and Write refused the array anyway, wrapped in a variant or not;
;;  MSXML, which exists to sidestep that, came back empty.
;;
;;  So here is the route with no array in it at all.  certutil has
;;  shipped with Windows since Vista and decodes base64 to binary in
;;  one command.  AutoLISP writes the base64 as ORDINARY TEXT with
;;  write-line -- which is the one thing it has never had trouble with
;;  -- and Windows does the decoding.  Nothing crosses the COM boundary
;;  except a command line.
;;
;;  It is last because it costs a process and writes a second file;
;;  when the stream route works this never runs.
(defun lzp:b64-lines (b64 fh / i n)
  ;; certutil wants the base64 wrapped rather than one enormous line
  (setq i 1 n (strlen b64))
  (while (<= i n)
    (write-line (substr b64 i 76) fh)
    (setq i (+ i 76))))

(defun lzp:bmp-certutil (path bytes / tmp fh sh r out)
  (setq tmp (strcat path ".b64"))
  (cond
    ((not (setq fh (open tmp "w")))
     (setq lzp:*iconerr*
           (strcat lzp:*iconerr* "  certutil: could not write " tmp "."))
     nil)
    (t
     (setq r (vl-catch-all-apply 'lzp:b64-lines (list (lzp:b64 bytes) fh)))
     (close fh)
     (cond
       ((vl-catch-all-error-p r)
        (vl-file-delete tmp)
        (setq lzp:*iconerr*
              (strcat lzp:*iconerr* "  certutil: writing the base64 failed: "
                      (vl-catch-all-error-message r)))
        nil)
       (t
        (setq sh (vl-catch-all-apply 'vlax-create-object
                                     (list "WScript.Shell")))
        (cond
          ((vl-catch-all-error-p sh)
           (vl-file-delete tmp)
           (setq lzp:*iconerr*
                 (strcat lzp:*iconerr* "  certutil: WScript.Shell would not "
                         "start: " (vl-catch-all-error-message sh)))
           nil)
          (t
           ;; the third argument waits for it, so the file is there by
           ;; the time this returns rather than some moments later
           (setq r (vl-catch-all-apply
                     'vlax-invoke-method
                     (list sh 'Run
                           (strcat "cmd /c certutil -f -decode \"" tmp
                                   "\" \"" path "\"")
                           0 :vlax-true)))
           (vl-catch-all-apply 'vlax-release-object (list sh))
           (vl-file-delete tmp)
           (cond
             ((vl-catch-all-error-p r)
              (setq lzp:*iconerr*
                    (strcat lzp:*iconerr* "  certutil: " 
                            (vl-catch-all-error-message r)))
              nil)
             ((findfile path) (setq lzp:*icontype* "base64 text + certutil") t)
             (t (setq lzp:*iconerr*
                      (strcat lzp:*iconerr* "  certutil ran but wrote nothing."))
                nil)))))))))

(defun lzp:bmp-via-stream (path bytes / st ok)
  (setq st (vl-catch-all-apply 'vlax-create-object (list "ADODB.Stream")))
  (cond
    ((vl-catch-all-error-p st)
     (setq lzp:*iconerr*
           (strcat "ADODB.Stream would not start: "
                   (vl-catch-all-error-message st)))
     nil)
    ((null st)
     (setq lzp:*iconerr* "ADODB.Stream came back nil.")
     nil)
    (t
     (setq ok (vl-catch-all-apply 'lzp:bmp-stream (list st path bytes)))
     (vl-catch-all-apply 'vlax-release-object (list st))
     (cond
       ((vl-catch-all-error-p ok)
        (setq lzp:*iconerr*
              (strcat "writing " path " failed at "
                      (if lzp:*iconstep* lzp:*iconstep* "an unnamed step")
                      ": " (vl-catch-all-error-message ok)))
        nil)
       (t path)))))

;; The icon, by whichever route this machine allows.  The stream first
;; because it writes the file directly; certutil after it, because it
;; costs a process and a second file but asks nothing of AutoLISP but
;; text.  Which one won is recorded for LAZICON to report.
(defun lzp:bmp-write (path size grid / bytes)
  (setq lzp:*iconerr* ""
        lzp:*iconroute* nil
        bytes (lzp:bmp-bytes size grid))
  (cond
    ((lzp:bmp-via-stream path bytes)
     (setq lzp:*iconroute* "ADODB.Stream" lzp:*iconerr* nil)
     path)
    ((lzp:bmp-certutil path bytes)
     (setq lzp:*iconroute* "certutil")
     path)
    (t nil)))

;; A STABLE path, not a fresh temp name each time: SetBitmaps stores the
;; path rather than the image, and AutoCAD re-reads it whenever the
;; button is redrawn.  A toolbar that survives into another session
;; would otherwise be pointing at a swept temp file for ever.
(defun lzp:icon-file (dir name / d)
  (setq d dir)
  ;; a folder is not guaranteed to end in a separator -- glue the name
  ;; straight on and a folder called Temp becomes a file called
  ;; Templazpanel-16.bmp, which fails silently later
  (if (not (member (substr d (strlen d) 1) '("\\" "/")))
      (setq d (strcat d "\\")))
  (strcat d "lazpanel-" name ".bmp"))

(defun lzp:icon-path (name / d)
  (setq d (getvar "TEMPPREFIX"))
  (if (and d (= (type d) 'STR) (/= d ""))
      (lzp:icon-file d name)
      (vl-filename-mktemp (strcat "lazpanel-" name) nil ".bmp")))

;;  WHERE THE FILES GO, AND WHAT SETBITMAPS IS TOLD.  The CUI resolves a
;;  toolbar bitmap by NAME along the support file search path -- hand it
;;  a full path into the temp folder, which is not on that path, and on
;;  many builds the button draws the "?" missing-image placeholder even
;;  though the file is right where the path says.  So the icons go into
;;  the FIRST folder of the support path (the user's own Support folder,
;;  writable by design) and SetBitmaps is handed the bare names, which
;;  resolve exactly the way the CUI wants to resolve them.  Only when
;;  that folder cannot be written does this fall back to the temp folder
;;  and full paths -- better a chance of an icon than none.

(defun lzp:support-read ()
  (vla-get-supportpath
    (vla-get-files (vla-get-preferences (vlax-get-acad-object)))))

;; The first entry of the support path, or nil.
(defun lzp:support-dir ( / p out i n c)
  (setq p (vl-catch-all-apply 'lzp:support-read nil))
  (if (and (not (vl-catch-all-error-p p)) (= (type p) 'STR) (/= p ""))
      (progn
        (setq i 1 n (strlen p) out "")
        (while (and (<= i n) (/= (setq c (substr p i 1)) ";"))
          (setq out (strcat out c)
                i (1+ i)))
        (if (/= out "") out))))

;; Write both sizes into DIR; the paths, or nil when either write fails
;; (lzp:bmp-write records why in lzp:*iconerr*).
(defun lzp:try-icons (dir / s l)
  (if (and dir (= (type dir) 'STR) (/= dir ""))
      (progn
        (setq s (lzp:icon-file dir "16")
              l (lzp:icon-file dir "32"))
        ;; Both already on disk from an earlier load: nothing to write.
        ;; The picture never changes, and writing it again on every
        ;; drawing open (a Startup Suite runs this file per document)
        ;; put two COM round trips and two file writes -- into a
        ;; shared network support folder, on some sites -- behind every
        ;; OPEN.  A missing or half-written pair is still rewritten.
        (cond
          ((and (findfile s) (findfile l))
           (setq lzp:*icondir* dir)
           (list s l))
          ((and (lzp:bmp-write s 16 lzp:*icon16*)
                (lzp:bmp-write l 32 lzp:*icon32*))
           (setq lzp:*icondir* dir
                 lzp:*iconwrote* t)
           (list s l))))))

;; What to hand SetBitmaps: bare names when the files sit on the support
;; path, full temp paths as the fallback.
(defun lzp:write-bmps ( / d)
  (setq lzp:*icondir* nil
        lzp:*iconref* nil
        lzp:*iconwrote* nil)
  (cond
    ((and (setq d (lzp:support-dir)) (lzp:try-icons d))
     (setq lzp:*iconref* "name")
     (list "lazpanel-16.bmp" "lazpanel-32.bmp"))
    ((lzp:try-icons (getvar "TEMPPREFIX"))
     (setq lzp:*iconref* "path")
     (list (lzp:icon-file (getvar "TEMPPREFIX") "16")
           (lzp:icon-file (getvar "TEMPPREFIX") "32")))))

;; The LazPanel toolbar, wherever it lives -- one this file made in an
;; earlier session may sit in any loaded menu group.
(defun lzp:toolbar-find ( / mgs n i tbs m j tb found)
  (setq mgs (vla-get-menugroups (vlax-get-acad-object)))
  (setq n (vla-get-count mgs)
        i 0)
  (while (and (< i n) (not found))
    (setq tbs (vla-get-toolbars (vla-item mgs i)))
    (setq m (vla-get-count tbs)
          j 0)
    (while (and (< j m) (not found))
      (setq tb (vla-item tbs j))
      (if (= (strcase (vla-get-name tb)) (strcase lzp:*tbname*))
        (setq found tb))
      (setq j (1+ j)))
    (setq i (1+ i)))
  found)

;; Make the toolbar with its one button.  The macro is what a menu
;; button really sends: two Cancels (ASCII 3 -- the COM API takes the
;; raw characters, not the "^C^C" spelling a menu FILE would use) and
;; the command.
;;
;; The button goes in at index 0.  The toolbar was created empty a line
;; earlier, so 1 is past its end -- and if that throws, an empty
;; toolbar called LazPanel is left behind, which lzp:toolbar-find would
;; then hand back for ever while LAZBUTTON reported success and put
;; nothing on screen.  So a toolbar that fails to get its button does
;; not survive the attempt.
(defun lzp:toolbar-make ( / tbs tb btn)
  (setq tbs (vla-get-toolbars
              (vla-item (vla-get-menugroups (vlax-get-acad-object)) 0)))
  (setq tb (vla-add tbs lzp:*tbname*))
  (setq btn (vl-catch-all-apply
              'vla-addtoolbarbutton
              (list tb 0 lzp:*tbname*
                    "Open the LazPanel tool panel"
                    (strcat (chr 3) (chr 3) "_LAZPANEL "))))
  (cond
    ((vl-catch-all-error-p btn)
     (vl-catch-all-apply 'vla-delete (list tb))
     nil)
    (t (list tb btn))))

;; Put the button on screen: reuse the toolbar when one exists -- its
;; position and docking are the user's -- otherwise create it and float
;; it in view.  Either way the icons are rewritten and re-applied, and
;; the toolbar is made visible: a toolbar the user closed is still
;; found by name, and without this it would never come back.
;; Returns the toolbar, or nil when there is none to be had.
(defun lzp:button-init ( / tb btn pair paths made)
  (cond
    ((setq tb (lzp:toolbar-find))
     (setq btn (vl-catch-all-apply 'vla-item (list tb 0)))
     (if (vl-catch-all-error-p btn) (setq btn nil)))
    ((setq pair (lzp:toolbar-make))
     (setq tb (car pair)
           btn (cadr pair)
           made t)))
  (if tb
    (progn
      (if (and btn (setq paths (lzp:write-bmps)))
        (vl-catch-all-apply 'vla-setbitmaps
                            (list btn (car paths) (cadr paths)))
        ;; one line, not a stack trace: the panel still works without a
        ;; picture, but a blank button should not be a mystery
        (princ "\n[lazpanel] button picture not applied - LAZICON says why."))
      (vl-catch-all-apply 'vla-put-visible (list tb :vlax-true))
      (if made (vl-catch-all-apply 'vla-float (list tb 200 300 1)))))
  tb)

;;; -------------------- the dialog run ----------------------------------
;;  No sysvar save, no undo group: the panel changes no settings and
;;  draws nothing -- whatever it launches manages its own.  The error
;;  handler only has the dialog and the temp file to pick up.
;;
;;  This is a helper rather than the command body so that its localized
;;  *error* is OUT OF SCOPE by the time anything is launched: the tool
;;  the user clicked gets whatever error handling it sets up itself,
;;  and a tool that fails reports as itself, not as "LAZPANEL error".

(defun lzp:show ( / *error* f dcl rc pick have n g done out)
  (defun *error* (msg)
    ;; the dialog itself first: unload_dialog alone does not dismiss a
    ;; dialog that is still up, term_dialog does (and is a no-op when
    ;; none is)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil lzp:*pick* nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZPANEL error: " msg)))
    (if lzd:report (lzd:report "LAZPANEL" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZPANEL" *lazpanel-version*))
  ;; NOT reset here: the panel reopens after every tool it launches, and
  ;; coming back to page one in the middle of the screen each time would
  ;; undo the whole point of reopening.  lzp:*page* and lzp:*pos* are
  ;; where the user last had it.
  (setq lzp:*pick* nil)
  (if (not (and lzp:*page* (member lzp:*page* (lzp:pages))))
    (setq lzp:*page* (car (car lzp:*groups*))))
  (setq g lzp:*page*)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPANEL error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPANEL error: could not load the dialog file.")
     (vl-file-delete f))
    (t
     ;; The page loop.  One page per group, so the eye lands on a dozen
     ;; buttons rather than all of them; the tab strip is the whole
     ;; roster and never changes width as you move along it.
     (while (not done)
       (cond
         ((not (lzp:newdlg (lzp:dlgname g) dcl))
          (princ "\nLAZPANEL error: could not open the panel.")
          (setq done t))
         (t
          (setq lzp:*page* g
                have (lzp:loaded))
          (set_tile "status"
                    (strcat (itoa (length (vl-remove-if 'lzp:hidden-p have)))
                            " of " (itoa (length (lzp:visible)))
                            (if (lzp:findpage g)
                              " tools loaded - the rest are listed, not run"
                              " tools loaded - greyed are not in this session")))
          ;; The search page has no per-command buttons to wire: its
          ;; three tiles carry the whole roster between them, and the
          ;; list is filled with the search the panel was last left on.
          (cond
            ((lzp:findpage g)
             (set_tile "filter" lzp:*filter*)
             (lzp:fill lzp:*filter*)
             (action_tile "filter" "(lzp:fill $value)")
             (action_tile "hits" "(lzp:hitpick $value $reason)")
             (action_tile "run" "(lzp:findrun)"))
            (t
             (foreach n (lzp:group-commands g)
               (action_tile n
                 "(setq lzp:*pick* $key lzp:*pos* (done_dialog 1))")
               (if (not (member n have))
                 (mode_tile n 1)))))
          ;; the pinned row: same launch, its own keys, greyed the same
          ;; way -- $key would read "pin_POOL", so the name is baked in.
          ;; lzp:pinshown, not lzp:*pins* itself: a hidden-but-pinned
          ;; tool has no button in the DCL lzp:pinrow just wrote, and
          ;; wiring a key that is not there is an error, not a no-op.
          (foreach n (lzp:pinshown)
            (action_tile (strcat "pin_" n)
              (strcat "(setq lzp:*pick* \"" n
                      "\" lzp:*pos* (done_dialog 1))"))
            (if (not (member n have))
              (mode_tile (strcat "pin_" n) 1)))
          ;; the recent row: the same launch again, its own keys
          (foreach n (lzp:recshown)
            (action_tile (strcat "rec_" n)
              (strcat "(setq lzp:*pick* \"" n
                      "\" lzp:*pos* (done_dialog 1))"))
            (if (not (member n have))
              (mode_tile (strcat "rec_" n) 1)))
          (action_tile "pin_edit" "(setq lzp:*pos* (done_dialog 5))")
          ;; a settings launch, not a roster one: it goes through the
          ;; ordinary rc=1 pick path (full teardown before it runs,
          ;; same as any button) but *options* is a sentinel c:LAZPANEL
          ;; reads itself rather than a name lzp:launch would look up --
          ;; CALSET is not on the roster and must never land in Recent
          (action_tile "options_btn"
            "(setq lzp:*pick* \"*options*\" lzp:*pos* (done_dialog 1))")
          (foreach n (lzp:pages)
            (action_tile (strcat "tab_" n)
              (strcat "(setq lzp:*go* \"" n
                      "\" lzp:*pos* (done_dialog 4))")))
          (action_tile "cancel" "(setq lzp:*pos* (done_dialog 0))")
          (setq rc (lzp:rundlg))
          (cond
            ((= rc 4) (setq g lzp:*go* lzp:*page* lzp:*go*))  ; a tab
            ;; the pin editor runs on the same loaded handle, then the
            ;; caller reopens: the Pinned row is generated DCL, so it
            ;; only changes when the file is written again
            ((= rc 5)
             (lzp:pin-edit dcl)
             (setq done t out "*pins*"))
            (t (setq done t
                     out (if (= rc 1) lzp:*pick*)))))))))
  ;; the dialog and its temp file go away BEFORE anything is launched,
  ;; so an interactive command never starts under an open modal dialog
  ;; and the temp file never outlives the panel
  (if (and dcl (>= dcl 0)) (unload_dialog dcl))
  (setq dcl nil)
  (if f (vl-file-delete f))
  (setq f nil lzp:*pick* nil)
  out)

;; WHERE THE PANEL COMES BACK UP.  done_dialog reports the position it
;; closed at, and that is the only chance to find out -- DCL cannot ask
;; an open dialog where it is.  Held in lzp:*pos* alone that answer lasts
;; until the file is reloaded, so the point also goes into the AutoCAD
;; profile as "x,y" and is read back at the next open: come back after a
;; restart and the panel is still where it was left.
(defun lzp:pos-save (p)                 ; answers with what it was given,
  (if (and p (listp p) (= (length p) 2) ; so it can wrap a done_dialog
           (numberp (car p)) (numberp (cadr p)))
    (setenv lzp:*poskey*
            (strcat (itoa (fix (car p))) "," (itoa (fix (cadr p))))))
  p)

;; The saved point, or nil when there is nothing worth trusting.  Only a
;; string this build could have written is taken -- the parse has to
;; round-trip -- so a hand-edited or foreign profile value can do no
;; more than centre the panel, which is what it did before.  The clamp
;; is a rescue and not a fence: a point saved on a second monitor that
;; has since been unplugged would otherwise put the panel where the
;; mouse cannot reach it.  SCREENSIZE is the drawing area rather than
;; the desktop, so the clamp can only ever pull one IN.
(defun lzp:pos-read ( / s i x y scr)
  (setq s (getenv lzp:*poskey*))
  (if (and s (setq i (vl-string-search "," s)) (> i 0))
    (progn
      (setq x (atoi (substr s 1 i))
            y (atoi (substr s (+ i 2))))
      (if (= s (strcat (itoa x) "," (itoa y)))
        (progn
          (setq scr (getvar "SCREENSIZE"))
          (if (and scr (listp scr) (= (length scr) 2)
                   (numberp (car scr)) (numberp (cadr scr)))
            (setq x (max 0 (min x (fix (- (car scr) 100.0))))
                  y (max 0 (min y (fix (- (cadr scr) 100.0))))))
          (list x y))))))

;; Open a page where the user last had the panel.  new_dialog takes a
;; position back, but only in its four-argument form -- and a build
;; answering done_dialog with something other than a point would poison
;; every reopen, so the shape is checked before it is trusted and the
;; plain two-argument call is the fallback.  lzp:*pos* is this session's
;; answer; the profile is the one the last session left behind.
(defun lzp:newdlg (name dcl / p)
  (setq p (if lzp:*pos* lzp:*pos* (lzp:pos-read)))
  (if (and p (listp p) (= (length p) 2)
           (numberp (car p)) (numberp (cadr p)))
      (new_dialog name dcl "" p)
      (new_dialog name dcl)))

;; start_dialog, then keep where the panel was left.  Saving here
;; rather than in the five action tiles keeps setenv out of a dialog
;; callback and gives the profile write one place to go wrong.
(defun lzp:rundlg ( / rc)
  (setq rc (start_dialog))
  (lzp:pos-save lzp:*pos*)
  rc)

;;; -------------------- commands ----------------------------------------

;;  THE REOPEN.  A DCL dialog is modal, so the panel still has to close
;;  for a tool to run -- but it no longer has to be reopened by hand.
;;  The loop is the feature: click, the panel closes, the tool runs to
;;  its own end, the panel comes straight back on the page and at the
;;  screen position it was at, with the session re-probed so a tool
;;  loaded meanwhile is no longer greyed.  Close is the way out, and it
;;  is the default button.
;;
;;  A tool cancelled with Escape comes back here exactly as a finished
;;  one does: lzp:launch has already returned by then, so the reopen is
;;  not conditional on the tool having succeeded.  A tool that dies with
;;  a hard error DOES end the loop -- its own *error* runs, the panel
;;  simply does not come back, and LAZPANEL reopens it.  That is the
;;  right way round: the alternative is a panel that keeps bouncing back
;;  in front of someone trying to read the error it just printed.
(defun c:LAZPANEL ( / pick)
  (lzp:pins-read)
  (lzp:recent-read)
  (lzp:hidden-read)
  (while (setq pick (lzp:show))
    (cond
      ((= pick "*pins*"))            ; already handled inside lzp:show
      ((= pick "*options*") (c:LAZSET))  ; settings, never a roster launch
      (t (lzp:launch pick))))
  (princ))

;; Open the pin editor on its own, without going through the panel.
(defun c:LAZPIN ( / *error* f dcl)
  ;; an error inside a tile callback used to leak the dialog handle
  ;; and the temp .dcl
  (defun *error* (msg)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (if f (vl-file-delete f))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZPIN error: " msg)))
    (if lzd:report (lzd:report "LAZPIN" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZPIN" *lazpanel-version*))
  (lzp:pins-read)
  (lzp:recent-read)
  (lzp:hidden-read)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPIN error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPIN error: could not load the dialog file.")
     (vl-file-delete f))
    (t
     (lzp:pin-edit dcl)
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZPANEL: "
                    (itoa (length lzp:*pins*)) " tools pinned."))))
  (if lzd:end (lzd:end "LAZPIN"))
  (princ))

;; Open the hide editor on its own, without going through the panel.
(defun c:LAZHIDE ( / *error* f dcl)
  ;; an error inside a tile callback used to leak the dialog handle
  ;; and the temp .dcl -- the same fix c:LAZPIN carries
  (defun *error* (msg)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (if f (vl-file-delete f))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZHIDE error: " msg)))
    (if lzd:report (lzd:report "LAZHIDE" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZHIDE" *lazpanel-version*))
  (lzp:pins-read)
  (lzp:recent-read)
  (lzp:hidden-read)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZHIDE error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZHIDE error: could not load the dialog file.")
     (vl-file-delete f))
    (t
     (lzp:hide-edit dcl)
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZPANEL: "
                    (itoa (length lzp:*hidden*)) " tools hidden."))))
  (if lzd:end (lzd:end "LAZHIDE"))
  (princ))

(defun c:LAZBUTTON ( / *error* tb)
  ;; Nothing to put back -- this command opens no undo group and
  ;; changes no system variable -- but a failure still has to be SAID,
  ;; and said to LAZDIAG, or it is the one command in the build whose
  ;; bugs arrive as a bare AutoCAD message with no report behind them.
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZBUTTON error: " msg)))
    (if lzd:report (lzd:report "LAZBUTTON" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZBUTTON" *lazpanel-version*))
  (setq tb (vl-catch-all-apply 'lzp:button-init nil))
  (cond
    ((vl-catch-all-error-p tb)
     (princ (strcat "\nLAZBUTTON error: " (vl-catch-all-error-message tb))))
    (tb
     (vl-catch-all-apply 'vla-put-visible (list tb :vlax-true))
     (princ (strcat "\nLazPanel button is on screen - drag it anywhere,"
                    " dock it, click it to open the panel.")))
    (t
     (princ "\nLAZBUTTON: the menu API is unavailable - type LAZPANEL instead.")))
  (if lzd:end (lzd:end "LAZBUTTON"))
  (princ))

(defun c:LAZICON ( / *error* paths tb btn r w)
  ;; Nothing to put back -- this command opens no undo group and
  ;; changes no system variable -- but a failure still has to be SAID,
  ;; and said to LAZDIAG, or it is the one command in the build whose
  ;; bugs arrive as a bare AutoCAD message with no report behind them.
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZICON error: " msg)))
    (if lzd:report (lzd:report "LAZICON" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZICON" *lazpanel-version*))
  ;; The icon path is best effort and fails silently on purpose: a
  ;; missing picture must never stop the panel working.  Silence is the
  ;; right default and a poor answer to "why is my button blank", so
  ;; this walks the same steps out loud.
  (princ "\nLAZICON: where the button's picture comes from.")
  (princ (strcat "\n  support    : "
                 (cond ((lzp:support-dir))
                       (t "(could not read the support path)"))))
  (princ (strcat "\n  TEMPPREFIX : "
                 (if (= (type (getvar "TEMPPREFIX")) 'STR)
                     (getvar "TEMPPREFIX") "(not a string)")))
  ;; which grey went behind the hexagon, and why.  A .bmp has no
  ;; transparency, so this square is painted and the wrong one shows.
  (princ (strcat "\n  theme      : "
                 (cond ((eq (lzp:ui) 'light) "light - icon ground 240 240 240")
                       ((eq (lzp:ui) 'dark)  "dark - icon ground 54 54 54")
                       (t "cannot tell - icon ground 54 54 54, as it always was"))
                 (if (and (getenv "CalofinTheme")
                          (/= (getenv "CalofinTheme") ""))
                     (strcat "  (CalofinTheme says "
                             (getenv "CalofinTheme") ")")
                     "  (COLORTHEME; CALSET overrides it)")))
  (setq paths (lzp:write-bmps))
  (cond
    (paths
     (princ (strcat (if lzp:*iconwrote* "\n  written to : " "\n  on disk at : ")
                    (if lzp:*icondir* lzp:*icondir* "?")))
     (princ (strcat "\n  route      : "
                    (if lzp:*iconroute* lzp:*iconroute* "?")
                    "  (" (if lzp:*icontype* lzp:*icontype* "?") ")"))
     (princ (strcat "\n  handed on  : " (car paths)
                    (if (= lzp:*iconref* "name")
                        "  (a name the support path resolves)"
                        "  (a full path - the fallback)")))
     ;; the CUI's own test, run here: a bitmap is resolved by findfile
     ;; along the support path, and a name findfile cannot resolve is
     ;; exactly the "?" placeholder on the button
     (princ (strcat "\n  findfile   : "
                    (cond ((findfile (car paths)))
                          (t "CANNOT RESOLVE - this is the ? placeholder"))))
     (cond
       ((not (setq tb (vl-catch-all-apply 'lzp:toolbar-find nil)))
        (princ "\n  toolbar    : not on screen - type LAZBUTTON first."))
       ((vl-catch-all-error-p tb)
        (princ (strcat "\n  toolbar    : " (vl-catch-all-error-message tb))))
       (t
        (setq btn (vl-catch-all-apply 'vla-item (list tb 0)))
        (cond
          ((vl-catch-all-error-p btn)
           (princ (strcat "\n  button     : "
                          (vl-catch-all-error-message btn))))
          (t
           (setq r (vl-catch-all-apply
                     'vla-setbitmaps
                     (list btn (car paths) (cadr paths))))
           (princ (strcat "\n  SetBitmaps : "
                          (if (vl-catch-all-error-p r)
                              (vl-catch-all-error-message r)
                              "accepted - the button should show it now"))))))))
    (t
     ;; the failure branch has to say as much as the success one, or
     ;; the next report leaves the same two questions open: which route
     ;; produced the array, and which COM call refused it
     (princ (strcat "\n  array      : "
                    (if lzp:*icontype* lzp:*icontype* "none was made")))
     (princ (strcat "\n  died at    : "
                    (if lzp:*iconstep* lzp:*iconstep* "an unnamed step")))
     ;; the MSXML route failing silently is what cost two rounds of
     ;; this; every ProgID now says what it said
     (if lzp:*msxmlwhy*
       (progn
         (princ "\n  MSXML      : every version refused it --")
         (foreach w (reverse lzp:*msxmlwhy*)
           (princ (strcat "\n               " w))))
       (princ "\n  MSXML      : carried it, so the array is not the story"))
     (princ (strcat "\n  written    : NO - "
                    (if lzp:*iconerr* lzp:*iconerr* "no reason recorded")))))
  (if lzd:end (lzd:end "LAZICON"))
  (princ))

;;; -------------------- the two front-desk commands ---------------------
;;  CALHELP and CALSET are machinery rather than drafting tools, which
;;  is why they are here and not files of their own: this is where the
;;  captions live, and where calofin's profile settings were already
;;  being read and written (lzp:*poskey*, lzp:*pinkey*).  Both are in
;;  NAMED_SATELLITES in tools/callib.py, so neither asks for a panel
;;  button it has no use for.

;; What a command IS, at the command line: its caption and its
;; one-sentence blurb, both.  They have been here all along and the
;; only way to read one was to open the panel and find the page the
;; tool was filed on -- which is the same complaint the Find page
;; answered inside the dialog, unanswered outside it.  The search
;; behind it is lzp:matches, so a keyword nobody would guess from the
;; name finds the tool here exactly as it does on the Find page.
;; Enter lists the lot.
(defun c:CALHELP ( / *error* s hits n)
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCALHELP error: " msg)))
    (if lzd:report (lzd:report "CALHELP" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CALHELP" *lazpanel-version*))
  (setq s (getstring T "\nCommand, or any part of one <Enter = all>: "))
  (if lzd:ask (lzd:ask "Command, or any part of one" s) s)
  ;; lzp:visible, not lzp:commands: a tool put out of sight is out of
  ;; sight here too, the same rule Find already runs by (lzp:matches).
  (setq hits (if (= s "") (lzp:visible) (lzp:matches s)))
  (cond
    ((null hits)
     (princ (strcat "\nNothing here matches \"" s "\".  CALHELP on its"
                    " own lists every tool.")))
    (t
     (princ (strcat "\n" (itoa (length hits)) " tool"
                    (if (= (length hits) 1) "" "s")
                    (if (= s "") "" (strcat " matching \"" s "\""))
                    " -- a name in brackets is not loaded in this"
                    " session:"))
     (foreach n hits
       (princ (strcat "\n  " (if (lzp:has n) (strcat n) (strcat "(" n ")"))
                      "  " (lzp:caption n) "  -  " (lzp:blurb n))))))
  (if lzd:end (lzd:end "CALHELP"))
  (princ))

;; The settings calofin keeps in the AutoCAD PROFILE, which is the one
;; place a setting survives a rebuild: releases/ and LAZPASS.lsp are
;; generated, so a number edited into either is gone at the next
;; regeneration.  Each row is (key default what-it-does).
(setq lzp:*settings*
  '(("CalofinTheme"
     "auto"
     "dark / light / auto.  Which way the ink is picked: auto measures the drawing's background and AutoCAD's theme, and the other two say so outright when a measurement comes out wrong")
    ("CalofinErrorDir"
     ""
     "the folder LAZDIAG writes its error report to.  Empty = the candidate walk, which starts at Downloads")
    ("StockCover_Folder"
     ""
     "the folder STOCKCOVER reads its stock drawings from -- the key STOCKCOVER-CFG writes when you browse to one.  Empty = the setting at the top of STOCKCOVER.lsp")))

;; The eight ITEM-TYPE roles cal:ink resolves for COVERCHECK, DIMCHECK
;; and LINFINCHECK -- generalized off the six colours plus the two
;; layer colours those three tools used to carry as separate hardcoded
;; copies.  Keyed by the Itemcolors keyword -> the role cal:ink takes,
;; which is also the CalofinInk-<ROLE> profile key (uppercased) an
;; override lives under.  One list so Itemcolors and lzp:setshow read
;; the same roster instead of two that can drift apart.
(setq lzp:*inkroles*
  '(("Flag"   . "flag")
    ("Arc"    . "arc")
    ("Olap"   . "olap")
    ("Orig"   . "orig")
    ("Sugg"   . "sugg")
    ("Point"  . "point")
    ("Constr" . "constr")
    ("Report" . "report")))

(defun lzp:setshow ( / r v)
  (princ "\ncalofin settings, as this session reads them:")
  (foreach r lzp:*settings*
    (setq v (getenv (car r)))
    (princ (strcat "\n  " (car r)
                   "\n      now: " (if (and v (/= v "")) v
                                       (strcat "(unset -- " (cadr r) ")"))
                   "\n      " (caddr r))))
  (princ (strcat "\n  Item colours (CALSET Itemcolors; CalofinInk-<ROLE> in"
                 "\n      the profile) -- COVERCHECK/DIMCHECK/LINFINCHECK's"
                 "\n      flag/arc/olap/orig/sugg/point/constr/report, each"
                 "\n      auto (the shared table in CALOFIN-LIB.lsp's"
                 "\n      cal:ink) unless overridden below:"))
  (foreach r lzp:*inkroles*
    (setq v (getenv (strcat "CalofinInk-" (strcase (cdr r)))))
    (princ (strcat "\n      " (car r) ": "
                   (if (and v (/= v "")) (strcat "ACI " v) "(auto)"))))
  ;; Not a row of lzp:*settings*: a hidden list is not one scalar in
  ;; the profile, it is a name list in the registry, the same shape
  ;; Pins and Recent already are -- so it gets its own line rather than
  ;; a table row that would have nowhere to put a value.
  (princ (strcat "\n  Hidden tools"
                 "\n      now: " (itoa (length lzp:*hidden*))
                 " of " (itoa (length (lzp:commands)))
                 " off the panel -- a hidden tool still runs typed, it"
                 " simply stops being shown"
                 "\n      LAZHIDE picks which, or Hidden below"))
  (princ))

(defun c:CALSET ( / *error* pick key v role)
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCALSET error: " msg)))
    (if lzd:report (lzd:report "CALSET" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "CALSET" *lazpanel-version*))
  (lzp:hidden-read)
  (lzp:setshow)
  (initget "Theme Errordir Stockdir Itemcolors Hidden Quit")
  (setq pick (getkword "\nChange which? [Theme/Errordir/Stockdir/Itemcolors/Hidden/Quit] <Quit>: "))
  (if lzd:ask (lzd:ask "Change which?" pick) pick)
  (setq key (cond ((= pick "Theme") "CalofinTheme")
                  ((= pick "Errordir") "CalofinErrorDir")
                  ((= pick "Stockdir") "StockCover_Folder")))
  (cond
    ((= pick "Itemcolors")
     ;; a second keyword picks WHICH of the eight roles, then the same
     ;; getstring/Back/"." shape as Errordir and Stockdir below sets its
     ;; CalofinInk-<ROLE> override -- Undo is accepted everywhere Back
     ;; is, unlisted (STANDARDS 1)
     (initget "Flag Arc Olap Orig Sugg Point Constr Report Back Undo")
     (setq role (getkword
                  "\nWhich item colour [Flag/Arc/Olap/Orig/Sugg/Point/Constr/Report/Back] <Back>: "))
     (if lzd:ask (lzd:ask "Which item colour?" role) role)
     (setq role (if role role "Back"))
     (cond
       ((member role '("Back" "Undo")) (c:CALSET))
       (t
        (setq key (strcat "CalofinInk-" (strcase (cdr (assoc role lzp:*inkroles*)))))
        (setq v (getstring T (strcat "\n" role
                                     " ACI colour (a number, Back to leave it, "
                                     "or . for Auto): ")))
        (if lzd:ask (lzd:ask (strcat role " colour") v) v)
        (cond
          ((member (strcase v) '("B" "BACK" "U" "UNDO")) (c:CALSET))
          ((= v "") (princ "\nUnchanged."))
          ((= v ".")
           (setenv key "")
           (princ (strcat "\n" role " colour cleared -- back to Auto.")))
          ((= (atoi v) 0)
           (princ "\nNot a colour number -- unchanged."))
          (t
           (setenv key (itoa (atoi v)))
           (princ (strcat "\n" role " colour is now ACI " (itoa (atoi v))
                          ".  COVERCHECK, DIMCHECK and LINFINCHECK read it"
                          " on their next run.")))))))
    ;; routes straight to LAZHIDE's own dialog and comes back to this
    ;; prompt -- the same way Back re-enters CALSET below
    ((= pick "Hidden") (c:LAZHIDE) (c:CALSET))
    ((null key) (princ "\nNothing changed."))
    ((= key "CalofinTheme")
     ;; Undo is accepted everywhere Back is, unlisted (STANDARDS 1)
     (initget "Dark Light Auto Back Undo")
     (setq v (getkword "\nTheme [Dark/Light/Auto/Back] <Auto>: "))
     (if lzd:ask (lzd:ask "Theme" v) v)
     (cond
       ((member v '("Back" "Undo")) (c:CALSET))
       (t (setq v (if v (strcase v) "AUTO"))
          (setenv "CalofinTheme" v)
          ;; ...and beside the pins, where the VB palette reads it
          ;; (ui/calofin_net/PaletteTheme.vb).  The profile is what the
          ;; Lisp side reads and the registry is what the palette can
          ;; reach, and a drafter who has said which way their screen
          ;; reads has said it to both surfaces -- the same bargain the
          ;; pinned row already strikes.  Auto is written as empty:
          ;; the palette's own probe is what "auto" means there.
          ;;
          ;; Read from V and not back out of getenv -- a strcase on the
          ;; nil a failed setenv would leave is an error thrown from
          ;; inside the line that reports success.
          (vl-catch-all-apply
            'vl-registry-write
            (list lzp:*pinkey* "Theme" (if (= v "AUTO") "" v)))
          (princ (strcat "\nCalofinTheme is now " v
                         ".  Every tool reads it on the next colour it"
                         " picks; the toolbar icon takes it at the next"
                         " LAZBUTTON or LAZICON, and the VB palette at"
                         " its next chart.")))))
    (t
     (setq v (getstring T (strcat "\n" key
                                  " (a folder, Back to leave it, "
                                  "or . to clear it): ")))
     (if lzd:ask (lzd:ask key v) v)
     (cond
       ((member (strcase v) '("B" "BACK" "U" "UNDO")) (c:CALSET))
       ((= v "") (princ "\nUnchanged."))
       ((= v ".")
        (setenv key "")
        (princ (strcat "\n" key " cleared.")))
       (t (setenv key v)
          (princ (strcat "\n" key " is now " v "."))))))
  (if lzd:end (lzd:end "CALSET"))
  (princ))

;;; -------------------- the settings dialog -----------------------------
;;  CALSET asks these same questions one prompt at a time.  This is the
;;  panel's Options button, and it is to CALSET what LAZFORM is to
;;  POOL: every answer in front of you at once, each box filled in from
;;  what the profile already holds, rather than an interview you have
;;  to finish to change one thing.
;;
;;  NOTHING IN THIS DIALOG IS WRITTEN UNTIL OK.  What you type lands in
;;  lzp:*setvals*, an alist keyed by the PROFILE KEY itself, and
;;  lzp:set-write is the single place that reaches setenv.  Cancel drops
;;  the store on the floor.  The Hidden... button closes this dialog,
;;  runs the hide editor on the same loaded handle and comes back --
;;  which is why the store is a global and not a local: the reopen
;;  repaints every box from it, so a hop through the checklist does not
;;  cost you the colour you had just typed.
;;
;;  THE HIDDEN LIST IS THE ONE EXCEPTION, and deliberately: it is its
;;  own dialog with its own OK and Cancel, and it commits there, so
;;  Cancel here does NOT put back a tool you hid through it.  That is
;;  the bargain Pin... already strikes from the panel -- a sub-dialog's
;;  OK is its own transaction -- and the alternative, silently undoing
;;  a checklist the drafter had just accepted, is the more surprising
;;  of the two.
;;
;;  A colour box holds an ACI number or nothing at all, and while one
;;  holds anything else the state line names it and OK stays greyed --
;;  the same bargain LAZFORM's Insert strikes, for the same reason: a
;;  value nothing can read must not be stored and then silently
;;  ignored by the tool that goes looking for it.

;; What the Theme dropdown offers -> what is stored under CalofinTheme.
;; The order is the list order, and the INDEX is what DCL hands back.
(setq lzp:*themes*
  '(("Auto"  . "AUTO")
    ("Dark"  . "DARK")
    ("Light" . "LIGHT")))

(setq lzp:*setvals* nil)          ; the pending answers, until OK

;; The profile key one item-colour role's override lives under.
(defun lzp:inkkey (r) (strcat "CalofinInk-" (strcase (cdr r))))

(defun lzp:set-get (key / p)
  (if (setq p (assoc key lzp:*setvals*)) (cdr p) ""))

(defun lzp:set-put (key v)
  (setq lzp:*setvals*
        (cons (cons key v)
              (vl-remove (assoc key lzp:*setvals*) lzp:*setvals*)))
  (princ))

;; mode_tile that cannot throw, for the same reason lzp:settile exists:
;; the state line is recomputed from a tile callback, where the tiles
;; are there, and from the tests, where they are not.
(defun lzp:setmode (key m)
  (vl-catch-all-apply 'mode_tile (list key m)))

(defun lzp:digit-p (c)
  (if (member c '("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")) t nil))

;; T when S reads as an ACI colour, 1 to 255.  Spelled out rather than
;; handed to atoi alone: atoi answers 0 for "red" and reads "12x" as
;; 12, so a typo would be stored as a colour and drawn in.
(defun lzp:aci-p (s / i n ok)
  (setq n (strlen s) i 1 ok (> n 0))
  (while (and ok (<= i n))
    (if (not (lzp:digit-p (substr s i 1))) (setq ok nil))
    (setq i (1+ i)))
  (if (and ok (> (atoi s) 0) (< (atoi s) 256)) t nil))

;; The roles whose box holds something that is not a colour.  Empty is
;; not one of them: empty is how a role is put back to auto.
(defun lzp:set-badinks ( / r v out)
  (foreach r lzp:*inkroles*
    (setq v (lzp:set-get (lzp:inkkey r)))
    (if (and (/= v "") (not (lzp:aci-p v)))
      (setq out (cons (car r) out))))
  (reverse out))

(defun lzp:hiddenmsg ()
  (strcat (itoa (length lzp:*hidden*)) " of "
          (itoa (length (lzp:commands))) " tools hidden"))

;; The state line, and OK with it.  Called as each box is typed into,
;; so the refusal arrives while the box is still in front of you.
(defun lzp:set-state ( / bad msg b)
  (setq bad (lzp:set-badinks) msg "")
  (foreach b bad (setq msg (strcat msg (if (= msg "") "" ", ") b)))
  (lzp:settile "state"
    (if bad
      (strcat "Not a colour number: " msg
              " -- type 1 to 255, or empty for auto")
      "OK writes these to your AutoCAD profile, where they survive a rebuild"))
  (lzp:setmode "accept" (if bad 1 0))
  (princ))

;; Which entry of lzp:*themes* the profile is on now, as the index DCL
;; wants.  An unset or unreadable value is Auto, which is index 0.
(defun lzp:theme-index ( / v i out r)
  (setq v (lzp:set-get "CalofinTheme") out 0 i 0)
  (foreach r lzp:*themes*
    (if (= (cdr r) v) (setq out i))
    (setq i (1+ i)))
  out)

;; The dropdown firing.  $value is an INDEX, not the word.
(defun lzp:set-theme (v / r)
  (if (setq r (nth (atoi v) lzp:*themes*))
    (lzp:set-put "CalofinTheme" (cdr r)))
  (princ))

;; A profile value, TRIMMED.  Every other reader in this tree trims
;; before it decides anything -- lzp:ui a few hundred lines up says so
;; in a comment ("\" dark \" typed into the profile meaning nothing at
;; all would be a silent no-op to stare at"), and cal:themeset, the
;; fourteen tool copies and the VB palette all do the same.  A dialog
;; that read the raw string would SHOW Auto for a profile holding
;; " dark ", which every tool is meanwhile drawing dark for, and then
;; write that lie back over it the first time OK was pressed.
(defun lzp:profread (key / v)
  (setq v (getenv key))
  (if v (vl-string-trim " \t" v) ""))

;; Fill the store from the profile.  Every key the dialog shows gets a
;; row, so a box is never painted from a nil.
(defun lzp:set-read ( / r v)
  (setq lzp:*setvals* nil)
  (setq v (strcase (lzp:profread "CalofinTheme")))
  (lzp:set-put "CalofinTheme"
               (if (member v '("DARK" "LIGHT")) v "AUTO"))
  (foreach r '("CalofinErrorDir" "StockCover_Folder")
    (lzp:set-put r (lzp:profread r)))
  (foreach r lzp:*inkroles*
    (lzp:set-put (lzp:inkkey r) (lzp:profread (lzp:inkkey r))))
  lzp:*setvals*)

;; The one place that writes.
(defun lzp:set-write ( / r v)
  (setq v (lzp:set-get "CalofinTheme"))
  ;; EMPTY is what every reader takes for auto -- lzp:ui, cal:themeset
  ;; and the palette all treat an unset or empty value as "measure it"
  ;; -- so writing the word AUTO would leave LAZICON and lzp:setshow
  ;; reporting an override the drafter never set.  The registry mirror
  ;; below already wrote it this way; now the profile agrees with it.
  (setenv "CalofinTheme" (if (= v "AUTO") "" v))
  ;; ...and beside the pins, where the VB palette reads it
  ;; (ui/calofin_net/PaletteTheme.vb) -- the same bargain CALSET's own
  ;; Theme branch strikes.
  (vl-catch-all-apply
    'vl-registry-write
    (list lzp:*pinkey* "Theme" (if (= v "AUTO") "" v)))
  (foreach r '("CalofinErrorDir" "StockCover_Folder")
    (setenv r (lzp:set-get r)))
  ;; A box that does not read as a colour is LEFT ALONE rather than
  ;; cleared.  Empty still clears -- that is how a role goes back to
  ;; auto -- but a typo must not: erasing an override the drafter
  ;; already had is the one outcome worse than ignoring what they just
  ;; typed, and lzp:set-ok is not the only way this can be reached.
  (foreach r lzp:*inkroles*
    (setq v (lzp:set-get (lzp:inkkey r)))
    (if (or (= v "") (lzp:aci-p v)) (setenv (lzp:inkkey r) v)))
  lzp:*setvals*)

;; OK, GUARDED.  Greying the button is not a hard stop and this file
;; already knows it: lzp:dcl-find's own comment says "DCL fires an edit
;; box's action BEFORE the default button's", so a click on OK with a
;; typo still in the box fires the box (which greys OK) and then lands
;; anyway.  LAZFORM learned this at lzf:insert -- "a guard that depends
;; on a tile really being un-clickable is a guard that hands POOL a
;; dropped box the day it is not" -- and this is the same guard: re-ask,
;; and stay open rather than write.
(defun lzp:set-ok ()
  (if (lzp:set-badinks)
    (lzp:set-state)
    (done_dialog 1))
  (princ))

;; The dialog.  The dropdown is emitted EMPTY -- DCL has no way to
;; write a list into a popup_list from the file, so it is filled with
;; start_list once the dialog is up, exactly as LAZFORM fills its
;; corner dropdowns.
(defun lzp:dcl-set ( / out col r)
  (setq out (list "lazpanel_set : dialog {"
                  "  label = \"LazPanel  -  settings\";"
                  "  : boxed_column {"
                  "    label = \"Ink\";"
                  (strcat "    : popup_list { key = \"set_theme\"; "
                          "label = \"Theme\"; edit_width = 10; }")
                  (strcat "    : text { label = \"auto measures the drawing's"
                          " background and AutoCAD's own theme\"; }")
                  "  }"
                  "  : boxed_row {"
                  (strcat "    label = \"Item colours - COVERCHECK, DIMCHECK"
                          " and LINFINCHECK; empty is auto\";")))
  ;; three to a column, so the box is a block rather than one tall stack
  (foreach col (lzp:chunk lzp:*inkroles* 3)
    (setq out (append out (list "    : column {")))
    (foreach r col
      (setq out (append out
        (list (strcat "      : edit_box { key = \"ink_" (cdr r)
                      "\"; label = \"" (car r)
                      "\"; edit_width = 5; fixed_width = true; }")))))
    (setq out (append out (list "    }"))))
  (append out
    (list "  }"
          "  : boxed_column {"
          "    label = \"Folders - empty means the tool's own default\";"
          (strcat "    : edit_box { key = \"set_errdir\"; "
                  "label = \"Error reports\"; edit_width = 40; }")
          (strcat "    : edit_box { key = \"set_stockdir\"; "
                  "label = \"Stock covers \"; edit_width = 40; }")
          "  }"
          "  : boxed_row {"
          "    label = \"Panel\";"
          "    : text { key = \"hiddenmsg\"; width = 32; }"
          (strcat "    : button { label = \"Hidden...\"; "
                  "key = \"set_hidden\"; fixed_width = true; }")
          (strcat "    : button { label = \"Names...\"; "
                  "key = \"set_names\"; fixed_width = true; }")
          "  }"
          ;; wide enough for the longest sentence lzp:set-state can put
          ;; in it: width is a MINIMUM in DCL, but a text tile with no
          ;; label and no value has only this to size itself from, and
          ;; the message that explains a greyed OK is the one message
          ;; that must not be the one cut off
          "  : text { key = \"state\"; width = 110; }"
          "  spacer;"
          "  : row {"
          "    alignment = centered;"
          (strcat "    : button { label = \"OK\"; key = \"accept\"; "
                  "is_default = true; fixed_width = true; }")
          (strcat "    : button { label = \"Cancel\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; }")
          "  }"
          "}")))

;; Open it, wire it, and keep reopening while the Hidden... button is
;; the way out.  Answers "ok" when OK was pressed and nil otherwise, so
;; the caller is what decides to write.
(defun lzp:set-edit (dcl / rc r done out)
  (while (not done)
    (cond
      ((not (new_dialog "lazpanel_set" dcl)) (setq done t))
      (t
       ;; the dropdown's list, which is only legal with the dialog up
       (start_list "set_theme")
       (foreach r lzp:*themes* (add_list (car r)))
       (end_list)
       (set_tile "set_theme" (itoa (lzp:theme-index)))
       (action_tile "set_theme" "(lzp:set-theme $value)")
       (foreach r lzp:*inkroles*
         (set_tile (strcat "ink_" (cdr r)) (lzp:set-get (lzp:inkkey r)))
         (action_tile (strcat "ink_" (cdr r))
           (strcat "(lzp:set-put \"" (lzp:inkkey r) "\" $value)"
                   " (lzp:set-state)")))
       (set_tile "set_errdir" (lzp:set-get "CalofinErrorDir"))
       (action_tile "set_errdir" "(lzp:set-put \"CalofinErrorDir\" $value)")
       (set_tile "set_stockdir" (lzp:set-get "StockCover_Folder"))
       (action_tile "set_stockdir"
                    "(lzp:set-put \"StockCover_Folder\" $value)")
       (set_tile "hiddenmsg" (lzp:hiddenmsg))
       (action_tile "set_hidden" "(done_dialog 5)")
       (action_tile "set_names" "(done_dialog 6)")
       (action_tile "accept" "(lzp:set-ok)")
       (action_tile "cancel" "(done_dialog 0)")
       (lzp:set-state)
       (setq rc (start_dialog))
       (cond
         ;; the hide editor, then round again: this dialog repaints
         ;; itself from the store, so nothing typed is lost to the trip
         ((= rc 5) (lzp:hide-edit dcl))
         ;; ...and the names editor the same way, on the same handle
         ((= rc 6) (lzp:name-edit dcl))
         ((= rc 1) (setq done t out "ok"))
         (t (setq done t))))))
  out)

(defun c:LAZSET ( / *error* f dcl ok)
  ;; an error inside a tile callback used to leak the dialog handle
  ;; and the temp .dcl -- the same fix c:LAZPIN and c:LAZHIDE carry
  (defun *error* (msg)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (if f (vl-file-delete f))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZSET error: " msg)))
    (if lzd:report (lzd:report "LAZSET" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZSET" *lazpanel-version*))
  (lzp:pins-read)
  (lzp:recent-read)
  (lzp:hidden-read)
  (lzp:set-read)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZSET error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZSET error: could not load the dialog file.")
     (vl-file-delete f))
    (t
     (setq ok (lzp:set-edit dcl))
     (unload_dialog dcl)
     (vl-file-delete f)
     (cond
       (ok
        (lzp:set-write)
        (princ (strcat "\nLAZPANEL: settings saved.  Every tool reads the"
                       " theme and the item colours on the next colour it"
                       " picks; the toolbar icon takes the theme at the next"
                       " LAZBUTTON or LAZICON, and the VB palette at its"
                       " next chart.")))
       (t (princ "\nLAZPANEL: settings unchanged.")))))
  (if lzd:end (lzd:end "LAZSET"))
  (princ))

;;; -------------------- names of your own --------------------------------
;;  Two things a drafter can rename, per machine: the NAME THEY TYPE to
;;  summon a tool, and the WORDS ITS BUTTON SAYS.  Neither touches the
;;  shipped tables -- lzp:*captions* stays the file's single truth, and
;;  no alias is ever written into a .lsp -- so `make check` still reads
;;  the same tree it always did.  This is a layer over the top of it.
;;
;;  AN ALIAS IS A WRAPPER DEFUN, which is the shape this tree already
;;  uses for the one alias it ships: DCE is (defun c:DCE () (c:DIMCONTEND))
;;  and nothing else.  Built at run time it is the same form, assembled
;;  as DATA rather than as source text -- (list 'defun sym nil (list
;;  target)) -- because a string spliced from what the drafter typed
;;  would go through read, and a malformed one throws from inside a
;;  file load, where there is nothing to catch it.  The wrapper
;;  resolves its target at CALL time, so an alias can be applied before
;;  the tool it names is loaded, which the standalone tier gives no
;;  guarantee about.
;;
;;  WHAT IS REFUSED, AND WHY EACH ONE MATTERS:
;;    - a name that is not letters and digits, or does not start with a
;;      letter, or is over 12 characters.  (read "c:MY TOOL") answers
;;      c:my and (read "c:") answers c:, both silently, so the check
;;      happens BEFORE anything reaches read and is a whitelist.
;;    - a name the session already answers to.  This is the dangerous
;;      one: (defun c:CHECK () ...) would retarget check_drawing.lsp's
;;      CHECK for the whole session, and DIMARCCHECK -- which is
;;      (c:CHECK) -- with it.  lzp:has cannot see the difference, so the
;;      button would stay lit while running the wrong tool.
;;    - a caption carrying ";" or "=", which are the store's own
;;      separators, or a double quote, which lzp:dcl-one pastes straight
;;      into DCL and which would make every page of the panel
;;      unloadable.
;;    - a caption over lzp:*capmax* characters.  tools/check_dcl.py
;;      measures the SHIPPED tables and structurally cannot see a
;;      drafter's override, so the cap is the only thing standing
;;      between a long rename and a page that will not open.
;;
;;  Removing an alias stops it being remembered, but the name it
;;  already defined answers until the drawing is closed: AutoLISP has
;;  no way to take a defun back, and pretending otherwise would be the
;;  lie.  The state line says so.

;; Records joined with ";" as Pins, Recent and Hidden already are, but
;; a record here is a PAIR -- NAME=VALUE.  Both separators are single
;; characters because lzp:split compares one character at a time, which
;; is also exactly why neither may appear in a value.
(defun lzp:kv-read (value / s out e i)
  (setq s (vl-catch-all-apply 'vl-registry-read (list lzp:*pinkey* value)))
  (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR) (/= s ""))
    (foreach e (lzp:split s ";")
      (if (and (setq i (vl-string-search "=" e)) (> i 0))
        (setq out (cons (cons (substr e 1 i) (substr e (+ i 2))) out)))))
  ;; a name the roster no longer carries is dropped on read, exactly as
  ;; a stale pin is: what is stored must never put a dead row on screen
  (vl-remove-if-not '(lambda (p) (member (car p) (lzp:commands)))
                    (reverse out)))

(defun lzp:kv-write (value map / s p)
  (setq s "")
  (foreach p map
    (if (/= (cdr p) "")
      (setq s (strcat s (if (= s "") "" ";") (car p) "=" (cdr p)))))
  (vl-catch-all-apply 'vl-registry-write (list lzp:*pinkey* value s))
  map)

(defun lzp:names-read ()
  (setq lzp:*aliases* (lzp:kv-read lzp:*aliasval*)
        lzp:*capsof*  (lzp:kv-read lzp:*capval*))
  lzp:*aliases*)

(defun lzp:letter-p (c)
  (if (vl-string-search c "ABCDEFGHIJKLMNOPQRSTUVWXYZ") t nil))

;; Letters and digits, first one a letter, 1 to 12 characters.
(defun lzp:alias-shape-p (s / i n c ok)
  (setq s (strcase s) n (strlen s) i 1 ok (and (> n 0) (<= n 12)))
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (if (not (or (lzp:letter-p c) (lzp:digit-p c))) (setq ok nil))
    (if (and (= i 1) (not (lzp:letter-p c))) (setq ok nil))
    (setq i (1+ i)))
  ok)

;; Does this session already answer to NAME?  The names-list form of
;; atoms-family answers nil in the slot for a name the session lacks --
;; and the LIST it returns is truthy either way, so the car is the
;; question and the bare call is not.
(defun lzp:alias-taken-p (name)
  (if (car (atoms-family 1 (list (strcase (strcat "C:" name))))) t nil))

;; Why this alias cannot be used, as words, or nil when it can.  TOOL is
;; the command it would summon; the alias it ALREADY had is allowed
;; through, or re-opening the editor would refuse what it just showed.
(defun lzp:alias-why (name tool / p)
  (cond
    ((= name "") nil)
    ((not (lzp:alias-shape-p name))
     "a name is letters and digits, starts with a letter, up to 12")
    ((setq p (car (vl-remove-if-not
                    '(lambda (q) (and (/= (car q) tool)
                                      (= (strcase (cdr q)) (strcase name))))
                    lzp:*aliases*)))
     (strcat "that name is already yours for " (car p)))
    ((and (lzp:alias-taken-p name)
          (/= (strcase name) (strcase (lzp:alias-was tool))))
     (strcat name " already runs something in this session"))))

(defun lzp:alias-was (tool)
  (lzp:pairval tool lzp:*aliasat*))

;; Why this caption cannot be used, as words, or nil when it can.
(defun lzp:cap-why (s)
  (cond
    ((> (strlen s) lzp:*capmax*)
     (strcat "keep it to " (itoa lzp:*capmax*) " characters or the page stops opening"))
    ((or (vl-string-search ";" s) (vl-string-search "=" s))
     "; and = are how the list itself is stored, so a caption cannot hold one")
    ((vl-string-search "\"" s)
     "a double quote would break the panel's own dialog file")))

;; Define one wrapper, or answer nil having done nothing.
(defun lzp:alias-make (name tool)
  (if (and (lzp:alias-shape-p name)
           (not (lzp:alias-taken-p name))
           (member tool (lzp:commands)))
    (progn
      (eval (list 'defun (read (strcat "c:" (strcase name))) nil
                  (list (read (strcat "c:" tool)))))
      t)))

(defun lzp:aliases-apply ( / p n)
  (setq n 0)
  (foreach p lzp:*aliases*
    (if (lzp:alias-make (cdr p) (car p)) (setq n (1+ n))))
  n)

(defun lzp:names-write ()
  (lzp:kv-write lzp:*aliasval* lzp:*aliases*)
  (lzp:kv-write lzp:*capval* lzp:*capsof*)
  (lzp:aliases-apply))

;; One row.  Not padded into columns: whether the dialog font is
;; fixed-pitch is exactly what LAZASCII exists to ask, so nothing here
;; may assume two rows line up.
(defun lzp:namerow (n / a)
  (setq a (lzp:pairval n lzp:*aliases*))
  (strcat n
          (if (/= a "") (strcat "  (type " a ")") "")
          "  -  " (lzp:caption n)))

;; A map's value, or "" when it has none.  (cdr (assoc ...)) answers nil
;; for a tool nobody has renamed, and nil is what strcase and strlen
;; throw on -- so every read of these two maps comes through here.
(defun lzp:pairval (key map / p)
  (if (setq p (assoc key map)) (cdr p) ""))

(defun lzp:put-pair (key v map)
  (cons (cons key v) (vl-remove (assoc key map) map)))

(defun lzp:name-alias-put (v)
  (if lzp:*namesel*
    (setq lzp:*aliases*
          (lzp:put-pair lzp:*namesel* (strcase v) lzp:*aliases*)))
  (lzp:namerefill)
  (lzp:name-state)
  (princ))

(defun lzp:name-cap-put (v)
  (if lzp:*namesel*
    (setq lzp:*capsof* (lzp:put-pair lzp:*namesel* v lzp:*capsof*)))
  (lzp:namerefill)
  (lzp:name-state)
  (princ))

;; What is wrong with the pair in front of the drafter, or nil.
(defun lzp:name-why ( / a)
  (if lzp:*namesel*
    (cond ((setq a (lzp:alias-why (lzp:pairval lzp:*namesel* lzp:*aliases*)
                                  lzp:*namesel*))
           a)
          (t (lzp:cap-why (lzp:pairval lzp:*namesel* lzp:*capsof*))))))

(defun lzp:name-state ( / why)
  (setq why (lzp:name-why))
  (lzp:settile "namestate"
    (cond (why why)
          ((not lzp:*namesel*) "Pick a tool to give it names of your own")
          (t (strcat lzp:*namesel*
                     " - OK keeps these; a name you remove still answers"
                     " until this drawing is closed"))))
  (lzp:setmode "accept" (if why 1 0))
  (princ))

;; Rebuild the list and put the selection back.  A row's words change
;; as the boxes are typed into, and a list that went on showing the old
;; ones would be the only part of the dialog telling a different story.
(defun lzp:namerefill ( / n i sel)
  (setq lzp:*names* (lzp:commands) i 0 sel 0)
  (foreach n lzp:*names*
    (if (= n lzp:*namesel*) (setq sel i))
    (setq i (1+ i)))
  ;; under a catch because this runs from a tile callback, where the
  ;; list is there, and from the tests, where it is not: start_list
  ;; outside a dialog is an error and not a no-op
  (vl-catch-all-apply
    '(lambda ()
       (start_list "names")
       (foreach n lzp:*names* (add_list (lzp:namerow n)))
       (end_list)
       (if lzp:*names* (set_tile "names" (itoa sel))))
    nil)
  lzp:*names*)

(defun lzp:namepick (v)
  (setq lzp:*namesel* (nth (atoi v) lzp:*names*))
  (lzp:settile "name_alias" (lzp:pairval lzp:*namesel* lzp:*aliases*))
  (lzp:settile "name_cap" (lzp:pairval lzp:*namesel* lzp:*capsof*))
  (lzp:name-state)
  lzp:*namesel*)

;; OK, guarded the way lzp:set-ok is, and for the same reason: DCL fires
;; an edit box's action before the default button's, so the greying is
;; not a stop.
(defun lzp:name-ok ()
  (if (lzp:name-why)
    (lzp:name-state)
    (done_dialog 1))
  (princ))

(defun lzp:dcl-names ( / out)
  (setq out
    (list "lazpanel_names : dialog {"
          "  label = \"LazPanel  -  names of your own\";"
          (strcat "  : text { label = \"Pick a tool, then say what you want"
                  " to type and what you want the button to say.\"; }")
          "  : list_box { key = \"names\"; width = 58; height = 16; }"
          "  : boxed_column {"
          "    label = \"The tool you picked\";"
          (strcat "    : edit_box { key = \"name_alias\"; "
                  "label = \"Type this to run it\"; edit_width = 14; }")
          (strcat "    : edit_box { key = \"name_cap\"; "
                  "label = \"Button says        \"; edit_width = 40; }")
          (strcat "    : text { label = \"Leave a box empty to go back to"
                  " the name calofin ships.\"; }")
          "  }"
          "  : text { key = \"namestate\"; width = 110; }"
          "  spacer;"
          "  : row {"
          "    alignment = centered;"
          (strcat "    : button { label = \"OK\"; key = \"accept\"; "
                  "is_default = true; fixed_width = true; }")
          (strcat "    : button { label = \"Cancel\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; }")
          "  }"
          "}"))
  out)

;; Cancel re-reads the store rather than unwinding the edits one by
;; one, exactly as the pin and hide editors do: what is stored is the
;; truth, so going back to it is exact where unwinding is approximate.
(defun lzp:name-edit (dcl / rc)
  (cond
    ((not (new_dialog "lazpanel_names" dcl)) nil)
    (t
     (setq lzp:*aliasat* lzp:*aliases*
           lzp:*namesel* nil)
     (lzp:namerefill)
     (lzp:namepick "0")
     (action_tile "names" "(lzp:namepick $value)")
     (action_tile "name_alias" "(lzp:name-alias-put $value)")
     (action_tile "name_cap" "(lzp:name-cap-put $value)")
     (action_tile "accept" "(lzp:name-ok)")
     (action_tile "cancel" "(done_dialog 0)")
     (setq rc (start_dialog))
     (if (= rc 1) (lzp:names-write) (lzp:names-read))
     t)))

(defun c:LAZNAME ( / *error* f dcl)
  ;; an error inside a tile callback used to leak the dialog handle
  ;; and the temp .dcl -- the same fix c:LAZPIN and c:LAZHIDE carry
  (defun *error* (msg)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (if f (vl-file-delete f))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZNAME error: " msg)))
    (if lzd:report (lzd:report "LAZNAME" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZNAME" *lazpanel-version*))
  (lzp:pins-read)
  (lzp:recent-read)
  (lzp:hidden-read)
  (lzp:names-read)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZNAME error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZNAME error: could not load the dialog file.")
     (vl-file-delete f))
    (t
     (lzp:name-edit dcl)
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZPANEL: "
                    (itoa (length lzp:*aliases*)) " tool"
                    (if (= (length lzp:*aliases*) 1) "" "s")
                    " answer to a name of yours, "
                    (itoa (length lzp:*capsof*)) " renamed on the panel."))))
  (if lzd:end (lzd:end "LAZNAME"))
  (princ))

(defun c:LAZPANELVER ()
  (princ (strcat "\nLAZPANEL " *lazpanel-version* " (LAZPANEL.lsp) - "
                 (itoa (length (lzp:visible))) " tools on the panel across "
                 (itoa (length lzp:*groups*)) " pages, "
                 (itoa (length lzp:*pins*)) " pinned"
                 (if lzp:*hidden*
                   (strcat ", " (itoa (length lzp:*hidden*)) " hidden.")
                   ".")))
  (princ))

;; Once per AutoCAD SESSION, not once per drawing.  LISP globals are
;; per-document, so a Startup Suite runs this file again in every
;; drawing opened -- and the toolbar, its picture and the CUI walk that
;; finds it are all application-wide, so the second and every later
;; document had nothing to do but do it anyway.  The blackboard
;; (vl-bb-*) is the one namespace every document shares, so it carries
;; the "done" mark; LAZBUTTON still calls lzp:button-init unconditionally
;; for the drafter who closed the toolbar and wants it back.
(defun lzp:first-load-p ()
  (if (vl-bb-ref 'lzp:*button-done*)
      nil
      (progn (vl-bb-set 'lzp:*button-done* t) t)))

;; Put the button up as the file loads, quietly: in a session where
;; the COM menu API (or the blackboard) is missing the panel still
;; loads and LAZPANEL still runs -- the button is a convenience, never
;; a gate.
(vl-catch-all-apply
  '(lambda () (if (lzp:first-load-p) (lzp:button-init))) nil)
(vl-catch-all-apply 'lzp:pins-read nil)
;; The drafter's own names, and the wrappers that make them answer.
;; Per DOCUMENT, not per session: a defun lives in the drawing's own
;; namespace, so the blackboard's once-a-session mark is the wrong
;; instrument here and every drawing has to be told again.  Under
;; vl-catch-all-apply beside the rest: a file that throws as it loads
;; takes the panel and the toolbar with it.
(vl-catch-all-apply 'lzp:names-read nil)
(vl-catch-all-apply 'lzp:aliases-apply nil)

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nLAZPANEL " *lazpanel-version*
                 " loaded.  LAZPANEL opens the panel;"
                 " LAZBUTTON puts its button on screen;"
                 " LAZPIN edits the pinned row;"
                 " LAZHIDE picks which tools stay off it;"
                 " CALHELP says what a command does;"
                 " LAZSET is the settings dialog, CALSET the prompts;"
                 " LAZNAME gives a tool a name of your own.")))
(princ)
