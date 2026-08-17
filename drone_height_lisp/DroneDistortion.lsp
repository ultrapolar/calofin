;;; ============================================================================
;;;  Drone Distortion Correction Tool for AutoCAD            (DroneDistortion.lsp)
;;; ----------------------------------------------------------------------------
;;;  Corrects the scale of pool features that are NOT at deck level after a
;;;  near-nadir drone photo has been rectified to deck scale (e.g. by Ariel /
;;;  Fisherlea using its 6 deck scale measurements) and exported as a DXF that
;;;  you open in AutoCAD. The photo itself is not in CAD - this tool works
;;;  purely on the traced geometry.
;;;
;;;  WHY THIS IS NEEDED
;;;  ------------------
;;;  The deck scale is only true ON the deck plane. A feature raised toward the
;;;  drone (a raised spa) is closer to the camera, so it traces LARGER than it
;;;  really is. A feature below the deck (a negative-edge catch basin) is farther
;;;  away, so it traces SMALLER than it really is.
;;;
;;;  THE MATH
;;;  --------
;;;  For a traced feature sitting a signed height z above the deck
;;;      z > 0  -> raised toward the drone
;;;      z < 0  -> sunken below the deck
;;;  and a drone height H above the deck, the TRUE geometry is the traced
;;;  geometry scaled by:
;;;
;;;         factor = (H - z) / H
;;;
;;;  The "distortion rate" is ~1/H to first order (at H = 100, about a 1% size
;;;  error per unit of height); the exact apparent/true ratio is H/(H - z),
;;;  which DDFIX reports for each feature you correct.
;;;
;;;  BASE POINT
;;;  ----------
;;;  DDFIX scales about the CENTRE of the selection by default, so the feature
;;;  stays put and only changes size. If a feature shares an edge with the pool
;;;  (e.g. a spillover spa), pick that shared corner as the base point instead
;;;  so the shared edge does not move.
;;;
;;;  COMMANDS
;;;  --------
;;;     DDFIX   - select a feature, enter its height, apply the correction
;;;     DDSET   - set/forget the drone height H (DDFIX also asks the first time)
;;;     DDALT   - read RelativeAltitude from the original DJI image and set H
;;;     DDCAL   - back-solve H from a feature of known true size (cross-check)
;;;     DDINFO  - show current settings and the distortion rate
;;;
;;;  UNITS
;;;  -----
;;;  The correction is a dimensionless ratio, so the DRAWING units do not matter.
;;;  Enter the DRONE HEIGHT (H) as a number in FEET (e.g. 62 or 62.25).
;;;  Enter each FEATURE HEIGHT in feet & inches - 6"  2'  1'6-1/2"  18'6.5" - and
;;;  put a - in front for a feature BELOW the deck (a bare number is read as
;;;  inches). Any size works; small ones get a tiny correction (1" at H=80' = ~0.1%).
;;;
;;;  H is the drone height ABOVE THE DECK, not above the take-off point. If the
;;;  drone took off from the deck, that is the logged "relative altitude" (DDALT
;;;  reads it straight out of the original DJI .JPG). If it took off X BELOW the
;;;  deck SUBTRACT X; if it took off X ABOVE the deck ADD X.
;;;
;;;  H is stored in the drawing and survives save/close/reopen.
;;; ============================================================================

(vl-load-com)

(setq *DD-STORE* "DRONE_DISTORTION")   ; LDATA dictionary key (per-drawing)

;; -- persistent storage helpers ---------------------------------------------
;; vlax-ldata-get returns the value with its original type, or nil if absent.
(defun dd-get (key)
  (vlax-ldata-get *DD-STORE* key))

(defun dd-put (key val)
  (vlax-ldata-put *DD-STORE* key val))

;; -- formatting helper ------------------------------------------------------
(defun dd-num (x) (rtos x 2 3))        ; trim a real to 3 decimals as a string

;; -- centre of the combined bounding box of a selection set (returns WCS) ----
(defun dd-ss-center (ss / i obj mn mx lo hi lomin himax)
  (setq i 0)
  (while (< i (sslength ss))
    (setq obj (vlax-ename->vla-object (ssname ss i)))
    (if (not (vl-catch-all-error-p
               (vl-catch-all-apply 'vla-getboundingbox (list obj 'mn 'mx))))
      (progn
        (setq lo (vlax-safearray->list mn)
              hi (vlax-safearray->list mx))
        (if lomin
          (setq lomin (mapcar 'min lomin lo)
                himax (mapcar 'max himax hi))
          (setq lomin lo himax hi))))
    (setq i (1+ i)))
  (if lomin
    (mapcar '(lambda (a b) (/ (+ a b) 2.0)) lomin himax)))

;; -- parse one numeric piece into a number of inches; nil if not numeric -------
;; "6"   "6.5"   "6-1/2"   "1/2"  ->  number
(defun dd-inchval (s / pos whole frac num den)
  (setq s (vl-string-trim " " s))
  (cond
    ((= s "") 0.0)
    ((setq pos (vl-string-search "-" s))               ; whole-and-fraction: 6-1/2
     (setq whole (dd-inchval (substr s 1 pos))
           frac  (dd-inchval (substr s (+ pos 2))))
     (if (and whole frac) (+ whole frac)))
    ((setq pos (vl-string-search "/" s))               ; fraction: 1/2
     (setq num (distof (substr s 1 pos) 2)
           den (distof (substr s (+ pos 2)) 2))
     (if (and num den (/= den 0.0)) (/ num den)))
    (t (distof s 2))))                                  ; plain decimal

;; -- ask for a height in feet & inches; return decimal FEET (nil if blank/bad) -
;; Accepts:  6"   18   2'   2'6"   1'6-1/2"   18'6.5"   -3'4"
;; A leading - means BELOW the deck; a bare number is read as inches. Splits on
;; the ' and " by hand, so it does not depend on the drawing's unit settings.
(defun dd-parse-height (prompt / s sign fpos ftxt itxt feet inch)
  (setq s (getstring T prompt))
  (if (or (null s) (= (vl-string-trim " \t" s) ""))
    nil
    (progn
      (setq s (vl-string-trim " \t" s) sign 1.0)
      (while (member (substr s 1 1) '("-" "+"))
        (if (= (substr s 1 1) "-") (setq sign (- sign)))
        (setq s (vl-string-trim " " (substr s 2))))
      (setq fpos (vl-string-search "'" s))
      (if fpos
        (setq ftxt (substr s 1 fpos) itxt (substr s (+ fpos 2)))
        (setq ftxt "0" itxt s))
      (if (= ftxt "") (setq ftxt "0"))
      (setq itxt (vl-string-trim " \"" itxt))
      (if (= itxt "") (setq itxt "0"))
      (setq feet (distof ftxt 2) inch (dd-inchval itxt))
      (if (and feet inch)
        (* sign (+ feet (/ inch 12.0)))))))

;; ---------------------------------------------------------------------------
;;  DDFIX : correct a selected off-deck feature
;; ---------------------------------------------------------------------------
(defun c:DDFIX ( / *error* cmd ss h cur-h z base factor appf)
  (setq cmd (getvar "CMDECHO"))
  (defun *error* (m)
    (setvar "CMDECHO" cmd)
    (if (and m (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*ABORT*")))
      (princ (strcat "\nError: " m)))
    (princ))

  ;; 1) select the spa / obstacle (one or more objects)
  (princ "\nSelect the spa / obstacle to correct (one or more objects), then Enter.")
  (setq ss (ssget))
  (cond
    ((null ss) (princ "\nNothing selected."))
    (t
      ;; 2) drone height above the deck - remembered; press Enter to keep last value
      (setq cur-h (dd-get "H"))
      (setq h (getreal (strcat "\nDrone height above the deck, in FEET"
                               (if cur-h (strcat " <" (dd-num cur-h) ">") "")
                               ": ")))
      (if (and (null h) cur-h) (setq h cur-h))
      (cond
        ((or (null h) (<= h 0.0))
         (princ "\nNeed a drone height greater than 0 - aborting."))
        (t
          (dd-put "H" h)
          ;; 3) spa / obstacle height in feet & inches
          (setq z (dd-parse-height
                    (strcat "\nSpa / obstacle height relative to deck"
                            "\n  e.g. 6\"  2'  1'6-1/2\"  18'6.5\"   (- in front = below deck): ")))
          (cond
            ((null z) (princ "\nNo valid height (try like 1'6\") - aborting."))
            ((equal z 0.0 1e-9)
             (princ "\nHeight is 0 - feature is at deck level, no change."))
            ((>= (abs z) h)
             (princ (strcat "\n|height| (" (dd-num z) " ft) >= drone height ("
                            (dd-num h) " ft). Check your value - aborting.")))
            (t
              ;; 4) scale about the centre of the selection
              (setq base (dd-ss-center ss))
              (cond
                ((null base) (princ "\nCould not work out a centre point - aborting."))
                (t
                  (setq base   (trans base 0 1)             ; WCS centre -> current UCS
                        factor (/ (- h z) h))               ; (H - z) / H
                  (setvar "CMDECHO" 0)
                  ;; "_non" overrides any running osnap; vl-cmdf returns nil on failure
                  (if (vl-cmdf "_.SCALE" ss "" "_non" base factor)
                    (progn
                      (setq appf (/ h (- h z)))             ; apparent / true
                      (princ (strcat "\nApplied scale " (rtos factor 2 5) " ("
                                     (rtos (* 100.0 (- factor 1.0)) 2 2) "% size change)."))
                      (if (> z 0.0)
                        (princ (strcat "\nRaised feature: it was traced ~"
                                       (rtos (* 100.0 (- appf 1.0)) 2 2) "% too BIG."))
                        (princ (strcat "\nSunken feature: it was traced ~"
                                       (rtos (* 100.0 (- 1.0 appf)) 2 2) "% too SMALL."))))
                    (princ "\nSCALE did not run - are the objects on a locked layer?"))
                  (setvar "CMDECHO" cmd)))))))))
  (setvar "CMDECHO" cmd)
  (princ))

;; ---------------------------------------------------------------------------
;;  DDSET : set / change the drone height H for this drawing
;; ---------------------------------------------------------------------------
(defun c:DDSET ( / h cur-h)
  (setq cur-h (dd-get "H"))
  (setq h (getreal (strcat "\nDrone height ABOVE THE DECK, in FEET"
                           (if cur-h (strcat " <" (dd-num cur-h) ">") "")
                           ": ")))
  (if (and (null h) cur-h) (setq h cur-h))   ; <Enter> keeps the current value
  (cond
    ((null h)   (princ "\nNo height set."))
    ((<= h 0.0) (princ "\nHeight must be greater than 0."))
    (t
      (dd-put "H" h)
      (princ (strcat "\nSaved drone height  H = " (dd-num h)))
      (princ (strcat "\nDistortion rate: ~" (dd-num (/ 100.0 h))
                     "% size change per unit of height."))))
  (princ))

;; ---------------------------------------------------------------------------
;;  DDCAL : back-solve H from a feature whose true size you measured on site
;;          (independent cross-check on the logged altitude)
;;          H = Lapp * z / (Lapp - Ltrue)
;; ---------------------------------------------------------------------------
(defun c:DDCAL ( / lapp ltrue z h)
  (princ "\nCalibrate drone height from a feature of known true size.")
  (setq lapp  (getdist "\nApparent (traced) size in the drawing - type it or pick 2 points: "))
  (setq ltrue (getreal "\nTrue size measured on site: "))
  (setq z (dd-parse-height "\nHeight of that feature, e.g. 6\"  2'  18'6.5\"  (- for sunken): "))
  (cond
    ((or (null lapp) (null ltrue) (null z))
     (princ "\nMissing input - aborting."))
    ((equal z 0.0 1e-9)
     (princ "\nHeight is 0 - cannot solve H from a deck-level feature."))
    ((equal lapp ltrue (* 1e-4 (max (abs lapp) (abs ltrue) 1.0)))
     (princ "\nApparent and true sizes are too close - distortion too small to solve H reliably."))
    (t
      (setq h (/ (* lapp z) (- lapp ltrue)))
      (if (> h 0.0)
        (progn
          (dd-put "H" h)
          (princ (strcat "\nSolved drone height  H = " (dd-num h) "  (saved)."))
          (princ (strcat "\nDistortion rate: ~" (dd-num (/ 100.0 h)) "% per unit of height.")))
        (princ (strcat "\nGot a non-physical H = " (dd-num h)
                       "\nCheck the sign of the height and that apparent/true sizes "
                       "match a raised (app>true) or sunken (app<true) feature.")))))
  (princ))

;; ---------------------------------------------------------------------------
;;  DDINFO : report current settings
;; ---------------------------------------------------------------------------
(defun c:DDINFO ( / h)
  (setq h (dd-get "H"))
  (princ "\n--- Drone Distortion settings (this drawing) ---")
  (if h
    (progn
      (princ (strcat "\n  Drone height above deck (H): " (dd-num h)))
      (princ (strcat "\n  Distortion rate            : ~" (dd-num (/ 100.0 h))
                     "% size change per unit of height")))
    (princ "\n  Drone height (H)           : NOT SET  (run DDSET or DDFIX)"))
  (princ "\n------------------------------------------------")
  (princ))

;; ---------------------------------------------------------------------------
;;  RelativeAltitude reader  -  pull dji:RelativeAltitude out of a DJI image
;; ---------------------------------------------------------------------------
;;  DJI writes an XMP text packet inside the image holding, e.g.
;;      dji:RelativeAltitude="+18.90"     (METRES above the TAKE-OFF point)
;;  This reads the file's raw bytes (Windows ADODB.Stream) and scans for the
;;  tag, so the container does not matter - JPG and PNG both work as long as
;;  the packet survived. It only works on ORIGINAL camera files; screenshots,
;;  edited, emailed or re-exported copies have the metadata stripped.
;;  (Windows AutoCAD only.)

;; value string like "+18.90" -> real metres (drops a leading +, trims spaces)
(defun dd-relalt->num (s)
  (setq s (vl-string-trim " " s))
  (if (and (> (strlen s) 0) (= (substr s 1 1) "+")) (setq s (substr s 2)))
  (atof s))

;; read up to `cnt` bytes of a file as a list of ints (0-255), BINARY-SAFE,
;; via Windows' ADODB.Stream.  Plain (open ... "r") + read-char is TEXT mode and
;; quits at the first 0x1A byte - DJI JPEGs have dozens of those before the XMP -
;; so it cannot be used here.  Returns the byte list, or nil if unreadable.
(defun dd-file-bytes (file cnt / stm out err)
  (setq err
    (vl-catch-all-apply
      '(lambda ( / raw sa tmp)
         (setq stm (vlax-create-object "ADODB.Stream"))
         (vlax-put-property  stm 'Type 1)              ; 1 = adTypeBinary,
         ;; AutoLISP will not call a method whose parameters are all optional
         ;; unless they are supplied - a bare (Open) fails with "too few
         ;; actual parameters". Pass Stream.Open's documented defaults.
         (if (vl-catch-all-error-p
               (vl-catch-all-apply
                 '(lambda ()
                    (vlax-invoke-method stm 'Open (vlax-make-variant) 0 -1 "" ""))
                 '()))
           (vlax-invoke-method stm 'Open))
         (vlax-invoke-method stm 'LoadFromFile file)
         (setq raw (vlax-invoke-method stm 'Read cnt)) ; first cnt bytes
         (vlax-invoke-method stm 'Close)
         (cond
           ((listp raw) (setq out raw))                ; some builds return a list
           (t
            (setq tmp (vl-catch-all-apply 'vlax-variant-value (list raw)))
            (setq sa  (if (vl-catch-all-error-p tmp) raw tmp))
            (setq out (vlax-safearray->list sa)))))
      '()))
  (if stm (vl-catch-all-apply 'vlax-release-object (list stm)))
  (if (vl-catch-all-error-p err) nil out))

;; scan an image for  RelativeAltitude="..."  ; returns METRES (real) or nil.
;; tgt is the ASCII for  RelativeAltitude="  - we walk the raw bytes so the
;; binary image data does not trip us up; stop at the closing quote.
(defun dd-jpg-relalt (file / lst tgt tlen m val done b)
  (setq tgt  '(82 101 108 97 116 105 118 101 65 108 116 105 116 117 100 101 61 34)
        tlen (length tgt) m 0 val "" done nil)
  (setq lst (dd-file-bytes file 262144))            ; first 256 KB (XMP is near the front)
  (while (and lst (not done))
    (setq b (car lst) lst (cdr lst))
    (if (< b 0) (setq b (+ b 256)))                 ; normalise if returned signed
    (cond
      ((< m tlen)                                    ; still matching the tag
       (if (= b (nth m tgt))
         (setq m (1+ m))
         (setq m (if (= b (car tgt)) 1 0))))         ; reset (tag starts with R)
      ((= b 34) (setq done t))                       ; closing quote -> done
      (t (setq val (strcat val (chr b))))))          ; collect the value
  (if (and done (> (strlen val) 0))
    (dd-relalt->num val)))

;; ---------------------------------------------------------------------------
;;  DDALT : read RelativeAltitude from a drone image and (optionally) set H
;; ---------------------------------------------------------------------------
(defun c:DDALT ( / file m ft off h ans)
  (setq file (getfiled "Select the ORIGINAL drone image (PNG / JPG / TIF)" ""
                       "png;jpg;jpeg;tif;tiff" 20))
  (cond
    ((null file) (princ "\nNo file selected."))
    ((null (setq m (dd-jpg-relalt file)))
     (alert (strcat "NO RelativeAltitude IN THIS FILE"
                    "\nFile: " (vl-filename-base file)
                    (if (vl-filename-extension file) (vl-filename-extension file) "")
                    "\n\nCould not find dji:RelativeAltitude in the file."
                    "\nIs it the ORIGINAL camera file?  Screenshots / edited /"
                    "\nexported copies lose the metadata."
                    "\n\n(DDGPS reads more formats and also falls back to the"
                    "\nEXIF GPS block - try that.)"))
     (princ "\nCould not find dji:RelativeAltitude in that file.")
     (princ "\n  Is it the ORIGINAL camera file?  Screenshots / edited / exported copies lose it."))
    (t
     (setq ft (* m 3.280839895))
     (princ "\nRelativeAltitude (drone height above the TAKE-OFF point):")
     (princ (strcat "\n   " (dd-num m) " m   =   " (dd-num ft) " ft"))
     (initget "Yes No")
     (setq ans (getkword "\nUse this to set the drone height H? [Yes/No] <Yes>: "))
     (if (null ans) (setq ans "Yes"))
     (if (= ans "No")
       (princ "\nH not changed.")
       (progn
         (setq off (getreal (strcat "\nTake-off point vs deck, in FEET"
                                    "\n  (+ if take-off ABOVE deck, - if BELOW, Enter if it took off FROM the deck): ")))
         (if (null off) (setq off 0.0))
         (setq h (+ ft off))
         (if (<= h 0.0)
           (princ (strcat "\nThat gives H = " (dd-num h) " ft (<= 0) - not saved. Check the offset."))
           (progn
             (dd-put "H" h)
             (princ (strcat "\nSaved drone height  H = " (dd-num h) " ft"))
             (if (/= off 0.0)
               (princ (strcat "   (" (dd-num ft) " ft relative "
                              (if (> off 0.0) "+ " "- ") (dd-num (abs off)) " ft offset)")))
             (princ (strcat "\nDistortion rate: ~" (dd-num (/ 100.0 h))
                            "% size change per unit of height."))))))))
  (princ))

(princ "\nDrone Distortion tool v3.4 loaded  (DDALT accepts PNG / JPG / TIF and fails loud).")
(princ "\n  Commands: DDFIX  DDSET  DDALT  DDCAL  DDINFO")
(princ)
