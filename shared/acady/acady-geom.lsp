;;; acady-geom.lsp
;;; Shape-signature extraction. Source-agnostic: consumes VLA objects,
;;; whether they came from the editor or from an ObjectDBX document.
;;;
;;; Signature format (alist):
;;;   ("VER" . 1) ("KIND" . "LOOP"|"CIRCLE"|"OPEN") ("CLOSED" . T/nil)
;;;   ("PERIM" . r) ("AREA" . r) ("ELEMS" . (...)) ("RADII" . (...))
;;;   ("LENGTHS" . (...))  and for CIRCLE: ("RADIUS" . r)
;;; Element: ("L" length turn)  |  ("A" arc-length radius sweep turn)
;;; turn = signed tangent change to the NEXT element, in (-pi, pi].
;;;
;;; Internal segment: (p1 p2 bulge)  — 2D points, bulge sign + = CCW.
;;; Internal record:  ("L" len st et) | ("A" alen rad sweep st et)
;;;   st/et = start/end tangent direction (radians, absolute).

(setq *acady-sig-ver* 1)

;; ---------------------------------------------------------------- seg math

(defun acady-seg->rec (seg / p1 p2 b chord ca sweep rad alen)
  ;; segment (p1 p2 bulge) -> record with tangents; nil for zero-length
  (setq p1 (car seg) p2 (cadr seg) b (caddr seg))
  (setq chord (distance p1 p2))
  (if (> chord *acady-eps-len*)
    (progn
      (setq ca (angle p1 p2))
      (if (< (abs b) *acady-eps-ang*)
        (list "L" chord ca ca)
        (progn
          (setq sweep (* 4.0 (atan b)))
          (setq rad (/ chord (* 2.0 (sin (/ (abs sweep) 2.0)))))
          (setq alen (* rad (abs sweep)))
          (list "A" alen rad sweep
                (- ca (/ sweep 2.0))    ; start tangent
                (+ ca (/ sweep 2.0)))))) ; end tangent
    nil))

(defun acady-rec-st (r) (if (= (car r) "L") (caddr r) (nth 4 r)))
(defun acady-rec-et (r) (if (= (car r) "L") (cadddr r) (nth 5 r)))
(defun acady-rec-len (r) (cadr r))

(defun acady-flip-seg (seg)
  ;; reverse traversal direction of (p1 p2 bulge)
  (list (cadr seg) (car seg) (- 0.0 (caddr seg))))

(defun acady-segs-area (segs / a p1 p2 b sweep rad)
  ;; signed area: shoelace over chords + circular-segment corrections
  (setq a 0.0)
  (foreach seg segs
    (setq p1 (car seg) p2 (cadr seg) b (caddr seg))
    (setq a (+ a (/ (- (* (car p1) (cadr p2)) (* (car p2) (cadr p1))) 2.0)))
    (if (>= (abs b) *acady-eps-ang*)
      (progn
        (setq sweep (* 4.0 (atan b)))
        (setq rad (/ (distance p1 p2) (* 2.0 (sin (/ (abs sweep) 2.0)))))
        ;; signed segment area between chord and arc
        (setq a (+ a (* (if (> sweep 0.0) 1.0 -1.0)
                        (/ (* rad rad) 2.0)
                        (- (abs sweep) (sin (abs sweep)))))))))
  a)

;; ---------------------------------------------------------------- merging

(defun acady-mergeable-p (a b / )
  ;; can records a,b (a followed by b) merge into one element?
  (cond
    ((and (= (car a) "L") (= (car b) "L"))
     (acady-fuzzeq 0.0 (acady-norm-ang (- (acady-rec-st b) (acady-rec-et a)))
                   *acady-merge-ang*))
    ((and (= (car a) "A") (= (car b) "A"))
     (and (> (* (nth 3 a) (nth 3 b)) 0.0)               ; same sweep sign
          (acady-fuzzeq (caddr a) (caddr b)
                        (max *acady-eps-len* (* 1e-5 (caddr a)))) ; same radius
          (acady-fuzzeq 0.0 (acady-norm-ang (- (acady-rec-st b) (acady-rec-et a)))
                        *acady-merge-ang*)))            ; tangent-continuous
    (t nil)))

(defun acady-merge-recs (a b)
  (if (= (car a) "L")
    (list "L" (+ (cadr a) (cadr b)) (caddr a) (cadddr b))
    (list "A" (+ (cadr a) (cadr b))
          (/ (+ (caddr a) (caddr b)) 2.0)
          (+ (nth 3 a) (nth 3 b))
          (nth 4 a) (nth 5 b))))

(defun acady-simplify-recs (recs closed / done i n a b out)
  ;; merge collinear lines and co-circular arcs; cyclic when closed
  (setq done nil)
  (while (and (not done) (> (length recs) 1))
    (setq done t i 0 n (length recs))
    (while (and done (< i (if closed n (1- n))))
      (setq a (nth i recs)
            b (nth (rem (1+ i) n) recs))
      (if (acady-mergeable-p a b)
        (progn
          (setq recs
            (if (< (1+ i) n)
              ;; adjacent in list order
              (append (acady-sublist recs 0 i)
                      (list (acady-merge-recs a b))
                      (acady-sublist recs (+ i 2) (- n i 2)))
              ;; wrap pair (last, first)
              (cons (acady-merge-recs a b)
                    (acady-sublist recs 1 (- n 2)))))
          (setq done nil)))
      (setq i (1+ i))))
  recs)

(defun acady-sublist (lst start len / out i)
  (setq i 0)
  (foreach x lst
    (if (and (>= i start) (< i (+ start len)))
      (setq out (cons x out)))
    (setq i (1+ i)))
  (reverse out))

;; ---------------------------------------------------------------- signature

(defun acady-recs->elems (recs closed / n i r nxt turn out)
  ;; attach turns, strip tangents
  (setq n (length recs) i 0)
  (while (< i n)
    (setq r (nth i recs))
    (setq turn
      (if (and (not closed) (= i (1- n)))
        0.0
        (progn
          (setq nxt (nth (rem (1+ i) n) recs))
          (acady-norm-ang (- (acady-rec-st nxt) (acady-rec-et r))))))
    (setq out
      (cons (if (= (car r) "L")
              (list "L" (cadr r) turn)
              (list "A" (cadr r) (caddr r) (nth 3 r) turn))
            out))
    (setq i (1+ i)))
  (reverse out))

(defun acady-elem-key (e)
  ;; numeric key for canonical-start ordering
  (if (= (car e) "L")
    (list 0.0 (cadr e) 0.0 0.0)
    (list 1.0 (cadr e) (caddr e) (cadddr e))))

(defun acady-keyseq> (a b / res)
  ;; lexicographic > over flattened key lists
  (setq res nil)
  (while (and a b (null res))
    (cond ((> (car a) (car b)) (setq res 'GT))
          ((< (car a) (car b)) (setq res 'LT))
          (t (setq a (cdr a) b (cdr b)))))
  (eq res 'GT))

(defun acady-canon-start (elems / n best bestk i cand candk)
  ;; rotate cyclic list to lexicographically greatest key sequence
  (setq n (length elems) best elems
        bestk (apply 'append (mapcar 'acady-elem-key elems))
        i 1)
  (while (< i n)
    (setq cand (acady-rotate-list elems i)
          candk (apply 'append (mapcar 'acady-elem-key cand)))
    (if (acady-keyseq> candk bestk)
      (setq best cand bestk candk))
    (setq i (1+ i)))
  best)

(defun acady-segs->sig (segs closed / recs area elems radii lens perim)
  ;; segments -> full signature; nil if nothing usable
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) *acady-eps-len*))
               segs))
  (if segs
    (progn
      ;; orient CCW, then recompute records from the reversed segs
      (if closed
        (progn
          (setq area (acady-segs-area segs))
          (if (< area 0.0)
            (setq segs (reverse (mapcar 'acady-flip-seg segs))
                  area (- 0.0 area)))))
      (setq recs (vl-remove nil (mapcar 'acady-seg->rec segs)))
      (setq recs (acady-simplify-recs recs closed))
      (setq elems (acady-recs->elems recs closed))
      (if closed (setq elems (acady-canon-start elems)))
      (setq perim (acady-sum (mapcar 'cadr elems)))
      (setq radii (acady-sort-desc
                    (mapcar 'caddr
                            (vl-remove-if '(lambda (e) (= (car e) "L")) elems))))
      (setq lens (acady-sort-desc
                   (mapcar 'cadr
                           (vl-remove-if '(lambda (e) (= (car e) "A")) elems))))
      ;; sanity: closed CCW loop must have total turning ~ +2pi
      (if closed
        (progn
          (setq *acady-turnsum*
            (+ (acady-sum (mapcar '(lambda (e) (last e)) elems))
               (acady-sum (mapcar '(lambda (e) (if (= (car e) "A") (cadddr e) 0.0))
                                  elems))))
          (if (not (acady-fuzzeq *acady-turnsum* *acady-pi2* 0.01))
            (acady-dbg (strcat "turn-sum sanity check off: "
                               (rtos *acady-turnsum* 2 4))))))
      (list (cons "VER" *acady-sig-ver*)
            (cons "KIND" (if closed "LOOP" "OPEN"))
            (cons "CLOSED" closed)
            (cons "PERIM" perim)
            (cons "AREA" (if closed area 0.0))
            (cons "ELEMS" elems)
            (cons "RADII" radii)
            (cons "LENGTHS" lens)))
    nil))

(defun acady-circle-sig (r)
  (list (cons "VER" *acady-sig-ver*)
        (cons "KIND" "CIRCLE")
        (cons "CLOSED" t)
        (cons "PERIM" (* *acady-pi2* r))
        (cons "AREA" (* pi r r))
        (cons "RADIUS" r)
        (cons "ELEMS" nil)
        (cons "RADII" (list r))
        (cons "LENGTHS" nil)))

;; ---------------------------------------------------------------- VLA -> segs

(defun acady-pt2 (p) (list (car p) (cadr p)))

(defun acady-vla-coords (obj) (vlax-get obj 'Coordinates))

(defun acady-lw->segs (obj / co n pts i closed segs p1 p2)
  ;; AcDbPolyline: flat 2D coordinate list
  (setq co (acady-vla-coords obj) pts nil i 0)
  (while (< i (length co))
    (setq pts (cons (list (nth i co) (nth (1+ i) co)) pts))
    (setq i (+ i 2)))
  (setq pts (reverse pts))
  (acady-pts->segs obj pts))

(defun acady-2dpl->segs (obj / co pts i)
  ;; AcDb2dPolyline: flat 3D coordinate list
  (setq co (acady-vla-coords obj) pts nil i 0)
  (while (< i (length co))
    (setq pts (cons (list (nth i co) (nth (1+ i) co)) pts))
    (setq i (+ i 3)))
  (setq pts (reverse pts))
  (acady-pts->segs obj pts))

(defun acady-vla-bool (v)
  ;; VARIANT_BOOL arrives as -1, T, or :vlax-true depending on host/version
  (cond ((eq v t) t) ((eq v :vlax-true) t) ((and (numberp v) (/= v 0)) t) (t nil)))

(defun acady-pts->segs (obj pts / n closed segs i p1 p2)
  ;; shared: points + per-vertex GetBulge -> ((closed . flag) seg...)
  (setq n (length pts))
  (setq closed (acady-vla-bool (vlax-get obj 'Closed)))
  ;; physically-closed but flag off -> treat as closed, drop dup vertex
  (if (and (not closed) (> n 2)
           (<= (distance (car pts) (last pts)) *acady-eps-len*))
    (setq closed t
          pts (reverse (cdr (reverse pts)))
          n (1- n)))
  (setq segs nil i 0)
  (while (< i (if closed n (1- n)))
    (setq p1 (nth i pts)
          p2 (nth (rem (1+ i) n) pts))
    (setq segs (cons (list p1 p2 (vlax-invoke obj 'GetBulge i)) segs))
    (setq i (1+ i)))
  (cons closed (reverse segs)))

(defun acady-line->seg (obj)
  (list (acady-pt2 (vlax-get obj 'StartPoint))
        (acady-pt2 (vlax-get obj 'EndPoint))
        0.0))

(defun acady-arc->seg (obj / c r a1 a2 sweep)
  ;; ARC entity is always CCW from StartAngle to EndAngle
  (setq c (vlax-get obj 'Center)
        r (vlax-get obj 'Radius)
        a1 (vlax-get obj 'StartAngle)
        a2 (vlax-get obj 'EndAngle))
  (setq sweep (- a2 a1))
  (while (<= sweep 0.0) (setq sweep (+ sweep *acady-pi2*)))
  (list (list (+ (car c) (* r (cos a1))) (+ (cadr c) (* r (sin a1))))
        (list (+ (car c) (* r (cos a2))) (+ (cadr c) (* r (sin a2))))
        (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0))))) ; tan(sweep/4)

;; ---------------------------------------------------------------- chaining

(defun acady-pteq (a b) (<= (distance a b) *acady-eps-len*))

(defun acady-chain-segs (segs / chains chain tail head cand found closed err)
  ;; chain loose (p1 p2 bulge) segments into paths by endpoint proximity.
  ;; returns (list-of (closed . segs)) or ('ERR msg)
  (setq chains nil err nil)
  (while (and segs (null err))
    (setq chain (list (car segs)) segs (cdr segs) closed nil)
    ;; grow at tail
    (setq found t)
    (while (and found (not closed))
      (setq tail (cadr (last chain)) found nil)
      (if (acady-pteq tail (car (car chain)))
        (setq closed (> (length chain) 1))
        (progn
          (setq cand (vl-remove-if-not
                       '(lambda (s) (or (acady-pteq (car s) tail)
                                        (acady-pteq (cadr s) tail)))
                       segs))
          (cond
            ((> (length cand) 1)
             (setq err "geometry branches (3+ ends meet); select a single outline"))
            ((= (length cand) 1)
             (setq segs (vl-remove (car cand) segs))
             (setq chain (append chain
                                 (list (if (acady-pteq (car (car cand)) tail)
                                         (car cand)
                                         (acady-flip-seg (car cand))))))
             (setq found t))))))
    ;; grow at head (open chains only)
    (if (and (null err) (not closed))
      (progn
        (setq found t)
        (while found
          (setq head (car (car chain)) found nil)
          (setq cand (vl-remove-if-not
                       '(lambda (s) (or (acady-pteq (car s) head)
                                        (acady-pteq (cadr s) head)))
                       segs))
          (cond
            ((> (length cand) 1)
             (setq err "geometry branches (3+ ends meet); select a single outline")
             (setq found nil))
            ((= (length cand) 1)
             (setq segs (vl-remove (car cand) segs))
             (setq chain (cons (if (acady-pteq (cadr (car cand)) head)
                                 (car cand)
                                 (acady-flip-seg (car cand)))
                               chain))
             (setq found t))))
        ;; head growth may have closed the loop
        (if (acady-pteq (cadr (last chain)) (car (car chain)))
          (setq closed t))))
    (if (null err) (setq chains (cons (cons closed chain) chains))))
  (if err (list 'ERR err) (reverse chains)))

;; ---------------------------------------------------------------- top level

(defun acady-obj-kind (obj / on)
  (setq on (vlax-get obj 'ObjectName))
  (cond
    ((= on "AcDbPolyline") 'LW)
    ((= on "AcDb2dPolyline")
     (if (= (vlax-get obj 'Type) 0) '2DPL 'UNSUP)) ; simple poly only
    ((= on "AcDbCircle") 'CIRCLE)
    ((= on "AcDbLine") 'LINE)
    ((= on "AcDbArc") 'ARC)
    ((= on "AcDbText") 'TEXT)
    ((= on "AcDbMText") 'MTEXT)
    (t 'UNSUP)))

(defun acady-objs->sigs (objs / loose sigs skipped k r chains)
  ;; list of VLA objects -> (sigs skipped-names err-or-nil)
  ;; polylines/circles become sigs directly; lines+arcs are chained.
  (setq loose nil sigs nil skipped nil)
  (foreach obj objs
    (setq k (acady-obj-kind obj))
    (cond
      ((eq k 'LW)
       (setq r (acady-lw->segs obj))
       (setq sigs (cons (acady-segs->sig (cdr r) (car r)) sigs)))
      ((eq k '2DPL)
       (setq r (acady-2dpl->segs obj))
       (setq sigs (cons (acady-segs->sig (cdr r) (car r)) sigs)))
      ((eq k 'CIRCLE)
       (setq sigs (cons (acady-circle-sig (vlax-get obj 'Radius)) sigs)))
      ((eq k 'LINE) (setq loose (cons (acady-line->seg obj) loose)))
      ((eq k 'ARC)  (setq loose (cons (acady-arc->seg obj) loose)))
      ((member k '(TEXT MTEXT)) nil) ; silently ignore notes
      (t (setq skipped (cons (vlax-get obj 'ObjectName) skipped)))))
  (if loose
    (progn
      (setq chains (acady-chain-segs (reverse loose)))
      (if (eq (car chains) 'ERR)
        (list (vl-remove nil (reverse sigs)) skipped (cadr chains))
        (progn
          (foreach ch chains
            (setq sigs (cons (acady-segs->sig (cdr ch) (car ch)) sigs)))
          (list (vl-remove nil (reverse sigs)) skipped nil))))
    (list (vl-remove nil (reverse sigs)) skipped nil)))

;; Mirrored form of a CCW-normalized closed loop, itself re-normalized to CCW:
;; element ORDER reverses; sweep/turn signs are UNCHANGED (mirroring negates
;; them, re-orienting back to CCW negates them again — chirality lives purely
;; in the sequence order). The turn following mirrored elem k is the turn that
;; was attached to the source of mirrored elem k+1. Validated numerically.
;; For OPEN paths this produces the reversed traversal (turns DO negate there,
;; since no re-orientation happens); last turn is 0.
(defun acady-sig-mirror (sig / elems closed out n e nxt)
  (setq elems (acady-aget "ELEMS" sig)
        closed (acady-aget "CLOSED" sig))
  (if (null elems)
    sig ; circle: mirror is identical
    (progn
      (setq out (reverse elems))
      (setq out
        (mapcar '(lambda (e nxt)
                   (if (= (car e) "L")
                     (list "L" (cadr e)
                           (if closed (caddr nxt) (- 0.0 (caddr nxt))))
                     (list "A" (cadr e) (caddr e)
                           (if closed (cadddr e) (- 0.0 (cadddr e)))
                           (if closed (last nxt) (- 0.0 (last nxt))))))
                out (acady-rotate-list out 1)))
      (if (not closed)
        (progn
          (setq n (1- (length out)))
          (setq out
            (append (acady-sublist out 0 n)
                    (list (if (= (car (last out)) "L")
                            (list "L" (cadr (last out)) 0.0)
                            (list "A" (cadr (last out)) (caddr (last out))
                                  (cadddr (last out)) 0.0)))))))
      (acady-aput "ELEMS" out sig))))

;; -------------------------------------------------------- signature printing

(defun acady-print-sig (sig / e)
  (if sig
    (progn
      (acady-log (strcat "kind=" (acady-aget "KIND" sig)
                         "  elems=" (itoa (length (acady-aget "ELEMS" sig)))
                         "  perim=" (acady-fmt-len (acady-aget "PERIM" sig))))
      (if (= (acady-aget "KIND" sig) "CIRCLE")
        (acady-log (strcat "  circle R=" (acady-fmt-len (acady-aget "RADIUS" sig))))
        (foreach e (acady-aget "ELEMS" sig)
          (if (= (car e) "L")
            (acady-log (strcat "  L len=" (acady-fmt-len (cadr e))
                               "  turn=" (angtos (caddr e) 0 2)))
            (acady-log (strcat "  A r=" (acady-fmt-len (caddr e))
                               "  arclen=" (acady-fmt-len (cadr e))
                               "  sweep=" (angtos (abs (cadddr e)) 0 2)
                               (if (< (cadddr e) 0.0) " (CW)" " (CCW)")
                               "  turn=" (angtos (last e) 0 2)))))))
    (acady-log "  <no signature>"))
  (princ))

(princ "\n[acady] geom loaded.")
(princ)
