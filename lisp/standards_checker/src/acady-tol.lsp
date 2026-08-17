;;; acady-tol.lsp
;;; Parse one reference drawing's model space into:
;;;   (nominal-signature tolerance-bands warnings)
;;; Tolerance sources, in priority order:
;;;   GEOM   two closed polylines on the TOLERANCE layer (MIN inside / MAX
;;;          outside, told apart by area), authored by OFFSETting the nominal
;;;          so element counts match; or ONE polyline = symmetric band
;;;   TEXT   a TEXT/MTEXT "TOL=0.25" (inches) and optional "ATOL=2" (degrees)
;;;   GLOBAL config defaults
;;; Band per element: (len-lo len-hi rad-lo rad-hi turn-tol); radius nil for L.
;;; Circle standards use ("RBAND" . (lo hi)) instead of ("BANDS" . ...).

;; ---------------------------------------------------------------- alignment

(defun acady-elems-dev (a b / d ea eb)
  ;; crude total deviation between two same-length elem lists (no rotation)
  (setq d 0.0)
  (mapcar
    '(lambda (ea eb)
       (setq d (+ d
                  (if (= (car ea) (car eb))
                    (+ (abs (- (cadr ea) (cadr eb)))
                       (if (= (car ea) "A")
                         (abs (- (caddr ea) (caddr eb)))
                         0.0))
                    1e9))) ; type mismatch at this slot
       nil)
    a b)
  d)

(defun acady-best-rotation (nom other / n i best bestd d)
  ;; rotate OTHER to best line up with NOM; -> (rotated-elems . total-dev)
  (setq n (length nom) i 0 best nil bestd 1e18)
  (while (< i n)
    (setq d (acady-elems-dev nom (acady-rotate-list other i)))
    (if (< d bestd) (setq bestd d best (acady-rotate-list other i)))
    (setq i (1+ i)))
  (cons best bestd))

;; ---------------------------------------------------------------- bands

(defun acady-uniform-bands (elems ltol rtol atol)
  (mapcar
    '(lambda (e)
       (if (= (car e) "L")
         (list (max 0.0 (- (cadr e) ltol)) (+ (cadr e) ltol) nil nil atol)
         (list (max 0.0 (- (cadr e) ltol)) (+ (cadr e) ltol)
               (max 0.0 (- (caddr e) rtol)) (+ (caddr e) rtol) atol)))
    elems))

(defun acady-geom-bands (nom lo hi atol-floor / bands e el eh)
  ;; per-element bands from aligned MIN (lo) and MAX (hi) elem lists
  (setq bands nil)
  (mapcar
    '(lambda (e el eh)
       (setq bands
         (cons
           (if (= (car e) "L")
             (list (min (cadr el) (cadr eh)) (max (cadr el) (cadr eh))
                   nil nil
                   (max atol-floor
                        (abs (- (caddr el) (caddr e)))
                        (abs (- (caddr eh) (caddr e)))))
             (list (min (cadr el) (cadr eh)) (max (cadr el) (cadr eh))
                   (min (caddr el) (caddr eh)) (max (caddr el) (caddr eh))
                   (max atol-floor
                        (abs (- (last el) (last e)))
                        (abs (- (last eh) (last e))))))
           bands))
       nil)
    nom lo hi)
  ;; widen degenerate (~zero-offset) bands to a small floor — NOT the global
  ;; defaults, which would override intentionally tight drawn tolerances
  (mapcar
    '(lambda (b e / fl)
       (setq fl 0.0625) ; 1/16" minimum half-width
       (list (min (car b) (- (cadr e) fl)) (max (cadr b) (+ (cadr e) fl))
             (if (caddr b) (min (caddr b) (- (caddr e) fl)) nil)
             (if (cadddr b) (max (cadddr b) (+ (caddr e) fl)) nil)
             (nth 4 b)))
    (reverse bands) nom))

;; ---------------------------------------------------------------- TOL= text

(defun acady-parse-tol-text (strs / ltol atol s p v start)
  ;; -> (ltol . atol-rad) or nil; accepts "TOL=0.25" and/or "ATOL=2" anywhere,
  ;; including both in one text string
  (setq ltol nil atol nil)
  (foreach s strs
    (setq s (strcase s))
    (if (setq p (vl-string-search "ATOL=" s))
      (progn
        (setq v (atof (substr s (+ p 6))))
        (if (> v 0.0) (setq atol (/ (* v pi) 180.0)))))
    ;; every "TOL=" whose preceding char is not "A" (i.e. not part of ATOL=)
    (setq start 0)
    (while (setq p (vl-string-search "TOL=" s start))
      (if (or (= p 0) (/= (substr s p 1) "A"))
        (progn
          (setq v (atof (substr s (+ p 5))))
          (if (> v 0.0) (setq ltol v))))
      (setq start (+ p 4))))
  (if ltol (cons ltol atol) nil))

;; ---------------------------------------------------------------- space scan

(defun acady-space->standard (ms / tol-layer nom-layer obj lay kind nomobjs
                                tolobjs toltexts warns nomsig r sigs tolsigs
                                bands src txttol ltol rtol atol circles pair
                                minsig maxsig alo ahi)
  ;; called by acady-dbx-with-doc with a live ModelSpace collection.
  ;; -> (sig tol-alist warnings) or nil when no usable outline.
  (setq tol-layer (strcase (acady-cfg "TOL-LAYER"))
        nom-layer (strcase (acady-cfg "NOM-LAYER"))
        nomobjs nil tolobjs nil toltexts nil warns nil)
  (vlax-for obj ms
    (setq kind (acady-obj-kind obj))
    (setq lay (strcase (vlax-get obj 'Layer)))
    (cond
      ((= lay tol-layer)
       (cond
         ((member kind '(LW 2DPL CIRCLE)) (setq tolobjs (cons obj tolobjs)))
         ((member kind '(TEXT MTEXT))
          (setq toltexts (cons (vlax-get obj 'TextString) toltexts)))))
      ((member kind '(LW 2DPL CIRCLE LINE ARC))
       (setq nomobjs (cons (cons (= lay nom-layer) obj) nomobjs)))
      ((eq kind 'UNSUP)
       (if (not (member (vlax-get obj 'ObjectName) warns))
         (setq warns (cons (strcat "ignored " (vlax-get obj 'ObjectName)) warns))))))
  ;; ---- nominal: prefer NOM-LAYER objects, else everything off-tolerance
  (setq r (acady-objs->sigs
            (mapcar 'cdr (if (vl-some 'car nomobjs)
                           (vl-remove-if-not 'car nomobjs)
                           nomobjs))))
  (setq sigs (vl-remove-if-not
               '(lambda (s) (acady-aget "CLOSED" s))
               (car r)))
  (if (caddr r) (setq warns (cons (caddr r) warns)))
  (cond
    ((null sigs) nil) ; caller reports "no closed outline"
    (t
     (if (> (length sigs) 1)
       (progn
         (setq warns (cons "multiple closed outlines; using largest area" warns))
         (setq sigs (vl-sort sigs
                             '(lambda (a b) (> (acady-aget "AREA" a)
                                               (acady-aget "AREA" b)))))))
     (setq nomsig (car sigs))
     ;; ---- tolerance
     (setq ltol (acady-cfg "TOL-LEN")
           rtol (acady-cfg "TOL-RAD")
           atol (acady-cfg "TOL-ANG"))
     (setq txttol (acady-parse-tol-text toltexts))
     (setq tolsigs
       (vl-remove-if-not '(lambda (s) (acady-aget "CLOSED" s))
                         (car (acady-objs->sigs (reverse tolobjs)))))
     (setq bands nil src nil)
     ;; circle nominal: radius band from tolerance circles
     (if (= (acady-aget "KIND" nomsig) "CIRCLE")
       (progn
         (setq circles (vl-remove-if-not
                         '(lambda (s) (= (acady-aget "KIND" s) "CIRCLE"))
                         tolsigs))
         (cond
           ((>= (length circles) 2)
            (setq src "GEOM"
                  bands (list (apply 'min (mapcar '(lambda (s) (acady-aget "RADIUS" s)) circles))
                              (apply 'max (mapcar '(lambda (s) (acady-aget "RADIUS" s)) circles)))))
           ((= (length circles) 1)
            (setq src "GEOM"
                  r (abs (- (acady-aget "RADIUS" (car circles))
                            (acady-aget "RADIUS" nomsig)))
                  bands (list (- (acady-aget "RADIUS" nomsig) (max r rtol))
                              (+ (acady-aget "RADIUS" nomsig) (max r rtol)))))
           (txttol
            (setq src "TEXT"
                  bands (list (- (acady-aget "RADIUS" nomsig) (car txttol))
                              (+ (acady-aget "RADIUS" nomsig) (car txttol)))))
           (t
            (setq src "GLOBAL"
                  bands (list (- (acady-aget "RADIUS" nomsig) rtol)
                              (+ (acady-aget "RADIUS" nomsig) rtol)))))
         (list nomsig
               (list (cons "RBAND" bands) (cons "BANDSRC" src))
               (reverse warns)))
       ;; loop nominal
       (progn
         (setq tolsigs (vl-remove-if
                         '(lambda (s) (= (acady-aget "KIND" s) "CIRCLE"))
                         tolsigs))
         (cond
           ;; two tolerance outlines with matching element counts
           ((and (>= (length tolsigs) 2)
                 (= (length (acady-aget "ELEMS" (car tolsigs)))
                    (length (acady-aget "ELEMS" nomsig)))
                 (= (length (acady-aget "ELEMS" (cadr tolsigs)))
                    (length (acady-aget "ELEMS" nomsig))))
            (setq pair (vl-sort tolsigs
                                '(lambda (a b) (< (acady-aget "AREA" a)
                                                  (acady-aget "AREA" b)))))
            (setq minsig (car pair) maxsig (last pair))
            (setq alo (acady-best-rotation (acady-aget "ELEMS" nomsig)
                                           (acady-aget "ELEMS" minsig))
                  ahi (acady-best-rotation (acady-aget "ELEMS" nomsig)
                                           (acady-aget "ELEMS" maxsig)))
            (if (and (< (cdr alo) 1e8) (< (cdr ahi) 1e8)) ; no type-mismatch slots
              (setq src "GEOM"
                    bands (acady-geom-bands (acady-aget "ELEMS" nomsig)
                                            (car alo) (car ahi) atol))
              (setq warns (cons "tolerance outlines do not align with nominal" warns))))
           ;; one tolerance outline: symmetric band
           ((and (= (length tolsigs) 1)
                 (= (length (acady-aget "ELEMS" (car tolsigs)))
                    (length (acady-aget "ELEMS" nomsig))))
            (setq alo (acady-best-rotation (acady-aget "ELEMS" nomsig)
                                           (acady-aget "ELEMS" (car tolsigs))))
            (if (< (cdr alo) 1e8)
              (progn
                ;; mirror the single outline's deviation to the other side
                ;; (floor at 1/16" so a ~zero offset still leaves a band)
                (setq bands
                  (mapcar
                    '(lambda (e eo / dl dr)
                       (setq dl (max 0.0625 (abs (- (cadr e) (cadr eo)))))
                       (if (= (car e) "L")
                         (list (- (cadr e) dl) (+ (cadr e) dl)
                               nil nil atol)
                         (progn
                           (setq dr (max 0.0625 (abs (- (caddr e) (caddr eo)))))
                           (list (- (cadr e) dl) (+ (cadr e) dl)
                                 (- (caddr e) dr) (+ (caddr e) dr)
                                 atol))))
                    (acady-aget "ELEMS" nomsig) (car alo)))
                (setq src "GEOM"))
              (setq warns (cons "tolerance outline does not align with nominal" warns))))
           ((> (length tolsigs) 0)
            (setq warns
              (cons (strcat "tolerance outline has "
                            (itoa (length (acady-aget "ELEMS" (car tolsigs))))
                            " elements, nominal has "
                            (itoa (length (acady-aget "ELEMS" nomsig)))
                            " — falling back")
                    warns))))
         ;; fallbacks
         (if (null bands)
           (if txttol
             (setq src "TEXT"
                   bands (acady-uniform-bands (acady-aget "ELEMS" nomsig)
                                              (car txttol) (car txttol)
                                              (if (cdr txttol) (cdr txttol) atol)))
             (setq src "GLOBAL"
                   bands (acady-uniform-bands (acady-aget "ELEMS" nomsig)
                                              ltol rtol atol))))
         (list nomsig
               (list (cons "BANDS" bands) (cons "BANDSRC" src))
               (reverse warns)))))))

(princ "\n[acady] tol loaded.")
(princ)
