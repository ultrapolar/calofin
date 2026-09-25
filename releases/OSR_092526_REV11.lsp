;;; ======================================================================
;;; OSR.lsp  --  Object Snap Restore: put the drafter's own osnaps back
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  OSR     set OSMODE to the drafter's saved preset
;;;            OSRVER  print the loaded version
;;; ======================================================================
;;;
;;;  Object snaps drift.  A drafter ticks Tangent for one arc, Nearest
;;;  for one leader, turns F3 off to click in open space -- and an hour
;;;  later the running snaps are whatever the last fiddle left them,
;;;  and the way back is OSNAP, fourteen tick boxes and OK, from
;;;  memory.  A tool that crashed without its handler can do the same
;;;  thing in one go.
;;;
;;;  OSR is the way back in one word.  It sets OSMODE to a PRESET the
;;;  drafter chose once -- which modes are ticked, and whether Object
;;;  Snap is on at all -- and says what it put back.  Nothing is asked:
;;;  the preset is chosen in the panel's Options (LAZSET, the "Object
;;;  snaps" box), or at the command line with CALSET -> Osnaps, and it
;;;  lives in the AutoCAD profile under CalofinOsnapPreset, so it
;;;  survives a restart and a rebuild of the tools.
;;;
;;;  With no preset saved yet OSR uses osr:*default* below: Endpoint,
;;;  Midpoint, Center, Node, Quadrant, Intersection and Perpendicular,
;;;  with Object Snap on.
;;;
;;;  WHAT IT DOES NOT DO: it does not touch Object Snap Tracking (that
;;;  is AUTOSNAP, not OSMODE), polar tracking, or the 3D object snaps
;;;  (3DOSMODE).  It changes the drafter's setting ON PURPOSE and leaves
;;;  it changed -- this is the one command in the tree whose job is to
;;;  move OSMODE and not give it back.
;;; ======================================================================

(setq *osr-version* "v1.1")

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;; Everything a shop might want changed, all in one block; nothing
;;; settable lives anywhere else in this file.  setq any of them after
;;; loading and the next run reads the new value.

;; The OSMODE OSR puts back when the drafter has not saved a preset of
;; their own (LAZSET's Object snaps box, or CALSET Osnaps).  The sum of
;; the modes wanted: Endpoint 1, Midpoint 2, Center 4, Node 8, Quadrant
;; 16, Intersection 32, Insertion 64, Perpendicular 128, Tangent 256,
;; Nearest 512, Geometric Center 1024, Apparent intersection 2048,
;; Extension 4096, Parallel 8192; add 16384 to leave Object Snap OFF.
;; Change it and a drafter with no preset of their own gets this set.
(setq osr:*default* 191)

;;; -------------------- the modes ----------------------------------------

;; NOT A KNOB: the profile key the drafter's own preset is stored
;; under.  LAZPANEL writes it (LAZSET and CALSET, lzp:*osrkey*), so a
;; change here alone would leave OSR reading a key nothing writes.
(setq osr:*envkey* "CalofinOsnapPreset")

;;; Not a knob: AutoCAD's own OSMODE bits, in the order its Drafting
;;; Settings dialog lists them.

(setq osr:*modes*
  '(("Endpoint"              . 1)
    ("Midpoint"              . 2)
    ("Center"                . 4)
    ("Geometric Center"      . 1024)
    ("Node"                  . 8)
    ("Quadrant"              . 16)
    ("Intersection"          . 32)
    ("Extension"             . 4096)
    ("Insertion"             . 64)
    ("Perpendicular"         . 128)
    ("Tangent"               . 256)
    ("Nearest"               . 512)
    ("Apparent intersection" . 2048)
    ("Parallel"              . 8192)))

;; NOT A KNOB: AutoCAD's own bit that means Object Snap is OFF (F3),
;; modes kept.
(setq osr:*offbit* 16384)

;;; -------------------- the preset ---------------------------------------

;; T when S reads as an OSMODE: digits only, 0 to 32767.  Spelled out
;; rather than handed to atoi alone -- atoi reads "12x" as 12 and "red"
;; as 0, and 0 is a real OSMODE (no snaps at all), so a typo in the
;; profile must not quietly clear every snap.
(defun osr:valid-p (s / i n ok)
  (setq n (strlen s) i 1 ok (and (> n 0) (< n 6)))
  (while (and ok (<= i n))
    (if (not (member (substr s i 1)
                     '("0" "1" "2" "3" "4" "5" "6" "7" "8" "9")))
      (setq ok nil))
    (setq i (1+ i)))
  (if (and ok (<= (atoi s) 32767)) t nil))

;; The preset this run puts back, as (OSMODE . FROM-PROFILE-P).  A value
;; in the profile that does not read as an OSMODE is ignored -- the
;; shipped default is used and the drafter is told why.
(defun osr:preset ( / v)
  (setq v (getenv osr:*envkey*))
  (setq v (if v (vl-string-trim " \t" v) ""))
  (cond
    ((osr:valid-p v) (cons (atoi v) t))
    ((/= v "")
     (princ (strcat "\nOSR: the saved preset \"" v "\" is not an OSMODE"
                    " -- using the shipped one.  Choose yours again in"
                    " LAZSET (Options) or CALSET Osnaps."))
     (cons osr:*default* nil))
    (t (cons osr:*default* nil))))

;; The modes an OSMODE has ticked, as one readable line.
(defun osr:describe (m / out p)
  (setq out "")
  (foreach p osr:*modes*
    (if (/= 0 (logand m (cdr p)))
      (setq out (strcat out (if (= out "") "" ", ") (car p)))))
  (strcat (if (= out "") "no modes ticked" out)
          (if (/= 0 (logand m osr:*offbit*))
            " -- Object Snap OFF"
            " -- Object Snap on")))

;;; -------------------- the command ---------------------------------------

(defun c:OSR ( / *error* oos p)
  (defun *error* (msg)
    ;; FIRST: a run that failed puts back the snaps the drafter had
    ;; when they typed OSR, not whatever it got as far as -- the same
    ;; restore every other command here carries (check_osnap.py)
    (if oos (setvar "OSMODE" oos))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nOSR error: " msg)))
    (if lzd:report (lzd:report "OSR" *osr-version* msg))
    (princ))

  (if lzd:begin (lzd:begin "OSR" *osr-version*))
  (setq oos (getvar "OSMODE"))
  (setq p (osr:preset))
  (setvar "OSMODE" (car p))
  (princ (strcat "\nOSR: object snaps restored -- "
                 (osr:describe (car p))
                 " (OSMODE " (itoa (car p)) ")."))
  (if (not (cdr p))
    (princ (strcat "\n     That is the shipped preset.  Choose your own in"
                   " LAZSET (Options, Object snaps) or CALSET Osnaps.")))
  (if lzd:end (lzd:end "OSR"))
  (princ))

(defun c:OSRVER ()
  (princ (strcat "\nOSR " *osr-version*))
  (princ))

;;; -------------------- load banner ---------------------------------------

;; -------------------- self tests ---------------------------------------
;; What LAZDIAG runs on the drafter's machine after this tool fails, and
;; writes into the report: the tool's own helpers on inputs whose answers
;; are KNOWN, so the report says whether the arithmetic was sound where
;; it ran.  (label expression expected) passes when the value is equal
;; to expected (to 1e-6); (label expression) passes when it is not nil,
;; and the value is written down either way.  Nothing here may prompt,
;; draw or (command): it is evaluated from inside *error*.
;; tests/test_selftests.py runs every entry in the VM at both tiers.
(defun osr:selftests ()
  (list
    (list "valid-p takes a plain OSMODE"        '(osr:valid-p "191")    T)
    (list "valid-p refuses a typo atoi would read" '(osr:valid-p "12x") nil)
    (list "valid-p refuses an empty string"     '(osr:valid-p "")       nil)
    (list "valid-p refuses one past the top"    '(osr:valid-p "32768")  nil)
    (list "the shipped default is an OSMODE"    '(osr:valid-p (itoa osr:*default*)) T)
    (list "describe names the modes ticked"     '(osr:describe 3)
          "Endpoint, Midpoint -- Object Snap on")
    (list "describe says when none are"         '(osr:describe 0)
          "no modes ticked -- Object Snap on")
    (list "describe sees the OFF bit"           '(osr:describe 16385)
          "Endpoint -- Object Snap OFF")
    (list "every mode is a single bit"
          '(not (vl-member-if '(lambda (p) (/= (cdr p) (logand (cdr p) (- (cdr p)))))
                              osr:*modes*)))))

(foreach c '("OSR")
  (setq *calofin-selftests*
        (cons (cons c 'osr:selftests) *calofin-selftests*)))

(if (not *calofin-quiet*)
  (princ (strcat "\nOSR " *osr-version*
                 " loaded.  Type OSR to put your object snaps back.")))
(princ)
