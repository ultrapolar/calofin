;;; ===================================================================
;;; WCALST.lsp -- straighten a curved constant-width "ladder" band
;;; -------------------------------------------------------------------
;;; Command: WCALST
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;; Select a band drawn as two long curved sides connected by rungs,
;;; click the side that must come out straight, and the command draws
;;; the developed (unrolled) band below the selection:
;;;
;;;   * the chosen side as one straight line (layer AIR-B, red)
;;;   * the opposite side as its rigidly unrolled, slightly wavy chain
;;;     (kept on its original layer)
;;;   * DARTS  -- V cutouts where unrolling creates excess material
;;;   * INSERTS -- straight slits plus a loose sliver piece drawn below
;;;     the band where unrolling opens a gap
;;;   * band-height dimensions at both ends (layer DIMENSION)
;;;
;;; Darts + inserts are capped (default 20): the required correction is
;;; accumulated along the band and only released when it reaches a
;;; minimum useful width, so the cut count stays conservative.
;;;
;;; Tested with AutoCAD 2018; plain AutoLISP, no VLX / ObjectARX.
;;; Load with APPLOAD, then run WCALST.
;;; ===================================================================

;;; ------------------------ small math helpers ----------------------

(setq *wcalst-version* "v1.6")   ; announced on load; release_lisp.py
                                    ; stamps the dated twin in releases/

(defun wc:key (p)
  ;; fuzzy node key so touching endpoints share one node
  (strcat (rtos (car p) 2 3) "," (rtos (cadr p) 2 3))
)

(defun wc:turn (d0 d1 / d)
  ;; signed turn angle normalized to (-pi, pi]
  (setq d (- d1 d0))
  (while (> d pi) (setq d (- d pi pi)))
  (while (<= d (- pi)) (setq d (+ d pi pi)))
  d
)

(defun wc:dir (a b)
  ;; direction angle of a->b
  (atan (- (cadr b) (cadr a)) (- (car b) (car a)))
)

;;; ------------------------- segment soup ---------------------------

(defun wc:ent-points (en / ed et pts sub sd closed)
  ;; ordered vertex list of a LINE / LWPOLYLINE / POLYLINE
  (setq ed (entget en)
        et (cdr (assoc 0 ed))
        pts nil
  )
  (cond
    ((= et "LINE")
     (setq pts (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))
    )
    ((= et "LWPOLYLINE")
     (foreach g ed
       (if (= (car g) 10) (setq pts (cons (cdr g) pts)))
     )
     (setq pts (reverse pts))
     (if (= 1 (logand 1 (if (assoc 70 ed) (cdr (assoc 70 ed)) 0)))
       (setq pts (append pts (list (car pts))))
     )
    )
    ((= et "POLYLINE")
     (setq closed (= 1 (logand 1 (if (assoc 70 ed) (cdr (assoc 70 ed)) 0)))
           sub (entnext en)
     )
     (while (and sub (= "VERTEX" (cdr (assoc 0 (setq sd (entget sub))))))
       ;; keep on-curve vertices, skip spline frame control points
       (if (= 0 (logand 16 (cdr (assoc 70 sd))))
         (setq pts (cons (cdr (assoc 10 sd)) pts))
       )
       (setq sub (entnext sub))
     )
     (setq pts (reverse pts))
     (if (and closed pts) (setq pts (append pts (list (car pts)))))
    )
  )
  ;; force 2D
  (mapcar '(lambda (p) (list (car p) (cadr p))) pts)
)

(defun wc:build-segs (ss / i en pts a segs lay)
  ;; -> list of (ptA ptB layer ename), one entry per 2-point segment
  (setq i 0 segs nil)
  (while (< i (sslength ss))
    (setq en  (ssname ss i)
          lay (cdr (assoc 8 (entget en)))
          pts (wc:ent-points en)
    )
    (while (cdr pts)
      (setq a (car pts) pts (cdr pts))
      (if (> (distance a (car pts)) 1.0e-6)
        (setq segs (cons (list a (car pts) lay en) segs))
      )
    )
    (setq i (1+ i))
  )
  (reverse segs)
)

(defun wc:build-nodes (segs / nodes i k e)
  ;; -> assoc list (key . (segidx ...))
  (setq nodes nil i 0)
  (foreach sg segs
    (foreach p (list (car sg) (cadr sg))
      (setq k (wc:key p)
            e (assoc k nodes)
      )
      (if e
        (setq nodes (subst (cons k (cons i (cdr e))) e nodes))
        (setq nodes (cons (list k i) nodes))
      )
    )
    (setq i (1+ i))
  )
  nodes
)

(defun wc:other-end (sg p)
  ;; endpoint of segment sg that is not (fuzzy-)equal to p
  (if (equal (wc:key (car sg)) (wc:key p))
    (cadr sg)
    (car sg)
  )
)

;;; -------------------------- chain tracing -------------------------

(defun wc:trace (segs nodes seed toward / cur p q ids pts cands best
                 bestang j sg r ang d0 stop)
  ;; walk from segment SEED through endpoint TOWARD, always taking the
  ;; straightest continuation; stop when the best turn exceeds 60 deg.
  ;; -> (ids . pts)  ids = seg indices walked (seed first),
  ;;                 pts = nodes visited (start node first)
  (setq cur seed
        p   (wc:other-end (nth seed segs) toward)
        q   toward
        ids (list seed)
        pts (list q p)                  ; reversed order, start last
        stop nil
  )
  (while (not stop)
    (setq d0 (wc:dir p q)
          cands (cdr (assoc (wc:key q) nodes))
          best nil
          bestang nil
    )
    (foreach j cands
      (if (/= j cur)
        (progn
          (setq sg (nth j segs)
                r (wc:other-end sg q)
                ang (abs (wc:turn d0 (wc:dir q r)))
          )
          (if (or (not bestang) (< ang bestang))
            (setq bestang ang best j)
          )
        )
      )
    )
    (if (or (not best) (> bestang 1.0472) (> (length ids) 5000)) ; 60 deg
      (setq stop T)
      (setq ids (cons best ids)
            p q
            cur best
            q (wc:other-end (nth best segs) q)
            pts (cons q pts)
      )
    )
  )
  (cons (reverse ids) (reverse pts))
)

(defun wc:full-chain (segs nodes seed / sg r1 r2)
  ;; trace both directions from SEED -> (ids . pts) covering the whole side
  (setq sg (nth seed segs)
        r1 (wc:trace segs nodes seed (car sg))   ; towards first endpoint
        r2 (wc:trace segs nodes seed (cadr sg))  ; towards second endpoint
  )
  ;; r1 pts = (B A ...towards a-side); r2 pts = (A B ...towards b-side)
  (cons
    (append (reverse (cdr (car r1))) (car r2))       ; ids, seed once
    (append (reverse (cdr r1)) (cddr (cdr r2)))      ; pts, join at A B
  )
)

;;; --------------------------- development --------------------------

(defun wc:member-key (p keys)
  (member (wc:key p) keys)
)

(defun wc:dev-point (fp pts s / k n A B ax ay L2 tt cx cy d2 bk bt bd
                     d c sn dx dy)
  ;; project FP on the chain, develop it with the transform of the
  ;; nearest chain segment -> (devx devy proj-s proj-dist original-pt)
  (setq k 0 n (1- (length pts)) bd 1.0e18 bk 0 bt 0.0)
  (while (< k n)
    (setq A (nth k pts) B (nth (1+ k) pts)
          ax (- (car B) (car A)) ay (- (cadr B) (cadr A))
          L2 (+ (* ax ax) (* ay ay))
          tt (if (< L2 1.0e-12)
               0.0
               (/ (+ (* (- (car fp) (car A)) ax)
                     (* (- (cadr fp) (cadr A)) ay))
                  L2)
             )
          tt (max 0.0 (min 1.0 tt))
          cx (+ (car A) (* tt ax)) cy (+ (cadr A) (* tt ay))
          d2 (+ (expt (- (car fp) cx) 2) (expt (- (cadr fp) cy) 2))
    )
    (if (< d2 bd) (setq bd d2 bk k bt tt))
    (setq k (1+ k))
  )
  (setq A (nth bk pts) B (nth (1+ bk) pts)
        d (wc:dir A B)
        c (cos (- d)) sn (sin (- d))
        dx (- (car fp) (car A)) dy (- (cadr fp) (cadr A))
  )
  (list
    (+ (nth bk s) (- (* dx c) (* dy sn)))
    (+ (* dx sn) (* dy c))
    (+ (nth bk s) (* bt (- (nth (1+ bk) s) (nth bk s))))
    (sqrt bd)
    fp
  )
)

;;; ---------------------------- drawing -----------------------------

(defun wc:line (a b lay)
  (entmake
    (list '(0 . "LINE") (cons 8 lay)
          (list 10 (car a) (cadr a) 0.0)
          (list 11 (car b) (cadr b) 0.0)
    )
  )
)

(defun wc:pline (pts lay closed)
  (entmake
    (append
      (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 lay)
            '(100 . "AcDbPolyline") (cons 90 (length pts))
            (cons 70 (if closed 1 0))
      )
      (mapcar '(lambda (p) (cons 10 (list (car p) (cadr p)))) pts)
    )
  )
)

(defun wc:emit (idebt rungs pts s wmin maxfeat carry / feats acc k fsum
                cw f fdev)
  ;; walk the per-interval correction debt, releasing a dart (mouth
  ;; capped at 4") or an insert whenever the accumulator reaches WMIN.
  ;; CARRY non-nil: the un-released remainder carries to the next rung
  ;; (large corrections split into several capped darts - best fit);
  ;; CARRY nil: the accumulator resets after each release (fewest cuts)
  ;; -> (feats fsum): feats = ((x width type local-depth) ...) in band
  ;;    order, fsum = inserts added - dart widths removed
  (setq feats nil acc 0.0 k 0 fsum 0.0)
  (while (< k (length idebt))
    (setq acc (+ acc (nth k idebt)))
    (if (and (>= (abs acc) wmin) (< (length feats) maxfeat))
      (progn
        (setq cw (abs acc))
        (if (< acc 0) (setq cw (min cw 4.0)))      ; dart mouth cap
        (setq f (nth (1+ k) rungs)
              fdev (wc:dev-point (caddr f) pts s)
        )
        ;; turn towards the far side = dart
        (setq feats (cons (list (nth (car f) s) cw
                                (if (< acc 0) 1 -1)
                                (- (cadr fdev)))
                          feats)
              fsum (+ fsum (if (< acc 0) (- cw) cw))
              acc (if carry
                    (if (< acc 0) (+ acc cw) (- acc cw))
                    0.0
                  )
        )
      )
    )
    (setq k (1+ k))
  )
  (list (reverse feats) fsum)
)

(defun wc:mult (sgm paircnt / f)
  ;; how many times this segment is drawn (2 = mesh interior, 1 = outline)
  (setq f (assoc (strcat (wc:key (car sgm)) "|" (wc:key (cadr sgm)))
                 paircnt))
  (if (not f)
    (setq f (assoc (strcat (wc:key (cadr sgm)) "|" (wc:key (car sgm)))
                   paircnt))
  )
  (if f (cdr f) 0)
)

(defun wc:chain-at (sv pts s / k n t0 sa sb A B)
  ;; point on the chosen chain at arc position SV
  (setq k 0 n (1- (length pts)))
  (while (and (< k (1- n)) (> sv (nth (1+ k) s)))
    (setq k (1+ k))
  )
  (setq sa (nth k s) sb (nth (1+ k) s)
        A (nth k pts) B (nth (1+ k) pts)
        t0 (if (> (- sb sa) 1.0e-9) (/ (- sv sa) (- sb sa)) 0.0)
        t0 (max 0.0 (min 1.0 t0))
  )
  (list (+ (car A) (* t0 (- (car B) (car A))))
        (+ (cadr A) (* t0 (- (cadr B) (cadr A))))
  )
)

(defun wc:depth-at (xv dps / a b res found)
  ;; linear interpolation of developed depth (cadr) at developed-x XV
  ;; over DPS (a list of dev-points sorted ascending by car); used to
  ;; land dart feet exactly on the bottom line
  (setq res (cadr (car dps)) found nil)
  (while (and (cdr dps) (not found))
    (setq a (car dps) b (cadr dps))
    (if (and (<= (car a) xv) (<= xv (car b)))
      (setq res (if (> (- (car b) (car a)) 1.0e-9)
                  (+ (cadr a) (* (- (cadr b) (cadr a))
                                 (/ (- xv (car a)) (- (car b) (car a)))))
                  (cadr a))
            found T
      )
    )
    (setq dps (cdr dps))
  )
  res
)

(defun wc:instair (xv rngs / hit)
  ;; T if arc position XV falls inside any (lo hi) stair range
  (setq hit nil)
  (foreach r rngs
    (if (and (>= xv (car r)) (<= xv (cadr r))) (setq hit T))
  )
  hit
)

(defun wc:notch (dps dfeats / runs run dp dd lx rx curr)
  ;; split the bottom line into runs at each dart mouth so no segment
  ;; spans the mouth (the base under the dart is erased); the run ends
  ;; land on the bottom line at the dart feet.
  ;; DFEATS: darts (cx cw) sorted ascending by cx.
  ;; -> list of runs, each a list of local (x y) points
  (setq runs nil run nil curr -1.0e18)
  (foreach dp dps
    (while (and dfeats
                (<= (- (car (car dfeats)) (/ (cadr (car dfeats)) 2.0))
                    (car dp)))
      (setq dd (car dfeats) dfeats (cdr dfeats)
            lx (- (car dd) (/ (cadr dd) 2.0))
            rx (+ (car dd) (/ (cadr dd) 2.0))
            run (cons (list lx (wc:depth-at lx dps)) run)   ; close at L foot
      )
      (if (cdr run) (setq runs (cons (reverse run) runs)))
      (setq run (list (list rx (wc:depth-at rx dps)))       ; reopen at R foot
            curr (max curr rx)
      )
    )
    (if (> (car dp) curr)
      (setq run (cons (list (car dp) (cadr dp)) run))
    )
  )
  (if (cdr run) (setq runs (cons (reverse run) runs)))
  (reverse runs)
)

;; A length as a percentage of the bottom-before length.  botb is
;; zero when the trace gave fewer than two distinct bottom points, and
;; a zero divisor here would throw AFTER the undo group opened, leaving
;; a half-drawn pair of layouts behind - a degenerate band reports 0%
;; and the run says so out loud instead.
(defun wc:pctof (v botb)
  (if (> botb 1e-9) (* 100.0 (/ (abs v) botb)) 0.0)
)

(defun wc:vdim (p1 p2 xline lay)
  ;; vertical rotated dimension between P1 and P2, dim line at X=XLINE
  (entmake
    (list '(0 . "DIMENSION") '(100 . "AcDbEntity") (cons 8 lay)
          '(100 . "AcDbDimension")
          (list 10 xline (/ (+ (cadr p1) (cadr p2)) 2.0) 0.0)
          '(70 . 32) '(1 . "")
          '(100 . "AcDbAlignedDimension")
          (list 13 (car p1) (cadr p1) 0.0)
          (list 14 (car p2) (cadr p2) 0.0)
          '(100 . "AcDbRotatedDimension")
          (cons 50 (/ pi 2))
    )
  )
)

;;; ------------------------------ main ------------------------------

(defun c:WCALST (/ *error* oldlay ss segs nodes pick en pk seed sg d2min
                 d2c i r ids pts chainkeys s n p0 p1 dch j far ang rungs
                 widths w mid side cross ni f k turns d0 d1 idebt i0 i1
                 tsum total wmin maxfeat acc feats fdev farlay fseed
                 fsegs cands rfar rr farpts farids fk seen ordered devpts
                 minx miny maxx maxy sgp x0 y0 wpt a b ld hz cw x
                 dl dr yb enda endb lay2 inundo conns nmk sgm dp1 dp2
                 bandlays tileh toplen botb bota tx th pass stop
                 resid featsb residb paircnt bndpts vy vfeats vresid
                 vlab ssstairs stsegs stkeys synth comp compkeys grow
                 strest nodes2 endpts dpa stentry stpath usedj stpt stgo
                 stcand se pA pB stang stca stsn sttot stlen stprev stdx
                 stdy dfeats run stairrng stage wc-pick)

  (defun *error* (msg)
    (if inundo (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if oldlay (setvar "CLAYER" oldlay))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nWCALST error: " msg))
    )
    (princ)
  )
  (setq oldlay (getvar "CLAYER"))

  ;; ---- 1.-7. the questions, staged so every prompt after the first
  ;; offers Back (Undo works too): the side pick returns to the band
  ;; selection, the numeric prompts to the side pick - the trace is
  ;; recomputed from whatever is re-answered.  A trace that fails now
  ;; re-opens the pick it came from instead of ending the command.
  ;; Lines highlighted before WCALST was typed (pickfirst) are the band -
  ;; the first pass through stage 1 takes them; a too-small band or Back
  ;; re-asks interactively.
  (setq wc-pick (ssget "_I" '((0 . "LINE,LWPOLYLINE,POLYLINE"))))
  (setq stage 1)
  (while (< stage 6)
    (cond

      ;; ---- 1. selection ----------------------------------------------
      ((= stage 1)
       (if wc-pick
         (setq ss wc-pick wc-pick nil)
         (progn
           (princ "\nSelect the band of lines (two long sides + rungs): ")
           (setq ss (ssget '((0 . "LINE,LWPOLYLINE,POLYLINE"))))))
       (if (not ss) (progn (princ "\nNothing selected.") (exit)))
       (setq segs (wc:build-segs ss))
       (if (< (length segs) 6)
         (princ "\nToo few segments to form a band - select again.")
         (progn
           (setq nodes (wc:build-nodes segs))
           (setq stage 2)
         )
       ))

      ;; ---- 2. pick the side to straighten ----------------------------
      ((= stage 2)
       (initget "Back Undo")
       (setq pick (entsel "\nClick the long side to STRAIGHTEN [Back]: "))
       (cond
         ((= (type pick) 'STR) (setq stage 1))
         ((not pick)
          (princ "  (nothing picked - click a line of the selection)"))
         ((not (ssmemb (car pick) ss))
          (princ "  (that entity is not in the selection)"))
         (T
          (setq en (car pick) pk (cadr pick))
          ;; seed = the segment of the picked entity nearest the pick
          (setq seed nil d2min 1.0e18 i 0)
          (foreach sg segs
            (if (eq (cadddr sg) en)
              (progn
                (setq d2c (cal:d2 pk (mapcar '(lambda (u v) (/ (+ u v) 2.0))
                                            (car sg) (cadr sg))))
                (if (< d2c d2min) (setq d2min d2c seed i))
              )
            )
            (setq i (1+ i))
          )
          (if (not seed)
            (princ "\nCould not locate a segment at that pick.")
            (setq stage 3)
          )
         )
       ))

      ;; ---- 3.-6. trace, rungs, orientation, turn debt (no input) -----
      ((= stage 3)
       (setq r (wc:full-chain segs nodes seed)
             ids (car r)
             pts (cdr r)
       )
       (if (< (length ids) 3)
         (progn
           (princ "\nCould not trace a long side from that pick - pick again.")
           (setq stage 2)
         )
         (progn
           (setq chainkeys (mapcar 'wc:key pts))

           ;; arc length of each chain node
           (setq s (list 0.0))
           (setq p0 (car pts))
           (foreach p1 (cdr pts)
             (setq s (cons (+ (car s) (distance p0 p1)) s) p0 p1)
           )
           (setq s (reverse s)
                 n (length pts)
           )

           ;; ---- 4. rungs --------------------------------------------
           ;; conns records every segment hanging off the chosen chain
           ;; (rungs, diagonal braces, chords) so none of them is later
           ;; mistaken for a free-standing reference mark
           (setq rungs nil conns nil ni 0)
           (foreach p pts
             (setq p0 (nth (max 0 (1- ni)) pts)
                   p1 (nth (min (1- n) (1+ ni)) pts)
                   dch (wc:dir p0 p1)
             )
             (foreach j (cdr (assoc (wc:key p) nodes))
               (if (not (member j ids))
                 (progn
                   (setq conns (cons j conns)
                         far (wc:other-end (nth j segs) p)
                   )
                   (if (not (wc:member-key far chainkeys))
                     (progn
                       (setq ang (abs (wc:turn dch (wc:dir p far)))
                             ang (min ang (- pi ang))
                       )
                       (if (> ang 0.7854)          ; > 45 deg off the chain
                         (setq rungs (cons (list ni p far) rungs))
                       )
                     )
                   )
                 )
               )
             )
             (setq ni (1+ ni))
           )
           (setq rungs (reverse rungs))
           (if (< (length rungs) 2)
             (progn
               (princ "\nCould not find the rungs between the two sides - pick again.")
               (setq stage 2)
             )
             (progn
               ;; band width = median rung length
               (setq widths (vl-sort (mapcar '(lambda (r)
                                                (distance (cadr r) (caddr r)))
                                             rungs)
                                     '<)
                     w (nth (/ (length widths) 2) widths)
               )

               ;; ---- 5. normalize orientation: far side below the
               ;; ---- travel direction
               (setq side 0)
               (foreach f rungs
                 (setq ni (car f) p (cadr f) far (caddr f)
                       p0 (nth (max 0 (1- ni)) pts)
                       p1 (nth (min (1- n) (1+ ni)) pts)
                       cross (- (* (- (car p1) (car p0))
                                   (- (cadr far) (cadr p)))
                                (* (- (cadr p1) (cadr p0))
                                   (- (car far) (car p))))
                 )
                 (setq side (+ side (if (> cross 0) 1 -1)))
               )
               (if (> side 0)          ; far side is left -> walk the other way
                 (progn
                   (setq pts (reverse pts)
                         mid (car (reverse s))
                         s (reverse (mapcar '(lambda (v) (- mid v)) s))
                         chainkeys (reverse chainkeys)
                         rungs (mapcar '(lambda (f)
                                          (list (- n 1 (car f)) (cadr f) (caddr f)))
                                       rungs)
                         rungs (reverse rungs)
                   )
                 )
               )

               ;; ---- 6. turn angles and per-interval correction debt --
               (setq turns (list 0.0) k 1)
               (while (< k (1- n))
                 (setq d0 (wc:dir (nth (1- k) pts) (nth k pts))
                       d1 (wc:dir (nth k pts) (nth (1+ k) pts))
                       turns (cons (wc:turn d0 d1) turns)
                       k (1+ k)
                 )
               )
               (setq turns (reverse (cons 0.0 turns)))

               (setq idebt nil k 0)
               (while (< k (1- (length rungs)))
                 (setq i0 (car (nth k rungs))
                       i1 (car (nth (1+ k) rungs))
                       tsum 0.0
                       j (1+ i0)
                 )
                 (while (<= j i1)
                   (setq tsum (+ tsum (nth j turns)) j (1+ j))
                 )
                 (setq idebt (cons (* tsum w) idebt) k (1+ k))
               )
               (setq idebt (reverse idebt)
                     total (apply '+ (mapcar 'abs idebt))
               )
               (setq stage 4)
             )
           )
         )
       ))

      ;; ---- 7. feature threshold (conservative, capped) ---------------
      ((= stage 4)
       (initget "Back Undo")
       (setq maxfeat (getint "\nMaximum darts + inserts <20> [Back]: "))
       (if (= (type maxfeat) 'STR)
         (setq stage 2)
         (progn
           (if (or (not maxfeat) (< maxfeat 1)) (setq maxfeat 20))
           (setq stage 5)
         )
       ))
      ;; a tile of this height sits along the straightened edge: cuts
      ;; may only come up to (width - tile height - 1") from the far edge
      (T
       (initget "Back Undo")
       (setq tileh (getreal
                     "\nTile height along the straightened edge <none> [Back]: "))
       (if (= (type tileh) 'STR)
         (setq stage 4)
         (progn
           (if (and tileh (< tileh 0.0)) (setq tileh nil))
           (setq stage 6)
         )
       ))
    )
  )
  ;; stair sections: the bottom line wraps around steps there; each
  ;; windowed section is developed rigidly as one piece so every tread
  ;; length and riser rise is kept exactly (treads come out level,
  ;; equal steps up and down stay equal)
  (princ "\nWindow the STAIR section(s) if any (Enter = none): ")
  (setq ssstairs (ssget))

  ;; ---- 8. develop the far edge ----------------------------------------
  ;; far side points = every rung far foot + the far chain traced from a
  ;; middle rung (feet alone already outline the edge if the chain breaks)
  (setq fseed (caddr (nth (/ (length rungs) 2) rungs))
        cands (cdr (assoc (wc:key fseed) nodes))
        fsegs nil
  )
  (foreach j cands
    (setq far (wc:other-end (nth j segs) fseed))
    (if (and (not (member j ids))
             (not (wc:member-key far chainkeys)))
      (setq fsegs (cons j fsegs))
    )
  )
  (setq farpts nil farlay nil farids nil)
  (if fsegs
    (progn
      (setq rr (wc:full-chain segs nodes (car fsegs))
            farids (car rr)
            farpts (cdr rr)
            farlay (caddr (nth (car fsegs) segs))
      )
    )
  )
  (if (not farlay) (setq farlay (caddr (nth seed segs))))
  ;; layers the band structure itself lives on: bands may be full
  ;; triangulated meshes (interior vertices, doubled edges), so segment
  ;; bookkeeping cannot tell structure from reference marks -- layers can
  (setq bandlays (list (caddr (nth seed segs))))
  (if (and farlay (not (member farlay bandlays)))
    (setq bandlays (cons farlay bandlays))
  )
  (foreach k conns
    (if (not (member (caddr (nth k segs)) bandlays))
      (setq bandlays (cons (caddr (nth k segs)) bandlays))
    )
  )

  ;; outline vertices: segments drawn ONCE are outline (mesh interiors
  ;; are always shared by two triangles and appear twice). Keeping every
  ;; far-side outline vertex preserves sharp steps (~90 deg temporary
  ;; rises) that the straightest-path tracing cuts across
  (setq paircnt nil)
  (foreach sgm segs
    (setq fk (strcat (wc:key (car sgm)) "|" (wc:key (cadr sgm)))
          f  (assoc fk paircnt)
    )
    (if (not f)
      (setq fk (strcat (wc:key (cadr sgm)) "|" (wc:key (car sgm)))
            f  (assoc fk paircnt)
      )
    )
    (if f
      (setq paircnt (subst (cons (car f) (1+ (cdr f))) f paircnt))
      (setq paircnt (cons (cons fk 1) paircnt))
    )
  )
  (setq bndpts nil)
  (foreach sgm segs
    (if (equal (caddr sgm) farlay)
      (progn
        (setq f (assoc (strcat (wc:key (car sgm)) "|" (wc:key (cadr sgm)))
                       paircnt))
        (if (not f)
          (setq f (assoc (strcat (wc:key (cadr sgm)) "|" (wc:key (car sgm)))
                         paircnt))
        )
        (if (and f (= 1 (cdr f)))
          (foreach p (list (car sgm) (cadr sgm))
            (if (not (wc:member-key p chainkeys))
              (setq bndpts (cons p bndpts))
            )
          )
        )
      )
    )
  )

  ;; merge + dedupe far points, order by projected arc length
  (setq seen nil ordered nil)
  (foreach f (append farpts (mapcar 'caddr rungs) bndpts)
    (setq fk (wc:key f))
    (if (not (member fk seen))
      (setq seen (cons fk seen)
            ordered (cons f ordered)
      )
    )
  )
  (setq devpts (mapcar '(lambda (f) (wc:dev-point f pts s)) ordered)
        ;; drop points projecting far off the chain (past the band ends,
        ;; end blocks, unrelated marks caught in the selection) and points
        ;; developing at/above the straight edge (end-clamp artifacts --
        ;; the far side always lies below the straightened edge)
        devpts (vl-remove-if
                 '(lambda (dp)
                    (or (> (cadddr dp) (* 1.75 w))
                        (> (cadr dp) (* -0.05 w))
                        (< (car dp) (* -0.25 w))
                        (> (car dp) (+ (car (reverse s)) (* 0.25 w)))))
                 devpts)
        devpts (vl-sort devpts '(lambda (a b) (< (caddr a) (caddr b))))
  )
  (if (< (length devpts) 2)
    (progn (princ "\nCould not develop the opposite side.") (exit))
  )

  ;; ---- 8s. stair sections ----------------------------------------------
  ;; each windowed stair section is developed as one rigid piece: the
  ;; whole outline path is rotated by the chord direction of the chosen
  ;; chain across the section and anchored at the section entry, so
  ;; treads come out level with their exact lengths and every riser
  ;; keeps its exact rise (validated against a hand-drawn example:
  ;; every segment length is preserved to the hundredth)
  (setq synth nil stkeys nil stairrng nil)
  (if ssstairs
    (progn
      ;; candidate segments: in the window, on the far side's layer,
      ;; outline (drawn once), touching neither end of the chain
      (setq stsegs nil)
      (foreach sgm segs
        (if (and (ssmemb (cadddr sgm) ssstairs)
                 (equal (caddr sgm) farlay)
                 (= 1 (wc:mult sgm paircnt))
                 (not (wc:member-key (car sgm) chainkeys))
                 (not (wc:member-key (cadr sgm) chainkeys)))
          (setq stsegs (cons (list (car sgm) (cadr sgm)) stsegs))
        )
      )
      ;; process each connected stair path
      (while stsegs
        ;; flood-fill one connected component
        (setq comp (list (car stsegs))
              compkeys (list (wc:key (car (car stsegs)))
                             (wc:key (cadr (car stsegs))))
              stsegs (cdr stsegs)
              grow T
        )
        (while grow
          (setq grow nil strest nil)
          (foreach sgm stsegs
            (if (or (member (wc:key (car sgm)) compkeys)
                    (member (wc:key (cadr sgm)) compkeys))
              (setq comp (cons sgm comp)
                    compkeys (cons (wc:key (car sgm))
                                   (cons (wc:key (cadr sgm)) compkeys))
                    grow T
              )
              (setq strest (cons sgm strest))
            )
          )
          (setq stsegs (reverse strest))
        )
        ;; open ends of the path = nodes with a single incident segment
        (setq nodes2 (wc:build-nodes comp) endpts nil)
        (foreach e nodes2
          (if (= 2 (length e))               ; (key idx) -> one segment
            (progn
              (setq sgm (nth (cadr e) comp))
              (setq endpts (cons (if (equal (wc:key (car sgm)) (car e))
                                   (car sgm)
                                   (cadr sgm))
                                 endpts))
            )
          )
        )
        (if (>= (length endpts) 2)
          (progn
            ;; entry = the end nearest the chain start (smaller proj-s)
            (setq endpts (vl-sort endpts
                           '(lambda (a b) (< (caddr (wc:dev-point a pts s))
                                             (caddr (wc:dev-point b pts s))))))
            (setq stentry (car endpts)
                  dpa (wc:dev-point stentry pts s)
            )
            ;; walk the path from the entry
            (setq stpath (list stentry) usedj nil stpt stentry stgo T)
            (while stgo
              (setq stcand nil)
              (foreach j (cdr (assoc (wc:key stpt) nodes2))
                (if (not (member j usedj)) (setq stcand j))
              )
              (if stcand
                (setq usedj (cons stcand usedj)
                      stpt (wc:other-end (nth stcand comp) stpt)
                      stpath (cons stpt stpath)
                )
                (setq stgo nil)
              )
            )
            (setq stpath (reverse stpath)
                  se (caddr (wc:dev-point (car (reverse stpath)) pts s))
                  pA (wc:chain-at (caddr dpa) pts s)
                  pB (wc:chain-at se pts s)
                  ;; arc-length span this stair section covers, so darts
                  ;; are not placed on it (handled by hand afterward)
                  stairrng (cons (list (min (caddr dpa) se)
                                       (max (caddr dpa) se))
                                 stairrng)
            )
            (if (> (distance pA pB) 1.0e-6)
              (progn
                ;; rotate the section by the chain chord, anchor at entry
                (setq stang (- (wc:dir pA pB))
                      stca (cos stang)
                      stsn (sin stang)
                      sttot 0.0
                      stprev (car stpath)
                )
                (foreach stq (cdr stpath)
                  (setq sttot (+ sttot (distance stprev stq)) stprev stq)
                )
                (setq stlen 0.0 stprev (car stpath))
                (foreach stq stpath
                  (setq stlen (+ stlen (distance stprev stq))
                        stprev stq
                        stdx (- (car stq) (car stentry))
                        stdy (- (cadr stq) (cadr stentry))
                  )
                  (setq synth
                    (cons (list (+ (car dpa) (- (* stdx stca) (* stdy stsn)))
                                (+ (cadr dpa) (+ (* stdx stsn) (* stdy stca)))
                                (+ (caddr dpa)
                                   (if (> sttot 1.0e-9)
                                     (* (- se (caddr dpa)) (/ stlen sttot))
                                     0.0))
                                0.0
                                stq)
                          synth)
                        stkeys (cons (wc:key stq) stkeys)
                  )
                )
              )
            )
          )
        )
      )
      ;; splice: synthesized stair points replace their projected twins
      (if synth
        (setq devpts (vl-remove-if
                       '(lambda (dp) (member (wc:key (nth 4 dp)) stkeys))
                       devpts)
              devpts (vl-sort (append devpts synth)
                              '(lambda (a b) (< (caddr a) (caddr b))))
        )
      )
    )
  )

  ;; bottom line lengths: along the original curve vs as developed
  (setq botb 0.0 bota 0.0 dp1 (car devpts))
  (foreach dp2 (cdr devpts)
    (setq botb (+ botb (distance (nth 4 dp1) (nth 4 dp2)))
          bota (+ bota (distance (list (car dp1) (cadr dp1))
                                 (list (car dp2) (cadr dp2))))
          dp1 dp2
    )
  )
  (if (<= botb 1e-9)
    (princ (strcat "\nThe far edge measured no length - fewer than two"
                   " distinct bottom points came back, so the"
                   " percentages below read 0%."))
  )

  ;; ---- 8b. feature emission -------------------------------------------
  ;; two variants are produced:
  ;;   A) minimum darts+inserts: one conservative pass at the base
  ;;      threshold (fewest, widest features)
  ;;   B) target <1%: the threshold is refined until the after-cuts
  ;;      residual (bottom-after - darts + inserts vs bottom-before)
  ;;      aims under 1% of the original bottom length
  ;; dart mouths are capped at 4" on the bottom line in both (larger
  ;; corrections split across consecutive rungs)
  (setq wmin (max (* 0.04 w) (/ total maxfeat)))

  (setq rr (wc:emit idebt rungs pts s wmin maxfeat nil)
        featsb (car rr)                            ; minimum variant
        residb (+ (- bota botb) (cadr rr))
  )

  (setq pass 0 stop nil)
  (while (not stop)
    (setq rr (wc:emit idebt rungs pts s wmin maxfeat T)
          feats (car rr)
          resid (+ (- bota botb) (cadr rr))
          pass (1+ pass)
    )
    (if (or (<= (abs resid) (* 0.01 botb))         ; under the 1% target
            (>= (length feats) maxfeat)            ; no room for more
            (<= wmin (* 0.0401 w))                 ; threshold bottomed out
            (>= pass 10)
        )
      (setq stop T)
      (setq wmin (max (* 0.04 w) (* wmin 0.6)))    ; more, smaller features
    )
  )

  ;; darts landing inside a windowed stair section are dropped (the
  ;; stairs are developed rigidly and get their darts added by hand);
  ;; inserts are left in place
  (if stairrng
    (progn
      (setq feats  (vl-remove-if
                     '(lambda (f) (and (= 1 (caddr f))
                                       (wc:instair (car f) stairrng)))
                     feats)
            featsb (vl-remove-if
                     '(lambda (f) (and (= 1 (caddr f))
                                       (wc:instair (car f) stairrng)))
                     featsb)
            fsum 0.0
      )
      (foreach f feats
        (setq fsum (+ fsum (if (= 1 (caddr f)) (- (cadr f)) (cadr f))))
      )
      (setq resid (+ (- bota botb) fsum) fsum 0.0)
      (foreach f featsb
        (setq fsum (+ fsum (if (= 1 (caddr f)) (- (cadr f)) (cadr f))))
      )
      (setq residb (+ (- bota botb) fsum))
    )
  )

  ;; ---- 9. placement below the selection --------------------------------
  (setq minx 1.0e18 miny 1.0e18 maxx -1.0e18 maxy -1.0e18)
  (foreach sg segs
    (foreach wpt (list (car sg) (cadr sg))
      (setq minx (min minx (car wpt)) miny (min miny (cadr wpt))
            maxx (max maxx (car wpt)) maxy (max maxy (cadr wpt))
      )
    )
  )
  (setq x0 minx
        y0 (- miny (* 1.5 w))          ; straight edge sits here
  )

  ;; ---- 10. draw ----------------------------------------------------------
  (command "_.UNDO" "_Begin")
  (setq inundo T)
  (setq lay2 (cal:ensure-layer "AIR-B" 1))
  (cal:ensure-layer "DIMENSION" 3)

  ;; two stacked drawings: the <1% target version, and below it the
  ;; minimum darts+inserts version
  (setq toplen (car (reverse s))
        nmk 0
        vy y0
  )
  (foreach vr (list (list feats resid "TARGET <1%")
                    (list featsb residb "MINIMUM DARTS+INSERTS"))
    (setq vfeats (car vr)
          vresid (cadr vr)
          vlab (caddr vr)
    )

    ;; variant label above the straight edge
    (cal:text (list x0 (+ vy (* 0.6 w))) (* 0.4 w) vlab "DIMENSION")

    ;; straight (chosen) edge
    (setq sgp (list (+ x0 (car s)) vy)
          wpt (list (+ x0 toplen) vy)
    )
    (wc:line sgp wpt lay2)

    ;; darts of this variant as (center-x mouth-width), sorted by x
    (setq dfeats nil)
    (foreach f vfeats
      (if (= 1 (caddr f))
        (setq dfeats (cons (list (car f) (cadr f)) dfeats))
      )
    )
    (setq dfeats (vl-sort dfeats '(lambda (a b) (< (car a) (car b)))))

    ;; far edge: bottom line split at each dart mouth so no segment spans
    ;; the mouth (the base under the dart is erased); the dart legs drawn
    ;; below close each gap, tied to the bottom line at the feet
    (foreach run (wc:notch devpts dfeats)
      (if (> (length run) 1)
        (wc:pline (mapcar '(lambda (p) (list (+ x0 (car p)) (+ vy (cadr p))))
                          run)
                  farlay nil)
      )
    )

    ;; band ends (vertical closing lines)
    (setq enda (list (+ x0 (car (car devpts))) (+ vy (cadr (car devpts))))
          endb (list (+ x0 (car (car (reverse devpts))))
                     (+ vy (cadr (car (reverse devpts)))))
    )
    (wc:line (list (car enda) vy) enda lay2)
    (wc:line (list (car endb) vy) endb lay2)

    ;; darts and inserts
    (foreach f vfeats
      (setq x (+ x0 (car f))
            cw (cadr f)
            ;; local band depth = the actual bottom line at this feature
            ld (max (- (wc:depth-at (car f) devpts)) (* 0.2 w))
            ;; apex/slit stop line, measured down from the straightened
            ;; edge.  With a tile height, tile+1" is the HIGHEST the apex
            ;; may rise (closest it may come to the straight edge); the
            ;; apex sits on that line, dropping lower only where the band
            ;; is too shallow to reach it (kept 1" above the foot).
            ;; Without a tile height, the default 42% of the local depth.
            hz (if tileh (min (+ tileh 1.0) (- ld 1.0)) (* 0.42 ld))
            yb (- vy ld)                          ; local far edge
      )
      (if (= 1 (caddr f))
        (progn                                    ; DART: V legs, feet on
          ;; the bottom line, apex at the stop line; the mouth base was
          ;; erased by splitting the far-edge polyline there
          (wc:line (list x (- vy hz))
                   (list (- x (/ cw 2.0))
                         (+ vy (wc:depth-at (- (car f) (/ cw 2.0)) devpts)))
                   lay2)
          (wc:line (list x (- vy hz))
                   (list (+ x (/ cw 2.0))
                         (+ vy (wc:depth-at (+ (car f) (/ cw 2.0)) devpts)))
                   lay2)
        )
        (progn                                    ; INSERT: slit + sliver below
          (wc:line (list x yb) (list x (- vy hz)) lay2)
          ;; sliver piece: 1" wide at the top, the gap width at the
          ;; bottom, sides about 1" longer than the slit it goes into
          (setq dl (+ (- ld hz) 1.0)              ; slit length + 1"
                cw (max cw 1.0)
                yb (- vy ld (* 0.2 w))            ; sliver top
                dr (- yb dl)                      ; sliver bottom
          )
          (wc:pline
            (list (list (- x (/ cw 2.0)) dr) (list (+ x (/ cw 2.0)) dr)
                  (list (+ x 0.5) yb) (list (- x 0.5) yb)
            )
            lay2 T
          )
        )
      )
    )

    ;; carry-along marks: selected segments on OTHER layers than the
    ;; band structure (reference crosses, datum lines, existing cut
    ;; marks) are developed point-by-point onto their own layer
    (setq k 0)
    (foreach sgm segs
      (if (and (not (member (caddr sgm) bandlays))
               (not (member k ids))
               (not (member k farids))
               (not (member k conns)))
        (progn
          (setq dp1 (wc:dev-point (car sgm) pts s)
                dp2 (wc:dev-point (cadr sgm) pts s)
          )
          ;; keep only marks that actually sit on/near the band
          (if (and (<= (cadddr dp1) (* 1.75 w))
                   (<= (cadddr dp2) (* 1.75 w)))
            (progn
              (wc:line (list (+ x0 (car dp1)) (+ vy (cadr dp1)))
                       (list (+ x0 (car dp2)) (+ vy (cadr dp2)))
                       (caddr sgm))
              (setq nmk (1+ nmk))
            )
          )
        )
      )
      (setq k (1+ k))
    )

    ;; height dimensions at both ends
    (wc:vdim (list (car enda) vy) enda (- (car enda) (* 1.2 w)) "DIMENSION")
    (wc:vdim (list (car endb) vy) endb (+ (car endb) (* 1.2 w)) "DIMENSION")

    ;; length summary to the right of the drawing: top line, bottom line
    ;; before (along the original curve) and after (as drawn), the delta
    ;; the flattened bottom line is off by, and the residual once the
    ;; darts close / inserts fill (target: under 1%)
    (setq tx (+ (car endb) (* 2.0 w))
          th (* 0.35 w)
    )
    (cal:text (list tx vy) th
             (strcat "TOP LINE:      " (rtos toplen 2 2)
                     "  (" (rtos toplen 4 8) ")")
             "DIMENSION")
    (cal:text (list tx (- vy (* 0.55 w))) th
             (strcat "BOTTOM BEFORE: " (rtos botb 2 2)
                     "  (" (rtos botb 4 8) ")")
             "DIMENSION")
    (cal:text (list tx (- vy (* 1.10 w))) th
             (strcat "BOTTOM AFTER:  " (rtos bota 2 2)
                     "  (" (rtos bota 4 8) ")")
             "DIMENSION")
    (cal:text (list tx (- vy (* 1.65 w))) th
             (strcat "DELTA:         " (rtos (- bota botb) 2 2)
                     "  (" (rtos (wc:pctof (- bota botb) botb) 2 2)
                     "%" (if (< bota botb) " short)" " long)"))
             "DIMENSION")
    (cal:text (list tx (- vy (* 2.20 w))) th
             (strcat "AFTER CUTS:    " (rtos vresid 2 2)
                     "  (" (rtos (wc:pctof vresid botb) 2 2)
                     "%)  [target <1%]"
                     (if (> (abs vresid) (* 0.01 botb)) "  ** OVER TARGET **" ""))
             "DIMENSION")

    ;; next variant goes below this one
    (setq vy (- vy (* 5.0 w)))
  )

  (command "_.UNDO" "_End")
  (setq inundo nil)
  (setvar "CLAYER" oldlay)

  ;; ---- 11. report ---------------------------------------------------------
  (princ (strcat "\nWCALST: developed length " (rtos toplen 2 2)
                 ", band width " (rtos w 2 2) ", two drawings:"))
  (foreach vr (list (list feats resid "target <1%")
                    (list featsb residb "minimum cuts"))
    (setq dl 0 dr 0)
    (foreach f (car vr) (if (= 1 (caddr f)) (setq dl (1+ dl)) (setq dr (1+ dr))))
    (princ (strcat "\n  " (caddr vr) ": " (itoa dl) " dart(s), "
                   (itoa dr) " insert(s) (max " (itoa maxfeat)
                   "), after cuts " (rtos (cadr vr) 2 2)
                   " (" (rtos (wc:pctof (cadr vr) botb) 2 2) "%)"
                   (if (> (abs (cadr vr)) (* 0.01 botb)) " OVER TARGET" "")))
  )
  (princ (strcat "\n  top line " (rtos toplen 2 2)
                 ", bottom before " (rtos botb 2 2)
                 ", bottom after " (rtos bota 2 2)
                 ", delta " (rtos (- bota botb) 2 2)
                 " (" (rtos (wc:pctof (- bota botb) botb) 2 2)
                 "%)."))
  (if (> nmk 0)
    (princ (strcat " " (itoa (/ nmk 2)) " reference mark(s) carried along."))
  )
  (princ)
)

(defun c:WCALSTVER ()
  (princ (strcat "\nWCALST " *wcalst-version*))
  (princ))

(princ (strcat "\nWCALST " *wcalst-version*
               " loaded -- select the band, pick the side to straighten."))
(princ)
