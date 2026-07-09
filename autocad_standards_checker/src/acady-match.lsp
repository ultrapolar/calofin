;;; acady-match.lsp
;;; Compare a candidate signature against the scanned standards.
;;; Tier 1: full cyclic alignment, every element inside its tolerance band.
;;; Tier 2: feature (multiset) matching of radii + lengths — catches the
;;;         "lone 8'-6\" corner looks like a PACIFIC" case.
;;; Result record (alist):
;;;   ("NAME") ("TIER" 1|2) ("LABEL" "MATCH"|"CLOSE"|"POSSIBLE") ("SCORE")
;;;   ("SUMMARY") ("DETAILS" list-of-strings) ("MRADII") ("MLENS") ("WARNS")

;; ---------------------------------------------------------------- tier 1

(defun acady-elem-band-dev (ce ne band / dl dr dt)
  ;; -> (in-band-p . center-usage 0..1+) for candidate elem vs nominal+band
  (if (/= (car ce) (car ne))
    (cons nil 9.9)
    (progn
      (setq dl (acady-clamp-dev (cadr ce) (car band) (cadr band)))
      (setq dr (if (= (car ce) "A")
                 (acady-clamp-dev (caddr ce) (caddr band) (cadddr band))
                 0.0))
      (setq dt (max 0.0 (- (abs (acady-norm-ang (- (last ce) (last ne))))
                           (nth 4 band))))
      (cons (and (= dl 0.0) (= dr 0.0) (= dt 0.0))
            (max (acady-band-center-dev (cadr ce) (car band) (cadr band))
                 (if (= (car ce) "A")
                   (acady-band-center-dev (caddr ce) (caddr band) (cadddr band))
                   0.0))))))

(defun acady-try-alignment (celems nelems bands / n i r inb use devs)
  ;; -> (in-count score per-elem-flags)
  (setq n (length nelems) inb 0 use 0.0 devs nil i 0)
  (while (< i n)
    (setq r (acady-elem-band-dev (nth i celems) (nth i nelems) (nth i bands)))
    (if (car r) (setq inb (1+ inb)))
    (setq use (+ use (min 1.0 (cdr r))))
    (setq devs (cons (car r) devs))
    (setq i (1+ i)))
  (list inb
        (max 0.0 (- 1.0 (/ use (float n))))
        (reverse devs)))

(defun acady-tier1 (csig entry / nsig tol nelems bands n cands best r rot mir
                        celems k)
  ;; -> (in-count score flags celems-aligned) best over rotations x mirror,
  ;;    or nil when tier 1 is not applicable
  (setq nsig (acady-entry-get entry 'SIG)
        tol (acady-entry-get entry 'TOL)
        nelems (acady-aget "ELEMS" nsig)
        bands (acady-aget "BANDS" tol))
  (cond
    ;; circles compare directly on the radius band
    ((and (= (acady-aget "KIND" csig) "CIRCLE")
          (= (acady-aget "KIND" nsig) "CIRCLE"))
     (setq r (acady-aget "RADIUS" csig)
           bands (acady-aget "RBAND" tol))
     (if (and (>= r (car bands)) (<= r (cadr bands)))
       (list 1 (- 1.0 (min 1.0 (acady-band-center-dev r (car bands) (cadr bands))))
             (list t) nil)
       (list 0 0.0 (list nil) nil)))
    ((or (/= (acady-aget "KIND" csig) "LOOP")
         (/= (acady-aget "KIND" nsig) "LOOP")
         (/= (length (acady-aget "ELEMS" csig)) (length nelems)))
     nil)
    ;; perimeter prefilter: total slack = sum of length band widths
    ((> (abs (- (acady-aget "PERIM" csig) (acady-aget "PERIM" nsig)))
        (acady-sum (mapcar '(lambda (b) (- (cadr b) (car b))) bands)))
     nil)
    (t
     (setq n (length nelems) best nil)
     (foreach mir (list csig (acady-sig-mirror csig))
       (setq celems (acady-aget "ELEMS" mir) k 0)
       (while (< k n)
         (setq rot (acady-rotate-list celems k))
         (setq r (acady-try-alignment rot nelems bands))
         (if (or (null best)
                 (> (car r) (car best))
                 (and (= (car r) (car best)) (> (cadr r) (cadr best))))
           (setq best (append r (list rot))))
         (setq k (1+ k))))
     best)))

;; ---------------------------------------------------------------- tier 2

(defun acady-feature-bands (entry / tol nsig bands rads lens rt lt)
  ;; reference features with their bands: ((nom lo hi) ...) for radii, lengths.
  ;; Tier 2 is the fuzzy "could be a PACIFIC" net, so bands are widened to at
  ;; least the global defaults (e.g. radius +/-6" -> 8'-9' catches 8'-6").
  (setq tol (acady-entry-get entry 'TOL)
        nsig (acady-entry-get entry 'SIG)
        rt (acady-cfg "TOL-RAD")
        lt (acady-cfg "TOL-LEN"))
  (if (= (acady-aget "KIND" nsig) "CIRCLE")
    (list (list (cons (acady-aget "RADIUS" nsig)
                      (list (min (car (acady-aget "RBAND" tol))
                                 (- (acady-aget "RADIUS" nsig) rt))
                            (max (cadr (acady-aget "RBAND" tol))
                                 (+ (acady-aget "RADIUS" nsig) rt)))))
          nil)
    (progn
      (setq rads nil lens nil)
      (mapcar
        '(lambda (e b)
           (if (= (car e) "A")
             (setq rads (cons (cons (caddr e)
                                    (list (min (caddr b) (- (caddr e) rt))
                                          (max (cadddr b) (+ (caddr e) rt))))
                              rads))
             (setq lens (cons (cons (cadr e)
                                    (list (min (car b) (- (cadr e) lt))
                                          (max (cadr b) (+ (cadr e) lt))))
                              lens)))
           nil)
        (acady-aget "ELEMS" nsig) (acady-aget "BANDS" tol))
      (list (reverse rads) (reverse lens)))))

(defun acady-greedy-pair (cand feats / used matched f best bestd c d)
  ;; greedy nearest pairing of candidate values against ((nom lo hi) ...)
  ;; -> list of matched candidate values
  (setq used nil matched nil)
  (foreach f feats
    (setq best nil bestd 1e18)
    (foreach c cand
      (if (and (not (member c used))
               (>= c (car (cadr f))) (<= c (cadr (cadr f))))
        (progn
          (setq d (abs (- c (car f))))
          (if (< d bestd) (setq bestd d best c)))))
    (if best (setq used (cons best used) matched (cons best matched))))
  (reverse matched))

(defun acady-tier2 (csig entry / fb rfeats lfeats crads clens mr ml nr nl score)
  ;; -> (score matched-radii matched-lengths) or nil below threshold
  (setq fb (acady-feature-bands entry)
        rfeats (car fb) lfeats (cadr fb)
        crads (acady-aget "RADII" csig)
        clens (acady-aget "LENGTHS" csig))
  (setq mr (acady-greedy-pair crads rfeats)
        ml (acady-greedy-pair clens lfeats))
  (setq nr (max (length crads) (length rfeats) 1)
        nl (max (length clens) (length lfeats) 1))
  (setq score (+ (* 0.7 (/ (float (length mr)) nr))
                 (* 0.3 (/ (float (length ml)) nl))))
  ;; report only when there's real signal
  (if (and (or (> (length mr) 0)
               (and lfeats (>= (/ (float (length ml)) nl) 0.6)))
           (>= score (acady-cfg "T2-THRESH")))
    (list score mr ml)
    nil))

;; ---------------------------------------------------------------- details

(defun acady-detail-rows (celems entry flags / nsig bands rows i e ne b n)
  ;; fixed-width comparison rows for the aligned tier-1 result
  (setq nsig (acady-entry-get entry 'SIG)
        bands (acady-aget "BANDS" (acady-entry-get entry 'TOL))
        n (length celems) rows nil i 0)
  (while (< i n)
    (setq e (nth i celems)
          ne (nth i (acady-aget "ELEMS" nsig))
          b (nth i bands))
    (setq rows
      (cons
        (strcat
          (acady-pad (car e) 3)
          (acady-pad (if (= (car e) "A")
                       (strcat "r=" (acady-fmt-len (caddr e)))
                       (strcat "len=" (acady-fmt-len (cadr e))))
                     16)
          (acady-pad (strcat "std "
                             (if (= (car ne) "A")
                               (acady-fmt-len (caddr ne))
                               (acady-fmt-len (cadr ne))))
                     16)
          (if (nth i flags) "OK" "OFF"))
        rows))
    (setq i (1+ i)))
  (reverse rows))

;; ---------------------------------------------------------------- run + rank

(defun acady-match-one (csig entry / name t1 t2 n inb res)
  (setq name (strcase (vl-filename-base (car entry))))
  (setq t1 (acady-tier1 csig entry))
  (setq n (if t1 (length (caddr t1)) 0)
        inb (if t1 (car t1) 0))
  (cond
    ((and t1 (= inb n) (> n 0))
     (list (cons "NAME" name) (cons "TIER" 1) (cons "LABEL" "MATCH")
           (cons "SCORE" (cadr t1))
           (cons "SUMMARY" (strcat "all " (itoa n) " element(s) within tolerance"))
           (cons "DETAILS" (if (cadddr t1)
                             (acady-detail-rows (cadddr t1) entry (caddr t1))
                             nil))
           (cons "MRADII" (acady-aget "RADII" csig))
           (cons "MLENS" nil)
           (cons "WARNS" (acady-entry-get entry 'WARN))))
    ;; 60%: a single dimensional change on a closed loop moves >=2 elements
    ;; out of band, so 80% would never fire on simple 4-6 element shapes
    ((and t1 (>= (/ (float inb) (max n 1)) 0.6))
     (list (cons "NAME" name) (cons "TIER" 1) (cons "LABEL" "CLOSE")
           (cons "SCORE" (cadr t1))
           (cons "SUMMARY" (strcat (itoa inb) " of " (itoa n)
                                   " elements within tolerance"))
           (cons "DETAILS" (if (cadddr t1)
                             (acady-detail-rows (cadddr t1) entry (caddr t1))
                             nil))
           (cons "MRADII" nil)
           (cons "MLENS" nil)
           (cons "WARNS" (acady-entry-get entry 'WARN))))
    ((setq t2 (acady-tier2 csig entry))
     (list (cons "NAME" name) (cons "TIER" 2) (cons "LABEL" "POSSIBLE")
           (cons "SCORE" (car t2))
           (cons "SUMMARY"
                 (strcat
                   (if (cadr t2)
                     (strcat (itoa (length (cadr t2))) " radius match(es): "
                             (acady-str-join (mapcar 'acady-fmt-len (cadr t2)) ", "))
                     "")
                   (if (and (cadr t2) (caddr t2)) "; " "")
                   (if (caddr t2)
                     (strcat (itoa (length (caddr t2))) " length match(es)")
                     "")))
           (cons "DETAILS" nil)
           (cons "MRADII" (cadr t2))
           (cons "MLENS" (caddr t2))
           (cons "WARNS" (acady-entry-get entry 'WARN))))
    (t nil)))

(defun acady-label-rank (r)
  (cond ((= (acady-aget "LABEL" r) "MATCH") 0)
        ((= (acady-aget "LABEL" r) "CLOSE") 1)
        (t 2)))

(defun acady-match-run (csig entries / results r)
  (setq results nil)
  (foreach entry entries
    (setq r (acady-match-one csig entry))
    (if r (setq results (cons r results))))
  (vl-sort results
           '(lambda (a b)
              (if (= (acady-label-rank a) (acady-label-rank b))
                (> (acady-aget "SCORE" a) (acady-aget "SCORE" b))
                (< (acady-label-rank a) (acady-label-rank b))))))

;; ---------------------------------------------------------------- command

(defun acady-pick-candidate (sigs / closed)
  ;; several paths selected -> use the largest closed loop
  (setq closed (vl-remove-if-not '(lambda (s) (acady-aget "CLOSED" s)) sigs))
  (if closed
    (car (vl-sort closed '(lambda (a b) (> (acady-aget "AREA" a)
                                           (acady-aget "AREA" b)))))
    (car sigs)))

(defun acady-result-line (r)
  (strcat (acady-pad (acady-aget "LABEL" r) 9)
          (acady-pad (acady-aget "NAME" r) 18)
          (acady-pad (acady-fmt-pct (acady-aget "SCORE" r)) 6)
          (acady-aget "SUMMARY" r)))

(defun c:MATCHSTD (/ sel sigs csig entries results)
  (setq sel (acady-selection-sigs))
  (cond
    ((cdr sel) (acady-log (strcat "error: " (cdr sel))))
    ((null (car sel)) (acady-log "no usable geometry in selection."))
    (t
     (setq sigs (car sel))
     (if (> (length sigs) 1)
       (acady-log (strcat (itoa (length sigs))
                          " paths selected — checking the largest closed loop.")))
     (setq csig (acady-pick-candidate sigs))
     (setq entries (acady-scan-standards nil))
     (if entries
       (progn
         (setq results (acady-match-run csig entries))
         (if results
           (if acady-ui-show
             (acady-ui-show results csig)
             (progn
               (acady-log "ranked results:")
               (foreach r results (acady-log (strcat "  " (acady-result-line r))))))
           (acady-log "no standard matches this shape."))))))
  (princ))

(princ "\n[acady] match loaded.")
(princ)
