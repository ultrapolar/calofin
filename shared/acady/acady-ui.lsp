;;; acady-ui.lsp
;;; DCL driver for the match-results dialog.
;;; DCL is modal, so Highlight/Zoom use a hide/re-show loop: the button closes
;;; the dialog with a code, the driver acts in the editor, waits for Enter,
;;; then re-opens the dialog with the previous selection restored.

(setq *acady-tmp-ents* nil)   ; temp feature markers (enames)
(setq *acady-hl-on* nil)      ; entities currently redraw-highlighted

;; ---------------------------------------------------------------- cleanup

(defun acady-ui-cleanup ()
  (foreach en *acady-hl-on*
    (if (entget en) (redraw en 4)))
  (setq *acady-hl-on* nil)
  (foreach en *acady-tmp-ents*
    (if (entget en) (entdel en)))
  (setq *acady-tmp-ents* nil))

;; ---------------------------------------------------------------- highlight

(defun acady-mark-point (pt / r)
  ;; temp marker: view-scaled circle, color override, current layer
  (setq r (* 0.02 (getvar "VIEWSIZE")))
  (if (entmake (list '(0 . "CIRCLE")
                     (cons 10 (list (car pt) (cadr pt) 0.0))
                     (cons 40 r)
                     (cons 62 (acady-cfg "HL-COLOR"))))
    (setq *acady-tmp-ents* (cons (entlast) *acady-tmp-ents*))))

(defun acady-mark-matching-arcs (radii / objs obj en on co i n b sweep rad p tol)
  ;; drop a marker on every arc (entity or polyline segment) in the last
  ;; selection whose radius pairs with a matched radius
  (setq tol (acady-cfg "TOL-RAD"))
  (foreach obj *acady-last-objs*
    (setq on (vlax-get obj 'ObjectName))
    (cond
      ((= on "AcDbArc")
       (setq rad (vlax-get obj 'Radius))
       (if (vl-some '(lambda (mr) (acady-fuzzeq rad mr tol)) radii)
         (acady-mark-point
           (vlax-curve-getPointAtDist obj
             (/ (vlax-curve-getDistAtParam obj (vlax-curve-getEndParam obj)) 2.0)))))
      ((= on "AcDbPolyline")
       (setq co (vlax-get obj 'Coordinates)
             n (/ (length co) 2)
             i 0)
       (while (< i n)
         (setq b (vlax-invoke obj 'GetBulge i))
         (if (>= (abs b) *acady-eps-ang*)
           (progn
             (setq sweep (* 4.0 (atan b)))
             (setq p (acady-catch 'vlax-curve-getPointAtParam (list obj (+ i 0.5))))
             (if p
               (progn
                 (setq rad (/ (distance (vlax-curve-getPointAtParam obj i)
                                        (vlax-curve-getPointAtParam obj (1+ i)))
                              (* 2.0 (abs (sin (/ sweep 2.0))))))
                 (if (vl-some '(lambda (mr) (acady-fuzzeq rad mr tol)) radii)
                   (acady-mark-point p))))))
         (setq i (1+ i)))))))

(defun acady-ui-highlight (res / en)
  (foreach obj *acady-last-objs*
    (setq en (vlax-vla-object->ename obj))
    (redraw en 3)
    (setq *acady-hl-on* (cons en *acady-hl-on*)))
  (if (acady-aget "MRADII" res)
    (acady-mark-matching-arcs (acady-aget "MRADII" res)))
  (princ (strcat "\n" (acady-aget "LABEL" res) " " (acady-aget "NAME" res)
                 " — matching geometry highlighted."))
  (getstring "\nPress Enter to return to results...")
  (acady-ui-cleanup))

;; ---------------------------------------------------------------- zoom

(defun acady-ui-zoom (/ ll ur allll allur obj p1 p2 d)
  (setq allll nil allur nil)
  (foreach obj *acady-last-objs*
    (acady-catch 'vla-GetBoundingBox (list obj 'll 'ur))
    (if (null *acady-last-err*) ; these vla calls return nil even on success
      (progn
        (setq p1 (vlax-safearray->list ll) p2 (vlax-safearray->list ur))
        (setq allll (if allll (mapcar 'min allll p1) p1)
              allur (if allur (mapcar 'max allur p2) p2)))))
  (if (and allll allur)
    (progn
      ;; inflate 10%
      (setq d (mapcar '(lambda (a b) (* 0.1 (max (- b a) 1.0))) allll allur))
      (setq allll (mapcar '- allll d) allur (mapcar '+ allur d))
      (acady-catch 'vla-ZoomWindow
                   (list (vlax-get-acad-object)
                         (vlax-3d-point allll) (vlax-3d-point allur)))
      (if *acady-last-err* ; ZoomWindow returns nil on success too
        (command "._ZOOM" "_W" allll allur))
      (getstring "\nPress Enter to return to results..."))))

;; ---------------------------------------------------------------- dialog

(defun acady-ui-fill (results sel / i r)
  (start_list "matches")
  (foreach r results (add_list (acady-result-line r)))
  (end_list)
  (set_tile "matches" (itoa sel))
  (acady-ui-details (nth sel results)))

(defun acady-ui-details (res / rows)
  (if res
    (progn
      (set_tile "d_name" (strcat (acady-aget "LABEL" res) "  "
                                 (acady-aget "NAME" res) "  "
                                 (acady-fmt-pct (acady-aget "SCORE" res))))
      (set_tile "d_src"
        (strcat "tier " (itoa (acady-aget "TIER" res))
                (if (acady-aget "WARNS" res)
                  (strcat "   warnings: "
                          (acady-str-join (acady-aget "WARNS" res) "; "))
                  "")))
      (start_list "features")
      (setq rows (acady-aget "DETAILS" res))
      (if rows
        (foreach s rows (add_list s))
        (add_list (acady-aget "SUMMARY" res)))
      (end_list))))

(defun acady-ui-show (results csig / dcl dclfile sel code res done olderr)
  (setq olderr *error*)
  (setq *error*
    (lambda (msg)
      (acady-ui-cleanup)
      (if dcl (unload_dialog dcl))
      (setq *error* olderr)
      (if (and msg (/= msg "Function cancelled")) (princ (strcat "\nError: " msg)))
      (princ)))
  (setq dclfile (strcat *acady-dir* "\\acady.dcl"))
  (setq dcl (load_dialog dclfile))
  (if (< dcl 0)
    (progn
      (acady-log (strcat "could not load dialog " dclfile " — console results:"))
      (foreach r results (acady-log (strcat "  " (acady-result-line r)))))
    (progn
      (setq sel 0 done nil)
      (while (not done)
        (if (not (new_dialog "acady_match" dcl))
          (setq done t code 0)
          (progn
            (acady-ui-fill results sel)
            (action_tile "matches"
              "(setq sel (atoi $value)) (acady-ui-details (nth sel results))")
            (action_tile "highlight" "(done_dialog 2)")
            (action_tile "zoom"      "(done_dialog 3)")
            (action_tile "rescan"    "(done_dialog 4)")
            (setq code (start_dialog))
            (setq res (nth sel results))
            (cond
              ((= code 2) (if res (acady-ui-highlight res)))
              ((= code 3) (acady-ui-zoom))
              ((= code 4)
               (acady-log "rescanning standards...")
               (setq results (acady-match-run csig (acady-scan-standards t)))
               (setq sel 0)
               (if (null results)
                 (progn (acady-log "no standard matches this shape.")
                        (setq done t))))
              (t (setq done t))))))
      (unload_dialog dcl)))
  (acady-ui-cleanup)
  (setq *error* olderr)
  (princ))

(princ "\n[acady] ui loaded.")
(princ)
