;;; ======================================================================
;;; LAZPANEL.lsp  --  clickable button panel that launches the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZPANEL       open the panel
;;;            LAZBUTTON      put the screen-button toolbars up
;;;            LAZICON        report where the button picture came from
;;;            LAZPIN         choose the pinned tools
;;;            LAZPANELVER    print the loaded version
;;;
;;; Every headline calofin routine as a button, on tabbed pages of two
;;; kinds.  Four JOB pages -- Pool, Cover, Spa, Rest -- hold what you
;;; reach for while doing that job, in columns that follow the work:
;;; lay the shape out, tie the points, build the steps, dimension and
;;; check.  Four CATEGORY pages -- Layout, Points, Dimensions, Checking,
;;; the same four names the VB.NET palette in ui/calofin_net uses --
;;; hold the whole roster filed by what each tool IS.  A tool that
;;; serves two jobs is on both, so there are more buttons than commands.
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
;;; session has.
;;;
;;; DCL dialogs are modal, so the panel cannot stay open while a tool
;;; runs the way a docked palette can -- but it no longer has to be
;;; reopened by hand: click, the panel closes, the tool runs to its own
;;; end, and the panel COMES BACK on the page and at the screen position
;;; it was at.  Close is the way out, and is the default button.  A
;;; PINNED row on every page carries the handful of tools you actually
;;; run all day, remembered between sessions; Pin... or LAZPIN edits it.
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

(setq *lazpanel-version* "v3.2")

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
;;  the points, build the steps, then dimension and check.  A command
;;  that serves two jobs appears on both; AUTODIM and DIMCHECK are on
;;  all three, because every job ends the same way.  The last four are
;;  the CATEGORIES the panel has always had -- the whole roster filed by
;;  what each tool is rather than when you reach for it -- so a tool you
;;  cannot place in a job is still one tab away.
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
    ("DRONE"            "Drone cleanup")
    ("FITABHD"          "Typed template fit")
    ("FITABHDCOVER"     "Typed template fit, no bottom")
    ("FLOORDIM"         "Floor dims")
    ("HEMISTEP"         "Hemi step")
    ("LAZFORM"          "Pool from a filled-in chart")
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
    ("NORMIESTEP"       "Normie step")
    ("OASIS"            "Freeform pool")
    ("PADDLE"           "Paddle pads")
    ("PERPPTS"          "Perpendicular points")
    ("POOL"             "Pool layout")
    ("POOLCOVER"        "Pool layout, no bottom")
    ("POOLDEMO"         "Worked pool example")
    ("SMARTFILLET"      "Corner radius, previewed")
    ("SPA"              "Spa template")
    ("SPACHECK"         "Spa sheet review")
    ("SPACHECKSCAN"     "Spa sheet scan")
    ("STAIRDIM"         "Stair dims")
    ("STOCKCOVER"       "Stock cover placement")
    ("TYDRN"            "Text + point tidy-up")
    ("TYLERDRONESUITE"  "Drone suite: tidy, pad, dim")
    ("WCALST"           "Unroll curved band")
    ("XFTCONV"          "Leica import cleanup")
    ("XYPLOT"           "X/Y offset plot")
   ))

(defun lzp:caption (name / p)
  (if (setq p (assoc name lzp:*captions*)) (cadr p) ""))

;;  THE PAGES, AS COLUMNS.  Each page is (title (heading cmd ...) ...) --
;;  one entry per COLUMN, laid out side by side across the page.  The
;;  job pages break their tools into the columns the work falls into:
;;  lay the shape out, tie the points, build the steps, dimension and
;;  check.  That is the grouping the drafter already carries; the
;;  columns just stop it being a single list of twenty-four.
;;
;;  A column heading of "" means the page is one plain column -- what
;;  the four category pages are.
;;
;;  WHY A MULTI-COLUMN PAGE SHOWS THE NAME ALONE.  A button reading
;;  "CDCALLOUT  -  Point-to-point cross dims" is about 39 cells wide;
;;  four of those side by side is 147, and DCL will not scroll a dialog
;;  wider than the screen -- the dialog simply fails to open.  So the
;;  columns carry the meaning in their headings and the buttons carry
;;  the command name, which puts the widest page at about 64 cells.
;;  Single-column pages have the room, and keep the caption on the
;;  button: the category pages stay the place to go to find out what a
;;  tool is, and the job pages are the place to go when you know.
(setq lzp:*groups*
  '(("Pool"
     ("Shape"
      "POOL"
      "LAZFORM"
      "LAZTXT"
      "OASIS"
      "ABHD"
      "ADAB"
      "FITABHD"
      "XFTCONV"
      )
     ("Points"
      "ABFIND"
      "ABMOVE"
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
      )
     ("Dims & check"
      "AUTODIM"
      "LINFINCHECK"
      "LINFINSCAN"
      "LITELINFINSCAN"
      "DIMCHECK"
      "DIMSCAN"
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
      "XFTCONV"
      )
     ("Points"
      "ABFIND"
      "ABMOVE"
      "CDCREATE"
      "CDCALLOUT"
      "BPCALLOUT"
      )
     ("Pads, dims & check"
      "PADDLE"
      "AUTODIM"
      "COVERCHECK"
      "COVERSCAN"
      "LITECOVERSCAN"
      "DIMCHECK"
      "DIMSCAN"
      )
    )
     ("Spa"
     (""
      "SPA"
      "LAZSPA"
      "CUSTBLOCK"
      "AUTODIM"
      "SPACHECK"
      "SPACHECKSCAN"
      "LITESPACHECKSCAN"
      "DIMCHECK"
      "DIMSCAN"
      )
    )
     ("Rest"
     (""
      "POOLDEMO"
      "CABHD"
      "LHD"
      "SMARTFILLET"
      "WCALST"
      "ABCDEF"
      "ALTABCDEF"
      "XYPLOT"
      "CONSTELLATION"
      "DRONE"
      "TYDRN"
      "TYLERDRONESUITE"
      "AUTODIMSIDEPOV"
      "STAIRDIM"
      "FLOORDIM"
      "DIMCONTEND"
      "CHECK"
      "DIMARCCHECK"
      "ABCURCHECK"
      "ABCURCHECKSCAN"
      "LINCHECK"
      "LINTXTCHK"
      "CCPRECHECK"
      )
    )
     ("Layout"
     (""
      "LAZFORM"
      "LAZTXT"
      "LAZFORMCOVER"
      "LAZSPA"
      "SPA"
      "POOL"
      "POOLCOVER"
      "POOLDEMO"
      "OASIS"
      "FITABHD"
      "FITABHDCOVER"
      "ABHD"
      "ABHDCOVER"
      "ADAB"
      "CABHD"
      "LHD"
      "PADDLE"
      "AUTOBEAD"
      "LAZSTEP"
      "CORNERSTP"
      "HEMISTEP"
      "NORMIESTEP"
      "SMARTFILLET"
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
      "ABFIND"
      "ABMOVE"
      "PERPPTS"
      "CPERPPTS"
      "XFTCONV"
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
      )
    )))

;; How the tab strip is laid out: one DCL row per entry, in this order.
;; The jobs sit on one line and the categories on the next, which is
;; both what they mean and what keeps the strip narrow -- eight tabs on
;; a single row run about 94 character cells, and DCL will not scroll a
;; dialog that is wider than the screen.  This is presentation only; the
;; pages themselves are still lzp:*groups*.  The test asserts the two
;; tables name exactly the same groups, so neither can drift.
(setq lzp:*rows*
  '(("Job"            "Pool" "Cover" "Spa" "Rest")
    ("Or by category" "Layout" "Points" "Dimensions" "Checking")))

(setq lzp:*pick* nil)             ; the button clicked on the last run
(setq lzp:*tbname* "LazPanel")    ; the panel's screen-button toolbar
(setq lzp:*tbsuite* "TylerDroneSuite")  ; and the suite's own

;; Whether TYLERDRONESUITE gets a screen button of its own.
;;
;;   AUTO  (the default) yes when the drone lisp was loaded ON ITS OWN,
;;         no when it arrived inside LAZPASS
;;   T     always      nil  never
;;
;; The distinction is the point.  A drawer who was handed tydrn.lsp by
;; itself has no panel to reach the suite through, so the button IS the
;; surface.  Inside LAZPASS the panel is already on screen and carries
;; the suite like every other tool, so a second toolbar is one more
;; thing on the strip earning nothing -- the whole build should put up
;; ONE external button, and that button is the panel's.
(setq lzp:*suitebutton* 'AUTO)

;; And whether the PANEL gets one.  Almost always yes -- being on screen
;; is the panel's whole reason for being.  The exception is a build put
;; together around ONE tool, where the panel is along for the ride and
;; its button would be the odd one out: editions/TYLERDRONE.lsp sets
;; this nil so the only thing on the strip is the drone button.
;; LAZPANEL still types the same as ever; it is just not on the strip.
(setq lzp:*panelbutton* T)

;; Draw the button at 32 pixels rather than 16.  The small one is easy
;; to miss on a crowded screen, and both pictures are already written
;; -- AutoCAD simply picks the 16 unless it is told otherwise.
;;
;; Read this before changing it: AutoCAD's large-button setting is not
;; per toolbar.  Asking for it here turns it on for EVERY toolbar in
;; the session, which is the same switch as Options > Display > "Use
;; large buttons for Toolbars".  That is why it is a tunable and why
;; LAZBUTTON says what it did: setq it nil and run LAZBUTTON to put the
;; setting back and return every toolbar to small buttons.
(setq lzp:*bigbutton* T)
(setq lzp:*iconerr* nil)          ; why the last icon write failed
(setq lzp:*pos* nil)              ; where the panel was last standing
(setq lzp:*go* nil)               ; the group a tab click asked for
(setq lzp:*icontype* nil)         ; which byte-array spelling worked
(setq lzp:*iconstep* nil)         ; the COM call the icon write died on
(setq lzp:*msxmlwhy* nil)         ; what each MSXML ProgID said, newest first
(setq lzp:*iconroute* nil)        ; which route actually wrote the file
(setq lzp:*icondir* nil)          ; the folder the icons landed in
(setq lzp:*iconref* nil)          ; "name" on the support path, else "path"
(setq lzp:*page* nil)             ; the page the panel reopens on
(setq lzp:*pins* nil)             ; the pinned tools, in pin order
(setq lzp:*pinkey* "HKEY_CURRENT_USER\\Software\\Calofin\\LazPanel")

;;; -------------------- roster access -----------------------------------

;; One page's commands, flattened out of its columns, in display order:
;; down the first column, then down the second.
(defun lzp:group-commands (name / g col c out)
  (foreach g lzp:*groups*
    (if (= (car g) name)
        (foreach col (cdr g)
          (foreach c (cdr col) (setq out (cons c out))))))
  (reverse out))

;; A page's columns: (heading cmd ...) each.
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
      (foreach c (cdr col)
        (if (not (member c out))
          (setq out (cons c out))))))
  (reverse out))

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
;;  the Pin... button packed last like any other item.  Pin thirty
;;  tools and you get a tall panel, never a broken one.
(setq lzp:*pinbudget* 84)

(defun lzp:pin-label (n) (strcat "    : button { label = \"" n
                                 "\"; key = \"pin_" n "\"; }"))

;; (name width) for every pinned tool, then the editor button last.
(defun lzp:pin-items ( / out n)
  (foreach n lzp:*pins* (setq out (cons n out)))
  (reverse (cons "*edit*" out)))

(defun lzp:pinrows ( / out row w n cw items)
  (setq items (lzp:pin-items) row nil w 0)
  (foreach n items
    (setq cw (+ (strlen (if (= n "*edit*") "Pin..." n)) 6))
    (if (and row (> (+ w cw) lzp:*pinbudget*))
      (setq out (cons (reverse row) out) row nil w 0))
    (setq row (cons n row) w (+ w cw)))
  (if row (setq out (cons (reverse row) out)))
  (reverse out))

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
    (if (and first (not lzp:*pins*))
      (setq out (cons "    : text { label = \"nothing pinned yet\"; }" out)))
    (setq out (cons "  }" out))
    (setq first nil))
  (reverse out))

;; One page per group.  The whole roster is still one list -- the pages
;; are lzp:*groups* itself, so re-ordering or re-grouping the tools is
;; an edit to that table and nothing else.
(defun lzp:dcl-one (g / out c col)
  ;; consed newest-first and reversed at the end, so this seed list
  ;; reads BACKWARDS: the dialog line last here comes out first
  (setq out (list (strcat "  : text { key = \"status\"; width = 60; "
                          "alignment = centered; }")
                  (strcat "  label = \"LazPanel " *lazpanel-version*
                          "  -  " (car g) "\";")
                  (strcat (lzp:dlgname (car g)) " : dialog {")))
  (setq out (append (reverse (lzp:tabstrip)) out))
  (setq out (append (reverse (lzp:pinrow)) out))
  (cond
    ;; ONE COLUMN: the page has the width to spare, so every button
    ;; carries its caption -- this is what the category pages are for.
    ((= (length (cdr g)) 1)
     (setq out (cons "  : boxed_column {" out))
     (setq out (cons (strcat "    label = \"" (car g) "\";") out))
     (foreach c (cdr (car (cdr g)))
       (setq out (cons (strcat "    : button { label = \"" c "  -  "
                               (lzp:caption c) "\"; key = \"" c "\"; }")
                       out)))
     (setq out (cons "  }" out)))
    ;; SEVERAL COLUMNS, side by side: the heading says what the column
    ;; is for and the buttons carry the command name alone.  Four
    ;; captioned buttons abreast would be about 147 cells wide and the
    ;; dialog would not open at all.
    (t
     (setq out (cons "  : boxed_row {" out))
     (setq out (cons (strcat "    label = \"" (car g) "\";") out))
     (foreach col (cdr g)
       (setq out (cons "    : boxed_column {" out))
       (setq out (cons (strcat "      label = \"" (car col) "\";") out))
       (foreach c (cdr col)
         (setq out (cons (strcat "      : button { label = \"" c
                                 "\"; key = \"" c "\"; }")
                         out)))
       (setq out (cons "    }" out)))
     (setq out (cons "  }" out))))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : button { label = \"Close\"; key = \"cancel\"; "
                          "is_default = true; is_cancel = true; "
                          "fixed_width = true; alignment = centered; }")
                  out))
  (reverse (cons "}" out)))

;; The pin editor: every tool on the panel as a toggle, in three
;; columns so fifty-six of them fit on a screen rather than a scroll
;; DCL would not give.
(defun lzp:dcl-pins ( / out cmds n per i j c)
  (setq cmds (lzp:commands)
        n    (length cmds)
        per  (1+ (/ (1- n) 3))
        i    0)
  (setq out (list "lazpanel_pins : dialog {"
                  "  label = \"LazPanel  -  pinned tools\";"
                  (strcat "  : text { label = \"Ticked tools sit in the "
                          "Pinned row on every page.\"; }")
                  "  : row {"))
  (while (< i n)
    (setq out (append out (list "    : column {")) j 0)
    (while (and (< j per) (< i n))
      (setq c (nth i cmds))
      (setq out (append out
        (list (strcat "      : toggle { label = \"" c
                      "\"; key = \"tg_" c "\"; }"))))
      (setq i (1+ i) j (1+ j)))
    (setq out (append out (list "    }"))))
  (append out
    (list "  }" "  spacer;"
          (strcat "  : row { alignment = centered; "
                  ": button { label = \"OK\"; key = \"accept\"; "
                  "is_default = true; fixed_width = true; } "
                  ": button { label = \"Cancel\"; key = \"cancel\"; "
                  "is_cancel = true; fixed_width = true; } }")
          "}")))

;; Every page, then the pin editor, in one generated file.
(defun lzp:dcl-lines ( / out g)
  (foreach g lzp:*groups*
    (setq out (append out (lzp:dcl-one g) (list ""))))
  (append out (lzp:dcl-pins) (list "")))

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
(defun lzp:pins-read ( / s)
  (setq s (vl-catch-all-apply 'vl-registry-read (list lzp:*pinkey* "Pins")))
  (setq lzp:*pins*
    (if (and (not (vl-catch-all-error-p s)) (= (type s) 'STR) (/= s ""))
      (vl-remove-if-not '(lambda (n) (member n (lzp:commands)))
                        (lzp:split s ";"))))
  lzp:*pins*)

(defun lzp:pins-write ( / s n)
  (setq s "")
  (foreach n lzp:*pins*
    (setq s (strcat s (if (= s "") "" ";") n)))
  (vl-catch-all-apply 'vl-registry-write (list lzp:*pinkey* "Pins" s))
  lzp:*pins*)

;; Pin order is click order: a newly ticked tool goes on the END rather
;; than jumping into the middle of a row the hand has already learned.
(defun lzp:pin-toggle (name val)
  (if (= val "1")
    (if (not (member name lzp:*pins*))
      (setq lzp:*pins* (append lzp:*pins* (list name))))
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

(defun lzp:launch (name / fn)
  (setq fn (read (strcat "C:" name)))
  (cond
    ((eval fn)
     (princ (strcat "\nLAZPANEL: running " name
                    " -- LAZPANEL reopens the panel."))
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

;; The second mark: a triangle, point north, for TYLERDRONESUITE's own
;; button.  A different SHAPE rather than a different colour, because
;; the two sit side by side on the same strip and both are orange --
;; lzp:bmp-bytes paints every "X" the one orange, which is what makes
;; the pair read as one toolkit rather than two.
(setq lzp:*tri16*
  '(
    "................"
    ".......XX......."
    ".......XX......."
    "......XXXX......"
    "......XXXX......"
    ".....XXXXXX....."
    ".....XXXXXX....."
    "....XXXXXXXX...."
    "....XXXXXXXX...."
    "...XXXXXXXXXX..."
    "...XXXXXXXXXX..."
    "..XXXXXXXXXXXX.."
    "..XXXXXXXXXXXX.."
    ".XXXXXXXXXXXXXX."
    "XXXXXXXXXXXXXXXX"
    "................"
))

(setq lzp:*tri32*
  '(
    "................................"
    "................................"
    "...............XX..............."
    "...............XX..............."
    "..............XXXX.............."
    "..............XXXX.............."
    ".............XXXXXX............."
    ".............XXXXXX............."
    "............XXXXXXXX............"
    "............XXXXXXXX............"
    "...........XXXXXXXXXX..........."
    "...........XXXXXXXXXX..........."
    "..........XXXXXXXXXXXX.........."
    "..........XXXXXXXXXXXX.........."
    ".........XXXXXXXXXXXXXX........."
    ".........XXXXXXXXXXXXXX........."
    "........XXXXXXXXXXXXXXXX........"
    ".......XXXXXXXXXXXXXXXXXX......."
    ".......XXXXXXXXXXXXXXXXXX......."
    "......XXXXXXXXXXXXXXXXXXXX......"
    "......XXXXXXXXXXXXXXXXXXXX......"
    ".....XXXXXXXXXXXXXXXXXXXXXX....."
    ".....XXXXXXXXXXXXXXXXXXXXXX....."
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "....XXXXXXXXXXXXXXXXXXXXXXXX...."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "...XXXXXXXXXXXXXXXXXXXXXXXXXX..."
    "..XXXXXXXXXXXXXXXXXXXXXXXXXXXX.."
    "..XXXXXXXXXXXXXXXXXXXXXXXXXXXX.."
    ".XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX."
    "................................"
    "................................"
))

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
;; so 0 165 255 -- and the rest panel grey.  Both sizes give a row
;; width that is a multiple of 4 (48 and 96), so there is no row
;; padding to get wrong.
(defun lzp:bmp-bytes (size grid / fg bg rowbytes out row s i)
  (setq fg '(0 165 255)
        bg '(54 54 54)
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
(defun lzp:icon-file (dir stem name / d)
  (setq d dir)
  ;; a folder is not guaranteed to end in a separator -- glue the name
  ;; straight on and a folder called Temp becomes a file called
  ;; Templazpanel-16.bmp, which fails silently later
  (if (not (member (substr d (strlen d) 1) '("\\" "/")))
      (setq d (strcat d "\\")))
  (strcat d stem "-" name ".bmp"))

(defun lzp:icon-path (stem name / d)
  (setq d (getvar "TEMPPREFIX"))
  (if (and d (= (type d) 'STR) (/= d ""))
      (lzp:icon-file d stem name)
      (vl-filename-mktemp (strcat stem "-" name) nil ".bmp")))

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
(defun lzp:try-icons (dir stem art16 art32 / s l)
  (if (and dir (= (type dir) 'STR) (/= dir ""))
      (progn
        (setq s (lzp:icon-file dir stem "16")
              l (lzp:icon-file dir stem "32"))
        (if (and (lzp:bmp-write s 16 art16)
                 (lzp:bmp-write l 32 art32))
            (progn (setq lzp:*icondir* dir)
                   (list s l))))))

;; What to hand SetBitmaps: bare names when the files sit on the support
;; path, full temp paths as the fallback.
(defun lzp:write-bmps (stem art16 art32 / d)
  (setq lzp:*icondir* nil
        lzp:*iconref* nil)
  (cond
    ((and (setq d (lzp:support-dir)) (lzp:try-icons d stem art16 art32))
     (setq lzp:*iconref* "name")
     (list (strcat stem "-16.bmp") (strcat stem "-32.bmp")))
    ((lzp:try-icons (getvar "TEMPPREFIX") stem art16 art32)
     (setq lzp:*iconref* "path")
     (list (lzp:icon-file (getvar "TEMPPREFIX") stem "16")
           (lzp:icon-file (getvar "TEMPPREFIX") stem "32")))))

;; The LazPanel toolbar, wherever it lives -- one this file made in an
;; earlier session may sit in any loaded menu group.
;;; -------------------- the two screen buttons --------------------------
;;  Each is one toolbar with one button, and a spec says everything that
;;  differs between them:
;;
;;      (toolbar-name  icon-stem  tooltip  command  art16  art32)
;;
;;  There are two because they are two different tools.  The panel is
;;  the whole roster; the suite is one job someone runs all day, and it
;;  earns a button of its own rather than two clicks through a dialog.
;;  A different SHAPE tells them apart -- hexagon and triangle -- since
;;  both are painted the same orange.
(defun lzp:tb-name (spec) (nth 0 spec))
(defun lzp:tb-stem (spec) (nth 1 spec))
(defun lzp:tb-tip  (spec) (nth 2 spec))
(defun lzp:tb-cmd  (spec) (nth 3 spec))
(defun lzp:tb-16   (spec) (nth 4 spec))
(defun lzp:tb-32   (spec) (nth 5 spec))

(defun lzp:panel-spec ()
  (list lzp:*tbname* "lazpanel"
        "Open the LazPanel tool panel" "LAZPANEL"
        lzp:*icon16* lzp:*icon32*))

(defun lzp:suite-spec ()
  (list lzp:*tbsuite* "tylerdronesuite"
        "TYLERDRONESUITE - TYDRN, then PADDLE, then AUTODIM"
        "TYLERDRONESUITE"
        lzp:*tri16* lzp:*tri32*))

;; Is this session the LAZPASS build?  Both LAZPASS.lsp and
;; CALOFIN-LOADER.lsp raise cal:*build-loading* before they load a
;; thing, and neither lowers it -- so it answers for the session, which
;; is what is being asked.  Standalone the symbol is simply unbound,
;; and an unbound symbol is nil.
(defun lzp:in-build-p () (if cal:*build-loading* T nil))

;; Does the suite want a button of its own here?
(defun lzp:suite-wanted-p ()
  (and (lzp:has "TYLERDRONESUITE")
       (cond ((eq lzp:*suitebutton* 'AUTO) (not (lzp:in-build-p)))
             (lzp:*suitebutton* T))))

;; The buttons to put up.  Two things have to be true for the suite's:
;; its command has to be loaded -- LAZPANEL.lsp APPLOADed on its own has
;; no tydrn.lsp beside it, and a button that answers a click with
;; "Unknown command" is worse than no button -- and this has to not be
;; the LAZPASS build, which puts up one external button and that one is
;; the panel's.
(defun lzp:tb-specs ( / out)
  (setq out nil)
  (if lzp:*panelbutton* (setq out (list (lzp:panel-spec))))
  (if (lzp:suite-wanted-p)
    (setq out (append out (list (lzp:suite-spec)))))
  out)

(defun lzp:toolbar-find (name / mgs n i tbs m j tb found)
  (setq mgs (vla-get-menugroups (vlax-get-acad-object)))
  (setq n (vla-get-count mgs)
        i 0)
  (while (and (< i n) (not found))
    (setq tbs (vla-get-toolbars (vla-item mgs i)))
    (setq m (vla-get-count tbs)
          j 0)
    (while (and (< j m) (not found))
      (setq tb (vla-item tbs j))
      (if (= (strcase (vla-get-name tb)) (strcase name))
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
(defun lzp:toolbar-make (spec / tbs tb btn)
  (setq tbs (vla-get-toolbars
              (vla-item (vla-get-menugroups (vlax-get-acad-object)) 0)))
  (setq tb (vla-add tbs (lzp:tb-name spec)))
  (setq btn (vl-catch-all-apply
              'vla-addtoolbarbutton
              (list tb 0 (lzp:tb-name spec)
                    (lzp:tb-tip spec)
                    (strcat (chr 3) (chr 3) "_" (lzp:tb-cmd spec) " "))))
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
(defun lzp:button-init (spec / tb btn pair paths made)
  (cond
    ((setq tb (lzp:toolbar-find (lzp:tb-name spec)))
     (setq btn (vl-catch-all-apply 'vla-item (list tb 0)))
     (if (vl-catch-all-error-p btn) (setq btn nil)))
    ((setq pair (lzp:toolbar-make spec))
     (setq tb (car pair)
           btn (cadr pair)
           made t)))
  (if tb
    (progn
      (if (and btn (setq paths (lzp:write-bmps (lzp:tb-stem spec)
                                               (lzp:tb-16 spec)
                                               (lzp:tb-32 spec))))
        (vl-catch-all-apply 'vla-setbitmaps
                            (list btn (car paths) (cadr paths)))
        ;; one line, not a stack trace: the panel still works without a
        ;; picture, but a blank button should not be a mystery
        (princ "\n[lazpanel] button picture not applied - LAZICON says why."))
      ;; Big buttons before visible: the toolbar resizes to fit its
      ;; button, and doing it the other way round makes it visibly jump.
      ;; nil does not merely SKIP this -- it puts the setting back, or
      ;; "setq it nil and run LAZBUTTON" would be advice that does
      ;; nothing once a session has already been switched over.
      (vl-catch-all-apply 'vla-put-largebuttons
                          (list tb (if lzp:*bigbutton*
                                     :vlax-true :vlax-false)))
      (vl-catch-all-apply 'vla-put-visible (list tb :vlax-true))
      ;; a new one is floated where it can be seen; the second lands
      ;; below the first rather than on top of it
      (if made
        (vl-catch-all-apply
          'vla-float
          (list tb (+ 200 (* 40 (lzp:tb-index spec))) 300 1)))))
  tb)

;; Where SPEC sits in the roster, so two new toolbars do not float onto
;; the same pixel.
(defun lzp:tb-index (spec / i n found)
  (setq i 0 found 0)
  (foreach n (lzp:tb-specs)
    (if (= (lzp:tb-name n) (lzp:tb-name spec)) (setq found i))
    (setq i (1+ i)))
  found)

;; Put every button this session should have on screen.  Returns the
;; toolbars it managed, newest last.
(defun lzp:buttons-init ( / out spec tb)
  (foreach spec (lzp:tb-specs)
    (if (setq tb (lzp:button-init spec))
      (setq out (append out (list tb)))))
  out)

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
    (princ))
  ;; NOT reset here: the panel reopens after every tool it launches, and
  ;; coming back to page one in the middle of the screen each time would
  ;; undo the whole point of reopening.  lzp:*page* and lzp:*pos* are
  ;; where the user last had it.
  (setq lzp:*pick* nil)
  (if (not (and lzp:*page* (assoc lzp:*page* lzp:*groups*)))
    (setq lzp:*page* (car (car lzp:*groups*))))
  (setq g lzp:*page*)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPANEL error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPANEL error: could not load the dialog file."))
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
                    (strcat (itoa (length have)) " of "
                            (itoa (length (lzp:commands)))
                            " tools loaded - greyed are not in this session"))
          (foreach n (lzp:group-commands g)
            (action_tile n
              "(setq lzp:*pick* $key lzp:*pos* (done_dialog 1))")
            (if (not (member n have))
              (mode_tile n 1)))
          ;; the pinned row: same launch, its own keys, greyed the same
          ;; way -- $key would read "pin_POOL", so the name is baked in
          (foreach n lzp:*pins*
            (action_tile (strcat "pin_" n)
              (strcat "(setq lzp:*pick* \"" n
                      "\" lzp:*pos* (done_dialog 1))"))
            (if (not (member n have))
              (mode_tile (strcat "pin_" n) 1)))
          (action_tile "pin_edit" "(setq lzp:*pos* (done_dialog 5))")
          (foreach n lzp:*groups*
            (action_tile (strcat "tab_" (car n))
              (strcat "(setq lzp:*go* \"" (car n)
                      "\" lzp:*pos* (done_dialog 4))")))
          (action_tile "cancel" "(setq lzp:*pos* (done_dialog 0))")
          (setq rc (start_dialog))
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

;; Open a page where the user last had the panel.  done_dialog reports
;; the position it closed at and new_dialog takes one back, but only in
;; its four-argument form -- and a build answering done_dialog with
;; something other than a point would poison every reopen, so the shape
;; is checked before it is trusted.
(defun lzp:newdlg (name dcl)
  (if (and lzp:*pos* (listp lzp:*pos*) (= (length lzp:*pos*) 2)
           (numberp (car lzp:*pos*)) (numberp (cadr lzp:*pos*)))
      (new_dialog name dcl "" lzp:*pos*)
      (new_dialog name dcl)))

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
  (while (setq pick (lzp:show))
    (if (/= pick "*pins*")
      (lzp:launch pick)))
  (princ))

;; Open the pin editor on its own, without going through the panel.
(defun c:LAZPIN ( / f dcl)
  (lzp:pins-read)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPIN error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPIN error: could not load the dialog file."))
    (t
     (lzp:pin-edit dcl)
     (unload_dialog dcl)
     (vl-file-delete f)
     (princ (strcat "\nLAZPANEL: "
                    (itoa (length lzp:*pins*)) " tools pinned."))))
  (princ))

(defun c:LAZBUTTON ( / tbs spec tb any)
  (setq tbs (vl-catch-all-apply 'lzp:buttons-init nil))
  (cond
    ((vl-catch-all-error-p tbs)
     (princ (strcat "\nLAZBUTTON error: " (vl-catch-all-error-message tbs))))
    (tbs
     (foreach tb tbs
       (vl-catch-all-apply 'vla-put-visible (list tb :vlax-true)))
     (setq any nil)
     (foreach spec (lzp:tb-specs)
       (if (lzp:toolbar-find (lzp:tb-name spec))
         (progn
           (setq any T)
           (princ (strcat "\n" (lzp:tb-name spec) " button is on screen -"
                          " drag it anywhere, dock it,"
                          "\n  click it to run " (lzp:tb-cmd spec) ".")))))
     ;; said out loud because it is not a change to THESE toolbars: the
     ;; operator's other toolbars grew too, and they should hear it
     ;; from the command that did it rather than wonder
     (if (and any lzp:*bigbutton*)
       (princ (strcat "\n  Drawn at 32 pixels.  AutoCAD sizes every"
                      " toolbar together, so the rest grew"
                      "\n  with it; (setq lzp:*bigbutton* nil) before"
                      " loading leaves them alone.")))
     (cond
       ((lzp:suite-wanted-p))
       ((not (lzp:has "TYLERDRONESUITE"))
        (princ (strcat "\n  TYLERDRONESUITE is not loaded, so it has no"
                       " button of its own -"
                       "\n  APPLOAD tydrn.lsp (or LAZPASS.lsp) and run"
                       " LAZBUTTON again.")))
       (t
        (princ (strcat "\n  TYLERDRONESUITE is on the panel rather than"
                       " on a button of its own:"
                       "\n  this is the whole build, and the build puts"
                       " up one external button."
                       "\n  (setq lzp:*suitebutton* T) before loading"
                       " gives it one anyway.")))))
    (t
     (princ "\nLAZBUTTON: the menu API is unavailable - type LAZPANEL instead.")))
  (princ))

(defun c:LAZICON ( / spec)
  ;; The icon path is best effort and fails silently on purpose: a
  ;; missing picture must never stop the panel working.  Silence is the
  ;; right default and a poor answer to "why is my button blank", so
  ;; this walks the same steps out loud -- once per button, because
  ;; they are written separately and either can fail on its own.
  (princ "\nLAZICON: where the button pictures come from.")
  (princ (strcat "\n  support    : "
                 (cond ((lzp:support-dir))
                       (t "(could not read the support path)"))))
  (princ (strcat "\n  TEMPPREFIX : "
                 (if (= (type (getvar "TEMPPREFIX")) 'STR)
                     (getvar "TEMPPREFIX") "(not a string)")))
  (foreach spec (lzp:tb-specs) (lzp:icon-report spec))
  (if (not (lzp:suite-wanted-p))
    (princ (strcat "\n\n  TYLERDRONESUITE has no button here, so no"
                   " picture is drawn for it."
                   "\n  LAZBUTTON says which of the two reasons it is.")))
  (princ))

;; One button's picture, start to finish.
(defun lzp:icon-report (spec / paths tb btn r w)
  (princ (strcat "\n\n  [" (lzp:tb-name spec) "] -> " (lzp:tb-cmd spec)))
  (setq paths (lzp:write-bmps (lzp:tb-stem spec)
                              (lzp:tb-16 spec) (lzp:tb-32 spec)))
  (cond
    (paths
     (princ (strcat "\n  written to : "
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
       ((not (setq tb (vl-catch-all-apply 'lzp:toolbar-find
                                          (list (lzp:tb-name spec)))))
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
  (princ))

(defun c:LAZPANELVER ()
  (princ (strcat "\nLAZPANEL " *lazpanel-version* " (LAZPANEL.lsp) - "
                 (itoa (length (lzp:commands))) " tools on the panel across "
                 (itoa (length lzp:*groups*)) " pages, "
                 (itoa (length lzp:*pins*)) " pinned."))
  (princ))

;; Put the button up as the file loads, quietly: in a session where
;; the COM menu API is missing the panel still loads and LAZPANEL
;; still runs -- the button is a convenience, never a gate.
(vl-catch-all-apply 'lzp:buttons-init nil)
(vl-catch-all-apply 'lzp:pins-read nil)

(princ (strcat "\nLAZPANEL " *lazpanel-version*
               " loaded.  LAZPANEL opens the panel;"
               " LAZBUTTON puts its button on screen;"
               " LAZPIN edits the pinned row."))
(princ)
