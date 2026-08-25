;;; ======================================================================
;;; LAZPANEL.lsp  --  clickable button panel that launches the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZPANEL       open the panel
;;;            LAZBUTTON      put the LazPanel button toolbar on screen
;;;            LAZICON        report where the button picture came from
;;;            LAZPANELVER    print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Every headline calofin routine as a button, grouped the way the
;;; drafter thinks about them (the same four group names as the VB.NET
;;; palette in ui/calofin_net: Layout, Points, Dimensions, Checking).
;;; Clicking a button closes the panel and runs the command exactly as
;;; if its name had been typed -- the panel adds nothing in front of a
;;; tool and nothing behind it.
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
;;; runs the way a docked palette can: click, the panel closes, the tool
;;; runs, LAZPANEL reopens it.  The *SCAN companions are on the panel;
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

(setq *lazpanel-version* "v1.9")

;;; -------------------- the roster --------------------------------------
;;  One entry per button: (label (command caption) ...) per group.  The
;;  rules for what belongs here:
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
;;  "Rest" is not a hand-kept list: it is every command the Pool, Cover
;;  and Spa pages do not name, and the test recomputes that complement
;;  from the tree, so a tool added to the panel lands there by default
;;  instead of falling off the job pages unnoticed.

(setq lzp:*groups*
  '(("Pool"
     ("POOL"           "Pool layout")
     ("LAZFORM"        "Pool from a filled-in chart")
     ("OASIS"          "Freeform pool")
     ("ABHD"           "Survey perimeter + bottom")
     ("ADAB"           "Organic shape points")
     ("FITABHD"        "Typed template fit")
     ("XFTCONV"        "Leica import cleanup")
     ("ABFIND"         "A/B stake ties")
     ("ABMOVE"         "Move mis-taped point")
     ("CDCREATE"       "Lines to cross dims")
     ("CDCALLOUT"      "Point-to-point cross dims")
     ("BPCALLOUT"      "Bad point callout")
     ("CORNERSTP"      "Corner step")
     ("HEMISTEP"       "Hemi step")
     ("NORMIESTEP"     "Normie step")
     ("AUTOBEAD"       "Bead offsets")
     ("PERPPTS"        "Perpendicular points")
     ("CPERPPTS"       "Curved perp points")
     ("AUTODIM"        "Auto dimension")
     ("LINFINCHECK"    "Liner finish review")
     ("LINFINSCAN"     "Liner finish scan")
     ("LITELINFINSCAN" "Liner scan, no dims")
     ("DIMCHECK"       "Dimension review")
     ("DIMSCAN"        "Dimension scan"))
    ("Cover"
     ("POOLCOVER"      "Pool layout, no bottom")
     ("LAZFORMCOVER"   "Chart to pool, no bottom")
     ("OASIS"          "Freeform pool")
     ("ABHDCOVER"      "Survey perimeter, no bottom")
     ("FITABHDCOVER"   "Typed template fit, no bottom")
     ("STOCKCOVER"     "Stock cover placement")
     ("XFTCONV"        "Leica import cleanup")
     ("ABFIND"         "A/B stake ties")
     ("ABMOVE"         "Move mis-taped point")
     ("CDCREATE"       "Lines to cross dims")
     ("CDCALLOUT"      "Point-to-point cross dims")
     ("BPCALLOUT"      "Bad point callout")
     ("PADDLE"         "Paddle pads")
     ("AUTODIM"        "Auto dimension")
     ("COVERCHECK"     "Cover review")
     ("COVERSCAN"      "Cover scan")
     ("LITECOVERSCAN"  "Cover scan, no dims")
     ("DIMCHECK"       "Dimension review")
     ("DIMSCAN"        "Dimension scan"))
    ("Spa"
     ("SPA"            "Spa template")
     ("AUTODIM"        "Auto dimension")
     ("SPACHECK"       "Spa sheet review")
     ("SPACHECKSCAN"   "Spa sheet scan")
     ("LITESPACHECKSCAN" "Spa scan, no dims")
     ("DIMCHECK"       "Dimension review")
     ("DIMSCAN"        "Dimension scan"))
    ("Rest"
     ("POOLDEMO"       "Worked pool example")
     ("CABHD"          "Perimeter-only fit")
     ("LHD"            "Laser outline fit")
     ("SMARTFILLET"    "Corner radius, previewed")
     ("WCALST"         "Unroll curved band")
     ("ABCDEF"         "Rectangle plot")
     ("ALTABCDEF"      "Clockwise rectangle plot")
     ("XYPLOT"         "X/Y offset plot")
     ("DRONE"          "Drone cleanup")
     ("TYDRN"          "Text + point tidy-up")
     ("AUTODIMSIDEPOV" "Side-view dims")
     ("STAIRDIM"       "Stair dims")
     ("FLOORDIM"       "Floor dims")
     ("DIMCONTEND"     "Continue dim chains")
     ("CHECK"          "Drawing check")
     ("DIMARCCHECK"    "Arc endpoint check")
     ("LINCHECK"       "Line checklist")
     ("LINTXTCHK"      "Liner checklist text")
     ("CCPRECHECK"     "Tech flow chart"))
    ("Layout"
     ("LAZFORM"        "Pool from a filled-in chart")
     ("LAZFORMCOVER"   "Chart to pool, no bottom")
     ("SPA"            "Spa template")
     ("POOL"           "Pool layout")
     ("POOLCOVER"      "Pool layout, no bottom")
     ("POOLDEMO"       "Worked pool example")
     ("OASIS"          "Freeform pool")
     ("FITABHD"        "Typed template fit")
     ("FITABHDCOVER"   "Typed template fit, no bottom")
     ("ABHD"           "Survey perimeter + bottom")
     ("ABHDCOVER"      "Survey perimeter, no bottom")
     ("ADAB"           "Organic shape points")
     ("CABHD"          "Perimeter-only fit")
     ("LHD"            "Laser outline fit")
     ("PADDLE"         "Paddle pads")
     ("AUTOBEAD"       "Bead offsets")
     ("CORNERSTP"      "Corner step")
     ("HEMISTEP"       "Hemi step")
     ("NORMIESTEP"     "Normie step")
     ("SMARTFILLET"    "Corner radius, previewed")
     ("STOCKCOVER"     "Stock cover placement")
     ("WCALST"         "Unroll curved band"))
    ("Points"
     ("ABCDEF"         "Rectangle plot")
     ("ALTABCDEF"      "Clockwise rectangle plot")
     ("XYPLOT"         "X/Y offset plot")
     ("ABFIND"         "A/B stake ties")
     ("ABMOVE"         "Move mis-taped point")
     ("PERPPTS"        "Perpendicular points")
     ("CPERPPTS"       "Curved perp points")
     ("XFTCONV"        "Leica import cleanup")
     ("DRONE"          "Drone cleanup")
     ("TYDRN"          "Text + point tidy-up"))
    ("Dimensions"
     ("AUTODIM"        "Auto dimension")
     ("AUTODIMSIDEPOV" "Side-view dims")
     ("STAIRDIM"       "Stair dims")
     ("FLOORDIM"       "Floor dims")
     ("DIMCONTEND"     "Continue dim chains")
     ("CDCREATE"       "Lines to cross dims")
     ("CDCALLOUT"      "Point-to-point cross dims")
     ("BPCALLOUT"      "Bad point callout"))
    ("Checking"
     ("CHECK"          "Drawing check")
     ("DIMARCCHECK"    "Arc endpoint check")
     ("DIMCHECK"       "Dimension review")
     ("DIMSCAN"        "Dimension scan")
     ("LINCHECK"       "Line checklist")
     ("LINFINCHECK"    "Liner finish review")
     ("LINFINSCAN"     "Liner finish scan")
     ("LITELINFINSCAN" "Liner scan, no dims")
     ("COVERCHECK"     "Cover review")
     ("COVERSCAN"      "Cover scan")
     ("LITECOVERSCAN"  "Cover scan, no dims")
     ("SPACHECK"       "Spa sheet review")
     ("SPACHECKSCAN"   "Spa sheet scan")
     ("LITESPACHECKSCAN" "Spa scan, no dims")
     ("LINTXTCHK"      "Liner checklist text")
     ("CCPRECHECK"     "Tech flow chart"))))

;; How the tab strip is laid out: one DCL row per entry, in this order.
;; The jobs sit on one line and the categories on the next, which is
;; both what they mean and what keeps the strip narrow -- eight tabs on
;; a single row run about 94 character cells, and DCL will not scroll a
;; dialog that is wider than the screen.  This is presentation only; the
;; pages themselves are still lzp:*groups*.  The test asserts the two
;; tables name exactly the same groups, so neither can drift.
(setq lzp:*rows*
  '(("Pool" "Cover" "Spa" "Rest")
    ("Layout" "Points" "Dimensions" "Checking")))

(setq lzp:*pick* nil)             ; the button clicked on the last run
(setq lzp:*tbname* "LazPanel")    ; the screen-button toolbar's name
(setq lzp:*iconerr* nil)          ; why the last icon write failed
(setq lzp:*pos* nil)              ; where the panel was last standing
(setq lzp:*go* nil)               ; the group a tab click asked for
(setq lzp:*icontype* nil)         ; which byte-array spelling worked
(setq lzp:*icondir* nil)          ; the folder the icons landed in
(setq lzp:*iconref* nil)          ; "name" on the support path, else "path"

;;; -------------------- roster access -----------------------------------

;; Every command on the panel, flat, in display order.
(defun lzp:group-commands (name / g c out)
  (foreach g lzp:*groups*
    (if (= (car g) name)
        (foreach c (cdr g) (setq out (cons (car c) out)))))
  (reverse out))

;; Folded, because a command that serves two jobs is listed on both
;; pages and the status line counts tools, not buttons.  First
;; appearance wins, so the order still reads as the panel is laid out.
(defun lzp:commands ( / g c out)
  (foreach g lzp:*groups*
    (foreach c (cdr g)
      (if (not (member (car c) out))
        (setq out (cons (car c) out)))))
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
    (setq out (cons "  : row {" out))
    (foreach g r
      (setq out (cons (strcat "    : button { key = \"tab_" g
                              "\"; label = \"" g "\"; }")
                      out)))
    (setq out (cons "  }" out)))
  (reverse out))

;; One page per group.  The whole roster is still one list -- the pages
;; are lzp:*groups* itself, so re-ordering or re-grouping the tools is
;; an edit to that table and nothing else.
(defun lzp:dcl-one (g / out c)
  ;; consed newest-first and reversed at the end, so this seed list
  ;; reads BACKWARDS: the dialog line last here comes out first
  (setq out (list (strcat "  : text { key = \"status\"; width = 60; "
                          "alignment = centered; }")
                  (strcat "  label = \"LazPanel " *lazpanel-version*
                          "  -  " (car g) "\";")
                  (strcat (lzp:dlgname (car g)) " : dialog {")))
  (setq out (append (reverse (lzp:tabstrip)) out))
  (setq out (cons "  : boxed_column {" out))
  (setq out (cons (strcat "    label = \"" (car g) "\";") out))
  (foreach c (cdr g)
    (setq out (cons (strcat "    : button { label = \"" (car c) "  -  "
                            (cadr c) "\"; key = \"" (car c) "\"; }")
                    out)))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : button { label = \"Close\"; key = \"cancel\"; "
                          "is_default = true; is_cancel = true; "
                          "fixed_width = true; alignment = centered; }")
                  out))
  (reverse (cons "}" out)))

;; Every page, one after another, in one generated file.
(defun lzp:dcl-lines ( / out g)
  (foreach g lzp:*groups*
    (setq out (append out (lzp:dcl-one g) (list ""))))
  out)

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
(defun lzp:bytearray (bytes / sa)
  (setq sa (vl-catch-all-apply
             'vlax-make-safearray
             (list 17 (cons 0 (1- (length bytes))))))
  (if (vl-catch-all-error-p sa)
      (setq sa (vl-catch-all-apply
                 'vlax-make-safearray
                 (list vlax-vbInteger (cons 0 (1- (length bytes))))))
      (setq lzp:*icontype* "VT_UI1"))
  (cond
    ((vl-catch-all-error-p sa) nil)
    (t (if (not lzp:*icontype*) (setq lzp:*icontype* "vbInteger"))
       (vlax-safearray-fill sa bytes)
       sa)))

(defun lzp:bmp-stream (st path bytes / sa)
  (setq lzp:*icontype* nil)
  (if (not (setq sa (lzp:bytearray bytes)))
      (exit))                                 ; caught by the caller
  (vlax-put st 'Type 1)                       ; adTypeBinary
  (vlax-invoke st 'Open)
  (vlax-invoke st 'Write sa)
  (vlax-invoke st 'SaveToFile path 2)         ; overwrite if present
  (vlax-invoke st 'Close)
  t)

(defun lzp:bmp-write (path size grid / st ok)
  (setq lzp:*iconerr* nil)
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
     (setq ok (vl-catch-all-apply
                'lzp:bmp-stream (list st path (lzp:bmp-bytes size grid))))
     (vl-catch-all-apply 'vlax-release-object (list st))
     (cond
       ((vl-catch-all-error-p ok)
        (setq lzp:*iconerr*
              (strcat "writing " path " failed: "
                      (vl-catch-all-error-message ok)))
        nil)
       (t path)))))

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
        (if (and (lzp:bmp-write s 16 lzp:*icon16*)
                 (lzp:bmp-write l 32 lzp:*icon32*))
            (progn (setq lzp:*icondir* dir)
                   (list s l))))))

;; What to hand SetBitmaps: bare names when the files sit on the support
;; path, full temp paths as the fallback.
(defun lzp:write-bmps ( / d)
  (setq lzp:*icondir* nil
        lzp:*iconref* nil)
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
    (princ))
  (setq lzp:*pick* nil
        lzp:*pos* nil
        g (car (car lzp:*groups*)))
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
          (setq have (lzp:loaded))
          (set_tile "status"
                    (strcat (itoa (length have)) " of "
                            (itoa (length (lzp:commands)))
                            " tools loaded - greyed are not in this session"))
          (foreach n (lzp:group-commands g)
            (action_tile n
              "(setq lzp:*pick* $key lzp:*pos* (done_dialog 1))")
            (if (not (member n have))
              (mode_tile n 1)))
          (foreach n lzp:*groups*
            (action_tile (strcat "tab_" (car n))
              (strcat "(setq lzp:*go* \"" (car n)
                      "\" lzp:*pos* (done_dialog 4))")))
          (action_tile "cancel" "(setq lzp:*pos* (done_dialog 0))")
          (setq rc (start_dialog))
          (cond
            ((= rc 4) (setq g lzp:*go*))      ; a tab: go round again
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

(defun c:LAZPANEL ( / pick)
  (if (setq pick (lzp:show))
    (lzp:launch pick))
  (princ))

(defun c:LAZBUTTON ( / tb)
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
  (princ))

(defun c:LAZICON ( / paths tb btn r)
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
  (setq paths (lzp:write-bmps))
  (cond
    (paths
     (princ (strcat "\n  written to : "
                    (if lzp:*icondir* lzp:*icondir* "?")
                    "  (as a " (if lzp:*icontype* lzp:*icontype* "?")
                    " array)"))
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
     (princ (strcat "\n  written    : NO - "
                    (if lzp:*iconerr* lzp:*iconerr* "no reason recorded")))))
  (princ))

(defun c:LAZPANELVER ()
  (princ (strcat "\nLAZPANEL " *lazpanel-version* " (LAZPANEL.lsp) - "
                 (itoa (length (lzp:commands))) " tools on the panel."))
  (princ))

;; Put the button up as the file loads, quietly: in a session where
;; the COM menu API is missing the panel still loads and LAZPANEL
;; still runs -- the button is a convenience, never a gate.
(vl-catch-all-apply 'lzp:button-init nil)

(princ (strcat "\nLAZPANEL " *lazpanel-version*
               " loaded.  LAZPANEL opens the panel;"
               " LAZBUTTON puts its button on screen."))
(princ)
