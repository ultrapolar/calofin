;;; ======================================================================
;;; POOLPERIM.lsp  --  strip a drawing back to its outermost perimeter,
;;;                    the dimensions worth keeping, and PADDLE's pads
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  POOLPERIM       trace the perimeter, erase the rest, PADDLE
;;;            POOLPERIMSCAN   report what it would keep and erase, and stop
;;;            POOLPERIMVER    print the loaded version
;;;
;;;  A finished as-built sheet carries far more than the next station
;;;  needs: the hopper and its slope lines, steps, survey points and
;;;  their labels, the title block, the notes.  POOLPERIM cuts it back
;;;  to three things and then pads what is left:
;;;
;;;    1. TRACE.  Every LINE, ARC, LWPOLYLINE and POLYLINE in the tab is
;;;       broken into segments and chained end to end into closed loops.
;;;       The loop enclosing the largest area is the outermost one, and
;;;       that is the perimeter.  It is redrawn as ONE closed
;;;       LWPOLYLINE on the "POOL" layer, ByLayer, arcs carried as
;;;       bulges -- so what comes out is a single object however it was
;;;       drawn going in: one polyline, or fifty loose lines and arcs.
;;;
;;;    2. KEEP.  Two rules, and nothing else survives them:
;;;         * a dimension in a pp:*anystyles* style ("CROSS DIM*", which
;;;           catches both "CROSS DIM" and this repo's "CROSS
;;;           DIMENSIONS") is kept wherever it sits -- a cross dim
;;;           spans the pool, so most of it is nowhere near the edge;
;;;         * a dimension in a pp:*perimstyles* style ("STANDARD",
;;;           "SIDE STANDARD") is kept only when it is ON the perimeter
;;;           -- every one of its attachment points within
;;;           pp:*ontol* of the loop.  The same style measuring a
;;;           hopper or a step goes with the rest.
;;;       Everything else in the tab is erased: text, blocks, points,
;;;       hatches, the title block, the geometry the perimeter was
;;;       traced from, and dimensions in any other style.  Name a layer
;;;       in pp:*keeplayers* to spare it outright.
;;;
;;;    3. PADDLE.  The stripped drawing is handed to PADDLE, which pads
;;;       the concave features of the one loop now left.
;;;
;;;  POOLPERIM erases a great deal, so it asks first -- after printing
;;;  exactly what it found, and defaulting to No.  POOLPERIMSCAN prints
;;;  the same report and stops without touching the drawing; run it
;;;  first on a sheet you care about.  The whole run is one undo group:
;;;  a single U puts the drawing back.
;;;
;;;  Usage
;;;    Command: POOLPERIM       Enter at the selection prompt reads the
;;;                             whole tab; select geometry to trace the
;;;                             perimeter from a part of it instead
;;;    Command: POOLPERIMSCAN   the report, and nothing else
;;;    Command: POOLPERIMVER    prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  names, e.g. in a startup file):
;;;    pp:*poollayer*    layer the perimeter is drawn on    ("POOL")
;;;    pp:*poolcolor*    its colour when the layer has to be created
;;;    pp:*anystyles*    dim styles kept wherever they sit, as wildcard
;;;                      patterns matched against the style name
;;;    pp:*perimstyles*  dim styles kept only on the perimeter
;;;    pp:*keeplayers*   layers left alone entirely (nil = none)
;;;    pp:*skiplayers*   layers the perimeter is never traced from
;;;    pp:*ontol*        how far a dimension's attachment point may sit
;;;                      off the perimeter and still count as on it
;;;    pp:*fuzz*         largest gap between two segment ends that still
;;;                      chains them together
;;;    pp:*gap*          largest end-to-end gap POOLPERIM will close to
;;;                      turn an almost-closed trace into a perimeter
;;;    pp:*runpaddle*    T to run PADDLE at the end, nil to stop after
;;;                      the strip
;;;
;;;  Notes
;;;    * "STANDARD INCHES" is deliberately NOT in pp:*perimstyles*: the
;;;      request named STANDARD and SIDE STANDARD.  A perimeter side
;;;      under 12" that AUTODIM put in STANDARD INCHES therefore goes
;;;      with the rest -- but it is never silent about it, the report
;;;      counts every dropped dimension by style.  Add the style to
;;;      pp:*perimstyles* to keep those too.
;;;    * The perimeter is always redrawn, even when it was already one
;;;      closed polyline on POOL, so the result is the same object
;;;      whatever went in.  An associative dimension attached to the old
;;;      geometry loses its association (the measurement and the
;;;      definition points do not move -- the new polyline is drawn
;;;      through the same points).
;;;    * Only the CURRENT tab is read and changed; another layout is
;;;      untouched.  VIEWPORT entities are never erased.
;;;    * A locked layer is unlocked for the erase and locked again
;;;      afterwards.  A frozen or switched-off layer is not thawed --
;;;      what POOLPERIM cannot see it does not trace from, but ssget
;;;      still reaches it to erase.
;;;    * PADDLE lives in its own file.  When this session has not
;;;      loaded it the strip still happens and POOLPERIM says so
;;;      instead of failing.
;;;    * CLAYER, CMDECHO and OSMODE in force before the command are
;;;      restored afterwards, on a clean finish, an error, or Esc.
;;; ======================================================================

(setq *poolperim-version* "v1.0")  ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

(setq pp:*poollayer*   "POOL")
(setq pp:*poolcolor*   4)          ; ACI 4 = cyan, POOL's own colour
(setq pp:*anystyles*   '("CROSS DIM*"))
(setq pp:*perimstyles* '("STANDARD" "SIDE STANDARD"))
(setq pp:*keeplayers*  nil)        ; e.g. '("TITLEBLOCK") to spare one
(setq pp:*skiplayers*  '("DEFPOINTS" "DIMENSION"))
(setq pp:*ontol*       1.0)        ; drawing units; inches by default
(setq pp:*fuzz*        0.05)       ; PADDLE's chaining tolerance
(setq pp:*gap*         6.0)        ; largest end gap worth closing
(setq pp:*runpaddle*   t)
(setq pp:*sysold*      nil)        ; sysvar snapshot, live only mid-run

;;; -------------------- ask layer ---------------------------------------
;;; STANDARDS.md section 4, copied from the library so this file loads
;;; alone.  kws is the canonical keyword string -- it is BOTH the initget
;;; list and the bracket text, so the two can never drift.

(defun pp:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'PP-BACK)
        ((null v) (if dflt dflt (pp:askkw msg kws hidden dflt back)))
        (t v)))

;; Yes/No.  dflt is always shown; destructive actions default "No".
(defun pp:askyn (msg dflt back / v)
  (setq v (pp:askkw msg "Yes No" nil dflt back))
  (if (eq v 'PP-BACK) v (= v "Yes")))

;;; -------------------- drawing state -----------------------------------
;;; The sysvars this tool moves, saved in restore order -- OSMODE first,
;;; because object snaps are the setting the user misses most if a run is
;;; ever cut short partway.

(defun pp:syssave (vars / v)
  (if (not pp:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq pp:*sysold*
              (append pp:*sysold* (list (cons v (getvar v)))))))))

(defun pp:sysrestore ( / p)
  (foreach p pp:*sysold* (setvar (car p) (cdr p)))
  (setq pp:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun pp:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nPOOLPERIM: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; Unlock every named layer that is locked, and hand back the list of
;; those that were -- entdel refuses an entity on a locked layer, so a
;; run that skipped this would quietly leave half the drawing behind.
(defun pp:unlock (names / out n rec ed f)
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

(defun pp:relock (names / n rec ed f)
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

(defun pp:2d (p) (list (car p) (cadr p)))
(defun pp:v- (a b) (mapcar '- (pp:2d a) (pp:2d b)))
(defun pp:v+ (a b) (mapcar '+ (pp:2d a) (pp:2d b)))
(defun pp:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun pp:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

;; normalize an angle into [0, 2pi)
(defun pp:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun pp:dir (a) (list (cos a) (sin a)))    ; unit vector at angle a

;;; -------------------- entities -> segments ----------------------------
;;; A segment is (p1 p2 bulge) with 2-D points, and a loop is a list of
;;; (x y bulge) vertices whose bulge belongs to the segment LEAVING it --
;;; PADDLE's shapes exactly, so a loop traced here can be handed to it.
;;; The four readers below and pp:chain are ports of paddle--arcdata,
;;; --lwverts, --plverts, --vts->segs, --ent-segs and --chain
;;; (lisp/paddle/PADDLE.lsp).  POOLPERIM is a standalone file and cannot
;;; call into PADDLE's, so tests/test_poolperim.py runs the two side by
;;; side on the same geometry and fails when they part company.

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun pp:arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (pp:v+ a (pp:v* (pp:dir (+ ts (if (> blg 0.0)
                                              (/ pi 2.0)
                                              (/ pi -2.0))))
                              r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
(defun pp:area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
      (progn
        (setq seg   (pp:arcdata a b blg)
              theta (abs (car seg))
              r     (cadr seg))
        (setq area (+ area (* (if (> blg 0.0) 1.0 -1.0)
                              0.5 r r (- theta (sin theta)))))))
    (setq i (1+ i)))
  area)

;; Length once round a closed vertex list, arcs measured along the arc.
(defun pp:perim-len (vts / n i a b blg total seg)
  (setq n (length vts) i 0 total 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq total
          (+ total
             (if (/= blg 0.0)
               (progn (setq seg (pp:arcdata a b blg))
                      (* (abs (car seg)) (cadr seg)))
               (distance (pp:2d a) (pp:2d b)))))
    (setq i (1+ i)))
  total)

;; LWPOLYLINE -> (closed-flag . vts)
(defun pp:lwverts (ent / ed out grp)
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
(defun pp:plverts (ent / ed flags e ved out p)
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
(defun pp:vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (pp:2d a) (pp:2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun pp:ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (pp:2d (cdr (assoc 10 ed)))
                 (pp:2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (pp:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (pp:v+ cen (pp:v* (pp:dir sa) r))
                 (pp:v+ cen (pp:v* (pp:dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0))))))
    ((= typ "LWPOLYLINE")
     (setq cv (pp:lwverts ent))
     (pp:vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (pp:plverts ent))
     (if cv (pp:vts->segs (car cv) (cdr cv))))))

;;; -------------------- chaining ----------------------------------------

;; Chains touching segments (ends within pp:*fuzz*) end to end.  Returns
;; (loops . opens): each loop is a closed vertex list, and each open
;; entry is (vts . gap) -- the chain that ran out of neighbours, its
;; loose tail carried as a final bulge-0 vertex, and how far that tail
;; finished from the head.  PADDLE throws the open chains away and only
;; counts them; POOLPERIM keeps them, because a perimeter drawn with one
;; missed snap is still the perimeter and closing it is a better answer
;; than "no closed loop found".
(defun pp:chain (segs / loops opens chain head tail done found rest s gap)
  ;; drop degenerate slivers
  (setq segs (vl-remove-if
               '(lambda (s) (<= (distance (car s) (cadr s)) pp:*fuzz*))
               segs))
  (while segs
    (setq chain (list (car segs))
          head  (car (car segs))
          tail  (cadr (car segs))
          segs  (cdr segs)
          done  nil)
    (while (not done)
      (cond
        ;; loop closed back onto its start?
        ((and (> (length chain) 1) (<= (distance tail head) pp:*fuzz*))
         (setq loops (cons (mapcar '(lambda (s) (list (car (car s))
                                                      (cadr (car s))
                                                      (caddr s)))
                                   chain)
                           loops)
               done  T))
        (T ;; look for a segment continuing from the tail
         (setq found nil rest nil)
         (foreach s segs
           (if found
             (setq rest (cons s rest))
             (cond
               ((<= (distance tail (car s)) pp:*fuzz*)
                (setq found s))
               ((<= (distance tail (cadr s)) pp:*fuzz*)    ; reversed
                (setq found (list (cadr s) (car s) (- (caddr s)))))
               (T (setq rest (cons s rest))))))
         (if found
           (setq chain (append chain (list found))
                 tail  (cadr found)
                 segs  (reverse rest))
           (progn                                ; dead end: open chain
             (setq gap   (distance tail head)
                   opens (cons (cons (append
                                       (mapcar '(lambda (s)
                                                  (list (car (car s))
                                                        (cadr (car s))
                                                        (caddr s)))
                                               chain)
                                       (list (list (car tail) (cadr tail)
                                                   0.0)))
                                     gap)
                               opens)
                   done  T)))))))
  (cons (reverse loops) (reverse opens)))

;; The outermost loop in SEGS, as (vts . gap-closed): the closed loop
;; enclosing the largest area, or - when nothing closed on its own - the
;; largest almost-closed chain whose two ends finished within pp:*gap*,
;; shut with a straight segment.  nil when neither exists.
(defun pp:outer (segs / res loops opens best bestarea a vts oc)
  (setq res      (pp:chain segs)
        loops    (car res)
        opens    (cdr res)
        bestarea 0.0)
  (foreach vts loops
    (setq a (abs (pp:area vts)))
    (if (> a bestarea) (setq bestarea a best (cons vts nil))))
  (if (null best)
    (foreach oc opens
      (if (<= (cdr oc) pp:*gap*)
        (progn
          (setq vts (car oc)
                a   (abs (pp:area vts)))
          (if (> a bestarea)
            (setq bestarea a best (cons vts (cdr oc))))))))
  best)

;;; -------------------- is it on the perimeter? -------------------------

;; distance from P to the straight segment A-B
(defun pp:pt-seg-dist (p a b / v w l u)
  (setq v (pp:v- b a)
        w (pp:v- p a)
        l (pp:dot v v))
  (if (<= l 1e-18)
    (distance (pp:2d p) a)
    (progn
      (setq u (/ (pp:dot w v) l)
            u (max 0.0 (min 1.0 u)))
      (distance (pp:2d p) (pp:v+ a (pp:v* v u))))))

;; distance from P to the arc A-B of bulge BLG: off the radius while P
;; lies within the sweep, off the nearer end once it does not
(defun pp:pt-arc-dist (p a b blg / dat cen th sa ap off)
  (setq dat (pp:arcdata a b blg)
        th  (car dat)
        cen (caddr dat)
        sa  (angle cen a)
        ap  (angle cen (pp:2d p))
        off (if (> th 0.0) (pp:angnorm (- ap sa)) (pp:angnorm (- sa ap))))
  (if (<= off (abs th))
    (abs (- (distance cen (pp:2d p)) (cadr dat)))
    (min (distance (pp:2d p) a) (distance (pp:2d p) b))))

(defun pp:pt-loop-dist (p vts / n i a b blg d best)
  (setq n (length vts) i 0 best nil)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a)
          d   (if (/= blg 0.0)
                (pp:pt-arc-dist p (pp:2d a) (pp:2d b) blg)
                (pp:pt-seg-dist p (pp:2d a) (pp:2d b))))
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
(defun pp:dim-pts (ed / out p c)
  (foreach c '(13 14)
    (if (setq p (cdr (assoc c ed))) (setq out (cons p out))))
  (if (null out)
    (if (setq p (cdr (assoc 10 ed))) (setq out (list p))))
  out)

;; T when every attachment point sits within pp:*ontol* of the loop.
;; Every, not any: a dim running from the pool edge in to the hopper is
;; measuring the hopper, and one end on the perimeter does not make it a
;; perimeter dimension.
(defun pp:on-perim-p (ed vts / pts ok p)
  (setq pts (pp:dim-pts ed)
        ok  (and pts t))
  (foreach p pts
    (if (> (pp:pt-loop-dist p vts) pp:*ontol*) (setq ok nil)))
  ok)

;;; -------------------- styles and tallies ------------------------------

;; the dimension's style name, "" when it has none
(defun pp:dim-style (ed / s)
  (setq s (cdr (assoc 3 ed)))
  (if s s ""))

;; T when STY matches one of PATS.  The patterns are wildcards so that
;; "CROSS DIM*" covers a drawing whose style is spelled "CROSS DIM" and
;; one whose style is this repo's "CROSS DIMENSIONS"; case is folded,
;; because wcmatch is not.
(defun pp:stylep (sty pats / hit p)
  (setq sty (strcase sty))
  (foreach p pats
    (if (wcmatch sty (strcase p)) (setq hit t)))
  hit)

;; ((key . count) ...) with KEY's count raised by one
(defun pp:tally (key lst / p)
  (if (setq p (assoc key lst))
    (subst (cons key (1+ (cdr p))) p lst)
    (append lst (list (cons key 1)))))

(defun pp:s (n) (if (= n 1) "" "s"))

;; "A, B and C" from a list of strings
(defun pp:names (lst / n out)
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
(defun pp:tab-ents ( / ss i out)
  (setq ss (ssget "_X" (list (cons 410 (getvar "CTAB")))) i 0)
  (if ss
    (repeat (sslength ss)
      (setq out (cons (ssname ss i) out)
            i   (1+ i))))
  (reverse out))

;; the segments the perimeter may be traced from: the drawn geometry of
;; the tab, less the layers pp:*skiplayers* names.  SS is a selection
;; the user made, or nil for the whole tab.
(defun pp:trace-segs (ss / i out en ed)
  (if (null ss)
    (setq ss (ssget "_X" (list '(0 . "LINE,ARC,LWPOLYLINE,POLYLINE")
                               (cons 410 (getvar "CTAB"))))))
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq en (ssname ss i)
            ed (entget en)
            i  (1+ i))
      (if (and (member (cdr (assoc 0 ed))
                       '("LINE" "ARC" "LWPOLYLINE" "POLYLINE"))
               (not (member (strcase (cdr (assoc 8 ed)))
                            (mapcar 'strcase pp:*skiplayers*))))
        (setq out (append out (pp:ent-segs en))))))
  out)

;; Everything both commands need to know, worked out without changing a
;; thing.  Returns (vts gap kill nany nperim dropped nother nspared):
;;   vts      the perimeter as (x y bulge) vertices, nil when none found
;;   gap      the end gap closed to make it, nil when it closed itself
;;   kill     the entities that would be erased
;;   nany     dims kept for their style alone
;;   nperim   dims kept because they sit on the perimeter
;;   dropped  ((reason . count) ...) for the dimensions that would go
;;   nother   objects that would go which are not dimensions
;;   nspared  objects left alone because pp:*keeplayers* names their layer
(defun pp:analyze (ss / best vts gap kill nany nperim dropped nother
                        nspared en ed typ sty lay spare)
  (setq best    (pp:outer (pp:trace-segs ss))
        vts     (car best)
        gap     (cdr best)
        nany    0
        nperim  0
        nother  0
        nspared 0
        spare   (mapcar 'strcase pp:*keeplayers*))
  (if vts
    (foreach en (pp:tab-ents)
      (setq ed  (entget en)
            typ (cdr (assoc 0 ed))
            lay (strcase (cond ((cdr (assoc 8 ed))) ("0"))))
      (cond
        ((= typ "VIEWPORT") nil)             ; never ours to erase
        ((member lay spare) (setq nspared (1+ nspared)))
        ((= typ "DIMENSION")
         (setq sty (pp:dim-style ed))
         (cond
           ((pp:stylep sty pp:*anystyles*)
            (setq nany (1+ nany)))
           ((and (pp:stylep sty pp:*perimstyles*) (pp:on-perim-p ed vts))
            (setq nperim (1+ nperim)))
           (t
            (setq dropped
                  (pp:tally (strcat (if (= sty "") "(no style)" sty)
                                    (if (pp:stylep sty pp:*perimstyles*)
                                      " - not on the perimeter"
                                      " - style not kept"))
                            dropped)
                  kill (cons en kill)))))
        (t (setq nother (1+ nother)
                 kill   (cons en kill))))))
  (list vts gap (reverse kill) nany nperim dropped nother nspared))

;;; -------------------- writing the drawing -----------------------------

;; One closed LWPOLYLINE through VTS on LAY, ByLayer -- no per-entity
;; colour, linetype or lineweight, so the perimeter looks like whatever
;; the POOL layer says, the way POOL and DRONE leave it.
(defun pp:draw-perim (vts lay / dxf v)
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
(defun pp:kill-layers (kill / out en ed lay)
  (foreach en kill
    (setq ed  (entget en)
          lay (cond ((cdr (assoc 8 ed))) ("0")))
    (if (not (member lay out)) (setq out (cons lay out))))
  out)

;;; -------------------- the report --------------------------------------

(defun pp:report (res / vts gap kill nany nperim dropped nother nspared d)
  (setq vts     (nth 0 res)
        gap     (nth 1 res)
        kill    (nth 2 res)
        nany    (nth 3 res)
        nperim  (nth 4 res)
        dropped (nth 5 res)
        nother  (nth 6 res)
        nspared (nth 7 res))
  (if (null vts)
    (princ (strcat "\nPOOLPERIM: no perimeter found - nothing closed"
                   " into a loop, and no open trace finished within "
                   (rtos pp:*gap* 2 2) " of its own start.  Check for"
                   " gaps, or select the perimeter geometry yourself."))
    (progn
      (princ (strcat "\nPOOLPERIM: perimeter traced - " (itoa (length vts))
                     " vertice" (pp:s (length vts)) ", "
                     (rtos (pp:perim-len vts)) " around."))
      (if gap
        (princ (strcat "\nPOOLPERIM: it did not close on its own - a "
                       (rtos gap) " gap between its two ends was shut"
                       " with a straight segment.")))
      (princ (strcat "\nPOOLPERIM: keeping " (itoa nany) " dimension"
                     (pp:s nany) " in " (pp:names pp:*anystyles*)
                     " (kept wherever they sit)."))
      (princ (strcat "\nPOOLPERIM: keeping " (itoa nperim) " dimension"
                     (pp:s nperim) " on the perimeter in "
                     (pp:names pp:*perimstyles*) "."))
      (princ (strcat "\nPOOLPERIM: erasing " (itoa (length kill))
                     " object" (pp:s (length kill)) " - " (itoa nother)
                     " drawn object" (pp:s nother) " and "
                     (itoa (apply '+ (cons 0 (mapcar 'cdr dropped))))
                     " dimension"
                     (pp:s (apply '+ (cons 0 (mapcar 'cdr dropped))))
                     (if dropped ":" ".")))
      (foreach d dropped
        (princ (strcat "\n             " (itoa (cdr d)) " x " (car d))))
      (if (> nspared 0)
        (princ (strcat "\nPOOLPERIM: " (itoa nspared) " object"
                       (pp:s nspared) " left alone on "
                       (pp:names pp:*keeplayers*) ".")))))
  (princ))

;;; -------------------- handing over to PADDLE --------------------------

;; PADDLE is its own file, so it may not be in this session.  When it is
;; not, the strip has still happened and saying so beats dying on an
;; undefined function.
(defun pp:paddle ()
  (cond
    ((not pp:*runpaddle*)
     (princ "\nPOOLPERIM: pp:*runpaddle* is nil - stopping before PADDLE."))
    (c:PADDLE
     (princ (strcat "\nPOOLPERIM: handing the perimeter to PADDLE - press"
                    " Enter at its selection prompt to take the one loop"
                    " now left."))
     (c:PADDLE))
    (t
     (princ (strcat "\nPOOLPERIM: PADDLE is not loaded, so no pads were"
                    " placed.  APPLOAD PADDLE.lsp (or the shared"
                    " LAZPASS.lsp build) and type PADDLE."))))
  (princ))

;;; -------------------- the commands ------------------------------------

(defun c:POOLPERIM ( / *error* olderr undo-open ss res vts kill
                       locked en ask)

  ;; The user's settings come back FIRST so nothing below can skip them,
  ;; then the undo group is closed - or the next U would swallow the
  ;; user's own work along with this run - and any layer this command
  ;; unlocked is locked again.
  (setq olderr *error*)
  (defun *error* (m)
    (pp:sysrestore)
    (if locked (pp:relock locked))
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nPOOLPERIM error: " m)))
    (princ))

  (pp:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (princ (strcat "\nPOOLPERIM " *poolperim-version*))

  (princ "\nSelect the geometry to trace the perimeter from (Enter = the whole drawing): ")
  (setq ss   (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE")))
        res  (pp:analyze ss)
        vts  (nth 0 res)
        kill (nth 2 res))
  (pp:report res)

  ;; no perimeter, no question: without one there is no telling what in
  ;; the drawing was the pool, so nothing is erased
  (if vts
    (progn
      (setq ask (strcat "Erase the " (itoa (length kill)) " object"
                        (pp:s (length kill)) " POOLPERIM did not keep?"))
      (if (not (pp:askyn ask "No" nil))
        (princ "\nPOOLPERIM: nothing erased - the drawing is as you left it.")
        (progn
          (setvar "CMDECHO" 0)
          (setvar "OSMODE" 0)
          (command "_.UNDO" "_Begin")
          (setq undo-open t)
          ;; entdel refuses an entity on a locked layer, so open the ones
          ;; this erase has to reach and shut them again afterwards
          (setq locked (pp:unlock (pp:kill-layers kill)))
          (foreach en kill (if (entget en) (entdel en)))
          (setvar "CLAYER" (pp:ensure-layer pp:*poollayer* pp:*poolcolor*))
          (pp:draw-perim vts pp:*poollayer*)
          (pp:relock locked)
          (setq locked nil)
          (command "_.UNDO" "_End")
          (setq undo-open nil)
          (princ (strcat "\nPOOLPERIM: " (itoa (length kill)) " object"
                         (pp:s (length kill)) " erased; the perimeter is"
                         " one closed polyline on layer "
                         pp:*poollayer* "."))
          ;; the sysvars go back BEFORE PADDLE runs: it is a command in its
          ;; own right and must start from the user's settings, not this
          ;; one's zeroed OSMODE
          (pp:sysrestore)
          (pp:paddle)))))

  (pp:sysrestore)
  (setq *error* olderr)
  (princ))

(defun c:POOLPERIMSCAN ( / *error* olderr ss)
  (setq olderr *error*)
  (defun *error* (m)
    (setq *error* olderr)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nPOOLPERIMSCAN error: " m)))
    (princ))
  (princ (strcat "\nPOOLPERIMSCAN " *poolperim-version*
                 " - reading only, nothing in the drawing is changed."))
  (princ "\nSelect the geometry to trace the perimeter from (Enter = the whole drawing): ")
  (setq ss (ssget '((0 . "LINE,ARC,LWPOLYLINE,POLYLINE"))))
  (pp:report (pp:analyze ss))
  (princ "\nPOOLPERIMSCAN: nothing changed.  Type POOLPERIM to do it.")
  (setq *error* olderr)
  (princ))

(defun c:POOLPERIMVER ()
  (princ (strcat "\nPOOLPERIM " *poolperim-version*))
  (princ))

(princ (strcat "\nPOOLPERIM " *poolperim-version*
               " loaded -- trace the perimeter onto \"" pp:*poollayer*
               "\", erase the rest, run PADDLE."
               "\nPOOLPERIMSCAN reports what it would do and changes"
               " nothing."))
(princ)
