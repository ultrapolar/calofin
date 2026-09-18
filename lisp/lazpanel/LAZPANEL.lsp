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
;;; Find also carries two buttons over whatever is highlighted: HOW IT
;;; WORKS prints the fuller step-by-step explanation behind the
;;; one-sentence blurb (lzp:*howto*, an OK-only alert so the dialog
;;; stays open), and TUTORIAL launches the command's interactive
;;; TUTORIAL* walkthrough where one exists (lzp:*tutorials* -- most
;;; commands have none, and the button says so instead of failing
;;; silently).  A walkthrough launched this way is quiet: it must not
;;; land in Recent the way running the tool itself would, since it is a
;;; satellite and not a drafting command on its own.
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

(setq *lazpanel-version* "v3.42")

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
;;;    lzp:*inkpresets* LAZSET's Item colours dropdown: a small, curated
;;;                     set of named colour families, each already
;;;                     mapped to an ACI number and an RGB target a
;;;                     typed hex code is matched against (lzp:aci-near)
;;;                     -- see the comment on the table itself for why
;;;                     it is not the full 255-colour AutoCAD palette

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

;; How many rows LAZTUNE's knob list shows at once.  A ceiling of the
;; same kind as lzp:*colbudget*: DCL does not scroll a dialog, only a
;; list box scrolls inside one, so this is what keeps the defaults
;; page under the screen with a tool of ninety knobs on it.  22 puts
;; it near 810px.
(setq lzp:*tunerows* 22)

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
    ("DRONOTE"          "Drone photo review note")
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
    ("SQUAREUP"         "Square up to the perimeter")
    ("STAIRDIM"         "Stair dims")
    ("STOCKCOVER"       "Stock cover placement")
    ("TYDRN"            "Text + point tidy-up")
    ("TYLERDRONESUITE"  "Drone suite: tidy, pad, CDIM")
    ("UPADOVER"         "Pads a run of wall")
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
    ("DRONOTE" "Places a canned drone-photo review note - diving board, hidden anchors or slide sketch - at a picked point")
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
    ("SQUAREUP" "Turns a highlighted drawing until its perimeter's longest wall (or span) is horizontal")
    ("STAIRDIM" "Stair dimensioning")
    ("STOCKCOVER" "Replaces a highlighted perimeter with a stock cover drawing")
    ("TYDRN" "Text, pool-point and anchor cleanup in one pass")
    ("TYLERDRONESUITE" "The whole drone trace in one - TYDRN, then PADDLE, then CDIM")
    ("UPADOVER" "Pads a stretch of wall between two points, or the whole of a line or polyline - no overlap, no gap")
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

;; The fuller explanation behind the one-sentence blurb: what a command
;; actually asks, in the order it asks it, for the "How it works"
;; button on the Find page.  Copied in from the palette's own
;; ui/calofin_net/howto.txt rather than written a second time, the same
;; contract lzp:*blurbs* already keeps against blurbs.txt --
;; tests/test_lazpanel.py holds this table to that file word for word.
;; The numbered steps for most commands were drawn from that command's
;; own prompts in lisp/ rather than invented, then hand-checked; a
;; handful with no interactive prompts of their own (scan companions,
;; the DCL-form tools, cover-sheet wrappers) are a couple of sentences
;; instead.
(setq lzp:*howto*
  '(
    ("ABCDEF" "Plot rectangle points.\nWhat it asks, in order:\n 1. Dimension A-B (width across the top)\n 2. Dimension A-C (height down the side)\n 3. How should each point be placed?\n 4. Insertion point for corner A\n 5. Fit a pool perimeter through these points now?")
    ("ABCURCHECK" "Grades how continuous a drawn perimeter is.\nWhat it asks, in order:\n 1. Declared discontinuities\n 2. Pick a discontinuity (Enter = done)\n 3. Pick the declaration to drop (Enter = done)\n 4. Draw the curvature comb?")
    ("ABCURCHECKSCAN" "ABCURCHECK without marking the drawing.\nWhat it asks, in order:\n 1. Declared discontinuities\n 2. Pick a discontinuity (Enter = done)\n 3. Pick the declaration to drop (Enter = done)\n 4. Draw the curvature comb?")
    ("ABFIND" "Ties Pt.## back to the A and B survey stakes.\nWhat it asks, in order:\n 1. Pick the stake (Enter to cancel)\n 2. Pick the point, or type its number (Enter to cancel)\n 3. Pt. - click a marker or its label, or type a tag\n 4. Which one?\n 5. Click roughly where Pt. belongs\n 6. Number for the new point\n 7. Place the note for Pt")
    ("ABHD" "Fits a pool perimeter and bottom through surveyed points.\nWhat it asks, in order:\n 1. Select objects\n 2. Maximum distance from a point\n 3. Percent of points allowed off\n 4. Maximum curves\n 5. Any straight lines?\n 6. First end of the straight wall - pick it or type its number\n 7. Another straight line?\n 8. Any sharp corners?\n 9. Corner point - pick it or type its number\n 10. Any held points?\n 11. Point to hold exactly - pick it or type its number\n 12. Keep which fit - click one, or\n 13. Pick the outline to keep (or Enter for )\n 14. Add the bottom of the pool (breaks and hopper)?\n 15. First shallow break point\n 16. Enter = no bottom\n 17. First deep break point\n 18. Slope line from the offset at Pt\n 19. ...and more, depending on what you pick along the way")
    ("ABHDCOVER" "ABHD for a cover sheet: the same window-selection of POOL and POINTS geometry, the same automatic GUIDED-vs-POINTS-ONLY fit through the survey points, but the bottom (hopper) question is skipped -- a cover sheet stops at the perimeter.")
    ("ABLOBF" "Fits an OPEN run of arcs and lines through points, between two ends you pick.\nWhat it asks, in order:\n 1. Select objects\n 2. Maximum distance from a point\n 3. Percent of points allowed off\n 4. Maximum curves\n 5. Declare a stretch, corner or held point - or Done to fit?\n 6. Point to hold exactly - pick it or type its number\n 7. First end of the straight stretch - pick it or type its number\n 8. Corner point - pick it or type its number\n 9. Point the run STARTS at\n 10. Point the run ENDS at\n 11. Keep which fit - click one, or\n 12. Pick the outline to keep (or Enter for 2)\n 13. Point to omit, or a ringed one to restore - pick it or type its number\n 14. Straight stretches ( declared)\n 15. Pick near the straight stretch to remove\n 16. Sharp corners ( declared)\n 17. The declared corner to remove - pick it or type its number\n 18. Held points ( declared)\n 19. ...and more, depending on what you pick along the way")
    ("ABMOVE" "Moves a point, offering every mis-read tape it could be.\nWhat it asks, in order:\n 1. Pick the stake (Enter to cancel)\n 2. Pick the point, or type its number (Enter to cancel)\n 3. Pt. - click a marker or its label, or type a tag\n 4. Which one?\n 5. Click roughly where Pt. belongs\n 6. Number for the new point\n 7. Place the note for Pt")
    ("ABPCHECK" "ABHD's measuring half as a checker - how far each point is off the line.\nWhat it asks, in order:\n 1. Select objects\n 2. How far off the line is too far?")
    ("ABPCREATE" "Plots a point that is not there yet from the two readings it was taped at.\nWhat it asks, in order:\n 1. Pick the stake (Enter to cancel)\n 2. Pick the point, or type its number (Enter to cancel)\n 3. Pt. - click a marker or its label, or type a tag\n 4. Which one?\n 5. Click roughly where Pt. belongs\n 6. Number for the new point\n 7. Place the note for Pt")
    ("ADAB" "Freeform perimeter through surveyed points.\nWhat it asks, in order:\n 1. Select objects\n 2. Add the bottom of the pool (breaks and hopper)?\n 3. First shallow break point\n 4. Enter = no bottom\n 5. First deep break point\n 6. Slope line from the offset at Pt\n 7. Enter = done")
    ("ALTABCDEF" "ABCDEF with the clockwise corner order.\nWhat it asks, in order:\n 1. Dimension A-B (width across the top)\n 2. Dimension A-D (height down the side)\n 3. Insertion point for corner A")
    ("AUTOBEAD" "Offsets selected pool lines toward a clicked side.\nWhat it asks, in order:\n 1. Select objects\n 2. Click the side to bead toward\n 3. Which steps have beaded side walls?\n 4. Click a step")
    ("AUTODIM" "Automatic dimensioning.\nWhat it asks, in order:\n 1. Select objects\n 2. Would you like floor dims?\n 3. Floor dims 1 of 2\n 4. Floor dims 2 of 2\n 5. Would you like pads?")
    ("AUTODIMSIDEPOV" "Dimensions a side-view flight of steps.\nWhat it asks, in order:\n 1. Select objects")
    ("BPCALLOUT" "Rings clicked bad points and writes the callout.\nWhat it asks, in order:\n 1. Click a bad point (a ringed one un-rings it, Enter when done)\n 2. Place the callout text")
    ("CABHD" "ABHD's perimeter half, for a survey that runs past the pool.\nWhat it asks, in order:\n 1. Select objects\n 2. Maximum distance from a point\n 3. Percent of points allowed off\n 4. Maximum curves\n 5. Any straight lines?\n 6. First end of the straight wall - pick it or type its number\n 7. Another straight line?\n 8. Any sharp corners?\n 9. Corner point - pick it or type its number\n 10. Any held points?\n 11. Point to hold exactly - pick it or type its number\n 12. Include points up to\n 13. The LAST point that belongs to the pool edge - pick it or type its number\n 14. Keep which fit - click one, or\n 15. Pick the outline to keep (or Enter for )\n 16. Point to omit, or a ringed one to restore - pick it or type its number\n 17. Straight walls ( declared)\n 18. Pick near the straight wall to remove\n 19. ...and more, depending on what you pick along the way")
    ("CCPRECHECK" "Walks the Tech Flow Chart decision tree.\nWhat it asks, in order:\n 1. Product type\n 2. Liner for\n 3. Depth / Wall Height\n 4. Steps?\n 5. Step type\n 6. the step face is either straight or radius\n 7. the size of the step (especially for radius steps)\n 8. sum of Step Risers equals Wall Height\n 9. the corners\n 10. Spillway?\n 11. Spillway Dimensions and location\n 12. Pool shape\n 13. Overlap and Spacing\n 14. Are there obstacles?\n 15. Proximity to water's edge\n 16. Can the cover be secured to the obstruction?\n 17. Is the obstruction larger than 36\"?\n 18. Able to go over the obstruction?\n 19. ...and more, depending on what you pick along the way")
    ("CDCALLOUT" "Cross-dimensions from Pt.## to Pt.## by typed number.\nWhat it asks, in order:\n 1. From point number (Enter when done)\n 2. Which Pt. is meant - click it, or type its label\n 3. To point number (from Pt.)")
    ("CDCREATE" "Turns every highlighted line into a cross dimension.\nWhat it asks, in order:\n 1. Select objects")
    ("CHECK" "General drawing check.\nWhat it asks, in order:\n 1. Select objects")
    ("CLEARDIM" "Select the dimensions to clear (or Enter for the whole drawing). Each one's text is slid along its own track -- the dimension line, the angular arc, the radial line, the leader -- until it clears the geometry it measures; text that already reads clearly is left exactly where it is. Text only ever slides along its track, never off it.")
    ("CLEARDIMSCAN" "CLEARDIM's identical read, reporting which dimension text would move without moving anything.")
    ("CONSTELLATION" "Places points from the distances between them, inside a known box.\nWhat it asks, in order:\n 1. Space width (X)\n 2. Space height (Y)\n 3. How many points?\n 4. Insertion base point\n 5. Pair to dimension (B = back, D = done)\n 6. Points on the arc <Enter = done> (B = back)\n 7. Draw the outline through the points in order?\n 8. Does the drawing look right?\n 9. What needs changing?")
    ("CORNERSTP" "Corner step layout.\nWhat it asks, in order:\n 1. Select objects\n 2. Pick the FIRST wall of the corner\n 3. Pick the SECOND wall of the corner\n 4. Draw steps from the inside out, or the outside in?\n 5. Measure step treads from the middle of the diagonal, or the true corner?\n 6. Steps parallel to the diagonal, or equidistant from the true corner?\n 7. Treads parallel to the diagonal, or at the true angle?\n 8. Dimension the steps?\n 9. Add a bench along a wall?\n 10. Pick the wall the bench sits against\n 11. Bench offset off the wall (its depth)\n 12. Which step is the bench attached to (it ends on that tread)\n 13. Width of the furthest (outermost) step\n 14. Step - step tread (going in)\n 15. Step - step width\n 16. Step - step tread\n 17. Add a side profile?\n 18. Step 1 - step depth (the drop)\n 19. ...and more, depending on what you pick along the way")
    ("COVERCHECK" "Cover check.\nWhat it asks, in order:\n 1. Select objects\n 2. dimension point 1\n 3. dimension point 2\n 4. Is this dimension correct?\n 5. arc start point\n 6. arc end point\n 7. Merge into one line, Flag to fix, or Leave as is?\n 8. Flag to fix, or Leave as is?\n 9. Pick the block")
    ("COVERSCAN" "Scan drawing for covers.\nWhat it asks, in order:\n 1. Select objects\n 2. Pick the block")
    ("CPERPPTS" "PERPPTS for a curved run.\nWhat it asks, in order:\n 1. Select a curve (polyline, arc, spline...)\n 2. Click to pick direction / offset side\n 3. Overall width\n 4. Select a boundary for the offsets\n 5. Do the offsets stop at the boundary, or run out to meet it?\n 6. Round - how many values (points) are required?\n 7. points means dimensions. Continue?\n 8. Length for point of , boundary at\n 9. Overall width of the new curve\n 10. Repeat on the new polyline?\n 11. Dimension style - STANDARD INCHES or SIDE STANDARD?")
    ("CUSTBLOCK" "Custom block in pictorial view from three typed sizes.\nWhat it asks, in order:\n 1. Block length\n 2. Block width\n 3. Block height\n 4. Insertion base point\n 5. Place another block?")
    ("DIMARCCHECK" "Alias of CHECK. Select what to audit; it checks that every dimension's definition points land on real geometry or on a shared ANCHOR -- a point two or more dimensions measure to, which counts as an object in its own right. A dimension with a stray point gets a construction line drawn through its two points, the stray point snapped onto the nearest object or anchor, and its color changed so the fix is visible.")
    ("DIMCHECK" "Guided, one-at-a-time dimension review.\nWhat it asks, in order:\n 1. Select objects\n 2. dimension point 1\n 3. dimension point 2\n 4. Is this dimension correct?\n 5. arc start point\n 6. arc end point\n 7. Merge into one line, Flag to fix, or Leave as is?\n 8. Flag to fix, or Leave as is?")
    ("DIMCONTEND" "Chains a seed dimension out to every feature point.\nWhat it asks, in order:\n 1. Select the dimension to continue\n 2. Select objects\n 3. Continue from another dimension?")
    ("DIMSCAN" "Scan drawing for dimensions.\nWhat it asks, in order:\n 1. Select objects")
    ("DIMSTAMP" "Click a point, type 4'4.5 or 44.5; stamps it canonically, an on-screen ruler picks the next.\nWhat it asks, in order:\n 1. Click a point to place text (Enter when done)\n 2. Text - 4'-4 1/2\", or just 4'4.5\n 3. Click to place text, click the ruler to change it, or type new text (Enter when done)")
    ("DRONE" "Drone cleanup routine.\nWhat it asks, in order:\n 1. Select objects")
    ("DRONOTE" "Places a canned drone-photo review note - diving board, hidden anchors or slide sketch - at a picked point.\nWhat it asks, in order:\n 1. Which note?\n 2. Pick a point for the note (Enter when done)")
    ("FITABHD" "Fits a typed pool template through surveyed points.\nWhat it asks, in order:\n 1. Select objects\n 2. Rectangle/Grecian/ROman/Oval/L/LAzyl/ROUnd\n 3. the pool corners\n 4. the cut corners\n 5. Oasis shape\n 6. Maximum distance from a point\n 7. Percent of points allowed beyond\n 8. Is the pool in-square or out-of-square?\n 9. Any bowed walls?\n 10. Keep this fit, or Redo it?\n 11. Point to leave out, or a ringed one to restore - pick it or type its number\n 12. Hopper offset in from the wall\n 13. Pick a point at the DEEP end of the pool\n 14. Deep break - how far from the deep end wall?\n 15. Shallow break - how far from the deep end wall?\n 16. Hopper offset in from each side wall\n 17. Hopper offset in from the deep end wall")
    ("FITABHDCOVER" "FITABHD's typed-template fit for a cover sheet: pick the pool's shape family (Rectangle, Grecian, Roman, Oval, L, Lazy L or Round), and that template is fitted through the surveyed points same as FITABHD -- but the standard-hopper bottom question is skipped.")
    ("FLOORDIM" "Floor dimensioning.\nWhat it asks, in order:\n 1. Floor dims")
    ("G2MCONV" "Highlight the imported G2M architectural export, or press Enter to take every G2M layer in the drawing. It remaps the architect's AIA layer names, text style and dimension style onto calofin's own POOL / TEXT / DIMENSION layers and styles in one pass, off the before/after sample the shop keeps.")
    ("G2MRECONV" "Undoes a G2MCONV run: every object, layer, style, linetype and annotative override goes back exactly onto the G2M export's own names, as if G2MCONV had never touched the drawing.")
    ("HEMISTEP" "Hemi step layout.\nWhat it asks, in order:\n 1. Select objects\n 2. Pick a point on the side the steps go\n 3. Pick the point on the curve to measure from\n 4. Dimension the steps?\n 5. Width of the step at the wall\n 6. Step - step tread\n 7. Step - step width\n 8. Distance from the last step to the back of the curve\n 9. Draw the reconstructed boundary through the step ends?\n 10. Add a side profile?\n 11. Depth at - the drop onto the first tread\n 12. Pick the top of for the side profile\n 13. Bead the steps?\n 14. Which steps have beaded side walls?\n 15. Step numbers with beaded sides (B = back)\n 16. Click the side to bead toward")
    ("HONEFILLET" "Bracket two of SMARTFILLET's radii and hone between them at half inches.\nWhat it asks, in order:\n 1. Select the first line of the corner\n 2. Select the second line of the corner\n 3. Click one of the two corners to hone between\n 4. Click the one next to it\n 5. Click the rounded corner you want, or its label\n 6. Select the first line of the next corner\n 7. Select the second line of that corner")
    ("LAZDIAG" "Write the last failure out as a DXF to send in - and, with nothing to report, prove that path works.\nWhat it asks, in order:\n 1. Place the error report, far from the drawing")
    ("LAZFORM" "Opens a DCL chart of the pool outline, hopper and dimension chain -- the same picture as the paper order sheet, each box labelled with the letter the sheet uses. Type a number against a letter to fill it in, leave what you do not know blank, and press Insert: POOL runs from the completed sheet, asking only for whatever letter is still empty.")
    ("LAZFORMCOVER" "The same chart as LAZFORM, for a cover sheet: fill in the labelled boxes and press Insert to run POOLCOVER from them.")
    ("LAZLOG" "No prompts. Type LAZLOG to reprint the last failure's report; with nothing to report, it writes a test report to the same folder a real one would land in, proving that path still works.")
    ("LAZSIDE" "Opens the DCL side-view chart, one tab per bottom type (Normal, Sport, Wedge, SLope, MOdflat, SHallow). The longitudinal section stands on the left; fill in the labelled dimension boxes beside it and press Insert, and POOLSIDE draws it, asking for nothing but the base point.")
    ("LAZSPA" "The same lettered-chart pattern as LAZFORM, for SPA: fill in the spa order sheet's boxes (NA means \"not measured\"; blank means SPA should ask), press Insert, and SPA runs from the completed sheet, asking only for whatever is still blank.")
    ("LAZSTEP" "Pick which step routine this is -- CORNERSTP, HEMISTEP or NORMIESTEP -- and type the step count. The chart grows a labelled box for every dimension that count implies (five steps makes five tread boxes, five widths, six depths); fill them in and press Insert to run the step routine.")
    ("LAZTXT" "LAZFORM's identical chart, drawn from DCL tiles instead of vector geometry -- for checking whether the same form could be built in plain text tiles. Fill in the same lettered fields and press Insert.")
    ("LHD" "Laser-point outline fit, open or closed.\nWhat it asks, in order:\n 1. Select objects\n 2. Maximum distance from a point\n 3. Percent of points allowed off\n 4. Maximum curves\n 5. Closed outline or Open polyline?\n 6. Declare a stretch, corner or held point - or Done to fit?\n 7. Point to hold exactly - pick it or type its number\n 8. First end of the straight stretch - pick it or type its number\n 9. Corner point - pick it or type its number\n 10. Draw the outline at which height\n 11. Keep which fit - click one, or\n 12. Pick the outline to keep (or Enter for 2)\n 13. Point to omit, or a ringed one to restore - pick it or type its number\n 14. Straight stretches ( declared)\n 15. Pick near the straight stretch to remove\n 16. Sharp corners ( declared)\n 17. The declared corner to remove - pick it or type its number\n 18. Held points ( declared)\n 19. ...and more, depending on what you pick along the way")
    ("LINCHECK" "Runs the liner tech checklist one item at a time, prompting for each answer in turn. Every item after the first offers Back (B, BACK, U or UNDO, any case), which re-asks the previous item and drops what it logged. Ends with a report of everything checked, answered and noted along the way.")
    ("LINFINCHECK" "Full liner-finish drawing QA, guided.\nWhat it asks, in order:\n 1. Select objects\n 2. dimension point 1\n 3. dimension point 2\n 4. Is this dimension correct?\n 5. arc start point\n 6. arc end point\n 7. Merge into one line, Flag to fix, or Leave as is?\n 8. Flag to fix, or Leave as is?\n 9. Are these lines steps?\n 10. Is a side view of the steps drawn somewhere?\n 11. Type the overall step height or pick two points")
    ("LINFINSCAN" "Highlight the drawing (any selection); runs LINFINCHECK's full audit -- dimensions grouped by style and reviewed one at a time, arcs, overlapping lines, steps and their side views, wall height, the liner pattern, the title block border -- but read-only: nothing is moved or changed, only reported.")
    ("LINGUTTER" "Guts a highlighted area back to the pool, walking the outer face.\nWhat it asks, in order:\n 1. Keep CROSS DIMENSIONS?")
    ("LINGUTTERSCAN" "LINGUTTER's report only - reads the drawing, changes nothing.\nWhat it asks, in order:\n 1. Keep CROSS DIMENSIONS?")
    ("LINTXTCHK" "Places the vinyl-liner QA checklist as drawing text.\nWhat it asks, in order:\n 1. Pick top-left point for LINTXTCHK checklist")
    ("LITECOVERSCAN" "Cover rules only - skips the dimension audit.\nWhat it asks, in order:\n 1. Select objects\n 2. Pick the block")
    ("LITELINFINSCAN" "The same read-only scan as LINFINSCAN, minus the dimension audit -- liner and drawing rules only.")
    ("LITESPACHECKSCAN" "The same scan as SPACHECKSCAN, minus the dimension audit -- spa rules only.")
    ("LOBF" "Fits a construction line through points that should be on one line.\nWhat it asks, in order:\n 1. Select objects\n 2. Keep which fit - click one, or\n 3. Pick the line to keep (or Enter for )")
    ("MOHAMADDLE" "PADDLE's perimeter pads with a size pick first - 24in or 36in.\nWhat it asks, in order:\n 1. Pad size (inches)?\n 2. Select objects\n 3. Close the gap the arrow points at with a zero fillet?")
    ("NORMIESTEP" "Normie step layout.\nWhat it asks, in order:\n 1. Select objects\n 2. Pick a point on the side the steps go\n 3. Pick the line the steps run OFF OF\n 4. Step width (the same for every step)\n 5. Radius for\n 6. Is the cut given as its\n 7. Cut face length for\n 8. Offset back along each line\n 9. Dimension the steps?\n 10. Step - step tread\n 11. Add a side profile?\n 12. Step 1 - step depth (the drop)\n 13. Depth after the last tread\n 14. Pick the top of the first tread for the side profile\n 15. Bead the steps?\n 16. Which steps have beaded side walls?\n 17. Step numbers with beaded sides (B = back)\n 18. Click the side to bead toward")
    ("OASIS" "Continuous-tangent pool drawn live from envelope and radii.\nWhat it asks, in order:\n 1. Which shape is it?\n 2. Kidney type?\n 3. Cloud bottom?\n 4. Simple or complex?\n 5. Insertion base point\n 6. X - overall left-to-right bounds\n 7. Y - overall front-to-back bounds\n 8. center\n 9. right\n 10. Top-right centre to right bulge centre\n 11. Add the bottom of the pool (breaks and hopper)?\n 12. Hopper offset in from the wall")
    ("OLAUTO" "Best-fit overlay of a new perimeter on the original, worst error dimensioned.\nWhat it asks, in order:\n 1. Which perimeter should move onto the other?")
    ("PADDLE" "Paddle perimeter pads.\nWhat it asks, in order:\n 1. Select objects\n 2. Close the gap the arrow points at with a zero fillet?")
    ("PERPMARK" "Name a survey point, type what it measured: circle, perpendicular, dimension.\nWhat it asks, in order:\n 1. Select the pool perimeter\n 2. Click a spot inside the pool\n 3. Pick a survey point, or type its number\n 4. Draw a polyline through the marks?\n 5. The point the run starts at, or type its number\n 6. The point the run ends at, or type its number\n 7. Click a spot the run passes through")
    ("PERPPTS" "Perpendicular offset points along a line or curve.\nWhat it asks, in order:\n 1. Select a line or polyline\n 2. Click to pick direction / offset side\n 3. Overall width\n 4. Select a boundary for the offsets\n 5. Do the offsets stop at the boundary, or run out to meet it?\n 6. Round - how many values (points) are required?\n 7. points means dimensions. Continue?\n 8. Length for point of , boundary at\n 9. Round - how should the points be joined?\n 10. Which segments are arcs (1 to , e.g. 1 3-5)? (B = back)\n 11. Overall width of the new polyline\n 12. Repeat on the new polyline?\n 13. Dimension style - STANDARD INCHES or SIDE STANDARD?")
    ("POINTRENAMER" "Hands the survey point numbers back out in perimeter order.\nWhat it asks, in order:\n 1. Select objects\n 2. Select the perimeter (Enter = the highlighted closed polyline on )\n 3. Pick the start point on the perimeter\n 4. Number the points which way around?\n 5. How far off the perimeter still counts as on it?\n 6. Start the numbering at")
    ("POOL" "Full pool layout tool.\nWhat it asks, in order:\n 1. Is the pool in-square or out-of-square\n 2. Pool shape\n 3. Insertion base point\n 4. Anything to record about the corners (radius / cut / not given)?\n 5. the outer corners\n 6. the inner corner E\n 7. Add pool bottom (hopper) detail?\n 8. Mirror the pool (flips the wing; deep end stays left)\n 9. Mark the dimension(s) that could not be held at their original value as \"Given\"\n 10. Select a Given dimension to switch ft-in/in (Enter when done)\n 11. the body corners A, B, C and D\n 12. the end-tip corners LT, LB, RT and RB\n 13. Bottom type\n 14. Hopper type (SIX = six-sided)\n 15. SIX-sided corners measured by\n 16. C - wall height (shallow depth)\n 17. D - deep end depth\n 18. C2 - depth where the shallow floor meets the break\n 19. ...and more, depending on what you pick along the way")
    ("POOLCOVER" "The same interview as POOL -- in-square or out-of-square, shape, per-corner treatment, cross dims -- for a cover sheet: the pool-bottom question is pre-answered No, so the hopper is never asked about.")
    ("POOLDEMO" "No prompts. Draws one hardcoded example of every shape and every bottom POOL can produce, side by side and captioned, as an install check and a reference sheet. Safe to run any time in a scratch drawing -- run it in a new drawing, not over live work.")
    ("POOLSIDE" "POOL's longitudinal section on its own, from the floor run chain.\nWhat it asks, in order:\n 1. Bottom type\n 2. Insertion base point (top left of the section)\n 3. B - overall length, wall to wall\n 4. D - deep end depth\n 5. C2 - depth where the shallow floor meets the break\n 6. Put the deep end on the RIGHT?")
    ("SIMPABHD" "ABHD with nothing to decide: five ready-made perimeters, keep one.\nWhat it asks, in order:\n 1. Select objects\n 2. Maximum distance from a point\n 3. Percent of points allowed off\n 4. Maximum curves\n 5. Any straight lines?\n 6. First end of the straight wall - pick it or type its number\n 7. Another straight line?\n 8. Any sharp corners?\n 9. Corner point - pick it or type its number\n 10. Any held points?\n 11. Point to hold exactly - pick it or type its number\n 12. Keep which fit - click one, or\n 13. Pick the outline to keep (or Enter for )\n 14. Add the bottom of the pool (breaks and hopper)?\n 15. First shallow break point\n 16. Enter = no bottom\n 17. First deep break point\n 18. Slope line from the offset at Pt\n 19. ...and more, depending on what you pick along the way")
    ("SMARTFILLET" "Fillet a corner after previewing every radius that fits.\nWhat it asks, in order:\n 1. Select the first line of the corner\n 2. Select the second line of the corner\n 3. Select the first line of the next corner\n 4. Select the second line of that corner")
    ("SOCONV" "Puts an SO site-survey export onto the shop's layers in one pass.\nWhat it asks, in order:\n 1. Select objects")
    ("SORECONV" "Undoes a SOCONV run - every object back on the export's own layers.\nWhat it asks, in order:\n 1. Select objects")
    ("SPA" "Spa / hot-tub template layout.\nWhat it asks, in order:\n 1. Select the Spa Cover Details block\n 2. Is this drawing at the water's edge or the cover size\n 3. Spa shape\n 4. Insertion base point\n 5. Auto-hinge the cover\n 6. Is there a spillaway\n 7. Spillaway location (a wall one is centred on it)\n 8. Which corner\n 9. On which wall\n 10. Take it from\n 11. How far does the cover lap the water's edge\n 12. Taper (3-2, 4-2, 4-3, 5-3, 5-4, 3-3, 1-3/8)\n 13. Overall diameter\n 14. Are all four corners the same?\n 15. Square Radius Cut NotGiven NG 90 ROUNDED DIAG DIAGONAL")
    ("SPACHECK" "Audits a spa sheet against what SPA draws.\nWhat it asks, in order:\n 1. Select objects")
    ("SPACHECKSCAN" "Highlight the spa drawing together with its \"Spa Cover Details\" block; runs SPACHECK's full set of audits -- built from what SPA itself draws, so a SPA-produced drawing passes and a hand-edited one shows exactly where it drifted -- but read-only, as one scan instead of a guided walk.")
    ("SPACOVCREATE" "Offsets a selected spa outline into its cover and hinges it to the taper.\nWhat it asks, in order:\n 1. Select objects\n 2. Cover offset past the spa\n 3. Select the block that gives the taper\n 4. Taper (3-2, 4-2, 4-3, 5-3, 5-4, 3-3, 1-3/8)")
    ("SQUAREUP" "Turns a highlighted drawing until its perimeter's longest wall (or span) is horizontal.\nWhat it asks, in order:\n 1. Select objects\n 2. What should end up horizontal?\n 3. Turn the highlighted objects anyway?")
    ("STAIRDIM" "Stair dimensioning.\nWhat it asks, in order:\n 1. Select objects")
    ("STOCKCOVER" "Replaces a highlighted perimeter with a stock cover drawing.\nWhat it asks, in order:\n 1. Select objects\n 2. Stock drawing name\n 3. Which one?")
    ("TYDRN" "Text, pool-point and anchor cleanup in one pass.\nWhat it asks, in order:\n 1. Select objects")
    ("TYLERDRONESUITE" "The whole drone trace in one - TYDRN, then PADDLE, then CDIM.\nWhat it asks, in order:\n 1. Select objects")
    ("UPADOVER" "Pads a stretch of wall between two points, or the whole of a line or polyline - no overlap, no gap.\nWhat it asks, in order:\n 1. Select the perimeter, or the line or polyline to pad\n 2. Where the pads start - click it, or type a point number\n 3. Where the pads end - click it, or type a point number\n 4. Click a spot the run passes through")
    ("VSCONV" "Remaps a VS survey export's numbered layers onto the shop's.\nWhat it asks, in order:\n 1. Select objects")
    ("VSRECONV" "Undoes a VSCONV run - layers, properties and the dimension overrides.\nWhat it asks, in order:\n 1. Select objects")
    ("WCALST" "Unrolls a curved constant-width band flat, with darts.\nWhat it asks, in order:\n 1. Select objects\n 2. Click the long side to STRAIGHTEN\n 3. Maximum darts + inserts\n 4. Tile height along the straightened edge\n 5. Window a STAIR section - first corner [Back] (Enter = done)\n 6. Opposite corner")
    ("XFTCONV" "Cleans up a Leica XFT/DXF import or a site trace.\nWhat it asks, in order:\n 1. Select objects")
    ("XFTRECONV" "Undoes an XFTCONV run - the markers and text back, and the scale with them.\nWhat it asks, in order:\n 1. Select objects")
    ("XYPLOT" "Plot an X/Y sheet, twice: points, and dimensioned.\nWhat it asks, in order:\n 1. Insertion point for the origin (X=0, Y=0)\n 2. Fit a pool perimeter through graph 1's points now?")
   ))

;; No per-drafter override, the same as lzp:blurb: a command with
;; somehow no row (there is always one; the test above is what keeps
;; that true) falls back to its blurb rather than showing blank.
(defun lzp:howto (name / p)
  (cond ((setq p (assoc name lzp:*howto*)) (cadr p))
        (t (lzp:blurb name))))

;; The handful of commands with a full interactive TUTORIAL* walkthrough
;; -- a paced, captioned command of its own that draws example geometry
;; rather than a block of text -- keyed by the headline command Find
;; shows it under.  Most tools have none, which is normal: TUTORIAL*
;; stays a satellite (off the panel, off every group, see the roster
;; comment above) whether or not this table names it.
(setq lzp:*tutorials*
  '(
    ("CPERPPTS" "TUTORIALCPERPPTS")
    ("PERPPTS"  "TUTORIALPERPPTS")
    ("POOL"     "TUTORIALPOOL")
    ("SPA"      "TUTORIALSPA")
   ))

(defun lzp:tutorial-of (name / p)
  (cond ((setq p (assoc name lzp:*tutorials*)) (cadr p))))

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
    ("DRONOTE" "note RFI question diving board water edge anchors hidden slide sketch review mtext")
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
    ("SQUAREUP" "rotate turn straighten square align orient angle horizontal survey skew tilt level")
    ("STAIRDIM" "stairs steps dimensions plan flight standard typical")
    ("STOCKCOVER" "stock cover replace perimeter drawing folder align placement")
    ("TYDRN" "drone trace cleanup text points spa layer pool tidy")
    ("TYLERDRONESUITE" "suite chain drone trace tidy pad dimension selection")
    ("UPADOVER" "stretch run between entire wholesale continuous flush interlock staircase shorter way round straddle")
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
      "UPADOVER"
      "SQUAREUP"
      "DRONOTE"
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
      "UPADOVER"
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
      "SQUAREUP"
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
      "DRONOTE"
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
;; set alongside lzp:*pick* only by the Tutorial button: a TUTORIAL*
;; satellite launched from Find must not land in Recent the way a real
;; pick does, so lzp:launch is told to skip lzp:remember for this one
(setq lzp:*pick-quiet* nil)
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

;; Show the fuller explanation for what is highlighted -- an OK-only
;; message box, the same text CALHELP prints to the command line, but
;; reached without leaving the dialog or typing the name again.  A
;; tutorial mapping, when there is one, is mentioned rather than run:
;; the Tutorial button beside this one is what launches it.
(defun lzp:find-howto ( )
  (cond
    ((not lzp:*sel*)
     (set_tile "msg" "nothing highlighted - pick a tool first"))
    (t
     (alert (strcat lzp:*sel* "  -  " (lzp:caption lzp:*sel*)
                    "\n\n" (lzp:howto lzp:*sel*)
                    (if (lzp:tutorial-of lzp:*sel*)
                      (strcat "\n\nAn interactive walkthrough is also"
                              " available - click Tutorial, or type "
                              (lzp:tutorial-of lzp:*sel*) ".")
                      ""))))))

;; Launch the highlighted tool's TUTORIAL* walkthrough instead of the
;; tool itself.  Same refusal shape as lzp:findrun -- nothing
;; highlighted, no walkthrough for this tool, or the walkthrough itself
;; not loaded each say so on the message line rather than erroring --
;; plus lzp:*pick-quiet*, set alongside the pick: a TUTORIAL* command is
;; a satellite (see the roster comment above) and must never land in
;; Recent the way a real launch would.
(defun lzp:find-tutorial ( / tut)
  (cond
    ((not lzp:*sel*)
     (set_tile "msg" "nothing highlighted to run"))
    ((not (setq tut (lzp:tutorial-of lzp:*sel*)))
     (set_tile "msg" (strcat lzp:*sel*
                             " has no interactive tutorial - see How it works")))
    ((not (lzp:has tut))
     (set_tile "msg" (strcat tut " is not loaded in this session")))
    (t
     (setq lzp:*pick*       tut
           lzp:*pick-quiet* t
           lzp:*pos*        (done_dialog 1)))))

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
          (strcat "    : button { label = \"How it works\"; "
                  "key = \"howto_btn\"; fixed_width = true; }")
          (strcat "    : button { label = \"Tutorial\"; "
                  "key = \"tutorial_btn\"; fixed_width = true; }")
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
  (setq out (append out (lzp:dcl-names) (list "")))
  (append out (lzp:dcl-tune) (list "")))

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

;; quiet: true for a TUTORIAL* satellite launched off the Tutorial
;; button (lzp:find-tutorial) -- it still runs, but must not land in
;; Recent the way a real pick does.  Omitted (nil) by every other
;; caller, which is the ordinary remembered launch.
(defun lzp:launch (name quiet / fn)
  (setq fn (read (strcat "C:" name)))
  (cond
    ((eval fn)
     (princ (strcat "\nLAZPANEL: running " name
                    " -- LAZPANEL reopens the panel."))
     ;; remembered BEFORE it runs: a tool that errors out, or that is
     ;; cancelled with Escape, was still the one you reached for
     (if (not quiet) (lzp:remember name))
     ;; ...and the drafter's own defaults re-applied right before, so a
     ;; tool reloaded since the panel opened still runs with them
     (lzp:knobs-apply)
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
    (setq f nil lzp:*pick* nil lzp:*pick-quiet* nil)
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
             (action_tile "run" "(lzp:findrun)")
             (action_tile "howto_btn" "(lzp:find-howto)")
             (action_tile "tutorial_btn" "(lzp:find-tutorial)"))
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
  (setq f nil lzp:*pick* nil lzp:*pick-quiet* nil)
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
  ;; the drafter's own defaults, in case a tool was reloaded since --
  ;; a reloaded block has put Alec's choice back
  (lzp:knobs-apply)
  (while (setq pick (lzp:show))
    (cond
      ((= pick "*pins*"))            ; already handled inside lzp:show
      ((= pick "*options*") (c:LAZSET))  ; settings, never a roster launch
      (t (lzp:launch pick lzp:*pick-quiet*)
         (setq lzp:*pick-quiet* nil))))
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

;; The dropdown's recommended presets, so a drafter picks a colour
;; family by name instead of guessing an ACI number.  Each entry is
;; (label ACI r g b).  Deliberately NOT the full 255-colour AutoCAD
;; palette: 1-9 are the standard colours every "Select Color" dialog
;; shows first and 250-254 are its grey ramp, both unambiguous and
;; nowhere else in this tree to check a memory of the other 240
;; against -- a wrongly-remembered mid-palette shade would draw the
;; wrong colour and nothing here would ever notice.  The RGB is what a
;; typed hex code (lzp:hex2rgb) snaps to the nearest of, in
;; lzp:aci-near -- so "recommended presets, then hex codes" is one
;; mechanism, not two: every hex answer lands on one of these ACI
;; numbers too, which is what lets storage stay a bare ACI number and
;; cal:ink stay exactly as it was.
(setq lzp:*inkpresets*
  '(("Red"                            1 255   0   0)
    ("Yellow"                         2 255 255   0)
    ("Green"                          3   0 255   0)
    ("Cyan"                           4   0 255 255)
    ("Blue"                           5   0   0 255)
    ("Magenta"                        6 255   0 255)
    ("White / Black (auto-contrast)"  7 255 255 255)
    ("Gray - Darkest"               250  51  51  51)
    ("Gray - Dark"                  251 102 102 102)
    ("Gray - Medium"                252 128 128 128)
    ("Gray - Light"                 253 178 178 178)
    ("Gray - Palest"                254 204 204 204)))

(defun lzp:pname (p) (nth 0 p))
(defun lzp:paci  (p) (nth 1 p))
(defun lzp:pr    (p) (nth 2 p))
(defun lzp:pg    (p) (nth 3 p))
(defun lzp:pb    (p) (nth 4 p))

;; One hex digit's value, or nil -- either case, spelled out rather
;; than handed to a base conversion AutoLISP does not have.
(defun lzp:hexdigit (c)
  (vl-string-search (strcase c) "0123456789ABCDEF"))

;; (R G B) out of a 6-digit hex string, an optional leading # either
;; way -- nil when it is not exactly that, so a half-typed or garbled
;; hex is refused the same way lzp:aci-p refuses a bad ACI number.
(defun lzp:hex2rgb (s / h ok i)
  (setq h (if (= (substr s 1 1) "#") (substr s 2) s))
  (setq ok (= (strlen h) 6) i 1)
  (while (and ok (<= i 6))
    (if (not (lzp:hexdigit (substr h i 1))) (setq ok nil))
    (setq i (1+ i)))
  (if ok
    (list (+ (* 16 (lzp:hexdigit (substr h 1 1))) (lzp:hexdigit (substr h 2 1)))
          (+ (* 16 (lzp:hexdigit (substr h 3 1))) (lzp:hexdigit (substr h 4 1)))
          (+ (* 16 (lzp:hexdigit (substr h 5 1))) (lzp:hexdigit (substr h 6 1))))))

;; The preset whose RGB is closest to (R G B), by squared distance --
;; no sqrt needed, only the ordering does.  A tie keeps the FIRST
;; preset checked, which is lzp:*inkpresets*'s own order above.
(defun lzp:aci-near (r g b / best bestd p d)
  (foreach p lzp:*inkpresets*
    (setq d (+ (expt (- r (lzp:pr p)) 2)
               (expt (- g (lzp:pg p)) 2)
               (expt (- b (lzp:pb p)) 2)))
    (if (or (not bestd) (< d bestd))
      (setq bestd d best p)))
  (lzp:paci best))

;; The preset name an ACI number matches exactly, or nil -- an override
;; CALSET's command line or a hand-edited profile set outside the
;; presets entirely still reports as a bare number, same as always.
(defun lzp:presetname (aci / p out)
  (foreach p lzp:*inkpresets* (if (= (lzp:paci p) aci) (setq out (lzp:pname p))))
  out)

(defun lzp:setshow ( / r v p)
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
                   (cond
                     ((not (and v (/= v ""))) "(auto)")
                     ((setq p (lzp:presetname (atoi v)))
                      (strcat "ACI " v " (" p ")"))
                     (t (strcat "ACI " v))))))
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

(defun c:CALSET ( / *error* pick key v role rgb)
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
                                     " colour -- an ACI number, a hex code, "
                                     "Back to leave it, or . for Auto: ")))
        (if lzd:ask (lzd:ask (strcat role " colour") v) v)
        (setq rgb (lzp:hex2rgb v))
        (cond
          ((member (strcase v) '("B" "BACK" "U" "UNDO")) (c:CALSET))
          ((= v "") (princ "\nUnchanged."))
          ((= v ".")
           (setenv key "")
           (princ (strcat "\n" role " colour cleared -- back to Auto.")))
          (rgb
           (setenv key (itoa (lzp:aci-near (car rgb) (cadr rgb) (caddr rgb))))
           (princ (strcat "\n" role " colour is now ACI " (getenv key)
                          " -- the closest recommended preset to " v
                          ".  COVERCHECK, DIMCHECK and LINFINCHECK read it"
                          " on their next run.")))
          ((= (atoi v) 0)
           (princ "\nNot a colour number or hex code -- unchanged."))
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

;; The scratch key its hex box's typed text lives under, in
;; lzp:*setvals* only -- never a real profile key, never setenv'd.
;; lzp:set-write reaches lzp:inkkey's key alone; this one exists so the
;; box can be repainted (and its typo re-checked) across a trip through
;; Hidden... or Names..., the same reason CalofinErrorDir's own box
;; survives that hop.
(defun lzp:inkhexkey (r) (strcat "CalofinInkHex-" (strcase (cdr r))))

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

;; The roles whose HEX box holds something that is not a hex colour.
;; Empty is not one of them: an empty hex box simply defers to whatever
;; the family dropdown beside it says, which -- built from the presets
;; below -- can never itself be unreadable.
(defun lzp:set-badinks ( / r v out)
  (foreach r lzp:*inkroles*
    (setq v (lzp:set-get (lzp:inkhexkey r)))
    (if (and (/= v "") (not (lzp:hex2rgb v)))
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
      (strcat "Not a hex colour: " msg
              " -- type RRGGBB or #RRGGBB, or leave the box empty")
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
  ;; lzp:inkkey's value is always "" or one of the presets' own ACI
  ;; numbers by construction now -- a family pick or a valid hex both
  ;; go through lzp:aci-near -- so this guard is defensive rather than
  ;; load-bearing, the same posture lzp:profread already takes: nothing
  ;; here trusts that a hand-edited profile, or a value CALSET's own
  ;; command line wrote before this dialog existed, still reads as one.
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
                          " and LINFINCHECK; a family, a hex code, or empty"
                          " for auto\";")))
  ;; three to a column, so the box is a block rather than one tall
  ;; stack; each role is a family dropdown beside its hex box, in a row
  ;; of its own, so a column stays three rows tall exactly as it was
  ;; when a role was one plain edit_box -- only the row gets wider.
  (foreach col (lzp:chunk lzp:*inkroles* 3)
    (setq out (append out (list "    : column {")))
    (foreach r col
      (setq out (append out
        (list "      : row {"
              (strcat "        : popup_list { key = \"inkfam_" (cdr r)
                      "\"; label = \"" (car r) "\"; edit_width = 28; }")
              (strcat "        : edit_box { key = \"inkhex_" (cdr r)
                      "\"; label = \"hex\"; edit_width = 7;"
                      " fixed_width = true; }")
              "      }"))))
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
          (strcat "    : button { label = \"Defaults...\"; "
                  "key = \"set_tune\"; fixed_width = true; }")
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
;; The family dropdown's list, in the order DCL will hand indices back:
;; Auto first, then the presets, then Custom -- a landing state for a
;; value none of the presets name.
(defun lzp:inkfam-names ( / p out)
  (setq out (list "Auto"))
  (foreach p lzp:*inkpresets* (setq out (append out (list (lzp:pname p)))))
  (append out (list "Custom (typed hex below)")))

;; Which entry of that list a STORED value is, as the index DCL wants.
;; 0 is Auto (empty), 1..N a preset that matches it exactly, and the
;; last is Custom -- a value CALSET's own command line, a hand-edited
;; profile, or an earlier ACI-only build can still leave that none of
;; the presets name.
(defun lzp:inkfam-index (v / i out p)
  (cond
    ((= v "") 0)
    (t
     (setq out (1+ (length lzp:*inkpresets*)) i 1)
     (foreach p lzp:*inkpresets*
       (if (= v (itoa (lzp:paci p))) (setq out i))
       (setq i (1+ i)))
     out)))

;; A family choice fires.  0 writes Auto, 1..N a preset's own ACI, and
;; the last -- Custom -- is a no-op: there is no single ACI it could
;; mean by itself, only the hex box beside it says, so picking it by
;; hand leaves whatever was already stored exactly alone.  Choosing an
;; actual family clears that box, visibly as well as in the store, so
;; the two controls never show two different answers at once.
(defun lzp:inkfam-pick (key hexkey tile v / n)
  (setq v (atoi v) n (length lzp:*inkpresets*))
  (cond
    ((= v 0) (lzp:set-put key "") (lzp:set-put hexkey "") (set_tile tile ""))
    ((<= v n)
     (lzp:set-put key (itoa (lzp:paci (nth (1- v) lzp:*inkpresets*))))
     (lzp:set-put hexkey "")
     (set_tile tile "")))
  (lzp:set-state))

;; The hex box fires.  A valid 6-digit code snaps to the nearest
;; preset's ACI, exactly as CALSET's own Itemcolors prompt now does;
;; anything else is left for lzp:set-badinks to catch, the same bargain
;; every other box on this page already keeps -- a typo greys OK
;; without touching what was stored before it.
(defun lzp:inkhex-pick (key hexkey v / rgb)
  (lzp:set-put hexkey v)
  (if (setq rgb (lzp:hex2rgb v))
    (lzp:set-put key (itoa (lzp:aci-near (car rgb) (cadr rgb) (caddr rgb)))))
  (lzp:set-state))

(defun lzp:set-edit (dcl / rc r nm done out)
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
         (start_list (strcat "inkfam_" (cdr r)))
         (foreach nm (lzp:inkfam-names) (add_list nm))
         (end_list)
         (set_tile (strcat "inkfam_" (cdr r))
                   (itoa (lzp:inkfam-index (lzp:set-get (lzp:inkkey r)))))
         (set_tile (strcat "inkhex_" (cdr r)) (lzp:set-get (lzp:inkhexkey r)))
         (action_tile (strcat "inkfam_" (cdr r))
           (strcat "(lzp:inkfam-pick \"" (lzp:inkkey r) "\" \""
                   (lzp:inkhexkey r) "\" \"inkhex_" (cdr r) "\" $value)"))
         (action_tile (strcat "inkhex_" (cdr r))
           (strcat "(lzp:inkhex-pick \"" (lzp:inkkey r) "\" \""
                   (lzp:inkhexkey r) "\" $value)")))
       (set_tile "set_errdir" (lzp:set-get "CalofinErrorDir"))
       (action_tile "set_errdir" "(lzp:set-put \"CalofinErrorDir\" $value)")
       (set_tile "set_stockdir" (lzp:set-get "StockCover_Folder"))
       (action_tile "set_stockdir"
                    "(lzp:set-put \"StockCover_Folder\" $value)")
       (set_tile "hiddenmsg" (lzp:hiddenmsg))
       (action_tile "set_hidden" "(done_dialog 5)")
       (action_tile "set_names" "(done_dialog 6)")
       (action_tile "set_tune" "(done_dialog 7)")
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
         ;; ...and the defaults editor, which reports what its OK wrote
         ;; since this dialog's own OK has nothing to say about it
         ((= rc 7) (lzp:tune-report (lzp:tune-edit dcl)))
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

;;; -------------------- the knob catalog ---------------------------------
;;  Every tunable of every tool, transcribed from the tunables block
;;  at the top of its file by tools/gen_knobs.py: ((LABEL FILE (NAME
;;  LITERAL MEANING) ...) ...), the literal as the block spells it.
;;  This is what LAZTUNE offers a drafter, and "Alec's choice" is the
;;  literal here.  GENERATED, between the two markers, and held current
;;  by check_standards -- a knob added to a block and not regenerated
;;  here fails make check rather than quietly staying un-offerable.
;;  Only the region between the markers is written; do not edit it.
;;; >>> lzp:*knobs* -- GENERATED by tools/gen_knobs.py, do not edit
(setq lzp:*knobs*
  '(
    ("ABCDEF" "lisp/abcdef/abcdef.lsp"
     ("abcdef:*fit-ok*" "0.20" "Quarter-inch field data that was read and typed correctly fits a rectangle well under a tenth of an inch of...")
     ("abcdef:*fit-bad*" "0.50" "Quarter-inch field data that was read and typed correctly fits a rectangle well under a tenth of an inch of...")
     ("abcdef:*edge-tol*" "1.0" "How far outside the rectangle a solved point may land and still be treated as rounding to be snapped back o...")
     ("abcdef:*snap-show*" "0.001" "A snap smaller than this is not reported at all - it is arithmetic, not a finding. In inches.")
     ("abcdef:*drop-gain*" "0.5" "With four tapes and a poor fit, each tape is left out in turn. The best three-tape fit is allowed to win, a...")
     ("abcdef:*drop-ratio*" "3.0" "With four tapes and a poor fit, each tape is left out in turn. The best three-tape fit is allowed to win, a...")
     ("abcdef:*drop-margin*" "0.25" "With four tapes and a poor fit, each tape is left out in turn. The best three-tape fit is allowed to win, a...")
     ("abcdef:*swap-min*" "0.5" "Every row with three or more tapes is solved as labelled AND with the C and D columns exchanged. The sheet...")
     ("abcdef:*swap-ratio*" "0.25" "Every row with three or more tapes is solved as labelled AND with the C and D columns exchanged. The sheet...")
     ("abcdef:*poor-fit*" "1.0" "When the average fit over those rows is still worse than this many inches after any swap, the command warns...")
     ("abcdef:*conf-three*" "8.0" "Every point starts at 100 and loses points for what its tapes could not show. The number is clamped to 1..9...")
     ("abcdef:*conf-two*" "26.0" "Every point starts at 100 and loses points for what its tapes could not show. The number is clamped to 1..9...")
     ("abcdef:*conf-fit*" "110.0" "Leftover fit error costs *conf-fit* points per inch of RMS, up to *conf-fit-max*. At the defaults a tenth o...")
     ("abcdef:*conf-fit-max*" "55.0" "Leftover fit error costs *conf-fit* points per inch of RMS, up to *conf-fit-max*. At the defaults a tenth o...")
     ("abcdef:*conf-spread*" "12.0" "Spread - how far the answer moves when any one tape is dropped - costs *conf-spread* points per inch, up to...")
     ("abcdef:*conf-spread-max*" "20.0" "Spread - how far the answer moves when any one tape is dropped - costs *conf-spread* points per inch, up to...")
     ("abcdef:*cut-bad*" "20.0" "The angle the best pair of tapes crosses at, in degrees. A shallow crossing turns a quarter inch of tape er...")
     ("abcdef:*cut-poor*" "35.0" "The angle the best pair of tapes crosses at, in degrees. A shallow crossing turns a quarter inch of tape er...")
     ("abcdef:*cut-fair*" "50.0" "The angle the best pair of tapes crosses at, in degrees. A shallow crossing turns a quarter inch of tape er...")
     ("abcdef:*conf-cut-bad*" "22.0" "The angle the best pair of tapes crosses at, in degrees. A shallow crossing turns a quarter inch of tape er...")
     ("abcdef:*conf-cut-poor*" "10.0" "The angle the best pair of tapes crosses at, in degrees. A shallow crossing turns a quarter inch of tape er...")
     ("abcdef:*conf-cut-fair*" "3.0" "The angle the best pair of tapes crosses at, in degrees. A shallow crossing turns a quarter inch of tape er...")
     ("abcdef:*conf-drop*" "6.0" "A dropped tape costs this much: the row needed repairing, and a repair is a judgement even when the evidenc...")
     ("abcdef:*conf-mirror*" "25.0" "Two tapes fix a point twice over - once each side of the line joining the two corners they were measured fr...")
     ("abcdef:*grade-high*" "90.0" "The word that goes with the number: HIGH from *grade-high* up, then GOOD, FAIR, WEAK, and POOR below *grade...")
     ("abcdef:*grade-good*" "75.0" "The word that goes with the number: HIGH from *grade-high* up, then GOOD, FAIR, WEAK, and POOR below *grade...")
     ("abcdef:*grade-fair*" "60.0" "The word that goes with the number: HIGH from *grade-high* up, then GOOD, FAIR, WEAK, and POOR below *grade...")
     ("abcdef:*grade-weak*" "40.0" "The word that goes with the number: HIGH from *grade-high* up, then GOOD, FAIR, WEAK, and POOR below *grade...")
     ("abcdef:*conf-check*" "60.0" "A point under this confidence \"wants checking\": it is counted in the summary and gets a note beside it in t...")
     ("abcdef:*point-layer*" "\"POINTS\"" "The survey points, as the rest of the toolkit reads them: an \"ab_pt\" block on layer POINTS with the sheet's...")
     ("abcdef:*point-block*" "\"ab_pt\"" "The survey points, as the rest of the toolkit reads them: an \"ab_pt\" block on layer POINTS with the sheet's...")
     ("abcdef:*point-tag*" "\"number\"" "The survey points, as the rest of the toolkit reads them: an \"ab_pt\" block on layer POINTS with the sheet's...")
     ("abcdef:*point-color*" "2" "The survey points, as the rest of the toolkit reads them: an \"ab_pt\" block on layer POINTS with the sheet's...")
     ("abcdef:*frame-layer*" "\"ABCDEF-FRAME\"" "The rectangle with its corner letters, and the notes beside doubtful points. Colours are AutoCAD colour num...")
     ("abcdef:*frame-color*" "1" "The rectangle with its corner letters, and the notes beside doubtful points. Colours are AutoCAD colour num...")
     ("abcdef:*warn-layer*" "\"ABCDEF-WARN\"" "The rectangle with its corner letters, and the notes beside doubtful points. Colours are AutoCAD colour num...")
     ("abcdef:*warn-color*" "1" "The rectangle with its corner letters, and the notes beside doubtful points. Colours are AutoCAD colour num...")
     ("abcdef:*text-div*" "120.0" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. The bloc...")
     ("abcdef:*text-min*" "0.5" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. The bloc...")
     ("abcdef:*tag-scale*" "1.4" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. The bloc...")
     ("abcdef:*tag-gap*" "1.0" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. The bloc...")
     ("abcdef:*tag-drop*" "1.6" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. The bloc...")
     ("abcdef:*note-off*" "0.6" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. The bloc...")
     ("abcdef:*file-types*" "\"xlsx;xls;xlsm;csv\"" "What the file dialog offers, as a getfiled extension list. CSV is read natively; the Excel formats go throu...")
     ("abcdef:*hdr-dist*" "'(\"FROM A\" \"FROM B\" \"FROM C\" \"FROM D\")" "Header words that identify the columns, compared upper-case as substrings: a header containing the Nth entr...")
     ("abcdef:*hdr-name*" "'(\"NAME\" \"POINT\" \"LABEL\")" "Header words that identify the columns, compared upper-case as substrings: a header containing the Nth entr...")
     ("abcdef:*report-suffix*" "\"_ABCDEF_report.txt\"" "The report file is the sheet's name with its extension replaced by this, written beside the sheet.")
     ("abcdef:*apos-over*" "1.05" "A reading with no foot mark whose value is more than *apos-over* times the rectangle's diagonal, and whose...")
     ("abcdef:*impossible*" "1.1" "A reading with no foot mark whose value is more than *apos-over* times the rectangle's diagonal, and whose...")
     ("abcdef:*fractions*" "'(2 4 8 16 32)" "The denominators an inch fraction may have. A slash-less digit run like \"314\" is rebuilt as the one fractio...")
     ("abcdef:*log-denom*" "32" "The correction log writes each repaired value back as feet-inches to the nearest 1/*log-denom* of an inch,...")
     ("abcdef:*fuzz*" "1e-9" "Two lengths closer than this are the same length; also the shortest radius the solver will divide by. In in...")
     ("abcdef:*solve-iters*" "60" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("abcdef:*solve-step*" "1e-7" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("abcdef:*solve-singular*" "1e-12" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("abcdef:*seed-singular*" "1e-9" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("abcdef:*frame-tol*" "0.001" "The corner self-check accepts a side or diagonal within this many inches of what W and H say it should be."))
    ("ABCURCHECK" "lisp/abcurcheck/ABCURCHECK.lsp"
     ("acc:*mark-layer*" "\"POOL-CONT\"" "findings and declarations go here")
     ("acc:*comb-layer*" "\"POOL-COMB\"" "the curvature comb goes here")
     ("acc:*mark-color*" "3" "ACI: the marks layer (green)")
     ("acc:*comb-color*" "4" "ACI: the comb layer (cyan)")
     ("acc:*gap-color*" "1" "ACI: a gap, or the kink band (red)")
     ("acc:*corner-color*" "2" "ACI: an undeclared corner (yellow)")
     ("acc:*decl-color*" "3" "ACI: a declared break (green)")
     ("acc:*appid*" "\"ABCURCHECK\"" "Everything ABCURCHECK draws carries xdata under this name, so a rescue erases only its own work off a layer...")
     ("acc:*dash-name*" "\"DASHED\"" "The dashed linetype declarations are ringed with, and its pattern: dash, gap, and the total the two must ad...")
     ("acc:*dash-on*" "12.0" "drawing units of dash The dashed linetype declarations are ringed with, and its pattern: dash, gap, and the...")
     ("acc:*dash-off*" "6.0" "...and of gap -- G0: is the loop closed at all ------------------------------------- The dashed linetype de...")
     ("acc:*fuzz*" "1.0e-4" "drawing units Closer than this and two ends are the same point -- ABHD's *PF-CHAIN-FUZZ*. Raising it forgiv...")
     ("acc:*close-tol*" "5.0" "degrees The signed turning of a simple closed loop is 360 degrees. This is how far off that the total may s...")
     ("acc:*cross-max*" "300" "segments The crossing scan compares every segment with every other, so it is skipped above this many segmen...")
     ("acc:*tangent-eps*" "0.5" "degrees At or under this a joint is TANGENT -- the two sides run on into each other and there is nothing to...")
     ("acc:*kink-tol*" "8.0" "degrees The most a joint may turn and still read as smooth, and the angle over which it stops being a kink...")
     ("acc:*corner-ang*" "45.0" "degrees The most a joint may turn and still read as smooth, and the angle over which it stops being a kink...")
     ("acc:*micro-len*" "3.0" "drawing units A segment shorter than this is a micro-segment, the signature of an outline traced by hand ra...")
     ("acc:*micro-share*" "0.10" "fraction of the perimeter The share of the perimeter sitting in micro-segments that costs the whole noise s...")
     ("acc:*excess-free*" "0.35" "turns beyond one full turn A freeform pool turns more than 360 degrees in total because it weaves; FREE is...")
     ("acc:*excess-cap*" "1.00" "...and where it reaches zero A freeform pool turns more than 360 degrees in total because it weaves; FREE i...")
     ("acc:*w-integrity*" "40.0" "G0: gaps, doubles, crossings What each half of the check is worth. The three are summed and printed as the...")
     ("acc:*w-tangency*" "35.0" "the kink and corner bands What each half of the check is worth. The three are summed and printed as the den...")
     ("acc:*w-noise*" "25.0" "micro share and turning excess What each half of the check is worth. The three are summed and printed as th...")
     ("acc:*snap-dist*" "6.0" "drawing units How near a pick must land to a joint to declare it -- or, on Remove, to drop the declaration...")
     ("acc:*mark-radius*" "4.0" "drawing units Radius of the rings drawn round a finding or a declaration.")
     ("acc:*comb-step*" "12.0" "drawing units per tooth One comb tooth per this much run, and the length of the tooth at the tightest curva...")
     ("acc:*comb-max*" "24.0" "drawing units at the tightest bend One comb tooth per this much run, and the length of the tooth at the tig...")
     ("acc:*label-min*" "4.0" "drawing units Label text is sized against the perimeter, so it reads the same on a 20-foot spa and a 60-foo...")
     ("acc:*label-div*" "200.0" "perimeter divided by this Label text is sized against the perimeter, so it reads the same on a 20-foot spa...")
     ("acc:*flat-curv*" "1.0e-12" "1/drawing units A curvature below this is straight, so the comb is not drawn at all; a tooth shorter than t...")
     ("acc:*flat-tooth*" "1.0e-6" "drawing units A curvature below this is straight, so the comb is not drawn at all; a tooth shorter than thi..."))
    ("ABFIND" "lisp/abfind/ABFIND.lsp"
     ("abf:*style*" "\"CROSS DIMENSIONS\"" "dimension style to use")
     ("abf:*layer*" "\"DIMENSION\"" "layer the dims land on")
     ("abf:*offset*" "0.0" "distance the dimension line is pushed off the tie it measures, drawing units (0.0 = right on the tie -- CDC...")
     ("abf:*point-block*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit pushed off the tie it measures, drawing units (0.0 =...")
     ("abf:*point-layer*" "\"POINTS\"" "layer whose INSERTs are always points, and where the moved point lands once one is chosen points wherever t...")
     ("abf:*point-color*" "6" "colour to give that layer if the drawing somehow lacks it - the magenta the standard uses. An existing POIN...")
     ("abf:*pt-tag*" "\"number\"" "attribute tag on the point block naming the point, as in \"Pt.17\" drawing somehow lacks it - the magenta the...")
     ("abf:*a-name*" "\"A\"" "what the two stakes are numbered naming the point, as in \"Pt.17\"")
     ("abf:*b-name*" "\"B\"" "in the drawing naming the point, as in \"Pt.17\"")
     ("abf:*snap*" "12.0" "a click within this of a survey point takes THAT point naming the point, as in \"Pt.17\"")
     ("abf:*ring-layer*" "\"FGStep\"" "layer the ring round the point that moved, and its note, go on - the same layer BPCALLOUT rings bad points...")
     ("abf:*ring-radius*" "5.0" "ring RADIUS (5 inches) that moved, and its note, go on - the same layer BPCALLOUT rings bad points on")
     ("abf:*note-hgt*" "6.0" "height of the \"Moved Pt.##\" note that moved, and its note, go on - the same layer BPCALLOUT rings bad point...")
     ("abf:*note-prefix*" "\"- \"" "put in front of EVERY note this file writes, one per line. A run that moves or creates several points leave...")
     ("abf:*moved-suffix*" "\"m\"" "added to the number of a point that moved: Pt.17 -> Pt.17m writes, one per line. A run that moves or create...")
     ("abf:*sug-radius*" "3.0" "radius of a suggestion's marker circle - smaller than the ring so the two never read as the same mark that...")
     ("abf:*sug-layer*" "\"ABMOVE-POINTS\"" "the suggestions get a layer of their OWN, never the points layer: they are throwaway, they would inherit th...")
     ("abf:*sug-color*" "2" "colour of that layer, and an entity override to match: yellow, so a suggestion reads as a suggestion whatev...")
     ("abf:*sug-hgt*" "5.0" "height of a suggestion's tag - above the 4\" point numbers, and still narrow enough for the tags to file pas...")
     ("abf:*tag-standoff*" "10.0" "how far off its arc the row of tags hangs, in inches - each tag on a leader from its marker above the 4\" po...")
     ("abf:*tag-gap*" "1.5" "the daylight kept between two tags, between a tag and the other arc's markers, in inches. Along the arc the...")
     ("abf:*tag-width*" "0.8" "a character's width as a fraction of the tag height - how long the strip a click on a tag can land on is ta...")
     ("abf:*locus-color*" "'auto" "colour of the guide line each group of suggestions sits on: grey, so it reads as a guide and not as drawn w...")
     ("abf:*locus-ltype*" "\"DASHED\"" "and its linetype - created at pool scale when the drawing has no linetype by that name group of suggestions...")
     ("abf:*ghost-color*" "1" "colour of the two whole circles ABPCREATE draws round the stakes - everywhere each tape reaches - in abf:*l...")
     ("abf:*dupe-color*" "4" "colour of the ring round each point a number names when it names more than one, and round the stakes of eac...")
     ("abf:*dupe-radius*" "9.0" "radius of that ring - wider than abf:*sug-radius* and than the ring round a moved point, so the three never...")
     ("abf:*line-prefix*" "\"L\"" "what an AB line is called, on screen and at the prompt: the lines are L1, L2, ... in the order their A stak...")
     ("abf:*new-atts*" "nil" "T makes a CREATED point copy the other attribute values of the point it was patterned on (an elevation, a d...")
     ("abf:*foot-steps*" "10" "how many 1-foot steps are offered each way when a tape is swept: 10 up and 10 down, per held stake other at...")
     ("abf:*max-shift*" "120.0" "furthest a suggestion may sit from the reading, in inches. It bounds BOTH families, so the shipped 10 feet...")
     ("abf:*max-sugg*" "nil" "most suggestions per held stake, nil = as many as there are the reading, in inches. It bounds BOTH families...")
     ("abf:*prec*" "4" "rtos precision for every distance printed or written: 4 = 1/16\" nil = as many as there are")
     ("abf:*same-eps*" "0.125" "two suggestions this close are the same place; only one is kept printed or written: 4 = 1/16\"")
     ("abf:*touch*" "0.03125" "two readings that miss each other by less than this are taken as CROSSING, at the spot the two arcs come ne...")
     ("abf:*fuzz*" "1e-6" "zero-length / same-spot tolerance by less than this are taken as CROSSING, at the spot the two arcs come ne...")
     ("abf:*att-height*" "4.0" "height of the moved point's by less than this are taken as CROSSING, at the spot the two arcs come nearest....")
     ("abf:*att-offset*" "'(0.8697246 -3.5316825)" "number, and where it sits relative to the point (both as the ab_pt block has it). The FALLBACK's only: a po...")
     ("abf:*digit-pairs*" "'((\"1\" \"7\") (\"1\" \"4\") (\"3\" \"8\") ; each other, both ways round (\"3\" \"5\") (\"5\" \"6\") (\"6\" \"8\") (\"0\" \"9\") (\"4\" \"9\") (\"7\" \"9\"))" "digits a field sheet confuses for it sits relative to the point (both as the ab_pt block has it). The FALLB..."))
    ("ABHD" "lisp/abhd/abhd.lsp"
     ("*PF-POOL-LAYER*" "\"POOL\"" "layer holding the drawn perimeter guide, and where the kept fit, the bottom and its dims end up ---- 1. DRA...")
     ("*PF-POOL-COLOUR*" "4" "...its colour when ABHD creates it guide, and where the kept fit, the bottom and its dims end up")
     ("*PF-POINT-LAYER*" "\"POINTS\"" "layer holding the survey points as plain POINT entities (ab_pt blocks count on ANY layer) guide, and where...")
     ("*PF-POINT-COLOUR*" "7" "...its colour; only the tutorial ever creates it, for the practice survey as plain POINT entities (ab_pt bl...")
     ("*PF-POINT-BLOCK*" "\"ab_pt\"" "block name whose INSERTs mark survey points; the block's insertion point is taken as the point location eve...")
     ("*PF-PT-TAG*" "\"number\"" "attribute tag on the point block holding the surveyed point number, used to label it as \"Pt.17\"; a block wi...")
     ("*PF-MOVED-MARK*" "\"M\"" "a point number carrying this letter is a MOVED point - ABFIND writes \"17m\" when it copies Pt.17 to a positi...")
     ("*PF-OUT-LAYER*" "\"POOL-FIT\"" "layer the three candidate fits preview on, with their labels is a MOVED point - ABFIND writes \"17m\" when it...")
     ("*PF-OUT-COLOUR*" "3" "...its colour when ABHD creates it (each candidate carries its own, see *PF-COMPARE* below) preview on, wit...")
     ("*PF-MISS-LAYER*" "\"FGStep\"" "layer the \"could not hold this point\" circles and their list go on. This may well be a layer you already us...")
     ("*PF-MISS-COLOUR*" "1" "...its colour when ABHD creates it point\" circles and their list go on. This may well be a layer you alread...")
     ("*PF-MISS-RADIUS*" "4.0" "radius of those circles (4 inches) also the ring on a declared corner and on a point omitted at a Redo poin...")
     ("*PF-HOLD-RADIUS*" "(* 0.5 *PF-MISS-RADIUS*)" "the ring on a HELD point - half size, so it reads apart from a corner ring. Worked out from the line above...")
     ("*PF-WALL-LAYER*" "\"POOL-WALLS\"" "layer the dashed markers for declared straight walls, corners and held points go on (scaffolding: swept whe...")
     ("*PF-WALL-COLOUR*" "8" "...its colour when ABHD creates it declared straight walls, corners and held points go on (scaffolding: swe...")
     ("*PF-BOTTOM-LAYER*" "\"POOL-BOTTOM\"" "legacy: where earlier versions of this command put the bottom geometry and dims. Everything goes on *PF-POO...")
     ("*PF-MARK-LTYPE*" "\"DASHED\"" "linetype of the wall markers and the corner / held / omitted rings. A linetype the drawing already has is u...")
     ("*PF-STUB-LTYPE*" "\"DASHED2\"" "linetype of the two deep-break stubs (wall to hopper corner); created the same way, with half-size dashes t...")
     ("*PF-DIM-FTIN*" "\"SIDE DIMENSION\"" "dimension style stamped on the offset dims NOT anchored to a break point (hopper back, slope waypoints) whe...")
     ("*PF-DIM-IN*" "\"STANDARD INCHES\"" "same dims when the offset was typed in plain inches (42). Either style missing from the drawing falls back...")
     ("*PF-DIM-OFF*" "12.0" "the deep-end dimension string (wall-to-hopper, hopper width, hopper-to-wall) sits this far off the deep bre...")
     ("*PF-LABEL-FRAC*" "20.0" "the on-screen candidate labels (\"1\", \"2\", \"3\" with their figures) and the list of unheld points are sized t...")
     ("*PF-DEFAULT-FIT*" "\"2\"" "the candidate Enter keeps at the choose prompt - \"1\" (tight), \"2\" (as asked) or \"3\" (few). The standard is...")
     ("*PF-SLOW-NOTE*" "150" "above this many distinct points the command says the ordering and fitting will take a little while")
     ("*PF-COMPARE*" "'((\"tight\" 1 \"red\" \"most curves - least error\") (\"asked\" 2 \"yellow\" \"as asked\") (\"few\" 4 \"cyan\" \"fewest curves - still within the distance\"))" "the three candidate fits offered: the command says the ordering and fitting will take a little while")
     ("*PF-SIMP-TOL*" "1.0" "the distance SIMPABHD fits and measures to. SIMPABHD asks no numbers at all, so this is the one it uses in...")
     ("*PF-SIMP-COMPARE*" "'((\"tight\" 1 \"red\" \"most curves - least error\" nil nil nil) (\"pct\" 2 \"yellow\" \"10% off by 1in, a third as many curves\" 0.10 1.0 3.0) (\"hold\" 3 \"green\" \"all but the 3 worst held, half as many\" 3 1.0 2.0) (\"pct\" 4 \"cyan\" \"20% off by 1/2in, a third as many curves\" 0.20 0.5 3.0) (\"few\" 6 \"magenta\" \"fewest curves - still within the distance\" nil nil nil))" "the five candidates SIMPABHD draws measures to. SIMPABHD asks no numbers at all, so this is the one it uses...")
     ("*PF-SIMP-DEFAULT-FIT*" "\"2\"" "the candidate Enter keeps at SIMPABHD's choose prompt. \"2\" is the middle of the road - a tenth of the point...")
     ("*PF-TOL-MAX*" "2.0" "hard ceiling on the max-distance prompt (2 inches): further than that and the line is no longer a trace of...")
     ("*PF-MISS-PCT*" "0.20" "share of the points (rounded UP to a whole point) that may sit off the result by up to the tolerance (an in...")
     ("*PF-ARC-DIV*" "3.0" "the RECOMMENDED curve cap: one curve per this many survey points, rounded to the NEAREST whole curve and ne...")
     ("*PF-ON-EPS*" "0.25" "a point within this of the result counts as ON it; only points off by more than this eat into the miss allo...")
     ("*PF-ON-FRAC*" "0.25" "...and that threshold scales with the distance typed: this fraction of it, whichever of the two is the larg...")
     ("*PF-TIGHT-TOL*" "0.01" "the \"tight\" candidate's accuracy target (units) - what it fits to instead of the distance typed at step 1,...")
     ("*PF-FIT-EPS*" "0.01" "if a single arc misses any of its points by more than this, split it into several arcs that hit exactly (gu...")
     ("*PF-ANCHOR-EPS*" "(* 2.0 *PF-FIT-EPS*)" "an arc \"passes through\" an interior survey point when the point sits within this of it - twice the fit epsi...")
     ("*PF-CORNER-ANG*" "(/ pi 4.0)" "a point that turns more than this (45 deg) is a sharp corner: it may start or end a span but never gets bur...")
     ("*PF-NICE-RADII*" "'(12.0 6.0 1.0)" "preferred arc-radius increments, tried in order: whole feet, half feet, whole inches (drawing units are inc...")
     ("*PF-SNAP-EPS*" "0.02" "a nice-radius snap may move the covered points at most this far beyond where they already sat, and it may n...")
     ("*PF-TANG-TOL*" "(/ pi 22.5)" "wiggle room from perfect tangency at each joint between two arcs (8 degrees). Being ON the points matters m...")
     ("*PF-TANG-STEPS*" "'(1.0 1.25 1.5)" "when nothing fits inside the tangent window, stretch it by these multiples in turn rather than abandon it;...")
     ("*PF-ARC-SLACK*" "(/ pi 3.0)" "how much further than its own points actually turn one arc may sweep (60 degrees). An arc is allowed to cur...")
     ("*PF-FLOAT-GAIN*" "2" "an arc that floats between the points (its middle on no survey point) has to earn its keep: it is taken onl...")
     ("*PF-DROP-PCT*" "0.10" "share of the points (rounded UP) the fit may give up on entirely: left further off than the max distance, c...")
     ("*PF-DROP-MULT*" "2.0" "how far past the max distance a point has to be before the fit may give up on it at all. This is what separ...")
     ("*PF-DROP-GAIN*" "2" "and every point given up must buy at least this many more points of span, or it is held after all. Whole po...")
     ("*PF-CAP-RELAX*" "1.4" "when a fit needs more curves than the cap allows, the whole loop is refitted with the distance multiplied b...")
     ("*PF-CAP-TRIES*" "40" "...and at most this many refits the fewest-curves result seen is kept when the cap is still not met. 40 ste...")
     ("*PF-SNAP*" "12.0" "a CLICK within this of a survey point names that point - at a wall end, a corner, a held point, a break end...")
     ("*PF-PICKUP-EPS*" "3.0" "a survey point within this of the selected perimeter counts as one of ITS points when ADAB gathers or trims...")
     ("*PF-BOTTOM-STEP*" "6.0" "sampling step for the hopper offset curve (6 inches keeps it smooth without a heavy polyline); also how far...")
     ("*PF-BOTTOM-FIT*" "0.25" "merging those samples into long arcs may leave no sample further than this off the drawn curve (a quarter i...")
     ("*PF-SPIKE-TOL*" "2.0" "how far a slope waypoint's offset has to sit against BOTH its neighbours along that side before the run nam...")
     ("*PF-EXACT-EPS*" "0.001" "\"exactly on\" threshold (units): two points closer than this are the same point - duplicates collapse, picks...")
     ("*PF-CHAIN-FUZZ*" "1.0e-4" "endpoint-matching fuzz for chaining exploded segments into one closed loop two points closer than this are...")
     ("*PF-THIN-EPS*" "0.01" "consecutive samples of an offset curve closer than this (a hundredth) collapse to one - a tight offset can...")
     ("*PF-BULGE-CLAMP*" "1.373" "the half-angle a tangent-window edge, or a span's own permitted turn, may reach (radians): its tangent is a...")
     ("*PF-STRAIGHT-R*" "1.0e6" "an arc whose radius reaches this is a straight line for every practical purpose: it is not snapped to a nic...")
     ("*PF-2OPT-PASSES*" "40" "the automatic point ordering uncrosses its loop with 2-opt passes until one improves nothing, or this many..."))
    ("ABLOBF" "lisp/ablobf/ABLOBF.lsp"
     ("*ABL-POOL-LAYER*" "\"POOL\"" "layer the kept run ends up on - ABHD's, so the rest of the toolset can read the result reads this banner an...")
     ("*ABL-POINT-LAYER*" "\"POINTS\"" "layer whose POINTs/INSERTs are always points ABHD's, so the rest of the toolset can read the result")
     ("*ABL-POINT-BLOCK*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit always points")
     ("*ABL-OUT-LAYER*" "\"ABLOBF-FIT\"" "layer the candidate fits go on points wherever they sit")
     ("*ABL-MISS-LAYER*" "\"FGStep\"" "layer the \"could not hold this point\" rings go on; ABLOBF stamps its objects and only erases its own (see a...")
     ("*ABL-MISS-RADIUS*" "4.0" "radius of those rings (4 inches) point\" rings go on; ABLOBF stamps its objects and only erases its own (see...")
     ("*ABL-PT-TAG*" "\"number\"" "attribute tag on the point block naming the point, as in \"Pt.17\" point\" rings go on; ABLOBF stamps its obje...")
     ("*ABL-SNAP*" "12.0" "a CLICK within this of a survey point names that point - at a run end, a stretch end, a corner, a held poin...")
     ("*ABL-WALL-LAYER*" "\"POOL-WALLS\"" "layer for the dashed markers of declared straight stretches point names that point - at a run end, a stretc...")
     ("*ABL-TOL-MAX*" "2.0" "hard ceiling on the max-distance prompt (2 inches) declared straight stretches")
     ("*ABL-COMPARE*" "'((\"tight\" 1 \"red\" \"most curves - least error\") (\"asked\" 2 \"yellow\" \"as asked\") (\"few\" 4 \"cyan\" \"fewest curves - still within the distance\"))" "the three candidate fits offered: prompt (2 inches)")
     ("*ABL-TIGHT-TOL*" "0.01" "the \"tight\" candidate's accuracy target (units) same three aims as ABHD: \"tight\" fits to *ABL-TIGHT-TOL* wi...")
     ("*ABL-EXACT-EPS*" "0.001" "\"exactly on\" threshold (units) target (units)")
     ("*ABL-FIT-EPS*" "0.01" "an arc through an interior point must pass within twice this of it to count as anchored target (units)")
     ("*ABL-ON-EPS*" "0.25" "a point within this of the result counts as ON it; only points off by more eat into the allowance must pass...")
     ("*ABL-MISS-PCT*" "0.15" "share of the points (rounded UP) that may sit off the result by up to the tolerance counts as ON it; only p...")
     ("*ABL-CORNER-ANG*" "(/ pi 4.0)" "a point that turns more than this (45 deg) is a sharp corner: it may start or end a span but never gets bur...")
     ("*ABL-NICE-RADII*" "'(12.0 6.0 1.0)" "preferred arc-radius tiers, tried in order: whole feet, half feet, whole inches (45 deg) is a sharp corner:...")
     ("*ABL-TANG-TOL*" "(/ pi 22.5)" "wiggle room from perfect tangency at each joint (8 degrees) tried in order: whole feet, half feet, whole in...")
     ("*ABL-TANG-STEPS*" "'(1.0 1.25 1.5)" "when nothing fits inside the tangent window, stretch it by these multiples before falling back to a one-poi...")
     ("*ABL-ARC-SLACK*" "(/ pi 3.0)" "how much further than its own points actually turn one arc may sweep (60 degrees). An arc is allowed to cur...")
     ("*ABL-DROP-PCT*" "0.10" "share of the points (rounded UP) the fit may give up on entirely: left further off than the max distance, c...")
     ("*ABL-DROP-MULT*" "2.0" "how far past the max distance a point has to be before the fit may give up on it at all - what separates a...")
     ("*ABL-SNAP-EPS*" "0.02" "a nice-radius snap may move the covered points at most this far beyond where they already sat point has to...")
     ("*ABL-CHAIN-FUZZ*" "1.0e-4" "endpoint-matching fuzz for chaining sketch segments covered points at most this far beyond where they alrea...")
     ("*ABL-FLOAT-GAIN*" "2" "an arc that floats between the points (its middle on no survey point) is taken only when it covers at least...")
     ("*ABL-DROP-GAIN*" "2" "and every point given up must buy at least this many more points of span, or it is held after all points (i...")
     ("*ABL-ON-FRAC*" "0.25" "the on-the-shape threshold scales with the distance typed: this fraction of it, or *ABL-ON-EPS*, whichever...")
     ("*ABL-ANCHOR-EPS*" "(* 2.0 *ABL-FIT-EPS*)" "an arc \"passes through\" an interior survey point when the point sits within this of it - twice the fit epsi...")
     ("*ABL-CAP-RELAX*" "1.4" "when a fit needs more curves than the cap allows, the whole run is refitted with the distance multiplied by...")
     ("*ABL-CAP-TRIES*" "40" "...and at most this many refits the fewest-curves result seen is kept when the cap is still unmet than the...")
     ("*ABL-BULGE-CLAMP*" "1.373" "the half-angle a tangent-window edge, or a span's own permitted turn, may reach (radians): its tangent is a...")
     ("*ABL-STRAIGHT-R*" "1.0e6" "an arc whose radius reaches this is a straight line for every practical purpose: it is not snapped to a nic..."))
    ("ABPCHECK" "lisp/abpcheck/ABPCHECK.lsp"
     ("abp:*pt-layer*" "\"POINTS\"" "layer holding the survey points Where the survey points live, and what a point block calls its number -- AB...")
     ("abp:*pt-block*" "\"ab_pt\"" "block name whose INSERTs mark points Where the survey points live, and what a point block calls its number...")
     ("abp:*pt-tag*" "\"number\"" "the attribute carrying the number Where the survey points live, and what a point block calls its number --...")
     ("abp:*filter*" "'((0 . \"POINT,INSERT,LINE,ARC,CIRCLE,LWPOLYLINE,POLYLINE,SPLINE,ELLIPSE\"))" "What the highlight is allowed to hand the command: the points, the geometry they are measured against, and...")
     ("abp:*uncovered-types*" "'(\"SPLINE\" \"ELLIPSE\")" "The curve types the segment math does not cover. They are counted and named in the report rather than measu...")
     ("abp:*limit*" "1.0" "drawing units (1 inch) How far off the nearest line is too far. The command asks every run and Enter takes...")
     ("abp:*exact-eps*" "1.0e-6" "drawing units Two points closer than this are the same shot, not two.")
     ("abp:*plane-min*" "0.999" "cosine of the tilt, so nearer 1 is stricter How far an entity's extrusion normal (DXF 210) may lean from wo...")
     ("abp:*miss-layer*" "\"ABPCHECK-MISS\"" "The two layers ABPCHECK writes on, created on first use. It never clears a layer wholesale: everything it d...")
     ("abp:*miss-color*" "1" "ACI: the points that are too far off (red) The two layers ABPCHECK writes on, created on first use. It neve...")
     ("abp:*report-layer*" "\"ABPCHECK-REPORT\"" "The two layers ABPCHECK writes on, created on first use. It never clears a layer wholesale: everything it d...")
     ("abp:*report-color*" "3" "ACI (green) The two layers ABPCHECK writes on, created on first use. It never clears a layer wholesale: eve...")
     ("abp:*appid*" "\"ABPCHECK\"" "renaming this orphans earlier runs The two layers ABPCHECK writes on, created on first use. It never clears...")
     ("abp:*flag-color*" "1" "ACI: rows over the limit (red)")
     ("abp:*advice-color*" "4" "ACI: advice, not a failure (cyan)")
     ("abp:*green-scale*" "0.75" "height of a row that checked out")
     ("abp:*report-chars*" "48.0" "report column width, in text heights")
     ("abp:*ring-scale*" "1.2" "ring radius, in report text heights")
     ("abp:*clear-shown*" "10" "rows How many within-limit points are listed before the rest are summed up in one line, so a 200-point surv...")
     ("abp:*report-wide*" "0.25" "The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, short sheet the...")
     ("abp:*report-lead*" "1.66" "The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, short sheet the...")
     ("abp:*report-hmax*" "30.0" "The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, short sheet the...")
     ("abp:*report-hmin*" "200.0" "The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, short sheet the...")
     ("abp:*report-hfall*" "2.5" "drawing units The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, s...")
     ("abp:*report-gap*" "0.05" "The report is scaled to the drawing, as the check family's siblings do it. WIDE: on a wide, short sheet the...")
     ("abp:*title-scale*" "1.5" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("abp:*hdg-gap*" "0.4" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("abp:*head-lines*" "4.5" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("abp:*hdg-lines*" "1.4" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("abp:*row-indent*" "\" \"" "Findings are indented under their heading by this string.")
     ("abp:*dist-mode*" "4" "rtos mode Distances in the report go through (rtos d mode prec): mode 4 is architectural (feet-inches), so...")
     ("abp:*dist-prec*" "4" "2^4 = sixteenths of an inch Distances in the report go through (rtos d mode prec): mode 4 is architectural...")
     ("abp:*tiny*" "1.0e-8" "drawing units A bounding box smaller than this has nothing to scale a report to."))
    ("ALTABCDEF" "lisp/altabcdef/ALTABCDEF.lsp"
     ("altabcdef:*frame-layer*" "\"ALTABCDEF-FRAME\"" "The three output layers and the colours they are created with (AutoCAD colour numbers: 1 red, 2 yellow, 3 g...")
     ("altabcdef:*frame-color*" "1" "The three output layers and the colours they are created with (AutoCAD colour numbers: 1 red, 2 yellow, 3 g...")
     ("altabcdef:*point-layer*" "\"ALTABCDEF-POINTS\"" "The three output layers and the colours they are created with (AutoCAD colour numbers: 1 red, 2 yellow, 3 g...")
     ("altabcdef:*point-color*" "2" "The three output layers and the colours they are created with (AutoCAD colour numbers: 1 red, 2 yellow, 3 g...")
     ("altabcdef:*label-layer*" "\"ALTABCDEF-LABELS\"" "The three output layers and the colours they are created with (AutoCAD colour numbers: 1 red, 2 yellow, 3 g...")
     ("altabcdef:*label-color*" "3" "The three output layers and the colours they are created with (AutoCAD colour numbers: 1 red, 2 yellow, 3 g...")
     ("altabcdef:*text-div*" "120.0" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*text-min*" "0.5" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*marker-scale*" "0.4" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*label-off*" "1.4" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*tag-scale*" "1.4" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*tag-gap*" "1.0" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*tag-drop*" "1.6" "Text height is the longer rectangle side divided by *text-div*, but never under *text-min* inches. Everythi...")
     ("altabcdef:*file-types*" "\"xlsx;xls;xlsm;csv\"" "What the file dialog offers, as a getfiled extension list. CSV is read natively; the Excel formats go throu...")
     ("altabcdef:*hdr-dist*" "'(\"FROM A\" \"FROM B\" \"FROM C\" \"FROM D\")" "Header words that identify the columns, compared upper-case as substrings: a header containing the Nth entr...")
     ("altabcdef:*hdr-name*" "'(\"NAME\" \"POINT\" \"LABEL\")" "Header words that identify the columns, compared upper-case as substrings: a header containing the Nth entr...")
     ("altabcdef:*min-tapes*" "2" "How many distances a row needs before it is plotted at all. Two fix a point up to a mirror, three fix it ou...")
     ("altabcdef:*apos-over*" "1.05" "A reading with no foot mark whose value is more than *apos-over* times the rectangle's diagonal, and whose...")
     ("altabcdef:*impossible*" "1.1" "A reading with no foot mark whose value is more than *apos-over* times the rectangle's diagonal, and whose...")
     ("altabcdef:*fractions*" "'(2 4 8 16 32)" "The denominators an inch fraction may have. A slash-less digit run like \"314\" is rebuilt as the one fractio...")
     ("altabcdef:*log-denom*" "32" "The correction log writes each repaired value back as feet-inches to the nearest 1/*log-denom* of an inch,...")
     ("altabcdef:*fuzz*" "1e-9" "Two lengths closer than this are the same length; also the shortest radius the solver will divide by. In in...")
     ("altabcdef:*solve-iters*" "60" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("altabcdef:*solve-step*" "1e-7" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("altabcdef:*solve-singular*" "1e-12" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("altabcdef:*seed-singular*" "1e-9" "The least-squares fit: at most *solve-iters* Gauss-Newton steps, done when a step moves the point under *so...")
     ("altabcdef:*frame-tol*" "0.001" "The corner self-check accepts a side or diagonal within this many inches of what the entered W and H say it...")
     ("altabcdef:*mirror-min*" "1.0" "Two distances fix a point twice over - once each side of the line joining the two corners they were measure..."))
    ("AUTOBEAD" "lisp/autobead/AUTOBEAD.lsp"
     ("*autobead-offset*" "2.0" "revision stamp; the dated twin is named for it (v0.4 -> REV04)")
     ("*autobead-layer*" "\"Bead Track\"" "revision stamp; the dated twin is named for it (v0.4 -> REV04)")
     ("*autobead-filter*" "\"POOL*\"" "revision stamp; the dated twin is named for it (v0.4 -> REV04)")
     ("*autobead-fuzz*" "0.001" "revision stamp; the dated twin is named for it (v0.4 -> REV04)"))
    ("AUTODIM" "lisp/autodim/AutoDim.lsp"
     ("ad:*foot-when-unitless*" "12.0" "drawing units in one foot when INSUNITS is 0 (unitless) or a unit ad:onefoot does not know: 12 for a drawin...")
     ("ad:*style-plan*" "\"SIDE STANDARD\"" "perimeter sides, arc radii and the stairs (AUTODIM steps 2 and 3, STAIRDIM)")
     ("ad:*style-floor*" "\"STANDARD\"" "the floor dims chains (step 4, FLOORDIM) and the stairs (AUTODIM steps 2 and 3, STAIRDIM)")
     ("ad:*style-over*" "\"STANDARD\"" "the two overall dims (step 5) (step 4, FLOORDIM)")
     ("ad:*style-short*" "\"STANDARD INCHES\"" "anything measuring under ad:*short-feet*, whichever of the three above it would otherwise have been (step 5)")
     ("ad:*style-steps*" "\"STANDARD INCHES\"" "steps drawn in side view: the depth of every step and the overall, in AUTODIM's side-view route and in AUTO...")
     ("ad:*short-feet*" "1.0" "the cut-off for the short style, in feet: a dim measuring LESS than this goes in ad:*style-short*. Exactly...")
     ("ad:*layer*" "nil" "layer AUTODIM, STAIRDIM and FLOORDIM put their dims on: nil = whatever layer is current when the command ru...")
     ("ad:*steps-layer*" "\"DIMENSION\"" "the same for AUTODIMSIDEPOV, whose reference drawing keeps its step dims on a layer of their own; nil = the...")
     ("ad:*layer-color*" "7" "ACI colour a layer gets when it has to be created (7 = white/black) reference drawing keeps its step dims o...")
     ("ad:*text-offsets*" "2.0" "how many text heights a dim stands off its geometry. The stair dims use exactly this; every other dim uses...")
     ("ad:*perim-feet*" "1.0" "perimeter dims sit at least this far outside the plan, heading outwards its geometry. The stair dims use ex...")
     ("ad:*over-feet*" "2.0" "the overall width sits this far above the topmost dim around the plan, the overall height this far left of...")
     ("ad:*near-feet*" "4.0" "how far from the plan a dimension may sit and still count as one of the plan's own when the overall dims lo...")
     ("ad:*steps-feet*" "2.0" "side-view step dims sit this far clear of the flight, and the overall the same again further out sit and st...")
     ("ad:*same-inches*" "0.0625" "INCHES: two points this close (a sixteenth) are the same place and two measurements this close are the same...")
     ("ad:*band-feet*" "1.0" "two dims across the same two points are the same dim when their dimension lines are within this of each oth...")
     ("ad:*angle-tol*" "1e-3" "RADIANS: two lines within this of parallel are parallel (finding the treads), and a line within this of hor...")
     ("ad:*merge-tol*" "1e-4" "DRAWING UNITS: two points closer than this are one. Break points on a floor dims line are merged by it so n...")
     ("ad:*typ-note*" "\" Typ.\"" "appended to the one dim that stands for its group - the wording POOL.LSP already uses for the same job")
     ("ad:*typ-lines*" "2" "equal straight sides it takes before one is noted and the rest left to it; below this count every one is di...")
     ("ad:*typ-curves*" "4" "the same for equal radii. Higher than the sides on purpose: a pair or a trio of matching curves reads bette...")
     ("ad:*typ-default*" "\"Typ\"" "the Enter answer at the question AUTODIM puts before it dimensions the perimeter: \"Typ\" notes a repeated si...")
     ("ad:*square-share*" "0.75" "at least this share of the straight segments must run square - horizontal or vertical - so a sloping pool f...")
     ("ad:*min-risers*" "2" "risers it takes to be a flight. 1 would let a single riser and tread pass - and with it a plan that has one...")
     ("ad:*wall-share*" "0.9" "a vertical at least this share of the profile's full height is the back wall, not a riser - which is also w...")
     ("ad:*join-share*" "0.01" "how far apart, as a share of the profile's height (never less than ad:*same-inches*), the foot of one riser...")
     ("ad:*geom-types*" "\"LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE,INSERT\"" "what makes up a plan: the step-1 highlight keeps these, only these block a perimeter ray, and these are wha...")
     ("ad:*stair-types*" "\"LINE,LWPOLYLINE\"" "what the stairs highlight (step 3, STAIRDIM) and the side-view highlight (AUTODIMSIDEPOV) keep - the tool r..."))
    ("BPCALLOUT" "lisp/bpcallout/BPCALLOUT.lsp"
     ("bp:*layer*" "\"FGStep\"" "layer the rings and the callout text land on - the same layer LHD puts its miss rings on. Created when the...")
     ("bp:*layer-color*" "1" "ACI colour that layer is CREATED with (1 = red). A layer already in the drawing keeps its own text land on...")
     ("bp:*radius*" "5.0" "ring RADIUS (5\" = a 10\" circle) halve it if a 5\" DIAMETER is wanted. Also how far an un-ring click reaches:...")
     ("bp:*snap*" "12.0" "a pick within this of a survey point rings THAT point - the nearest one when several qualify; farther away,...")
     ("bp:*exact-eps*" "0.001" "two ring centres this close are the same spot, so a second click on a ringed survey point un-rings it rathe...")
     ("bp:*text-hgt*" "6.0" "TEXT height of the callout -- the callout text")
     ("bp:*text-gap*" "10.0" "Enter at the text prompt tucks the callout this far to the right of AND below the last ring's centre -- the...")
     ("bp:*pt-prefix*" "\"Pt.\"" "how a point is named, in the callout and on the command line: the prefix + its number, \"Pt.12\" callout this...")
     ("bp:*tail-one*" "\" is bad\"" "what follows the name when ONE point was ringed: \"Pt.12 is bad\" callout and on the command line: the prefix...")
     ("bp:*tail-many*" "\" are bad\"" "...and when two or more were: \"Pt.12, Pt.15 and Pt.20 are bad\" point was ringed: \"Pt.12 is bad\"")
     ("bp:*unknown*" "\"?\"" "the number given to a ring with no readable survey point under it, so it still reads \"Pt.? is bad\" rather t...")
     ("bp:*point-block*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit -- what counts as a survey point. The classifier is...")
     ("bp:*point-layer*" "\"POINTS\"" "layer whose POINTs and INSERTs are always points, whatever block points wherever they sit")
     ("bp:*pt-tag*" "\"number\"" "attribute tag on the point block naming the point. A block without it lends its first attribute that reads..."))
    ("CABHD" "lisp/cabhd/CABHD.lsp"
     ("*CAB-POOL-LAYER*" "\"POOL\"" "layer holding the drawn perimeter stamps the dated twin in releases/ from it (vN.N -> CABHD_MMDDYY_ REVNN),...")
     ("*CAB-POINT-LAYER*" "\"POINTS\"" "layer holding the survey points stamps the dated twin in releases/ from it (vN.N -> CABHD_MMDDYY_ REVNN), s...")
     ("*CAB-POINT-BLOCK*" "\"ab_pt\"" "block name whose INSERTs mark survey points; the block's insertion point is taken as the point location sta...")
     ("*CAB-OUT-LAYER*" "\"POOL-FIT\"" "layer the fitted polyline goes on points; the block's insertion point is taken as the point location")
     ("*CAB-MISS-LAYER*" "\"FGStep\"" "layer the \"could not hold this point\" circles and their list go on. This may well be a layer you already us...")
     ("*CAB-MISS-RADIUS*" "4.0" "radius of those circles (4 inches) point\" circles and their list go on. This may well be a layer you alread...")
     ("*CAB-PT-TAG*" "\"number\"" "attribute tag on the point block holding the surveyed point number, used to label it as \"Pt.17\" point\" circ...")
     ("*CAB-MOVED-MARK*" "\"M\"" "a point number carrying this letter is a MOVED point - ABFIND writes \"17m\" when it copies Pt.17 to a positi...")
     ("*CAB-SNAP*" "12.0" "a CLICK within this of a survey point names that point - at a wall end, a corner, a held point, the cutoff'...")
     ("*CAB-WALL-LAYER*" "\"POOL-WALLS\"" "layer the dashed markers for user-declared straight walls go on point names that point - at a wall end, a c...")
     ("*CAB-TOL-MAX*" "2.0" "hard ceiling on the max-distance prompt (2 inches): further than that and the line is no longer a trace of...")
     ("*CAB-COMPARE*" "'((\"tight\" 1 \"red\" \"most curves - least error\") (\"asked\" 2 \"yellow\" \"as asked\") (\"few\" 4 \"cyan\" \"fewest curves - still within the distance\"))" "the three candidate fits offered: prompt (2 inches): further than that and the line is no longer a trace of...")
     ("*CAB-TIGHT-TOL*" "0.01" "the \"tight\" candidate's accuracy target (units) - what it fits to instead of the distance typed at step 2,...")
     ("*CAB-EXACT-EPS*" "0.001" "\"exactly on\" threshold (units) target (units) - what it fits to instead of the distance typed at step 2, or...")
     ("*CAB-FIT-EPS*" "0.01" "if a single arc misses any of its points by more than this, split it into several arcs that hit exactly tar...")
     ("*CAB-ON-EPS*" "0.25" "a point within this of the result counts as ON it; only points off by more than this eat into the miss allo...")
     ("*CAB-MISS-PCT*" "0.20" "share of the points (rounded UP to a whole point) that may sit off the result by up to the tolerance (an in...")
     ("*CAB-ARC-DIV*" "3.0" "the RECOMMENDED curve cap: one curve per this many survey points the cutoff kept, rounded to the NEAREST wh...")
     ("*CAB-CORNER-ANG*" "(/ pi 4.0)" "a point that turns more than this (45 deg) is a sharp corner: it may start or end a span but never gets bur...")
     ("*CAB-NICE-RADII*" "'(12.0 6.0 1.0)" "preferred arc-radius increments, tried in order: whole feet, half feet, whole inches (drawing units are inc...")
     ("*CAB-TANG-TOL*" "(/ pi 22.5)" "wiggle room from perfect tangency at each joint between two arcs (8 degrees). Being ON the points matters m...")
     ("*CAB-TANG-STEPS*" "'(1.0 1.25 1.5)" "when nothing fits inside the tangent window, stretch it by these multiples in turn rather than abandon it;...")
     ("*CAB-ARC-SLACK*" "(/ pi 3.0)" "how much further than its own points actually turn one arc may sweep (60 degrees). An arc is allowed to cur...")
     ("*CAB-DROP-PCT*" "0.10" "share of the points (rounded UP) the fit may give up on entirely: left further off than the max distance, c...")
     ("*CAB-DROP-MULT*" "2.0" "how far past the max distance a point has to be before the fit may give up on it at all. This is what separ...")
     ("*CAB-SNAP-EPS*" "0.02" "a nice-radius snap may move the covered points at most this far beyond where they already sat, and it may n...")
     ("*CAB-CHAIN-FUZZ*" "1.0e-4" "endpoint-matching fuzz for chaining exploded segments covered points at most this far beyond where they alr...")
     ("*CAB-FLOAT-GAIN*" "2" "an arc that floats between the points (its middle on no survey point) is taken only when it covers at least...")
     ("*CAB-DROP-GAIN*" "2" "and every point given up must buy at least this many more points of span, or it is held after all points (i...")
     ("*CAB-ON-FRAC*" "0.25" "the on-the-shape threshold scales with the distance typed: this fraction of it, or *CAB-ON-EPS*, whichever...")
     ("*CAB-ANCHOR-EPS*" "(* 2.0 *CAB-FIT-EPS*)" "an arc \"passes through\" an interior survey point when the point sits within this of it - twice the fit epsi...")
     ("*CAB-CAP-RELAX*" "1.4" "when a fit needs more curves than the cap allows, the whole run is refitted with the distance multiplied by...")
     ("*CAB-CAP-TRIES*" "40" "...and at most this many refits the fewest-curves result seen is kept when the cap is still unmet than the...")
     ("*CAB-BULGE-CLAMP*" "1.373" "the half-angle a tangent-window edge, or a span's own permitted turn, may reach (radians): its tangent is a...")
     ("*CAB-STRAIGHT-R*" "1.0e6" "an arc whose radius reaches this is a straight line for every practical purpose: it is not snapped to a nic..."))
    ("CCPRECHECK" "lisp/ccprecheck/ccprecheck.lsp"
     ("chk:*note-mark*" "\"NOTE: \"" "The summary is printed to the command line when the walk finishes, one line per thing answered or noted. Th...")
     ("chk:*confirm-mark*" "\"CONFIRMED: \"" "The summary is printed to the command line when the walk finishes, one line per thing answered or noted. Th...")
     ("chk:*ans-sep*" "\" -> \"" "The summary is printed to the command line when the walk finishes, one line per thing answered or noted. Th...")
     ("chk:*val-sep*" "\" = \"" "The summary is printed to the command line when the walk finishes, one line per thing answered or noted. Th...")
     ("chk:*note-echo*" "\"\\n >> \"" "A note is echoed to the command line as it is given, behind this.")
     ("chk:*sum-open*" "\"\\n\\n--- Checklist summary ---\"" "The summary's own furniture: its opening and closing rules, and the indent every line inside it carries.")
     ("chk:*sum-close*" "\"\\n--- End of checklist ---\\n\"" "The summary's own furniture: its opening and closing rules, and the indent every line inside it carries.")
     ("chk:*sum-indent*" "\" \"" "The summary's own furniture: its opening and closing rules, and the indent every line inside it carries.")
     ("chk:*back-words*" "'(\"B\" \"BACK\" \"U\" \"UNDO\")" "A getstring prompt cannot take initget keywords, so \"go back a step\" has to be typed like a note. These are..."))
    ("CDCALLOUT" "lisp/cdcallout/CDCALLOUT.lsp"
     ("cdo:*style*" "\"CROSS DIMENSIONS\"" "dimension style the dims are drawn in. NOT invented when the drawing lacks it: the dims then take the curre...")
     ("cdo:*layer*" "\"DIMENSION\"" "layer the dims land on, ByLayer (colour, linetype and lineweight overrides stripped). Created when the draw...")
     ("cdo:*layer-color*" "7" "ACI colour that layer is CREATED with (7 = white/black). A layer already in the drawing keeps its own (colo...")
     ("cdo:*offset*" "0.0" "distance the dimension line is pushed off the tie it measures. 0.0 = right inbetween, on the tie itself (CD...")
     ("cdo:*exact-eps*" "0.001" "two survey points closer than this sit on the same spot: the tie is refused, nothing to measure pushed off...")
     ("cdo:*point-block*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit -- what counts as a survey point. The classifier is...")
     ("cdo:*point-layer*" "\"POINTS\"" "layer whose INSERTs are always points, whatever block they are points wherever they sit")
     ("cdo:*pt-tag*" "\"number\"" "attribute tag on the point block naming the point. A block without it lends its first attribute that reads...")
     ("cdo:*pick-layer*" "\"CDCALLOUT-PICK\"" "the rings round the points a doubled number names get a layer of their OWN, never the points layer: they ar...")
     ("cdo:*pick-color*" "4" "colour of that layer, and an entity override to match: cyan, so a ring reads as a question and not as drawn...")
     ("cdo:*pick-radius*" "9.0" "radius of one of those rings, in drawing units - wide enough to stand clear of the point block's own number...")
     ("cdo:*pick-hgt*" "5.0" "height of the label beside it - above the 4\" point numbers drawing units - wide enough to stand clear of th...")
     ("cdo:*pick-prefix*" "\"P\"" "what those labels are called, on screen and at the prompt: P1, P2, ... in drawing order above the 4\" point...")
     ("cdo:*prec*" "4" "rtos precision for the distances printed in the table: 4 = 1/16\" screen and at the prompt: P1, P2, ... in d..."))
    ("CDCREATE" "lisp/cdcreate/CDCREATE.lsp"
     ("cdc:*style*" "\"CROSS DIMENSIONS\"" "dimension style the dims are drawn in. NOT invented when the drawing lacks it: the dims then take the curre...")
     ("cdc:*layer*" "\"DIMENSION\"" "layer the dims land on, ByLayer (colour, linetype and lineweight overrides stripped). Created when the draw...")
     ("cdc:*layer-color*" "7" "ACI colour that layer is CREATED with (7 = white/black). A layer already in the drawing keeps its own (colo...")
     ("cdc:*offset*" "0.0" "distance the dimension line is pushed off the line it measures. 0.0 = on the line itself; positive = to the...")
     ("cdc:*textpos*" "0.8" "position of the text along the dimension line, as a fraction of its length measured from the far end toward...")
     ("cdc:*vertang*" "15.0" "degrees off vertical within which a line counts as standing up, so its text goes to the BOTTOM end rather t...")
     ("cdc:*erase*" "T" "T erases each line once its dimension is drawn - the tie is the dimension now; nil keeps them. A line that...")
     ("cdc:*skipdimmed*" "T" "T leaves a line alone when some dimension in model space already runs between its two ends - either way rou...")
     ("cdc:*dupetol*" "nil" "how close two extension-line origins have to be to count as the same point, drawing units. nil = a sixteent..."))
    ("CHECK" "lisp/check/check_drawing.lsp"
     ("*cfchk-tol*" "1.0e-4" "drawing units A dimension point or an arc end that sits within this distance of an object is ATTACHED and l...")
     ("*cfchk-anchor-tol*" "1.0e-4" "drawing units Two dimensions measuring to the same spot make it an ANCHOR: a point that is left exactly whe...")
     ("*cfchk-anchor-min*" "2" "dimensions meeting at one spot ...and how many dimensions must meet there. 2 is the everyday case (the pair...")
     ("*cfchk-curve-types*" "'(\"LINE\" \"ARC\" \"CIRCLE\" \"ELLIPSE\" \"LWPOLYLINE\" \"POLYLINE\" \"SPLINE\")" "Entity types a dimension point or an arc end may attach to. Every name must be a curve AutoCAD can measure...")
     ("*cfchk-dim-types*" "'(0 1)" "Which kinds of dimension are audited, by the low three bits of DXF group 70: 0 = rotated (horizontal / vert...")
     ("*cfchk-dim-color*" "1" "ACI: dimensions whose points were shifted (red)")
     ("*cfchk-arc-color*" "6" "ACI: arcs whose endpoints were snapped (magenta)")
     ("*cfchk-constr-layer*" "\"CHECK-CONSTRUCTION\"" "Construction lines (XLINEs) through the ORIGINAL points of every shifted dimension go on this layer, create...")
     ("*cfchk-constr-color*" "2" "ACI (yellow) Construction lines (XLINEs) through the ORIGINAL points of every shifted dimension go on this...")
     ("*cfchk-dist-mode*" "2" "rtos mode Distances in the command-line report go through (rtos d mode prec): mode 2 is decimal, 3 engineer...")
     ("*cfchk-dist-prec*" "4" "places for a shift or snap distance Distances in the command-line report go through (rtos d mode prec): mod...")
     ("*cfchk-tol-prec*" "6" "places for the tolerance in the summary Distances in the command-line report go through (rtos d mode prec):...")
     ("*cfchk-same-pt*" "1e-8" "drawing units Two points closer than this are the SAME point: no construction line is drawn through them, a...")
     ("*cfchk-planar-eps*" "1e-9" "dimensionless (normal components) An ARC is only audited when its extrusion normal (DXF 210) is within this..."))
    ("CLEARDIM" "lisp/cleardim/CLEARDIM.lsp"
     ("cd:*charwidth*" "0.75" "how wide one glyph is taken to be, as a fraction of the text height. The one estimate in the file: raise it...")
     ("cd:*gap-f*" "0.4" "breathing room left around a text box on every side, as a multiple of the text height. 0.0 asks only that t...")
     ("cd:*step-f*" "0.25" "how far each trial slide steps, as a multiple of the text height. Smaller finds narrower gaps and takes pro...")
     ("cd:*reach-f*" "4.0" "how far a text may slide from where it started, each way, as a multiple of its own width. A text with nothi...")
     ("cd:*refine*" "5" "halvings used to bisect the found spot back toward the original one, so the move is the smallest that still...")
     ("cd:*rowtol-f*" "2.0" "how tall a \"row\" is for reading order, as a multiple of the tallest text in the sweep. Two dimensions insid...")
     ("cd:*track-tol-f*" "0.5" "how far apart two dimension lines may be across their own direction and still be the SAME track, as a multi...")
     ("cd:*run-gap-f*" "6.0" "how big a break may be between two dimensions on one line before they stop reading as one run, as a multipl...")
     ("cd:*row-f*" "2.0" "how far one row out is, as a multiple of the text height -- the unit AUTODIM already stands its own chains...")
     ("cd:*rows*" "3" "how many rows out a run or a staggered dimension may be pushed before the run is left as drawn. A dimension...")
     ("cd:*stagger-max*" "3" "how many rows a run may be staggered ACROSS: 2 is every other dimension a row out, 3 goes out, further out,...")
     ("cd:*stagger*" "T" "whether dimensions on one track that crowd each other may be STAGGERED -- the one in the way pushed out a r...")
     ("cd:*arcsegs*" "32" "chords a full circle is flattened into before it is tested against a text box; an arc gets its share of the...")
     ("cd:*skip-layers*" "'(\"DEFPOINTS\")" "layers whose entities are not ink: nothing on them is treated as an obstacle. DEFPOINTS does not plot, so t...")
     ("cd:*obstacle-types*" "'(\"LINE\" \"LWPOLYLINE\" \"POLYLINE\" \"ARC\" \"CIRCLE\" \"TEXT\" \"MTEXT\")" "entity types read as ink under the")
     ("cd:*dimtxt-default*" "0.18" "DIMTXT to assume when the style record carries none -- AutoCAD's own out-of-the-box value"))
    ("CONSTELLATION" "lisp/constellation/CONSTELLATION.lsp"
     ("cst:*space-layer*" "\"CONSTELLATION-SPACE\"" "the rectangle asked for The layer each part of the result lands on. Point one at a layer the office already...")
     ("cst:*guide-layer*" "\"CONSTELLATION-GUIDE\"" "the starting oval, erased The layer each part of the result lands on. Point one at a layer the office alrea...")
     ("cst:*outline-layer*" "\"CONSTELLATION\"" "the ring through A B C ... The layer each part of the result lands on. Point one at a layer the office alre...")
     ("cst:*dim-layer*" "\"DIMENSION\"" "as AUTODIM and WCALST The layer each part of the result lands on. Point one at a layer the office already u...")
     ("cst:*point-layer*" "\"POINTS\"" "as ABCDEF and XYPLOT The layer each part of the result lands on. Point one at a layer the office already us...")
     ("cst:*space-color*" "'auto" "'auto picks the grey for the background; a number as given The ACI colour each of those layers is CREATED w...")
     ("cst:*guide-color*" "4" "background; a number as given")
     ("cst:*outline-color*" "3" "background; a number as given")
     ("cst:*dim-color*" "2" "background; a number as given")
     ("cst:*point-color*" "2" "background; a number as given")
     ("cst:*point-block*" "\"ab_pt\"" "ABCDEF's survey block and its attribute tag. Move either and ABHD, CABHD, ABFIND, LHD and BPCALLOUT stop re...")
     ("cst:*point-tag*" "\"number\"" "ABCDEF's survey block and its attribute tag. Move either and ABHD, CABHD, ABFIND, LHD and BPCALLOUT stop re...")
     ("cst:*letters*" "\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"" "The labels, in the order they are handed out clockwise. Shortening the string lowers the ceiling below with...")
     ("cst:*minpts*" "3" "The count the run will accept. Raising the floor refuses small jobs the solver can do; the ceiling is read...")
     ("cst:*maxpts*" "(strlen cst:*letters*)" "The count the run will accept. Raising the floor refuses small jobs the solver can do; the ceiling is read...")
     ("cst:*defcount*" "4" "What Enter takes at the count prompt. Set it to the job you do most and the common case becomes one keystro...")
     ("cst:*def-outline*" "\"Yes\"" "What Enter takes at \"Draw the outline through the points in order?\" -- \"No\" to make the ring something aske...")
     ("cst:*sweeps*" "120" "Stress-majorization sweeps only have to get the layout into the right BASIN, which takes a few dozen; stage...")
     ("cst:*tol*" "1.0e-6" "How far the furthest point moved in one sweep, in drawing units, below which sweeping stops early. Lowering...")
     ("cst:*lm-iters*" "40" "The outer steps, and the damping retries allowed inside one of them before the fit is called finished. Lowe...")
     ("cst:*lm-tries*" "8" "The outer steps, and the damping retries allowed inside one of them before the fit is called finished. Lowe...")
     ("cst:*lm-lam*" "1.0e-3" "The damping itself: what it starts at, the floor it may fall to, and what a step that reduced the miss and...")
     ("cst:*lm-lammin*" "1.0e-12" "The damping itself: what it starts at, the floor it may fall to, and what a step that reduced the miss and...")
     ("cst:*lm-down*" "0.1" "The damping itself: what it starts at, the floor it may fall to, and what a step that reduced the miss and...")
     ("cst:*lm-up*" "10.0" "The damping itself: what it starts at, the floor it may fall to, and what a step that reduced the miss and...")
     ("cst:*lm-done*" "1.0e-14" "The sum of squared misses below which there is nothing left to gain -- about a ten-millionth of an inch, RM...")
     ("cst:*squash*" "0.35" "A stress minimum is LOCAL, and a constellation that starts folded can stay folded, so the oval is not the o...")
     ("cst:*shake*" "0.30" "A stress minimum is LOCAL, and a constellation that starts folded can stay folded, so the oval is not the o...")
     ("cst:*rot-coarse*" "360" "The solved shape is spun to sit in the space: the whole circle sampled *rot-coarse* ways, then *rot-passes*...")
     ("cst:*rot-fine*" "40" "The solved shape is spun to sit in the space: the whole circle sampled *rot-coarse* ways, then *rot-passes*...")
     ("cst:*rot-passes*" "3" "The solved shape is spun to sit in the space: the whole circle sampled *rot-coarse* ways, then *rot-passes*...")
     ("cst:*flag*" "0.25" "How far a dim or an arc radius may end up from what was given before it is starred and the leave-one-out te...")
     ("cst:*over-tol*" "1.0e-6" "How far the points may reach past the space, the two axes added, before the report says so. Raise it to sto...")
     ("cst:*texth*" "0.025" "Label height, preview marker radius and how far a perimeter dim stands off, as shares of the smaller side o...")
     ("cst:*dotr*" "0.008" "Label height, preview marker radius and how far a perimeter dim stands off, as shares of the smaller side o...")
     ("cst:*dimoff*" "0.060" "Label height, preview marker radius and how far a perimeter dim stands off, as shares of the smaller side o...")
     ("cst:*texth-min*" "0.5" "Floors under the first two, in drawing units, so a tiny space still gets a label that can be read and a mar...")
     ("cst:*dotr-min*" "0.1" "Floors under the first two, in drawing units, so a tiny space still gets a label that can be read and a mar..."))
    ("COVERCHECK" "lisp/covercheck/covercheck.lsp"
     ("*cchk-pool-layer*" "\"POOL\"" "The pool outline and, when one is drawn, the cover. Both are read for their ByLayer properties, so these ar...")
     ("*cchk-cover-layer*" "\"COVER\"" "The pool outline and, when one is drawn, the cover. Both are read for their ByLayer properties, so these ar...")
     ("*cchk-perim-layers*" "'(\"CABLE\")" "Layers OTHER than the pool layer that may carry a stretch of the SAME closed perimeter -- the cable run dra...")
     ("*cchk-pool-note*" "\"Pool Size Shown\"" "When no cover is drawn the sheet has to say which size IS shown. Both notes together is an error -- a sheet...")
     ("*cchk-spa-note*" "\"Spa Size Shown\"" "When no cover is drawn the sheet has to say which size IS shown. Both notes together is an error -- a sheet...")
     ("*cchk-details-block*" "\"Cover Details\"" "The block carrying Overlap and Spacing, the block a replacement drawing has to carry, and the linetype name...")
     ("*cchk-repl-block*" "\"Replacement Disclaimer\"" "The block carrying Overlap and Spacing, the block a replacement drawing has to carry, and the linetype name...")
     ("*cchk-dashed-pat*" "\"*DASH*,*HIDDEN*\"" "wcmatch, case-blind The block carrying Overlap and Spacing, the block a replacement drawing has to carry, a...")
     ("*cchk-overlap-vals*" "'(12.0 15.0 18.0)" "The only overlaps that exist, in inches. A drawing carrying anything else is wrong, not merely unusual.")
     ("*cchk-area-small*" "1200.0" "square feet Water area decides which: under SMALL -> 12\" overlap and 5x5 spacing, over LARGE -> 18\" and 3x3...")
     ("*cchk-area-large*" "2000.0" "square feet Water area decides which: under SMALL -> 12\" overlap and 5x5 spacing, over LARGE -> 18\" and 3x3...")
     ("*cchk-pad-size*" "36.0" "drawing units Pads are suggested at this size (PADDLE's big pad), and these block names, on this layer, cou...")
     ("*cchk-pad-blocks*" "'(\"Pad36x36\" \"Pad24x24\")" "Pads are suggested at this size (PADDLE's big pad), and these block names, on this layer, count as a pad th...")
     ("*cchk-pads-layer*" "\"PADS\"" "Pads are suggested at this size (PADDLE's big pad), and these block names, on this layer, count as a pad th...")
     ("*cchk-pad-near*" "18.0" "drawing units A pad centre within this of a spot (Chebyshev distance -- the pad is a square) already covers...")
     ("*cchk-pad-maxrad*" "54.0" "drawing units The largest concave radius that still needs pads: a gentler curve than 4'-6\" does not pull th...")
     ("*cchk-pad-cornertol*" "(/ (* 30.0 pi) 180.0)" "30 degrees, in radians A joint bending less than CORNERTOL is semi-straight rather than an inside corner; a...")
     ("*cchk-pad-arctol*" "(/ (* 10.0 pi) 180.0)" "10 degrees, in radians A joint bending less than CORNERTOL is semi-straight rather than an inside corner; a...")
     ("*cchk-chain-fuzz*" "0.05" "drawing units The widest gap that still chains two ends of an exploded outline into one loop. Raising it cl...")
     ("*cchk-title-block*" "\"Tech Title\"" "The title block and the attribute in it carrying the date; the date must read today, written MM/DD/YYYY. Sp...")
     ("*cchk-date-tag*" "\"Date\"" "The title block and the attribute in it carrying the date; the date must read today, written MM/DD/YYYY. Sp...")
     ("*cchk-block-depth*" "3" "levels How many levels of nested block to search when looking for a name or a piece of text. Raising it fin...")
     ("*cchk-tut-layer*" "\"TUTORIAL-COVERCHECK-DEMO\"" "The layer TUTORIALCOVERCHECK draws its non-pool demo geometry on.")
     ("*cchk-tol*" "1.0e-4" "drawing units A dimension point or an arc end within this distance of an object is ATTACHED and is not ques...")
     ("*cchk-anchor-tol*" "1.0e-4" "drawing units How close two dimension points must be to count as the same spot...")
     ("*cchk-anchor-min*" "2" "dimensions meeting at one spot ...and how many dimensions must meet there to make it an ANCHOR: a point lef...")
     ("*cchk-curve-types*" "'(\"LINE\" \"ARC\" \"CIRCLE\" \"ELLIPSE\" \"LWPOLYLINE\" \"POLYLINE\" \"SPLINE\")" "Entity types a dimension point or an arc end may attach to. Each must be a curve AutoCAD can measure to (vl...")
     ("*cchk-ask-all-arc-ends*" "nil" "T = confirm EVERY arc endpoint, even ones already attached.")
     ("*cchk-olap-fuzz*" "1.0e-4" "drawing units, sideways offset How far apart two parallel lines may sit and still be called the same line....")
     ("*cchk-olap-dirtol*" "0.5" "degrees Two segments are only tested for overlap when their directions are within this of each other. It is...")
     ("*cchk-olap-types*" "'(\"LINE\" \"LWPOLYLINE\" \"POLYLINE\")" "Entity types whose straight segments take part in overlap detection. Arcs, circles and splines have no stra...")
     ("*cchk-style-order*" "'(\"STANDARD\" \"SIDE STANDARD\" \"STANDARD INCHES\" \"CROSS DIMENSIONS\")" "Dimension styles are reviewed in this order; styles not listed come afterwards (\"whatever else is left\"), s...")
     ("*cchk-dim-layer*" "\"DIMENSION\"" "Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what t...")
     ("*cchk-dimfix-cmd*" "\"CDIM\"" "Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what t...")
     ("*cchk-row-band*" "0.05" "fraction of the selection's height Within a style, dimensions are reviewed row by row. Two dimensions count...")
     ("*cchk-row-flat*" "1.0" "...and the band for a selection with no height Within a style, dimensions are reviewed row by row. Two dime...")
     ("*cchk-grey-color*" "'auto" "ACI: everything not under review, faded. 'auto fades it the way round the drawing needs -- darker than the...")
     ("*cchk-flag-color*" "'auto" "ACI: what you answered \"No\" to (red) 'auto fades it the way round the drawing needs -- darker than the work...")
     ("*cchk-arc-color*" "'auto" "ACI: arcs whose endpoints were moved (magenta) 'auto fades it the way round the drawing needs -- darker tha...")
     ("*cchk-olap-color*" "'auto" "ACI: merged or flagged overlapping lines (cyan) 'auto fades it the way round the drawing needs -- darker th...")
     ("*cchk-orig-color*" "'auto" "ACI: the X marking where you drew the point (red) 'auto fades it the way round the drawing needs -- darker...")
     ("*cchk-sugg-color*" "'auto" "ACI: the + marking where COVERCHECK would put it (green) 'auto fades it the way round the drawing needs --...")
     ("*cchk-point-color*" "'auto" "ACI: the crosses marking an overlap's two ends (yellow) 'auto fades it the way round the drawing needs -- d...")
     ("*cchk-constr-layer*" "\"COVERCHECK-CONSTRUCTION\"" "The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are c...")
     ("*cchk-constr-color*" "'auto" "ACI (yellow) The construction XLINE through a moved dimension's original points, and the report MTEXT. Both...")
     ("*cchk-report-layer*" "\"COVERCHECK-REPORT\"" "The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are c...")
     ("*cchk-report-color*" "'auto" "ACI (green) The construction XLINE through a moved dimension's original points, and the report MTEXT. Both...")
     ("*cchk-green-scale*" "0.75" "All-clear lines are written at this fraction of the height the red attention lines get, so problems stand o...")
     ("*cchk-report-chars*" "45.0" "Report column width, in text heights.")
     ("*cchk-report-wide*" "0.25" "The report is scaled to the drawing: its text height is chosen so the whole report is about as tall as the...")
     ("*cchk-report-lead*" "1.66" "MTEXT line pitch as a multiple of text height, used to turn a line count into a height. AutoCAD's default s...")
     ("*cchk-report-hmax*" "30.0" "...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both ar...")
     ("*cchk-report-hmin*" "200.0" "...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both ar...")
     ("*cchk-report-hfall*" "2.5" "drawing units The height used when the selection has no extents to scale against (DIMTXT x DIMSCALE is trie...")
     ("*cchk-report-gap*" "0.05" "Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around th...")
     ("*cchk-zoom-out*" "0.05" "Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around th...")
     ("*cchk-zoom-margin*" "0.75" "Empty space around ONE item when the review zooms to it, as a fraction of its size.")
     ("*cchk-mark-size*" "0.02" "fraction of VIEWSIZE Half-size of the X and + markers drawn while you answer, as a fraction of the current...")
     ("*cchk-attn-words*" "\"*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*NOT ATTACHED*,*OVERLAP*,*ASSOCIATIVE*,*DISAGREE*,*SUGGEST*,*BLANK*,*UNREADABLE*,*NOT A POLYLINE*,*LOOK AT*,*NO DASHED*,*AMBIGUOUS*,*ONLY ONE SIZE*,*NO INCHES*,*NOT TODAY*,*EXPECTED MM/DD/YYYY*,*NEEDS UPDATING*,*UPDATED TO*\"" "A report line is rendered red and full-size when it matches this pattern (wcmatch, case-blind; comma separa...")
     ("*cchk-dist-mode*" "2" "rtos mode Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engineeri...")
     ("*cchk-dist-prec*" "4" "decimal places Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engi...")
     ("*cchk-same-pt*" "1e-8" "drawing units Two points closer than this are the SAME point: no construction line is drawn through them, n...")
     ("*cchk-planar-eps*" "1e-9" "dimensionless (normal components) How far an arc's extrusion normal (DXF 210) may lean from world +Z and st...")
     ("*cchk-flat-eps*" "1e-12" "---------------------------------------------------------------------- Below this a polyline bulge is treat..."))
    ("CUSTBLOCK" "lisp/custblock/CUSTBLOCK.lsp"
     ("cbk:*layer*" "\"COVER\"" "the block itself")
     ("cbk:*laycolor*" "7" "")
     ("cbk:*dimlayer*" "\"DIMENSION\"" "its dimensions")
     ("cbk:*dimcolor*" "141" "")
     ("cbk:*style*" "\"STANDARD INCHES\"" "")
     ("cbk:*dimoff*" "12.0" "dim line stand-off, units")
     ("cbk:*sysold*" "nil" "sysvar snapshot, live mid-run")
     ("cbk:*last-len*" "nil" "the previous block's sizes -")
     ("cbk:*last-wid*" "nil" "session memory, offered as")
     ("cbk:*last-hgt*" "nil" "<defaults> that Enter accepts"))
    ("DIMCHECK" "lisp/dimcheck/dimcheck.lsp"
     ("*dchk-tol*" "1.0e-4" "drawing units A dimension point or an arc end within this distance of an object is ATTACHED and is not ques...")
     ("*dchk-anchor-tol*" "1.0e-4" "drawing units How close two dimension points must be to count as the same spot...")
     ("*dchk-anchor-min*" "2" "dimensions meeting at one spot ...and how many dimensions must meet there to make it an ANCHOR: a point lef...")
     ("*dchk-curve-types*" "'(\"LINE\" \"ARC\" \"CIRCLE\" \"ELLIPSE\" \"LWPOLYLINE\" \"POLYLINE\" \"SPLINE\")" "Entity types a dimension point or an arc end may attach to. Each must be a curve AutoCAD can measure to (vl...")
     ("*dchk-ask-all-arc-ends*" "nil" "T = confirm EVERY arc endpoint, even ones already attached.")
     ("*dchk-olap-fuzz*" "1.0e-4" "drawing units, sideways offset How far apart two parallel lines may sit and still be called the same line....")
     ("*dchk-olap-dirtol*" "0.5" "degrees Two segments are only tested for overlap when their directions are within this of each other. It is...")
     ("*dchk-olap-types*" "'(\"LINE\" \"LWPOLYLINE\" \"POLYLINE\")" "Entity types whose straight segments take part in overlap detection. Arcs, circles and splines have no stra...")
     ("*dchk-style-order*" "'(\"STANDARD\" \"SIDE STANDARD\" \"STANDARD INCHES\" \"CROSS DIMENSIONS\")" "Dimension styles are reviewed in this order; styles not listed come afterwards (\"whatever else is left\"), s...")
     ("*dchk-row-band*" "0.05" "fraction of the selection's height Within a style, dimensions are reviewed row by row. Two dimensions count...")
     ("*dchk-row-flat*" "1.0" "...and the band for a selection with no height Within a style, dimensions are reviewed row by row. Two dime...")
     ("*dchk-grey-color*" "'auto" "ACI: everything not under review, faded. 'auto fades it the way round the drawing needs -- darker than the...")
     ("*dchk-flag-color*" "'auto" "ACI: dimensions you answered \"No\" to (red) 'auto fades it the way round the drawing needs -- darker than th...")
     ("*dchk-arc-color*" "'auto" "ACI: arcs whose endpoints were moved (magenta) 'auto fades it the way round the drawing needs -- darker tha...")
     ("*dchk-olap-color*" "'auto" "ACI: merged or flagged overlapping lines (cyan) 'auto fades it the way round the drawing needs -- darker th...")
     ("*dchk-orig-color*" "'auto" "ACI: the X marking where you drew the point (red) 'auto fades it the way round the drawing needs -- darker...")
     ("*dchk-sugg-color*" "'auto" "ACI: the + marking where DIMCHECK would put it (green) 'auto fades it the way round the drawing needs -- da...")
     ("*dchk-point-color*" "'auto" "ACI: the crosses marking an overlap's two ends (yellow) 'auto fades it the way round the drawing needs -- d...")
     ("*dchk-constr-layer*" "\"DIMCHECK-CONSTRUCTION\"" "The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are c...")
     ("*dchk-constr-color*" "'auto" "ACI (yellow) The construction XLINE through a moved dimension's original points, and the report MTEXT. Both...")
     ("*dchk-report-layer*" "\"DIMCHECK-REPORT\"" "The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are c...")
     ("*dchk-report-color*" "'auto" "ACI (green) The construction XLINE through a moved dimension's original points, and the report MTEXT. Both...")
     ("*dchk-green-scale*" "0.75" "All-clear lines are written at this fraction of the height the red attention lines get, so problems stand o...")
     ("*dchk-report-chars*" "45.0" "Report column width, in text heights.")
     ("*dchk-sheet-chars*" "70.0" "...and the width of TUTORIALDIMCHECK's reference sheet, which is prose rather than a column of findings and...")
     ("*dchk-report-wide*" "0.25" "The report is scaled to the drawing: its text height is chosen so the whole report is about as tall as the...")
     ("*dchk-report-lead*" "1.66" "MTEXT line pitch as a multiple of text height, used to turn a line count into a height. AutoCAD's default s...")
     ("*dchk-report-hmax*" "30.0" "...then the height is clamped, so a three-line report on a big sheet is not gigantic and a 200-line one is...")
     ("*dchk-report-hmin*" "200.0" "...then the height is clamped, so a three-line report on a big sheet is not gigantic and a 200-line one is...")
     ("*dchk-report-hfall*" "2.5" "drawing units The height used when the selection has no extents to scale against (DIMCHECK tries DIMTXT x D...")
     ("*dchk-report-gap*" "0.05" "Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around th...")
     ("*dchk-zoom-out*" "0.05" "Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around th...")
     ("*dchk-zoom-margin*" "0.75" "Empty space around ONE item when the review zooms to it, as a fraction of its size.")
     ("*dchk-mark-size*" "0.02" "fraction of VIEWSIZE Half-size of the X and + markers drawn while you answer, as a fraction of the current...")
     ("*dchk-attn-words*" "\"*FLAGGED*,*SKIPPED*,*ENDPOINT(S) MOVED*,*ASSOCIATIVE*,*NOT ATTACHED*,*OVERLAP*\"" "A report line is rendered red and full-size when it matches this pattern (wcmatch, case-blind; comma separa...")
     ("*dchk-dist-mode*" "2" "rtos mode Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engineeri...")
     ("*dchk-dist-prec*" "4" "decimal places Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engi...")
     ("*dchk-same-pt*" "1e-8" "drawing units Two points closer than this are the SAME point: no construction line is drawn through them, n...")
     ("*dchk-planar-eps*" "1e-9" "dimensionless (normal components) How far an arc's extrusion normal (DXF 210) may lean from world +Z and st...")
     ("*dchk-flat-eps*" "1e-12" "---------------------------------------------------------------------- Below this a polyline bulge is treat..."))
    ("DIMSTAMP" "lisp/dimstamp/DIMSTAMP.lsp"
     ("ds:*layer*" "\"TEXT\"" "layer the stamped MTEXT lands on. Created when the drawing lacks it; thawed, unlocked and switched on when...")
     ("ds:*layer-color*" "7" "ACI colour that layer is CREATED with -- 7 is AutoCAD's own black-on-white/white-on-black swap. A layer alr...")
     ("ds:*style*" "\"Attributes\"" "text style the stamp is written in. A drawing without it gets a plain variable-height style of that name ma...")
     ("ds:*text-hgt*" "6.0" "MTEXT height of a stamp in. A drawing without it gets a plain variable-height style of that name made, and...")
     ("ds:*text-width*" "0.0" "its defined (wrap) width; 0 is no wrap at all, so a value can never break across two lines in. A drawing wi...")
     ("ds:*line-space*" "1.0" "line space factor, at the \"at least\" spacing style wrap at all, so a value can never break across two lines")
     ("ds:*stack*" "\"/\"" "what separates a STACKED fraction's numerator from its denominator in the drawn MTEXT: \"/\" is the one over...")
     ("ds:*stack-hgt*" "1.0" "how tall that stacked fraction is drawn, as a factor of the text around it. 1.0 is the size of the whole in...")
     ("ds:*stack-align*" "1" "where that fraction sits against the line it is on: 0 bottom, 1 centred, 2 top, and 1 is what the shop's ow...")
     ("ds:*ruler-layer*" "\"DIMSTAMP RULER\"" "layer the scratch ruler is drawn on -- its own, so the TEXT layer never carries scratch -- the ruler. Scrat...")
     ("ds:*ruler-color*" "3" "ACI colour of the ruler, on the entities themselves so it reads the same whatever its layer says drawn on -...")
     ("ds:*ruler-screen-x*" "0.88" "where the spine sits across the view: a fraction of the view's WIDTH in from its LEFT edge, so 0.88 is near...")
     ("ds:*ruler-row-frac*" "0.042" "one row's share of the view's HEIGHT -- the ruler's whole size knob. Raise it for a bigger ruler with fewer...")
     ("ds:*ruler-txt-frac*" "0.5" "the biggest row label's height, as a fraction of the row spacing HEIGHT -- the ruler's whole size knob. Rai...")
     ("ds:*ruler-tick-frac*" "0.6" "the longest tick, same measure as a fraction of the row spacing")
     ("ds:*ring-frac*" "0.26" "the ring round the CURRENT row, as a fraction of the row spacing. Bigger than a tick is long on purpose: th...")
     ("ds:*current-color*" "nil" "ACI colour of that current row -- nil is ByLayer, and since the row is drawn on the STAMP's layer that mean...")
     ("ds:*ruler-reach*" "6.0" "how far INBOARD of the spine -- the way the rows run -- in row spacings, a click still counts as picking a..."))
    ("DRONOTE" "lisp/dronote/DRONOTE.lsp"
     ("dn:*layer*" "\"TEXT\"" "layer every note lands on - the shop's own text layer, the one its note blocks and DIMSTAMP's stamps are al...")
     ("dn:*layer-color*" "4" "ACI colour that layer is CREATED with (4 = cyan, what the office template carries). A layer already in the...")
     ("dn:*style*" "\"Attributes\"" "text style a note is written in - the shop's own. A drawing without it gets a variable-height style of that...")
     ("dn:*style-font*" "\"arialbd.ttf\"" "font a style MADE here is built on; one already in the drawing keeps its own the shop's own. A drawing with...")
     ("dn:*text-hgt*" "9.5" "MTEXT height of a placed note font a style MADE here is built on; one already in the drawing keeps its own")
     ("dn:*text-width*" "440.1875" "MTEXT reference width, so a long note wraps instead of running clear across the sheet - the width the shop'...")
     ("dn:*line-space*" "1.0" "line space factor, at the \"at least\" spacing style: what sets the note under its header note wraps instead...")
     ("dn:*header*" "\"*All listed issues must be resolved to proceed with design*\"" "the standing first line of every note, the shop's own wording. \"\" writes the note with no header over it le...")
     ("dn:*bullet*" "\"- \"" "what the note itself is prefixed with under that header the standing first line of every note, the shop's o..."))
    ("FITABHD" "lisp/fitabhd/FITABHD.lsp"
     ("fit:*pool-layer*" "\"POOL\"" "layer the kept fit and bottom go on ---- configuration ---------------------------------------------------")
     ("fit:*point-layer*" "\"POINTS\"" "layer holding plain survey POINTs ---- configuration ---------------------------------------------------")
     ("fit:*point-block*" "\"ab_pt\"" "block whose INSERTs mark survey points; insertion point = location ---- configuration ---------------------...")
     ("fit:*pt-tag*" "\"number\"" "attribute tag carrying the point number, for the miss report points; insertion point = location")
     ("fit:*snap*" "12.0" "a CLICK within this of a survey point names that point, at the Redo's omit prompt. A typed number never use...")
     ("fit:*moved-mark*" "\"M\"" "a point number carrying this letter is a MOVED point - ABFIND writes \"17m\" when it copies Pt.17 to a positi...")
     ("fit:*out-layer*" "\"POOL-FIT\"" "layer the preview outline goes on is a MOVED point - ABFIND writes \"17m\" when it copies Pt.17 to a position...")
     ("fit:*miss-layer*" "\"FGStep\"" "layer the stray-point rings go on may already be in use, so FITABHD stamps its objects and only ever erases...")
     ("fit:*miss-radius*" "4.0" "radius of those rings (4 inches) may already be in use, so FITABHD stamps its objects and only ever erases...")
     ("fit:*exact-eps*" "0.001" "duplicate-point fuzz (units) may already be in use, so FITABHD stamps its objects and only ever erases its own")
     ("fit:*on-eps*" "0.25" "a point within this of the outline counts as ON it (ABHD's threshold) may already be in use, so FITABHD sta...")
     ("fit:*tol-max*" "2.0" "ceiling on the max-distance prompt (2 inches): looser than that and the fit is no longer a trace counts as...")
     ("fit:*corner-zone*" "18.0" "starting radius of the corner zones: points inside belong to the corner feature, not the walls (2 inches):...")
     ("fit:*zone-pad*" "4.0" "the zone refit sizes itself to 1.2 x the fitted radius plus this zones: points inside belong to the corner...")
     ("fit:*icp-iters*" "12" "assignment/update rounds per placement - each is cheap and the walls settle in well under this 1.2 x the fi...")
     ("fit:*rad-iters*" "15" "centre/radius rounds for a Round placement - each is cheap and the walls settle in well under this")
     ("fit:*rad-max*" "120.0" "fillet-radius search ceiling (10') placement - each is cheap and the walls settle in well under this")
     ("fit:*rad-turn-min*" "(/ pi 3.0)" "only corners turning at least this (60 deg) vote for the shared radius or cut: a 45-degree bend's fillet ap...")
     ("fit:*both-edge*" "0.8" "a both-ends cap fit must beat the best single-ended one by this factor: a big flat arc can always shave a l...")
     ("fit:*snap-eps*" "0.02" "a nice-dim snap may move the fit at most this far beyond where it already sat when a stray point is past th...")
     ("fit:*vsize-min*" "1.0" "a fitted corner easing smaller than this reads as sharp at most this far beyond where it already sat when a...")
     ("fit:*miss-pct*" "0.15" "the standard share of the points allowed to sit beyond the distance; asked per run, and what a snap to a wh...")
     ("fit:*bow-min*" "1.0" "a bow shallower than this reads as a straight wall - an inch over thirty feet is drafting noise, and survey...")
     ("fit:*bow-max*" "12.0" "a wall bowed more than a foot is not a straight wall any more a straight wall - an inch over thirty feet is...")
     ("fit:*bow-max-frac*" "0.04" "nor one bowed more than this share of its own length not a straight wall any more")
     ("fit:*bow-pts-min*" "4" "and one shot fewer times than this cannot tell a bow from noise of its own length")
     ("fit:*oos-max*" "(/ pi 36.0)" "how far a wall may swing off its template direction (5 degrees): further than that and the survey is not th...")
     ("fit:*cap-oos-max*" "(/ pi 18.0)" "how far a Roman or Oval side wall may lean, and how far the two may diverge from each other (10 degrees). A...")
     ("fit:*arc-pts-min*" "3" "points each arc of a run needs before it means anything - and so, the only thing that limits how many arcs...")
     ("fit:*tang-tol*" "(/ pi 22.5)" "ABHD's own tangency window (8 degrees): how far the next arc of a run may start off the tangent the last on...")
     ("fit:*tang-steps*" "'(1.0 1.25 1.5)" "when nothing inside the window holds the points, stretch it by these in turn rather than abandon it - ABHD'...")
     ("fit:*oos-min*" "1.0" "the drift from one end of a wall to the other below which the wall reads as true and is held there holds th...")
     ("fit:*feat-snap*" "0.1" "snapping a MEASURED feature (a corner radius, a cut face, a roman end radius) may grow the worst deviation...")
     ("fit:*nice-dims*" "'(12.0 6.0 1.0 0.5)" "snapping increments, tried in order: whole feet, half feet, inches, half inches corner radius, a cut face,...")
     ("fit:*oas-fuzz*" "1.0e-6" "OASIS's own fuzz, for the ring in order: whole feet, half feet, inches, half inches")
     ("fit:*oas-huge*" "1.0e18" "the score of a ring that will not build in order: whole feet, half feet, inches, half inches")
     ("fit:*oas-line*" "20.0" "a joiner radius past this many envelope-sides has flattened into the straight run it is drawn as - the reve...")
     ("fit:*oas-rmin*" "0.04" "and the smallest joiner radius worth hunting, as a share of that side envelope-sides has flattened into the...")
     ("fit:*oas-astep*" "(/ pi 12.0)" "the coarse frame sweep's step (15 degrees). An oasis has no walls to vote on its rotation the way every oth...")
     ("fit:*oas-aspan*" "(/ pi 9.0)" "how far the angle hunts either way on the first round (20 degrees), halving on each one after it degrees)....")
     ("fit:*oas-apart*" "(/ pi 7.2)" "and how far apart two coarse placements have to sit (25 degrees) to count as different tries: three tries a...")
     ("fit:*oas-tries*" "3" "how many of them get a real fit placements have to sit (25 degrees) to count as different tries: three trie...")
     ("fit:*oas-coarse*" "26" "points the coarse sweep works on, and placements have to sit (25 degrees) to count as different tries: thre...")
     ("fit:*oas-rough*" "40" "the early rounds of a real fit: where a pool SITS is a question about the shape of the survey, not about ho...")
     ("fit:*oas-grid*" "6" "grid samples per parameter per pass a pool SITS is a question about the shape of the survey, not about how...")
     ("fit:*oas-gold*" "8" "golden-section rounds after the grid a pool SITS is a question about the shape of the survey, not about how...")
     ("fit:*oas-rounds*" "5" "shape/envelope/angle rounds per fit a pool SITS is a question about the shape of the survey, not about how...")
     ("fit:*oas-narrow*" "'(nil nil 0.35 0.20)" "the band each round hunts, as a share of the full range. TWO rounds look over the whole range before any na...")
     ("fit:*oas-edge*" "0.8" "a kidney fitted the freer way must beat the tighter one by this, like a both-ends cap: extra freedom is not...")
     ("fit:*types*" "\"Rectangle Grecian ROman Oval L LAzyl ROUnd OAsis\"" "POOL's shape vocabulary, minus the shapes a template cannot say (Octagon rides Grecian, Mutt and freeform a...")
     ("fit:*oas-fams*" "\"Center TopRight CLoud Kidney NXTcloud\"" "OASIS's own first question, in OASIS's own words. The sub-type each of two of them asks for is NOT here: wh...")
     ("fit:*dim-off*" "12.0" "the K/L/M string sits this far off the deep break, on the shallow side OASIS's own first question, in OASIS...")
     ("fit:*ptype*" "fit:*ptype*" "The rest of the answers a session remembers, so a second run is mostly Enter. Reading an unset symbol yield...")
     ("fit:*treat*" "fit:*treat*" "The rest of the answers a session remembers, so a second run is mostly Enter. Reading an unset symbol yield...")
     ("fit:*gtreat*" "fit:*gtreat*" "The rest of the answers a session remembers, so a second run is mostly Enter. Reading an unset symbol yield...")
     ("fit:*oasfam*" "fit:*oasfam*" "The rest of the answers a session remembers, so a second run is mostly Enter. Reading an unset symbol yield...")
     ("fit:*rect-dirs*" "(list 0.0 (/ pi 2.0) pi (* pi 1.5))" "the template wall directions, one CCW ring per type (see below)")
     ("fit:*grec-dirs*" "(list 0.0 (/ pi 4.0) (/ pi 2.0) (* pi 0.75) pi (* pi 1.25) (* pi 1.5) (* pi 1.75))" "the template wall directions, one CCW ring per type (see below)")
     ("fit:*l-dirs*" "(list 0.0 (/ pi 2.0) pi (* pi 1.5) pi (* pi 1.5))" "")
     ("fit:*lazy-dirs*" "(list 0.0 (/ pi 4.0) (* pi 0.75) (* pi 1.25) pi (* pi 1.5))" ""))
    ("G2MCONV" "lisp/g2mconv/G2MCONV.lsp"
     ("*g2mconv-map*" "'((\"1 A POOL WALL - PARED PISCINA\" \"*\" \"POOL\" \"ByLayer\" 0.4) (\"A-STAIRS - GRADAS\" \"*\" \"POOL\" \"DASHED2\" nil) (\"A-ANNO-TEXT - TEXTO\" \"*\" \"TEXT\" \"ByLayer\" 0.4) (\"A-ANNO-DIMS - DIMENSIONES\" \"TEXT,MTEXT,MULTILEADER\" \"TEXT\" \"ByLayer\" 0.4) (\"A-ANNO-DIMS - DIMENSIONES\" \"*\" \"DIMENSION\" \"ByLayer\" 0.4))" "The conversion itself, one row per rule: (source-layer entity-types destination linetype ltscale) The first...")
     ("*g2mconv-make-dashed2*" "T" "A linetype a map row names that the drawing has not got. DASHED2 is stock and this file can make it (the sa...")
     ("*g2mconv-colors*" "'((\"POOL\" . 4) ; cyan, as POOL.LSP and POOLSIDE create it (\"TEXT\" . 4) ; as SOCONV creates it (\"DIMENSION\" . 141))" "The color a destination layer is CREATED with, when the drawing does not carry it yet. A drawing that has t...")
     ("*g2mconv-default-color*" "7" "The color for a destination the table above does not name - what a retuned *g2mconv-map* row pointing at a...")
     ("*g2mconv-force-bylayer*" "T" "T, and every moved object has its color and lineweight set to BYLAYER on the way past, so it takes the dest...")
     ("*g2mconv-text-style*" "\"Attributes\"" "The text style and height every note the run moves is put on. These are the shop drawing's own TEXTSTYLE an...")
     ("*g2mconv-text-height*" "9.5" "The text style and height every note the run moves is put on. These are the shop drawing's own TEXTSTYLE an...")
     ("*g2mconv-dim-style*" "\"STANDARD\"" "The dimension style every converted dimension is put on. If the drawing has no style by this name the dimen...")
     ("*g2mconv-dim-xdata*" "\"ACAD\"" "The xdata application whose style overrides come off each dimension with the restyle. AutoCAD keeps a dimen...")
     ("*g2mconv-deannotate*" "T" "T, and an object that arrives ANNOTATIVE stops being so: its annotative flag goes to 0 and it draws at the...")
     ("*g2mconv-anno-xdata*" "\"AcadAnnotative\"" "The application the annotative flag lives under. AutoCAD writes it as AnnotativeData { <class> <flag> }, wh...")
     ("*g2mconv-record*" "t" "The record G2MRECONV reads back, and the application it lives under. nil converts exactly as before and wri...")
     ("*g2mconv-xdata-app*" "\"G2MCONV\"" "The record G2MRECONV reads back, and the application it lives under. nil converts exactly as before and wri..."))
    ("HONEFILLET" "lisp/honefillet/HONEFILLET.lsp"
     ("hn:*first*" "6.0" "the smallest radius in the COARSE fan --")
     ("hn:*step*" "6.0" "the one that is only there to bracket from -- and the step between the ones after it. SMARTFILLET's fan, be...")
     ("hn:*extras*" "'(3.0 9.0)" "radii offered BESIDES that series. A 3 or a 9 turns up, just not often enough to be the step; they are draw...")
     ("hn:*maxshown*" "10" "how many COARSE previews may be on screen at once; nil = every radius that fits, which on a long wall is a...")
     ("hn:*fine*" "0.5" "the honing step: what the range between the two bracketed sizes is redrawn at. Half an inch is where a radi...")
     ("hn:*maxfine*" "14" "most honed previews at once, and so also what \"neighbouring\" MEANS here: a full 6\" bracket comes to 13 half...")
     ("hn:*fit*" "0.98" "how much of the shorter leg a fillet may use up: 1.0 would put the tangent point exactly on the far end and...")
     ("hn:*layer*" "\"HONE FILLET PREVIEW\"" "use up: 1.0 would put the tangent point exactly on the far end and leave a zero-length line behind")
     ("hn:*color*" "3" "the layer's colour, and the fallback index on every preview: green, so a preview reads as a preview even wh...")
     ("hn:*shade-lo*" "'(190 255 190)" "the SMALLEST preview's green ... index on every preview: green, so a preview reads as a preview even where...")
     ("hn:*shade-hi*" "'(0 110 0)" "... and the largest's. The fan is graded between the two, so which arc a label belongs to is a matter of sh...")
     ("hn:*trans*" "40" "per cent transparency on every preview, so an arc crossing another still reads. 0 or nil = solid; over 90 i...")
     ("hn:*ltype*" "\"DASHED\"" "so an arc crossing another still reads. 0 or nil = solid; over 90 is a preview nobody can see")
     ("hn:*ltscale*" "0.25" "the stock DASHED pattern is 18 units long, so a 6\" fillet arc (9 units of it) would come out as one unbroke...")
     ("hn:*guide*" "t" "nil = never draw one, and a far-off corner is a fan of green arcs floating in space again long, so a 6\" fil...")
     ("hn:*gapmin*" "4.5" "how far short of the corner a line has to stop before it gets one. The stock DASHED pattern is 18 units and...")
     ("hn:*label*" "t" "stop before it gets one. The stock DASHED pattern is 18 units and hn:*ltscale* takes a quarter of it, so a...")
     ("hn:*txthgt*" "3.0" "smaller than SMARTFILLET's: R13.5 is two characters longer than R12 and the honed fan sets them half an inc...")
     ("hn:*rung*" "1.4" "and each one climbs this many text heights further off its leg than the label before it on that side, which...")
     ("hn:*dimlayer*" "\"DIMENSION\"" "heights further off its leg than the label before it on that side, which is what carries the honed fan -- s...")
     ("hn:*smalldim*" "24.0" "POOL's small-dimension rule, heights further off its leg than the label before it on that side, which is wh...")
     ("hn:*smallstyle*" "\"STANDARD INCHES\"" "kept so a fillet callout matches the dims beside it heights further off its leg than the label before it on...")
     ("hn:*dimoff*" "nil" "nil = one radius past the arc matches the dims beside it")
     ("hn:*dimrepeat*" "nil" "one callout plus \"Typ.\" is how the sheet reads; set T to dimension every corner matches the dims beside it")
     ("hn:*typ*" "t" "reads; set T to dimension every corner")
     ("hn:*minang*" "0.02" "how far off straight (radians) two legs must be before there is a corner at all reads; set T to dimension e...")
     ("hn:*sysold*" "nil" "sysvar snapshot, live only mid-run")
     ("hn:*preview*" "nil" "every entity drawn as a preview")
     ("hn:*picks*" "nil" "(preview-arc . radius), what a click means")
     ("hn:*smallwarned*" "nil" "the missing-style note is said once"))
    ("LAZDIAG" "lisp/lazdiag/LAZDIAG.lsp"
     ("lzd:*max-ents*" "400" "How many entities a report will copy. A run that drew ten thousand things before falling over is a real fai...")
     ("lzd:*max-log*" "200" "How many transcript lines are kept. A tutorial loop can princ for ever; the last 200 lines are the ones tha...")
     ("lzd:*subdir*" "\"Downloads\"" "Where reports go, tried in order. The first that accepts the file wins. \"\" means \"ask the drawing\" -- see l..."))
    ("LAZFORM" "lisp/lazform/LAZFORM.lsp"
     ("lzf:*btypes*" "'(\"Normal\" \"Sport\" \"Wedge\" \"SLope\" \"MOdflat\" \"SHallow\")" "The bottoms POOL draws, spelled as POOL's own keywords -- the capitals are each one's abbreviation at the p...")
     ("lzf:*ctreat*" "'(\"(ask)\" \"Square\" \"Radius\" \"Cut\" \"NotGiven\")" "What a corner can be: STANDARDS.md's canonical set, \"(ask)\" first so a row left alone sends nothing and POO...")
     ("lzf:*tabbudget*" "84" "the row of chart tabs Width budgets, in DCL character cells. DCL does not scroll: a row wider than the scre...")
     ("lzf:*rowbudget*" "92" "a row of paired column boxes Width budgets, in DCL character cells. DCL does not scroll: a row wider than t...")
     ("lzf:*colbudget*" "34" "the boxes beside the chart The same wall, the other way up. How many lines of generated DCL may stack in th...")
     ("lzf:*chart-w*" "52" "The chart column: its width in cells, and its height as a share of that width (a string, because DCL reads...")
     ("lzf:*chart-a*" "\"0.72\"" "The chart column: its width in cells, and its height as a share of that width (a string, because DCL reads...")
     ("lzf:*poskey*" "\"LazForm_Pos\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she...")
     ("lzf:*recallkey*" "\"HKEY_CURRENT_USER\\\\Software\\\\Calofin\\\\LazForm\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she..."))
    ("LAZPANEL" "lisp/lazpanel/LAZPANEL.lsp"
     ("lzp:*findname*" "\"Find\"" "The Find page's tab title. Find is a page but not a group: it stays out of lzp:*groups* -- what Rest is com...")
     ("lzp:*tbname*" "\"LazPanel\"" "The screen-button toolbar's name, as the CUI lists it.")
     ("lzp:*poskey*" "\"LazPanel_Pos\"" "Where the panel remembers its position between restarts: a value in the AutoCAD profile (setenv), which is...")
     ("lzp:*pinkey*" "\"HKEY_CURRENT_USER\\\\Software\\\\Calofin\\\\LazPanel\"" "Where pins and recents live: one registry key, values \"Pins\" and \"Recent\", names joined with \";\". THE VB PA...")
     ("lzp:*aliasval*" "\"Alias\"" "The two per-user maps LAZNAME writes, on that same key. Named here rather than spelled at the call sites so...")
     ("lzp:*capval*" "\"Caption\"" "The two per-user maps LAZNAME writes, on that same key. Named here rather than spelled at the call sites so...")
     ("lzp:*capmax*" "40" "The longest caption LAZNAME will let a drafter set. A ceiling, not a preference: tools/check_dcl.py measure...")
     ("lzp:*pinbudget*" "84" "How wide, in DCL character cells, a row of pinned or recent buttons may be before the next button starts a...")
     ("lzp:*colbudget*" "16" "How many captioned buttons may stack in ONE column before a page is split into more columns. The width budg...")
     ("lzp:*pinrowmax*" "3" "How many rows the Pinned strip may occupy. Pins are the one part of a page whose height the DRAFTER sets, a...")
     ("lzp:*reclimit*" "5" "How many recently launched tools are remembered, newest first. The palette keeps the same number (PaletteMe...")
     ("lzp:*tunerows*" "22" "How many rows LAZTUNE's knob list shows at once. A ceiling of the same kind as lzp:*colbudget*: DCL does no..."))
    ("LAZSIDE" "lisp/lazside/LAZSIDE.lsp"
     ("lzv:*b-y*" "120" "the overall B, across the top THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture,...")
     ("lzv:*water-y*" "230" "the waterline: the top of both walls THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the p...")
     ("lzv:*sec-x0*" "90" "the left wall... THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y, y D...")
     ("lzv:*sec-x1*" "910" "...and the right one THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y,...")
     ("lzv:*shal-y*" "430" "the floor at depth C THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y,...")
     ("lzv:*brk-y*" "530" "...at C2, the SHallow break THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture, x...")
     ("lzv:*deep-y*" "660" "...and at D, the deep end THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture, x a...")
     ("lzv:*chain-y*" "810" "the run chain's baseline THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the picture, x an...")
     ("lzv:*c-x*" "45" "where C stands, outside the left wall THE FRAME THE SECTION IS DRAWN IN. Everything is in PER-MILLE of the...")
     ("lzv:*chart-w*" "58" "The chart column: width in cells, and its height as a DCL aspect ratio (height / width of the tile itself)....")
     ("lzv:*chart-a*" "\"0.62\"" "The chart column: width in cells, and its height as a DCL aspect ratio (height / width of the tile itself)....")
     ("lzv:*hint-w*" "92" "How wide the hint and state lines are, in character cells. Wider than the picture beside them, because ever...")
     ("lzv:*poskey*" "\"LazSide_Pos\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she...")
     ("lzv:*recallkey*" "\"HKEY_CURRENT_USER\\\\Software\\\\Calofin\\\\LazSide\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she..."))
    ("LAZSPA" "lisp/lazspa/LAZSPA.lsp"
     ("lzs:*ctreat*" "'(\"(ask)\" \"90\" \"Radius\" \"Diagonal\")" "What a corner can be, in the SHEET LEGEND's words -- 90 / Radius / Diagonal -- with \"(ask)\" first so a row...")
     ("lzs:*tabbudget*" "84" "Width budget for the row of chart tabs, in DCL character cells. Three charts run about 39 cells, so this ne...")
     ("lzs:*chart-w*" "52" "The chart column: width in cells, and its total height in rows, which is spread over the bands the chart is...")
     ("lzs:*chart-h*" "19" "The chart column: width in cells, and its total height in rows, which is spread over the bands the chart is...")
     ("lzs:*poskey*" "\"LazSpa_Pos\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she...")
     ("lzs:*recallkey*" "\"HKEY_CURRENT_USER\\\\Software\\\\Calofin\\\\LazSpa\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she..."))
    ("LAZSTEP" "lisp/lazstep/LAZSTEP.lsp"
     ("lzt:*plan-x0*" "100" "the wall, or the corner THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y...")
     ("lzt:*plan-x1*" "860" "the far end of the run THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y,...")
     ("lzt:*plan-yc*" "180" "the run's centre line THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y,...")
     ("lzt:*plan-hh*" "120" "half the plan's opening at the far end THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the p...")
     ("lzt:*width-x*" "930" "where a whole-run width dim stands THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the pictu...")
     ("lzt:*chord-x1*" "860" "the last chord across a hemi curve THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the pictu...")
     ("lzt:*curve-rx*" "840" "...whose crown sits beyond it, at x0 + this THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of...")
     ("lzt:*tread-y0*" "385" "the tread dimension row THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y...")
     ("lzt:*tread-y1*" "445" "...and the second one, when N needs it THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the p...")
     ("lzt:*one-row*" "4" "treads that fit one row of boxes THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture...")
     ("lzt:*prof-x*" "860" "top of the flight, x... THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y...")
     ("lzt:*prof-y*" "540" "...and y: the profile hangs from here THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the pi...")
     ("lzt:*prof-w*" "760" "the flight's whole run... THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and...")
     ("lzt:*prof-h*" "450" "...and its whole drop THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the picture, x and y,...")
     ("lzt:*prof-gap*" "40" "how far a depth dim stands off its step THE FRAME THE CHART IS DRAWN IN. Everything is in PER-MILLE of the...")
     ("lzt:*max-steps*" "8" "THE CEILING. DCL will not scroll and a dialog taller than the screen does not open at all, so the count has...")
     ("lzt:*steps-nominal*" "3" "WHAT THE PICTURE SHOWS BEFORE A COUNT IS TYPED. The page opens with the count box empty -- the form invents...")
     ("lzt:*chart-w*" "58" "The chart column: width in cells, its total height in rows spread over the bands, and the edit_width of a b...")
     ("lzt:*chart-h*" "20" "The chart column: width in cells, its total height in rows spread over the bands, and the edit_width of a b...")
     ("lzt:*wedge-ed*" "5" "The chart column: width in cells, its total height in rows spread over the bands, and the edit_width of a b...")
     ("lzt:*colbudget*" "34" "HOW TALL THE ANSWER COLUMN MAY GET before it is split in two. The page is as tall as its longest column and...")
     ("lzt:*hint-w*" "96" "How wide the hint and state lines are, in character cells. Wider than the boxes they sit under, because the...")
     ("lzt:*poskey*" "\"LazStep_Pos\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she...")
     ("lzt:*recallkey*" "\"HKEY_CURRENT_USER\\\\Software\\\\Calofin\\\\LazStep\"" "Where the dialog remembers its position between restarts (the AutoCAD profile, via setenv), and where a she..."))
    ("LHD" "lisp/lhd/lhd.lsp"
     ("*LH-POOL-LAYER*" "\"POOL\"" "layer of the ordering sketch, and where the kept outline ends up reads this banner and stamps the dated twi...")
     ("*LH-POINT-LAYER*" "\"POINTS\"" "layer whose POINTs/INSERTs are always points where the kept outline ends up")
     ("*LH-POINT-BLOCK*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit always points")
     ("*LH-OUT-LAYER*" "\"LHD-FIT\"" "layer the candidate fits go on points wherever they sit")
     ("*LH-MISS-LAYER*" "\"FGStep\"" "layer the \"could not hold this point\" rings go on; LHD stamps its objects and only erases its own (see lh:t...")
     ("*LH-MISS-RADIUS*" "4.0" "radius of those rings (4 inches) point\" rings go on; LHD stamps its objects and only erases its own (see lh...")
     ("*LH-PT-TAG*" "\"number\"" "attribute tag on the point block naming the point, as in \"Pt.17\" point\" rings go on; LHD stamps its objects...")
     ("*LH-SNAP*" "12.0" "a CLICK within this of a scanned point names that point - at a stretch end, a corner, a held point, a run e...")
     ("*LH-WALL-LAYER*" "\"POOL-WALLS\"" "layer for the dashed markers of declared straight stretches point names that point - at a stretch end, a co...")
     ("*LH-TOL-MAX*" "2.0" "hard ceiling on the max-distance prompt (2 inches) declared straight stretches")
     ("*LH-TEXT-EPS*" "6.0" "a numeric TEXT within this of a point is that point's elevation label (6 in; labels sit right on their poin...")
     ("*LH-COMPARE*" "'((\"tight\" 1 \"red\" \"most curves - least error\") (\"asked\" 2 \"yellow\" \"as asked\") (\"few\" 4 \"cyan\" \"fewest curves - still within the distance\"))" "the three candidate fits offered: point is that point's elevation label (6 in; labels sit right on their po...")
     ("*LH-TIGHT-TOL*" "0.01" "the \"tight\" candidate's accuracy target (units) same three aims as ABHD: \"tight\" fits to *LH-TIGHT-TOL* wit...")
     ("*LH-EXACT-EPS*" "0.001" "\"exactly on\" threshold (units) target (units)")
     ("*LH-FIT-EPS*" "0.01" "an arc through an interior point must pass within twice this of it to count as anchored target (units)")
     ("*LH-ON-EPS*" "0.25" "a point within this of the result counts as ON it; only points off by more eat into the allowance must pass...")
     ("*LH-MISS-PCT*" "0.15" "share of the points (rounded UP) that may sit off the result by up to the tolerance counts as ON it; only p...")
     ("*LH-CORNER-ANG*" "(/ pi 4.0)" "a point that turns more than this (45 deg) is a sharp corner: it may start or end a span but never gets bur...")
     ("*LH-NICE-RADII*" "'(12.0 6.0 1.0)" "preferred arc-radius tiers, tried in order: whole feet, half feet, whole inches (45 deg) is a sharp corner:...")
     ("*LH-TANG-TOL*" "(/ pi 22.5)" "wiggle room from perfect tangency at each joint (8 degrees) tried in order: whole feet, half feet, whole in...")
     ("*LH-TANG-STEPS*" "'(1.0 1.25 1.5)" "when nothing fits inside the tangent window, stretch it by these multiples before falling back to a one-poi...")
     ("*LH-ARC-SLACK*" "(/ pi 3.0)" "how much further than its own points actually turn one arc may sweep (60 degrees). An arc is allowed to cur...")
     ("*LH-DROP-PCT*" "0.10" "share of the points (rounded UP) the fit may give up on entirely: left further off than the max distance, c...")
     ("*LH-DROP-MULT*" "2.0" "how far past the max distance a point has to be before the fit may give up on it at all - what separates a...")
     ("*LH-SNAP-EPS*" "0.02" "a nice-radius snap may move the covered points at most this far beyond where they already sat point has to...")
     ("*LH-CHAIN-FUZZ*" "1.0e-4" "endpoint-matching fuzz for chaining sketch segments covered points at most this far beyond where they alrea...")
     ("*LH-FLOAT-GAIN*" "2" "an arc that floats between the points (its middle on no survey point) is taken only when it covers at least...")
     ("*LH-DROP-GAIN*" "2" "and every point given up must buy at least this many more points of span, or it is held after all points (i...")
     ("*LH-ON-FRAC*" "0.25" "the on-the-shape threshold scales with the distance typed: this fraction of it, or *LH-ON-EPS*, whichever i...")
     ("*LH-ANCHOR-EPS*" "(* 2.0 *LH-FIT-EPS*)" "an arc \"passes through\" an interior survey point when the point sits within this of it - twice the fit epsi...")
     ("*LH-CAP-RELAX*" "1.4" "when a fit needs more curves than the cap allows, the whole run is refitted with the distance multiplied by...")
     ("*LH-CAP-TRIES*" "40" "...and at most this many refits the fewest-curves result seen is kept when the cap is still unmet than the...")
     ("*LH-BULGE-CLAMP*" "1.373" "the half-angle a tangent-window edge, or a span's own permitted turn, may reach (radians): its tangent is a...")
     ("*LH-STRAIGHT-R*" "1.0e6" "an arc whose radius reaches this is a straight line for every practical purpose: it is not snapped to a nic..."))
    ("LINCHECK" "lisp/lincheck/lincheck.lsp"
     ("lin:*tick*" "\"[x] \"" "The report is printed to the command line, one line per item. These are the pieces every line is built from...")
     ("lin:*note-sep*" "\" -- \"" "The report is printed to the command line, one line per item. These are the pieces every line is built from...")
     ("lin:*ans-sep*" "\" -> \"" "The report is printed to the command line, one line per item. These are the pieces every line is built from...")
     ("lin:*indent*" "\" \"" "A cross dimension is logged indented under its heading by this.")
     ("lin:*head-in*" "\"== \"" "A section heading, in the report and on the command line. The two differ on purpose: the report's is quiete...")
     ("lin:*head-out*" "\"==\"" "A section heading, in the report and on the command line. The two differ on purpose: the report's is quiete...")
     ("lin:*head-echo-in*" "\"=== \"" "A section heading, in the report and on the command line. The two differ on purpose: the report's is quiete...")
     ("lin:*head-echo-out*" "\"===\"" "A section heading, in the report and on the command line. The two differ on purpose: the report's is quiete...")
     ("lin:*rule*" "\"############################################\"" "The banner the printed report is boxed in, and its title. RULE is drawn as-is, so its width is what sets th...")
     ("lin:*title*" "\"# LINER CHECKLIST REPORT #\"" "The banner the printed report is boxed in, and its title. RULE is drawn as-is, so its width is what sets th...")
     ("lin:*back-words*" "'(\"B\" \"BACK\" \"U\" \"UNDO\")" "A getstring prompt cannot take initget keywords, so \"go back a step\" has to be typed like a note. These are..."))
    ("LINFINCHECK" "lisp/linfincheck/linfincheck.lsp"
     ("*lfc-step-maxgap*" "18.0" "drawing units Treads are found as stacked parallel lines. MAXGAP is the widest spacing that still reads as...")
     ("*lfc-step-minlines*" "3" "lines Treads are found as stacked parallel lines. MAXGAP is the widest spacing that still reads as one flig...")
     ("*lfc-bench-minlines*" "2" "lines Treads are found as stacked parallel lines. MAXGAP is the widest spacing that still reads as one flig...")
     ("*lfc-step-angtol*" "1.0" "degrees Treads are found as stacked parallel lines. MAXGAP is the widest spacing that still reads as one fl...")
     ("*lfc-bead-layer*" "\"Bead Track\"" "Bead track: the layer it belongs on, and how close to the plan-view steps it has to run before it counts as...")
     ("*lfc-bead-dist*" "18.0" "drawing units Bead track: the layer it belongs on, and how close to the plan-view steps it has to run befor...")
     ("*lfc-attach-options*" "'(\"Bead\" \"Flaps\" \"Rod Pockets\" \"No Attachment\")" "The generic Step Attachment block lists every option with a box; if ALL of them are still showing, nobody p...")
     ("*lfc-secured-phrase*" "\"to be secured\"" "")
     ("*lfc-fgstep-words*" "'(\"Fiberglass Step\" \"FG Step\")" "A fiberglass step shows up under any of these names.")
     ("*lfc-title-block*" "\"Tech Title\"" "The title block holding the wall height and the sheet date, and the two attribute tags inside it. Spaces in...")
     ("*lfc-wallht-tag*" "\"WallHt\"" "The title block holding the wall height and the sheet date, and the two attribute tags inside it. Spaces in...")
     ("*lfc-date-tag*" "\"Date\"" "The title block holding the wall height and the sheet date, and the two attribute tags inside it. Spaces in...")
     ("*lfc-height-tol*" "0.25" "drawing units The step height and WallHt may differ by this much before the report says to check the wall h...")
     ("*lfc-min-wallht*" "1.0" "drawing units ...and a WallHt below this is NONSENSICAL rather than merely wrong (0\" walls do not exist).")
     ("*lfc-ask-phrase*" "\"Wall height\"" "The question text expected in the drawing when WallHt reads \"?\".")
     ("*lfc-badwords*" "'(\"NOT\" \"ERROR\")" "A liner pattern field carrying one of these words was never really filled in (\"Not Supplied\", \"#ERROR\") --...")
     ("*lfc-border-layer*" "\"border\"" "The title block border is nominally 58'-8\" x 45'-3 5/8\", or a scaled-UP whole multiple of it, on this layer...")
     ("*lfc-border-w*" "704.0" "58'-8\" in drawing units The title block border is nominally 58'-8\" x 45'-3 5/8\", or a scaled-UP whole multi...")
     ("*lfc-border-h*" "543.625" "45'-3 5/8\" in drawing units The title block border is nominally 58'-8\" x 45'-3 5/8\", or a scaled-UP whole m...")
     ("*lfc-border-tol*" "0.005" "0.5%, as a fraction The title block border is nominally 58'-8\" x 45'-3 5/8\", or a scaled-UP whole multiple...")
     ("*lfc-block-depth*" "3" "levels How many levels of nested block to search when looking for a name or a piece of text. Raising it fin...")
     ("*lfc-tol*" "1.0e-4" "drawing units A dimension point or an arc end within this distance of an object is ATTACHED and is not ques...")
     ("*lfc-anchor-tol*" "1.0e-4" "drawing units How close two dimension points must be to count as the same spot...")
     ("*lfc-anchor-min*" "2" "dimensions meeting at one spot ...and how many dimensions must meet there to make it an ANCHOR: a point lef...")
     ("*lfc-curve-types*" "'(\"LINE\" \"ARC\" \"CIRCLE\" \"ELLIPSE\" \"LWPOLYLINE\" \"POLYLINE\" \"SPLINE\")" "Entity types a dimension point or an arc end may attach to. Each must be a curve AutoCAD can measure to (vl...")
     ("*lfc-ask-all-arc-ends*" "nil" "T = confirm EVERY arc endpoint, even ones already attached.")
     ("*lfc-olap-fuzz*" "1.0e-4" "drawing units, sideways offset How far apart two parallel lines may sit and still be called the same line....")
     ("*lfc-olap-dirtol*" "0.5" "degrees Two segments are only tested for overlap when their directions are within this of each other. It is...")
     ("*lfc-olap-types*" "'(\"LINE\" \"LWPOLYLINE\" \"POLYLINE\")" "Entity types whose straight segments take part in overlap detection. Arcs, circles and splines have no stra...")
     ("*lfc-style-order*" "'(\"STANDARD\" \"SIDE STANDARD\" \"STANDARD INCHES\" \"CROSS DIMENSIONS\")" "Dimension styles are reviewed in this order; styles not listed come afterwards (\"whatever else is left\"), s...")
     ("*lfc-dim-layer*" "\"DIMENSION\"" "Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what t...")
     ("*lfc-dimfix-cmd*" "\"CDIM\"" "Every dimension belongs on this layer; DIMFIX-CMD is the command that moves the strays there, and is what t...")
     ("*lfc-row-band*" "0.05" "fraction of the selection's height Within a style, dimensions are reviewed row by row. Two dimensions count...")
     ("*lfc-row-flat*" "1.0" "...and the band for a selection with no height Within a style, dimensions are reviewed row by row. Two dime...")
     ("*lfc-grey-color*" "'auto" "ACI: everything not under review, faded. 'auto fades it the way round the drawing needs -- darker than the...")
     ("*lfc-flag-color*" "'auto" "ACI: what you answered \"No\" to (red) 'auto fades it the way round the drawing needs -- darker than the work...")
     ("*lfc-arc-color*" "'auto" "ACI: arcs whose endpoints were moved (magenta) 'auto fades it the way round the drawing needs -- darker tha...")
     ("*lfc-olap-color*" "'auto" "ACI: merged or flagged overlapping lines (cyan) 'auto fades it the way round the drawing needs -- darker th...")
     ("*lfc-orig-color*" "'auto" "ACI: the X marking where you drew the point (red) 'auto fades it the way round the drawing needs -- darker...")
     ("*lfc-sugg-color*" "'auto" "ACI: the + marking where LINFINCHECK would put it (green) 'auto fades it the way round the drawing needs --...")
     ("*lfc-point-color*" "'auto" "ACI: the crosses marking an overlap's two ends (yellow) 'auto fades it the way round the drawing needs -- d...")
     ("*lfc-constr-layer*" "\"LINFINCHECK-CONSTRUCTION\"" "The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are c...")
     ("*lfc-constr-color*" "'auto" "ACI (yellow) The construction XLINE through a moved dimension's original points, and the report MTEXT. Both...")
     ("*lfc-report-layer*" "\"LINFINCHECK-REPORT\"" "The construction XLINE through a moved dimension's original points, and the report MTEXT. Both layers are c...")
     ("*lfc-report-color*" "'auto" "ACI (green) The construction XLINE through a moved dimension's original points, and the report MTEXT. Both...")
     ("*lfc-green-scale*" "0.75" "All-clear lines are written at this fraction of the height the red attention lines get, so problems stand o...")
     ("*lfc-report-chars*" "45.0" "Report column width, in text heights, and the width of the tutorial's reference sheet, which is prose rathe...")
     ("*lfc-sheet-chars*" "70.0" "Report column width, in text heights, and the width of the tutorial's reference sheet, which is prose rathe...")
     ("*lfc-report-wide*" "0.25" "The report is scaled to the drawing: its text height is chosen so the whole report is about as tall as the...")
     ("*lfc-report-lead*" "1.66" "MTEXT line pitch as a multiple of text height, used to turn a line count into a height. AutoCAD's default s...")
     ("*lfc-report-hmax*" "30.0" "...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both ar...")
     ("*lfc-report-hmin*" "200.0" "...then the height is clamped: never taller than reference/HMAX, never shorter than reference/HMIN. Both ar...")
     ("*lfc-report-hfall*" "2.5" "drawing units The height used when the selection has no extents to scale against (DIMTXT x DIMSCALE is trie...")
     ("*lfc-report-gap*" "0.05" "Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around th...")
     ("*lfc-zoom-out*" "0.05" "Gap between the drawing and the report, as a fraction of the drawing's width, and the margin left around th...")
     ("*lfc-zoom-margin*" "0.75" "Empty space around ONE item when the review zooms to it, as a fraction of its size.")
     ("*lfc-mark-size*" "0.02" "fraction of VIEWSIZE Half-size of the X and + markers drawn while you answer, as a fraction of the current...")
     ("*lfc-attn-words*" "\"*FLAGGED*,*WRONG*,*SKIPPED*,*MAGENTA*,*MISSING*,*NOTHING*,*NO SIDE VIEW*,*NO 'STEP*,*NO BLOCK*,*WORD NOT*,*WORD ERROR*,* ADD *,*MISMATCH*,*NOT CONFIRMED*,*NOT ATTACHED*,*OVERLAP*,*CHECK THE WALL HEIGHT*,*FIBERGLASS STEP*,*ASSOCIATIVE*,*DISAGREE*,*SCALED DOWN*,*STRETCHED*,*NO BORDER*,*WIPED*,*NEEDS WIPING*,*NONSENSICAL*,*EXPECTED MM/DD/YYYY*,*NO INCHES*,*NOT TODAY*,*NEEDS UPDATING*,*UPDATED TO*\"" "A report line is rendered red and full-size when it matches this pattern (wcmatch, case-blind; comma separa...")
     ("*lfc-dist-mode*" "2" "rtos mode Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engineeri...")
     ("*lfc-dist-prec*" "4" "decimal places Distances in prompts and the report go through (rtos d mode prec): mode 2 is decimal, 3 engi...")
     ("*lfc-same-pt*" "1e-8" "drawing units Two points closer than this are the SAME point: no construction line is drawn through them, n...")
     ("*lfc-planar-eps*" "1e-9" "dimensionless (normal components) How far an arc's extrusion normal (DXF 210) may lean from world +Z and st...")
     ("*lfc-flat-eps*" "1e-12" "---------------------------------------------------------------------- Below this a polyline bulge is treat..."))
    ("LINGUTTER" "lisp/lingutter/LINGUTTER.lsp"
     ("lg:*poollayer*" "\"POOL\"" "layer the traced perimeter is drawn on; made if missing, and thawed / switched on / unlocked if it exists b...")
     ("lg:*poolcolor*" "4" "its colour when the layer has to be created -- ACI 4 = cyan, POOL's own. Ignored when the layer already exi...")
     ("lg:*anystyles*" "'(\"CROSS DIM*\")" "dim styles kept WHEREVER they sit: a cross dim spans the pool, so most of it is nowhere near the edge creat...")
     ("lg:*perimstyles*" "'(\"STANDARD\" \"SIDE STANDARD\")" "dim styles kept only ON the perimeter -- every attachment point within lg:*ontol* of the loop. The same sty...")
     ("lg:*keeplayers*" "nil" "layers left alone entirely, even inside the highlight; nil = none, e.g. '(\"TITLEBLOCK\") to spare one dim st...")
     ("lg:*skiplayers*" "'(\"DEFPOINTS\" \"DIMENSION\")" "layers the perimeter is never traced FROM. They are still swept: this keeps dimension geometry out of the w...")
     ("lg:*ontol*" "1.0" "how far a dimension's attachment point may sit off the perimeter and still count as on it. Drawing units, s...")
     ("lg:*snaps*" "'(0.05 6.0 24.0)" "the snap ladder: how far apart two ends may be and still be treated as one node. Tried TIGHTEST FIRST, a ru...")
     ("lg:*cover*" "0.8" "how much of the highlight's extent a traced exterior has to span, both ways, to be believed as the perimete...")
     ("lg:*crossspan*" "0.8" "how much of the PERIMETER's own bounding box a kept lg:*anystyles* dim has to span, in X or in Y, to count...")
     ("lg:*runpaddle*" "t" "T to hand the new perimeter to PADDLE and pad it; nil to stop after the gut and leave it unpadded bounding..."))
    ("LINTXTCHK" "lisp/lintxtchk/LINTXTCHK.lsp"
     ("ltc:*height*" "12.0" "Text height, in drawing units (1 unit = 1 inch on the shop's sheets). The next two are multiples of it, so...")
     ("ltc:*spacing*" "1.6" "Vertical distance between lines, and the horizontal indent per sub-level, both as multiples of the text hei...")
     ("ltc:*indent*" "1.5" "Vertical distance between lines, and the horizontal indent per sub-level, both as multiples of the text hei...")
     ("ltc:*bullet*" "\"- \"" "What every line is prefixed with. \"\" gives a plain column, \"[ ] \" gives boxes to tick.")
     ("ltc:*items*" "(list (cons 0 \"Read all WSN (White Screen Notes), Notes from Merlin, and Customer Info\") (cons 1 \"Does this job actually require a Tech drawing?\") (cons 0 \"Verify Finished Wall Ht & Pool Depth\") (cons 1 \"Finished Wall Ht should be a single value, or \\\"Varies\\\" if needed\") (cons 0 \"Place liner pattern block (GLP) - Delete \\\"Not Supplied\\\" text\") (cons 0 \"Verify the type of pool bead, or overlap for AG, etc\") (cons 0 \"Pool perimeter & overall dims\") (cons 0 \"Verify orientation: Shallow end to the RIGHT of page\") (cons 0 \"Report ALL cross dimensions provided by customer\") (cons 0 \"Pool corners with dimensions\") (cons 1 \"Look out special mfgrs like Esther Williams (3x3, 5x5) or Foxx (37\\\" Deep)\") (cons 0 \"Look for special bottom conditions:\") (cons 1 \"Does the shallow end have a Cove?\") (cons 1 \"Does the pool have a Safety Ledge?\") (cons 1 \"Did the customer provide various depths for the bottom?\") (cons 1 \"Does the pool require a side view?\") (cons 0 \"Are hopper corners radius?\") (cons 0 \"Did you draw trowel lines accurately?\") (cons 0 \"Are steps / bench Fiberglass?\") (cons 1 \"Place FGS note or draw step outline if dimensions were provided\") (cons 1 \"Is the step Straight or Radius? Ask if not given\") (cons 0 \"Are steps / bench Vinyl-covered?\") (cons 1 \"Verify step corner type & dimensions\") (cons 1 \"Place Step Attachment block - is the attachment type provided?\") (cons 1 \"Place side views for all steps and benches\") (cons 0 \"Did you scale the titleblock? REDVIEW!\") )" "Each entry is (indent-level . \"line text\"). Level 0 is a main item, 1 a sub-item indented under the one abo..."))
    ("LOBF" "lisp/lobf/LOBF.lsp"
     ("lobf:*pt-layer*" "\"POINTS\"" "layer holding the survey points Where the survey points live, and what a point block calls its number -- AB...")
     ("lobf:*pt-block*" "\"ab_pt\"" "block name whose INSERTs mark points Where the survey points live, and what a point block calls its number...")
     ("lobf:*pt-tag*" "\"number\"" "the attribute carrying the number Where the survey points live, and what a point block calls its number --...")
     ("lobf:*filter*" "'((0 . \"POINT,INSERT\"))" "What the highlight is allowed to hand the command. Only points are wanted -- LOBF fits a line THROUGH point...")
     ("lobf:*exact-eps*" "1.0e-6" "drawing units Two points closer together than this are one shot, not two: a double-shot must not get two vo...")
     ("lobf:*drastic*" "4.0" "multiples of the worst held point THE RULE THAT PICKS THE DEFAULT. Fit 2 sets one point aside; it is offere...")
     ("lobf:*drastic-floor*" "0.5" "drawing units ...and at least this far off in its own right. Without a floor, a survey where every point is...")
     ("lobf:*default-fit*" "\"1\"" "\"1\", \"2\" or \"3\" Which fit Enter takes when NO point stands out that way -- there is then no outlier to isol...")
     ("lobf:*blob-ratio*" "0.2" "worst error / length of the run When fit 1's worst point is further off than this fraction of the run's own...")
     ("lobf:*layer*" "\"LOBF\"" "the construction line kept The three layers LOBF writes on, created on first use. PREVIEW holds the three c...")
     ("lobf:*color*" "4" "ACI (cyan) The three layers LOBF writes on, created on first use. PREVIEW holds the three candidates and th...")
     ("lobf:*preview-layer*" "\"LOBF-PREVIEW\"" "the three candidates The three layers LOBF writes on, created on first use. PREVIEW holds the three candida...")
     ("lobf:*preview-color*" "'auto" "ACI (grey) -- each XLINE carries its own colour. 'auto picks the grey for the background; a number is used...")
     ("lobf:*ign-layer*" "\"LOBF-IGNORED\"" "ring round a set-aside point carries its own colour. 'auto picks the grey for the background; a number is u...")
     ("lobf:*ign-color*" "1" "ACI (red) carries its own colour. 'auto picks the grey for the background; a number is used exactly as given")
     ("lobf:*appid*" "\"LOBF\"" "renaming this orphans earlier runs carries its own colour. 'auto picks the grey for the background; a numbe...")
     ("lobf:*fit-colors*" "'(3 2 6)" "ACI: green, yellow, magenta The colour each candidate is previewed in, fit 1 first. These are what the on-s...")
     ("lobf:*label-div*" "40.0" "Label sizing, all as fractions of the run the points cover. DIV sets the text height (a bigger number is sm...")
     ("lobf:*label-gap*" "0.08" "Label sizing, all as fractions of the run the points cover. DIV sets the text height (a bigger number is sm...")
     ("lobf:*label-stalk*" "1.6" "text heights, times the fit number Label sizing, all as fractions of the run the points cover. DIV sets the...")
     ("lobf:*ring-scale*" "1.2" "text heights Label sizing, all as fractions of the run the points cover. DIV sets the text height (a bigger...")
     ("lobf:*dist-mode*" "4" "rtos mode Distances on the command line go through (rtos d mode prec): mode 4 is architectural (feet-inches...")
     ("lobf:*dist-prec*" "5" "2^5 = thirty-seconds of an inch Distances on the command line go through (rtos d mode prec): mode 4 is arch...")
     ("lobf:*ang-prec*" "2" "decimal places Degrees of bearing printed after each fit, so two fits that read the same to the thirty-seco...")
     ("lobf:*tiny*" "1.0e-10" "Anything smaller than this is zero: the guard on a degenerate fit (every point on one spot), on a zero-leng..."))
    ("MOHAMADDLE" "lisp/mohamaddle/MOHAMADDLE.lsp"
     ("*mohamaddle-sizes*" "'((\"24\" \"Pad24x24\" 24.0) (\"36\" \"Pad36x36\" 36.0))" "--- the pad itself --- Pad sizes MOHAMADDLE offers, in the order shown at the prompt. Each entry is (KEYWOR...")
     ("*mohamaddle-defaultkw*" "\"36\"" "The dwg the block definitions are imported from when the drawing does not already hold them. Looked up with...")
     ("*mohamaddle-blkfile*" "\"24inpad.dwg\"" "Layer the pads land on. Created when missing; an existing one is thawed, unlocked and turned on so the resu...")
     ("*mohamaddle-layer*" "\"PADS\"" "AutoCAD colour index the layer is created with. An existing layer keeps whatever colour it already has. Lay...")
     ("*mohamaddle-layer-color*" "7" "nil = every pad stays parallel to the X/Y axes (the shop standard). T = each pad rotates to follow its stre...")
     ("*mohamaddle-align*" "nil" "nil = every pad stays parallel to the X/Y axes (the shop standard). T = each pad rotates to follow its stre...")
     ("*mohamaddle-maxrad*" "54.0" "A connection point (line meets line, line meets arc, a polyline vertex) counts as a sharp inside corner onl...")
     ("*mohamaddle-cornertol*" "(/ (* 30.0 pi) 180.0)" "A concave arc counts as a feature only when its total bend is MORE than this many degrees; a gentler sweep...")
     ("*mohamaddle-arctol*" "(/ (* 10.0 pi) 180.0)" "A concave arc counts as a feature only when its total bend is MORE than this many degrees; a gentler sweep...")
     ("*mohamaddle-fuzz*" "0.05" "--- reading the perimeter --- Largest gap between the end of one loose line/arc and the start of the next t...")
     ("*mohamaddle-gapmax*" "36.0" "Layer the gap arrow is drawn on, and the colour index it is created with. A plain ACI number rather than 'a...")
     ("*mohamaddle-gap-layer*" "\"PADDLE-GAP\"" "Layer the gap arrow is drawn on, and the colour index it is created with. A plain ACI number rather than 'a...")
     ("*mohamaddle-gap-color*" "1" "Length of that arrow, tail to tip, in drawing units. Its head is a third of that long and three times as wi...")
     ("*mohamaddle-arrow*" "36.0" "Length of that arrow, tail to tip, in drawing units. Its head is a third of that long and three times as wi..."))
    ("OASIS" "lisp/oasis/OASIS.lsp"
     ("oasis:*poollayer*" "\"POOL\"" "the arcs, and the pool bottom The three layers, created if the drawing has not got them and thawed, unlocke...")
     ("oasis:*poolcolor*" "4" "The three layers, created if the drawing has not got them and thawed, unlocked and switched back on if it h...")
     ("oasis:*dimlayer*" "\"DIMENSION\"" "every dimension, both drawings The three layers, created if the drawing has not got them and thawed, unlock...")
     ("oasis:*dimcolor*" "2" "The three layers, created if the drawing has not got them and thawed, unlocked and switched back on if it h...")
     ("oasis:*guidelayer*" "\"POOL-GUIDE\"" "the dashed circles, box and labels The three layers, created if the drawing has not got them and thawed, un...")
     ("oasis:*guidecolor*" "'auto" "'auto picks it for the background: 8 on a light one, a lighter grey on a dark one, where 8 is very nearly t...")
     ("oasis:*hicolor*" "1" "red: the part being asked about 8 on a light one, a lighter grey on a dark one, where 8 is very nearly the...")
     ("oasis:*dimstyle*" "\"Standard\"" "the pool's own dims Two styles, because the two drawings are read differently: the pool itself is a plan an...")
     ("oasis:*crossstyle*" "\"CROSS DIMENSIONS\"" "the check drawing's Two styles, because the two drawings are read differently: the pool itself is a plan an...")
     ("oasis:*checkgap*" "4.0" "How far to the right of the pool the check drawing sits, measured from the pool's own right-hand bound, as...")
     ("oasis:*topfrac*" "0.5" "Where a Center pool's top bulge sits across the X bound, as a fraction of it. 0.5 centres the hump, which i...")
     ("oasis:*startside*" "0.75" "A radius not answered yet still needs a value for the preview to be drawable at all, so the gaps are filled...")
     ("oasis:*starttop*" "0.5" "A radius not answered yet still needs a value for the preview to be drawable at all, so the gaps are filled...")
     ("oasis:*startjoin*" "0.6" "A joiner has no rule of thumb of its own -- what looks right depends entirely on the bulges either side of...")
     ("oasis:*startbig*" "1.2" "A joiner has no rule of thumb of its own -- what looks right depends entirely on the bulges either side of...")
     ("oasis:*startclear*" "1.25" "...and whichever of those two it is, it is then lifted to at least this multiple of its own minimum. Keep i...")
     ("oasis:*startktop*" "1.5" "The two kidneys, whose provisionals cannot be read off neighbours because the shape derives half of itself:...")
     ("oasis:*startkleft*" "0.40" "The two kidneys, whose provisionals cannot be read off neighbours because the shape derives half of itself:...")
     ("oasis:*startkright*" "0.45" "The two kidneys, whose provisionals cannot be read off neighbours because the shape derives half of itself:...")
     ("oasis:*startkside*" "48.0" "The side radius a true kidney's bottom joiner is sized against when the derivation has no answer at all. Ev...")
     ("oasis:*dimoffmin*" "12.0" "All of it scales off the pool, so a 10-foot spa and a 40-foot pool are annotated to LOOK the same rather th...")
     ("oasis:*dimoffdiv*" "18.0" "All of it scales off the pool, so a 10-foot spa and a 40-foot pool are annotated to LOOK the same rather th...")
     ("oasis:*radiusdrag*" "0.9" "How far a radius dimension's text is dragged off its own arc, as a fraction of that stand-off -- away from...")
     ("oasis:*dashmin*" "2.0" "The dashed guide linetype, built rather than loaded from acad.lin (a failed load falls back to CONTINUOUS i...")
     ("oasis:*dashdiv*" "40.0" "The dashed guide linetype, built rather than loaded from acad.lin (a failed load falls back to CONTINUOUS i...")
     ("oasis:*pvtextdiv*" "28.0" "The preview's radius labels: how tall the text is, and how far out from its own arc it sits, in text height...")
     ("oasis:*pvtextgap*" "1.7" "The preview's radius labels: how tall the text is, and how far out from its own arc it sits, in text height...")
     ("oasis:*markmin*" "1.0" "The little circle the check drawing marks each centre with.")
     ("oasis:*markdiv*" "90.0" "The little circle the check drawing marks each centre with.")
     ("oasis:*tangmarkdiv*" "150.0" "The numbered marks the pool-bottom flow puts on every change of tangency, so one can be named: the mark's o...")
     ("oasis:*tangtextdiv*" "34.0" "The numbered marks the pool-bottom flow puts on every change of tangency, so one can be named: the mark's o...")
     ("oasis:*tangtextgap*" "1.6" "The numbered marks the pool-bottom flow puts on every change of tangency, so one can be named: the mark's o...")
     ("oasis:*hopoff*" "18.0" "The hopper offset the question opens on when a session has not yet had an answer accepted. After that the s...")
     ("oasis:*hopchord*" "24" "How many chords a GUIDED slope line is drawn with. It follows the wall with its offset easing away to nothi...")
     ("oasis:*hopscan*" "720" "How finely the deepest point of the offset ring is looked for, in samples round the whole ring. Only the de...")
     ("oasis:*fuzz*" "1.0e-6" "Slack for \"is this the same point / the same length\" tests, in drawing units. Measurements arrive in inches...")
     ("oasis:*ptfuzz*" "1.0e-8" "The tighter slack the check drawing dedupes its tie measurements with. Two ties wanted between the same pai...")
     ("oasis:*ucsfuzz*" "1.0e-8" "How far out of the world plan the current UCS may lie and still count as flat. A DIRECTION COSINE, not a le...")
     ("oasis:*cmdguard*" "10" "Two belt-and-braces loop limits, neither reached by any input the questions admit: they are here so a bug u...")
     ("oasis:*ringguard*" "4" "Two belt-and-braces loop limits, neither reached by any input the questions admit: they are here so a bug u..."))
    ("OLAUTO" "lisp/olauto/OLAUTO.lsp"
     ("ola:*new-layer*" "\"POOL\"" "the NEW perimeter ends up here The two perimeters are put onto the shop's own layers on the way out, so the...")
     ("ola:*og-layer*" "\"Bead Track\"" "the ORIGINAL ends up here The two perimeters are put onto the shop's own layers on the way out, so the shee...")
     ("ola:*dim-layer*" "\"DIMENSION\"" "and the error dimensions here The two perimeters are put onto the shop's own layers on the way out, so the...")
     ("ola:*new-color*" "3" "ACI for a created POOL layer Colours used only when a layer above has to be CREATED; a layer the drawing al...")
     ("ola:*og-color*" "1" "ACI for a created Bead Track Colours used only when a layer above has to be CREATED; a layer the drawing al...")
     ("ola:*dim-color*" "7" "ACI for a created DIMENSION Colours used only when a layer above has to be CREATED; a layer the drawing alr...")
     ("ola:*dim-style*" "\"STANDARD INCHES\"" "The dimension style the errors are drawn in. A drawing without it keeps whatever style is current and is to...")
     ("ola:*dimcount*" "4" "dimensions drawn How many of the worst spots to dimension. Each one is a local worst, so raising this finds...")
     ("ola:*peak-gap*" "0.07" "fraction of the perimeter How far apart two dimensions have to be, as a fraction of the perimeter. This is...")
     ("ola:*peak-min*" "0.0625" "drawing units (1/16\") An error smaller than this is not worth a dimension and the spot is skipped -- so a f...")
     ("ola:*peak-share*" "0.10" "fraction of the worst error ...and neither is one this much smaller than the worst error found. A fit alway...")
     ("ola:*text-push*" "0.045" "fraction of the bbox diagonal How far the dimension TEXT is dragged clear of the geometry, as a fraction of...")
     ("ola:*fitpts*" "96" "samples per perimeter Points each perimeter is walked out into for the fit. The phase search costs this SQU...")
     ("ola:*devpts*" "240" "samples along the original Points along the ORIGINAL at which the error is measured once the fit is in. Hig...")
     ("ola:*icp-win*" "6" "samples either side How far along the curve the polish may look for a better match, in samples either way....")
     ("ola:*fit-tol*" "0.001" "drawing units The polish stops when no point moved further than this, or after this many passes, whichever...")
     ("ola:*fit-max*" "60" "passes The polish stops when no point moved further than this, or after this many passes, whichever comes f...")
     ("ola:*fuzz*" "1.0e-4" "drawing units Closer than this and two ends are the same point -- ABHD's *PF-CHAIN-FUZZ*, so a perimeter re...")
     ("ola:*close-frac*" "0.01" "fraction of the chain length ...and the gap that still counts as closed, as a fraction of the chain's own l...")
     ("ola:*len-warn*" "0.10" "fraction of the longer perimeter How far apart the two PERIMETER LENGTHS may be before the pick itself look...")
     ("ola:*fit-warn*" "0.05" "fraction of the bbox diagonal ...and how big the worst error may be, against the diagonal of the original's...")
     ("ola:*piece-frac*" "0.05" "fraction of the chain length A pick that came in as more than one piece -- a stray deck line or coping arc...")
     ("ola:*mirror-ratio*" "0.5" "flipped residual / unflipped, at most -- mirror images ----------------------------------------------------..."))
    ("PADDLE" "lisp/paddle/PADDLE.lsp"
     ("*paddle-blkname*" "\"Pad36x36\"" "Edge of the pad in drawing units (a 36\" x 36\" square). This one number sets the pitch of the flush rows alo...")
     ("*paddle-padsize*" "36.0" "The dwg the block definitions are imported from when the drawing does not already hold them. Looked up with...")
     ("*paddle-blkfile*" "\"24inpad.dwg\"" "Layer the pads land on. Created when missing; an existing one is thawed, unlocked and turned on so the resu...")
     ("*paddle-layer*" "\"PADS\"" "AutoCAD colour index the layer is created with. An existing layer keeps whatever colour it already has. Lay...")
     ("*paddle-layer-color*" "7" "nil = every pad stays parallel to the X/Y axes (the shop standard). T = each pad rotates to follow its stre...")
     ("*paddle-align*" "nil" "nil = every pad stays parallel to the X/Y axes (the shop standard). T = each pad rotates to follow its stre...")
     ("*paddle-maxrad*" "54.0" "A connection point (line meets line, line meets arc, a polyline vertex) counts as a sharp inside corner onl...")
     ("*paddle-cornertol*" "(/ (* 30.0 pi) 180.0)" "A concave arc counts as a feature only when its total bend is MORE than this many degrees; a gentler sweep...")
     ("*paddle-arctol*" "(/ (* 10.0 pi) 180.0)" "A concave arc counts as a feature only when its total bend is MORE than this many degrees; a gentler sweep...")
     ("*paddle-fuzz*" "0.05" "--- reading the perimeter --- Largest gap between the end of one loose line/arc and the start of the next t...")
     ("*paddle-gapmax*" "36.0" "Layer the gap arrow is drawn on, and the colour index it is created with. A plain ACI number rather than 'a...")
     ("*paddle-gap-layer*" "\"PADDLE-GAP\"" "Layer the gap arrow is drawn on, and the colour index it is created with. A plain ACI number rather than 'a...")
     ("*paddle-gap-color*" "1" "Length of that arrow, tail to tip, in drawing units. Its head is a third of that long and three times as wi...")
     ("*paddle-arrow*" "36.0" "Length of that arrow, tail to tip, in drawing units. Its head is a third of that long and three times as wi...")
     ("*paddle-demo-layer*" "\"PADDLE-DEMO\"" "--- TUTORIALPADDLE --- Layer the tutorial draws its labelled sample perimeter on, and the colour index it i...")
     ("*paddle-demo-color*" "3" "--- TUTORIALPADDLE --- Layer the tutorial draws its labelled sample perimeter on, and the colour index it i..."))
    ("CPERP_POINTS" "lisp/perp_points/cperp_points.lsp"
     ("cperp:*ruler-color*" "3" "ACI colour of the rows you can PICK, carried on the entities themselves -------------------- tunables -----...")
     ("cperp:*ruler-current-color*" "7" "ACI colour of the ringed CURRENT row -- the last length -- so it reads apart from the options; 7 is AutoCAD...")
     ("cperp:*ruler-screen-x*" "0.88" "where the spine sits across the view, as a fraction of its width in from the left; past 0.5 the rows reach...")
     ("cperp:*ruler-row-frac*" "0.042" "one row's share of the view's height -- the ruler's size knob view, as a fraction of its width in from the...")
     ("cperp:*ruler-txt-frac*" "0.5" "the biggest row label's height, as a fraction of the row spacing height -- the ruler's size knob")
     ("cperp:*ruler-tick-frac*" "0.6" "the longest tick, same measure a fraction of the row spacing")
     ("cperp:*ruler-ring-frac*" "0.26" "the ring round the current row, as a fraction of the row spacing a fraction of the row spacing")
     ("cperp:*ruler-reach*" "6.0" "how far inboard of the spine, in row spacings, a click still counts as picking a row rather than as the fir..."))
    ("PERP_POINTS" "lisp/perp_points/perp_points.lsp"
     ("perp:*ruler-color*" "3" "ACI colour of the rows you can PICK, carried on the entities themselves -------------------- tunables -----...")
     ("perp:*ruler-current-color*" "7" "ACI colour of the ringed CURRENT row -- the last length -- so it reads apart from the options; 7 is AutoCAD...")
     ("perp:*ruler-screen-x*" "0.88" "where the spine sits across the view, as a fraction of its width in from the left; past 0.5 the rows reach...")
     ("perp:*ruler-row-frac*" "0.042" "one row's share of the view's height -- the ruler's size knob view, as a fraction of its width in from the...")
     ("perp:*ruler-txt-frac*" "0.5" "the biggest row label's height, as a fraction of the row spacing height -- the ruler's size knob")
     ("perp:*ruler-tick-frac*" "0.6" "the longest tick, same measure a fraction of the row spacing")
     ("perp:*ruler-ring-frac*" "0.26" "the ring round the current row, as a fraction of the row spacing a fraction of the row spacing")
     ("perp:*ruler-reach*" "6.0" "how far inboard of the spine, in row spacings, a click still counts as picking a row rather than as the fir..."))
    ("PERPMARK" "lisp/perpmark/PERPMARK.lsp"
     ("pm:*marklayer*" "\"PERPMARK\"" "Layer the circles and the perpendicular lines are drawn on. Change it to put the run's working marks somewh...")
     ("pm:*markcolor*" "1" "ACI colour that layer is CREATED with, on a drawing that lacks it. A number, not 'auto: these marks are the...")
     ("pm:*dimlayer*" "\"DIMENSION\"" "Layer and creation colour for the dimensions step 6 leaves behind.")
     ("pm:*dimcolor*" "7" "Layer and creation colour for the dimensions step 6 leaves behind.")
     ("pm:*dimstyle-std*" "\"STANDARD INCHES\"" "The two dimension styles step 6 offers, and their order in the question: STandard is the Enter answer. PERP...")
     ("pm:*dimstyle-side*" "\"SIDE STANDARD\"" "The two dimension styles step 6 offers, and their order in the question: STandard is the Enter answer. PERP...")
     ("pm:*point-block*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit What counts as a survey point. The classifier is the...")
     ("pm:*point-layer*" "\"POINTS\"" "layer whose POINTs and INSERTs are always points, whatever block points wherever they sit")
     ("pm:*pt-tag*" "\"number\"" "attribute tag on the point block naming the point. A block without it lends its first attribute that reads...")
     ("pm:*unknown*" "\"?\"" "what a point with no readable number is called. It can still be clicked; only a number can be typed naming...")
     ("pm:*pt-prefix*" "\"Pt.\"" "how a point is named in the prompts and the report number is called. It can still be clicked; only a number...")
     ("pm:*snap*" "12.0" "A click within this of a survey point picks that point. The number typed at the same prompt never uses it -...")
     ("pm:*fuzz*" "1e-6" "Two points closer than this are one point: it keeps a zero-length segment out of the joined polyline and a...")
     ("pm:*spike-tol*" "2.0" "How far a distance has to sit against BOTH its neighbours along the wall before the round names it: two inc...")
     ("pm:*ruler-color*" "3" "ACI colour of the rows you can PICK, carried on the entities themselves The LENGTH RULER beside the distanc...")
     ("pm:*ruler-current-color*" "7" "ACI colour of the ringed CURRENT row -- the last distance -- so it reads apart from the options; 7 is AutoC...")
     ("pm:*ruler-screen-x*" "0.88" "where the spine sits across the view, as a fraction of its width in from the left; past 0.5 the rows reach...")
     ("pm:*ruler-row-frac*" "0.042" "one row's share of the view's height -- the ruler's size knob view, as a fraction of its width in from the...")
     ("pm:*ruler-txt-frac*" "0.5" "the biggest row label's height, as a fraction of the row spacing height -- the ruler's size knob")
     ("pm:*ruler-tick-frac*" "0.6" "the longest tick, same measure a fraction of the row spacing")
     ("pm:*ruler-ring-frac*" "0.26" "the ring round the current row, as a fraction of the row spacing a fraction of the row spacing")
     ("pm:*ruler-reach*" "6.0" "how far inboard of the spine, in row spacings, a click still counts as picking a row rather than as the fir..."))
    ("POINTRENAMER" "lisp/pointrenamer/POINTRENAMER.lsp"
     ("ptr:*pt-layer*" "\"POINTS\"" "layer whose blocks count as points ABPCHECK's definition of a survey point, unchanged, so the two tools nev...")
     ("ptr:*pt-block*" "\"ab_pt\"" "block name that counts wherever it sits ABPCHECK's definition of a survey point, unchanged, so the two tool...")
     ("ptr:*pt-tag*" "\"number\"" "the attribute the number lives in ABPCHECK's definition of a survey point, unchanged, so the two tools neve...")
     ("ptr:*perim-layer*" "\"POOL\"" "Where the perimeter is looked for before anything is asked: the BIGGEST closed polyline on this layer insid...")
     ("ptr:*filter*" "'((0 . \"POINT,INSERT,LWPOLYLINE,POLYLINE\"))" "What the highlight is allowed to keep, so a hatch or a dimension cannot be dragged in by a sloppy window. L...")
     ("ptr:*vertex-skip*" "16" "Which vertices of an old-style (heavy) POLYLINE are NOT on the drawn curve, as a mask over the vertex flags...")
     ("ptr:*band*" "6.0" "How far off the perimeter still counts as on it -- what the FIRST run of a session offers, before anyone ha...")
     ("ptr:*dir*" "\"Clockwise\"" "Which way round the FIRST run of a session offers, on the same footing as the band. Spelled exactly as the...")
     ("ptr:*first*" "1" "The number the count starts at, offered at every run. Unlike the band and the direction this one is NOT car...")
     ("ptr:*sysvars*" "'(\"CMDECHO\")" "The sysvars saved on the way in and put back on the way out, however the run ends. Add a name here if a cha...")
     ("ptr:*far-pick*" "12.0" "A start pick further than this off the perimeter is called out. The sweep still begins at the nearest spot...")
     ("ptr:*name-width*" "8" "The width the OLD number is padded to in the old-to-new table, so the arrows line up. Widen it for a survey...")
     ("ptr:*dist-mode*" "4" "How every distance in a prompt or a report is written -- the two arguments of (rtos d MODE PRECISION). Mode...")
     ("ptr:*dist-prec*" "4" "How every distance in a prompt or a report is written -- the two arguments of (rtos d MODE PRECISION). Mode...")
     ("ptr:*exact-eps*" "1.0e-6" "Two spots closer together than this are the same spot -- the test for whether a closed polyline's last vert...")
     ("ptr:*zero-len*" "1.0e-6" "A perimeter shorter than this has nothing to sweep, so it is refused instead of divided by.")
     ("ptr:*bulge-eps*" "1.0e-9" "Below this a bulge is a straight line rather than an arc -- and so is the chord under one, which the same f...")
     ("ptr:*flat-eps*" "1.0e-10" "Below this a determinant has gone to zero: three points are collinear and have no circumcentre, and an arc'...")
     ("ptr:*tiny-len2*" "1.0e-20" "Below this a segment has no direction to project onto, so the nearest spot on it is simply its start. It is...")
     ("ptr:*whole-eps*" "1.0e-9" "How near a whole number a point's number has to read before the clash sweep counts it as one. A shot number...")
     ("ptr:*start-whisker*" "1.0e-4" "Added to every station before it is wrapped round the loop, so that a point clicked dead-on the start sorts..."))
    ("POOL" "lisp/pool/POOL.LSP"
     ("pool:*side-tol*" "1.0" "side length tolerance ---- field tolerances: how far the drawn pool may sit off the tape A crew's measureme...")
     ("pool:*cross-tol*" "2.0" "cross dimension (diagonal) tolerance ---- field tolerances: how far the drawn pool may sit off the tape A c...")
     ("pool:*grec-step*" "0.125" "Grecian diagonal adjustment increment ---- field tolerances: how far the drawn pool may sit off the tape A...")
     ("pool:*grec-max*" "4" "max increments each way (4 * 1/8 = 1/2) ---- field tolerances: how far the drawn pool may sit off the tape...")
     ("pool:*capfuzz*" "1.0e-6" "How far a corner treatment may exceed its own setback cap before the size is refused and re-asked. It exist...")
     ("pool:*lay-pool*" "\"POOL\"" "the pool perimeter and the bottom ---- output layers and their colours Made (or un-frozen, unlocked and swi...")
     ("pool:*lay-dim*" "\"DIMENSION\"" "every dimension and corner mark ---- output layers and their colours Made (or un-frozen, unlocked and switc...")
     ("pool:*lay-notes*" "\"POOL-NOTES\"" "guide, report, mini-model, dashed reference lines ---- output layers and their colours Made (or un-frozen,...")
     ("pool:*col-pool*" "4" "cyan, and only when POOL is created reference lines")
     ("pool:*col-dim*" "2" "yellow, ditto -- an existing layer keeps the colour the office gave it reference lines")
     ("pool:*col-notes*" "3" "green, on the same terms keeps the colour the office gave it")
     ("pool:*col-bad*" "1" "red -- a measurement the validator had to adjust, in the drawing and in the report table keeps the colour t...")
     ("pool:*dashname*" "\"POOLDASH\"" "---- linetypes Defined here rather than loaded from acad.lin: a failed load used to fall back to CONTINUOUS...")
     ("pool:*dashpat*" "'(12.0 -12.0)" "1 ft dash, 1 ft gap ---- linetypes Defined here rather than loaded from acad.lin: a failed load used to fal...")
     ("pool:*dotname*" "\"POOLDOT\"" "---- linetypes Defined here rather than loaded from acad.lin: a failed load used to fall back to CONTINUOUS...")
     ("pool:*dotpat*" "'(0.0 -1.0)" "a dot every inch; widen the gap for a sparser measuring line ---- linetypes Defined here rather than loaded...")
     ("pool:*smalldim*" "24.0" "---- dimension styles A style the drawing already defines is used as it stands -- the office template wins...")
     ("pool:*smallfuzz*" "1.0e-6" "---- dimension styles A style the drawing already defines is used as it stands -- the office template wins...")
     ("pool:*smallstyle*" "\"STANDARD INCHES\"" "---- dimension styles A style the drawing already defines is used as it stands -- the office template wins...")
     ("pool:*crossstyle*" "\"CROSS DIMENSIONS\"" "---- dimension styles A style the drawing already defines is used as it stands -- the office template wins...")
     ("pool:*sidestyle*" "\"SIDE STANDARD\"" "---- dimension styles A style the drawing already defines is used as it stands -- the office template wins...")
     ("pool:*given-den*" "8" "A \"Given\" mark (below) reads the SAME cut-off: under 24\" it is plain inches, at or past it feet-inches -- t...")
     ("pool:*doff-min*" "12.0" "never closer than 1 ft ---- how big the drawing furniture comes out Every flow sizes its dimension offsets...")
     ("pool:*doff-div*" "18.0" "---- how big the drawing furniture comes out Every flow sizes its dimension offsets and its text off the po...")
     ("pool:*th-min*" "3.0" "never smaller than 3\" ---- how big the drawing furniture comes out Every flow sizes its dimension offsets a...")
     ("pool:*th-div*" "70.0" "---- how big the drawing furniture comes out Every flow sizes its dimension offsets and its text off the po...")
     ("pool:*mark-r*" "0.18" "circle radius on the corner point ---- corner marks and callouts, as multiples of doff The square-corner ma...")
     ("pool:*mark-lead*" "1.2" "how far out the mark's own text sits ---- corner marks and callouts, as multiples of doff The square-corner...")
     ("pool:*ng-lead*" "1.5" "where the \"Not Given\" leader leaves it ---- corner marks and callouts, as multiples of doff The square-corn...")
     ("pool:*ng-off*" "2.05" "... and how far out that note sits ---- corner marks and callouts, as multiples of doff The square-corner m...")
     ("pool:*rad-off*" "0.9" "radius dim, dragged out past the arc ---- corner marks and callouts, as multiples of doff The square-corner...")
     ("pool:*cut-off*" "0.5" "cut-face dim, out past the face ---- corner marks and callouts, as multiples of doff The square-corner mark...")
     ("pool:*mlkoff*" "30.0" "M/L/K dim line, right of the hopper ---- where the bottom's chain dimensions sit The H/G/F/E chain runs bel...")
     ("pool:*chainoff*" "12.0" "H/G/F/E drop: at most this... ---- where the bottom's chain dimensions sit The H/G/F/E chain runs below the...")
     ("pool:*chaindiv*" "6.0" "...and at most hopper width / this ---- where the bottom's chain dimensions sit The H/G/F/E chain runs belo...")
     ("pool:*rep-gap*" "2.0" "doff multiples: pool -> table ---- the report table and the mini-model beside it Column positions are multi...")
     ("pool:*rep-row*" "2.2" "h multiples: row pitch ---- the report table and the mini-model beside it Column positions are multiples of...")
     ("pool:*rep-title*" "1.25" "h multiples: the heading's text height ---- the report table and the mini-model beside it Column positions...")
     ("pool:*rep-note*" "1.4" "h multiples: a red failure note ---- the report table and the mini-model beside it Column positions are mul...")
     ("pool:*rep-c1*" "20.0" "h multiples: the TARGET column ---- the report table and the mini-model beside it Column positions are mult...")
     ("pool:*rep-c2*" "29.0" "ACTUAL, decimal inches ---- the report table and the mini-model beside it Column positions are multiples of...")
     ("pool:*rep-c2f*" "33.0" "ACTUAL, feet-inches ---- the report table and the mini-model beside it Column positions are multiples of th...")
     ("pool:*rep-c3*" "38.0" "DELTA, decimal inches ---- the report table and the mini-model beside it Column positions are multiples of...")
     ("pool:*rep-c3f*" "46.0" "DELTA, feet-inches ---- the report table and the mini-model beside it Column positions are multiples of the...")
     ("pool:*rep-w*" "46.0" "table width, decimal inches ---- the report table and the mini-model beside it Column positions are multipl...")
     ("pool:*rep-wf*" "54.0" "table width, feet-inches ---- the report table and the mini-model beside it Column positions are multiples...")
     ("pool:*map-gap*" "3.0" "th multiples: table -> mini-model ---- the report table and the mini-model beside it Column positions are m...")
     ("pool:*map-size*" "24.0" "th multiples: the mini-model's box ---- the report table and the mini-model beside it Column positions are...")
     ("pool:*pv-col*" "'auto" "guide outline: 'auto picks the grey for the background (8 is nearly the stock dark one), a number is used e...")
     ("pool:*pvx-col*" "7" "cross-dim / measuring line (white) grey for the background (8 is nearly the stock dark one), a number is us...")
     ("pool:*hi-col*" "1" "the element being asked for (red) grey for the background (8 is nearly the stock dark one), a number is use...")
     ("pool:*pv-margin*" "30.0" "smallest margin round the guide's zoom grey for the background (8 is nearly the stock dark one), a number i...")
     ("pool:*pv-churn*" "0.05" "re-zoom only when the box moved this much of its own width -- lower follows the shape more closely and flic...")
     ("pool:*fit-iter*" "3000" "relaxation sweeps, pulling phase ---- the fitting engine Two passes, both iterative: sides held exactly tru...")
     ("pool:*fit-polish*" "400" "sweeps of the sides-only finish ---- the fitting engine Two passes, both iterative: sides held exactly true...")
     ("pool:*fit-quad*" "2000" "sweeps for the four-corner relaxation ---- the fitting engine Two passes, both iterative: sides held exactl...")
     ("pool:*fit-slack*" "0.05" "how far outside a band still passes ---- the fitting engine Two passes, both iterative: sides held exactly...")
     ("pool:*alfa-lo*" "15.0" "degrees: the flattest corner A the scan will consider The four-bar scan: the angle at corner A is swept coa...")
     ("pool:*alfa-hi*" "165.0" "and the sharpest; narrowing the pair is faster and can miss a real fit scan will consider")
     ("pool:*alfa-step*" "0.25" "coarse sweep; finer costs every run is faster and can miss a real fit")
     ("pool:*alfa-fine*" "0.3" "how far either side the fine sweep runs is faster and can miss a real fit")
     ("pool:*alfa-fstep*" "0.005" "fine sweep, and the angle the fit is finally read to is faster and can miss a real fit")
     ("pool:*grecth-step*" "0.00087" "radians, ~ 0.05 degree The Grecian end solver: the diagonal angle is scanned for the one that reproduces th...")
     ("pool:*grec-fit*" "0.0625" "accept an end within 1/16\" The Grecian end solver: the diagonal angle is scanned for the one that reproduce...")
     ("pool:*half-ratio*" "0.5" "A pool runs about twice as long as it is wide, so the width question is offered this fraction of the length...")
     ("pool:*treat-default*" "\"\"" "What the FIRST corner's treatment question offers on Enter, before there is a previous answer to reuse: \"\"...")
     ("pool:*quarter*" "0.25" "A derived letter is quoted to the nearest quarter inch -- the granularity a tape is actually read to (pool:...")
     ("pool:*fixfloor*" "12.0" "A sheet letter that does not close positive against its overall is lifted to a positive floor and the repor...")
     ("pool:*hookslack*" "0.0625" "---- how far a wall dim may slide to stay ON the pool A corner UNDER 90 degrees pokes out past its own trea...")
     ("pool:*sq90-tol*" "(* pi (/ 20.0 180.0))" "---- when a corner may be called square on the sheet How far off 90 a corner may sit and still be marked \"9...")
     ("pool:*btypes*" "\"Normal Sport Wedge SLope MOdflat SHallow\"" "---- vocabulary Bottom-type keywords, shared by the rectangle / oval / grecian dispatchers. Normal and the...")
     ("pool:*btshown*" "\"Normal/Sport/Wedge/SLope/MOdflat/SHallow\"" "---- vocabulary Bottom-type keywords, shared by the rectangle / oval / grecian dispatchers. Normal and the...")
     ("pool:*grecnpts*" "(list (list 0.0 0.0) (list 360.0 0.0) (list 410.0 55.0) (list 410.0 125.0) (list 360.0 180.0) (list 0.0 180.0) (list -50.0 125.0) (list -50.0 55.0))" "---- nominal guide rings What the Grecian and Octagon guides look like before any measurement is in. The oc...")
     ("pool:*octnpts*" "(list (list 87.87 0.0) (list 212.13 0.0) (list 300.0 87.87) (list 300.0 212.13) (list 212.13 300.0) (list 87.87 300.0) (list 0.0 212.13) (list 0.0 87.87))" "...and the octagon's, which a change here resizes on screen and nowhere else -- the first answer rescales i..."))
    ("POOLSIDE" "lisp/poolside/POOLSIDE.lsp"
     ("psd:*base*" "(list 0.0 0.0)" "insertion base for this run")
     ("psd:*sysold*" "nil" "the user's sysvars, pending restore")
     ("psd:*pvents*" "nil" "live guide entities")
     ("psd:*valnotes*" "nil" "validation problems, for the notes")
     ("psd:*pv-col*" "'auto" "guide outline color: 'auto picks it for the background (grey either way round), a number is used as given")
     ("psd:*pvx-col*" "7" "guide measuring-tie color (white) it for the background (grey either way round), a number is used as given")
     ("psd:*hi-col*" "1" "highlight color (red) it for the background (grey either way round), a number is used as given")
     ("psd:*btypes*" "\"Normal Sport Wedge SLope MOdflat SHallow\"" "The six bottom types, POOL's own keywords and capitalization -- the palette and the field sheets both speak...")
     ("psd:*btshown*" "\"Normal/Sport/Wedge/SLope/MOdflat/SHallow\"" "The six bottom types, POOL's own keywords and capitalization -- the palette and the field sheets both speak..."))
    ("SMARTFILLET" "lisp/smartfillet/SMARTFILLET.lsp"
     ("sf:*first*" "6.0" "the smallest radius offered, and the step")
     ("sf:*step*" "6.0" "between the ones after it -- 6\" of radius is the smallest difference that reads on a pool plan")
     ("sf:*extras*" "'(3.0 9.0)" "radii offered BESIDES that series. A 3 or a 9 turns up, just not often enough to be the step; they are draw...")
     ("sf:*maxshown*" "10" "how many previews may be on screen at once; nil = every radius that fits, which on a long wall is a great m...")
     ("sf:*fit*" "0.98" "how much of the shorter leg a fillet may use up: 1.0 would put the tangent point exactly on the far end and...")
     ("sf:*layer*" "\"SMART FILLET PREVIEW\"" "use up: 1.0 would put the tangent point exactly on the far end and leave a zero-length line behind")
     ("sf:*color*" "3" "the layer's colour, and the fallback index on every preview: green, so a preview reads as a preview even wh...")
     ("sf:*shade-lo*" "'(190 255 190)" "the SMALLEST preview's green ... index on every preview: green, so a preview reads as a preview even where...")
     ("sf:*shade-hi*" "'(0 110 0)" "... and the largest's. The fan is graded between the two, so which arc a label belongs to is a matter of sh...")
     ("sf:*trans*" "40" "per cent transparency on every preview, so an arc crossing another still reads. 0 or nil = solid; over 90 i...")
     ("sf:*ltype*" "\"DASHED\"" "so an arc crossing another still reads. 0 or nil = solid; over 90 is a preview nobody can see")
     ("sf:*ltscale*" "0.25" "the stock DASHED pattern is 18 units long, so a 6\" fillet arc (9 units of it) would come out as one unbroke...")
     ("sf:*guide*" "t" "nil = never draw one, and a far-off corner is a fan of green arcs floating in space again long, so a 6\" fil...")
     ("sf:*gapmin*" "4.5" "how far short of the corner a line has to stop before it gets one. The stock DASHED pattern is 18 units and...")
     ("sf:*label*" "t" "stop before it gets one. The stock DASHED pattern is 18 units and sf:*ltscale* takes a quarter of it, so a...")
     ("sf:*txthgt*" "4.0" "small enough that two labels a 6\" step apart clear each other side to side stop before it gets one. The sto...")
     ("sf:*rung*" "1.4" "and each one climbs this many text heights further off its leg than the label before it on that side, so th...")
     ("sf:*dimlayer*" "\"DIMENSION\"" "heights further off its leg than the label before it on that side, so they cannot collide however tight the...")
     ("sf:*smalldim*" "24.0" "POOL's small-dimension rule, heights further off its leg than the label before it on that side, so they can...")
     ("sf:*smallstyle*" "\"STANDARD INCHES\"" "kept so a fillet callout matches the dims beside it heights further off its leg than the label before it on...")
     ("sf:*dimoff*" "nil" "nil = one radius past the arc matches the dims beside it")
     ("sf:*dimrepeat*" "nil" "one callout plus \"Typ.\" is how the sheet reads; set T to dimension every corner matches the dims beside it")
     ("sf:*typ*" "t" "reads; set T to dimension every corner")
     ("sf:*minang*" "0.02" "how far off straight (radians) two legs must be before there is a corner at all reads; set T to dimension e...")
     ("sf:*sysold*" "nil" "sysvar snapshot, live only mid-run")
     ("sf:*preview*" "nil" "every entity drawn as a preview")
     ("sf:*picks*" "nil" "(preview-arc . radius), what a click means")
     ("sf:*smallwarned*" "nil" "the missing-style note is said once"))
    ("SOCONV" "lisp/soconv/SOCONV.lsp"
     ("*soconv-map*" "'((\"Pool Perimeter\" \"*\" \"POOL\") (\"Obstacles\" \"*\" \"POOL\") (\"LEICA_DISTO_POINT_ENTITY\" \"POINT\" \"POINTS\") (\"Existing Anchorss\" \"POINT\" \"POINTS\") (\"Existing Anchors\" \"POINT\" \"POINTS\") (\"Dimensions\" \"TEXT,MTEXT\" \"TEXT\") (\"Dimensions\" \"*\" \"DIMENSION\"))" "The conversion itself, one row per rule: (source-layer entity-types destination-layer) Both patterns are wc...")
     ("*soconv-colors*" "'((\"POOL\" . 4) ; cyan, as POOL.LSP creates it (\"POINTS\" . 6) ; magenta - the pink survey points read as (\"TEXT\" . 4) (\"DIMENSION\" . 141))" "What to CREATE a destination layer with when the drawing has not got it. An existing layer is never recolou...")
     ("*soconv-default-color*" "7" "The colour for a destination the table above does not name - what a retuned *soconv-map* row pointing at a...")
     ("*soconv-force-bylayer*" "nil" "nil, and a moved object keeps every property it arrived with, which is what the sample conversion does. T i...")
     ("*soconv-record*" "t" "The record SORECONV reads back, and the application it lives under. nil converts exactly as before and writ...")
     ("*soconv-xdata-app*" "\"SOCONV\"" "The record SORECONV reads back, and the application it lives under. nil converts exactly as before and writ..."))
    ("SPA" "lisp/spa/SPA.LSP"
     ("spa:*dimlunit*" "5" "5 = fractional (84-1/2), 2 = decimal (84.50) ---- dimension text Every dimension is written in standard inc...")
     ("spa:*dimprec*" "3" "5 -> 1/8\", 2 -> 3 decimal places ---- dimension text Every dimension is written in standard inches whatever...")
     ("spa:*dimpost*" "\"\\\"\"" "---- dimension text Every dimension is written in standard inches whatever the host drawing is set to. Anyt...")
     ("spa:*dim-asz*" "0.8" "arrow size; raise for a bolder dim The dimension furniture is sized off the drawing's note height th, so th...")
     ("spa:*dim-exe*" "0.6" "extension line past the dim line The dimension furniture is sized off the drawing's note height th, so the...")
     ("spa:*dim-exo*" "0.6" "extension line offset from the outline The dimension furniture is sized off the drawing's note height th, s...")
     ("spa:*dim-gap*" "0.4" "gap round the text The dimension furniture is sized off the drawing's note height th, so the numbers read a...")
     ("spa:*dimvars*" "'(\"DIMLUNIT\" \"DIMFRAC\" \"DIMDEC\" \"DIMZIN\" \"DIMPOST\" \"DIMTAD\" \"DIMTMOVE\" \"DIMTXT\" \"DIMASZ\" \"DIMEXE\" \"DIMEXO\" \"DIMGAP\" \"DIMSCALE\" \"DIMTIX\" \"DIMTOFL\" \"DIMATFIT\")" "The system variables the routine sets for the run and puts back afterwards. A variable this release does no...")
     ("spa:*dimoff*" "36.0" "3 ft: cover outline -> the LEFT overall dim ---- where the dimension lines stand off The COVER's overalls g...")
     ("spa:*topoff*" "24.0" "2 ft: cover outline -> the TOP overall dim ---- where the dimension lines stand off The COVER's overalls go...")
     ("spa:*flatoff*" "18.0" "outline -> the inboard flat dims ---- where the dimension lines stand off The COVER's overalls go outside t...")
     ("spa:*insetfrac*" "0.3333" "water's edge dims, a third of the way in ---- where the dimension lines stand off The COVER's overalls go o...")
     ("spa:*lapoff*" "14.0" "how far under the cover the lap note sits ---- where the dimension lines stand off The COVER's overalls go...")
     ("spa:*mark-r*" "0.18" "circle radius on the corner point ---- corner callouts, as multiples of doff A radius corner takes a radius...")
     ("spa:*mark-lead*" "1.2" "how far out the mark's own text sits ---- corner callouts, as multiples of doff A radius corner takes a rad...")
     ("spa:*ng-lead*" "1.5" "where the \"Not Given\" leader leaves it ---- corner callouts, as multiples of doff A radius corner takes a r...")
     ("spa:*ng-off*" "2.05" "... and how far out that note sits ---- corner callouts, as multiples of doff A radius corner takes a radiu...")
     ("spa:*rad-off*" "0.9" "radius dim, dragged out past the arc ---- corner callouts, as multiples of doff A radius corner takes a rad...")
     ("spa:*cut-off*" "0.6" "cut-face dim, out past the face ---- corner callouts, as multiples of doff A radius corner takes a radius d...")
     ("spa:*oct-off*" "0.8" "the octagon's one cut callout ---- corner callouts, as multiples of doff A radius corner takes a radius dim...")
     ("spa:*doff-min*" "6.0" "never closer than 6\" ---- how big the drawing furniture comes out Both flows size their dimension offsets a...")
     ("spa:*doff-div*" "12.0" "---- how big the drawing furniture comes out Both flows size their dimension offsets and text off the spa i...")
     ("spa:*th-min*" "1.0" "never smaller than 1\" ---- how big the drawing furniture comes out Both flows size their dimension offsets...")
     ("spa:*th-div*" "40.0" "---- how big the drawing furniture comes out Both flows size their dimension offsets and text off the spa i...")
     ("spa:*hingetxth*" "5.0" "hinge label height ---- hinge lettering and linework Matched to the office template's before/after sample:...")
     ("spa:*hingetxw*" "60.0" "hinge label MTEXT frame width ---- hinge lettering and linework Matched to the office template's before/aft...")
     ("spa:*hingestyle*" "\"Attributes\"" "label style (Standard when absent) ---- hinge lettering and linework Matched to the office template's befor...")
     ("spa:*hingetxoff*" "0.6" "label height multiples: line -> label ---- hinge lettering and linework Matched to the office template's be...")
     ("spa:*hdashmult*" "20.0" "DASHED2 0.25\" dash x 20 = 5\" on paper ---- hinge lettering and linework Matched to the office template's be...")
     ("spa:*sfx-water*" "\"Water's Edge\"" "---- the note stacked under every overall")
     ("spa:*sfx-cover*" "\"Cover Size\"" "---- the note stacked under every overall")
     ("spa:*lay-water*" "\"POOL\"" "water's edge perimeter (dashed) ---- output layers and their colours Made (or un-frozen, unlocked and switc...")
     ("spa:*lay-cover*" "\"COVER\"" "cover size perimeter ---- output layers and their colours Made (or un-frozen, unlocked and switched back on...")
     ("spa:*lay-dim*" "\"DIMENSION\"" "every dimension and corner mark ---- output layers and their colours Made (or un-frozen, unlocked and switc...")
     ("spa:*lay-notes*" "\"SPA-NOTES\"" "the mini-model and its corner letters, the mode note, the report, and the grey input guide ---- output laye...")
     ("spa:*lay-text*" "\"TEXT\"" "the Hinge / Velcro Hinge labels The hinges themselves are cover hardware, so they are drawn on the cover's...")
     ("spa:*lay-hinge*" "\"COVER\"" "The hinges themselves are cover hardware, so they are drawn on the cover's layer even on a sheet that shows...")
     ("spa:*col-water*" "4" "cyan, and only when POOL is created The hinges themselves are cover hardware, so they are drawn on the cove...")
     ("spa:*col-cover*" "6" "magenta, ditto -- an existing layer keeps the colour the office gave it The hinges themselves are cover har...")
     ("spa:*col-dim*" "2" "yellow, on the same terms keeps the colour the office gave it")
     ("spa:*col-notes*" "3" "green, on the same terms keeps the colour the office gave it")
     ("spa:*col-text*" "7" "white or black, whichever the background makes it keeps the colour the office gave it")
     ("spa:*col-bad*" "1" "red -- a letter the validator adjusted background makes it")
     ("spa:*col-advice*" "4" "cyan -- a recommendation, not a failure background makes it")
     ("spa:*dashname*" "\"SPADASH\"" "---- linetypes Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTI...")
     ("spa:*dashpat*" "'(4.0 -3.0)" "---- linetypes Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTI...")
     ("spa:*dotname*" "\"SPADOT\"" "---- linetypes Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTI...")
     ("spa:*dotpat*" "'(0.0 -3.0)" "---- linetypes Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTI...")
     ("spa:*hdashname*" "\"DASHED2\"" "the stock fold-hinge pattern ---- linetypes Defined here rather than loaded from acad.lin, so a failed load...")
     ("spa:*hdashpat*" "'(0.25 -0.125)" "---- linetypes Defined here rather than loaded from acad.lin, so a failed load can never fall back to CONTI...")
     ("spa:*ds-cover*" "\"STANDARD INCHES\"" "---- dimension styles, one per outline A style the drawing already defines is used exactly as it stands --...")
     ("spa:*ds-water*" "\"STANDARD INCHES 0.5\"" "---- dimension styles, one per outline A style the drawing already defines is used exactly as it stands --...")
     ("spa:*wefactor*" "0.5" "---- dimension styles, one per outline A style the drawing already defines is used exactly as it stands --...")
     ("spa:*gapdflt*" "6.0" "suggested cover lap over the water's edge ---- dimension styles, one per outline A style the drawing alread...")
     ("spa:*diagoff*" "0.82842712" "Offsetting a corner by g is not the same for every treatment: a radius stays concentric (r -> r + g) and a...")
     ("spa:*capfuzz*" "1.0e-6" "How far a corner treatment may exceed its own setback cap before the size is refused and re-asked. Float no...")
     ("spa:*octeq*" "0.125" "How far the eight sides of an octagon may differ and still count as \"all equal\" -- a rounded-off cut face l...")
     ("spa:*sameeps*" "0.0005" "...and how far two corners' sizes may differ and still be one treatment for the Typ. rule.")
     ("spa:*rep-row*" "2.2" "h multiples: row pitch ---- the report table and the mini-model beside it Column positions are multiples of...")
     ("spa:*rep-title*" "1.25" "h multiples: the heading's text height ---- the report table and the mini-model beside it Column positions...")
     ("spa:*rep-note*" "1.4" "h multiples: a red failure note ---- the report table and the mini-model beside it Column positions are mul...")
     ("spa:*rep-advice*" "1.15" "h multiples: a cyan recommendation ---- the report table and the mini-model beside it Column positions are...")
     ("spa:*rep-c1*" "20.0" "h multiples: the TARGET column ---- the report table and the mini-model beside it Column positions are mult...")
     ("spa:*rep-c2*" "29.0" "the ACTUAL column; move it out if a measurement ever runs into it ---- the report table and the mini-model...")
     ("spa:*rep-c3*" "38.0" "the DELTA column, on the same terms measurement ever runs into it")
     ("spa:*rep-w*" "46.0" "how wide the ruled box comes out measurement ever runs into it")
     ("spa:*map-gap*" "3.0" "th multiples: table -> the mini-model measurement ever runs into it")
     ("spa:*map-size*" "24.0" "th multiples: the mini-model's fit box measurement ever runs into it")
     ("spa:*pv-col*" "'auto" "guide outline: 'auto picks the grey for the background (8 is nearly the stock dark one), a number is used e...")
     ("spa:*pvx-col*" "7" "measuring tie (white) grey for the background (8 is nearly the stock dark one), a number is used exactly as...")
     ("spa:*hi-col*" "1" "the element being asked for (red) The RECTANGLE guide's nominal box. The octagon and round guides keep thei...")
     ("spa:*pv-w*" "240.0" "nominal guide width The RECTANGLE guide's nominal box. The octagon and round guides keep their own ring in...")
     ("spa:*pv-l*" "200.0" "nominal guide length The RECTANGLE guide's nominal box. The octagon and round guides keep their own ring in...")
     ("spa:*pv-th*" "12.0" "guide corner-letter height The RECTANGLE guide's nominal box. The octagon and round guides keep their own r...")
     ("spa:*pv-tie*" "10.0" "guide tie-letter height The RECTANGLE guide's nominal box. The octagon and round guides keep their own ring...")
     ("spa:*pv-lbl*" "22.0" "how far a rectangle corner letter sits out The RECTANGLE guide's nominal box. The octagon and round guides...")
     ("spa:*pv-olbl*" "20.0" "...and an octagon one, which sits tighter The RECTANGLE guide's nominal box. The octagon and round guides k...")
     ("spa:*pv-cap*" "50.0" "biggest treatment the guide will draw, so one huge corner cannot swallow it The RECTANGLE guide's nominal b...")
     ("spa:*pv-zoom*" "0.35" "margin round the real spa when the view leaves the guide for it (of its long side) so one huge corner canno...")
     ("spa:*foamtab*" "(list (list \"ECONOMY\" \"3-2\" (list (cons 48.0 96.0)) (list 2)) (list \"STANDARD\" \"3-2\" (list (cons 48.0 144.0) (cons 49.5 102.0)) (list 2)) (list \"STANDARD\" \"4-2\" (list (cons 48.0 96.0) (cons 49.5 102.0)) (list 2 3 4)) (list \"STANDARD\" \"4-3\" (list (cons 48.0 144.0)) (list 2 3 4)) (list \"STANDARD\" \"5-3\" (list (cons 48.0 96.0)) (list 2 3 4 5)) (list \"STANDARD\" \"5-4\" (list (cons 48.0 96.0)) (list 2 3 4 5)) (list \"STANDARD\" \"3-3\" (list (cons 48.0 144.0)) (list 2 3 4 5)) (list \"ULTRA\" \"3-2\" (list (cons 48.0 144.0)) (list 2)) (list \"ULTRA\" \"4-3\" (list (cons 48.0 96.0)) (list 2 3 4)) (list \"ULTRA\" \"3-3\" (list (cons 48.0 144.0)) (list 2 3 4 5)) (list \"THERMOLIGHT\" \"1-3/8\" (list (cons 53.0 nil)) (list 2 3 4 5)))" "---- the foam sheet THE SHOP DATA THIS ROUTINE IS BUILT ON. Grade and taper -- read off the Spa Cover Detai...")
     ("spa:*foamdflt*" "(list (cons 48.0 96.0))" "assumed when nothing matches")
     ("spa:*foamdpc*" "(list 2 3 4 5)" "and the counts it will accept")
     ("spa:*thermotaper*" "\"1-3/8\"" "the one taper a Thermo-Light comes in")
     ("spa:*hardtab*" "(list ; grade velcro double C hold down (list \"ECONOMY\" '(REQUEST) '(REQUEST) '(REQUEST)) (list \"STANDARD\" '(OVER 120.0) '(OVER 108.0) '(OVER 120.0)) (list \"ULTRA\" '(OVER 108.0) '(NEVER) '(OVER 96.0)) (list \"THERMOLIGHT\" '(ALWAYS) '(NEVER) '(NEVER)))" "---- hardware called for by the LONGEST hinge, per grade Each rule is (OVER <inches>) | (ALWAYS) | (NEVER)...")
     ("spa:*hardnames*" "(list \"VELCRO HINGES\" \"DOUBLE C CHANNEL\" \"HOLD DOWN KIT\")" "What the three columns are called in the report, in the order the table above holds them -- rename one and...")
     ("spa:*hinge-min*" "2" "a cover is never fewer pieces than this ---- the hinge placement solver The fewest pieces that fit the foam...")
     ("spa:*hinge-try*" "3" "how many extra piece counts to try ---- the hinge placement solver The fewest pieces that fit the foam widt...")
     ("spa:*hinge-edge*" "0.01" "keep a hinge this far off the cover's edge ---- the hinge placement solver The fewest pieces that fit the f...")
     ("spa:*allcorners*" "\"the four corners\"" "---- vocabulary The subject the all-same round asks about, spelled ONCE: it is the label the treatment ques..."))
    ("SPACHECK" "lisp/spacheck/SPACHECK.lsp"
     ("spachk:*lay-cover*" "\"COVER\"" "the cover outline and the hinges Layers SPA draws on -- the audit is only as right as these are.")
     ("spachk:*lay-water*" "\"POOL\"" "the water's edge outline Layers SPA draws on -- the audit is only as right as these are.")
     ("spachk:*lay-dim*" "\"DIMENSION\"" "every dimension Layers SPA draws on -- the audit is only as right as these are.")
     ("spachk:*lay-text*" "\"TEXT\"" "the hinge labels Layers SPA draws on -- the audit is only as right as these are.")
     ("spachk:*lay-notes*" "\"SPA-NOTES\"" "corner letters, mode note, report Layers SPA draws on -- the audit is only as right as these are.")
     ("spachk:*dimfix-cmd*" "\"CDIM\"" "CDIM is the command that moves stray dimensions onto *lay-dim*, and is what the report tells you to run whe...")
     ("spachk:*techtitle-block*" "\"Tech Title\"" "spaces optional in the name The sheet's title block, and the attribute in it carrying the date. This is the...")
     ("spachk:*date-tag*" "\"Date\"" "The sheet's title block, and the attribute in it carrying the date. This is the Tech Title BLOCK, not the d...")
     ("spachk:*ds-cover*" "\"STANDARD INCHES\"" "Dimension styles, one per outline (SPA's spa:*ds-cover* / *ds-water*).")
     ("spachk:*ds-water*" "\"STANDARD INCHES 0.5\"" "Dimension styles, one per outline (SPA's spa:*ds-cover* / *ds-water*).")
     ("spachk:*sfx-cover*" "\"Cover Size\"" "The notes SPA stacks under an overall's measurement.")
     ("spachk:*sfx-water*" "\"Water's Edge\"" "The notes SPA stacks under an overall's measurement.")
     ("spachk:*sfx-lap*" "\"Overlap\"" "The notes SPA stacks under an overall's measurement.")
     ("spachk:*topoff*" "24.0" "2 ft: cover -> the TOP overall dim SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a dim...")
     ("spachk:*dimoff*" "36.0" "3 ft: cover -> the LEFT overall dim SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a di...")
     ("spachk:*off-tol*" "2.0" "inches of slack on either standoff SPA's standoffs (spa:*topoff* / *dimoff* / *flatoff*), and how far a dim...")
     ("spachk:*details-block*" "\"Spa Cover Details\"" "The block SPA reads the grade and taper out of.")
     ("spachk:*liner-w*" "704.0" "58'-8\" in drawing units TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc...")
     ("spachk:*liner-h*" "543.625" "45'-3 5/8\" in drawing units TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* /...")
     ("spachk:*title-frac*" "0.6" "spa title block = 0.6 x the liner TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border...")
     ("spachk:*border-layer*" "\"border\"" "TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-border-w* / *lfc-border-h*); a spa sheet...")
     ("spachk:*border-tol*" "0.005" "0.5% slack on the factor and the aspect TITLE BLOCK. The liner block is linfincheck's nominal border (*lfc-...")
     ("spachk:*meas-tol*" "0.0625" "1/16\" -- a fractional dim rounds How close a dimension's measurement must be to the geometry it spans, and...")
     ("spachk:*pt-tol*" "1.0e-4" "How close a dimension's measurement must be to the geometry it spans, and how close a definition point must...")
     ("spachk:*grey-color*" "8" "ACI: reserved for fading, unused today")
     ("spachk:*flag-color*" "1" "ACI: what you confirmed is wrong (red)")
     ("spachk:*advice-color*" "4" "ACI: advice, not a failure (cyan)")
     ("spachk:*green-scale*" "0.75" "all-clear text height vs the red")
     ("spachk:*report-layer*" "\"SPACHECK-REPORT\"" "The layer the report MTEXT goes on, created on first use; the colour applies only then, so a layer already...")
     ("spachk:*report-color*" "3" "ACI (green) The layer the report MTEXT goes on, created on first use; the colour applies only then, so a la...")
     ("spachk:*report-chars*" "48.0" "report column width, in text heights The layer the report MTEXT goes on, created on first use; the colour a...")
     ("spachk:*zoom-margin*" "0.75" "empty space around a zoomed item The layer the report MTEXT goes on, created on first use; the colour appli...")
     ("spachk:*foamtab*" "(list (list \"ECONOMY\" \"3-2\" (list (cons 48.0 96.0)) (list 2)) (list \"STANDARD\" \"3-2\" (list (cons 48.0 144.0) (cons 49.5 102.0)) (list 2)) (list \"STANDARD\" \"4-2\" (list (cons 48.0 96.0) (cons 49.5 102.0)) (list 2 3 4)) (list \"STANDARD\" \"4-3\" (list (cons 48.0 144.0)) (list 2 3 4)) (list \"STANDARD\" \"5-3\" (list (cons 48.0 96.0)) (list 2 3 4 5)) (list \"STANDARD\" \"5-4\" (list (cons 48.0 96.0)) (list 2 3 4 5)) (list \"STANDARD\" \"3-3\" (list (cons 48.0 144.0)) (list 2 3 4 5)) (list \"ULTRA\" \"3-2\" (list (cons 48.0 144.0)) (list 2)) (list \"ULTRA\" \"4-3\" (list (cons 48.0 96.0)) (list 2 3 4)) (list \"ULTRA\" \"3-3\" (list (cons 48.0 144.0)) (list 2 3 4 5)) (list \"THERMOLIGHT\" \"1-3/8\" (list (cons 53.0 nil)) (list 2 3 4 5)))" "Foam sheets, copied from SPA (spa:*foamtab*) so the audit measures against the same rules the drawing was b...")
     ("spachk:*hardtab*" "(list (list \"ECONOMY\" '(REQUEST) '(REQUEST) '(REQUEST)) (list \"STANDARD\" '(OVER 120.0) '(OVER 108.0) '(OVER 120.0)) (list \"ULTRA\" '(OVER 108.0) '(NEVER) '(OVER 96.0)) (list \"THERMOLIGHT\" '(ALWAYS) '(NEVER) '(NEVER)))" "Hardware called for by the LONGEST hinge, per grade: (grade velcro doubleC holddown), each (OVER n) | (ALWA...")
     ("spachk:*hallow-max*" "5" "pieces A piece count this high or higher is the table's top row (\"5 = 5+\").")
     ("spachk:*grade-tag*" "\"GRADE\"" "The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as...")
     ("spachk:*taper-tag*" "\"TAPER\"" "The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as...")
     ("spachk:*grade-words*" "'((\"ECON\" . \"ECONOMY\") (\"ULTRA\" . \"ULTRA\") (\"FRP\" . \"ULTRA\") (\"THERMO\" . \"THERMOLIGHT\"))" "The details block's two attribute tags, and how their values are recognised. GRADE and TAPER are matched as...")
     ("spachk:*grade-default*" "\"STANDARD\"" "the grade a value matching nothing takes ...and the taper vocabulary, matched the same way; an unrecognised...")
     ("spachk:*taper-words*" "'((\"3-2\" . \"3-2\") (\"4-2\" . \"4-2\") (\"4-3\" . \"4-3\") (\"5-3\" . \"5-3\") (\"5-4\" . \"5-4\") (\"3-3\" . \"3-3\") (\"3/8\" . \"1-3/8\"))" "...and the taper vocabulary, matched the same way; an unrecognised taper measures against no foam row at al...")
     ("spachk:*grade-short*" "'((\"ECONOMY\" . \"ECO\") (\"STANDARD\" . \"STD\") (\"ULTRA\" . \"ULTRA\") (\"THERMOLIGHT\" . \"THERMO\"))" "The short grade names the report prints, keyed by the canonical name.")
     ("spachk:*outline-types*" "'(\"LWPOLYLINE\" \"POLYLINE\" \"CIRCLE\" \"ELLIPSE\")" "Entity types, by the job each does in the audit: what may be an outline at all, which of those are closed b...")
     ("spachk:*closed-types*" "'(\"CIRCLE\" \"ELLIPSE\")" "Entity types, by the job each does in the audit: what may be an outline at all, which of those are closed b...")
     ("spachk:*loose-types*" "'(\"LINE\" \"ARC\")" "Entity types, by the job each does in the audit: what may be an outline at all, which of those are closed b...")
     ("spachk:*linear-types*" "'(0 1)" "Dimension subtypes whose span can be measured, by the low three bits of DXF group 70: 0 = rotated, 1 = alig...")
     ("spachk:*velcro-word*" "\"Velcro\"" "The word SPA labels a Velcro hinge with. The arrangement audit finds those labels by it, so it has to be th...")
     ("spachk:*report-wide*" "0.25" "The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short s...")
     ("spachk:*report-lead*" "1.66" "The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short s...")
     ("spachk:*report-hmax*" "30.0" "The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short s...")
     ("spachk:*report-hmin*" "200.0" "The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short s...")
     ("spachk:*report-hfall*" "2.5" "drawing units The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a...")
     ("spachk:*report-gap*" "0.05" "The report is scaled to the drawing, exactly as the check family's siblings do it. WIDE: on a wide, short s...")
     ("spachk:*col-gap*" "2.0" "Gap between the main sheet and the DIMENSION AUDIT column beside it, in text heights.")
     ("spachk:*title-scale*" "1.5" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("spachk:*hdg-gap*" "0.4" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("spachk:*head-lines*" "4.5" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("spachk:*hdg-lines*" "1.4" "The title is written this many times the base height, and a section heading gets this much blank line above...")
     ("spachk:*dim-head*" "2.5" "the same allowance for the audit column The title is written this many times the base height, and a section...")
     ("spachk:*row-indent*" "\" \"" "Findings are indented under their heading by this string.")
     ("spachk:*date-sep*" "\"/\"" "The sheet's date is written and read in this order, with this separator: change both together, and remember...")
     ("spachk:*date-order*" "'(month day year)" "The sheet's date is written and read in this order, with this separator: change both together, and remember...")
     ("spachk:*tiny*" "1.0e-6" "drawing units A border edge shorter than this has no measurable size, and a bounding box smaller than this...")
     ("spachk:*foam-slack*" "0.01" "drawing units How close a foam sheet's dimension must come to the table's before it counts as that sheet --..."))
    ("SPACOVCREATE" "lisp/spacovcreate/SPACOVCREATE.lsp"
     ("scv:*offset-dflt*" "6.0" "drawing units How far the cover laps the spa, the number Enter takes. SPA offers the same 6\" as its cover-o...")
     ("scv:*filter*" "'((0 . \"LINE,LWPOLYLINE,POLYLINE,ARC,CIRCLE,ELLIPSE,SPLINE\"))" "What the selection is allowed to hand the command. Anything not in this list is never seen, so a window dra...")
     ("scv:*taper-dflt*" "\"4-2\"" "The grade and taper assumed when nobody gives one. THE POINT OF THESE TWO is that the run still produces a...")
     ("scv:*grade-dflt*" "\"STANDARD\"" "The grade and taper assumed when nobody gives one. THE POINT OF THESE TWO is that the run still produces a...")
     ("scv:*block-name*" "\"SPA COVER DETAILS\"" "The block the grade and taper are read off, and its two tags. The name is only used to warn that a DIFFEREN...")
     ("scv:*grade-tag*" "\"GRADE\"" "The block the grade and taper are read off, and its two tags. The name is only used to warn that a DIFFEREN...")
     ("scv:*taper-tag*" "\"TAPER\"" "The block the grade and taper are read off, and its two tags. The name is only used to warn that a DIFFEREN...")
     ("scv:*chain-tol*" "0.05" "drawing units Two ends this close together are the same end. Raise it for a drawing whose walls were drawn...")
     ("scv:*arcstep*" "5.0" "degrees per tessellated segment How finely an arc is chopped when one has to be measured as points -- the c...")
     ("scv:*miterlim*" "4.0" "How far a corner may be stretched by the offset before the spike is cut back, in multiples of the offset it...")
     ("scv:*fuzz*" "1.0e-6" "Anything smaller than this is zero: a zero-length wall, a bulge that is really a straight run, an area of n...")
     ("scv:*lay-cover*" "\"COVER\"" "the cover outline AND the hinges The layers written on, created on first use with these colours. An existin...")
     ("scv:*col-cover*" "6" "ACI (magenta) The layers written on, created on first use with these colours. An existing layer is used exa...")
     ("scv:*lay-text*" "\"TEXT\"" "the Hinge / Velcro Hinge labels The layers written on, created on first use with these colours. An existing...")
     ("scv:*col-text*" "7" "ACI (white or black, whichever reads) The layers written on, created on first use with these colours. An ex...")
     ("scv:*lay-report*" "\"SPA-NOTES\"" "the report table beside the cover The layers written on, created on first use with these colours. An existi...")
     ("scv:*col-report*" "3" "ACI (green) The layers written on, created on first use with these colours. An existing layer is used exact...")
     ("scv:*col-bad*" "1" "ACI (red) -- a flagged report row The layers written on, created on first use with these colours. An existi...")
     ("scv:*col-advice*" "4" "ACI (cyan) -- a recommendation The layers written on, created on first use with these colours. An existing...")
     ("scv:*hdashname*" "\"DASHED2\"" "The fold hinge's linetype: the stock DASHED2 pattern, defined when the drawing lacks it, scaled so its dash...")
     ("scv:*hdashpat*" "'(0.25 -0.125)" "The fold hinge's linetype: the stock DASHED2 pattern, defined when the drawing lacks it, scaled so its dash...")
     ("scv:*hdashmult*" "20.0" "The fold hinge's linetype: the stock DASHED2 pattern, defined when the drawing lacks it, scaled so its dash...")
     ("scv:*hingetxth*" "5.0" "label height The hinge labels: SPA's numbers, so the two tools' drawings stack.")
     ("scv:*hingetxw*" "60.0" "label MTEXT frame width The hinge labels: SPA's numbers, so the two tools' drawings stack.")
     ("scv:*hingestyle*" "\"Attributes\"" "label style (Standard when absent) The hinge labels: SPA's numbers, so the two tools' drawings stack.")
     ("scv:*hingetxoff*" "0.6" "label heights from the line to the label The hinge labels: SPA's numbers, so the two tools' drawings stack.")
     ("scv:*th-min*" "1.0" "smallest report lettering The report table beside the cover. Its text height is worked out from the size of...")
     ("scv:*th-div*" "40.0" "cover size / this = lettering height The report table beside the cover. Its text height is worked out from...")
     ("scv:*rep-gap*" "12.0" "th multiples: cover -> the table The report table beside the cover. Its text height is worked out from the...")
     ("scv:*rep-row*" "2.2" "th multiples: row pitch The report table beside the cover. Its text height is worked out from the size of t...")
     ("scv:*rep-title*" "1.25" "th multiples: heading text height The report table beside the cover. Its text height is worked out from the...")
     ("scv:*rep-note*" "1.4" "th multiples: a red failure note The report table beside the cover. Its text height is worked out from the...")
     ("scv:*rep-adv*" "1.15" "th multiples: a cyan recommendation The report table beside the cover. Its text height is worked out from t...")
     ("scv:*rep-c1*" "22.0" "th multiples: the LIMIT column The report table beside the cover. Its text height is worked out from the si...")
     ("scv:*rep-c2*" "32.0" "th multiples: the ACTUAL column The report table beside the cover. Its text height is worked out from the s...")
     ("scv:*rep-w*" "44.0" "th multiples: how wide the box comes out The report table beside the cover. Its text height is worked out f...")
     ("scv:*foamtab*" "(list (list \"ECONOMY\" \"3-2\" (list (cons 48.0 96.0)) (list 2)) (list \"STANDARD\" \"3-2\" (list (cons 48.0 144.0) (cons 49.5 102.0)) (list 2)) (list \"STANDARD\" \"4-2\" (list (cons 48.0 96.0) (cons 49.5 102.0)) (list 2 3 4)) (list \"STANDARD\" \"4-3\" (list (cons 48.0 144.0)) (list 2 3 4)) (list \"STANDARD\" \"5-3\" (list (cons 48.0 96.0)) (list 2 3 4 5)) (list \"STANDARD\" \"5-4\" (list (cons 48.0 96.0)) (list 2 3 4 5)) (list \"STANDARD\" \"3-3\" (list (cons 48.0 144.0)) (list 2 3 4 5)) (list \"ULTRA\" \"3-2\" (list (cons 48.0 144.0)) (list 2)) (list \"ULTRA\" \"4-3\" (list (cons 48.0 96.0)) (list 2 3 4)) (list \"ULTRA\" \"3-3\" (list (cons 48.0 144.0)) (list 2 3 4 5)) (list \"THERMOLIGHT\" \"1-3/8\" (list (cons 53.0 nil)) (list 2 3 4 5)))" "-- the shop data the hinges are built on ----------------------------- THE FOAM SHEET. Grade and taper pick...")
     ("scv:*foamdflt*" "(list (cons 48.0 96.0))" "when nothing matches at all")
     ("scv:*foamdpc*" "(list 2 3 4 5)" "and the counts it will accept")
     ("scv:*thermotaper*" "\"1-3/8\"" "the one taper a Thermo-Light comes in")
     ("scv:*hardtab*" "(list ; grade velcro double C hold down (list \"ECONOMY\" '(REQUEST) '(REQUEST) '(REQUEST)) (list \"STANDARD\" '(OVER 120.0) '(OVER 108.0) '(OVER 120.0)) (list \"ULTRA\" '(OVER 108.0) '(NEVER) '(OVER 96.0)) (list \"THERMOLIGHT\" '(ALWAYS) '(NEVER) '(NEVER)))" "HARDWARE called for by the LONGEST hinge, per grade. Each rule is (OVER <inches>) | (ALWAYS) | (NEVER) | (R...")
     ("scv:*hardnames*" "(list \"VELCRO HINGES\" \"DOUBLE C CHANNEL\" \"HOLD DOWN KIT\")" "What the three columns are called in the report, in the order the table above holds them -- rename one and...")
     ("scv:*hinge-min*" "2" "a cover is never fewer pieces than this The placement solver. The fewest pieces that fit the foam width are...")
     ("scv:*hinge-try*" "3" "how many extra piece counts to try The placement solver. The fewest pieces that fit the foam width are used..."))
    ("SQUAREUP" "lisp/squareup/SQUAREUP.lsp"
     ("sq:*arcsegs*" "12" "How many chords an arc is measured as when the SPAN is worked out. Raise it and a big sweeping arc's widest...")
     ("sq:*fuzz*" "0.02" "How close two points have to be to count as the same one -- what decides whether two straight pieces of per...")
     ("sq:*collinear-deg*" "1.0" "How far two touching straight pieces may differ in direction, in DEGREES, and still be read as one wall. Th...")
     ("sq:*square-deg*" "0.01" "Under this many DEGREES out of square, the drawing is already square and nothing is turned. It is not a pre...")
     ("sq:*tie-frac*" "0.02" "When the runner-up wall is within this FRACTION of the longest one's length and sq:*tie-deg* or more away i...")
     ("sq:*tie-deg*" "2.0" "How far apart in DEGREES two walls have to point before a tie between them is worth mentioning. Two long si...")
     ("sq:*about*" "'perimeter" "What the drawing turns ABOUT. 'perimeter is the middle of the perimeter's extents, which keeps the pool whe..."))
    ("STOCKCOVER" "lisp/stockcover/STOCKCOVER.lsp"
     ("*stock-folder*" "\"F:\\\\TechTeam\\\\2022 StockCoverTech\"" "where the stock DWGs live")
     ("*stock-suffixes*" "'(\"_Tech\")" "tried after an exact stem match: \"5M\" -> \"5M.dwg\", then \"5M_Tech.dwg\", then \"5M*.dwg\"")
     ("*stock-explode*" "t" "T = explode the insert so the stock geometry merges into the drawing nil = leave it as a single block refer...")
     ("*stock-anchor-tol*" "0.25" "inches - the two anchor spans may differ this much before STOCKCOVER shouts that the wrong file was named")
     ("*stock-env-folder*" "\"StockCover_Folder\"" "profile keys used to")
     ("*stock-env-last*" "\"StockCover_Last\"" "remember folder + name"))
    ("UPADOVER" "lisp/upadover/UPADOVER.lsp"
     ("upad:*blkname*" "\"Pad36x36\"" "Block inserted at every pad spot, and the edge of that pad in drawing units. The two go together: the size...")
     ("upad:*padsize*" "36.0" "Block inserted at every pad spot, and the edge of that pad in drawing units. The two go together: the size...")
     ("upad:*blkfile*" "\"24inpad.dwg\"" "The dwg the block definitions are imported from when the drawing does not already hold them. Looked up with...")
     ("upad:*layer*" "\"PADS\"" "Layer the pads land on -- PADDLE's, so a drawing padded by both has them in one place -- and the colour it...")
     ("upad:*layercolor*" "7" "Layer the pads land on -- PADDLE's, so a drawing padded by both has them in one place -- and the colour it...")
     ("upad:*evenpct*" "0.70" "How near the two ways round a closed perimeter have to be before the shorter one stops being an answer and...")
     ("upad:*samples*" "48" "How finely the run is walked, in samples per pad width. It is the resolution the cover is worked out at: ev...")
     ("upad:*mincontact*" "6.0" "How much of their shared edge two neighbouring pads have to have in common. Every pad is laid exactly one p...")
     ("upad:*snap*" "12.0" "A click within this of a survey point picks that point rather than the place it landed. 12.0 is what PERPMA...")
     ("upad:*onwall*" "0.25" "How far off the perimeter a pick may sit before the run says where it landed. A quarter inch is drafting no...")
     ("upad:*fuzz*" "1e-6" "Two stations closer than this along the wall are the same place: it is what refuses a run whose two ends ar...")
     ("upad:*point-block*" "\"ab_pt\"" "block name whose INSERTs mark points wherever they sit What counts as a survey point. The classifier is the...")
     ("upad:*point-layer*" "\"POINTS\"" "layer whose POINTs and INSERTs are always points, whatever block points wherever they sit")
     ("upad:*pt-tag*" "\"number\"" "attribute tag on the point block naming the point. A block without it lends its first attribute that reads...")
     ("upad:*unknown*" "\"?\"" "what a point with no readable number is called. It can still be clicked; only a number can be typed naming...")
     ("upad:*pt-prefix*" "\"Pt.\"" "how a point is named in the prompts and the report number is called. It can still be clicked; only a number..."))
    ("VSCONV" "lisp/vsconv/VSCONV.lsp"
     ("*vsconv-map*" "'((\"1 Perimeter\" . \"POOL\") (\"2 Coping\" . \"POOL\") (\"3 Features\" . \"POOL\") (\"3.1 Anchors\" . \"POINTS\") (\"4 Dimensions\" . \"DIMENSION\"))" "source layer -> destination layer. The conversion IS this table: an exporter that names its layers differen...")
     ("*vsconv-colors*" "'((\"POOL\" . 4) ; cyan, as the rest of the tree creates it (\"POINTS\" . 6) ; magenta - the pink the points show in (\"DIMENSION\" . 141))" "The color a destination layer is CREATED with, when the drawing does not carry it yet. A drawing that has t...")
     ("*vsconv-default-color*" "7" "The color for a destination the table above does not name - what a retuned *vsconv-map* row pointing at a n...")
     ("*vsconv-force-bylayer*" "T" "T, and every moved object has its color, linetype and lineweight set to BYLAYER on the way past, so it take...")
     ("*vsconv-dim-style*" "\"STANDARD\"" "The dimension style every converted dimension is put on. If the drawing has no style by this name the dimen...")
     ("*vsconv-dim-xdata*" "\"ACAD\"" "The xdata application whose style overrides come off each dimension with the restyle. AutoCAD keeps a dimen...")
     ("*vsconv-record*" "t" "The record VSRECONV reads back, and the application it lives under. nil converts exactly as before and writ...")
     ("*vsconv-xdata-app*" "\"VSCONV\"" "The record VSRECONV reads back, and the application it lives under. nil converts exactly as before and writ..."))
    ("WCALST" "lisp/wcalst/wcalst.lsp"
     ("wc:*cut-layer*" "\"AIR-B\"" "moves the straight edge, band ends, dart legs, slits and slivers to another layer")
     ("wc:*cut-color*" "1" "recolours that layer where WCALST is the one creating it (1 = red)")
     ("wc:*dim-layer*" "\"DIMENSION\"" "moves the end height dims, the variant labels and the length summary")
     ("wc:*dim-color*" "3" "recolours that one on creation (3 = green)")
     ("wc:*node-fuzz*" "3" "decimals kept when two endpoints are merged into one node: fewer welds points that are genuinely apart, mor...")
     ("wc:*seg-min*" "1.0e-6" "shorter than this is a repeated point rather than a segment, and is dropped")
     ("wc:*trace-turn*" "1.0472" "sharpest turn (radians, 60 deg) the trace of a long side will follow: raise it for a band with genuinely sh...")
     ("wc:*trace-max*" "5000" "hard stop on one walk - the backstop behind the revisited-node test, and only reachable by geometry that is...")
     ("wc:*rung-turn*" "0.7854" "how steeply (radians, 45 deg) a segment must leave the chain to count as a rung: lower it and gentle diagon...")
     ("wc:*min-segs*" "6" "fewest segments a selection may hold before it is sent back to be re-picked")
     ("wc:*min-chain*" "3" "fewest segments a traced side may have before the pick is sent back")
     ("wc:*min-rungs*" "2" "fewest rungs to find between the two sides, below which there is no width to measure")
     ("wc:*maxfeat*" "20" "the darts+inserts cap the prompt offers, and what an out-of-range answer falls back to")
     ("wc:*dart-cap*" "4.0" "widest mouth ONE dart may open: lower it and a big bend splits across more darts side by side, raise it for...")
     ("wc:*dart-space*" "2.0" "bottom line left between two darts cut side by side for one bend, and between any two mouths: less packs th...")
     ("wc:*wmin-f*" "0.04" "smallest correction worth a cut, as a share of the band width - the floor that stops the refining pass cutt...")
     ("wc:*target*" "0.01" "the after-cuts residual the refining variant aims under, as a share of the bottom line, and what OVER TARGE...")
     ("wc:*refine*" "0.6" "how far each refining pass drops the threshold: nearer 1 refines in smaller steps and uses more of the pass...")
     ("wc:*passes*" "10" "how many refining passes before it settles for what it has and says so")
     ("wc:*tile-clear*" "1.0" "how far a cut clears the tile along the straight edge, and how far it stops short of the far edge")
     ("wc:*apex-f*" "0.42" "how far down the local depth a cut stops when no tile height is given: lower it for a deeper hinge along th...")
     ("wc:*apex-min-f*" "0.20" "closest a cut may ever come to the straightened edge, as a share of the local depth - what a band too shall...")
     ("wc:*depth-min-f*" "0.2" "floor under the local depth, as a share of the band width, so a dip in the far edge cannot collapse a cut")
     ("wc:*sliver-top*" "1.0" "width at the top of an insert sliver, and the narrowest one that is drawn")
     ("wc:*sliver-extra*" "1.0" "how much longer a sliver's sides are than the slit they fill - stock to trim on fitting")
     ("wc:*sliver-gap-f*" "0.2" "how far below the band a sliver is drawn, as a share of the width")
     ("wc:*near-f*" "1.75" "how far off the chain (x band width) a point may sit and still be taken as part of this band, or carried al...")
     ("wc:*over-f*" "0.05" "how far above the straight edge (x width) a developed point may land before it is read as an end-clamp arte...")
     ("wc:*past-f*" "0.25" "how far beyond either end of the band (x width) a point may sit and still be kept")
     ("wc:*drop-f*" "1.5" "how far below the lowest point of the selection (x width) the first straight edge lands")
     ("wc:*stack-f*" "5.0" "the gap (x width) between the two drawings: raise it when the summaries of one run into the next")
     ("wc:*label-f*" "0.6" "how far above its straight edge (x width) a variant label sits")
     ("wc:*label-h-f*" "0.4" "text height of that label, as a share of the band width")
     ("wc:*sum-x-f*" "2.0" "how far right of the band end (x width) the length summary is written")
     ("wc:*sum-h-f*" "0.35" "text height of the summary, as a share of the band width")
     ("wc:*sum-step-f*" "0.55" "line spacing within the summary, as a share of the band width")
     ("wc:*dim-off-f*" "1.2" "how far out past each end (x width) the height dimension lines are placed")
     ("wc:*dec-places*" "2" "decimals in every decimal-inch figure the report and the summary print")
     ("wc:*arch-frac*" "8" "smallest fraction in the feet-and-inches twin printed beside it (8 = eighths, 16 = sixteenths)"))
    ("XFTCONV" "lisp/xftconv/xftconv.lsp"
     ("*xft-scale*" "12.0" "Scale factor applied to EVERYTHING highlighted, about the middle of its bounding box, before any point is r...")
     ("*xft-block*" "\"ab_pt\"" "The block that replaces each marker: the template's point block, the one ABHD, POINTRENAMER and the rest of...")
     ("*xft-block-layer*" "\"POINTS\"" "The layer the block is inserted on. Created if missing; thawed, unlocked and switched on if it is there but...")
     ("*xft-block-layer-color*" "6" "The colour *xft-block-layer* is CREATED with when the drawing has not got it. An existing layer is never re...")
     ("*xft-att-tag*" "\"number\"" "The attribute tag inside the block that receives the point number. The template's ab_pt calls it \"number\",...")
     ("*xft-att-style*" "\"Attributes\"" "The text style the attribute is written in. If the drawing has no style by this name the current TEXTSTYLE...")
     ("*xft-att-height*" "4.0" "The attribute's text height, in drawing units AFTER the scale - 4.0 is what the sample drawing shows. It is...")
     ("*xft-att-offset*" "'(0.8697246 -3.5316825)" "Where the attribute sits relative to the point: (dx dy) in drawing units after the scale, as measured off t...")
     ("*xft-marker-layer*" "\"LEICA_POINT\"" "The layer the X markers sit on. A wcmatch pattern - \"*\" and \",\" work - so \"LEICA_POINT,LEICA_PT\" would read...")
     ("*xft-name-layer*" "\"LEICA_POINT_NAME\"" "The layer the point-name text sits on. Also a wcmatch pattern. It is tested BEFORE the marker layer, so a n...")
     ("*xft-name-reach*" "6.0" "How far from a marker its name may sit, counted in that name's own text heights (so the scale leaves it alo...")
     ("*xft-strip-prefix*" "T" "T takes the letter prefix off a Leica name: \"P22\" -> \"22\". Leica calls every point \"P<n>\", so the P is nois...")
     ("*xft-purge-text*" "T" "T erases every TEXT / MTEXT still in the selection once the swap is done: a Leica export writes nothing but...")
     ("*xft-dot-layer*" "\"POOL_POINTS,BREAK_LINES,CROSS_MEASUREMENTS\"" "The layers the circle markers sit on - a wcmatch comma list, so a trace that adds a fourth point layer is o...")
     ("*xft-dot-name-layer*" "\"TEXT\"" "The layer the trace writes its point names on. It is the general text layer, shared with the captions on it...")
     ("*xft-dot-reach*" "1.0" "How far from a circle its name may sit, in text heights. The name sits ON the centre rather than above it,...")
     ("*xft-dot-strip-prefix*" "nil" "nil keeps a trace name whole: \"C1\" stays \"C1\". The letter is the point's family - C for a pool corner, S fo...")
     ("*xft-dot-purge-text*" "nil" "nil leaves the trace's leftover text alone, because it is not all point names: the break lines and the diag...")
     ("*xft-column-tol*" "0.5" "Both exports put the name in the marker's column - Leica stacks it above, the trace lands it on the centre...")
     ("*xft-fuzz*" "1e-4" "How close two marker centres have to be, in drawing units after the scale, to count as the same point. The...")
     ("*xft-record*" "T" "T writes a record into each block's xdata as it goes in, and that record is the only thing that lets XFTREC...")
     ("*xft-xdata-app*" "\"XFTCONV\"" "The xdata application the record lives under. Two drawings' records cannot collide, so this only wants chan...")
     ("*xft-num-prec*" "8" "Decimals a coordinate is written to in the record. 8 puts the round trip within 1e-8 of a drawing unit -- a...")
     ("*xft-rebuild-color*" "7" "The colour a source layer is re-created with when XFTRECONV has to rebuild one that was PURGED after the co...")
     ("*xft-keep-common*" "'(8 62 6 370 410)" "Which DXF groups the record carries whatever the entity type is -- layer, colour, linetype, lineweight, and...")
     ("*xft-keep*" "'((\"LINE\" (10 11)) (\"POINT\" (10 50)) (\"CIRCLE\" (10 40)) (\"TEXT\" (1 7 10 11 40 41 50 51 71 72 73)) (\"MTEXT\" (1 3 7 10 40 41 50 71 72)))" "And the groups it carries per type: what an export writes on the five kinds of object XFTCONV erases. An ex..."))
    ("XYPLOT" "lisp/xyplot/XYPLOT.lsp"
     ("xyp:*gutter*" "0.35" "Gap between the two graphs, as a share of graph 1's width. Wide enough that graph 2's Y dimension chain nev...")
     ("xyp:*same*" "0.0625" "Two points whose X (or Y) differ by less than this share one rung of the dimension chain - a chain rung of...")
     ("xyp:*dirty*" "nil" "set T whenever a value needed cleaning")
     ("xyp:*fixes*" "nil" "running list of cleanup / warning messages"))
   ))
;;; <<< lzp:*knobs*

;;; -------------------- carrying it with you -----------------------------
;;  LAZNAME's names and CALSET/LAZSET's settings already survive an
;;  ordinary LAZPASS rebuild: both live in the registry or the AutoCAD
;;  profile, outside releases/ and LAZPASS.lsp, which is what lets a
;;  regenerated build change under them without losing either -- see
;;  the comment on lzp:*settings* above.  What neither reaches is
;;  somewhere the profile does not: a new machine, a rebuilt profile, a
;;  drafter who wants their own setup on somebody else's seat for a
;;  day.  LAZBACKUP is that -- one plain text file, written and read
;;  back with nothing but this file's own open/write-line/read-line.

;; The settings LAZBACKUP carries -- the three lzp:*settings* keys plus
;; one CalofinInk-<ROLE> per role -- as their profile key names, in the
;; order they will be written.
(defun lzp:backup-keys ( / out r)
  (setq out (mapcar 'car lzp:*settings*))
  (foreach r lzp:*inkroles* (setq out (append out (list (lzp:inkkey r)))))
  out)

;; The header a written file opens with.  It is a plain ; comment line,
;; the same syntax a hand-edited addition anywhere else in the file
;; would use, so an import never refuses a file for missing it or for
;; carrying an older or newer version after the "--" -- it is here so a
;; file opened in a text editor names itself, not to gate reading it.
;; NOT A KNOB: identifies the format to a person reading the file, not
;; a setting -- changing the words here changes nothing LAZBACKUP reads
;; or writes, only what a human sees at the top of the file.
(setq lzp:*backup-header* "; calofin LAZBACKUP")

;; Write everything, under lzp:backup-export's vl-catch-all-apply -- a
;; disk that fills up mid-write must not leave FH unclosed.  Returns
;; (aliases captions settings), the counts the command reports.  Empty
;; overrides are skipped in Alias/Caption, the same convention
;; lzp:kv-write already keeps for the registry copy; a Settings key is
;; written even when empty, because empty there is Auto, a real answer.
(defun lzp:backup-writebody (fh / p k na nc)
  (setq na 0 nc 0)
  (write-line (strcat lzp:*backup-header* " -- " *lazpanel-version*) fh)
  (write-line "[Alias]" fh)
  (foreach p lzp:*aliases*
    (if (/= (cdr p) "")
      (progn (write-line (strcat (car p) "=" (cdr p)) fh) (setq na (1+ na)))))
  (write-line "[Caption]" fh)
  (foreach p lzp:*capsof*
    (if (/= (cdr p) "")
      (progn (write-line (strcat (car p) "=" (cdr p)) fh) (setq nc (1+ nc)))))
  (write-line "[Settings]" fh)
  (foreach k (lzp:backup-keys) (write-line (strcat k "=" (lzp:profread k)) fh))
  ;; ...and LAZTUNE's own defaults, one line per knob the drafter has
  ;; set: the text they typed, exactly as the profile holds it
  (write-line "[Knobs]" fh)
  (foreach k (lzp:knob-index) (write-line (strcat k "=" (lzp:knob-get k)) fh))
  (list na nc (length (lzp:backup-keys)) (length (lzp:knob-index))))

(defun lzp:backup-export (path / fh counts)
  (setq fh (vl-catch-all-apply 'open (list path "w")))
  (cond
    ((or (vl-catch-all-error-p fh) (not fh)) nil)
    (t
     (setq counts (vl-catch-all-apply 'lzp:backup-writebody (list fh)))
     (close fh)
     (if (vl-catch-all-error-p counts) nil counts))))

;; One imported Settings KEY=VALUE, checked the same way its own box
;; would check it -- Theme against the three words every reader takes,
;; a folder taken as typed, an ink role through lzp:aci-p -- and
;; applied straight to the profile.  "" for applied, or the reason it
;; was not, so the caller can report both without a second pass.
(defun lzp:backup-apply-setting (key val / role)
  (cond
    ((= key "CalofinTheme")
     (cond
       ((member (strcase val) '("" "AUTO" "DARK" "LIGHT"))
        (setenv key (strcase val)) "")
       (t (strcat key "=" val " (not Auto, Dark or Light)"))))
    ((member key '("CalofinErrorDir" "StockCover_Folder"))
     (setenv key val) "")
    ((setq role (car (vl-remove-if-not
                       '(lambda (r) (= (lzp:inkkey r) key)) lzp:*inkroles*)))
     (cond
       ((or (= val "") (lzp:aci-p val)) (setenv key val) "")
       (t (strcat key "=" val " (not a colour number)"))))
    (t (strcat key "=" val " (not a setting this build has)"))))

;; One imported line, section already known.  Alias and Caption are
;; checked exactly as LAZNAME's own boxes check them -- lzp:alias-why,
;; lzp:cap-why -- so an import can refuse only what typing the same
;; answer into LAZNAME would also refuse, and a command the roster does
;; not carry is refused before either helper sees it, the same
;; roster-first rule lzp:kv-read already applies to the registry copy.
(defun lzp:backup-apply (section key val / why)
  (cond
    ((= section "Alias")
     (cond
       ((not (member key (lzp:commands))) (strcat key "=" val " (no such command)"))
       ((setq why (lzp:alias-why (strcase val) key)) (strcat key "=" val " (" why ")"))
       (t (setq lzp:*aliases* (lzp:put-pair key (strcase val) lzp:*aliases*)) "")))
    ((= section "Caption")
     (cond
       ((not (member key (lzp:commands))) (strcat key "=" val " (no such command)"))
       ((setq why (lzp:cap-why val)) (strcat key "=" val " (" why ")"))
       (t (setq lzp:*capsof* (lzp:put-pair key val lzp:*capsof*)) "")))
    ((= section "Settings") (lzp:backup-apply-setting key val))
    ((= section "Knobs") (lzp:knob-import key val))
    (t (strcat key "=" val " (not inside a known section)"))))

;; Read every line, section by section, applying as it goes -- under
;; lzp:backup-import's vl-catch-all-apply, the same belt lzp:write-dcl
;; already wears for the write side.  (n-applied (skipped ...)).
(defun lzp:backup-readbody (fh / line section at key val res n skipped)
  (setq section "" n 0)
  (while (setq line (read-line fh))
    (cond
      ;; blank, or a ; comment -- the header line reads as one of these
      ((or (= line "") (= (substr line 1 1) ";")) nil)
      ((and (>= (strlen line) 2) (= (substr line 1 1) "[")
            (= (substr line (strlen line) 1) "]"))
       (setq section (substr line 2 (- (strlen line) 2))))
      ((setq at (vl-string-search "=" line))
       (setq key (substr line 1 at) val (substr line (+ at 2))
             res (lzp:backup-apply section key val))
       (if (= res "") (setq n (1+ n)) (setq skipped (cons res skipped))))
      (t (setq skipped (cons (strcat line " (not KEY=VALUE)") skipped)))))
  (list n (reverse skipped)))

(defun lzp:backup-import (path / fh res)
  (setq fh (vl-catch-all-apply 'open (list path "r")))
  (cond
    ((or (vl-catch-all-error-p fh) (not fh)) nil)
    (t
     (setq res (vl-catch-all-apply 'lzp:backup-readbody (list fh)))
     (close fh)
     (cond
       ((vl-catch-all-error-p res) nil)
       ;; the registry copy AND this session's alias wrapper defuns --
       ;; an imported name works from the next command typed, not only
       ;; after a reload; and the imported defaults the same way
       (t (lzp:names-write) (lzp:knobs-apply) res)))))

;; Export your names and settings to a file, or read them back from
;; one.  Both prompts take Back/Undo, typed, the same way CALSET's own
;; Theme/Errordir/Stockdir question already does -- "Backup [...]" is
;; the first question of the command and does not, matching
;; tools/back_baseline.txt's reason for CALSET's own first prompt.
(defun c:LAZBACKUP ( / *error* pick path counts res n skipped s)
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZBACKUP error: " msg)))
    (if lzd:report (lzd:report "LAZBACKUP" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZBACKUP" *lazpanel-version*))
  (lzp:names-read)
  (initget "Export Import Quit")
  (setq pick (getkword "\nBackup [Export/Import/Quit] <Quit>: "))
  (if lzd:ask (lzd:ask "Backup" pick) pick)
  (cond
    ((= pick "Export")
     (setq path (getstring T "\nFile to write the backup to, Back to leave it: "))
     (if lzd:ask (lzd:ask "File to write" path) path)
     (cond
       ((member (strcase path) '("B" "BACK" "U" "UNDO")) (c:LAZBACKUP))
       ((= path "") (princ "\nNothing written."))
       ((setq counts (lzp:backup-export path))
        (princ (strcat "\nWrote " (itoa (car counts)) " name"
                       (if (= (car counts) 1) "" "s") ", "
                       (itoa (cadr counts)) " caption"
                       (if (= (cadr counts) 1) "" "s") ", "
                       (itoa (caddr counts)) " setting"
                       (if (= (caddr counts) 1) "" "s") " and "
                       (itoa (cadddr counts)) " default"
                       (if (= (cadddr counts) 1) "" "s")
                       " of yours to " path ".")))
       (t (princ (strcat "\nCould not write " path ".")))))
    ((= pick "Import")
     (setq path (getstring T "\nFile to read the backup from, Back to leave it: "))
     (if lzd:ask (lzd:ask "File to read" path) path)
     (cond
       ((member (strcase path) '("B" "BACK" "U" "UNDO")) (c:LAZBACKUP))
       ((= path "") (princ "\nNothing read."))
       ((setq res (lzp:backup-import path))
        (setq n (car res) skipped (cadr res))
        (princ (strcat "\n" (itoa n) " line" (if (= n 1) "" "s")
                       " applied from " path "."))
        (if skipped
          (progn
            (princ (strcat "\n" (itoa (length skipped)) " skipped:"))
            (foreach s skipped (princ (strcat "\n  " s))))))
       (t (princ (strcat "\nCould not read " path ".")))))
    (t (princ "\nNothing changed.")))
  (if lzd:end (lzd:end "LAZBACKUP"))
  (princ))

;;; -------------------- LAZTUNE: a value of your own for any knob --------
;;  Every tool's tunables block is "Alec's choice": the value the tool
;;  ships with, chosen once for the shop.  A drafter who wants another
;;  -- STANDARD INCHES where AutoDim's block says SIDE STANDARD, a
;;  third of the length where POOL's says half -- used to have to ask
;;  for the file to be changed.  LAZTUNE lets them set it themselves,
;;  per machine, in the AutoCAD profile where CalofinTheme and the item
;;  colours already live, with Alec's choice one button away to come
;;  back to.  The knobs it offers are lzp:*knobs* above, transcribed
;;  from every block by tools/gen_knobs.py.
;;
;;  HOW AN OVERRIDE TAKES EFFECT.  A knob is a global the tool reads
;;  when it runs, set by the block when the file loads.  So an override
;;  is applied by setting that global AGAIN, later: lzp:knobs-apply
;;  runs when this file loads (LAZPASS.lsp loads LAZPANEL last, so
;;  every tool's block has already spoken), when the panel opens, right
;;  before a tool is launched from it, and after LAZTUNE's own OK.  A
;;  tool APPLOADed on its own AFTER that resets its knobs to the block
;;  until the next panel open; the grouped build never does.
;;
;;  WHAT IS STORED.  The drafter's value is kept as the TEXT they typed,
;;  one profile key per knob (CalofinKnob-<name>, with : and * spelled
;;  . and ~ so the name is a plain value name) and an index of the
;;  names under CalofinKnobs, so the set can be walked without an
;;  enumerable registry.  Text rather than a value because the profile
;;  holds strings and because (read) is how a Lisp literal round-trips
;;  -- and because LAZBACKUP carries it as text, one line per knob.
;;
;;  WHAT IS REFUSED.  The text is READ, never evaluated: a number, a
;;  string, a symbol, a quoted list, or a (list ...)/(cons ...) of
;;  those is taken as DATA, and anything else -- a call -- is refused.
;;  Then its kind has to match Alec's choice: a string where the block
;;  has a string, a number where it has a number (a whole number is
;;  widened to a real when the block has one, and a colour knob may go
;;  between a number and 'auto).  A knob whose shipped value is a form
;;  that needs its tool loaded to evaluate -- (/ pi 4.0) -- is not
;;  kind-checked when that cannot be told; the profile is still only
;;  ever handed data.

(setq lzp:*tunevals* nil)         ; pending answers: (name . text), "" = Alec's
(setq lzp:*tunetool* nil)         ; which tool the dropdown is on
(setq lzp:*tunesel* nil)          ; the highlighted knob's name
(setq lzp:*tunenames* nil)        ; the names on the list, in row order

(defun lzp:knobkey (sym)
  (strcat "CalofinKnob-" (vl-string-translate ":*" ".~" sym)))

(defun lzp:knob-index ( / v)
  (setq v (lzp:profread "CalofinKnobs"))
  (if (= v "") nil (lzp:split v ";")))

(defun lzp:knob-index-write (syms / s k)
  (setq s "")
  (foreach k syms (setq s (strcat s (if (= s "") "" ";") k)))
  (setenv "CalofinKnobs" s)
  syms)

;; The drafter's text for SYM, or nil when they have none.
(defun lzp:knob-get (sym / v)
  (setq v (lzp:profread (lzp:knobkey sym)))
  (if (= v "") nil v))

(defun lzp:knob-set (sym text)
  (setenv (lzp:knobkey sym) text)
  (if (not (member sym (lzp:knob-index)))
    (lzp:knob-index-write (append (lzp:knob-index) (list sym))))
  text)

(defun lzp:knob-clear (sym)
  (setenv (lzp:knobkey sym) "")
  (lzp:knob-index-write (vl-remove sym (lzp:knob-index)))
  nil)

;; The catalog row for SYM -- (NAME LITERAL MEANING) -- or nil for a
;; name no block has; and the label of the tool it belongs to.
(defun lzp:knob-entry (sym / tl e out)
  (foreach tl lzp:*knobs*
    (foreach e (cddr tl)
      (if (= (car e) sym) (setq out e))))
  out)

(defun lzp:knob-tool (sym / tl e out)
  (foreach tl lzp:*knobs*
    (foreach e (cddr tl)
      (if (= (car e) sym) (setq out (car tl)))))
  out)

;; (read) under a catch, so garbage is a refusal and not an error
;; thrown from inside a dialog callback.
(defun lzp:knob-read (text / v)
  (setq v (vl-catch-all-apply 'read (list text)))
  (if (vl-catch-all-error-p v) 'LZP-BAD v))

;; The DATA a read form stands for, or LZP-BAD.  quote hands back what
;; it quotes; list and cons build from their arguments, each checked
;; the same way; an atom is itself.  Anything else is a call, and a
;; call is exactly what a profile value must never be able to make.
(defun lzp:knob-safe (f / a out)
  (cond
    ((eq f 'LZP-BAD) 'LZP-BAD)
    ((or (null f) (not (eq (type f) 'LIST))) f)
    ((eq (car f) 'quote) (if (= (length f) 2) (cadr f) 'LZP-BAD))
    ((eq (car f) 'list)
     (foreach a (cdr f)
       (setq a (lzp:knob-safe a))
       (if (eq a 'LZP-BAD)
         (setq out 'LZP-BAD)
         (if (not (eq out 'LZP-BAD)) (setq out (cons a out)))))
     (if (eq out 'LZP-BAD) out (reverse out)))
    ((and (eq (car f) 'cons) (= (length f) 3))
     (setq a (lzp:knob-safe (cadr f)) out (lzp:knob-safe (caddr f)))
     (if (or (eq a 'LZP-BAD) (eq out 'LZP-BAD)) 'LZP-BAD (cons a out)))
    (t 'LZP-BAD)))

;; The drafter's TEXT as a value: (T value) when it reads as data, nil
;; when it does not.  A list rather than the value alone, because nil
;; is a value a knob can legitimately hold.
(defun lzp:knob-parse (text / v)
  (cond
    ((= (vl-string-trim " \t" text) "") nil)
    (t (setq v (lzp:knob-safe (lzp:knob-read text)))
       (if (eq v 'LZP-BAD) nil (list t v)))))

;; Alec's choice as a VALUE: the catalog literal read and evaluated --
;; evaluated, because a few blocks derive one knob from another
;; ((* 0.5 *PF-MISS-RADIUS*)) or from pi, and only a loaded tool can
;; answer those.  (T value), or nil when it cannot be told here.  The
;; catalog is this file's own generated table, so evaluating it is not
;; the risk a drafter's text would be, and that text never comes here.
(defun lzp:knob-evaltext (text) (eval (read text)))
(defun lzp:knob-shipped (sym / e v)
  (if (setq e (lzp:knob-entry sym))
    (progn
      (setq v (vl-catch-all-apply 'lzp:knob-evaltext (list (cadr e))))
      (if (vl-catch-all-error-p v) nil (list t v)))))

;; A value's kind, as the state line names it.
(defun lzp:knob-kind (v)
  (cond ((null v) "nil")
        ((eq v t) "T")
        ((eq (type v) 'STR) "a string")
        ((eq (type v) 'INT) "a whole number")
        ((eq (type v) 'REAL) "a number")
        ((eq (type v) 'LIST) "a list")
        ((eq (type v) 'SYM) "a symbol")
        (t "something else")))

;; Why NEW's kind cannot stand in for SHIPPED's, or nil when it can.
;; A knob shipped nil is "off, or a value" -- AutoDim's ad:*layer* is
;; the current layer or a layer NAME, CDCREATE's cdc:*dupetol* off or a
;; DISTANCE -- and nil says nothing about which, so it takes any atom;
;; only a list is refused, since no tool here reads a nil knob as one.
(defun lzp:knob-typewhy (shipped new / ks kn)
  (setq ks (lzp:knob-kind shipped) kn (lzp:knob-kind new))
  (cond
    ((= ks kn) nil)
    ((and (= ks "nil") (/= kn "a list")) nil)
    ((and (= ks "a number") (= kn "a whole number")) nil)
    ((and (member ks '("nil" "T")) (member kn '("nil" "T"))) nil)
    ((and (member ks '("a symbol" "a whole number"))
          (member kn '("a symbol" "a whole number"))) nil)
    (t (strcat "Alec's choice is " ks ", this is " kn))))

;; Why TEXT cannot be SYM's value, or nil when it can.
(defun lzp:knob-why (sym text / p s)
  (cond
    ((not (lzp:knob-entry sym)) "not a knob this build has")
    ((not (setq p (lzp:knob-parse text)))
     "not a value: a number, \"a string\", 'a-symbol or '(a list)")
    ((not (setq s (lzp:knob-shipped sym))) nil)
    (t (lzp:knob-typewhy (cadr s) (cadr p)))))

;; TEXT as the value to put in SYM's global: parsed, and widened to a
;; real where Alec's choice is one.
(defun lzp:knob-value (sym text / v s)
  (setq v (cadr (lzp:knob-parse text)) s (lzp:knob-shipped sym))
  (if (and s (eq (type (cadr s)) 'REAL) (eq (type v) 'INT)) (float v) v))

(defun lzp:knob-apply (sym value)
  (vl-catch-all-apply 'eval (list (list 'setq (read sym) (list 'quote value)))))

;; Alec's choice, put back into this session's global.
(defun lzp:knob-restore (sym / s)
  (if (setq s (lzp:knob-shipped sym)) (lzp:knob-apply sym (cadr s))))

;; Every stored override, applied to this session.  How many took.
(defun lzp:knobs-apply ( / n k v)
  (setq n 0)
  (foreach k (lzp:knob-index)
    (setq v (lzp:knob-get k))
    (if (and v (not (lzp:knob-why k v)))
      (progn (lzp:knob-apply k (lzp:knob-value k v)) (setq n (1+ n)))))
  n)

;; One imported line of LAZBACKUP's [Knobs] section: "" when applied,
;; else the reason, the same shape lzp:backup-apply-setting answers in.
(defun lzp:knob-import (sym text / why)
  (cond
    ((setq why (lzp:knob-why sym text)) (strcat sym "=" text " (" why ")"))
    (t (lzp:knob-set sym text) "")))

;; ---- the dialog

(defun lzp:dcl-tune ( )
  (list "lazpanel_tune : dialog {"
        "  label = \"LazPanel  -  defaults: Alec's choice, or yours\";"
        (strcat "  : popup_list { key = \"tune_tool\"; label = \"Tool\"; "
                "edit_width = 18; }")
        (strcat "  : list_box { key = \"tune_list\"; width = 120; height = "
                (itoa lzp:*tunerows*) "; }")
        "  : text { key = \"tune_meaning\"; width = 120; }"
        "  : row {"
        (strcat "    : edit_box { key = \"tune_val\"; label = \"Value\"; "
                "edit_width = 48; }")
        (strcat "    : button { label = \"Alec's choice\"; key = \"tune_reset\"; "
                "fixed_width = true; }")
        "  }"
        "  : text { key = \"state\"; width = 120; }"
        "  spacer;"
        "  : row {"
        "    alignment = centered;"
        (strcat "    : button { label = \"OK\"; key = \"accept\"; "
                "is_default = true; fixed_width = true; }")
        (strcat "    : button { label = \"Cancel\"; key = \"cancel\"; "
                "is_cancel = true; fixed_width = true; }")
        "  }"
        "}"))

;; What the list shows and the box holds for SYM: the pending answer,
;; else the stored override, else Alec's choice -- and whether it is
;; the drafter's own.  (text yours-p)
(defun lzp:tune-text (sym / p v e)
  (setq e (lzp:knob-entry sym))
  (cond
    ((setq p (assoc sym lzp:*tunevals*))
     (if (= (cdr p) "") (list (cadr e) nil) (list (cdr p) t)))
    ((setq v (lzp:knob-get sym)) (list v t))
    (t (list (cadr e) nil))))

(defun lzp:trunc (s n)
  (if (> (strlen s) n) (strcat (substr s 1 (- n 3)) "...") s))

;; One row.  Not padded into columns: whether the dialog font is
;; fixed-pitch is exactly what LAZASCII exists to ask.
(defun lzp:tune-row (sym / e tx)
  (setq e (lzp:knob-entry sym) tx (lzp:tune-text sym))
  (strcat sym "  =  " (car tx)
          (if (cadr tx) (strcat "   (yours; Alec's choice " (cadr e) ")") "")
          "   -  " (lzp:trunc (caddr e) 60)))

(defun lzp:tune-put (sym text)
  (setq lzp:*tunevals*
        (cons (cons sym text)
              (vl-remove (assoc sym lzp:*tunevals*) lzp:*tunevals*))))

(defun lzp:tune-bad ( / p out)
  (foreach p lzp:*tunevals*
    (if (and (/= (cdr p) "") (lzp:knob-why (car p) (cdr p)))
      (setq out (cons (car p) out))))
  (reverse out))

;; The state line, and OK with it -- greyed while a pending answer
;; will not read, and re-checked at OK (lzp:tune-ok) as every other
;; editor here does.
(defun lzp:tune-state ( / bad tx e)
  (setq bad (lzp:tune-bad))
  (lzp:settile "state"
    (cond
      (bad (strcat (car bad) ": "
                   (lzp:knob-why (car bad) (cdr (assoc (car bad) lzp:*tunevals*)))))
      ((and lzp:*tunesel* (setq e (lzp:knob-entry lzp:*tunesel*)))
       (setq tx (lzp:tune-text lzp:*tunesel*))
       (if (cadr tx)
         (strcat "Yours -- Alec's choice is " (cadr e)
                 ".  OK keeps it in your AutoCAD profile and applies it now")
         (strcat "Alec's choice -- type a value of your own, or leave it;"
                 " OK keeps yours in your AutoCAD profile")))
      (t "")))
  (lzp:setmode "accept" (if bad 1 0))
  (princ))

(defun lzp:tune-show ( / e tx)
  (cond
    ((and lzp:*tunesel* (setq e (lzp:knob-entry lzp:*tunesel*)))
     (setq tx (lzp:tune-text lzp:*tunesel*))
     (lzp:settile "tune_val" (car tx))
     (lzp:settile "tune_meaning" (strcat lzp:*tunesel* ": " (caddr e))))
    (t (lzp:settile "tune_val" "") (lzp:settile "tune_meaning" "")))
  (lzp:tune-state))

;; The list for the tool the dropdown is on, keeping the highlight
;; where it was or putting it on the first row.
(defun lzp:tune-refill ( / tl e i sel)
  (setq tl (nth lzp:*tunetool* lzp:*knobs*) lzp:*tunenames* nil)
  (start_list "tune_list")
  (foreach e (cddr tl)
    (add_list (lzp:tune-row (car e)))
    (setq lzp:*tunenames* (append lzp:*tunenames* (list (car e)))))
  (end_list)
  (setq i 0 sel 0)
  (foreach e lzp:*tunenames*
    (if (= e lzp:*tunesel*) (setq sel i))
    (setq i (1+ i)))
  (setq lzp:*tunesel* (nth sel lzp:*tunenames*))
  (if lzp:*tunenames* (set_tile "tune_list" (itoa sel)))
  (lzp:tune-show))

(defun lzp:tune-tool (v)
  (setq lzp:*tunetool* (atoi v) lzp:*tunesel* nil)
  (lzp:tune-refill)
  (princ))

(defun lzp:tune-pick (v)
  (setq lzp:*tunesel* (nth (atoi v) lzp:*tunenames*))
  (lzp:tune-show)
  (princ))

;; The value box fired.  Empty, or Alec's choice typed back in, means
;; back to Alec's choice; anything else is kept as typed and checked,
;; and OK is greyed while it will not read.
(defun lzp:tune-val (v / sh)
  (if lzp:*tunesel*
    (progn
      (setq sh (cadr (lzp:knob-entry lzp:*tunesel*))
            v  (vl-string-trim " \t" v))
      (lzp:tune-put lzp:*tunesel* (if (= v sh) "" v))
      (lzp:tune-refill)))
  (princ))

(defun lzp:tune-reset ()
  (if lzp:*tunesel*
    (progn (lzp:tune-put lzp:*tunesel* "") (lzp:tune-refill)))
  (princ))

(defun lzp:tune-ok ()
  (if (lzp:tune-bad) (lzp:tune-state) (done_dialog 1))
  (princ))

;; The one place LAZTUNE writes: every pending answer to the profile,
;; then every override applied to this session.  (set cleared).  An
;; answer that will not read is SKIPPED here as well as greyed at the
;; button: DCL fires the box's action before the default button's, so
;; OK with a bad value still in the box lands anyway -- the same
;; reason lzp:set-write leaves an unreadable colour alone.
(defun lzp:tune-write ( / p ns nc)
  (setq ns 0 nc 0)
  (foreach p (reverse lzp:*tunevals*)
    (cond
      ((= (cdr p) "")
       (if (lzp:knob-get (car p))
         (progn (lzp:knob-clear (car p))
                (lzp:knob-restore (car p))
                (setq nc (1+ nc)))))
      ((not (lzp:knob-why (car p) (cdr p)))
       (lzp:knob-set (car p) (cdr p))
       (setq ns (1+ ns)))))
  (lzp:knobs-apply)
  (list ns nc))

;; Open it, wire it, and hand back what OK wrote -- or nil.  The tool
;; dropdown opens on the tool it was last left on in this session.
(defun lzp:tune-edit (dcl / rc tl out)
  (if (null lzp:*tunetool*) (setq lzp:*tunetool* 0))
  (cond
    ((not (new_dialog "lazpanel_tune" dcl)) nil)
    (t
     (start_list "tune_tool")
     (foreach tl lzp:*knobs* (add_list (car tl)))
     (end_list)
     (set_tile "tune_tool" (itoa lzp:*tunetool*))
     (action_tile "tune_tool" "(lzp:tune-tool $value)")
     (action_tile "tune_list" "(lzp:tune-pick $value)")
     (action_tile "tune_val" "(lzp:tune-val $value)")
     (action_tile "tune_reset" "(lzp:tune-reset)")
     (action_tile "accept" "(lzp:tune-ok)")
     (action_tile "cancel" "(done_dialog 0)")
     (lzp:tune-refill)
     (setq rc (start_dialog))
     (if (= rc 1) (setq out (lzp:tune-write)))
     (setq lzp:*tunevals* nil)
     out)))

(defun lzp:tune-report (res)
  (cond
    ((null res) (princ "\nLAZPANEL: defaults unchanged."))
    (t (princ (strcat "\nLAZPANEL: " (itoa (car res)) " knob"
                      (if (= (car res) 1) "" "s")
                      " set to a value of yours, " (itoa (cadr res))
                      " back to Alec's choice -- "
                      (itoa (length (lzp:knob-index)))
                      " of yours in all, applied now and at every panel open."))))
  (princ))

(defun c:LAZTUNE ( / *error* f dcl res)
  ;; an error inside a tile callback used to leak the dialog handle
  ;; and the temp .dcl -- the same fix c:LAZPIN and c:LAZHIDE carry
  (defun *error* (msg)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (if f (vl-file-delete f))
    (setq lzp:*tunevals* nil)
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLAZTUNE error: " msg)))
    (if lzd:report (lzd:report "LAZTUNE" *lazpanel-version* msg))
    (princ))
  (if lzd:begin (lzd:begin "LAZTUNE" *lazpanel-version*))
  (setq lzp:*tunevals* nil)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZTUNE error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZTUNE error: could not load the dialog file.")
     (vl-file-delete f))
    (t
     (setq res (lzp:tune-edit dcl))
     (unload_dialog dcl)
     (vl-file-delete f)
     (lzp:tune-report res)))
  (if lzd:end (lzd:end "LAZTUNE"))
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
;; The drafter's own defaults (LAZTUNE), over every tool's block.  This
;; file loads LAST in LAZPASS.lsp, which is what makes the load-time
;; pass enough there; the panel re-applies on every open and launch for
;; a tool reloaded on its own since.
(vl-catch-all-apply 'lzp:knobs-apply nil)

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
