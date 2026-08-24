;;; ======================================================================
;;; LAZPANEL.lsp  --  clickable button panel that launches the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZPANEL       open the panel
;;;            LAZBUTTON      put the LazPanel button toolbar on screen
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
;;; orange L, a placeholder logo) is generated as two .bmp files under
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

(setq *lazpanel-version* "v1.3")

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

(setq lzp:*groups*
  '(("Layout"
     ("LAZFORM"        "Pool from a filled-in chart")
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

(setq lzp:*pick* nil)             ; the button clicked on the last run
(setq lzp:*tbname* "LazPanel")    ; the screen-button toolbar's name

;;; -------------------- roster access -----------------------------------

;; Every command on the panel, flat, in display order.
(defun lzp:commands ( / g c out)
  (foreach g lzp:*groups*
    (foreach c (cdr g)
      (setq out (cons (car c) out))))
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

(defun lzp:dcl-lines ( / g c out)
  ;; built newest-first (cons) and reversed once at the end, so the
  ;; seed list below is the header in REVERSE order
  (setq out (list "  : row {"
                  "  : text { key = \"status\"; width = 70; alignment = centered; }"
                  (strcat "  label = \"LazPanel  " *lazpanel-version* "\";")
                  "lazpanel : dialog {"))
  (foreach g lzp:*groups*
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
;;  file to install; the icon is an orange L (a placeholder logo).
;;
;;  Everything here is best effort by design.  A session without COM,
;;  with a locked CUI or an unwritable temp folder loses the button and
;;  keeps the panel -- which is why the load-time call sits inside
;;  vl-catch-all-apply and why nothing below reports its own failure.

;; The L, drawn in 16x16; the 32x32 icon is this grid doubled.
(setq lzp:*icon16*
  '("................"
    "................"
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXX.........."
    "...XXXXXXXXXX..."
    "...XXXXXXXXXX..."
    "...XXXXXXXXXX..."
    "................"
    "................"))

(defun lzp:le2 (n)
  (list (rem n 256) (rem (/ n 256) 256)))

(defun lzp:le4 (n)
  (append (lzp:le2 (rem n 65536)) (lzp:le2 (/ n 65536))))

;; Double a pixel grid: each row's characters twice, each row twice.
(defun lzp:grid2x (grid / out row s i c)
  (foreach row grid
    (setq s "" i 1)
    (while (<= i (strlen row))
      (setq c (substr row i 1)
            s (strcat s c c)
            i (1+ i)))
    (setq out (cons s (cons s out))))
  (reverse out))

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

(defun lzp:bmp-stream (st path bytes / sa)
  (vlax-put st 'Type 1)                       ; adTypeBinary
  (vlax-invoke st 'Open)
  (setq sa (vlax-make-safearray 17            ; VT_UI1, a byte array
                                (cons 0 (1- (length bytes)))))
  (vlax-safearray-fill sa bytes)
  (vlax-invoke st 'Write sa)
  (vlax-invoke st 'SaveToFile path 2)         ; overwrite if present
  (vlax-invoke st 'Close)
  t)

(defun lzp:bmp-write (path size grid / st ok)
  (setq st (vl-catch-all-apply 'vlax-create-object (list "ADODB.Stream")))
  (cond
    ((or (vl-catch-all-error-p st) (null st)) nil)
    (t
     (setq ok (vl-catch-all-apply
                'lzp:bmp-stream (list st path (lzp:bmp-bytes size grid))))
     (vl-catch-all-apply 'vlax-release-object (list st))
     (if (vl-catch-all-error-p ok) nil path))))

;; A STABLE path, not a fresh temp name each time: SetBitmaps stores the
;; path rather than the image, and AutoCAD re-reads it whenever the
;; button is redrawn.  A toolbar that survives into another session
;; would otherwise be pointing at a swept temp file for ever.
(defun lzp:icon-path (name / d)
  (setq d (getvar "TEMPPREFIX"))
  (if (and d (= (type d) 'STR) (/= d ""))
      (strcat d "lazpanel-" name ".bmp")
      (vl-filename-mktemp (strcat "lazpanel-" name) nil ".bmp")))

;; Both icon files; (small large) paths, or nil when they cannot be
;; written.
(defun lzp:write-bmps ( / small large)
  (setq small (lzp:icon-path "16")
        large (lzp:icon-path "32"))
  (if (and small large
           (lzp:bmp-write small 16 lzp:*icon16*)
           (lzp:bmp-write large 32 (lzp:grid2x lzp:*icon16*)))
    (list small large)))

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
                            (list btn (car paths) (cadr paths))))
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

(defun lzp:show ( / *error* f dcl rc pick have n)
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
  (setq lzp:*pick* nil)
  (cond
    ((not (setq f (lzp:write-dcl)))
     (princ "\nLAZPANEL error: could not write the dialog file."))
    ((< (setq dcl (load_dialog f)) 0)
     (princ "\nLAZPANEL error: could not load the dialog file."))
    ((not (new_dialog "lazpanel" dcl))
     (princ "\nLAZPANEL error: could not open the panel."))
    (t
     (setq have (lzp:loaded))
     (set_tile "status"
               (strcat (itoa (length have)) " of "
                       (itoa (length (lzp:commands)))
                       " tools loaded - greyed buttons are not in this session"))
     (foreach n (lzp:commands)
       (action_tile n "(setq lzp:*pick* $key) (done_dialog 1)")
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
  (setq pick lzp:*pick*
        lzp:*pick* nil)
  (if (and rc (= rc 1) pick)
    pick))

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
