;;; ======================================================================
;;; LINGUTTER.lsp  --  gut a highlighted area back to its perimeter, the
;;;                    dimensions worth keeping, and PADDLE's pads
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LINGUTTER       gut the highlighted area, then run PADDLE
;;;            LINGUTTERSCAN   report what it would keep and erase, and stop
;;;            LINGUTTERVER    print the loaded version
;;;
;;;  A finished as-built sheet carries far more than the next station
;;;  needs: the hopper and its slope lines, steps, survey points and
;;;  their labels, the notes.  LINGUTTER cuts one pool back to three
;;;  things and then pads what is left.
;;;
;;;  IT WORKS ONLY INSIDE THE HIGHLIGHT.  Window the pool -- before
;;;  typing the command or at its prompt -- and everything below happens
;;;  to that selection and nothing else.  What you did not highlight is
;;;  not traced from, not counted, and not erased, so a second pool, the
;;;  title block and the rest of the sheet are all safe from it.
;;;
;;;    1. TRACE.  It does not look for a closed loop and hope one of
;;;       them is the pool.  It walks the OUTER FACE of the highlighted
;;;       geometry and draws its own perimeter over it -- the outline
;;;       you would get walking round the outside with your hand on the
;;;       wall.  Ends closer than a snap tolerance count as one point,
;;;       so a drafting gap heals; the walk always takes the hardest
;;;       available right turn, which is what keeps it outside -- the
;;;       hopper, the steps and a bottom break are never stepped onto,
;;;       because reaching them needs a left turn.  Three tolerances are
;;;       tried in turn (lg:*snaps*), tightest first, and the result is
;;;       measured against what was highlighted before it is believed.
;;;       What comes out is redrawn as ONE closed LWPOLYLINE on the
;;;       "POOL" layer, ByLayer, arcs carried as bulges -- a single
;;;       object however it was drawn going in: one polyline, or fifty
;;;       loose lines and arcs.
;;;
;;;       When no exterior can be walked at any tolerance it still draws
;;;       a perimeter: the convex hull of everything highlighted.  That
;;;       is reported as the wrap it is, because a hull has no concave
;;;       features and PADDLE will find nothing to pad.
;;;
;;;    2. KEEP.  Two rules, and nothing else highlighted survives them:
;;;         * a dimension in a lg:*anystyles* style ("CROSS DIM*", which
;;;           catches both "CROSS DIM" and this repo's "CROSS
;;;           DIMENSIONS") is kept wherever it sits -- a cross dim
;;;           spans the pool, so most of it is nowhere near the edge;
;;;         * a dimension in a lg:*perimstyles* style ("STANDARD",
;;;           "SIDE STANDARD") is kept only when it is ON the perimeter
;;;           -- every one of its attachment points within
;;;           lg:*ontol* of the loop.  The same style measuring a
;;;           hopper or a step goes with the rest.
;;;       Everything else highlighted is erased: text, blocks, points,
;;;       hatches, the geometry the perimeter was traced from, and
;;;       dimensions in any other style.  Name a layer in
;;;       lg:*keeplayers* to spare it even inside the highlight.
;;;
;;;    3. PADDLE.  The new perimeter is handed over as a pickfirst
;;;       selection and PADDLE pads its concave features.  Handed, not
;;;       hunted: PADDLE's own auto-detect reads the WHOLE drawing for
;;;       its largest closed loop, which after a scoped gut may well be
;;;       a title block border rather than the pool.
;;;
;;;  LINGUTTER erases a great deal of what you highlight, so it asks
;;;  first -- after printing exactly what it found, and defaulting to
;;;  No.  LINGUTTERSCAN prints the same report and stops without
;;;  touching the drawing; run it first on a sheet you care about.  The
;;;  whole run is one undo group: a single U puts the drawing back.
;;;
;;;  Usage
;;;    Command: LINGUTTER       highlight the area before typing it and
;;;                             that selection is used as-is; otherwise
;;;                             it asks for one.  There is no "the whole
;;;                             drawing" answer -- it erases what it
;;;                             sweeps, so it sweeps only what you showed
;;;                             it
;;;    Command: LINGUTTERSCAN   the report, and nothing else
;;;    Command: LINGUTTERVER    prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  names, e.g. in a startup file):
;;;    lg:*poollayer*    layer the perimeter is drawn on    ("POOL")
;;;    lg:*poolcolor*    its colour when the layer has to be created
;;;    lg:*anystyles*    dim styles kept wherever they sit, as wildcard
;;;                      patterns matched against the style name
;;;    lg:*perimstyles*  dim styles kept only on the perimeter
;;;    lg:*keeplayers*   layers left alone entirely (nil = none)
;;;    lg:*skiplayers*   layers the perimeter is never traced from
;;;    lg:*ontol*        how far a dimension's attachment point may sit
;;;                      off the perimeter and still count as on it
;;;    lg:*snaps*        the snap ladder: how far apart two ends may be
;;;                      and still count as one point, tried in order
;;;    lg:*cover*        how much of the highlight's extent a traced
;;;                      exterior must span before it is believed
;;;    lg:*runpaddle*    T to run PADDLE at the end, nil to stop after
;;;                      the gut
;;;
;;;  Notes
;;;    * A crossing window takes in whatever it touches, so a dimension
;;;      half inside the highlight is in the sweep and one wholly
;;;      outside it is not -- the highlight is the whole of the rule.
;;;    * Snapping MOVES a corner, by up to the tolerance that healed it.
;;;      A rung is only climbed when the one below could not produce an
;;;      exterior covering the highlight, and the report always names the
;;;      rung that worked.
;;;    * Highlighting two pools at once traces the bigger one and warns
;;;      that it covers only part of what you showed it.  That warning is
;;;      never a veto -- the alternative to a partial answer is a convex
;;;      hull, which is worse.
;;;    * "STANDARD INCHES" is deliberately NOT in lg:*perimstyles*: the
;;;      request named STANDARD and SIDE STANDARD.  A perimeter side
;;;      under 12" that AUTODIM put in STANDARD INCHES therefore goes
;;;      with the rest -- but it is never silent about it, the report
;;;      counts every dropped dimension by style.  Add the style to
;;;      lg:*perimstyles* to keep those too.
;;;    * The perimeter is always redrawn, even when it was already one
;;;      closed polyline on POOL, so the result is the same object
;;;      whatever went in.  An associative dimension attached to the old
;;;      geometry loses its association (the measurement and the
;;;      definition points do not move -- the new polyline is drawn
;;;      through the same points).
;;;    * VIEWPORT entities are never erased, however they were caught.
;;;    * A locked layer is unlocked for the erase and locked again
;;;      afterwards.
;;;    * PADDLE lives in its own file.  When this session has not
;;;      loaded it the gut still happens and LINGUTTER says so instead
;;;      of failing.
;;;    * CLAYER, CMDECHO and OSMODE in force before the command are
;;;      restored afterwards, on a clean finish, an error, or Esc.
;;; ======================================================================

(setq *lingutter-version* "v2.2")  ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

(setq lg:*poollayer*   "POOL")
(setq lg:*poolcolor*   4)          ; ACI 4 = cyan, POOL's own colour
(setq lg:*anystyles*   '("CROSS DIM*"))
(setq lg:*perimstyles* '("STANDARD" "SIDE STANDARD"))
(setq lg:*keeplayers*  nil)        ; e.g. '("TITLEBLOCK") to spare one
(setq lg:*skiplayers*  '("DEFPOINTS" "DIMENSION"))
(setq lg:*ontol*       1.0)        ; drawing units; inches by default
(setq lg:*snaps*  '(0.05 6.0 24.0)) ; snap ladder: how far apart two ends
                                   ; may be and still be treated as one
                                   ; node, tried tightest first
(setq lg:*cover*       0.8)        ; how much of the highlight's extent a
                                   ; traced exterior has to span to be
                                   ; believed as the perimeter
(setq lg:*runpaddle*   t)
(setq lg:*sysold*      nil)        ; sysvar snapshot, live only mid-run

;;; -------------------- ask layer ---------------------------------------
;;; STANDARDS.md section 4, copied from the library so this file loads
;;; alone.  kws is the canonical keyword string -- it is BOTH the initget
;;; list and the bracket text, so the two can never drift.

(defun lg:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'LG-BACK)
        ((null v) (if dflt dflt (lg:askkw msg kws hidden dflt back)))
        (t v)))

;; Yes/No.  dflt is always shown; destructive actions default "No".
(defun lg:askyn (msg dflt back / v)
  (setq v (lg:askkw msg "Yes No" nil dflt back))
  (if (eq v 'LG-BACK) v (= v "Yes")))

;;; -------------------- drawing state -----------------------------------
;;; The sysvars this tool moves, saved in restore order -- OSMODE first,
;;; because object snaps are the setting the user misses most if a run is
;;; ever cut short partway.

(defun lg:syssave (vars / v)
  (if (not lg:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq lg:*sysold*
              (append lg:*sysold* (list (cons v (getvar v)))))))))

(defun lg:sysrestore ( / p)
  (foreach p lg:*sysold* (setvar (car p) (cdr p)))
  (setq lg:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun lg:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nLINGUTTER: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; Unlock every named layer that is locked, and hand back the list of
;; those that were -- entdel refuses an entity on a locked layer, so a
;; run that skipped this would quietly leave half the drawing behind.
(defun lg:unlock (names / out n rec ed f)
  (foreach n names
    (if (setq rec (tblobjname "LAYER" n))
      (progn
        (setq ed (entget rec)
              f  (cdr (assoc 70 ed)))
        (if (/= 0 (logand 4 f))
          (progn
            (entmod (subst (cons 70 (- f 4)) (assoc 70 ed) ed))
            (setq out (cons n out)))))))
  out)

(defun lg:relock (names / n rec ed f)
  (foreach n names
    (if (setq rec (tblobjname "LAYER" n))
      (progn
        (setq ed (entget rec)
              f  (cdr (assoc 70 ed)))
        (if (= 0 (logand 4 f))
          (entmod (subst (cons 70 (+ f 4)) (assoc 70 ed) ed)))))))

;;; -------------------- 2-D vector helpers ------------------------------
;;; Copied from the library, this file's prefix.  Strictly 2-element
;;; results; inputs may be 2- or 3-element (the Z is dropped).

(defun lg:2d (p) (list (car p) (cadr p)))
(defun lg:v- (a b) (mapcar '- (lg:2d a) (lg:2d b)))
(defun lg:v+ (a b) (mapcar '+ (lg:2d a) (lg:2d b)))
(defun lg:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun lg:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

;; normalize an angle into [0, 2pi)
(defun lg:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun lg:dir (a) (list (cos a) (sin a)))    ; unit vector at angle a

;;; -------------------- entities -> segments ----------------------------
;;; A segment is (p1 p2 bulge) with 2-D points, and a loop is a list of
;;; (x y bulge) vertices whose bulge belongs to the segment LEAVING it --
;;; PADDLE's shapes exactly, so a loop traced here can be handed to it.
;;; The four readers below and lg:chain are ports of paddle--arcdata,
;;; --lwverts, --plverts, --vts->segs, --ent-segs and --chain
;;; (lisp/paddle/PADDLE.lsp).  LINGUTTER is a standalone file and cannot
;;; call into PADDLE's, so tests/test_lingutter.py runs the two side by
;;; side on the same geometry and fails when they part company.

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun lg:arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (lg:v+ a (lg:v* (lg:dir (+ ts (if (> blg 0.0)
                                              (/ pi 2.0)
                                              (/ pi -2.0))))
                              r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
(defun lg:area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
      (progn
        (setq seg   (lg:arcdata a b blg)
              theta (abs (car seg))
              r     (cadr seg))
        (setq area (+ area (* (if (> blg 0.0) 1.0 -1.0)
                              0.5 r r (- theta (sin theta)))))))
    (setq i (1+ i)))
  area)

;; Length once round a closed vertex list, arcs measured along the arc.
(defun lg:perim-len (vts / n i a b blg total seg)
  (setq n (length vts) i 0 total 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq total
          (+ total
             (if (/= blg 0.0)
               (progn (setq seg (lg:arcdata a b blg))
                      (* (abs (car seg)) (cadr seg)))
               (distance (lg:2d a) (lg:2d b)))))
    (setq i (1+ i)))
  total)

;; LWPOLYLINE -> (closed-flag . vts)
(defun lg:lwverts (ent / ed out grp)
  (setq ed (entget ent))
  (foreach grp ed
    (cond
      ((= (car grp) 10)
       (setq out (cons (list (cadr grp) (caddr grp) 0.0) out)))
      ((= (car grp) 42)
       (if out (setq out (cons (list (caar out) (cadr (car out)) (cdr grp))
                               (cdr out)))))))
  (cons (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse out)))

;; heavy 2D POLYLINE -> (closed-flag . vts), nil for 3D/mesh plines
(defun lg:plverts (ent / ed flags e ved out p)
  (setq ed (entget ent) flags (cdr (assoc 70 ed)))
  (if (zerop (logand 112 flags))     ; skip 3D polylines / meshes / faces
    (progn
      (setq e (entnext ent))
      (while (and e (= "VERTEX" (cdr (assoc 0 (setq ved (entget e))))))
        (if (zerop (logand 16 (cond ((cdr (assoc 70 ved))) (0))))
          (progn
            (setq p (cdr (assoc 10 ved)))
            (setq out (cons (list (car p) (cadr p)
                                  (cond ((cdr (assoc 42 ved))) (0.0)))
                            out))))
        (setq e (entnext e)))
      (cons (= 1 (logand 1 flags)) (reverse out)))))

;; vertex list -> segments (wrapping when closed)
(defun lg:vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (lg:2d a) (lg:2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun lg:ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (lg:2d (cdr (assoc 10 ed)))
                 (lg:2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (lg:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (lg:v+ cen (lg:v* (lg:dir sa) r))
                 (lg:v+ cen (lg:v* (lg:dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0))))))
    ((= typ "LWPOLYLINE")
     (setq cv (lg:lwverts ent))
     (lg:vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (lg:plverts ent))
     (if cv (lg:vts->segs (car cv) (cdr cv))))))

;;; -------------------- tracing the exterior ----------------------------
;;; LINGUTTER does not look for a closed loop and hope one is the pool.
;;; It walks the OUTER FACE of the highlighted geometry and draws its own
;;; perimeter over it -- the outline you would get by walking round the
;;; outside of everything with your hand on the wall.
;;;
;;; Endpoints closer together than the snap tolerance become one node, so
;;; a drafting gap heals; every segment becomes two darts, one each way;
;;; and from the lowest node of each connected piece the walk always takes
;;; the hardest available RIGHT turn.  That rule is what hugs the outside:
;;; interior geometry -- the hopper, the steps, a bottom break -- is never
;;; stepped onto, because reaching it always needs a left turn.
;;;
;;; Three things follow, and they are the three ways the old
;;; largest-closed-loop guess got it wrong:
;;;   * a perimeter with a gap in it encloses nothing once its spurs are
;;;     pruned, so it fails LOUDLY at the tight tolerance instead of
;;;     quietly handing over whatever else did close;
;;;   * a hopper that closed while the outline did not can never win,
;;;     because it fails the coverage test below;
;;;   * and when no exterior can be walked at any tolerance there is
;;;     still an answer: the convex hull of everything highlighted.

;; A handful of points along one segment, its two ends included -- what
;; the coverage test measures and what the hull is wrapped round.  An arc
;; gets interior samples too: its bulge can carry it well outside the
;; straight line between its ends.
(defun lg:seg-pts (seg / a b blg dat cen r sa th i n out)
  (setq a   (car seg)
        b   (cadr seg)
        blg (caddr seg)
        out (list (lg:2d a) (lg:2d b)))
  (if (/= blg 0.0)
    (progn
      (setq dat (lg:arcdata a b blg)
            th  (car dat)
            r   (cadr dat)
            cen (caddr dat)
            sa  (angle cen a)
            n   6
            i   1)
      (repeat (1- n)
        (setq out (cons (lg:v+ cen (lg:v* (lg:dir (+ sa (* th (/ (float i) n))))
                                          r))
                        out)
              i   (1+ i)))))
  out)

(defun lg:segs-pts (segs / s out)
  (foreach s segs (setq out (append (lg:seg-pts s) out)))
  out)

;; The index of the node at P, adding P as a new node when nothing within
;; TOL is already there.  Returns (index nodelist).
(defun lg:node-of (p tol nodes / i n found)
  (setq i 0 found nil)
  (foreach n nodes
    (if (and (null found) (<= (distance (lg:2d p) n) tol)) (setq found i))
    (setq i (1+ i)))
  (if found
    (list found nodes)
    (list (length nodes) (append nodes (list (lg:2d p))))))

;; SEGS as a graph at snap tolerance TOL: (nodes segments), where each
;; segment is (node-a node-b bulge).  A segment whose two ends land on
;; the same node is dropped -- it is shorter than the tolerance and has
;; no direction left to walk in.
(defun lg:build-graph (segs tol / nodes segn s r ia ib)
  (foreach s segs
    (setq r     (lg:node-of (car s) tol nodes)
          ia    (car r)
          nodes (cadr r)
          r     (lg:node-of (cadr s) tol nodes)
          ib    (car r)
          nodes (cadr r))
    (if (/= ia ib) (setq segn (cons (list ia ib (caddr s)) segn))))
  (list nodes (reverse segn)))

;; The tangent angles of a segment travelled A -> B: (departing arriving).
;; A straight one departs and arrives on the same heading; an arc does
;; not, which is why the walk cannot just use (angle a b).
(defun lg:dart-tangents (a b blg / dat)
  (if (equal blg 0.0 1e-12)
    (list (angle a b) (angle a b))
    (progn
      (setq dat (lg:arcdata a b blg))
      (list (nth 3 dat) (nth 4 dat)))))

;; Every dart leaving node V, as (seg dir to departing arriving bulge).
(defun lg:darts-at (v nodes segn / i s a b tg out)
  (setq i 0)
  (foreach s segn
    (if (= (car s) v)
      (progn
        (setq a  (nth (car s) nodes)
              b  (nth (cadr s) nodes)
              tg (lg:dart-tangents a b (caddr s))
              out (cons (list i 1 (cadr s) (car tg) (cadr tg) (caddr s))
                        out))))
    (if (= (cadr s) v)
      (progn
        (setq a  (nth (cadr s) nodes)
              b  (nth (car s) nodes)
              tg (lg:dart-tangents a b (- (caddr s)))
              out (cons (list i -1 (car s) (car tg) (cadr tg) (- (caddr s)))
                        out))))
    (setq i (1+ i)))
  (reverse out))

(defun lg:same-dart (a b)
  (and a b (= (car a) (car b)) (= (cadr a) (cadr b))))

(defun lg:reverse-dart-p (a b)
  (and a b (= (car a) (car b)) (= (cadr a) (- (cadr b)))))

;; Arriving at V travelling at AIN, the next dart of the outer face: the
;; hardest right turn there is.  Measured as the smallest angle from the
;; way back (AIN + pi) round to the dart's departing tangent, taken over
;; (0, 2pi] so that turning straight back is the last resort rather than
;; the first choice.  Swap the sense of this one comparison and the same
;; walk traces interior faces instead.
(defun lg:next-dart (v ain nodes segn / darts d t2 best bt)
  (setq darts (lg:darts-at v nodes segn))
  (foreach d darts
    (setq t2 (lg:angnorm (- (nth 3 d) ain pi)))
    (if (<= t2 1e-9) (setq t2 (+ t2 pi pi)))
    (if (or (null best) (< t2 bt)) (setq best d bt t2)))
  best)

;; Every node reachable from V, so each connected piece of the highlight
;; is walked once and only once.
(defun lg:component (v segn / seen frontier nxt n s)
  (setq seen (list v) frontier (list v))
  (while frontier
    (setq nxt nil)
    (foreach n frontier
      (foreach s segn
        (cond
          ((and (= (car s) n) (not (member (cadr s) seen)))
           (setq seen (cons (cadr s) seen) nxt (cons (cadr s) nxt)))
          ((and (= (cadr s) n) (not (member (car s) seen)))
           (setq seen (cons (car s) seen) nxt (cons (car s) nxt))))))
    (setq frontier nxt))
  seen)

;; Node indices lowest first, leftmost breaking a tie.  A component's
;; lowest node is always on its outer boundary, which is why the walk
;; starts there and leaves along the shallowest edge it can find.
(defun lg:node-order (nodes / i n out)
  (setq i 0)
  (foreach n nodes
    (setq out (cons (list (cadr n) (car n) i) out)
          i   (1+ i)))
  (mapcar 'caddr
          (vl-sort out '(lambda (a b)
                          (if (equal (car a) (car b) 1e-9)
                            (< (cadr a) (cadr b))
                            (< (car a) (car b)))))))

;; Walk the outer face of the piece START belongs to.  Returns the darts
;; travelled, each consed onto the node it left, or nil when the walk
;; never closed (which a sound graph does not do -- the guard is there so
;; a pathological one cannot hang AutoCAD).
(defun lg:walk (start nodes segn / darts d first cur v ain out done guard lim)
  (setq darts (lg:darts-at start nodes segn))
  (if darts
    (progn
      (setq first (car darts))
      (foreach d darts
        (if (< (lg:angnorm (nth 3 d)) (lg:angnorm (nth 3 first)))
          (setq first d)))
      (setq cur   first
            v     start
            guard 0
            lim   (+ 10 (* 4 (length segn))))
      (while (not done)
        (setq out   (cons (cons v cur) out)
              ain   (nth 4 cur)
              v     (nth 2 cur)
              cur   (lg:next-dart v ain nodes segn)
              guard (1+ guard))
        (if (or (null cur) (> guard lim)
                (and (= v start) (lg:same-dart cur first)))
          (setq done T)))
      (if (> guard lim) nil (reverse out)))))

;; Drop every out-and-back excursion.  A dart followed by itself reversed
;; is a spur -- a tick mark, a stray line, or the whole of an outline that
;; never closed -- and the outer face really does run up it and back.  It
;; encloses nothing either way, and left in, PADDLE would read it as a
;; 180-degree inside corner and pad it.
(defun lg:prune (walk / out changed rest a b)
  (setq changed T)
  (while (and changed walk)
    (setq changed nil out nil rest walk)
    (while rest
      (setq a (car rest) b (cadr rest))
      (if (and b (lg:reverse-dart-p (cdr a) (cdr b)))
        (setq rest (cddr rest) changed T)
        (setq out (cons a out) rest (cdr rest))))
    (setq walk (reverse out))
    ;; the loop wraps, so its last dart and its first are neighbours too
    (if (and (> (length walk) 1)
             (lg:reverse-dart-p (cdr (last walk)) (cdr (car walk))))
      (setq walk    (reverse (cdr (reverse (cdr walk))))
            changed T)))
  walk)

(defun lg:walk-vts (walk nodes / w p out)
  (foreach w walk
    (setq p   (nth (car w) nodes)
          out (cons (list (car p) (cadr p) (nth 6 w)) out)))
  (reverse out))

;; The largest exterior the highlight can be walked round at tolerance
;; TOL.  Every connected piece is traced and the one enclosing the most
;; area wins -- a pool beside a stray line, or beside a second pool, comes
;; out right without anything having to rank them.
(defun lg:exterior (segs tol / g nodes segn seen v comp walk vts a
                                best bestarea)
  (setq g        (lg:build-graph segs tol)
        nodes    (car g)
        segn     (cadr g)
        bestarea 0.0)
  (foreach v (lg:node-order nodes)
    (if (not (member v seen))
      (progn
        (setq comp (lg:component v segn)
              seen (append seen comp)
              walk (lg:prune (lg:walk v nodes segn)))
        (if (and walk (> (length walk) 2))
          (progn
            (setq vts (lg:walk-vts walk nodes)
                  a   (abs (lg:area vts)))
            (if (> a bestarea) (setq bestarea a best vts)))))))
  best)

(defun lg:bbox (pts / p mnx mny mxx mxy)
  (foreach p pts
    (if (null mnx)
      (setq mnx (car p) mxx (car p) mny (cadr p) mxy (cadr p))
      (setq mnx (min mnx (car p)) mxx (max mxx (car p))
            mny (min mny (cadr p)) mxy (max mxy (cadr p)))))
  (if mnx (list mnx mny mxx mxy)))

;; T when the traced loop spans at least lg:*cover* of what was
;; highlighted, both ways.  This is the "is that really the perimeter?"
;; test, and it is the one the old code did not have: a hopper rectangle
;; traced because the outline round it never closed is a perfectly good
;; closed loop and a perfectly wrong answer.  Its extent gives it away.
(defun lg:covers-p (vts pts / lb pb w h)
  (setq lb (lg:bbox (lg:segs-pts (lg:vts->segs T vts)))
        pb (lg:bbox pts))
  (if (and lb pb)
    (progn
      (setq w (- (nth 2 pb) (car pb))
            h (- (nth 3 pb) (cadr pb)))
      (and (or (<= w 1e-9) (>= (/ (- (nth 2 lb) (car lb)) w) lg:*cover*))
           (or (<= h 1e-9) (>= (/ (- (nth 3 lb) (cadr lb)) h) lg:*cover*))))))

(defun lg:cross3 (o a b)
  (- (* (- (car a) (car o)) (- (cadr b) (cadr o)))
     (* (- (cadr a) (cadr o)) (- (car b) (car o)))))

;; Convex hull of PTS (Andrew's monotone chain).  The last resort: when no
;; exterior can be walked at any tolerance LINGUTTER still draws a
;; perimeter, and this one is guaranteed to enclose every bit of what was
;; highlighted.  It is reported as what it is -- a wrap, not a trace --
;; because it straightens out every concave feature PADDLE exists to find.
(defun lg:hull (pts / srt lower upper p out)
  (setq srt (vl-sort pts '(lambda (a b)
                            (if (equal (car a) (car b) 1e-9)
                              (< (cadr a) (cadr b))
                              (< (car a) (car b))))))
  (foreach p srt
    (while (and (cdr lower) (<= (lg:cross3 (cadr lower) (car lower) p) 0.0))
      (setq lower (cdr lower)))
    (setq lower (cons p lower)))
  (foreach p (reverse srt)
    (while (and (cdr upper) (<= (lg:cross3 (cadr upper) (car upper) p) 0.0))
      (setq upper (cdr upper)))
    (setq upper (cons p upper)))
  (setq out (append (reverse (cdr lower)) (reverse (cdr upper))))
  (if (> (length out) 2)
    (mapcar '(lambda (q) (list (car q) (cadr q) 0.0)) out)))

;; The perimeter of the highlighted geometry, and how it was arrived at.
;; Returns (vts (tol short)), where tol is
;;   nil     the exterior was walked with nothing moved,
;;   <n>     ...after ends that far apart were treated as one to close it,
;;   HULL    no exterior could be walked at all, so the geometry was
;;           simply wrapped,
;; and short is T when what was traced spans less of the highlight than
;; lg:*cover* asks -- a warning, never a veto.  Coverage decides whether
;; to try a looser tolerance, and the loosest run still wins over nothing:
;; a pool highlighted alongside a long stray line fails the test through
;; no fault of its own, and answering that with a convex hull would be
;; worse than answering it with the pool and a word of warning.
;; nil when there is not enough geometry to draw a perimeter round.
(defun lg:perimeter (segs / pts tol vts a out fall falla falltol tight)
  (setq pts   (lg:segs-pts segs)
        falla 0.0
        tight (car lg:*snaps*))
  (foreach tol lg:*snaps*
    (if (null out)
      (progn
        (setq vts (lg:exterior segs tol))
        (if vts
          (if (lg:covers-p vts pts)
            (setq out (list vts (list (if (equal tol tight 1e-12) nil tol)
                                      nil)))
            (progn
              (setq a (abs (lg:area vts)))
              (if (> a falla) (setq fall vts falla a falltol tol))))))))
  (if (and (null out) fall)
    (setq out (list fall (list (if (equal falltol tight 1e-12) nil falltol)
                               T))))
  (if (and (null out) pts)
    (progn
      (setq vts (lg:hull pts))
      (if vts (setq out (list vts (list 'HULL nil))))))
  out)

;;; -------------------- is it on the perimeter? -------------------------

;; distance from P to the straight segment A-B
(defun lg:pt-seg-dist (p a b / v w l u)
  (setq v (lg:v- b a)
        w (lg:v- p a)
        l (lg:dot v v))
  (if (<= l 1e-18)
    (distance (lg:2d p) a)
    (progn
      (setq u (/ (lg:dot w v) l)
            u (max 0.0 (min 1.0 u)))
      (distance (lg:2d p) (lg:v+ a (lg:v* v u))))))

;; distance from P to the arc A-B of bulge BLG: off the radius while P
;; lies within the sweep, off the nearer end once it does not
(defun lg:pt-arc-dist (p a b blg / dat cen th sa ap off)
  (setq dat (lg:arcdata a b blg)
        th  (car dat)
        cen (caddr dat)
        sa  (angle cen a)
        ap  (angle cen (lg:2d p))
        off (if (> th 0.0) (lg:angnorm (- ap sa)) (lg:angnorm (- sa ap))))
  (if (<= off (abs th))
    (abs (- (distance cen (lg:2d p)) (cadr dat)))
    (min (distance (lg:2d p) a) (distance (lg:2d p) b))))

(defun lg:pt-loop-dist (p vts / n i a b blg d best)
  (setq n (length vts) i 0 best nil)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a)
          d   (if (/= blg 0.0)
                (lg:pt-arc-dist p (lg:2d a) (lg:2d b) blg)
                (lg:pt-seg-dist p (lg:2d a) (lg:2d b))))
    (if (or (null best) (< d best)) (setq best d))
    (setq i (1+ i)))
  best)

;; The definition points that say what a dimension is attached to.  13
;; and 14 are the two measured points of a linear, aligned, ordinate or
;; angular dim; a radius or diameter dim carries neither and hangs off
;; 10, where its arrow lands on the curve.  Everything else in the
;; entity -- 11 (the text), 15/16 (an angular dim's second leg, a radius
;; dim's centre) -- places the dimension rather than attaching it, so it
;; is not tested: a radius dim on a 3" fillet would otherwise be judged
;; by a centre point 3" inside the pool.
(defun lg:dim-pts (ed / out p c)
  (foreach c '(13 14)
    (if (setq p (cdr (assoc c ed))) (setq out (cons p out))))
  (if (null out)
    (if (setq p (cdr (assoc 10 ed))) (setq out (list p))))
  out)

;; T when every attachment point sits within lg:*ontol* of the loop.
;; Every, not any: a dim running from the pool edge in to the hopper is
;; measuring the hopper, and one end on the perimeter does not make it a
;; perimeter dimension.
(defun lg:on-perim-p (ed vts / pts ok p)
  (setq pts (lg:dim-pts ed)
        ok  (and pts t))
  (foreach p pts
    (if (> (lg:pt-loop-dist p vts) lg:*ontol*) (setq ok nil)))
  ok)

;;; -------------------- styles and tallies ------------------------------

;; the dimension's style name, "" when it has none
(defun lg:dim-style (ed / s)
  (setq s (cdr (assoc 3 ed)))
  (if s s ""))

;; T when STY matches one of PATS.  The patterns are wildcards so that
;; "CROSS DIM*" covers a drawing whose style is spelled "CROSS DIM" and
;; one whose style is this repo's "CROSS DIMENSIONS"; case is folded,
;; because wcmatch is not.
(defun lg:stylep (sty pats / hit p)
  (setq sty (strcase sty))
  (foreach p pats
    (if (wcmatch sty (strcase p)) (setq hit t)))
  hit)

;; ((key . count) ...) with KEY's count raised by one
(defun lg:tally (key lst / p)
  (if (setq p (assoc key lst))
    (subst (cons key (1+ (cdr p))) p lst)
    (append lst (list (cons key 1)))))

(defun lg:s (n) (if (= n 1) "" "s"))

;; "A, B and C" from a list of strings
(defun lg:names (lst / n out)
  (setq out "")
  (while lst
    (setq n   (car lst)
          lst (cdr lst)
          out (cond ((= out "") n)
                    ((null lst) (strcat out " and " n))
                    (t (strcat out ", " n)))))
  out)

;;; -------------------- reading the drawing -----------------------------

;; every entity in the current tab, as a list of enames
;; The highlighted set: a pickfirst selection when there is one,
;; otherwise ask for it.  There is no "the whole drawing" answer --
;; LINGUTTER erases what it sweeps, so it sweeps only what you showed
;; it, and nothing outside the highlight is read, kept or erased.
(defun lg:highlight ( / ss)
  (setq ss (ssget "_I"))
  (if (null ss)
    (progn
      (princ "\nHighlight the area to gut: ")
      (setq ss (ssget))))
  ss)

;; the highlighted set as a list of enames
(defun lg:ss-ents (ss / i out)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq out (cons (ssname ss i) out)
            i   (1+ i))))
  (reverse out))

;; the segments the perimeter may be traced from: the drawn geometry
;; INSIDE the highlight, less the layers lg:*skiplayers* names
(defun lg:trace-segs (ss / i out en ed)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            ed (entget en)
            i  (1+ i))
      (if (and (member (cdr (assoc 0 ed))
                       '("LINE" "ARC" "LWPOLYLINE" "POLYLINE"))
               (not (member (strcase (cdr (assoc 8 ed)))
                            (mapcar 'strcase lg:*skiplayers*))))
        (setq out (append out (lg:ent-segs en))))))
  out)

;; Everything both commands need to know about the highlighted set SS,
;; worked out without changing a thing.  Nothing outside SS is looked
;; at: the perimeter is traced from the geometry in it, and only what
;; is in it can be kept or erased.
;; Returns (vts gap kill nany nperim dropped nother nspared):
;;   vts      the perimeter as (x y bulge) vertices, nil when none found
;;   how      (tol short) from lg:perimeter: how the perimeter was
;;            arrived at, and whether it covers the highlight
;;   kill     the entities that would be erased
;;   nany     dims kept for their style alone
;;   nperim   dims kept because they sit on the perimeter
;;   dropped  ((reason . count) ...) for the dimensions that would go
;;   nother   objects that would go which are not dimensions
;;   nspared  objects left alone because lg:*keeplayers* names their layer
(defun lg:analyze (ss / best vts how kill nany nperim dropped nother
                        nspared en ed typ sty lay spare)
  (setq best    (lg:perimeter (lg:trace-segs ss))
        vts     (car best)
        how     (cadr best)
        nany    0
        nperim  0
        nother  0
        nspared 0
        spare   (mapcar 'strcase lg:*keeplayers*))
  (if vts
    (foreach en (lg:ss-ents ss)
      (setq ed  (entget en)
            typ (cdr (assoc 0 ed))
            lay (strcase (cond ((cdr (assoc 8 ed))) ("0"))))
      (cond
        ((= typ "VIEWPORT") nil)             ; never ours to erase
        ((member lay spare) (setq nspared (1+ nspared)))
        ((= typ "DIMENSION")
         (setq sty (lg:dim-style ed))
         (cond
           ((lg:stylep sty lg:*anystyles*)
            (setq nany (1+ nany)))
           ((and (lg:stylep sty lg:*perimstyles*) (lg:on-perim-p ed vts))
            (setq nperim (1+ nperim)))
           (t
            (setq dropped
                  (lg:tally (strcat (if (= sty "") "(no style)" sty)
                                    (if (lg:stylep sty lg:*perimstyles*)
                                      " - not on the perimeter"
                                      " - style not kept"))
                            dropped)
                  kill (cons en kill)))))
        (t (setq nother (1+ nother)
                 kill   (cons en kill))))))
  (list vts how (reverse kill) nany nperim dropped nother nspared))

;;; -------------------- writing the drawing -----------------------------

;; One closed LWPOLYLINE through VTS on LAY, ByLayer -- no per-entity
;; colour, linetype or lineweight, so the perimeter looks like whatever
;; the POOL layer says, the way POOL and DRONE leave it.
(defun lg:draw-perim (vts lay / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE")
                  '(100 . "AcDbEntity")
                  (cons 8 lay)
                  '(100 . "AcDbPolyline")
                  (cons 90 (length vts))
                  '(70 . 1)))
  (foreach v vts
    (setq dxf (append dxf (list (cons 10 (list (car v) (cadr v))))))
    (if (/= 0.0 (caddr v))
      (setq dxf (append dxf (list (cons 42 (caddr v)))))))
  (entmakex dxf))

;; the layers the erase has to reach, so the locked ones among them can
;; be opened first
(defun lg:kill-layers (kill / out en ed lay)
  (foreach en kill
    (setq ed  (entget en)
          lay (cond ((cdr (assoc 8 ed))) ("0")))
    (if (not (member lay out)) (setq out (cons lay out))))
  out)

;;; -------------------- the report --------------------------------------

(defun lg:report (res / vts how kill nany nperim dropped nother nspared d)
  (setq vts     (nth 0 res)
        how     (nth 1 res)
        kill    (nth 2 res)
        nany    (nth 3 res)
        nperim  (nth 4 res)
        dropped (nth 5 res)
        nother  (nth 6 res)
        nspared (nth 7 res))
  (if (null vts)
    (princ (strcat "\nLINGUTTER: nothing to draw a perimeter round - the"
                   " highlight holds no lines, arcs or polylines, or none"
                   " off " (lg:names lg:*skiplayers*) "."))
    (progn
      (princ (strcat "\nLINGUTTER: perimeter "
                     (if (eq (car how) 'HULL) "wrapped" "traced") " - "
                     (itoa (length vts)) " vertice" (lg:s (length vts)) ", "
                     (rtos (lg:perim-len vts)) " around."))
      (cond
        ((eq (car how) 'HULL)
         (princ (strcat "\n** No exterior could be walked at any tolerance"
                        " up to " (rtos (last lg:*snaps*) 2 2) " - the"
                        " highlight is wrapped in its convex hull instead."
                        "  That straightens out every concave feature, so"
                        " PADDLE will find nothing to pad: close the"
                        " outline and run it again.")))
        ((car how)
         (princ (strcat "\nLINGUTTER: it would not close as drawn - ends up"
                        " to " (rtos (car how)) " apart were treated as one"
                        " to walk round it."))))
      (if (cadr how)
        (princ (strcat "\n** What was traced spans less than "
                       (rtos (* 100.0 lg:*cover*) 2 0) "% of what you"
                       " highlighted.  Check it really is the pool before"
                       " answering Yes - highlighting less, or closing the"
                       " outline, is what fixes it.")))
      (princ (strcat "\nLINGUTTER: keeping " (itoa nany) " dimension"
                     (lg:s nany) " in " (lg:names lg:*anystyles*)
                     " (kept wherever they sit)."))
      (princ (strcat "\nLINGUTTER: keeping " (itoa nperim) " dimension"
                     (lg:s nperim) " on the perimeter in "
                     (lg:names lg:*perimstyles*) "."))
      (princ (strcat "\nLINGUTTER: erasing " (itoa (length kill))
                     " highlighted object" (lg:s (length kill)) " - "
                     (itoa nother)
                     " drawn object" (lg:s nother) " and "
                     (itoa (apply '+ (cons 0 (mapcar 'cdr dropped))))
                     " dimension"
                     (lg:s (apply '+ (cons 0 (mapcar 'cdr dropped))))
                     (if dropped ":" ".")))
      (foreach d dropped
        (princ (strcat "\n             " (itoa (cdr d)) " x " (car d))))
      (if (> nspared 0)
        (princ (strcat "\nLINGUTTER: " (itoa nspared) " object"
                       (lg:s nspared) " left alone on "
                       (lg:names lg:*keeplayers*) ".")))))
  (princ))

;;; -------------------- handing over to PADDLE --------------------------

;; Hand PERIM over as a pickfirst selection rather than letting PADDLE
;; hunt for it: PADDLE auto-detects the largest closed loop in the WHOLE
;; drawing, and LINGUTTER only ever gutted the highlighted area -- a
;; title block border still standing outside it is a bigger loop than
;; the pool.  Highlighted, PADDLE pads what we drew and asks nothing.
;;
;; PADDLE is its own file, so it may not be in this session.  When it is
;; not, the gut has still happened and saying so beats dying on an
;; undefined function.
(defun lg:paddle (perim / ss)
  (cond
    ((not lg:*runpaddle*)
     (princ "\nLINGUTTER: lg:*runpaddle* is nil - stopping before PADDLE."))
    (c:PADDLE
     (if perim
       (progn
         (setq ss (ssadd))
         (ssadd perim ss)
         (sssetfirst nil ss)))
     (princ "\nLINGUTTER: handing the new perimeter to PADDLE.")
     (c:PADDLE))
    (t
     (princ (strcat "\nLINGUTTER: PADDLE is not loaded, so no pads were"
                    " placed.  APPLOAD PADDLE.lsp (or the shared"
                    " LAZPASS.lsp build) and type PADDLE."))))
  (princ))

;;; -------------------- the commands ------------------------------------

(defun c:LINGUTTER ( / *error* undo-open ss res vts kill
                       locked en ask perim)

  ;; The user's settings come back FIRST so nothing below can skip them,
  ;; then the undo group is closed - or the next U would swallow the
  ;; user's own work along with this run - and any layer this command
  ;; unlocked is locked again.
  (defun *error* (m)
    (lg:sysrestore)
    (if locked (lg:relock locked))
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINGUTTER error: " m)))
    (princ))

  (lg:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (princ (strcat "\nLINGUTTER " *lingutter-version*))

  (setq ss (lg:highlight))
  (if (null ss)
    (princ "\nLINGUTTER: nothing highlighted - nothing to gut.")
    (progn
      (setq res  (lg:analyze ss)
            vts  (nth 0 res)
            kill (nth 2 res))
      (lg:report res)))

  ;; no perimeter, no question: without one there is no telling which of
  ;; the highlighted lines was the pool, so nothing is erased
  (if vts
    (progn
      (setq ask (strcat "Erase the " (itoa (length kill))
                        " highlighted object" (lg:s (length kill))
                        " LINGUTTER did not keep?"))
      (if (not (lg:askyn ask "No" nil))
        (princ "\nLINGUTTER: nothing erased - the drawing is as you left it.")
        (progn
          (setvar "CMDECHO" 0)
          (setvar "OSMODE" 0)
          ;; only when undo is recording - _Begin in a drawing with UNDO
          ;; off (bit 1 of UNDOCTL clear) errors out of the command
          (if (= 1 (logand 1 (getvar "UNDOCTL")))
            (progn
              (command "_.UNDO" "_Begin")
              (setq undo-open T)))
          ;; entdel refuses an entity on a locked layer, so open the ones
          ;; this erase has to reach and shut them again afterwards
          (setq locked (lg:unlock (lg:kill-layers kill)))
          (foreach en kill (if (entget en) (entdel en)))
          (setvar "CLAYER" (lg:ensure-layer lg:*poollayer* lg:*poolcolor*))
          (setq perim (lg:draw-perim vts lg:*poollayer*))
          (lg:relock locked)
          (setq locked nil)
          (command "_.UNDO" "_End")
          (setq undo-open nil)
          (princ (strcat "\nLINGUTTER: " (itoa (length kill))
                         " highlighted object" (lg:s (length kill))
                         " erased; the perimeter is one closed polyline"
                         " on layer " lg:*poollayer*
                         ".  Nothing outside the highlight was touched."))
          ;; the sysvars go back BEFORE PADDLE runs: it is a command in its
          ;; own right and must start from the user's settings, not this
          ;; one's zeroed OSMODE
          (lg:sysrestore)
          (lg:paddle perim)))))

  (lg:sysrestore)
  (princ))

(defun c:LINGUTTERSCAN ( / *error* ss)
  (defun *error* (m)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINGUTTERSCAN error: " m)))
    (princ))
  (princ (strcat "\nLINGUTTERSCAN " *lingutter-version*
                 " - reading only, nothing in the drawing is changed."))
  (setq ss (lg:highlight))
  (if (null ss)
    (princ "\nLINGUTTERSCAN: nothing highlighted - nothing to report on.")
    (progn
      (lg:report (lg:analyze ss))
      (princ "\nLINGUTTERSCAN: nothing changed.  Type LINGUTTER to do it.")))
  (princ))

(defun c:LINGUTTERVER ()
  (princ (strcat "\nLINGUTTER " *lingutter-version*))
  (princ))

(princ (strcat "\nLINGUTTER " *lingutter-version*
               " loaded -- highlight an area: its perimeter goes onto \""
               lg:*poollayer* "\", the rest of it is erased, PADDLE runs."
               "\nLINGUTTERSCAN reports what it would do and changes"
               " nothing."))
(princ)
