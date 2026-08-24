;;; ======================================================================
;;; CALPANEL.lsp  --  clickable button panel that launches the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  CALPANEL       open the panel
;;;            CALPANELVER    print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Every headline calofin routine as a button, grouped the way the
;;; drafter thinks about them (the same four groups as the VB.NET
;;; palette in ui/calofin_net: Layout, Points, Dimensions, Checking).
;;; Clicking a button closes the panel and runs the command exactly as
;;; if its name had been typed -- the panel adds nothing in front of a
;;; tool and nothing behind it.
;;;
;;; ZERO INSTALL.  The dialog is plain DCL, and this file writes its own
;;; .dcl into the system temp folder each time the panel opens, so there
;;; is no second file to ship, no support-path entry to add and no DLL
;;; to NETLOAD.  APPLOAD this one file (or LAZPASS.lsp, which carries
;;; it), type CALPANEL, click.
;;;
;;; A button whose command is not loaded in this session is greyed out
;;; rather than left to fail -- the same availability probe the VB
;;; palette uses (read the name, evaluate it: an unbound C: symbol is
;;; nil).  The status line across the top says how many tools the
;;; session has.
;;;
;;; DCL dialogs are modal, so the panel cannot stay open while a tool
;;; runs the way a docked palette can: click, the panel closes, the tool
;;; runs, CALPANEL reopens it.  The *SCAN companions are on the panel;
;;; satellites reachable from their headline tool (TUTORIAL*
;;; walkthroughs, *VER reporters, *RESCUE undo companions, -CFG /
;;; -SETUP partners) stay off on purpose, and so does the DD*
;;; drone-height toolset -- eight specialist photo-EXIF commands that
;;; are not part of the drafting flow the panel serves.
;;; tests/test_calpanel.py pins the roster to the commands actually
;;; defined under lisp/, so a new tool without a button fails the suite
;;; instead of being quietly missing.
;;; ======================================================================

(vl-load-com)

(setq *calpanel-version* "v1.0")

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
;;  tests/test_calpanel.py enforces all five rules against the tree.

(setq cpl:*groups*
  '(("Layout"
     ("SPA"            "Spa template")
     ("POOL"           "Pool layout")
     ("POOLDEMO"       "Worked pool example")
     ("OASIS"          "Freeform pool")
     ("FITABHD"        "Typed template fit")
     ("ABHD"           "Survey perimeter + bottom")
     ("ADAB"           "Organic shape points")
     ("CABHD"          "Perimeter-only fit")
     ("LHD"            "Laser outline fit")
     ("PADDLE"         "Paddle pads")
     ("AUTOBEAD"       "Bead offsets")
     ("CORNERSTP"      "Corner step")
     ("HEMISTEP"       "Hemi step")
     ("NORMIESTEP"     "Normie step")
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
     ("COVERCHECK"     "Cover review")
     ("COVERSCAN"      "Cover scan")
     ("SPACHECK"       "Spa sheet review")
     ("SPACHECKSCAN"   "Spa sheet scan")
     ("LINTXTCHK"      "Liner checklist text")
     ("CCPRECHECK"     "Tech flow chart"))))

(setq cpl:*pick* nil)   ; the button clicked on the last run, if any

;;; -------------------- roster access -----------------------------------

;; Every command on the panel, flat, in display order.
(defun cpl:commands ( / g c out)
  (foreach g cpl:*groups*
    (foreach c (cdr g)
      (setq out (cons (car c) out))))
  (reverse out))

;; Is C:<name> defined in this session?  An unbound symbol evaluates to
;; nil in AutoLISP, so reading the name and evaluating it is enough --
;; and it stays correct for commands loaded after this file was.
(defun cpl:has (name)
  (if (eval (read (strcat "C:" name))) t nil))

;; The subset of the roster that is loaded right now.
(defun cpl:loaded ( / n out)
  (foreach n (cpl:commands)
    (if (cpl:has n)
      (setq out (cons n out))))
  (reverse out))

;;; -------------------- the dialog --------------------------------------
;;  The DCL is built here as a list of lines and written to a temp file
;;  when the panel opens, so the whole panel travels inside this one
;;  .lsp.  Keys are the command names themselves; boxed columns carry
;;  the group labels.

(defun cpl:dcl-lines ( / g c out)
  ;; built newest-first (cons) and reversed once at the end, so the
  ;; seed list below is the header in REVERSE order
  (setq out (list "  : row {"
                  "  : text { key = \"status\"; width = 70; alignment = centered; }"
                  (strcat "  label = \"Calofin tools  " *calpanel-version* "\";")
                  "calpanel : dialog {"))
  (foreach g cpl:*groups*
    (setq out (cons (strcat "      label = \"" (car g) "\";")
                    (cons "    : boxed_column {" out)))
    (foreach c (cdr g)
      (setq out (cons (strcat "      : button { label = \"" (car c) "  -  "
                              (cadr c) "\"; key = \"" (car c) "\"; }")
                      out)))
    (setq out (cons "    }" (cons "      spacer;" out))))
  (setq out (cons "  }" out))
  (setq out (cons "  spacer;" out))
  (setq out (cons (strcat "  : button { label = \"Close\"; key = \"cancel\"; "
                          "is_default = true; is_cancel = true; "
                          "fixed_width = true; alignment = centered; }")
                  out))
  (reverse (cons "}" out)))

;; The write loop, alone so it can run under vl-catch-all-apply: if a
;; write dies half way (disk full, quota) the handle still gets closed
;; and the partial file deleted instead of being handed to load_dialog.
(defun cpl:write-lines (fh / l)
  (foreach l (cpl:dcl-lines)
    (write-line l fh)))

;; Write the dialog into the system temp folder; the path comes back,
;; or nil when the folder cannot be written to.
(defun cpl:write-dcl ( / f fh err)
  (setq f (vl-filename-mktemp "calpanel" nil ".dcl"))
  (if (and f (setq fh (open f "w")))
    (progn
      (setq err (vl-catch-all-apply 'cpl:write-lines (list fh)))
      (close fh)
      (cond
        ((vl-catch-all-error-p err)
         (vl-file-delete f)
         nil)
        (t f)))))

;; Run a roster command by name, exactly as if it had been typed.  The
;; probe guards the greyed-button race: a command that vanished between
;; opening the panel and clicking reports itself instead of erroring.
(defun cpl:launch (name / fn)
  (setq fn (read (strcat "C:" name)))
  (cond
    ((eval fn)
     (princ (strcat "\nCALPANEL: running " name
                    " -- CALPANEL reopens the panel."))
     (eval (list fn)))
    (t
     (princ (strcat "\nCALPANEL: " name
                    " is not loaded in this session.")))))

;;; -------------------- the dialog run ----------------------------------
;;  No sysvar save, no undo group: the panel changes no settings and
;;  draws nothing -- whatever it launches manages its own.  The error
;;  handler only has the dialog and the temp file to pick up.
;;
;;  This is a helper rather than the command body so that its localized
;;  *error* is OUT OF SCOPE by the time anything is launched: the tool
;;  the user clicked gets whatever error handling it sets up itself,
;;  and a tool that fails reports as itself, not as "CALPANEL error".

(defun cpl:show ( / *error* f dcl rc pick have n)
  (defun *error* (msg)
    ;; the dialog itself first: unload_dialog alone does not dismiss a
    ;; dialog that is still up, term_dialog does (and is a no-op when
    ;; none is)
    (term_dialog)
    (if (and dcl (>= dcl 0)) (unload_dialog dcl))
    (setq dcl nil)
    (if f (vl-file-delete f))
    (setq f nil cpl:*pick* nil)
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nCALPANEL error: " msg)))
    (princ))
  (setq cpl:*pick* nil)
  (cond
    ((not (setq f (cpl:write-dcl)))
     (princ "\nCALPANEL error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nCALPANEL error: could not load the dialog file."))
    ((not (new_dialog "calpanel" dcl))
     (princ "\nCALPANEL error: could not open the panel."))
    (t
     (setq have (cpl:loaded))
     (set_tile "status"
               (strcat (itoa (length have)) " of "
                       (itoa (length (cpl:commands)))
                       " tools loaded - greyed buttons are not in this session"))
     (foreach n (cpl:commands)
       (action_tile n "(setq cpl:*pick* $key) (done_dialog 1)")
       (if (not (member n have))
         (mode_tile n 1)))
     (setq rc (start_dialog))))
  ;; the dialog and its temp file go away BEFORE anything is launched,
  ;; so an interactive command never starts under an open modal dialog
  ;; and the temp file never outlives the panel
  (if (and dcl (>= dcl 0)) (unload_dialog dcl))
  (setq dcl nil)
  (if f (vl-file-delete f))
  (setq f nil)
  (setq pick cpl:*pick*
        cpl:*pick* nil)
  (if (and rc (= rc 1) pick)
    pick))

;;; -------------------- commands ----------------------------------------

(defun c:CALPANEL ( / pick)
  (if (setq pick (cpl:show))
    (cpl:launch pick))
  (princ))

(defun c:CALPANELVER ()
  (princ (strcat "\nCALPANEL " *calpanel-version* " (CALPANEL.lsp) - "
                 (itoa (length (cpl:commands))) " tools on the panel."))
  (princ))

(princ (strcat "\nCALPANEL " *calpanel-version*
               " loaded.  Type CALPANEL to open the panel."))
(princ)
