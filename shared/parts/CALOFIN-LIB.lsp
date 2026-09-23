;;; ======================================================================
;;; CALOFIN-LIB.lsp  --  the shared helper library for the calofin tools
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP + ActiveX for bboxes).
;;;
;;; Every routine in shared/ calls these helpers instead of embedding its
;;; own copy, so this file must be loaded FIRST -- APPLOAD LAZPASS.lsp (or
;;; CALOFIN-LOADER.lsp for the multi-file build) and
;;; the order is handled for you.  The standalone builds in lisp/ do not
;;; use this file; they embed their own copies and load alone.
;;;
;;; Namespace: cal: for every function, cal:*name* for every global.
;;; The Back sentinel returned by the ask helpers is the symbol CAL-BACK.
;;;
;;; Each helper is the proven implementation lifted from the tool named
;;; beside it, behavior-identical unless a comment says otherwise.  The
;;; divergent variants deliberately NOT absorbed here (POOL/SPA's unit
;;; that returns (0.0 0.0), abhd/lhd's 2-element circumcenter, the
;;; tutorials' pause polarity, ...) stay in their own tools -- see
;;; STANDARDS.md section 6.
;;;
;;; Command:  CALVER   this library's version, and every calofin file
;;;                   loaded in this session with the version it is at
;;; ======================================================================

(vl-load-com)

(setq cal:*version* "v2.6")


;;  WHAT IS LOADED, AND AT WHICH VERSION.  Every tool reports its own
;;  version with a <TOOL>VER command, and CALVER used to report one of
;;  them -- this file's -- so the question a support call actually asks
;;  ("what are you running?") was one command per tool's worth of
;;  typing, and a LAZDIAG report names only the tool that failed.
;;
;;  There is no table of versions here and there is not going to be:
;;  every tool sets its own banner global as it loads, so the SESSION
;;  is the table.  atoms-family reads it, which means a drafter who
;;  has APPLOADed a newer single file over the bundle sees the newer
;;  number against that one tool -- exactly the mix a support call is
;;  usually trying to untangle, and exactly what a generated list
;;  would have hidden.

;; The version globals this session carries, as (label value symbol)
;; rows sorted by label.  Two banner spellings exist -- *tool-version*
;; and the POOL/SPA ns:*version* -- and both end up as the tool's name;
;; the symbol rides along so the sort has something unique to order on.
(defun cal:vlabel (n / s)
  (setq s n)
  ;; vl-string-search counts from 0, so the index IS the length of the
  ;; part in front of the colon
  (if (wcmatch s "*:*") (setq s (substr s 1 (vl-string-search ":" s))))
  (setq s (vl-string-trim "*" s))
  (if (wcmatch (strcase s) "*-VERSION")
    (setq s (substr s 1 (- (strlen s) 8))))
  (strcase s))

(defun cal:versions ( / out n v)
  (foreach n (atoms-family 1)
    (if (and (wcmatch n "*VERSION*")
             (= (type (setq v (eval (read n)))) 'STR))
      (setq out (cons (list (cal:vlabel n) v n) out))))
  ;; Sorted on the label AND the symbol it came from, because vl-sort
  ;; DROPS any element its comparison calls equal to another.  Sorting
  ;; on the label alone loses one of two files whose banner globals
  ;; reduce to the same name -- *cchk-version* and cchk:*version* both
  ;; read CCHK -- and losing one silently is the one thing this command
  ;; must not do.  A symbol name is unique in a session, so no two rows
  ;; can compare equal and nothing can be dropped.
  (vl-sort out '(lambda (a b) (< (strcat (car a) " " (caddr a))
                                 (strcat (car b) " " (caddr b))))))

(defun c:CALVER ( / all v)
  (princ (strcat "\nCALOFIN-LIB " cal:*version*))
  (setq all (cal:versions))
  (cond
    ((null all) (princ))
    (t
     (princ (strcat "\n" (itoa (length all))
                    " calofin file(s) loaded in this session:"))
     (foreach v all
       (princ (strcat "\n  " (cal:pad (car v) 22) " " (cadr v))))))
  (princ))

;;; -------------------- ask layer ---------------------------------------
;;; From pool:askkw / spa:askkw (POOL.LSP:557, byte-identical twins).
;;; kws is the initget string, shown the bracketed list, dflt the Enter
;;; answer (nil = an answer is required).  Returns the keyword or CAL-BACK.
;;; Undo is accepted everywhere Back is, as a hidden synonym.

(defun cal:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'CAL-BACK)
        ((null v) (if dflt dflt (cal:askkw msg kws shown dflt back)))
        (t v)))

;; Yes/No that can be backed out of.  Returns T, nil or CAL-BACK.
;; From pool:askyn (POOL.LSP:568).
(defun cal:askyn (msg dflt back / v)
  (setq v (cal:askkw msg "Yes No" "Yes/No" dflt back))
  (if (eq v 'CAL-BACK) v (= v "Yes")))

;; Distance entry with the kind system of STANDARDS.md section 3:
;; REQ required, NAX accepts NA, ZER accepts NA and zero, SUG offers a
;; default that Enter takes.  Returns the number, nil for NA, or
;; CAL-BACK.  (From pool:asks / spa:asks, POOL.LSP:522, with the
;; order-sheet highlighting left behind in POOL -- a generated drawing
;; has no entity to light up.)
(defun cal:askdist (kind msg dflt back / v kw)
  ;; Undo is accepted everywhere Back is, as a hidden synonym
  (setq kw (cond ((eq kind 'REQ) (if back "Back Undo" nil))
                 (back "NA Back Undo")
                 (t "NA")))
  ;; REQ always rejects zero - offering Back must not loosen what
  ;; counts as a valid measurement; ZER alone admits 0
  (if kw
      (initget (cond ((eq kind 'ZER) 5)
                     ((and (eq kind 'SUG) dflt) 6)
                     (t 7))
               kw)
      (initget 7))
  (setq v (getdist
            (strcat "\n" msg
                    (cond ((eq kind 'REQ) "")
                          ((eq kind 'SUG)
                           (if dflt (strcat " <" (rtos dflt) "> (or NA)")
                               " (or NA)"))
                          (t " (or NA if not measured)"))
                    (if back " [Back]" "")
                    ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((and (= (type v) 'STR) (member v '("Back" "Undo"))) 'CAL-BACK)
        ((= (type v) 'STR) nil)               ; NA
        ((and (null v) (eq kind 'SUG)) dflt)  ; Enter took the suggestion
        (t v)))

;; The Treatment question of STANDARDS.md section 2: "How should
;; <subject> be treated?"  Returns "Square", "Radius", "Cut" or
;; "NotGiven" -- the legacy words and NG are accepted typed in full and
;; normalized HERE, never downstream -- or CAL-BACK.
(defun cal:asktreat (subject dflt back / v kws)
  ;; the bracket is DERIVED from the visible words (section 1 rule 1),
  ;; so it cannot drift from the initget list; the hidden aliases go on
  ;; the initget list only
  (setq kws "Square Radius Cut NotGiven")
  (setq v (cal:askkw (strcat "How should " subject " be treated?")
                     (strcat kws " NG 90 ROUNDED DIAG DIAGONAL")
                     (vl-string-translate " " "/" kws)
                     dflt back))
  (cond ((eq v 'CAL-BACK) v)
        ((= v "NG") "NotGiven")
        ((= v "90") "Square")
        ((= v "ROUNDED") "Radius")
        ((member v '("DIAG" "DIAGONAL")) "Cut")
        (t v)))

;; Yes/No with the default baked into the prompt and no Back -- the
;; review-loop form.  From cchk:ask-yn / cchk:ask-ny (covercheck.lsp:489,
;; 495; dchk:/lfc: identical) with the default as an argument: pass
;; "Yes" for the old ask-yn, "No" for the cautious ask-ny.  The caller
;; supplies any leading \n in msg, as the originals did.
(defun cal:ask-yn (msg dflt / ans)
  (initget "Yes No")
  (setq ans (getkword (strcat msg " [Yes/No] <" dflt ">: ")))
  (if lzd:ask (lzd:ask msg ans) ans)
  (if (null ans) (setq ans dflt))
  (= ans "Yes"))

;; The reviewing question, with a way out of a mis-press.  Returns the
;; symbols yes / no / back / skip.  From cchk:ask-yn-nav
;; (covercheck.lsp:501; dchk:/lfc: byte-identical).
(defun cal:ask-yn-nav (msg / ans)
  (initget "Yes No Back Skip Undo")   ; Undo = hidden synonym for Back
  ;; the bracket is exactly the keyword list (STANDARDS section 1 rule
  ;; 1): a click sends the bracket text, and "Skip rest" was a click
  ;; the initget list could not accept
  (setq ans (getkword (strcat msg " [Yes/No/Back/Skip] <Yes>: ")))
  (if lzd:ask (lzd:ask msg ans) ans)
  (cond ((null ans)      'yes)
        ((= ans "Yes")   'yes)
        ((= ans "No")    'no)
        ((= ans "Back")  'back)
        ((= ans "Undo")  'back)
        (t               'skip)))

;; Typed prompts cannot take keywords, so Back is typed like a value.
;; The shared predicate (pf:back-word, lin:back-word, chk:back-word,
;; cdo:backp, dd-back-word -- all byte-identical).
(defun cal:back-word-p (s)
  (member (strcase s) '("B" "BACK" "U" "UNDO")))

;; Free-text entry (notes, feet-inch dimensions).  Returns the string
;; (Enter = dflt when one is given) or CAL-BACK.
(defun cal:askstr (msg dflt back / v)
  (setq v (getstring T (strcat "\n" msg
                               (if dflt (strcat " <" dflt ">") "")
                               (if back " (B = back)" "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((and back (cal:back-word-p v)) 'CAL-BACK)
        ((= v "") (if dflt dflt v))
        (t v)))

;; The one pause wording of STANDARDS.md section 3, for new code.  The
;; POOL/SPA tutorials keep their own pauses -- theirs can stop the
;; tutorial, and the two disagree about which answer means stop.
(defun cal:pause ()
  ((lambda (v) (if lzd:ask (lzd:ask "\n--- press Enter to continue ---" v) v))
    (getstring "\n--- press Enter to continue ---"))
  (princ))

;;; -------------------- system variables --------------------------------
;;; The snapshot lives in a GLOBAL, and a variable already in it is
;;; never captured again: if a previous run died before restoring, the
;;; stale snapshot still holds the user's TRUE settings, and saving them
;;; again at that point would capture the zeroed OSMODE and every later
;;; run would faithfully "restore" 0.  (From pool:/spa:syssave,
;;; POOL.LSP:5504.)  One thing the per-tool originals never faced: here
;;; EVERY tool shares the one snapshot, and the tools list different
;;; variables.  So a variable the pending snapshot lacks is ADDED rather
;;; than the whole save skipped -- otherwise a run after an interrupted
;;; one would change CLAYER, say, and never put it back, because the run
;;; that took the snapshot never listed it.  Restore runs in the saved
;;; order, so put OSMODE first in the list -- object snaps are the
;;; setting the user misses most if a run is ever cut short partway.

(defun cal:syssave (vars / v)
  (foreach v vars
    (if (and (not (assoc v cal:*sysold*))
             (/= nil (getvar v)))
        (setq cal:*sysold*
              (append cal:*sysold* (list (cons v (getvar v))))))))

(defun cal:sysrestore ( / p)
  (foreach p cal:*sysold* (setvar (car p) (cdr p)))
  (setq cal:*sysold* nil))

;; The current dimension style is read-only to setvar, so it has its own
;; snapshot pair and restores via a command.  (From spa:syssave/:restore.)
(defun cal:dimstysave ()
  (if (not cal:*odstyle*) (setq cal:*odstyle* (getvar "DIMSTYLE"))))

(defun cal:dimstyrestore ( / doc)
  ;; The style comes back through ActiveX, not -DIMSTYLE.  This runs from
  ;; *error* handlers, some of which PUSH the error mode, and under a push
  ;; AutoCAD refuses command-s outright -- "INTERNAL error in FAIL, message
  ;; lost, reset to top" -- which vl-catch-all-apply cannot catch: the handler
  ;; died here, the undo group stayed open, the mode stayed pushed and
  ;; the failure was never reported.  A property put drives no command,
  ;; so it is legal in every error mode and a throw from it IS caught.
  (if (and cal:*odstyle* (tblsearch "DIMSTYLE" cal:*odstyle*))
      (vl-catch-all-apply
        '(lambda ()
           (vl-load-com)
           (setq doc (vla-get-activedocument (vlax-get-acad-object)))
           (vla-put-activedimstyle
             doc (vla-item (vla-get-dimstyles doc) cal:*odstyle*)))
        '()))
  (setq cal:*odstyle* nil))

;; T when MSG is the message of a plain cancel (Esc, quit) rather than
;; a real error.  The canonical test of STANDARDS section 5 -- ten
;; hand-copied variants of it existed, two with the same typo, which is
;; why it is a helper now.
(defun cal:error-cancel-p (msg)
  (and msg (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))

;; One undo group per command, in the one casing (STANDARDS section 5).
;; Track the open group in a local and close it from *error* too:
;;   (setq undo-open (cal:undobegin))
;;   ... (if undo-open (cal:undoend)) ...
;; Opens only while undo is recording - _Begin in a drawing with UNDO
;; off (bit 1 of UNDOCTL clear) errors out of the command - and returns
;; nil then, so the idiom above skips the close it does not own.
(defun cal:undobegin ()
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn (command "_.UNDO" "_Begin") T)))

(defun cal:undoend ()
  (command "_.UNDO" "_End")
  nil)

;; The user's own object snaps stay LIVE during every measurement
;; prompt; OSMODE is zeroed only while a routine feeds points to
;; commands, where a snap would grab the wrong geometry.  Coupled to
;; the cal:syssave snapshot.  (From pool:/spa:osup, POOL.LSP:480.)
(defun cal:osup ( / p)
  (setq p (assoc "OSMODE" cal:*sysold*))
  (if p (setvar "OSMODE" (cdr p))))

(defun cal:osdown () (setvar "OSMODE" 0))

;;; -------------------- settings, the theme and the ink -----------------
;;;
;;;  Three things a tool cannot learn by reading itself: what the shop
;;;  has changed, which way AutoCAD's interface reads, and which way the
;;;  drawing it is about to draw into reads.  All three are answered
;;;  here, once, so that a colour is CHOSEN in one table instead of
;;;  being assumed in fourteen tunables blocks.

;; A setting the drafter may have moved out of the source: the profile
;; value KEY holds, or DFLT when it holds nothing.  The literal in the
;; file stays the default, so a tree with no profile entries behaves
;; exactly as it reads -- what the profile buys is SURVIVAL, which the
;; source does not have: releases/ and LAZPASS.lsp are generated, so a
;; number edited into either is gone at the next regeneration.  (From
;; STOCKCOVER's stock:getenv and LAZDIAG's CalofinErrorDir, which had
;; this idea one folder at a time.)
(defun cal:setting (key dflt / v)
  (setq v (getenv key))
  (if (and v (/= v "")) v dflt))

;; What CalofinTheme has been set to: 'dark, 'light, or nil for "work
;; it out".  One override for both probes below, because a drafter who
;; disagrees with what was measured should have to say so once rather
;; than once per tool.  CALSET writes it.
(defun cal:themeset ( / v)
  ;; trimmed: this is typed by a person, and " dark " meaning nothing
  ;; at all would be a silent no-op they could stare at for a while
  (setq v (strcase (vl-string-trim " \t" (cal:setting "CalofinTheme" "AUTO"))))
  (cond ((= v "DARK") 'dark)
        ((= v "LIGHT") 'light)))

;; Which way AutoCAD's INTERFACE reads: 'dark, 'light, or nil when the
;; release will not say (COLORTHEME arrived with 2015).  The DCL tiles
;; and the toolbar icon follow this one and not the drawing: a dialog's
;; -15 and -16 are whatever the interface is, so anything drawn beside
;; them has to be asking the same question or it comes out half themed.
(defun cal:ui ( / v)
  (cond ((cal:themeset))
        ((null (setq v (getvar "COLORTHEME"))) nil)
        ((= v 0) 'dark)
        (t 'light)))

;; Which way the DRAWING reads: 'dark, 'light, or nil when the
;; background cannot be measured.  A different question from cal:ui --
;; the interface theme and the model background are set in different
;; dialogs, and a light-themed AutoCAD over the stock near-black model
;; space is an ordinary way to work.
;;
;; The measurement is COM, so it is wrapped: a session that cannot
;; reach ActiveX answers nil rather than dying inside a colour lookup.
;; Nothing is cached.  Caching it would be one global more than this
;; buys: the review tools resolve the grey ONCE per pass into a local
;; of the command, which is where the volume is, and the rest of the
;; tree asks for a colour two or three times in a run.  A cache would
;; also have to be a session global, and COVERCHECK, DIMCHECK and
;; LINFINCHECK each say in their own tunables block that they keep no
;; state between runs -- a claim worth more than three property gets.
(defun cal:bg ( / c lum)
  (cond
    ((cal:themeset))
    (t
     (setq c (vl-catch-all-apply
               '(lambda ()
                  (vl-load-com)
                  (vla-get-GraphicsWinModelBackgrndColor
                    (vla-get-Display
                      (vla-get-Preferences (vlax-get-acad-object)))))
               nil))
     (if (or (vl-catch-all-error-p c) (not (numberp c)))
       nil
       (progn
         ;; an OLE colour is packed low byte first: R, then G, then B
         (setq c   (fix c)
               lum (+ (* 0.30 (rem c 256))
                      (* 0.59 (rem (/ c 256) 256))
                      (* 0.11 (rem (/ c 65536) 256))))
         (if (< lum 128.0) 'dark 'light))))))

;; A per-ROLE override a drafter has set through CALSET's Itemcolors
;; menu: CalofinInk-<ROLE> in the profile, or nil when none is set for
;; this role -- or when what is set is not a colour.  CALSET and LAZSET
;; both refuse anything but 1-255 now (lzp:aci-p), but an older CALSET
;; stored whatever atoi made of the typed text, so "300" or "-3" can
;; still be sitting in a profile; read as no override, it never reaches
;; grdraw or entmod.  Works for any role, fade/guide/dim/hi included,
;; though today only the item-type roles below are reachable from CALSET.
(defun cal:inkoverride (role / q v)
  (setq q (assoc role '((fade . "FADE") (guide . "GUIDE") (dim . "DIM")
                         (hi . "HI") (flag . "FLAG") (arc . "ARC")
                         (olap . "OLAP") (orig . "ORIG") (sugg . "SUGG")
                         (point . "POINT") (constr . "CONSTR")
                         (report . "REPORT"))))
  (if q
    (progn
      (setq v (cal:setting (strcat "CalofinInk-" (cdr q)) ""))
      (if (/= v "") (setq v (atoi v)))
      (if (and (numberp v) (< 0 v 256)) v))))

;;  THE INK TABLE.  A colour knob set to 'auto asks for the ACI that
;;  suits the background it will be seen against; a knob set to a
;;  NUMBER is used exactly as given, so a shop that has picked its own
;;  colours keeps them and every existing test still measures what it
;;  measured before.
;;
;;    role     what it is                    dark  light  unmeasured
;;    fade     the review tools' grey-out     251    254        8
;;    guide    preview and guide geometry     253      8        8
;;    dim      a chart tile's dimensions      253      8        8
;;    hi       a chart tile's active box        4      5        5
;;
;;  fade and guide are drawn into the DRAWING and read cal:bg; dim and
;;  hi are drawn inside a dialog and read cal:ui.
;;
;;  Two rules decided the numbers.  FADE has to recede, which on a dark
;;  background means darker than the work and on a light one means
;;  lighter: 8 does the first and the opposite of the second, which is
;;  why a review sheet opened on a white background used to come up
;;  with its greyed-out half as the most prominent thing on screen.
;;  GUIDE has to be read while it is answered but not compete with the
;;  pool, which is 8 on white and nearly the background itself on the
;;  stock dark grey.  The unmeasured column is deliberately what the
;;  tree did before this table existed: a session that cannot tell is
;;  not a session that behaves differently.
;;
;;  ITEM-TYPE COLOURS.  A second set of roles, alongside the four
;;  above, for parts of a review that are not about the SCREEN at all
;;  but about what KIND of thing is being marked -- a flagged error, an
;;  arc whose endpoints moved, an overlap, the point as drawn versus
;;  the one suggested, the construction line, the report text.
;;  COVERCHECK, DIMCHECK and LINFINCHECK each carried the same eight
;;  numbers as a separate literal copy; this table is the one place
;;  they are decided now.
;;
;;    role     what it is                                    ACI
;;    flag     what a drafter answered "No" to                 1  red
;;    arc      an arc whose endpoints were moved                6  magenta
;;    olap     a merged or flagged overlapping line             4  cyan
;;    orig     the X at the point as drawn                      1  red
;;    sugg     the + at the point the tool suggests              3  green
;;    point    the crosses at an overlap's two ends              2  yellow
;;    constr   the construction line through moved points       2  yellow
;;    report   the report text                                  3  green
;;
;;  None of these vary with the screen the way fade/guide/dim/hi do --
;;  they are the same ordinary ACI colours on any background the three
;;  review tools have ever drawn on -- so there is no dark/light table
;;  for them, only the override above and CALSET's Itemcolors menu.
(defun cal:ink (knob role / th ov)
  ;; numberp, not (eq knob 'auto): a knob is a colour NUMBER used
  ;; exactly as given, or it is resolved.  Testing for 'auto instead
  ;; would hand back whatever a mistyped knob holds -- nil, or the
  ;; symbol AUOT -- and that reaches entmake as a DXF group 62, where
  ;; it dies a long way from the line that caused it.
  (cond
    ((numberp knob) knob)
    ((setq ov (cal:inkoverride role)) ov)
    ((setq ov (assoc role '((flag . 1) (arc . 6) (olap . 4) (orig . 1)
                             (sugg . 3) (point . 2) (constr . 2)
                             (report . 3))))
     (cdr ov))
    (t
     (setq th (if (member role '(dim hi)) (cal:ui) (cal:bg)))
     (cond
       ((eq role 'fade)
        (cond ((eq th 'dark) 251) ((eq th 'light) 254) (t 8)))
       ((eq role 'guide)
        (cond ((eq th 'dark) 253) ((eq th 'light) 8) (t 8)))
       ((eq role 'dim)
        (cond ((eq th 'dark) 253) ((eq th 'light) 8) (t 8)))
       ((eq role 'hi)
        (cond ((eq th 'dark) 4) ((eq th 'light) 5) (t 5)))
       (t 7)))))

;;; -------------------- layers ------------------------------------------

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case (WCALST draws on the return
;; value).  (From pf:ensure-layer, abhd.lsp:1402; announcement kept,
;; tool prefix dropped.)  Point it at OUTPUT layers only -- the review
;; tools' consent-based unlock of SELECTION layers is a different job.
(defun cal:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nLayer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; T when layer NAME exists and can be drawn on right now.  A read-only
;; test -- it repairs nothing.  (From cs-layerok, CORNERSTP.lsp:308.)
;;
;; A NAME that is not a string is not a layer, and answers nil the way
;; a layer that is not there does: tblsearch takes a string and throws
;; "bad argument type: stringp" on anything else, which is a failure
;; report in the drafter's Downloads folder rather than an answer.
;; Every caller here reads its name out of a KNOB, and a knob holds
;; whatever somebody left in it.
(defun cal:layer-usable-p (name / ld f cl)
  (if (and (= (type name) 'STR) (setq ld (tblsearch "LAYER" name)))
    (progn
      (setq f  (cond ((cdr (assoc 70 ld))) (0))
            cl (cond ((cdr (assoc 62 ld))) (7)))
      (and (zerop (logand 1 f))                  ; not frozen
           (zerop (logand 4 f))                  ; not locked
           (> cl 0)))))                          ; not off

;;; -------------------- 2-D vector helpers ------------------------------
;;; Strictly 2-element results; inputs may be 2- or 3-element (the Z is
;;; dropped).  From the pf:/lh: set (abhd.lsp:330), the most defensive
;;; of the nine copies.  POOL/SPA keep their own unit -- theirs returns
;;; (0.0 0.0) for a zero vector where this one returns nil, and callers
;;; branch on that.  AutoDim keeps its mapcar 3-D set (cal:dotn/midn).

(defun cal:2d (p) (list (car p) (cadr p)))
(defun cal:dist (a b) (distance (cal:2d a) (cal:2d b)))
(defun cal:v- (a b) (mapcar '- (cal:2d a) (cal:2d b)))
(defun cal:v+ (a b) (mapcar '+ (cal:2d a) (cal:2d b)))
(defun cal:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun cal:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun cal:mid (a b) (cal:v* (cal:v+ a b) 0.5))
(defun cal:perp (v) (list (- (cadr v)) (car v))) ; rotate 90 deg CCW
(defun cal:vlen (v) (sqrt (cal:dot v v)))
(defun cal:d2 (a b / dx dy)                      ; squared 2-D distance
  (setq dx (- (car a) (car b)) dy (- (cadr a) (cadr b)))
  (+ (* dx dx) (* dy dy)))
(defun cal:cross (a b)                           ; 2-D scalar cross
  (- (* (car a) (cadr b)) (* (cadr a) (car b))))

;; v scaled to length 1; nil for a (near-)zero vector.
(defun cal:unit (v / l)
  (setq v (cal:2d v)
        l (cal:vlen v))
  (if (> l 1e-12) (cal:v* v (/ 1.0 l))))

;;; Length-preserving (N-element) variants, for the tools whose vectors
;;; carry their Z: the check family's overlap machinery and AutoDim.
;;; mapcar is strict -- both arguments must be the same length.

;; From cchk:unit (covercheck.lsp:638; dchk:/lfc: byte-identical).
(defun cal:unitn (v / l)
  (setq l (distance '(0.0 0.0 0.0) v))
  (if (> l 1e-12)
    (mapcar '(lambda (x) (/ x l)) v)))

(defun cal:dotn (p q) (apply '+ (mapcar '* p q)))          ; ad:dot
(defun cal:midn (p1 p2)                                    ; ad:mid
  (mapcar '(lambda (a b) (* 0.5 (+ a b))) p1 p2))

;; signed distance of p along the axis through a with unit dir u
;; (cchk:proj-param, covercheck.lsp:644)
(defun cal:proj-param (p a u)
  (apply '+ (mapcar '* (mapcar '- p a) u)))

;; the point at parameter s on that axis (cchk:axis-pt)
(defun cal:axis-pt (a u s)
  (mapcar '+ a (mapcar '(lambda (x) (* x s)) u)))

;; distance from p to the infinite line through a with unit dir u
;; (cchk:pt-line-dist)
(defun cal:pt-line-dist (p a u / s)
  (setq s (cal:proj-param p a u))
  (distance p (cal:axis-pt a u s)))

;;; -------------------- angles ------------------------------------------

;; normalize an angle into [0, 2pi).  (Eight tools agree on this range;
;; acady-norm-ang folds into (-pi, pi] instead and keeps its own name.)
(defun cal:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

;; smallest signed angular difference (to - from), in (-pi, pi]
;; (pf:signed-dang, abhd.lsp:375)
(defun cal:signed-dang (from to / d)
  (setq d (cal:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

;; distance between two folded directions, in [0, pi/2]
;; (cchk:ang-diff, covercheck.lsp:844)
(defun cal:ang-diff (a b / d)
  (setq d (abs (- a b)))
  (min d (- pi d)))

;;; -------------------- circle / arc geometry ---------------------------

;; center of the circle through three points (plan view, z taken from
;; p1); nil when the points are collinear.  (cchk:circumcenter,
;; covercheck.lsp:580; the check family's 4-way-identical form.  abhd
;; and lhd keep their 2-element, looser-gated pf:/lh:circumcenter.)
(defun cal:circumcenter (p1 p2 p3 / ax ay bx by cx cy d)
  (setq ax (car p1) ay (cadr p1)
        bx (car p2) by (cadr p2)
        cx (car p3) cy (cadr p3)
        d  (* 2.0 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (if (> (abs d) 1e-12)
    (list (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                (* (+ (* bx bx) (* by by)) (- cy ay))
                (* (+ (* cx cx) (* cy cy)) (- ay by)))
             d)
          (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                (* (+ (* bx bx) (* by by)) (- ax cx))
                (* (+ (* cx cx) (* cy cy)) (- bx ax)))
             d)
          (caddr p1))))

;;; -------------------- bounding boxes ----------------------------------
;;; Nested-point form ((minx miny minz) (maxx maxy maxz)) throughout.
;;; abhd/lhd keep their flat 4-tuple point-list pf:/lh:bbox -- their
;;; label layout reads it with caddr/cadddr.

;; one entity, or nil when it has no box (cchk:bbox, covercheck.lsp:421)
(defun cal:bbox-ent (ent / obj ll ur)
  (setq obj (vlax-ename->vla-object ent))
  (if (not (vl-catch-all-error-p
             (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
    (list (vlax-safearray->list ll) (vlax-safearray->list ur))))

;; a whole selection set, nil-safe (ad:ssbox, AutoDim.lsp:191)
(defun cal:bbox-ss (ss / i obj ll ur mn mx)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq obj (vlax-ename->vla-object (ssname ss i))
            i   (1+ i))
      (if (not (vl-catch-all-error-p
                 (vl-catch-all-apply 'vla-getboundingbox (list obj 'll 'ur))))
        (progn
          (setq ll (vlax-safearray->list ll)
                ur (vlax-safearray->list ur)
                mn (if mn (mapcar 'min mn ll) ll)
                mx (if mx (mapcar 'max mx ur) ur))))))
  (if mn (list mn mx)))

;;; -------------------- lists -------------------------------------------

;; the list from index K on (pf:nthcdr, abhd.lsp:357)
(defun cal:nthcdr (k lst)
  (while (> k 0) (setq lst (cdr lst) k (1- k)))
  lst)

;; COUNT elements of LST starting at index K (pf:sublist).  Running
;; past the end conses nils, exactly as the original does.
(defun cal:sublist (lst k count / out)
  (setq lst (cal:nthcdr k lst))
  (while (> count 0)
    (setq out   (cons (car lst) out)
          lst   (cdr lst)
          count (1- count)))
  (reverse out))

;; drop every point within EPS of a kept one, order preserved
;; (pf:dedupe, abhd.lsp:826, with the epsilon as an argument.
;; perp_points keeps its own consecutive-only dedupe -- different
;; algorithm, different results.)
(defun cal:dedupe (pts eps / out q p dup)
  (foreach q pts
    (setq dup nil)
    (foreach p out
      (if (< (cal:dist p q) eps) (setq dup T)))
    (if (not dup) (setq out (cons q out))))
  (reverse out))

;;; -------------------- numbers -----------------------------------------

;; smallest integer >= X (X non-negative)  (pf:ceil, abhd.lsp:352)
(defun cal:ceil (x / f)
  (setq f (fix x))
  (if (> x f) (1+ f) f))

;; Tangent with the angle clamped just short of +/-90 degrees, so a
;; degenerate half-turn bulge yields a huge but finite number instead
;; of dividing by zero.  (pf:tan, abhd.lsp:347.)
(defun cal:tan (x)
  (cond ((> x  1.5697) (setq x  1.5697))    ; 89.94 deg
        ((< x -1.5697) (setq x -1.5697)))
  (/ (sin x) (cos x)))

;;; -------------------- strings -----------------------------------------

;; Trim leading / trailing blanks (spaces, tabs); nil-safe.
;; (abcdef:trim, abcdef.lsp:50 -- the strongest of the four string
;; trims.  chk:trim / lin:trim / stock:trim are different functions
;; and keep their own names.)
(defun cal:trim (s / i n)
  (if (null s) (setq s ""))
  (setq n (strlen s) i 1)
  (while (and (<= i n) (member (substr s i 1) '(" " "\t")))
    (setq i (1+ i)))
  (setq s (substr s i))
  (setq n (strlen s))
  (while (and (> n 0) (member (substr s n 1) '(" " "\t")))
    (setq s (substr s 1 (1- n)) n (1- n)))
  s)

;; Pad S with spaces to width W (pf:pad, five byte-identical copies)
(defun cal:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; zero-pad an integer to two digits (cchk:pad2)
(defun cal:zeropad2 (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

;; "YYYY-MM-DD HH:MM" -- CDATE decoded arithmetically so DIMZIN (which
;; trims rtos output) cannot mangle it (cchk:datestr, three-way
;; byte-identical)
(defun cal:datestr (/ d dd tt)
  (setq d  (getvar "CDATE")
        dd (fix d)
        tt (- d dd))
  (strcat (itoa (fix (/ dd 10000))) "-"
          (cal:zeropad2 (rem (fix (/ dd 100)) 100)) "-"
          (cal:zeropad2 (rem dd 100)) " "
          (cal:zeropad2 (fix (+ (* tt 100) 1e-6))) ":"
          (cal:zeropad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))))

;;; -------------------- the chart forms ---------------------------------
;;;  LAZFORM, LAZSPA and LAZSTEP draw their charts into a DCL IMAGE
;;;  TILE, which can take line segments and nothing else -- no raster,
;;;  no text, not even a font.  So the letters are stroked out of
;;;  segments, the arcs are polygonised, and all three carried a
;;;  byte-identical copy of the machinery for it: the font table, its
;;;  metrics, the tile palette and seven drawing helpers, about 130
;;;  lines apiece.
;;;
;;;  They still do, in lisp/ -- a standalone file has to load alone --
;;;  but the grouped build takes them from here instead, through the
;;;  swap map in tools/mirror_shared.py.  That map is also the written
;;;  statement that the three copies ARE the same code: regenerate a
;;;  twin whose local copy has drifted and --check fails.
;;;
;;;  Named img* because that is exactly where they draw.  cal:text
;;;  already draws an AutoCAD TEXT entity and means something else
;;;  entirely, which is the collision this prefix exists to avoid.

;; The stroke font.  One entry per character: the glyph as a list of
;; polylines, each a flat list of x y x y ... in TENTHS of a font unit,
;; on a cell 4 wide and 6 tall with y running DOWN the way image-tile
;; pixels do.  Integers, so nothing here depends on float formatting.
(setq cal:*imgfont* '(
    ("A" (0 60 20 0 40 60) (8 40 32 40))
    ("B" (0 0 0 60) (0 0 30 0 40 10 40 20 30 30 0 30) (30 30 40 40 40 50 30 60 0 60))
    ("C" (40 10 30 0 10 0 0 10 0 50 10 60 30 60 40 50))
    ("D" (0 0 0 60) (0 0 30 0 40 10 40 50 30 60 0 60))
    ("E" (40 0 0 0 0 60 40 60) (0 30 30 30))
    ("F" (40 0 0 0 0 60) (0 30 30 30))
    ("G" (40 10 30 0 10 0 0 10 0 50 10 60 30 60 40 50 40 30 20 30))
    ("H" (0 0 0 60) (40 0 40 60) (0 30 40 30))
    ("I" (10 0 30 0) (20 0 20 60) (10 60 30 60))
    ("J" (30 0 30 50 20 60 10 60 0 50))
    ("K" (0 0 0 60) (40 0 0 35) (14 25 40 60))
    ("L" (0 0 0 60 40 60))
    ("M" (0 60 0 0 20 30 40 0 40 60))
    ("N" (0 60 0 0 40 60 40 0))
    ("O" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0))
    ("P" (0 60 0 0 30 0 40 10 40 20 30 30 0 30))
    ("Q" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0) (25 45 40 60))
    ("R" (0 60 0 0 30 0 40 10 40 20 30 30 0 30) (20 30 40 60))
    ("S" (40 10 30 0 10 0 0 10 0 20 10 30 30 30 40 40 40 50 30 60 10 60 0 50))
    ("T" (0 0 40 0) (20 0 20 60))
    ("U" (0 0 0 50 10 60 30 60 40 50 40 0))
    ("V" (0 0 20 60 40 0))
    ("W" (0 0 10 60 20 20 30 60 40 0))
    ("X" (0 0 40 60) (40 0 0 60))
    ("Y" (0 0 20 30 40 0) (20 30 20 60))
    ("Z" (0 0 40 0 0 60 40 60))
    ("0" (10 0 30 0 40 10 40 50 30 60 10 60 0 50 0 10 10 0) (5 55 35 5))
    ("1" (10 10 20 0 20 60) (10 60 30 60))
    ("2" (0 10 10 0 30 0 40 10 40 20 0 60 40 60))
    ("3" (0 0 40 0 20 25) (20 25 40 35 40 50 30 60 10 60 0 50))
    ("4" (30 60 30 0 0 40 40 40))
    ("5" (40 0 0 0 0 25 30 25 40 35 40 50 30 60 10 60 0 50))
    ("6" (40 0 20 0 0 20 0 50 10 60 30 60 40 50 40 40 30 30 10 30 0 40))
    ("7" (0 0 40 0 15 60))
    ("8" (10 30 0 20 0 10 10 0 30 0 40 10 40 20 30 30 10 30 0 40 0 50 10 60 30 60 40 50 40 40 30 30))
    ("9" (0 60 20 60 40 40 40 10 30 0 10 0 0 10 0 20 10 30 30 30 40 20))
    ("." (17 54 23 54 23 60 17 60 17 54))
    ("-" (5 30 35 30))
    ("'" (20 0 20 16))
    ("\"" (13 0 13 16) (27 0 27 16))
    ("/" (0 60 40 0))
    (":" (20 16 20 22) (20 40 20 46))
    ("%" (0 60 40 0) (5 5 12 5) (28 55 35 55))
    ("#" (10 0 6 60) (30 0 26 60) (0 20 40 20) (0 40 40 40))
    (" ")
))

;; the cell, and how far the pen moves between characters
(setq cal:*imgfont-w* 40)
(setq cal:*imgfont-h* 60)
(setq cal:*imgfont-adv* 56)

;; The tile palette.  -16 and -15 are the dialog's own foreground and
;; background, so the chart follows the user's AutoCAD theme rather
;; than fighting it -- and the two that are drawn BESIDE them say
;; 'auto, which asks cal:ink the same question (a dark grey dimension
;; arrow and a dark blue focus box are the two things on this tile that
;; a dark dialog swallows, and -16 adapting while they do not is what
;; half-themed looks like).  Orange is the one that reads either way,
;; so it is the one still written as a number.
(setq cal:*imgcol-line* -16)
(setq cal:*imgcol-back* -15)
(setq cal:*imgcol-dim* 'auto)
(setq cal:*imgcol-val* 30)
(setq cal:*imgcol-hi* 'auto)
;; a letter whose box is still owed -- drawn in this and struck twice,
;; which is what a stroke font has instead of a bold weight
(setq cal:*imgcol-miss* 1)

;; one character's polylines, or nil
(defun cal:imgglyph (ch / p)
  (if (setq p (assoc (strcase ch) cal:*imgfont*)) (cdr p)))

;; how wide / tall a string is at scale SC, in pixels
(defun cal:imgtextw (s sc)
  (if (= s "") 0
      (fix (/ (* (- (* (strlen s) cal:*imgfont-adv*)
                    (- cal:*imgfont-adv* cal:*imgfont-w*))
                 sc)
              100.0))))
(defun cal:imgtexth (sc) (fix (/ (* cal:*imgfont-h* sc) 100.0)))

;; a flat list of PIXEL coordinates, drawn as segments
(defun cal:imgpline (flat col)
  (while (and flat (cddr flat))
    (vector_image (car flat) (cadr flat) (caddr flat) (cadddr flat) col)
    (setq flat (cddr flat))))

;; Stroke a string at (X, Y) in pixels, left edge and top, at scale SC.
;; Returns the pen position after it, so callers can run text on.
(defun cal:imgtext (s x y sc col / i ch pen poly out n)
  (setq i 1 pen x)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (foreach poly (cal:imgglyph ch)
      (setq out nil n poly)
      (while n
        (setq out (cons (+ y (fix (/ (* (cadr n) sc) 100.0)))
                        (cons (+ pen (fix (/ (* (car n) sc) 100.0))) out))
              n (cddr n)))
      (cal:imgpline (reverse out) col))
    (setq pen (+ pen (fix (/ (* cal:*imgfont-adv* sc) 100.0)))
          i (1+ i)))
  pen)

;; An arc written ("A" cx cy rx ry from to) -- centre and both radii in
;; per-mille, angles in degrees with 0 due east and counting
;; anticlockwise ON SCREEN -- polygonised into a flat point list.  Two
;; radii rather than one because these charts want half of an ellipse
;; as often as half of a circle.  Image-tile y runs DOWN, which is the
;; minus on the y term and nowhere else.
(defun cal:imgarcpts (a / cx cy rx ry f to n i ang out)
  (setq cx (nth 1 a) cy (nth 2 a) rx (nth 3 a) ry (nth 4 a)
        f (nth 5 a) to (nth 6 a))
  (setq n (fix (/ (abs (- to f)) 6.0)))
  (if (< n 4) (setq n 4))
  (setq i 0)
  (while (<= i n)
    ;; NB: the angle local is not called t -- a local of that name would
    ;; shadow TRUE for the length of the call
    (setq ang (/ (* pi (+ f (/ (* (- to f) i) (float n)))) 180.0)
          out (cons (fix (- cy (* ry (sin ang))))
                    (cons (fix (+ cx (* rx (cos ang)))) out))
          i (1+ i)))
  (reverse out))

;; an outline element -- a polyline already, or an arc -- as points
(defun cal:imgflatten (e)
  (if (= (type (car e)) 'STR) (cal:imgarcpts e) e))

;;  STANDARDS.md's three-state form contract, decided here:
;;
;;    box left empty   the key is not sent at all -> the routine asks
;;    NA typed in it   (key . nil) is sent        -> the routine takes NA
;;    a measurement    (key . 84.0) is sent       -> taken, no prompt
;;
;;  Anything that is neither NA nor a distance AutoCAD can read comes
;;  back SKIP and is treated as an empty box: a typo must leave the
;;  routine asking rather than quietly feeding it a nil that means
;;  something else entirely.  distof reads the architectural spellings,
;;  so 25'6" and 25'-6-1/2" arrive as the numbers they look like.
(defun cal:formanswer (v / n)
  (cond
    ((or (null v) (= v "")) 'SKIP)
    ((= (strcase (cal:trim v)) "NA") nil)
    ((setq n (distof (cal:trim v) 4)) n)
    ((setq n (distof (cal:trim v) 2)) n)
    (t 'SKIP)))

;;  RECALLING THE LAST SHEET.  A form's answers are (key . "typed")
;;  pairs, and the registry stores strings -- so a sheet is remembered
;;  as one string, "key=typed;key=typed", and read back the same way.
;;
;;  A value carrying ";" or "=" would come back as two pairs or as the
;;  wrong pair, so cal:kvpack DROPS one rather than writing a record it
;;  cannot read.  Nothing a box legitimately holds contains either --
;;  a measurement is digits, feet and inch marks, dashes and slashes,
;;  and NA is two letters -- so this is a guard against the impossible,
;;  not a limitation anyone will meet.  Silently losing one entry beats
;;  a whole sheet that reads back scrambled.

(defun cal:kvsplit (s sep / i n c cur out)
  (setq i 1 n (strlen s) cur "")
  (while (<= i n)
    (setq c (substr s i 1))
    (if (= c sep)
      (progn (setq out (cons cur out)) (setq cur ""))
      (setq cur (strcat cur c)))
    (setq i (1+ i)))
  (reverse (cons cur out)))

(defun cal:kvpack (alist / out p k v)
  (setq out "")
  (foreach p alist
    (setq k (car p) v (cdr p))
    (if (and (= (type v) 'STR) (/= v "")
             (not (cal:kvhas k ";")) (not (cal:kvhas k "="))
             (not (cal:kvhas v ";")) (not (cal:kvhas v "=")))
      (setq out (strcat out (if (= out "") "" ";") k "=" v))))
  out)

;; Is NEEDLE anywhere in HAY?  A written-out search, so a needle of "="
;; or ";" is looked for rather than obeyed by some pattern reader.
(defun cal:kvhas (hay ned / i n m)
  (setq n (strlen hay) m (strlen ned) i 1)
  (cond
    ((> m n) nil)
    (t (while (and (<= i (1+ (- n m))) (/= (substr hay i m) ned))
         (setq i (1+ i)))
       (<= i (1+ (- n m))))))

(defun cal:kvunpack (s / out p bits)
  (if (and s (= (type s) 'STR) (/= s ""))
    (foreach p (cal:kvsplit s ";")
      (setq bits (cal:kvsplit p "="))
      (if (and (cdr bits) (/= (car bits) ""))
        (setq out (cons (cons (car bits) (cadr bits)) out)))))
  (reverse out))

;; "1 box" / "5 boxes" -- a line that says "all 1 boxes" reads as a bug
;; in the form, whatever it is actually reporting.
(defun cal:plural (n one many)
  (strcat (itoa n) " " (if (= n 1) one many)))

;; "A", "A and B", "A, B and C" -- or, with LAST nil, commas
;; throughout, which is what a list with "and 2 more" hung off the end
;; of it needs: "A, B and C and 2 more" reads as two lists rather than
;; one.
(defun cal:andjoin (l last / n i out k)
  (setq n (length l) i 0 out "")
  (foreach k l
    (setq i (1+ i)
          out (cond ((= i 1) k)
                    ((and last (= i n)) (strcat out " and " k))
                    (t (strcat out ", " k)))))
  out)

;;; -------------------- entity creation ---------------------------------

;; plain TEXT at pt (wc:text, wcalst.lsp:396).  POOL/SPA keep their own
;; text helpers -- theirs run the point through the insertion-base
;; offset first.
(defun cal:text (pt hgt str lay)
  (entmake
    (list '(0 . "TEXT") (cons 8 lay)
          (list 10 (car pt) (cadr pt) 0.0)
          (cons 40 hgt) (cons 1 str))))

;; entmake an MTEXT, splitting into 250-char DXF chunks; returns the
;; new ename, or nil.  (cchk:mtext body, covercheck.lsp:541, minus the
;; per-tool xdata tag -- the check tools tag the returned ename
;; themselves.)
(defun cal:mtext (ins hgt wid str lay / dxf)
  (setq dxf (list '(0 . "MTEXT")
                  '(100 . "AcDbEntity")
                  (cons 8 lay)
                  '(100 . "AcDbMText")
                  (cons 10 ins)
                  (cons 40 hgt)
                  (cons 41 wid)
                  '(71 . 1)))                  ; attachment: top-left
  (while (> (strlen str) 250)
    (setq dxf (append dxf (list (cons 3 (substr str 1 250))))
          str (substr str 251)))
  (if (entmake (append dxf (list (cons 1 str))))
    (entlast)))

;;; -------------------- the length ruler --------------------------------
;;;  DIMSTAMP's ruler, as a helper any LENGTH prompt can stand beside.
;;;  Once a first length has been given, the prompt draws the eighths
;;;  of an inch for a whole inch either side of the last one down a
;;;  strip near the right edge of the view, graded like a tape with the
;;;  last length ringed in the middle -- and one prompt then takes a
;;;  click on a row (that row's value), a typed measurement in any
;;;  spelling (44, 44.5, 44-1/2, 4'4.5, 4'-4-1/2"), Enter, a keyword,
;;;  or a click on empty space as the first of two points to measure
;;;  between, which is what getdist always offered.  A run of
;;;  near-equal lengths is clicked rather than typed over and over.
;;;  The fractions are DASHED because the prompt is a getpoint, where
;;;  the spacebar is Enter: 44 1/2 is two answers there, 44 to this
;;;  question and 1/2 to the next, so a bare fraction is refused
;;;  rather than taken as a length of its own.
;;;
;;;  PERPPTS, CPERPPTS, PERPMARK, CORNERSTP, HEMISTEP and NORMIESTEP
;;;  ask their lengths through it.  Each carries this block under its
;;;  own prefix so the standalone file loads alone, the grouped build
;;;  swaps the copy for the library's, and tests/test_ruler_copies.py
;;;  holds every copy to this one text.  DIMSTAMP keeps its own ruler:
;;;  its current row is drawn as the stamp it would make, on the
;;;  stamp's layer in the stamp's style, which is a different thing
;;;  from a row of nearby lengths.
;;;
;;;  A ruler comes in two families, and the prompt picks which.
;;;
;;;  The TAPE is the one above: the eighths of an inch for a whole inch
;;;  either side of the LAST answer, which is what a run of near-equal
;;;  numbers wants.  It needs a last answer to be built round, so the
;;;  first prompt of a run stands alone.
;;;
;;;  The LADDER is the other: a fixed (LO HI STEP) of the values that
;;;  prompt is actually answered with, every one of them offered from
;;;  the first prompt on.  A corner radius is 3" to 2'-0" by 3" and a
;;;  tape of eighths round nothing helps nobody -- 3, 6, 9, 12 is the
;;;  whole vocabulary, and a drafter picks out of it rather than types
;;;  into it.  Its rows are graded off the VALUE, not off a distance
;;;  from the current row: the foot marks are the deep ones and the
;;;  half-foot next, which is where a tape's deep marks are too.  A
;;;  ladder still takes a typed measurement that is not on it, and the
;;;  answer is then ringed among the rungs as the current row.
;;;
;;;  Nothing in here reads a knob.  A tool hands its knobs in as one
;;;  STYLE list and keeps the ruler between prompts as one STATE list:
;;;    STYLE  (COLOR CURRENT-COLOR SCREEN-X ROW-FRAC TXT-FRAC TICK-FRAC
;;;            RING-FRAC REACH) -- a caller's tunables block says what
;;;            each one moves
;;;    STATE  (LEN FEET ENTS BOX ROWS LAY STYLE SAID LADDER) -- the
;;;            length the ruler stands round (nil = none), the family it
;;;            is labelled in (T = feet), what is drawn, its layer, the
;;;            style, whether the one-line hint has been said, and the
;;;            ladder it is standing on (nil = a tape)
;;;  Values are INCHES, the unit this shop draws in, and the ruler
;;;  steps in eighths of one, which is what a tape reads in.

;; T when C is 0-9.
(defun cal:len-digit-p (c)
  (and (>= (ascii c) 48) (<= (ascii c) 57)))

;; T when S reads as a plain decimal number: digits, at most one dot,
;; at least one digit, nothing else.
(defun cal:len-num-p (s / i n c dots digits ok)
  (setq n (strlen s) i 1 dots 0 digits 0 ok T)
  (while (and ok (<= i n))
    (setq c (substr s i 1))
    (cond
      ((cal:len-digit-p c) (setq digits (1+ digits)))
      ((= c ".") (setq dots (1+ dots)))
      (T (setq ok nil)))
    (setq i (1+ i)))
  (and ok (> digits 0) (< dots 2)))

;; S cut on spaces, tabs and dashes, empty pieces dropped -- the
;; separators an inches part is written with, so "4 1/2" and "4-1/2"
;; come apart the same way.  It cuts a keyword list the same way.
(defun cal:len-split (s / i n c buf out)
  (setq n (strlen s) i 1 buf "" out nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (if (or (= c " ") (= c "\t") (= c "-"))
      (progn
        (if (/= buf "") (setq out (cons buf out)))
        (setq buf ""))
      (setq buf (strcat buf c)))
    (setq i (1+ i)))
  (if (/= buf "") (setq out (cons buf out)))
  (reverse out))

;; One token of an inches part -- a decimal number, or a fraction N/D
;; -- as a number of inches.  nil when it is neither.
(defun cal:len-token (tok / slash n d)
  (if (setq slash (vl-string-search "/" tok))
    (progn
      (setq n (substr tok 1 slash)
            d (substr tok (+ slash 2)))
      (if (and (cal:len-num-p n) (cal:len-num-p d) (/= (atof d) 0.0))
        (/ (atof n) (atof d))))
    (if (cal:len-num-p tok) (atof tok))))

;; The inches part of a measurement as a number of inches: every token
;; added up, so "4", "4.5", "4 1/2", "4-1/2" and "1/2" all read.  An
;; empty part is 0, which is how 4' reads as 4'-0".  nil when any
;; token is neither a number nor a fraction.
(defun cal:len-inches (s / toks total v tk)
  (setq toks (cal:len-split s) total 0.0)
  (foreach tk toks
    (if (and total (setq v (cal:len-token tk)))
      (setq total (+ total v))
      (setq total nil)))
  total)

;; Read a typed measurement as (INCHES HASFEET): the length in inches,
;; exactly as typed and NOT rounded, and T when feet were spelled --
;; carried through so the ruler is labelled in the family the length
;; was typed in.  Lenient, the way DIMSTAMP reads: the inch mark is
;; optional and may be two apostrophes, the dash after the feet mark is
;; optional, inches may be decimal, and a fraction may be spaced or
;; dashed -- 44, 44.5, 44 1/2, 4'4.5 and 4'-4 1/2" all read.  nil when
;; the text is not a measurement at all.
(defun cal:parse-len (s / n apos feetstr rest hasfeet feet inch)
  (setq s (vl-string-trim " \t" s)
        n (strlen s))
  (cond
    ((and (>= n 2) (= (substr s (1- n) 2) "''"))
     (setq s (substr s 1 (- n 2))))
    ((and (>= n 1) (= (substr s n 1) "\""))
     (setq s (substr s 1 (1- n)))))
  (setq s (vl-string-trim " \t" s) hasfeet nil feet 0.0)
  (if (setq apos (vl-string-search "'" s))
    (progn
      (setq feetstr (vl-string-trim " \t" (substr s 1 apos))
            rest    (vl-string-trim " \t-" (substr s (+ apos 2))))
      (if (cal:len-num-p feetstr)
        (setq feet (atof feetstr) hasfeet T)
        (setq rest nil)))
    (setq rest (vl-string-trim " \t" s)))
  (setq inch (if rest (cal:len-inches rest)))
  (if (and inch (or hasfeet (/= rest "")))
    (list (+ (* feet 12.0) inch) hasfeet)))

;; INCHES to the nearest eighth, as an integer count of eighths -- the
;; unit the ruler is built in.
(defun cal:len-eighths (inches)
  (fix (+ 0.5 (* 8.0 inches))))

;; Spell TOTAL-EIGHTHS out as text, in the HASFEET family.  STACKED nil
;; is the PLAIN spelling ("44 1/2\"", what the command line says);
;; STACKED T is the DRAWN one, the fraction stacked through AutoCAD's
;; \S code at the size of the text around it, for a ruler label and
;; nothing else.
(defun cal:spell-len (total-eighths hasfeet stacked / feet remain whole f8
                         g num den fr)
  (if hasfeet
    (setq feet   (/ total-eighths 96)
          remain (- total-eighths (* feet 96)))
    (setq feet 0 remain total-eighths))
  (setq whole (/ remain 8)
        f8    (- remain (* whole 8))
        num   0
        den   1)
  (if (/= f8 0)
    (progn
      (setq g (gcd f8 8))
      (setq num (/ f8 g) den (/ 8 g))))
  (setq fr (cond
             ((= num 0) "")
             ((null stacked) (strcat " " (itoa num) "/" (itoa den)))
             (T (strcat "{\\H1.0000x;\\S" (itoa num) "/" (itoa den) ";}"))))
  (strcat (if (and stacked (/= num 0)) "\\A1;" "")
          (if hasfeet (strcat (itoa feet) "'-") "")
          (itoa whole) fr "\""))

;; What to say when something typed is not a length at all.  The
;; examples are the lazy spellings on purpose: the ones worth showing
;; are the ones that save keystrokes.  A fraction is shown DASHED, never
;; spaced: at a click-or-type prompt the spacebar is Enter, so 44 1/2
;; entered 44 and handed the 1/2 to the next question as half an inch.
(defun cal:len-unread (v)
  (princ (strcat "\n\"" v "\" is not a length - try 44, 44.5, 44-1/2,"
                 " 4'4.5 or 4'-4-1/2\".")))

;; The RULER TIER an offset of OFFSET eighths from the current value
;; falls in -- 'jump for a whole inch, 'half/'quarter/'eighth for the
;; finer steps, biggest to smallest; a row's tick length and text
;; height read off it.
(defun cal:ruler-tier (offset / a m)
  (setq a (abs offset) m (rem a 8))
  (cond
    ((= m 0) 'jump)
    ((= m 4) 'half)
    ((member m '(2 6)) 'quarter)
    (T 'eighth)))

;; The nearby values to offer, as (EIGHTHS TIER) pairs: every eighth
;; for a whole inch either side, and with feet in play the 2" and 3"
;; jumps beyond that as well.  A row at or below zero is dropped.
;; Unsorted -- the ruler sorts once it also has the current row.
(defun cal:ruler-rows (total-eighths hasfeet / out i off)
  (setq out nil i 1)
  (while (<= i 8)
    (setq out (cons (list (- total-eighths i) (cal:ruler-tier i)) out))
    (setq out (cons (list (+ total-eighths i) (cal:ruler-tier i)) out))
    (setq i (1+ i)))
  (if hasfeet
    (progn
      (setq i 2)
      (while (<= i 3)
        (setq off (* i 8))
        (setq out (cons (list (- total-eighths off) 'jump) out))
        (setq out (cons (list (+ total-eighths off) 'jump) out))
        (setq i (1+ i)))))
  (vl-remove-if '(lambda (pr) (<= (car pr) 0)) out))

;; The RULER TIER a LADDER rung falls in, read off the value itself
;; rather than off a distance from the current row: a whole foot is the
;; deepest mark, a half foot the next, a quarter foot after that, and
;; everything else is a plain rung.  That is where a tape's deep marks
;; are, so a ladder of radii reads as a ruler and not as a list.
(defun cal:ladder-tier (eighths)
  (cond
    ((= 0 (rem eighths 96)) 'jump)        ; a whole foot
    ((= 0 (rem eighths 48)) 'half)        ; a half foot
    ((= 0 (rem eighths 24)) 'quarter)     ; a quarter foot
    (T 'eighth)))

;; The rungs of LADDER, given as (LO HI STEP) in inches: every step from
;; LO to HI, as the same (EIGHTHS TIER) pairs a tape's rows are.  A rung
;; at or below zero is dropped, as a tape's rows are.
;;
;; A ladder is a KNOB, and a knob is whatever a drafter left in it -- a
;; string, two numbers where three were wanted, a step of zero.  So the
;; shape is read here rather than trusted: anything that is not three
;; numbers with a positive step has no rungs, and cal:ruler-show reads
;; that as no ladder.  A settings line typed wrong costs the ruler, not
;; the command.  Unsorted -- the ruler sorts once it also has the
;; current row.
(defun cal:ladder-rows (ladder / lo hi step v out)
  (setq out nil)
  (if (and (= (type ladder) 'LIST) (= 3 (length ladder))
           (numberp (car ladder)) (numberp (cadr ladder))
           (numberp (caddr ladder)) (> (caddr ladder) 0.0))
    (progn
      (setq lo   (cal:len-eighths (car ladder))
            hi   (cal:len-eighths (cadr ladder))
            step (cal:len-eighths (caddr ladder))
            v    lo)
      (if (> step 0)
        (while (<= v hi)
          (if (> v 0) (setq out (cons (list v (cal:ladder-tier v)) out)))
          (setq v (+ v step))))))
  out)

;; Ascending by value -- the comparator the ruler sorts rows with.
(defun cal:ruler-val-lt (a b) (< (car a) (car b)))

;; What the screen is showing, as (LEFT BOTTOM WIDTH HEIGHT) in drawing
;; units: VIEWSIZE is the view's height and SCREENSIZE its aspect.
;; This is what pins the ruler to the same strip of screen at any zoom.
(defun cal:ruler-view ( / ctr vh ss aspect vw)
  (setq ctr (getvar "VIEWCTR")
        vh  (getvar "VIEWSIZE")
        ss  (getvar "SCREENSIZE"))
  (setq aspect (if (and ss (listp ss) (numberp (car ss))
                        (numberp (cadr ss)) (> (cadr ss) 0))
                 (/ (float (car ss)) (float (cadr ss)))
                 1.6))                    ; no viewport to measure
  (setq vw (* vh aspect))
  (list (- (car ctr) (/ vw 2.0)) (- (cadr ctr) (/ vh 2.0)) vw vh))

;; Which way a row reaches from a spine pinned SCREEN-X of the way
;; across the view: always toward the middle, so a ruler pinned near an
;; edge is never drawn past it.  1.0 toward higher x, -1.0 lower.
(defun cal:ruler-dir (screen-x)
  (if (> screen-x 0.5) -1.0 1.0))

;; Label height for a row of this TIER, against a row spacing of GAP,
;; the biggest label being FRAC of the spacing.
(defun cal:ruler-hgt (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.8))
    ((eq tier 'quarter) (* base 0.65))
    ((eq tier 'eighth) (* base 0.5))
    (T base)))                     ; 'current and 'jump

;; Tick length for a row of this TIER, same measure.
(defun cal:ruler-tick (tier gap frac / base)
  (setq base (* gap frac))
  (cond
    ((eq tier 'half) (* base 0.75))
    ((eq tier 'quarter) (* base 0.55))
    ((eq tier 'eighth) (* base 0.35))
    (T base)))                     ; 'current and 'jump

;; The ruler is laid out in the UCS -- VIEWCTR is a UCS point, and so
;; is every click the hit test reads -- and entmake takes the WORLD.
;; So each point goes through trans on its way into the drawing: under
;; a UCS whose origin a drafter has moved to the pool's corner, the
;; ruler was drawn that far away from the view it was measured off,
;; out of sight, while the prompt still answered clicks on the empty
;; strip where it should have been.

;; A ruler stroke from (X1 Y1) to (X2 Y2) on LAY in ACI colour COL.
(defun cal:ruler-line (x1 y1 x2 y2 lay col)
  (entmakex (list '(0 . "LINE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbLine")
                  (cons 10 (trans (list x1 y1 0.0) 1 0))
                  (cons 11 (trans (list x2 y2 0.0) 1 0)))))

;; The ring that marks the current row.
(defun cal:ruler-ring (x y r lay col)
  (entmakex (list '(0 . "CIRCLE") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbCircle")
                  (cons 10 (trans (list x y 0.0) 1 0)) (cons 40 r))))

;; A ruler label: one unwrapped MTEXT of height HGT at PT in the
;; current text style, attached top left (ATT 1) or top right (3) so
;; it grows away from the spine, and running along the UCS X axis
;; (group 11, a WORLD direction) so it reads level in a plan view of
;; that UCS.
(defun cal:ruler-label (pt hgt str lay col att)
  (entmakex (list '(0 . "MTEXT") '(100 . "AcDbEntity") (cons 8 lay)
                  (cons 62 col) '(100 . "AcDbMText")
                  (cons 10 (trans (list (car pt) (cadr pt) 0.0) 1 0))
                  (cons 40 hgt) '(41 . 0.0) (cons 71 att) '(72 . 5)
                  (cons 1 str) (cons 11 (trans '(1.0 0.0 0.0) 1 0 T))
                  '(73 . 1) '(44 . 1.0))))

;; Draw the ruler down its strip of the current view round
;; TOTAL-EIGHTHS, in the HASFEET family, on layer LAY, sized and
;; coloured by STYLE: one row per suggestion plus the ringed current
;; row among them, the whole thing centred vertically in the view.
;; LADDER nil is the tape, the eighths either side of TOTAL-EIGHTHS;
;; a (LO HI STEP) is the ladder, its rungs instead.  TOTAL-EIGHTHS may
;; be nil ON A LADDER and only there -- a ladder is the values a prompt
;; is answered with and stands whether or not one has been given yet,
;; where a tape is built round the last answer and has nothing to be
;; without it.  A rung equal to the current row is dropped, so the row
;; is ringed once rather than drawn twice.
;; Returns (ENTS BOX ROWS): the entities drawn, BOX as (XMIN XMAX YTOL)
;; for the hit test, and ROWS as (EIGHTHS ROW-Y) pairs.
(defun cal:draw-ruler (total-eighths hasfeet lay style ladder / rows n i row
                          val tier y hgt tl spx ents result view vx vy vw vh
                          gap base rcol dir far near)
  (setq rows (if ladder
               (vl-remove-if '(lambda (pr) (equal (car pr) total-eighths))
                             (cal:ladder-rows ladder))
               (cal:ruler-rows total-eighths hasfeet)))
  (if total-eighths
    (setq rows (cons (list total-eighths 'current) rows)))
  (setq rows (vl-sort rows 'cal:ruler-val-lt))
  (setq view (cal:ruler-view)
        vx   (car view)  vy (cadr view)
        vw   (caddr view) vh (cadddr view))
  (setq n    (length rows)
        gap  (* vh (nth 3 style))
        spx  (+ vx (* vw (nth 2 style)))
        dir  (cal:ruler-dir (nth 2 style))   ; rows run inward
        base (- (+ vy (/ vh 2.0)) (* gap (/ (- n 1) 2.0)))
        i    0
        ents nil
        result nil)
  (foreach row rows
    (setq val  (car row) tier (cadr row))
    (setq y    (+ base (* i gap))
          hgt  (cal:ruler-hgt tier gap (nth 4 style))
          tl   (cal:ruler-tick tier gap (nth 5 style))
          rcol (if (eq tier 'current) (nth 1 style) (nth 0 style)))
    (setq ents (cons (cal:ruler-line spx y (+ spx (* dir tl)) y lay rcol)
                     ents))
    ;; half a label's height above the tick puts it astride its own
    ;; row, and the attachment turns with the row: a label on a row
    ;; that reaches left is hung by its RIGHT edge, so it grows away
    ;; from the spine rather than back across it
    (setq ents (cons (cal:ruler-label (list (+ spx (* dir (+ tl (* gap 0.35))))
                                            (+ y (/ hgt 2.0)))
                                      hgt (cal:spell-len val hasfeet T)
                                      lay rcol (if (< dir 0.0) 3 1))
                     ents))
    (if (eq tier 'current)
      (setq ents (cons (cal:ruler-ring spx y (* gap (nth 6 style)) lay rcol)
                       ents)))
    (setq result (cons (list val y) result))
    (setq i (1+ i)))
  (setq ents (cons (cal:ruler-line spx base spx (+ base (* (- n 1) gap))
                                   lay (nth 0 style))
                   ents))
  ;; the strip a click counts as a pick in: the reach on the side the
  ;; rows run, half a spacing on the other -- the tick's own side
  (setq near (+ spx (* dir gap (nth 7 style)))
        far  (- spx (* dir (/ gap 2.0))))
  (list ents
        (list (min near far) (max near far) (/ gap 2.0))
        (reverse result)))

;; The row (if any) that PT lands on: inside the ruler's strip in X and
;; close enough in Y to one of ROWS.  Returns the row's EIGHTHS, or nil
;; when PT is empty space.
(defun cal:ruler-hit (pt box rows / r best bd d)
  (setq best nil bd nil)
  (if (and box (>= (car pt) (car box)) (<= (car pt) (cadr box)))
    (foreach r rows
      (setq d (abs (- (cadr pt) (cadr r))))
      (if (and (<= d (caddr box)) (or (null bd) (< d bd)))
        (setq best (car r) bd d))))
  best)

;; A ruler that is not up yet, to draw on LAY in STYLE.
(defun cal:ruler-new (lay style)
  (list nil nil nil nil nil lay style nil nil))

;; The ruler taken down: its entities erased and forgotten.  The family
;; and the hint flag are kept, since neither is about what is drawn; the
;; ladder is not, since it is what the next prompt asks for and the next
;; prompt says so itself.
;;
;; entdel refuses on a locked layer, and it refuses quietly -- so a
;; ruler that would not come down stayed in the drawing, and every
;; redraw added another.  The tools unlock their own ruler layer before
;; drawing on it; this is the line that says so if one gets through
;; anyway (the step routines draw on the current layer), once per
;; take-down, naming the layer the rows are left on.
(defun cal:ruler-off (state / e left)
  (setq left 0)
  (foreach e (nth 2 state)
    (if (and e (entget e) (not (entdel e))) (setq left (1+ left))))
  (if (> left 0)
    (princ (strcat "
  " (itoa left) " ruler item(s) could not be"
                   " erased - layer " (vl-princ-to-string (nth 5 state))
                   " is locked.  Unlock it and ERASE them.")))
  (list nil (nth 1 state) nil nil nil (nth 5 state) (nth 6 state)
        (nth 7 state) nil))

;; The ruler the next prompt stands beside: the tape round LEN when
;; LADDER is nil, the rungs of LADDER when it is not -- with LEN ringed
;; among them when there is one.  Drawn fresh when it is not up, or is
;; up round some other length or on some other ladder; left alone when
;; it already is what was asked for; taken down when neither is given,
;; since there is then nothing to build one out of.  Whether it is UP is
;; what is drawn, not what it stands round: a ladder with no answer yet
;; stands round nothing and is up all the same.
;; The one-line hint is said the first time a run draws one.
(defun cal:ruler-show (state len ladder / rr)
  ;; a ladder nothing can be built out of is no ladder at all, and is
  ;; dropped here rather than drawn as an empty one
  (if (and ladder (null (cal:ladder-rows ladder))) (setq ladder nil))
  (cond
    ((and (null len) (null ladder)) (cal:ruler-off state))
    ((and (nth 2 state) (equal (nth 0 state) len)
          (equal (nth 8 state) ladder)) state)
    (T
     (setq state (cal:ruler-off state))
     (setq rr (cal:draw-ruler (if len (cal:len-eighths len)) (nth 1 state)
                              (nth 5 state) (nth 6 state) ladder))
     (if (not (nth 7 state))
       (princ (strcat "\n  A ruler of " (if ladder "the usual" "nearby")
                      " lengths is beside the drawing: click a row to"
                      " take it, or type a length (44, 44-1/2, 3'8).")))
     (list len (nth 1 state) (car rr) (cadr rr) (caddr rr)
           (nth 5 state) (nth 6 state) T ladder))))

;; One length prompt beside the ruler in STATE, and every way of
;; answering it: Enter (nil back, for the caller to read as it always
;; did), a keyword out of KWS (handed back as the keyword), a typed
;; measurement in any spelling cal:parse-len reads, a click on a ruler
;; row (that row's value), or a click on empty space, which is the
;; first of two points to measure the length between.  Zero, a
;; negative and text that is not a length are refused and asked again,
;; as initget 6 used to refuse them.  Returns (VALUE STATE): the
;; answer, and the ruler as it now stands.
;;
;; READER is the one thing a caller can add to the reading: a function
;; of the typed string returning inches, for a spelling this tree reads
;; somewhere and the library does not -- SPA's "600mm".  It is tried
;; AFTER the standard spellings, so a measurement written the tree's
;; way still reads the tree's way at a prompt that has one, and what it
;; returns is refused on the same terms as anything else: zero and a
;; negative are not lengths whoever read them.  nil = no such spelling,
;; which is every caller but one.
;;
;; The caller SHOWS the ruler first -- (setq rl (cal:ruler-show rl last
;; ladder) rr (cal:ask-len prompt kws rl nil) v (car rr) rl (cadr rr)) --
;; and that order is not a nicety: an Esc inside this prompt runs the
;; caller's *error*, and what that handler can take down is the ruler
;; the CALLER's state names.  A ruler drawn in here, in a state only
;; this function held, would outlive the Esc.  The caller keeps the
;; state between prompts and takes the ruler down with cal:ruler-off
;; before a prompt that does not take it and on every way out.
(defun cal:ask-len (prompt kws state reader / pk v out done toks)
  (setq done nil out nil)
  (while (not done)
    (if kws (initget 128 kws) (initget 128))
    (setq pk (getpoint prompt))
    (if lzd:ask (lzd:ask prompt pk) pk)
    (cond
      ((null pk) (setq done T))
      ((= (type pk) 'STR)
       (cond
         ((member pk (cal:len-split (if kws kws ""))) (setq out pk done T))
         ;; a leading minus is refused here, since the reader treats a
         ;; dash as the separator in 4-1/2 and would read -5 as 5
         ((= (substr (vl-string-trim " \t" pk) 1 1) "-")
          (princ "\nA length must be more than zero."))
         ;; a fraction with nothing in front of it is almost always the
         ;; tail of 44 1/2 typed with a space -- which this prompt, a
         ;; getpoint, took as Enter after 44 -- landing on the NEXT
         ;; question.  Taken, it was half an inch there, and nothing
         ;; said so.  Refused, the drafter sees what happened and can
         ;; still give half an inch as 0-1/2 or .5
         ((and (= 1 (length (setq toks (cal:len-split
                                          (vl-string-trim " \t\"'" pk)))))
               (vl-string-search "/" (car toks)))
          (princ (strcat "\n\"" pk "\" on its own?  A space ends the answer"
                         " at this prompt - type 44-1/2, or 0-1/2 for half"
                         " an inch.")))
         ((setq v (cal:parse-len pk))
          (if (> (car v) 0.0)
            (progn
              (setq out (car v) done T)
              ;; a typed spelling picks the ruler's family -- feet typed
              ;; means feet on the ruler -- and a change relabels every
              ;; row, so the one standing is taken down here.  Down, not
              ;; forgotten: a ladder stands round no length, so there is
              ;; nothing for forgetting one to redraw
              (if (not (eq (cadr v) (nth 1 state)))
                (setq state (cal:ruler-off
                              (list (nth 0 state) (cadr v) (nth 2 state)
                                    (nth 3 state) (nth 4 state) (nth 5 state)
                                    (nth 6 state) (nth 7 state)
                                    (nth 8 state))))))
            (princ "\nA length must be more than zero.")))
         ((and reader (setq v (apply reader (list pk))))
          (if (and (numberp v) (> v 0.0))
            (setq out v done T)
            (princ "\nA length must be more than zero.")))
         (T (cal:len-unread pk))))
      ((setq v (cal:ruler-hit pk (nth 3 state) (nth 4 state)))
       (setq out (/ v 8.0) done T))
      (T
       (setq v (getdist pk "\nSecond point of the length: "))
       (if lzd:ask (lzd:ask "\nSecond point of the length: " v) v)
       (if (and (numberp v) (> v 0.0))
         (setq out v done T)
         (princ "\nA length must be more than zero.")))))
  (list out state))
;;; -------------------- end of the length ruler -------------------------

;;; -------------------- point blocks ------------------------------------

;; The name carried by a point block, read from its TAG attribute; when
;; the block has no such attribute, the first attribute whose value
;; reads as a number is taken instead (survey exports do not all use
;; the ab_pt tag).  nil when neither exists.  (lh:block-number,
;; lhd.lsp:671, with the tag as an argument.)
(defun cal:block-number (en tag / sub ed val fall v)
  (setq sub (entnext en) val nil fall nil)
  (while (and sub
              (setq ed (entget sub))
              (= "ATTRIB" (cdr (assoc 0 ed))))
    (setq v (cdr (assoc 1 ed)))
    (if (and (null val)
             (cdr (assoc 2 ed))
             (= (strcase (cdr (assoc 2 ed))) (strcase tag)))
      (setq val v))
    (if (and (null fall) v (distof v 2))
      (setq fall v))
    (setq sub (entnext sub)))
  (if val val fall))

;;; -------------------- the inside of a closed loop ---------------------

;; Signed area of the closed polygon PTS, by the shoelace sum: positive
;; when it runs counterclockwise.  That SIGN is how this tree defines
;; the inside of a pool -- turn the direction of travel 90 degrees the
;; way the sign says and you are pointing into the water, at every
;; point of the wall, whatever shape it is.  A clicked centre answers
;; the same question only for a shape with no notch in it: on an L or a
;; keyhole a centre in one lobe sits on the wrong side of a wall in the
;; other, and the marks there come out backwards.  (ABHD's pf:loop-area,
;; which the hopper and the slope lines have always been built on.)
(defun cal:loop-area (pts / sum prev q)
  (setq sum 0.0 prev (last pts))
  (foreach q pts
    (setq sum  (+ sum (- (* (car prev) (cadr q))
                         (* (car q) (cadr prev))))
          prev q))
  (/ sum 2.0))

;; Which way to turn a tangent to point INTO the loop PTS: 1.0 or -1.0,
;; to multiply the left-hand normal (cal:perp) by.  nil when the loop
;; encloses nothing measurable -- a figure-eight, a doubled-back trace,
;; three points in a line -- where there is no inside to point at and
;; the caller has to ask instead of guessing.
(defun cal:inward-sign (pts / a)
  (if (< (length pts) 3)
    nil
    (progn
      (setq a (cal:loop-area pts))
      (cond ((> a 1.0e-6) 1.0)
            ((< a -1.0e-6) -1.0)))))

;; T when P lies inside the closed polygon PTS -- the crossing test: a
;; ray cast along +X crosses an odd number of edges from inside and an
;; even number from outside.  A point exactly ON an edge may answer
;; either way, which is why every caller here asks it about a point it
;; has already moved clear of the wall.
(defun cal:in-loop-p (p pts / in prev q x y yi yj)
  (setq in nil prev (last pts) x (car p) y (cadr p))
  (foreach q pts
    (setq yi (cadr q) yj (cadr prev))
    ;; the two ends straddle the ray, written as two ands rather than
    ;; (/= (> ..) (> ..)): AutoLISP's /= is for numbers and strings, and
    ;; handing it T and nil is a bad-argument-type nobody sees until a
    ;; real drawing runs it
    (if (and (or (and (> yi y) (<= yj y))
                 (and (> yj y) (<= yi y)))
             (< x (+ (car q)
                     (* (- (car prev) (car q))
                        (/ (- y yi) (- yj yi))))))
      (setq in (not in)))
    (setq prev q))
  in)

;;; -------------------- a measurement that fights its neighbours -------

;; The entries of PAIRS that sit AGAINST the run on both sides by more
;; than TOL -- the mis-keyed number in a series of measurements taken
;; along one wall.  PAIRS is ((position . value) ...) in position order:
;; how far along the wall each measurement was taken, and what it
;; measured.
;;
;; The rule, and why it is this one.  A value is suspect when it is
;; lower than BOTH its neighbours by more than TOL, or higher than both
;; by more than TOL, AND it sits more than TOL off the straight line
;; between them.  40, 10, 30 at three points in a row is that: the 10
;; fights both sides, and the wall between a 40 and a 30 is about 35.
;; Requiring it to fight BOTH neighbours is what keeps a real curve
;; quiet -- 40, 38, 30 is a wall bending away, every value between its
;; neighbours, and nothing is said about it however far the middle one
;; sits off the chord.
;;
;; Returns ((index . what the neighbours put there) ...), oldest first,
;; indexed into PAIRS.  The caller names the measurement and says so;
;; nothing here changes a number, because a surveyed value is the one
;; thing a drawing tool may not quietly overwrite.
(defun cal:spikes (pairs tol / n i a b c span expect out)
  (setq n (length pairs) i 1 out nil)
  (while (< i (1- n))
    (setq a    (nth (1- i) pairs)
          b    (nth i pairs)
          c    (nth (1+ i) pairs)
          span (- (car c) (car a)))
    (if (> span 1.0e-9)
      (progn
        (setq expect (+ (cdr a) (* (- (cdr c) (cdr a))
                                   (/ (- (car b) (car a)) span))))
        (if (and (> (abs (- (cdr b) expect)) tol)
                 (or (and (> (- (cdr a) (cdr b)) tol)
                          (> (- (cdr c) (cdr b)) tol))
                     (and (> (- (cdr b) (cdr a)) tol)
                          (> (- (cdr b) (cdr c)) tol))))
          (setq out (cons (cons i expect) out)))))
    (setq i (1+ i)))
  (reverse out))

;;; -------------------- naming a survey point ---------------------------
;;; PERPMARK's infrastructure (pm:as-number, pm:canon, pm:matches,
;;; pm:nearest and pm:askpoint, PERPMARK.lsp), lifted for the fitters
;;; ABHD, CABHD, LHD, ABLOBF and FITABHD, which ask about survey points
;;; at every declaration -- the wall runs from Pt.17 to Pt.22, Pt.9 is
;;; a corner, Pt.30 is held, leave Pt.41 out -- and used to take a
;;; PLACE for each and snap it to whatever point was nearest, however
;;; far off the click landed.  A question about a point NAMES one: a
;;; click within SNAP of a point picks it, a typed number finds it,
;;; and a miss is re-asked where it stands.
;;;
;;; A candidate is (position name ...): the point as the tool holds it
;;; and what the prompts call it.  The tools keep their own classifier
;;; (which entities are survey points, and what a moved point is) and
;;; hand the list in; the tag reader above is what names a block.

;; The NUMBER a typed point name carries: the spelling with the spaces,
;; the hashes and the "Pt." prefix taken off, and nothing else touched.
;; Only the dot right after PT is a prefix dot - a point genuinely named
;; "40.5" keeps its decimal.  (ABFIND's abf:as-number.)
(defun cal:as-number (s / out i ch)
  (setq out "" i 1)
  (while (<= i (strlen s))
    (setq ch (substr s i 1))
    (if (not (member ch '(" " "#")))
      (setq out (strcat out ch)))
    (setq i (1+ i)))
  (if (and (>= (strlen out) 2) (= (strcase (substr out 1 2)) "PT"))
    (progn
      (setq out (substr out 3))
      (if (= (substr out 1 1) ".") (setq out (substr out 2)))))
  out)

;; One comparable form for a point number, so "35", "Pt.35", "pt 35",
;; "#35" and "035" all meet in the middle.  (ABFIND's abf:canon.)
(defun cal:canon (s)
  (setq s (cal:as-number (strcase s)))
  (if (distof s 2)
    (rtos (distof s 2) 2 8)
    s))

;; Every candidate whose name is the number typed.  More than one is a
;; sheet that numbers two points the same, and is asked about rather
;; than guessed at.
(defun cal:cand-matches (s cands / want out c)
  (setq want (cal:canon s) out nil)
  (foreach c cands
    (if (= (cal:canon (cadr c)) want) (setq out (cons c out))))
  (reverse out))

;; The candidate nearest PK, when one sits within SNAP of it.  A typed
;; number never comes here - a name is exact.
(defun cal:cand-nearest (pk cands snap / best bd c d)
  (setq best nil bd nil)
  (foreach c cands
    (setq d (distance (cal:2d pk) (cal:2d (car c))))
    (if (and (<= d snap) (or (null bd) (< d bd)))
      (setq best c bd d)))
  best)

;; A survey point, clicked or typed.  One prompt takes both: (initget
;; 128) is arbitrary input, which hands typed text back from getpoint as
;; the string it is where a click comes back as the point it is.  The
;; misses are re-asked HERE rather than unwinding the caller's chain --
;; a number nothing carries and a click on nothing are typos, not
;; answers, and the question they belong to is this one.  TAIL is the
;; prose inside the angle brackets on a prompt whose Enter means
;; something - "Enter = done", the point Enter takes - and nil when a
;; point is required.  CANDS are the (position name) candidates and
;; SNAP how close a click has to land.  Returns the candidate, nil for
;; Enter, or CAL-BACK.
(defun cal:askpoint (msg tail back cands snap / v out done dupes)
  (setq done nil out nil)
  (while (not done)
    (if back
      (initget (if tail 128 129) "Back Undo")
      (initget (if tail 128 129)))
    (setq v (getpoint (strcat "\n" msg
                              (if back " [Back]" "")
                              (if tail (strcat " <" tail ">") "")
                              ": ")))
    (if lzd:ask (lzd:ask msg v) v)
    (cond
      ((null v)
       (if tail
         (setq out nil done T)
         (princ "\nA survey point is required - click one, or type its number.")))
      ((and (= (type v) 'STR) (member v '("Back" "Undo")))
       (setq out 'CAL-BACK done T))
      ((= (type v) 'STR)
       (setq dupes (cal:cand-matches v cands))
       (cond
         ((null dupes)
          (princ (strcat "\nNo survey point is numbered \""
                         (cal:as-number v)
                         "\" - try again, or click the point itself.")))
         ((> (length dupes) 1)
          (princ (strcat "\n" (itoa (length dupes)) " points are numbered \""
                         (cal:as-number v)
                         "\" - click the one you mean.")))
         (t (setq out (car dupes) done T))))
      (t
       (setq out (cal:cand-nearest v cands snap))
       (if out
         (setq done T)
         (princ (strcat "\nNo survey point there - click one, or type"
                        " its number."))))))
  out)

;;; ----------------------------------------------------------------------
;; Quiet inside the whole build, on the same rule every member
;; follows -- the build says once that it loaded, and CALVER says what
;; it loaded.  cal:*build-loading* is this file's own flag rather than
;; the members' *calofin-quiet*, because it is already set for exactly
;; this file and means exactly this.
(if (not cal:*build-loading*)
  (princ (strcat "\nCALOFIN-LIB " cal:*version*
                 " loaded.  Shared helpers under the cal: prefix.")))
;; On its own this file defines helpers and exactly one command
;; (CALVER) -- no tools at all.  LAZPASS.lsp and CALOFIN-LOADER.lsp
;; both set the flag below before loading it, so this only ever fires
;; when someone APPLOADs the library by itself and would otherwise be
;; left wondering why not one command exists.
(if (not cal:*build-loading*)
  (progn
    (princ "\n[calofin] That is the helper library ONLY - it defines no tools.")
    (princ "\n[calofin] APPLOAD LAZPASS.lsp for the whole build instead.")))
(princ)
