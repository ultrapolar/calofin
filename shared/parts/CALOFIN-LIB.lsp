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
;;; Command:  CALVER   print the loaded library version
;;; ======================================================================

(vl-load-com)

(setq cal:*version* "v1.6")

(defun c:CALVER ()
  (princ (strcat "\nCALOFIN-LIB " cal:*version*))
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
  (cond ((and back (cal:back-word-p v)) 'CAL-BACK)
        ((= v "") (if dflt dflt v))
        (t v)))

;; The one pause wording of STANDARDS.md section 3, for new code.  The
;; POOL/SPA tutorials keep their own pauses -- theirs can stop the
;; tutorial, and the two disagree about which answer means stop.
(defun cal:pause ()
  (getstring "\n--- press Enter to continue ---")
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

(defun cal:dimstyrestore ()
  ;; called from *error* handlers, where a bare (command ...) can itself
  ;; fail -- so command-s under vl-catch-all-apply (STANDARDS section 5)
  (if (and cal:*odstyle* (tblsearch "DIMSTYLE" cal:*odstyle*))
      (vl-catch-all-apply 'command-s
        (list "_.-DIMSTYLE" "_Restore" cal:*odstyle*)))
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
(defun cal:layer-usable-p (name / ld f cl)
  (if (setq ld (tblsearch "LAYER" name))
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
;; than fighting it; the other three are real colour numbers.
(setq cal:*imgcol-line* -16)
(setq cal:*imgcol-back* -15)
(setq cal:*imgcol-dim* 8)
(setq cal:*imgcol-val* 30)
(setq cal:*imgcol-hi* 5)

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

;;; ----------------------------------------------------------------------
(princ (strcat "\nCALOFIN-LIB " cal:*version*
               " loaded.  Shared helpers under the cal: prefix."))
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
