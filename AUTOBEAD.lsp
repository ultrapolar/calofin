;;; ==========================================================================
;;; AUTOBEAD.lsp
;;; --------------------------------------------------------------------------
;;; Command:  AUTOBEAD
;;;
;;; Prompts the user to select POOL lines to "bead", then to click the side to
;;; bead toward.  For every selected line a companion line is created at a 2"
;;; offset toward the clicked side.  The bead lines are placed on the
;;; BEADTRACK layer.  Where adjacent bead offsets overshoot and cross one
;;; another (e.g. at corners), the excess stubs are trimmed back to the
;;; intersection point.
;;; ==========================================================================

;; ---- small vector helpers -------------------------------------------------

(defun autobead-unit (v / d)
  ;; Return the 2D unit vector of v (Z = 0), or nil if v is zero length.
  (setq d (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v)))))
  (if (> d 1e-9)
    (list (/ (car v) d) (/ (cadr v) d) 0.0)
    nil))

(defun autobead-dot (a b)
  ;; 2D dot product.
  (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

(defun autobead-flat (p)
  ;; Force a point onto the Z = 0 plane.
  (list (car p) (cadr p) 0.0))

;; ---- layer -----------------------------------------------------------------

(defun autobead-ensure-layer (name)
  ;; Create the target layer if it does not already exist.
  (if (not (tblsearch "LAYER" name))
    (entmake (list '(0 . "LAYER")
                   '(100 . "AcDbSymbolTableRecord")
                   '(100 . "AcDbLayerTableRecord")
                   (cons 2 name)
                   (cons 70 0)
                   (cons 62 1)               ; color: red
                   (cons 6 "Continuous")))))

;; ---- trimming --------------------------------------------------------------

(defun autobead-nearend (bead x)
  ;; Return the index (0 or 1) of the bead endpoint nearest to point x.
  (if (< (distance (car bead) x) (distance (cadr bead) x)) 0 1))

(defun autobead-addupd (updates bi ei np orig / found res)
  ;; Record that endpoint ei of bead bi should move to np.
  ;; If a move for that same endpoint already exists, keep whichever new point
  ;; trims the least (i.e. is closest to the original endpoint 'orig').
  (setq res '() found nil)
  (foreach u updates
    (if (and (= (car u) bi) (= (cadr u) ei))
      (progn
        (setq found T)
        (if (< (distance np orig) (distance (caddr u) orig))
          (setq res (cons (list bi ei np orig) res))
          (setq res (cons u res))))
      (setq res (cons u res))))
  (if (not found)
    (setq res (cons (list bi ei np orig) res)))
  (reverse res))

(defun autobead-trim (beads / n i j bi bj x nei nej updates res k b)
  ;; Trim overshooting stubs where beads cross one another.  Intersections are
  ;; computed against the original offset geometry, then all trims are applied.
  (setq n (length beads) updates '() i 0)
  (while (< i n)
    (setq j (1+ i))
    (while (< j n)
      (setq bi (nth i beads)
            bj (nth j beads)
            ;; intersection, must lie on both segments (onseg = T)
            x  (inters (car bi) (cadr bi) (car bj) (cadr bj) T))
      (if x
        (progn
          (setq x   (autobead-flat x)
                nei (autobead-nearend bi x)
                nej (autobead-nearend bj x))
          (setq updates (autobead-addupd updates i nei x
                          (if (= nei 0) (car bi) (cadr bi))))
          (setq updates (autobead-addupd updates j nej x
                          (if (= nej 0) (car bj) (cadr bj))))))
      (setq j (1+ j)))
    (setq i (1+ i)))
  ;; apply the collected trims
  (setq res '() k 0)
  (foreach b beads
    (setq b (list (car b) (cadr b)))
    (foreach u updates
      (if (= (car u) k)
        (if (= (cadr u) 0)
          (setq b (list (caddr u) (cadr b)))
          (setq b (list (car b) (caddr u))))))
    (setq res (cons b res) k (1+ k)))
  (reverse res))

;; ---- command ---------------------------------------------------------------

(defun c:AUTOBEAD ( / beadoff layname ss dirpt beads i ent edata
                      p1 p2 dir nrm side unit np1 np2 b )
  (setq beadoff 2.0            ; bead offset distance (drawing units / inches)
        layname "BEADTRACK")

  (autobead-ensure-layer layname)

  ;; 1) select the pool lines to bead
  (prompt "\nSelect POOL lines to bead: ")
  (setq ss (ssget '((0 . "LINE"))))

  (cond
    ((null ss)
     (prompt "\nNo lines selected."))

    ;; 2) pick the side to bead toward
    ((null (setq dirpt (getpoint "\nClick the side to bead toward: ")))
     (prompt "\nNo direction point picked."))

    (T
     (setq dirpt (autobead-flat dirpt)
           beads '()
           i 0)

     ;; 3) build an offset bead line for each selected line
     (while (< i (sslength ss))
       (setq ent   (ssname ss i)
             edata (entget ent)
             p1    (autobead-flat (cdr (assoc 10 edata)))
             p2    (autobead-flat (cdr (assoc 11 edata)))
             dir   (autobead-unit (mapcar '- p2 p1)))
       (if dir
         (progn
           ;; left-hand normal of the line
           (setq nrm (list (- (cadr dir)) (car dir) 0.0))
           ;; flip it if the clicked side is on the other hand
           (setq side (autobead-dot (mapcar '- dirpt p1) nrm))
           (if (< side 0.0)
             (setq nrm (mapcar '- nrm)))
           (setq unit (mapcar '(lambda (c) (* c beadoff)) nrm)
                 np1  (mapcar '+ p1 unit)
                 np2  (mapcar '+ p2 unit)
                 beads (cons (list np1 np2) beads))))
       (setq i (1+ i)))
     (setq beads (reverse beads))

     ;; 4) trim excess where beads intersect one another
     (setq beads (autobead-trim beads))

     ;; 5) draw the finished beads on BEADTRACK
     (foreach b beads
       (entmake (list '(0 . "LINE")
                      (cons 8 layname)
                      (cons 10 (car b))
                      (cons 11 (cadr b)))))
     (prompt (strcat "\nCreated " (itoa (length beads))
                     " bead line(s) on " layname "."))))
  (princ))

(princ "\nAUTOBEAD loaded.  Type AUTOBEAD to run.")
(princ)
